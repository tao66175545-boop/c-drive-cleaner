[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$')]
    [string]$Version,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [string]$Repository = '',

    [switch]$KeepStage
)

$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$versionFile = Join-Path $repositoryRoot 'version.json'
if (-not (Test-Path -LiteralPath $versionFile)) {
    throw "Missing version manifest: $versionFile"
}

$versionManifest = Get-Content -LiteralPath $versionFile -Raw -Encoding UTF8 | ConvertFrom-Json
if ($versionManifest.version -ne $Version) {
    throw "Version mismatch: version.json is $($versionManifest.version), requested $Version."
}

if ([string]::IsNullOrWhiteSpace($Repository)) {
    $Repository = [string]$versionManifest.repository
}
if ($Repository -notmatch '^[^/\s]+/[^/\s]+$') {
    throw 'Repository must use the owner/repository format.'
}

$packageFiles = @(
    'C-Drive-Cleaner.ps1',
    'C-Drive-Cleaner-UI.ps1',
    'AgentHost.ps1',
    'C盘清理.bat',
    'version.json',
    'README.md',
    'README-使用说明.txt',
    'UI-DESIGN-RULES.md',
    'OTA-在线升级方案.md',
    'ARCHITECTURE.md',
    'AI-AGENT-架构方案.md',
    'agent-roadmap.json',
    'architecture-loop.json',
    'migration-decision.json'
)

$packageDirectories = @('assets', 'contracts', 'core', 'rules')

foreach ($relativePath in $packageFiles + $packageDirectories) {
    $sourcePath = Join-Path $repositoryRoot $relativePath
    if (-not (Test-Path -LiteralPath $sourcePath)) {
        throw "Required release content is missing: $relativePath"
    }
}

$resolvedOutput = [System.IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $resolvedOutput -Force | Out-Null

$stageName = "C盘智能清理-v$Version"
$stagePath = Join-Path $resolvedOutput $stageName
if (Test-Path -LiteralPath $stagePath) {
    Remove-Item -LiteralPath $stagePath -Recurse -Force
}
New-Item -ItemType Directory -Path $stagePath -Force | Out-Null

foreach ($relativePath in $packageFiles) {
    Copy-Item -LiteralPath (Join-Path $repositoryRoot $relativePath) -Destination $stagePath -Force
}
foreach ($relativeDirectory in $packageDirectories) {
    Copy-Item -LiteralPath (Join-Path $repositoryRoot $relativeDirectory) -Destination $stagePath -Recurse -Force
}

# GitHub 会清洗非 ASCII Release 资产名，导致清单 URL 与实际文件名不一致。
$packageName = "C-Drive-Cleaner-v$Version.zip"
if ($packageName -notmatch '^[A-Za-z0-9._-]+$') {
    throw "Release asset name is not GitHub-safe: $packageName"
}
$packagePath = Join-Path $resolvedOutput $packageName
if (Test-Path -LiteralPath $packagePath) {
    Remove-Item -LiteralPath $packagePath -Force
}
Compress-Archive -LiteralPath $stagePath -DestinationPath $packagePath -Force

$hash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash
$checksumPath = Join-Path $resolvedOutput 'SHA256SUMS.txt'
[System.IO.File]::WriteAllText(
    $checksumPath,
    "$hash  $packageName`r`n",
    [System.Text.UTF8Encoding]::new($false)
)

$publishedAt = [DateTime]::UtcNow.ToString('o')
$releaseManifest = [ordered]@{
    schemaVersion = 1
    product = [string]$versionManifest.product
    channel = [string]$versionManifest.channel
    version = $Version
    publishedAt = $publishedAt
    releaseUrl = "https://github.com/$Repository/releases/tag/v$Version"
    package = [ordered]@{
        name = $packageName
        url = "https://github.com/$Repository/releases/download/v$Version/$([uri]::EscapeDataString($packageName))"
        size = (Get-Item -LiteralPath $packagePath).Length
        sha256 = $hash
    }
}
$releaseManifestPath = Join-Path $resolvedOutput 'release.json'
$releaseJson = $releaseManifest | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText(
    $releaseManifestPath,
    $releaseJson,
    [System.Text.UTF8Encoding]::new($false)
)

if (-not $KeepStage -and (Test-Path -LiteralPath $stagePath)) {
    Remove-Item -LiteralPath $stagePath -Recurse -Force
}

[PSCustomObject]@{
    PackagePath = $packagePath
    ChecksumPath = $checksumPath
    ManifestPath = $releaseManifestPath
    Sha256 = $hash
}
