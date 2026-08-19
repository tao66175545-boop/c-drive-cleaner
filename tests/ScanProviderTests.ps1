$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot 'core\ScanProvider.ps1')

$testRoot = Join-Path $env:TEMP ('cdc-scan-provider-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
try {
    $payload = New-Object byte[] 128
    for ($directoryIndex = 0; $directoryIndex -lt 60; $directoryIndex++) {
        $directory = Join-Path $testRoot ('d{0:D3}\nested' -f $directoryIndex)
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        for ($fileIndex = 0; $fileIndex -lt 60; $fileIndex++) {
            [System.IO.File]::WriteAllBytes((Join-Path $directory ('f{0:D3}.bin' -f $fileIndex)), $payload)
        }
    }

    # Exclude one-time module/JIT and cold-cache cost: the architecture target is a warm repeat scan.
    $null = Measure-CDrivePathSize $testRoot Fast
    $null = Measure-CDrivePathSize $testRoot Legacy

    $legacyRuns = New-Object System.Collections.Generic.List[double]
    $fastRuns = New-Object System.Collections.Generic.List[double]
    $legacy = $null
    $fast = $null
    for ($run = 0; $run -lt 5; $run++) {
        if (($run % 2) -eq 0) {
            $legacy = Measure-CDrivePathSize $testRoot Legacy
            $fast = Measure-CDrivePathSize $testRoot Fast
        } else {
            $fast = Measure-CDrivePathSize $testRoot Fast
            $legacy = Measure-CDrivePathSize $testRoot Legacy
        }
        $legacyRuns.Add([double]$legacy.ElapsedTicks)
        $fastRuns.Add([double]$fast.ElapsedTicks)
    }
    if ($legacy.Size -ne $fast.Size) { throw "Scan providers disagree: legacy=$($legacy.Size), fast=$($fast.Size)" }
    $legacyTicks = @($legacyRuns | Sort-Object)[[int][Math]::Floor($legacyRuns.Count / 2)]
    $fastTicks = @($fastRuns | Sort-Object)[[int][Math]::Floor($fastRuns.Count / 2)]
    $legacyMs = $legacyTicks * 1000.0 / [System.Diagnostics.Stopwatch]::Frequency
    $fastMs = $fastTicks * 1000.0 / [System.Diagnostics.Stopwatch]::Frequency
    $speedup = $legacyTicks / [Math]::Max(1.0, $fastTicks)
    if ($fast.Provider -eq 'Fast' -and $speedup -lt 3) {
        throw ('Fast scan provider did not reach the 3x warm-repeat benchmark: {0:F2}x (legacy={1:F1}ms fast={2:F1}ms)' -f $speedup, $legacyMs, $fastMs)
    }
    Write-Output ('[OK] scan provider parity/speed -> {0:F2}x warm median (legacy={1:F1}ms fast={2:F1}ms)' -f $speedup, $legacyMs, $fastMs)

    $oldPreference = $env:CDRIVE_SCAN_PROVIDER
    try {
        $env:CDRIVE_SCAN_PROVIDER = 'legacy'
        $fallback = Measure-CDrivePathSize $testRoot Auto
        if ($fallback.Provider -ne 'Legacy' -or $fallback.Size -ne $legacy.Size) { throw 'Legacy fallback is not correct.' }
    } finally {
        $env:CDRIVE_SCAN_PROVIDER = $oldPreference
    }
    Write-Output '[OK] scan provider fallback -> explicit legacy path'

    $capability = Get-CDriveIncrementalCapability
    Write-Output ("[OK] incremental capability probe -> supported=$($capability.Supported), reason=$($capability.Reason)")
} finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
