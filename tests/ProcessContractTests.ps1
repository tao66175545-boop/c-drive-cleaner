$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot 'core\ProcessOrchestrator.ps1')

$testRoot = Join-Path $env:TEMP ('cdc-process-contract-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
try {
    $echoScript = Join-Path $testRoot 'echo.ps1'
    $echoLog = Join-Path $testRoot 'echo.log'
    [System.IO.File]::WriteAllText($echoScript, "param([string]`$Value)`r`nWrite-Output `$Value`r`n", (New-Object System.Text.UTF8Encoding($false)))
    $chinesePrefix = -join ([char[]]@(0x4E2D, 0x6587, 0x65E5, 0x5FD7, 0xFF1A, 0x626B, 0x63CF, 0x5FAE, 0x4FE1, 0x56FE, 0x7247, 0xFF0C))
    $expected = $chinesePrefix + 'value with spaces and "quotes"'
    $echoProcess = Start-CDriveEngineProcess $echoScript @('-Value', $expected) $testRoot $echoLog
    $echoExit = $echoProcess.Complete()
    if ($echoExit -ne 0) { throw "Typed argument process failed: $echoExit" }
    $actual = (Get-Content -LiteralPath $echoLog -Raw -Encoding UTF8).Trim()
    if ($actual -cne $expected) {
        $difference = 0
        while ($difference -lt [Math]::Min($actual.Length, $expected.Length) -and $actual[$difference] -ceq $expected[$difference]) { $difference++ }
        $expectedCode = if ($difference -lt $expected.Length) { [int]$expected[$difference] } else { -1 }
        $actualCode = if ($difference -lt $actual.Length) { [int]$actual[$difference] } else { -1 }
        throw "Typed argument round-trip failed: expectedLength=$($expected.Length), actualLength=$($actual.Length), index=$difference, expectedCode=$expectedCode, actualCode=$actualCode"
    }
    if ($actual.Contains([char]0xFFFD)) { throw 'UTF-8 process log contains a decoder replacement character.' }
    Write-Output '[OK] typed process arguments and UTF-8 logs -> no interpolation or Chinese mojibake'

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
