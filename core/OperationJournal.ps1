function Write-CDriveJournalLine {
    param($Journal, [string]$Type, [System.Collections.IDictionary]$Data)

    if ($null -eq $Journal -or -not $Journal.Path) { return }
    $entry = [ordered]@{
        schemaVersion = 1
        timestampUtc = [DateTimeOffset]::UtcNow.ToString('o')
        operationId = [string]$Journal.OperationId
        type = $Type
        data = $Data
    }
    $line = ($entry | ConvertTo-Json -Depth 6 -Compress) + [Environment]::NewLine
    [System.IO.File]::AppendAllText([string]$Journal.Path, $line, (New-Object System.Text.UTF8Encoding($false)))
}

function New-CDriveOperationJournal {
    param(
        [string]$Root,
        [string]$OperationId,
        [string]$ManifestHash,
        [string[]]$SelectedIds,
        [bool]$IsElevated
    )

    if ($OperationId -notmatch '^[a-fA-F0-9]{32}$') { throw 'Invalid operation journal ID.' }
    if ($ManifestHash -notmatch '^[a-f0-9]{64}$') { throw 'Invalid operation journal manifest hash.' }
    if ([string]::IsNullOrWhiteSpace($Root)) {
        $base = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { $env:TEMP }
        $Root = Join-Path $base 'CDriveCleaner\journals'
    }
    New-Item -ItemType Directory -Path $Root -Force | Out-Null

    $cutoff = (Get-Date).AddDays(-30)
    $existing = @(Get-ChildItem -LiteralPath $Root -Filter 'operation-*.ndjson' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    foreach ($old in @($existing | Where-Object { $_.LastWriteTime -lt $cutoff } | Select-Object -Skip 0)) {
        try { Remove-Item -LiteralPath $old.FullName -Force -ErrorAction Stop } catch {}
    }
    foreach ($overflow in @($existing | Where-Object { $_.LastWriteTime -ge $cutoff } | Select-Object -Skip 99)) {
        try { Remove-Item -LiteralPath $overflow.FullName -Force -ErrorAction Stop } catch {}
    }

    $journal = [PSCustomObject]@{
        Path = Join-Path $Root ('operation-{0}-{1}.ndjson' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $OperationId)
        OperationId = $OperationId
    }
    Write-CDriveJournalLine $journal 'operation.planned' ([ordered]@{
        manifestHash = $ManifestHash
        selectedIds = @($SelectedIds | Sort-Object -Unique)
        elevated = $IsElevated
        recoveryPolicy = 'user-content-to-recycle-bin'
    })
    return $journal
}

function Write-CDriveJournalItemStarted {
    param($Journal, [string]$ItemId, [string]$ExecutionMode)
    Write-CDriveJournalLine $Journal 'item.started' ([ordered]@{ itemId = $ItemId; executionMode = $ExecutionMode })
}

function Write-CDriveJournalItemCompleted {
    param(
        $Journal,
        [string]$ItemId,
        [ValidateSet('completed', 'skipped', 'failed')][string]$Status,
        [double]$Freed = 0,
        [double]$StagedForRecovery = 0,
        [int]$Failed = 0,
        [string]$Code = ''
    )
    Write-CDriveJournalLine $Journal 'item.completed' ([ordered]@{
        itemId = $ItemId
        status = $Status
        freed = $Freed
        stagedForRecovery = $StagedForRecovery
        failed = $Failed
        code = $Code
    })
}

function Write-CDriveJournalOperationCompleted {
    param($Journal, [string]$Status, [double]$Freed = 0, [double]$StagedForRecovery = 0, [int]$Failed = 0, [string]$Code = '')
    Write-CDriveJournalLine $Journal 'operation.completed' ([ordered]@{
        status = $Status
        freed = $Freed
        stagedForRecovery = $StagedForRecovery
        failed = $Failed
        code = $Code
    })
}
