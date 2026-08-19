$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot 'core\OperationJournal.ps1')
. (Join-Path $projectRoot 'core\ExecutionBroker.ps1')

$journalRoot = Join-Path $env:TEMP ('cdc-journal-test-' + [guid]::NewGuid().ToString('N'))
$targets = @(
    @{ Id = 'cache-safe'; Type = 'FolderContents'; Path = 'C:\catalog-only'; RequiresAdmin = $false; UserContent = $false },
    @{ Id = 'admin-cache'; Type = 'FolderContents'; Path = 'C:\catalog-admin'; RequiresAdmin = $true; UserContent = $false },
    @{ Id = 'user-media'; Type = 'PatternCache'; Path = 'C:\catalog-media'; SubDirs = 'Image'; RequiresAdmin = $false; UserContent = $true },
    @{ Id = 'recycle-bin'; Type = 'RecycleBin'; Path = ''; RequiresAdmin = $false; UserContent = $false }
)
try {
    try {
        $null = New-CDriveExecutionContext $targets @('unknown-id') $false
        throw 'Unknown stable ID was accepted.'
    } catch {
        if ($_.Exception.Message -notmatch 'BROKER_UNKNOWN_ID') { throw }
    }
    Write-Output '[OK] execution broker -> unknown IDs fail closed'

    try {
        $null = New-CDriveExecutionContext $targets @('user-media', 'recycle-bin') $false
        throw 'Recovery conflict was accepted.'
    } catch {
        if ($_.Exception.Message -notmatch 'BROKER_RECOVERY_CONFLICT') { throw }
    }
    Write-Output '[OK] recovery policy -> user content cannot be purged with recycle bin'

    $journal = New-CDriveOperationJournal $journalRoot ([guid]::NewGuid().ToString('N')) ('a' * 64) @('admin-cache') $false
    $context = New-CDriveExecutionContext $targets @('admin-cache') $false $journal
    $script:handlerCalled = $false
    $handlers = @{ FolderContents = { param($target, $action) $script:handlerCalled = $true; [PSCustomObject]@{ Freed = 1; Failed = 0 } } }
    $result = Invoke-CDriveBrokeredCleanup $context 'admin-cache' $handlers
    if ($result.Status -ne 'skipped' -or $script:handlerCalled) { throw 'Least-privilege broker invoked an admin handler without elevation.' }
    Write-Output '[OK] least privilege -> no automatic elevation and admin item skipped'

    $lines = @(Get-Content -LiteralPath $journal.Path -Encoding UTF8)
    $events = @($lines | ForEach-Object { $_ | ConvertFrom-Json })
    if ($events.Count -lt 3 -or @($events | Where-Object { $_.operationId -ne $journal.OperationId }).Count -gt 0) { throw 'Operation journal correlation is invalid.' }
    if (($lines -join "`n") -match 'catalog-admin|C:\\') { throw 'Operation journal leaked a raw cleanup path.' }
    Write-Output '[OK] operation journal -> durable NDJSON without raw paths'

    $engine = Get-Content -LiteralPath (Join-Path $projectRoot 'C-Drive-Cleaner.ps1') -Raw -Encoding UTF8
    if ($engine -notmatch 'PLAN_REQUIRED') { throw 'Engine does not fail closed when cleanup has no scan plan.' }
    if ($engine -match '(?i)Verb\s*=\s*["'']RunAs') { throw 'Engine contains automatic elevation.' }
    Write-Output '[OK] cleanup entry -> validated selection plan required'
} finally {
    if (Test-Path -LiteralPath $journalRoot) { Remove-Item -LiteralPath $journalRoot -Recurse -Force }
}
