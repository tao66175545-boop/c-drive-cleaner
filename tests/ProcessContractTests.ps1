$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot 'core\ProcessOrchestrator.ps1')

$testRoot = Join-Path $env:TEMP ('cdc-process-contract-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
try {
    $echoScript = Join-Path $testRoot 'echo.ps1'
    $echoLog = Join-Path $testRoot 'echo.log'
    [System.IO.File]::WriteAllText($echoScript, "param([string]`$Value)`r`nWrite-Output `$Value`r`n", (New-Object System.Text.UTF8Encoding($false)))
    $expected = 'value with spaces and "quotes"'
    $echoProcess = Start-CDriveEngineProcess $echoScript @('-Value', $expected) $testRoot $echoLog
    $echoExit = $echoProcess.Complete()
    if ($echoExit -ne 0) { throw "Typed argument process failed: $echoExit" }
    $actual = (Get-Content -LiteralPath $echoLog -Raw -Encoding UTF8).Trim()
    if ($actual -ne $expected) { throw "Typed argument round-trip failed: $actual" }
    Write-Output '[OK] typed process arguments -> no command-string interpolation'

    $sleepScript = Join-Path $testRoot 'sleep.ps1'
    $sleepLog = Join-Path $testRoot 'sleep.log'
    [System.IO.File]::WriteAllText($sleepScript, "Start-Sleep -Seconds 30`r`n", (New-Object System.Text.UTF8Encoding($false)))
    $sleepProcess = Start-CDriveEngineProcess $sleepScript @() $testRoot $sleepLog
    Start-Sleep -Milliseconds 200
    $elapsed = $sleepProcess.Cancel(2000)
    if ($elapsed -gt 2000) { throw "Cancellation acknowledgement exceeded 2 seconds: $elapsed ms" }
    Write-Output "[OK] cancellation acknowledgement -> $elapsed ms"
} finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
