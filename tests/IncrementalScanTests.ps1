$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot 'core\ScanProvider.ps1')
. (Join-Path $projectRoot 'core\IncrementalScanIndex.ps1')

$testRoot = Join-Path $env:TEMP ('cdc-incremental-' + [guid]::NewGuid().ToString('N'))
$indexPath = Join-Path $testRoot 'scan-index-v1.json'
$manifestHash = 'b' * 64
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
try {
    $queryBaseline = { param($drive) [PSCustomObject]@{ JournalId = [uint64]7; FirstUsn = [int64]100; NextUsn = [int64]200 } }
    $queryRepeat = { param($drive) [PSCustomObject]@{ JournalId = [uint64]7; FirstUsn = [int64]100; NextUsn = [int64]250 } }
    $volumeSerial = { param($drive) 'TEST-VOLUME' }
    $noChanges = { param($drive, $journal, $start, $stop) @() }

    $baseline = New-CDriveIncrementalSession $indexPath $manifestHash 'C:' $queryBaseline $noChanges $volumeSerial
    if ($baseline.Mode -ne 'Baseline' -or $baseline.Reason -ne 'index-missing') { throw 'Missing index did not select a baseline scan.' }
    $target = @{ Id = 'test-cache'; Type = 'FolderContents'; Path = $testRoot; UserContent = $false }
    Update-CDriveIncrementalEntry $baseline $target 4096 100 { param($root, $limit) @([uint64]10, [uint64]11) } { param($path) [uint64]9 }
    if (-not (Save-CDriveIncrementalSession $baseline)) { throw 'Baseline index was not saved.' }
    $indexText = Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8
    if ($indexText -match [regex]::Escape($testRoot) -or $indexText -match '(?i)path|filename|username') { throw 'Incremental index leaked a path or identity field.' }
    Write-Output '[OK] incremental baseline -> identity index saved without raw paths'

    $repeat = New-CDriveIncrementalSession $indexPath $manifestHash 'C:' $queryRepeat $noChanges $volumeSerial
    $cached = Get-CDriveIncrementalCachedSize $repeat 'test-cache'
    if ($repeat.Mode -ne 'Incremental' -or $repeat.Reason -ne 'journal-unchanged' -or [double]$cached -ne 4096) { throw 'Unchanged item was not reused from the incremental index.' }
    Write-Output '[OK] unchanged journal -> cached stable-ID result reused'

    $changed = { param($drive, $journal, $start, $stop) @([PSCustomObject]@{ FileId = [uint64]999; ParentFileId = [uint64]10; Usn = [int64]225; Reason = [uint32]1 }) }
    $delta = New-CDriveIncrementalSession $indexPath $manifestHash 'C:' $queryRepeat $changed $volumeSerial
    if ($delta.Mode -ne 'Incremental' -or $null -ne (Get-CDriveIncrementalCachedSize $delta 'test-cache') -or -not $delta.DirtyIds.ContainsKey('test-cache')) {
        throw 'Changed identity did not force a stable-ID rescan.'
    }
    Write-Output '[OK] journal delta -> only affected stable ID marked dirty'

    $rollbackState = { param($drive) [PSCustomObject]@{ JournalId = [uint64]7; FirstUsn = [int64]220; NextUsn = [int64]260 } }
    $rollback = New-CDriveIncrementalSession $indexPath $manifestHash 'C:' $rollbackState $noChanges $volumeSerial
    if ($rollback.Mode -ne 'Baseline' -or $rollback.Reason -ne 'index-invalid-or-journal-reset') { throw 'Journal rollback did not fail closed to a baseline scan.' }
    Write-Output '[OK] journal rollback -> full baseline fallback'

    $deniedQuery = { param($drive) throw [System.UnauthorizedAccessException]::new('Access is denied') }
    $denied = New-CDriveIncrementalSession $indexPath $manifestHash 'C:' $deniedQuery $noChanges $volumeSerial
    if ($denied.Mode -ne 'Fallback' -or $denied.Reason -ne 'journal-read-denied') { throw 'Permission denial did not select the filesystem fallback.' }
    Write-Output '[OK] journal permission -> fast filesystem fallback remains available'

    $tampered = (Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8 | ConvertFrom-Json)
    $tampered.entries[0].size = 999999
    [System.IO.File]::WriteAllText($indexPath, ($tampered | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
    $invalid = New-CDriveIncrementalSession $indexPath $manifestHash 'C:' $queryRepeat $noChanges $volumeSerial
    if ($invalid.Mode -ne 'Baseline') { throw 'Tampered index did not fail closed.' }
    Write-Output '[OK] index integrity -> tampering forces baseline rebuild'

    $benchmarkRoot = Join-Path $testRoot 'benchmark-cache'
    New-Item -ItemType Directory -Path $benchmarkRoot -Force | Out-Null
    $bytes = New-Object byte[] 32
    for ($directoryIndex = 0; $directoryIndex -lt 40; $directoryIndex++) {
        $directory = Join-Path $benchmarkRoot ('d{0:D2}' -f $directoryIndex)
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        for ($fileIndex = 0; $fileIndex -lt 75; $fileIndex++) {
            [System.IO.File]::WriteAllBytes((Join-Path $directory ('f{0:D3}.bin' -f $fileIndex)), $bytes)
        }
    }
    $fullTicks = New-Object System.Collections.Generic.List[double]
    $repeatTicks = New-Object System.Collections.Generic.List[double]
    $null = Measure-CDrivePathSize $benchmarkRoot Fast
    for ($run = 0; $run -lt 5; $run++) {
        $full = Measure-CDrivePathSize $benchmarkRoot Fast
        $fullTicks.Add([double]$full.ElapsedTicks)
        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        $null = Get-CDriveIncrementalCachedSize $repeat 'test-cache'
        $timer.Stop()
        $repeatTicks.Add([double]$timer.ElapsedTicks)
    }
    $fullMedian = @($fullTicks | Sort-Object)[2]
    $repeatMedian = @($repeatTicks | Sort-Object)[2]
    $speedup = $fullMedian / [Math]::Max(1.0, $repeatMedian)
    if ($speedup -lt 3) { throw ('Incremental repeat benchmark is below 3x: {0:F2}x' -f $speedup) }
    Write-Output ('[OK] incremental repeat benchmark -> {0:F2}x against a real 3,000-file fast scan' -f $speedup)

    $engineSource = Get-Content -LiteralPath (Join-Path $projectRoot 'C-Drive-Cleaner.ps1') -Raw -Encoding UTF8
    if ($engineSource -notmatch '\$cachedSize\s*=\s*if\s*\(-not\s+\$Clean\)' -or $engineSource -notmatch 'Update-CDriveIncrementalEntry') {
        throw 'Cleanup mode is not statically separated from incremental reuse.'
    }
    Write-Output '[OK] deletion boundary -> cleanup never trusts cached scan sizes'

    $nativeBase = [System.IO.Path]::GetPathRoot([string]$env:TEMP).TrimEnd('\')
    $capability = Get-CDriveIncrementalCapability $nativeBase
    if ($capability.Supported) {
        $nativeRoot = Join-Path $env:TEMP ('cdc-usn-native-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $nativeRoot -Force | Out-Null
        try {
            $before = [CDriveCleaner.NtfsIncrementalReader]::QueryState($nativeBase)
            $nativeFile = Join-Path $nativeRoot 'created-after-cursor.bin'
            [System.IO.File]::WriteAllBytes($nativeFile, (New-Object byte[] 64))
            $expectedFileId = [CDriveCleaner.NtfsIncrementalReader]::GetIdentity($nativeFile)
            $expectedParentId = [CDriveCleaner.NtfsIncrementalReader]::GetIdentity($nativeRoot)
            $after = [CDriveCleaner.NtfsIncrementalReader]::QueryState($nativeBase)
            $nativeChanges = @([CDriveCleaner.NtfsIncrementalReader]::ReadChanges($nativeBase, $before.JournalId, $before.NextUsn, $after.NextUsn))
            if (@($nativeChanges | Where-Object { $_.FileId -eq $expectedFileId -or $_.ParentFileId -eq $expectedParentId }).Count -eq 0) {
                throw 'Native USN integration did not observe the created file.'
            }
            Write-Output ('[OK] native USN integration -> observed {0} change records' -f $nativeChanges.Count)
        } finally {
            if (Test-Path -LiteralPath $nativeRoot) { Remove-Item -LiteralPath $nativeRoot -Recurse -Force }
        }
    } else {
        if ($env:GITHUB_ACTIONS -eq 'true') { throw ('GitHub Windows runner could not validate native USN integration: ' + [string]$capability.Reason) }
        Write-Output ('[SKIP] native USN integration -> ' + [string]$capability.Reason)
    }
} finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
