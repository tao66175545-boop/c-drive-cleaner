function Get-CDriveIncrementalRoots {
    param($Target)

    $roots = New-Object System.Collections.Generic.List[string]
    if ([bool]$Target.UserContent) { return $roots.ToArray() }
    switch ([string]$Target.Type) {
        'FolderContents' { if (Test-Path -LiteralPath ([string]$Target.Path) -PathType Container) { $roots.Add([string]$Target.Path) } }
        'Remove' { if (Test-Path -LiteralPath ([string]$Target.Path)) { $roots.Add([string]$Target.Path) } }
        'PatternCache' {
            if (Test-Path -LiteralPath ([string]$Target.Path) -PathType Container) {
                foreach ($profile in @(Get-ChildItem -LiteralPath ([string]$Target.Path) -Directory -Force -ErrorAction SilentlyContinue)) {
                    if ((([int]$profile.Attributes -band 0x400) -ne 0)) { continue }
                    foreach ($relative in @(([string]$Target.SubDirs -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
                        $candidate = Join-Path $profile.FullName $relative
                        if (Test-Path -LiteralPath $candidate -PathType Container) { $roots.Add($candidate) }
                    }
                }
            }
        }
    }
    return $roots.ToArray()
}

$script:CDriveIncrementalMaximumIndexBytes = 64MB
$script:CDriveIncrementalMaximumEntries = 100
$script:CDriveIncrementalMaximumIdsPerItem = 250000
$script:CDriveIncrementalMaximumTotalIds = 1000000

function Get-CDriveIncrementalBoundaryPaths {
    param($Target)

    $boundaries = New-Object System.Collections.Generic.List[string]
    $path = [string]$Target.Path
    if (-not [string]::IsNullOrWhiteSpace($path)) {
        $parent = Split-Path -Parent $path
        if ($parent -and (Test-Path -LiteralPath $parent -PathType Container)) { $boundaries.Add($parent) }
    }
    if ([string]$Target.Type -eq 'PatternCache' -and (Test-Path -LiteralPath $path -PathType Container)) {
        $boundaries.Add($path)
        foreach ($profile in @(Get-ChildItem -LiteralPath $path -Directory -Force -ErrorAction SilentlyContinue)) {
            if ((([int]$profile.Attributes -band 0x400) -ne 0)) { continue }
            $boundaries.Add($profile.FullName)
            foreach ($relative in @(([string]$Target.SubDirs -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
                $current = $profile.FullName
                foreach ($segment in @($relative -split '[\\/]+' | Where-Object { $_ })) {
                    $candidate = Join-Path $current $segment
                    if (-not (Test-Path -LiteralPath $candidate -PathType Container)) { break }
                    $boundaries.Add($candidate)
                    $current = $candidate
                }
            }
        }
    }
    return @($boundaries | Sort-Object -Unique)
}

function Get-CDriveIncrementalPayloadHash {
    param($Payload)

    $canonical = [ordered]@{
        schemaVersion = [int]$Payload.schemaVersion
        manifestHash = [string]$Payload.manifestHash
        volumeSerial = [string]$Payload.volumeSerial
        journalId = [string]$Payload.journalId
        nextUsn = [string]$Payload.nextUsn
        entries = @($Payload.entries | Sort-Object itemId | ForEach-Object {
            [ordered]@{ itemId = [string]$_.itemId; size = [double]$_.size; identities = @($_.identities | ForEach-Object { [string]$_ } | Sort-Object -Unique) }
        })
    }
    $json = $canonical | ConvertTo-Json -Depth 7 -Compress
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return -join @($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($json)) | ForEach-Object { $_.ToString('x2') }) }
    finally { $sha.Dispose() }
}

function Get-CDriveVolumeSerial {
    param([string]$Drive = 'C:')
    try { return [string][CDriveCleaner.NtfsIncrementalReader]::GetVolumeSerial($Drive) }
    catch { return '' }
}

function New-CDriveIncrementalSession {
    param(
        [string]$IndexPath,
        [string]$ManifestHash,
        [string]$Drive = 'C:',
        [scriptblock]$QueryState,
        [scriptblock]$ReadChanges,
        [scriptblock]$GetVolumeSerial
    )

    $session = [PSCustomObject]@{
        Mode = 'Fallback'
        Reason = 'not-initialized'
        IndexPath = $IndexPath
        ManifestHash = $ManifestHash
        Drive = $Drive
        VolumeSerial = ''
        JournalId = ''
        FirstUsn = 0L
        NextUsn = 0L
        Entries = @{}
        DirtyIds = @{}
        ReusedIds = New-Object System.Collections.Generic.List[string]
        UpdatedIds = New-Object System.Collections.Generic.List[string]
        FailureCode = ''
        FailureDetail = ''
    }
    if ($null -eq $GetVolumeSerial) { $GetVolumeSerial = { param($volume) Get-CDriveVolumeSerial $volume } }
    $session.VolumeSerial = [string](& $GetVolumeSerial $Drive)
    if ([string]::IsNullOrWhiteSpace([string]$session.VolumeSerial)) { $session.Reason = 'volume-identity-unavailable'; return $session }
    if ($env:CDRIVE_INCREMENTAL_SCAN -eq 'off') { $session.Reason = 'disabled'; return $session }
    if ([string]::IsNullOrWhiteSpace($IndexPath) -or $ManifestHash -notmatch '^[a-f0-9]{64}$') { $session.Reason = 'invalid-configuration'; return $session }
    if ($null -eq $QueryState) { $QueryState = { param($volume) [CDriveCleaner.NtfsIncrementalReader]::QueryState($volume) } }
    if ($null -eq $ReadChanges) { $ReadChanges = { param($volume, $journal, $start, $stop) [CDriveCleaner.NtfsIncrementalReader]::ReadChanges($volume, [uint64]$journal, [int64]$start, [int64]$stop) } }

    try {
        $state = & $QueryState $Drive
        $session.JournalId = ([uint64]$state.JournalId).ToString()
        $session.FirstUsn = [int64]$state.FirstUsn
        $session.NextUsn = [int64]$state.NextUsn
    } catch {
        $session.Reason = if ($_.Exception.Message -match '(?i)access.*denied') { 'journal-read-denied' } else { 'journal-query-failed' }
        return $session
    }

    if (-not (Test-Path -LiteralPath $IndexPath -PathType Leaf)) {
        $session.Mode = 'Baseline'
        $session.Reason = 'index-missing'
        return $session
    }
    try {
        if ((Get-Item -LiteralPath $IndexPath -Force).Length -gt $script:CDriveIncrementalMaximumIndexBytes) { throw 'size' }
        $payload = Get-Content -LiteralPath $IndexPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([int]$payload.schemaVersion -ne 1) { throw 'schema' }
        if ([string]$payload.manifestHash -ne $ManifestHash) { throw 'manifest' }
        if ([string]$payload.volumeSerial -ne [string]$session.VolumeSerial) { throw 'volume' }
        if ([string]$payload.journalId -ne [string]$session.JournalId) { throw 'journal' }
        $cursor = [int64]$payload.nextUsn
        if ($cursor -lt $session.FirstUsn -or $cursor -gt $session.NextUsn) { throw 'cursor' }
        if ([string]$payload.payloadHash -ne (Get-CDriveIncrementalPayloadHash $payload)) { throw 'hash' }
        $payloadEntries = @($payload.entries)
        if ($payloadEntries.Count -gt $script:CDriveIncrementalMaximumEntries) { throw 'entry-count' }
        $totalIdentityCount = 0
        foreach ($entry in $payloadEntries) {
            if ([string]$entry.itemId -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$' -or [double]$entry.size -lt 0) { throw 'entry' }
            $entryIdentities = @($entry.identities | ForEach-Object { [string]$_ })
            if ($entryIdentities.Count -gt $script:CDriveIncrementalMaximumIdsPerItem) { throw 'item-identity-count' }
            $totalIdentityCount += $entryIdentities.Count
            if ($totalIdentityCount -gt $script:CDriveIncrementalMaximumTotalIds) { throw 'total-identity-count' }
            $session.Entries[[string]$entry.itemId] = [PSCustomObject]@{ Size = [double]$entry.size; Identities = $entryIdentities }
        }
        $identityOwners = @{}
        foreach ($entryPair in $session.Entries.GetEnumerator()) {
            foreach ($identity in @($entryPair.Value.Identities)) {
                if (-not $identityOwners.ContainsKey($identity)) { $identityOwners[$identity] = New-Object System.Collections.Generic.List[string] }
                $identityOwners[$identity].Add([string]$entryPair.Key)
            }
        }
        $changes = @(& $ReadChanges $Drive ([uint64]$session.JournalId) $cursor $session.NextUsn)
        foreach ($change in $changes) {
            foreach ($identity in @(([uint64]$change.FileId).ToString(), ([uint64]$change.ParentFileId).ToString())) {
                if (-not $identityOwners.ContainsKey($identity)) { continue }
                foreach ($owner in @($identityOwners[$identity])) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$owner)) { $session.DirtyIds[[string]$owner] = $true }
                }
            }
        }
        $session.Mode = 'Incremental'
        $session.Reason = if ($changes.Count -eq 0) { 'journal-unchanged' } else { 'journal-delta' }
        return $session
    } catch {
        $session.Mode = 'Baseline'
        $session.Reason = 'index-invalid-or-journal-reset'
        $session.FailureCode = $_.Exception.GetType().Name
        $session.FailureDetail = $_.Exception.Message
        $session.Entries = @{}
        $session.DirtyIds = @{}
        return $session
    }
}

