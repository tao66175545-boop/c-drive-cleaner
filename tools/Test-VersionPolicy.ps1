[CmdletBinding()]
param(
    [string]$BaseCommit = '',
    [string]$Repository = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$versionManifest = Get-Content -LiteralPath (Join-Path $projectRoot 'version.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$policy = Get-Content -LiteralPath (Join-Path $projectRoot 'source-policy.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$localVersion = [string]$versionManifest.version
if ([string]::IsNullOrWhiteSpace($Repository)) { $Repository = [string]$versionManifest.repository }

function Compare-SemVer {
    param([string]$Left, [string]$Right)

    $pattern = '^(?<core>\d+\.\d+\.\d+)(?:-(?<pre>[0-9A-Za-z.-]+))?$'
    $leftMatch = [regex]::Match($Left, $pattern)
    $rightMatch = [regex]::Match($Right, $pattern)
    if (-not $leftMatch.Success -or -not $rightMatch.Success) { throw "Invalid semantic version: $Left / $Right" }
    $coreComparison = ([version]$leftMatch.Groups['core'].Value).CompareTo([version]$rightMatch.Groups['core'].Value)
    if ($coreComparison -ne 0) { return $coreComparison }
    $leftPre = $leftMatch.Groups['pre'].Value
    $rightPre = $rightMatch.Groups['pre'].Value
    if (-not $leftPre -and -not $rightPre) { return 0 }
    if (-not $leftPre) { return 1 }
    if (-not $rightPre) { return -1 }
    return [string]::CompareOrdinal($leftPre, $rightPre)
}

function Test-ProductPath {
    param([string]$Path)
    $normalized = $Path.Replace('\', '/')
    foreach ($productPath in @($policy.productPaths)) {
        $candidate = [string]$productPath
        if ($candidate.EndsWith('/')) {
            if ($normalized.StartsWith($candidate, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        } elseif ($normalized.Equals($candidate, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

if ($localVersion -notmatch '^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$') { throw "Invalid local semantic version: $localVersion" }

if (-not [string]::IsNullOrWhiteSpace($BaseCommit)) {
    $baseVersionJson = [string]::Join("`n", @(& git -C $projectRoot show "$BaseCommit`:version.json" 2>&1))
    if ($LASTEXITCODE -ne 0) { throw "Unable to read version.json from base commit $BaseCommit." }
    $baseVersion = [string](($baseVersionJson | ConvertFrom-Json).version)
    if ((Compare-SemVer $localVersion $baseVersion) -lt 0) {
        throw "Version cannot move backwards: base=$baseVersion, candidate=$localVersion"
    }

    $changedPaths = @(& git -C $projectRoot diff --name-only $BaseCommit HEAD)
    if ($LASTEXITCODE -ne 0) { throw "Unable to compare candidate with base commit $BaseCommit." }
    $productChanges = @($changedPaths | Where-Object { Test-ProductPath $_ })
    if ($productChanges.Count -gt 0 -and (Compare-SemVer $localVersion $baseVersion) -le 0) {
        throw "Product files require a version increment. Changed: $([string]::Join(', ', $productChanges))"
    }

    if ((Compare-SemVer $localVersion $baseVersion) -gt 0) {
        $notesPath = Join-Path $projectRoot "RELEASE_NOTES_v$localVersion.md"
        if (-not (Test-Path -LiteralPath $notesPath -PathType Leaf)) {
            throw "Missing release notes: RELEASE_NOTES_v$localVersion.md"
        }
    }
}

if (Get-Command gh -ErrorAction SilentlyContinue) {
    $releaseJson = & gh release view --repo $Repository --json tagName 2>$null
    if ($LASTEXITCODE -eq 0 -and $releaseJson) {
        $releaseVersion = ([string](($releaseJson | ConvertFrom-Json).tagName)) -replace '^v', ''
        if ((Compare-SemVer $localVersion $releaseVersion) -lt 0) {
            throw "Candidate version $localVersion is older than latest Release $releaseVersion."
        }
    }
}

[PSCustomObject]@{
    Version = $localVersion
    BaseCommit = $BaseCommit
    Status = 'Passed'
}
