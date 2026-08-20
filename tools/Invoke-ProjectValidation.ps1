[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$versionManifest = Get-Content -LiteralPath (Join-Path $projectRoot 'version.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$temporaryRelease = Join-Path $env:TEMP ('c-drive-cleaner-validation-' + [guid]::NewGuid().ToString('N'))

try {
    $scriptFiles = @(
        Get-Item -LiteralPath (Join-Path $projectRoot 'C-Drive-Cleaner.ps1')
        Get-Item -LiteralPath (Join-Path $projectRoot 'C-Drive-Cleaner-UI.ps1')
        Get-Item -LiteralPath (Join-Path $projectRoot '.ui-smoke-test.ps1')
        Get-ChildItem -LiteralPath (Join-Path $projectRoot 'core') -Filter '*.ps1' -File
        Get-ChildItem -LiteralPath (Join-Path $projectRoot 'tools') -Filter '*.ps1' -File
        Get-ChildItem -LiteralPath (Join-Path $projectRoot 'tests') -Filter '*.ps1' -File
    ) | Sort-Object FullName -Unique

    foreach ($file in $scriptFiles) {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
        if ($errors.Count -gt 0) {
            $messages = ($errors | ForEach-Object Message) -join '; '
            throw "PowerShell parse failed: $($file.Name): $messages"
        }
    }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot 'C-Drive-Cleaner.ps1') -SelfTest
    if ($LASTEXITCODE -ne 0) { throw 'Safety self-test failed.' }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot 'tests\PlanContractTests.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Cleanup plan contract tests failed.' }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot 'tests\ArchitectureContractTests.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Architecture contract tests failed.' }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot 'tests\ProcessContractTests.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Process contract tests failed.' }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot 'tests\ScanProviderTests.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Scan provider tests failed.' }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot 'tests\IncrementalScanTests.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Incremental scan tests failed.' }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot 'tests\ExecutionBrokerTests.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Execution broker tests failed.' }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot 'tests\CopilotTests.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Read-only copilot tests failed.' }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot 'tests\AssistantToolTests.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Constrained assistant tool tests failed.' }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot 'tests\AgentRuntimeTests.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Agent runtime tests failed.' }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot 'tests\FlyAiTravelProviderTests.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'FlyAI travel provider tests failed.' }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot 'tests\MigrationDecisionTests.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Shell migration decision tests failed.' }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot '.ui-smoke-test.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'UI smoke test failed.' }

    $package = & (Join-Path $projectRoot 'tools\New-ReleasePackage.ps1') `
        -Version ([string]$versionManifest.version) `
        -OutputDirectory $temporaryRelease `
        -Repository ([string]$versionManifest.repository)

    foreach ($requiredPath in @($package.PackagePath, $package.ChecksumPath, $package.ManifestPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw "Release dry-run output is missing: $requiredPath"
        }
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($package.PackagePath)
    try {
        if (-not @($archive.Entries | Where-Object { $_.FullName -match '(^|[\\/])version\.json$' }).Count) {
            throw 'Dry-run release package does not contain version.json.'
        }
    } finally {
        $archive.Dispose()
    }

    [PSCustomObject]@{
        Version = [string]$versionManifest.version
        ParsedScripts = $scriptFiles.Count
        PackageSha256 = [string]$package.Sha256
        Status = 'Passed'
    }
} finally {
    if (Test-Path -LiteralPath $temporaryRelease) {
        Remove-Item -LiteralPath $temporaryRelease -Recurse -Force
    }
}
