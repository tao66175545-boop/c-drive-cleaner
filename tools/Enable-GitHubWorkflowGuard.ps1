[CmdletBinding()]
param(
    [string]$Repository = '',
    [Parameter(Mandatory = $true)]
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$versionManifest = Get-Content -LiteralPath (Join-Path $projectRoot 'version.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($Repository)) { $Repository = [string]$versionManifest.repository }
if ($Repository -notmatch '^[^/\s]+/[^/\s]+$') { throw 'Repository must use owner/repository format.' }
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'GitHub CLI (gh) is not installed.' }
& gh auth status *> $null
if ($LASTEXITCODE -ne 0) { throw 'GitHub CLI is not logged in. Run: gh auth login' }

$requestPath = Join-Path $env:TEMP ('cdc-branch-protection-' + [guid]::NewGuid().ToString('N') + '.json')
try {
    $protection = [ordered]@{
        required_status_checks = [ordered]@{
            strict = $true
            contexts = @('powershell-validation')
        }
        enforce_admins = $true
        required_pull_request_reviews = [ordered]@{
            dismiss_stale_reviews = $false
            require_code_owner_reviews = $false
            required_approving_review_count = 0
            require_last_push_approval = $false
        }
        restrictions = $null
        required_linear_history = $true
        allow_force_pushes = $false
        allow_deletions = $false
        required_conversation_resolution = $true
        lock_branch = $false
        allow_fork_syncing = $true
    }
    [System.IO.File]::WriteAllText(
        $requestPath,
        ($protection | ConvertTo-Json -Depth 8 -Compress),
        (New-Object System.Text.UTF8Encoding($false))
    )
    & gh api "repos/$Repository/branches/main/protection" --method PUT --input $requestPath | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Unable to enable main branch protection.' }

    [PSCustomObject]@{
        Repository = $Repository
        Branch = 'main'
        RequiredCheck = 'powershell-validation'
        DirectPushBlocked = $true
        Status = 'Enabled'
    }
} finally {
    if (Test-Path -LiteralPath $requestPath) {
        Remove-Item -LiteralPath $requestPath -Force
    }
}
