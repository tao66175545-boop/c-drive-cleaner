$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot 'core\RuleCatalog.ps1')
. (Join-Path $projectRoot 'core\Copilot.ps1')

$payload = [PSCustomObject]@{
    SchemaVersion = 2
    ScanId = [guid]::NewGuid().ToString('N')
    ManifestHash = ('a' * 64)
    ScannedAt = [DateTimeOffset]::UtcNow.ToString('o')
    Items = @(
        [PSCustomObject]@{ Id = 'user-temp'; Name = 'Private user temp'; Path = 'C:\Users\Alice\AppData\Local\Temp'; Size = 1048576; RecommendationLevel = 'Recommended'; SafetyLevel = 'Standard'; Advice = 'private advice'; Note = 'private log' },
        [PSCustomObject]@{ Id = 'user-wechat-media'; Name = 'Private chat media'; Path = 'C:\Users\Alice\Documents\WeChat Files'; Size = 2097152; RecommendationLevel = 'Review'; SafetyLevel = 'UserContent'; RecoveryMode = 'RecycleBin' }
    )
}

$summary = ConvertTo-CDriveCopilotSummary $payload
if (-not (Test-CDriveCopilotPayloadPrivacy $summary)) { throw 'Copilot summary failed the privacy contract.' }
$summaryJson = $summary | ConvertTo-Json -Depth 6 -Compress
if ($summaryJson -match 'Alice|Private|Users|AppData|WeChat Files|advice|log') { throw 'Copilot summary leaked private source data.' }
Write-Output '[OK] copilot privacy -> field allowlist excludes raw paths and private text'

$targets = @(Get-CDriveCleanupTargets)
$explanation = Get-CDriveCopilotItemExplanation 'user-wechat-media' $targets
foreach ($required in @('whatItIs', 'whyConsiderIt', 'effect', 'recovery', 'recommendationLevel', 'finalDecision')) {
    if ([string]::IsNullOrWhiteSpace([string]$explanation.$required)) { throw "Explanation is missing: $required" }
}
if ($explanation.recovery -notmatch 'Recycle Bin' -or $explanation.finalDecision -notmatch 'user') { throw 'User-content explanation does not describe recovery and final control.' }
Write-Output '[OK] explanation quality -> effect, recovery, risk, and user decision are explicit'

$proposal = Get-CDriveCopilotProposal $summary 'low-risk' 'recommended-only'
if (@($proposal.proposedItemIds).Count -ne 1 -or $proposal.proposedItemIds[0] -ne 'user-temp' -or -not $proposal.advisoryOnly -or -not $proposal.requiresUserConfirmation) {
    throw 'Low-risk proposal crossed the advisory boundary.'
}
Write-Output '[OK] offline copilot -> deterministic low-risk proposal without a model'

$cloud = New-CDriveCloudCopilotPreview $summary 'Please inspect C:\Users\Alice\Secret\file.txt'
$cloudJson = $cloud | ConvertTo-Json -Depth 8 -Compress
if ($cloudJson -match 'Alice|Secret|file.txt' -or -not $cloud.requiresExplicitCloudConsent) { throw 'Cloud preview failed redaction or consent requirements.' }
Write-Output '[OK] cloud preview -> redacted and opt-in only'
