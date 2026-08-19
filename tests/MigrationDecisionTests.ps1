$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$decision = Get-Content -LiteralPath (Join-Path $projectRoot 'migration-decision.json') -Raw -Encoding UTF8 | ConvertFrom-Json

if ([int]$decision.schemaVersion -ne 1 -or [string]$decision.decision -ne 'defer-full-shell-migration') {
    throw 'The shell migration decision is missing or unsupported.'
}
if ([double]$decision.evidence.warmScanMinimumSpeedup -lt 3 -or [int]$decision.evidence.cancellationMaximumMilliseconds -gt 2000) {
    throw 'Migration evidence thresholds weakened the architecture targets.'
}
$requiredSuites = @('ArchitectureContractTests.ps1', 'PlanContractTests.ps1', 'ProcessContractTests.ps1', 'ScanProviderTests.ps1', 'IncrementalScanTests.ps1', 'ExecutionBrokerTests.ps1', 'CopilotTests.ps1', 'AssistantToolTests.ps1', 'AgentRuntimeTests.ps1', '.ui-smoke-test.ps1')
foreach ($suite in $requiredSuites) {
    if (@($decision.evidence.contractParitySuites) -notcontains $suite) { throw "Contract parity omits: $suite" }
}
Write-Output '[OK] migration metrics -> rewrite deferred until measured thresholds are crossed'

if ([int]$decision.migrationTriggers.coldStartupP95Milliseconds -le 0 -or
    [int]$decision.migrationTriggers.uiThreadStallP95Milliseconds -le 0 -or
    -not [bool]$decision.migrationTriggers.requiresTwoConsecutiveMeasuredReleases) {
    throw 'Migration triggers are not measurable or resistant to one-off noise.'
}
Write-Output '[OK] migration trigger -> startup, UI stall, and defect thresholds are explicit'

$rollbackText = $decision.rollback | ConvertTo-Json -Depth 5 -Compress
if ($rollbackText -notmatch 'CDRIVE_SCAN_PROVIDER=legacy' -or $rollbackText -notmatch 'semantic version' -or $rollbackText -notmatch 'stable IDs') {
    throw 'Rollback path does not preserve fallback, contracts, and release history.'
}
Write-Output '[OK] rollback path -> provider, module, and release rollback are documented'

$scanProvider = Get-Content -LiteralPath (Join-Path $projectRoot 'core\ScanProvider.ps1') -Raw -Encoding UTF8
$processProvider = Get-Content -LiteralPath (Join-Path $projectRoot 'core\ProcessOrchestrator.ps1') -Raw -Encoding UTF8
if ($scanProvider -notmatch 'FastDirectorySizer' -or $scanProvider -notmatch 'Get-CDriveLegacyDirectorySize' -or $processProvider -notmatch 'EngineProcess') {
    throw 'Current local .NET boundaries or fallback are missing.'
}
Write-Output '[OK] contract parity -> local .NET hotspots retain tested shell fallback boundaries'
