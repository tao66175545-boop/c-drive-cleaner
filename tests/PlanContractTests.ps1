$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$enginePath = Join-Path $projectRoot 'C-Drive-Cleaner.ps1'

$selfTestOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $enginePath -SelfTest 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    throw 'Engine self-test failed before plan contract tests.'
}

$manifestHash = [regex]::Match($selfTestOutput, 'sha256=([a-f0-9]{64})').Groups[1].Value
if (-not $manifestHash) {
    throw 'Target manifest hash was not emitted by the engine self-test.'
}

function Assert-PlanRejected {
    param(
        [string]$Name,
        $Payload,
        [string]$ExpectedCode
    )

    $planPath = Join-Path $env:TEMP ('cdc-plan-test-{0}-{1}.json' -f $Name, [guid]::NewGuid().ToString('N'))
    try {
        [System.IO.File]::WriteAllText(
            $planPath,
            ($Payload | ConvertTo-Json -Depth 5),
            (New-Object System.Text.UTF8Encoding($false))
        )
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $enginePath -SelfTest -SelectionFile $planPath 2>&1 | Out-String
        if ($LASTEXITCODE -ne 1) {
            throw "Plan '$Name' was not rejected."
        }
        if ($output -notmatch [regex]::Escape($ExpectedCode)) {
            throw "Plan '$Name' returned the wrong validation code."
        }
        Write-Output "[OK] $Name -> $ExpectedCode"
    } finally {
        if (Test-Path -LiteralPath $planPath) {
            [System.IO.File]::Delete($planPath)
        }
    }
}

$basePlan = @{
    SchemaVersion = 2
    ScanId = [guid]::NewGuid().ToString('N')
    ManifestHash = $manifestHash
    ScannedAt = [DateTimeOffset]::UtcNow.ToString('o')
    SelectedIds = @('user-temp')
    Items = @(@{ Id = 'user-temp'; Size = 0 })
}

$legacyPlan = $basePlan.Clone()
$legacyPlan.SchemaVersion = 1
Assert-PlanRejected 'legacy-schema' $legacyPlan 'PLAN_SCHEMA'

$wrongManifestPlan = $basePlan.Clone()
$wrongManifestPlan.ManifestHash = ('0' * 64)
Assert-PlanRejected 'wrong-manifest' $wrongManifestPlan 'PLAN_MANIFEST'

$expiredPlan = $basePlan.Clone()
$expiredPlan.ScannedAt = [DateTimeOffset]::UtcNow.AddHours(-1).ToString('o')
Assert-PlanRejected 'expired' $expiredPlan 'PLAN_EXPIRED'

$futurePlan = $basePlan.Clone()
$futurePlan.ScannedAt = [DateTimeOffset]::UtcNow.AddHours(1).ToString('o')
Assert-PlanRejected 'future-clock' $futurePlan 'PLAN_CLOCK'

$missingSnapshotPlan = $basePlan.Clone()
$missingSnapshotPlan.Items = @()
Assert-PlanRejected 'missing-snapshot' $missingSnapshotPlan 'PLAN_SNAPSHOT'

$negativeSnapshotPlan = $basePlan.Clone()
$negativeSnapshotPlan.Items = @(@{ Id = 'user-temp'; Size = -1 })
Assert-PlanRejected 'negative-snapshot' $negativeSnapshotPlan 'PLAN_SNAPSHOT'