function Get-CDriveIncrementalCachedSize {
    param($Session, [string]$ItemId)

    if ($null -eq $Session -or $Session.Mode -ne 'Incremental') { return $null }
    if ($Session.DirtyIds.ContainsKey($ItemId) -or -not $Session.Entries.ContainsKey($ItemId)) { return $null }
    $Session.ReusedIds.Add($ItemId)
    return [double]$Session.Entries[$ItemId].Size
}

function Update-CDriveIncrementalEntry {
    param(
        $Session,
        $Target,
        [double]$Size,
        [int]$MaximumIdsPerItem = 250000,
        [scriptblock]$GetIdentities,
        [scriptblock]$GetIdentity,
        [int]$MaximumTotalIds = 1000000
    )

    if ($null -eq $Session -or $Session.Mode -eq 'Fallback' -or [bool]$Target.UserContent) { return }
    if ([string]$Target.Type -notin @('FolderContents', 'Remove', 'PatternCache')) { return }
    if ($null -eq $GetIdentities) {
        $GetIdentities = { param($root, $limit) [CDriveCleaner.NtfsIncrementalReader]::GetTreeFileIds($root, $limit) }
    }
    if ($null -eq $GetIdentity) { $GetIdentity = { param($path) [CDriveCleaner.NtfsIncrementalReader]::GetIdentity($path) } }
    try {
        $identities = New-Object System.Collections.Generic.HashSet[string]
        foreach ($root in @(Get-CDriveIncrementalRoots $Target)) {
            foreach ($identity in @(& $GetIdentities $root $MaximumIdsPerItem)) {
                [void]$identities.Add(([uint64]$identity).ToString())
                if ($identities.Count -gt $MaximumIdsPerItem) { throw 'identity-limit' }
            }
        }
        foreach ($boundary in @(Get-CDriveIncrementalBoundaryPaths $Target)) {
            [void]$identities.Add(([uint64](& $GetIdentity $boundary)).ToString())
            if ($identities.Count -gt $MaximumIdsPerItem) { throw 'identity-limit' }
        }
        $existingCount = 0
        foreach ($pair in $Session.Entries.GetEnumerator()) {
            if ([string]$pair.Key -ne [string]$Target.Id) { $existingCount += @($pair.Value.Identities).Count }
        }
        if (($existingCount + $identities.Count) -gt $MaximumTotalIds) { throw 'total-identity-limit' }
        $Session.Entries[[string]$Target.Id] = [PSCustomObject]@{ Size = $Size; Identities = @($identities | Sort-Object) }
        $Session.UpdatedIds.Add([string]$Target.Id)
    } catch {
        $Session.Entries.Remove([string]$Target.Id)
    }
}

function Save-CDriveIncrementalSession {
    param($Session)

    if ($null -eq $Session -or $Session.Mode -eq 'Fallback' -or [string]::IsNullOrWhiteSpace([string]$Session.IndexPath)) { return $false }
    $entries = @($Session.Entries.GetEnumerator() | Sort-Object Key | ForEach-Object {
        [ordered]@{ itemId = [string]$_.Key; size = [double]$_.Value.Size; identities = @($_.Value.Identities) }
    })
    $payload = [ordered]@{
        schemaVersion = 1
        manifestHash = [string]$Session.ManifestHash
        volumeSerial = [string]$Session.VolumeSerial
        journalId = [string]$Session.JournalId
        nextUsn = ([int64]$Session.NextUsn).ToString()
        entries = $entries
    }
    $payload.payloadHash = Get-CDriveIncrementalPayloadHash $payload
    $directory = Split-Path -Parent ([string]$Session.IndexPath)
    if ($directory) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $temporary = [string]$Session.IndexPath + '.tmp-' + [guid]::NewGuid().ToString('N')
    try {
        [System.IO.File]::WriteAllText($temporary, ($payload | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temporary -Destination ([string]$Session.IndexPath) -Force
        return $true
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
}
