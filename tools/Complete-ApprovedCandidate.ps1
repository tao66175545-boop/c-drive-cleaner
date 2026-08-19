[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$PullRequest,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{40}$')]
    [string]$ExpectedHeadSha,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$ExpectedFingerprint,

    [Parameter(Mandatory = $true)]
    [switch]$UserApproved,

    [string]$Repository = '',
    [int]$TimeoutMinutes = 30,
    [switch]$PreflightOnly
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$versionManifest = Get-Content -LiteralPath (Join-Path $projectRoot 'version.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($Repository)) { $Repository = [string]$versionManifest.repository }
if ($Repository -notmatch '^[^/\s]+/[^/\s]+$') { throw 'Repository must use owner/repository format.' }
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'GitHub CLI (gh) is not installed.' }
& gh auth status *> $null
if ($LASTEXITCODE -ne 0) { throw 'GitHub CLI is not logged in. Run: gh auth login' }

function Invoke-GhJson {
    param([string[]]$Arguments)

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & gh @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($exitCode -ne 0) { throw "GitHub CLI failed: gh $([string]::Join(' ', $Arguments))`n$([string]::Join("`n", @($output)))" }
    $text = [string]::Join("`n", @($output))
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return $text | ConvertFrom-Json
}

function Get-RawGitHubContent {
    param([string]$Path, [string]$Ref)

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & gh api -H 'Accept: application/vnd.github.raw+json' "repos/$Repository/contents/$Path`?ref=$Ref" 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($exitCode -ne 0) { throw "Unable to read $Path at $Ref from GitHub." }
    return [string]::Join("`n", @($output))
}

function Wait-WorkflowRun {
    param(
        [string]$Workflow,
        [string]$Commit,
        [datetime]$Deadline
    )

    Write-Host "Waiting for $Workflow at $Commit..."
    while ([DateTime]::UtcNow -lt $Deadline) {
        $runs = Invoke-GhJson @(
            'run', 'list', '--repo', $Repository,
            '--workflow', $Workflow,
            '--branch', 'main', '--commit', $Commit,
            '--limit', '10',
            '--json', 'databaseId,status,conclusion,url,headSha,event,createdAt'
        )
        $run = @($runs | Sort-Object createdAt -Descending) | Select-Object -First 1
        if ($run) {
            if ([string]$run.status -eq 'completed') {
                if ([string]$run.conclusion -ne 'success') {
                    throw "$Workflow failed: $($run.url)"
                }
                Write-Host "$Workflow passed: $($run.url)"
                return $run
            }
            Write-Host "$Workflow status: $($run.status)"
        }
        Start-Sleep -Seconds 10
    }
    throw "Timed out waiting for $Workflow at $Commit."
}

$ExpectedHeadSha = $ExpectedHeadSha.ToLowerInvariant()
$ExpectedFingerprint = $ExpectedFingerprint.ToLowerInvariant()
$pr = Invoke-GhJson @(
    'pr', 'view', [string]$PullRequest, '--repo', $Repository,
    '--json', 'number,state,url,title,baseRefName,headRefOid,mergeable,mergeStateStatus,statusCheckRollup'
)
if ([string]$pr.state -ne 'OPEN') { throw "PR #$PullRequest is not open." }
if ([string]$pr.baseRefName -ne 'main') { throw "PR #$PullRequest does not target main." }
if ([string]$pr.headRefOid -ne $ExpectedHeadSha) {
    throw "Approval is stale. Expected head $ExpectedHeadSha, actual $($pr.headRefOid). Request a new Codex approval."
}
if ([string]$pr.mergeable -ne 'MERGEABLE' -or [string]$pr.mergeStateStatus -ne 'CLEAN') {
    throw "PR #$PullRequest is not currently clean and mergeable."
}

$sourceManifest = Get-RawGitHubContent 'source-manifest.json' $ExpectedHeadSha | ConvertFrom-Json
if (([string]$sourceManifest.sourceFingerprint).ToLowerInvariant() -ne $ExpectedFingerprint) {
    throw 'Approval is stale. The PR source fingerprint changed; request a new Codex approval.'
}
$version = [string]$sourceManifest.version
$requiredCheck = @($pr.statusCheckRollup | Where-Object { [string]$_.name -eq 'powershell-validation' }) | Select-Object -First 1
if (-not $requiredCheck -or [string]$requiredCheck.status -ne 'COMPLETED' -or [string]$requiredCheck.conclusion -ne 'SUCCESS') {
    throw 'The required powershell-validation check has not passed.'
}

if ($PreflightOnly) {
    [PSCustomObject]@{
        Status = 'ReadyForConversationApproval'
        PullRequest = $PullRequest
        PullRequestUrl = [string]$pr.url
        Version = $version
        HeadCommit = $ExpectedHeadSha
        SourceFingerprint = $ExpectedFingerprint
        RequiredCheck = 'Passed'
    }
    return
}

$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $releaseBefore = & gh release view "v$version" --repo $Repository --json tagName 2>$null
    $releaseViewExitCode = $LASTEXITCODE
} finally {
    $ErrorActionPreference = $previousErrorActionPreference
}
$versionAlreadyPublished = $releaseViewExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$releaseBefore)
$approvedAt = [DateTime]::UtcNow.ToString('o')
$auditComment = @(
    'Codex conversation approval recorded.'
    ''
    "- Approved candidate: PR #$PullRequest"
    "- Version: $version"
    "- Head commit: $ExpectedHeadSha"
    "- Source fingerprint: $ExpectedFingerprint"
    "- Approval processed at: $approvedAt"
    ''
    'The candidate identifiers were revalidated immediately before merge.'
) -join "`n"
& gh pr comment $PullRequest --repo $Repository --body $auditComment | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Unable to record the approval audit comment.' }

