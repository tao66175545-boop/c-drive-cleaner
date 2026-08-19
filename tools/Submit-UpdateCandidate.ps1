[CmdletBinding()]
param(
    [string]$Repository = '',
    [string]$Title = '',
    [string]$Body = '',
    [switch]$Bootstrap,
    [switch]$PrepareOnly
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$versionPath = Join-Path $projectRoot 'version.json'
$manifestPath = Join-Path $projectRoot 'source-manifest.json'
$policyPath = Join-Path $projectRoot 'source-policy.json'

function Invoke-GhApi {
    param(
        [Parameter(Mandatory = $true)][string]$Endpoint,
        [ValidateSet('GET', 'POST', 'PATCH')][string]$Method = 'GET',
        $Body = $null,
        [switch]$AllowFailure
    )

    $inputPath = $null
    try {
        $arguments = @('api', $Endpoint, '--method', $Method)
        if ($null -ne $Body) {
            $inputPath = Join-Path $env:TEMP ('cdc-gh-api-' + [guid]::NewGuid().ToString('N') + '.json')
            $json = $Body | ConvertTo-Json -Depth 20 -Compress
            [System.IO.File]::WriteAllText($inputPath, $json, (New-Object System.Text.UTF8Encoding($false)))
            $arguments += @('--input', $inputPath)
        }
        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $output = & gh @arguments 2>&1
            $exitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }
        if ($exitCode -ne 0) {
            if ($AllowFailure) { return $null }
            throw "GitHub API request failed ($Method $Endpoint): $([string]::Join("`n", @($output)))"
        }
        $text = [string]::Join("`n", @($output))
        if ([string]::IsNullOrWhiteSpace($text)) { return $null }
        return $text | ConvertFrom-Json
    } finally {
        if ($inputPath -and (Test-Path -LiteralPath $inputPath)) {
            Remove-Item -LiteralPath $inputPath -Force
        }
    }
}

function Get-GhRawContent {
    param([string]$Endpoint, [switch]$AllowFailure)

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & gh api -H 'Accept: application/vnd.github.raw+json' $Endpoint 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($exitCode -ne 0) {
        if ($AllowFailure) { return $null }
        throw "Unable to read GitHub content: $Endpoint"
    }
    return [string]::Join("`n", @($output))
}

function Compare-SemVer {
    param([string]$Left, [string]$Right)

    $pattern = '^(?<core>\d+\.\d+\.\d+)(?:-(?<pre>[0-9A-Za-z.-]+))?$'
    $leftMatch = [regex]::Match($Left, $pattern)
    $rightMatch = [regex]::Match($Right, $pattern)
    if (-not $leftMatch.Success -or -not $rightMatch.Success) { throw "Invalid semantic version comparison: $Left / $Right" }
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
    param([string]$Path, $Policy)

    foreach ($productPath in @($Policy.productPaths)) {
        $candidate = [string]$productPath
        if ($candidate.EndsWith('/')) {
            if ($Path.StartsWith($candidate, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        } elseif ($Path.Equals($candidate, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'GitHub CLI (gh) is not installed.' }
& gh auth status *> $null
if ($LASTEXITCODE -ne 0) { throw 'GitHub CLI is not logged in. Run: gh auth login' }

$versionManifest = Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8 | ConvertFrom-Json
$policy = Get-Content -LiteralPath $policyPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($Repository)) { $Repository = [string]$versionManifest.repository }
if ($Repository -notmatch '^[^/\s]+/[^/\s]+$') { throw 'Repository must use owner/repository format.' }
$owner = $Repository.Split('/')[0]
$localVersion = [string]$versionManifest.version
if ($localVersion -notmatch '^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$') { throw "Invalid local semantic version: $localVersion" }

$mainRef = Invoke-GhApi "repos/$Repository/git/ref/heads/main"
$mainCommit = [string]$mainRef.object.sha
$mainCommitData = Invoke-GhApi "repos/$Repository/git/commits/$mainCommit"
$mainTree = [string]$mainCommitData.tree.sha
$remoteVersionJson = Get-GhRawContent "repos/$Repository/contents/version.json?ref=main"
$remoteVersion = [string](($remoteVersionJson | ConvertFrom-Json).version)
if ((Compare-SemVer $localVersion $remoteVersion) -lt 0) {
    throw "Local version $localVersion is older than remote main $remoteVersion. Synchronize locally before submitting."
}

$latestRelease = & gh release view --repo $Repository --json tagName 2>$null
$latestReleaseVersion = ''
if ($LASTEXITCODE -eq 0 -and $latestRelease) {
    $latestReleaseVersion = ([string](($latestRelease | ConvertFrom-Json).tagName)) -replace '^v', ''
    if ((Compare-SemVer $localVersion $latestReleaseVersion) -lt 0) {
        throw "Local version $localVersion is older than latest Release $latestReleaseVersion."
    }
}

$remoteManifestJson = Get-GhRawContent "repos/$Repository/contents/source-manifest.json?ref=main" -AllowFailure
$remoteManifest = $null
if ($remoteManifestJson) { $remoteManifest = $remoteManifestJson | ConvertFrom-Json }
if (-not $remoteManifest -and -not $Bootstrap) {
    throw 'Remote source-manifest.json is missing. The first infrastructure PR must use -Bootstrap.'
}

if ($remoteManifest) {
    $remoteTree = Invoke-GhApi "repos/$Repository/git/trees/$mainTree`?recursive=1"
    $treeByPath = @{}
    foreach ($entry in @($remoteTree.tree | Where-Object type -eq 'blob')) { $treeByPath[[string]$entry.path] = [string]$entry.sha }
    foreach ($record in @($remoteManifest.files)) {
        if (-not $treeByPath.ContainsKey([string]$record.path) -or
            $treeByPath[[string]$record.path] -ne [string]$record.gitBlobSha1) {
            throw "Remote main has drifted from its source manifest: $($record.path). Repair or synchronize before submitting."
        }
    }

    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw 'Local source-manifest.json is missing. Synchronize it from remote main before submitting.'
    }
    $localBaseline = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $baselineMatches = [string]$localBaseline.sourceFingerprint -eq [string]$remoteManifest.sourceFingerprint
    $pendingFromCurrentMain = [string]$localBaseline.baseCommit -eq $mainCommit
    if (-not $baselineMatches -and -not $pendingFromCurrentMain) {
        throw 'Local and GitHub baselines differ. Remote main changed after the local candidate was prepared; synchronize before retrying.'
    }
}

$temporaryManifest = Join-Path $env:TEMP ('cdc-source-manifest-' + [guid]::NewGuid().ToString('N') + '.json')
try {
    $manifestResult = & (Join-Path $PSScriptRoot 'Get-SourceManifest.ps1') -OutputPath $temporaryManifest -BaseCommit $mainCommit
    $candidateManifest = Get-Content -LiteralPath $temporaryManifest -Raw -Encoding UTF8 | ConvertFrom-Json

    if ($remoteManifest -and (Compare-SemVer $localVersion $remoteVersion) -eq 0) {
        $remoteByPath = @{}
        foreach ($record in @($remoteManifest.files)) { $remoteByPath[[string]$record.path] = [string]$record.sha256 }
        $changedProductFiles = @(
            $candidateManifest.files | Where-Object {
                (Test-ProductPath ([string]$_.path) $policy) -and
                (-not $remoteByPath.ContainsKey([string]$_.path) -or $remoteByPath[[string]$_.path] -ne [string]$_.sha256)
            }
        )
        if ($changedProductFiles.Count -gt 0) {
            throw "Product files changed without a version increment: $([string]::Join(', ', @($changedProductFiles.path)))"
        }
    }

    if ((Compare-SemVer $localVersion $remoteVersion) -gt 0) {
        $notesPath = Join-Path $projectRoot "RELEASE_NOTES_v$localVersion.md"
        if (-not (Test-Path -LiteralPath $notesPath -PathType Leaf)) {
            throw "Missing release notes for new version: RELEASE_NOTES_v$localVersion.md"
        }
    }

    Write-Host 'Running the same validation suite used by GitHub Actions...'
    $validation = & (Join-Path $PSScriptRoot 'Invoke-ProjectValidation.ps1')
    if ([string]$validation.Status -ne 'Passed') { throw 'Local validation did not complete successfully.' }

    [System.IO.File]::WriteAllText(
        $manifestPath,
        (Get-Content -LiteralPath $temporaryManifest -Raw -Encoding UTF8),
        (New-Object System.Text.UTF8Encoding($false))
    )

    if ($PrepareOnly) {
        [PSCustomObject]@{
            Status = 'Prepared'
            Version = $localVersion
            BaseCommit = $mainCommit
            SourceFingerprint = [string]$manifestResult.SourceFingerprint
            FileCount = [int]$manifestResult.FileCount
            ManifestPath = $manifestPath
        }
        return
    }

    $branch = "candidate/v$localVersion-$($mainCommit.Substring(0, 8))"
    $branchRef = Invoke-GhApi "repos/$Repository/git/ref/heads/$branch" -AllowFailure
    $parentCommit = $mainCommit
    $baseTree = $mainTree
    if ($branchRef) {
        $parentCommit = [string]$branchRef.object.sha
        $candidateCommitData = Invoke-GhApi "repos/$Repository/git/commits/$parentCommit"
        $baseTree = [string]$candidateCommitData.tree.sha
    }

    $treeEntries = New-Object System.Collections.Generic.List[object]
    $candidatePaths = @($candidateManifest.files | ForEach-Object { [string]$_.path }) + 'source-manifest.json'
    foreach ($relativePath in $candidatePaths | Sort-Object -Unique) {
        $fullPath = Join-Path $projectRoot $relativePath.Replace('/', '\')
        $content = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($fullPath))
        $blob = Invoke-GhApi "repos/$Repository/git/blobs" -Method POST -Body @{ content = $content; encoding = 'base64' }
        $treeEntries.Add([ordered]@{ path = $relativePath; mode = '100644'; type = 'blob'; sha = [string]$blob.sha })
    }

    if ($remoteManifest) {
        foreach ($oldPath in @($remoteManifest.files | ForEach-Object { [string]$_.path })) {
            if ($candidatePaths -notcontains $oldPath) {
                $treeEntries.Add([ordered]@{ path = $oldPath; mode = '100644'; type = 'blob'; sha = $null })
            }
        }
    }

    $newTree = Invoke-GhApi "repos/$Repository/git/trees" -Method POST -Body @{ base_tree = $baseTree; tree = $treeEntries.ToArray() }
    $commitMessage = "chore(release): prepare v$localVersion candidate"
    $newCommit = Invoke-GhApi "repos/$Repository/git/commits" -Method POST -Body @{
        message = $commitMessage
        tree = [string]$newTree.sha
        parents = @($parentCommit)
    }

    if ($branchRef) {
        Invoke-GhApi "repos/$Repository/git/refs/heads/$branch" -Method PATCH -Body @{ sha = [string]$newCommit.sha; force = $false } | Out-Null
    } else {
        Invoke-GhApi "repos/$Repository/git/refs" -Method POST -Body @{ ref = "refs/heads/$branch"; sha = [string]$newCommit.sha } | Out-Null
    }

    $openPulls = Invoke-GhApi "repos/$Repository/pulls?state=open&head=$owner`:$branch&base=main"
    $pullRequest = @($openPulls) | Select-Object -First 1
    if (-not $pullRequest) {
        if ([string]::IsNullOrWhiteSpace($Title)) { $Title = "Release candidate: v$localVersion" }
        if ([string]::IsNullOrWhiteSpace($Body)) {
            $Body = @(
                '## Automated update candidate'
                ''
                "- Version: $localVersion"
                "- Base commit: $mainCommit"
                "- Source fingerprint: $($manifestResult.SourceFingerprint)"
                '- Local validation: passed'
                ''
                'Approval is collected in the Codex conversation. After approval, Codex revalidates these exact identifiers, merges this PR, monitors GitHub Actions, and verifies the Release artifacts.'
            ) -join "`n"
        }
        $pullRequest = Invoke-GhApi "repos/$Repository/pulls" -Method POST -Body @{
            title = $Title
            head = $branch
            base = 'main'
            body = $Body
            maintainer_can_modify = $true
        }
    }

    [PSCustomObject]@{
        Status = 'AwaitingApproval'
        Version = $localVersion
        Branch = $branch
        Commit = [string]$newCommit.sha
        SourceFingerprint = [string]$manifestResult.SourceFingerprint
        PullRequestNumber = [int]$pullRequest.number
        PullRequestUrl = [string]$pullRequest.html_url
    }
} finally {
    if (Test-Path -LiteralPath $temporaryManifest) {
        Remove-Item -LiteralPath $temporaryManifest -Force
    }
}
