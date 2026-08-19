[CmdletBinding()]
param([switch]$FullValidation)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$statePath = Join-Path $projectRoot 'architecture-loop.json'
if (-not (Test-Path -LiteralPath $statePath)) { throw 'Missing architecture-loop.json.' }
$state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($state.schemaVersion -ne 1) { throw "Unsupported architecture loop schema: $($state.schemaVersion)" }
$phase = @($state.phases | Where-Object id -eq $state.currentPhase) | Select-Object -First 1
if (-not $phase) { throw "Current architecture phase is missing: $($state.currentPhase)" }

$checks = New-Object System.Collections.Generic.List[object]
function Add-LoopCheck([string]$Name, [bool]$Passed, [string]$Evidence) {
    $checks.Add([PSCustomObject]@{ Name = $Name; Passed = $Passed; Evidence = $Evidence })
}

try {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot 'tests\ArchitectureContractTests.ps1') | Out-Host
    Add-LoopCheck 'architecture_contracts' ($LASTEXITCODE -eq 0) 'tests/ArchitectureContractTests.ps1'
} catch {
    Add-LoopCheck 'architecture_contracts' $false $_.Exception.Message
}

if ([string]$phase.id -eq 'P1-process') {
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot 'tests\ProcessContractTests.ps1') | Out-Host
        Add-LoopCheck 'process_contracts' ($LASTEXITCODE -eq 0) 'tests/ProcessContractTests.ps1'
    } catch {
        Add-LoopCheck 'process_contracts' $false $_.Exception.Message
    }
}

if ([string]$phase.id -eq 'P2-scan-providers') {
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot 'tests\ScanProviderTests.ps1') | Out-Host
        Add-LoopCheck 'scan_provider_contracts' ($LASTEXITCODE -eq 0) 'tests/ScanProviderTests.ps1'
    } catch {
        Add-LoopCheck 'scan_provider_contracts' $false $_.Exception.Message
    }
}

if ([string]$phase.id -eq 'P3-execution-broker') {
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot 'tests\ExecutionBrokerTests.ps1') | Out-Host
        Add-LoopCheck 'execution_broker_contracts' ($LASTEXITCODE -eq 0) 'tests/ExecutionBrokerTests.ps1'
    } catch {
        Add-LoopCheck 'execution_broker_contracts' $false $_.Exception.Message
    }
}

if ([string]$phase.id -eq 'P4-readonly-copilot') {
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot 'tests\CopilotTests.ps1') | Out-Host
        Add-LoopCheck 'readonly_copilot_contracts' ($LASTEXITCODE -eq 0) 'tests/CopilotTests.ps1'
    } catch {
        Add-LoopCheck 'readonly_copilot_contracts' $false $_.Exception.Message
    }
}

if ([string]$phase.id -eq 'P5-constrained-agent') {
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot 'tests\AssistantToolTests.ps1') | Out-Host
        Add-LoopCheck 'constrained_agent_contracts' ($LASTEXITCODE -eq 0) 'tests/AssistantToolTests.ps1'
    } catch {
        Add-LoopCheck 'constrained_agent_contracts' $false $_.Exception.Message
    }
}

if ([string]$phase.id -eq 'P6-shell-migration') {
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot 'tests\MigrationDecisionTests.ps1') | Out-Host
        Add-LoopCheck 'shell_migration_decision' ($LASTEXITCODE -eq 0) 'tests/MigrationDecisionTests.ps1'
    } catch {
        Add-LoopCheck 'shell_migration_decision' $false $_.Exception.Message
    }
}

if ([string]$phase.id -eq 'P7-incremental-scan') {
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot 'tests\IncrementalScanTests.ps1') | Out-Host
        Add-LoopCheck 'incremental_scan_contracts' ($LASTEXITCODE -eq 0) 'tests/IncrementalScanTests.ps1'
    } catch {
        Add-LoopCheck 'incremental_scan_contracts' $false $_.Exception.Message
    }
}

if ($FullValidation) {
    try {
        $result = & (Join-Path $PSScriptRoot 'Invoke-ProjectValidation.ps1')
        Add-LoopCheck 'legacy_validation_suite' ([string]$result.Status -eq 'Passed') "version=$($result.Version)"
    } catch {
        Add-LoopCheck 'legacy_validation_suite' $false $_.Exception.Message
    }
}

$failed = @($checks | Where-Object { -not $_.Passed })
$allCompleted = @($state.phases | Where-Object { [string]$_.status -ne 'completed' }).Count -eq 0
[PSCustomObject]@{
    Objective = [string]$state.objective
    Phase = [string]$phase.id
    Iteration = [int]$state.iteration
    Gate = $(if ($failed.Count -eq 0) { 'Passed' } else { 'Failed' })
    ObjectiveStatus = $(if ($failed.Count -eq 0 -and $allCompleted) { 'Completed' } else { 'InProgress' })
    Checks = $checks.ToArray()
    NextAction = $(if ($failed.Count -gt 0) { 'Repair the failed checks in the current phase; do not advance.' } elseif ($allCompleted) { 'Architecture objective achieved; prepare a validated release candidate.' } else { 'Measure exit criteria and advance the phase deliberately.' })
}

if ($failed.Count -gt 0) { exit 1 }