& gh pr merge $PullRequest --repo $Repository --squash --delete-branch --match-head-commit $ExpectedHeadSha
if ($LASTEXITCODE -ne 0) { throw "Unable to merge approved PR #$PullRequest." }

$mergedPr = Invoke-GhJson @(
    'pr', 'view', [string]$PullRequest, '--repo', $Repository,
    '--json', 'state,mergedAt,mergeCommit,url'
)
if ([string]$mergedPr.state -ne 'MERGED' -or -not $mergedPr.mergeCommit.oid) {
    throw "PR #$PullRequest did not reach the MERGED state."
}
$mergeCommit = ([string]$mergedPr.mergeCommit.oid).ToLowerInvariant()
$deadline = [DateTime]::UtcNow.AddMinutes($TimeoutMinutes)
$validateRun = Wait-WorkflowRun 'validate.yml' $mergeCommit $deadline
$releaseRun = Wait-WorkflowRun 'release.yml' $mergeCommit $deadline
$consistencyRun = Wait-WorkflowRun 'consistency.yml' $mergeCommit $deadline

$mainSha = [string]::Join('', @(& gh api "repos/$Repository/git/ref/heads/main" --jq '.object.sha' 2>&1)).Trim().ToLowerInvariant()
if ($LASTEXITCODE -ne 0 -or $mainSha -ne $mergeCommit) {
    throw "Remote main is not the approved merge commit. Expected $mergeCommit, actual $mainSha."
}
$remoteManifest = Get-RawGitHubContent 'source-manifest.json' 'main' | ConvertFrom-Json
if (([string]$remoteManifest.sourceFingerprint).ToLowerInvariant() -ne $ExpectedFingerprint) {
    throw 'Remote main source fingerprint does not match the approved candidate.'
}
if ([string]$remoteManifest.version -ne $version) { throw 'Remote main version does not match the approved candidate.' }

$release = Invoke-GhJson @('release', 'view', "v$version", '--repo', $Repository, '--json', 'url,tagName,targetCommitish,assets')
if (-not $versionAlreadyPublished -and [string]$release.targetCommitish -ne $mergeCommit) {
    throw "New Release v$version does not target the approved merge commit."
}

[PSCustomObject]@{
    Status = 'Completed'
    PullRequest = $PullRequest
    PullRequestUrl = [string]$mergedPr.url
    Version = $version
    MergeCommit = $mergeCommit
    SourceFingerprint = $ExpectedFingerprint
    ReleaseMode = $(if ($versionAlreadyPublished) { 'ExistingVersionVerified' } else { 'NewVersionPublished' })
    ReleaseUrl = [string]$release.url
    ValidateRunUrl = [string]$validateRun.url
    PublishRunUrl = [string]$releaseRun.url
    ConsistencyRunUrl = [string]$consistencyRun.url
}
