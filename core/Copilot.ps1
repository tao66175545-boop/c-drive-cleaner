function ConvertTo-CDriveCopilotSummary {
    param($ScanPayload)

    if ($null -eq $ScanPayload -or [int]$ScanPayload.SchemaVersion -ne 2) {
        throw '[COPILOT_SCAN_SCHEMA] A supported scan summary is required.'
    }
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($ScanPayload.Items)) {
        $id = [string]$item.Id
        if ($id -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') { continue }
        $level = [string]$item.RecommendationLevel
        if ($level -notin @('Recommended', 'Review', 'NotRecommended')) { $level = 'Review' }
        $safety = if ([string]$item.SafetyLevel -eq 'UserContent') { 'UserContent' } else { 'Standard' }
        $recovery = if ([string]$item.RecoveryMode -eq 'RecycleBin') { 'RecycleBin' } else { 'Permanent' }
        $items.Add([PSCustomObject][ordered]@{
            itemId = $id
            sizeBytes = [Math]::Max(0, [double]$item.Size)
            recommendationLevel = $level
            safetyLevel = $safety
            recoveryMode = $recovery
        })
    }
    $total = 0.0
    foreach ($item in $items) { $total += [double]$item.sizeBytes }
    return [PSCustomObject][ordered]@{
        schemaVersion = 1
        scanAgeClass = 'fresh'
        itemCount = $items.Count
        totalCandidateBytes = $total
        items = $items.ToArray()
    }
}

function Test-CDriveCopilotPayloadPrivacy {
    param($Payload)

    $json = $Payload | ConvertTo-Json -Depth 10 -Compress
    $forbiddenKeys = 'path|fullName|fileName|userName|userProfile|log|content|advice|note|name'
    if ($json -match ('(?i)"(?:' + $forbiddenKeys + ')"\s*:')) { return $false }
    if ($json -match '(?i)[a-z]:\\|\\\\|/users/|/home/') { return $false }
    return $true
}

function Get-CDriveCopilotItemExplanation {
    param([string]$ItemId, [object[]]$Targets)

    $target = @($Targets | Where-Object { [string]$_.Id -eq $ItemId }) | Select-Object -First 1
    if ($null -eq $target) { throw "[COPILOT_UNKNOWN_ID] Unknown item ID: $ItemId" }
    $recovery = if ([bool]$target.UserContent) {
        'The item is sent to the Windows Recycle Bin and remains recoverable until the bin is emptied.'
    } elseif ([string]$target.Type -in @('Detect', 'SpaceHog')) {
        'This item is diagnostic only and cannot be cleaned by the application.'
    } else {
        'This cache cleanup is permanent; the application or Windows may recreate the data later.'
    }
    return [PSCustomObject][ordered]@{
        schemaVersion = 1
        itemId = [string]$target.Id
        displayName = [string]$target.Name
        whatItIs = if ([string]$target.Type -in @('Detect', 'SpaceHog')) { 'A diagnostic storage finding.' } elseif ([bool]$target.UserContent) { 'User media stored by a messaging application.' } else { 'Application or operating-system cache data.' }
        whyConsiderIt = [string]$target.Advice
        recommendationLevel = [string]$target.RecommendationLevel
        effect = if ([bool]$target.UserContent) { 'The selected media leaves its application folder but does not free disk space until the Recycle Bin is emptied.' } else { 'The selected data is removed from its cataloged cleanup location.' }
        recovery = $recovery
        requiresAdmin = [bool]$target.RequiresAdmin
        finalDecision = 'The user must make the final selection and approve cleanup in the application UI.'
    }
}

function Get-CDriveCopilotProposal {
    param(
        $CopilotSummary,
        [ValidateSet('free-space', 'low-risk', 'developer-cache')][string]$Goal = 'low-risk',
        [ValidateSet('recommended-only', 'include-review')][string]$RiskLevel = 'recommended-only'
    )

    if (-not (Test-CDriveCopilotPayloadPrivacy $CopilotSummary)) { throw '[COPILOT_PRIVACY] Unsafe scan payload.' }
    $eligible = @($CopilotSummary.items | Where-Object {
        $_.recommendationLevel -eq 'Recommended' -or
        ($RiskLevel -eq 'include-review' -and $_.recommendationLevel -eq 'Review')
    })
    if ($Goal -eq 'low-risk') { $eligible = @($eligible | Where-Object safetyLevel -eq 'Standard') }
    if ($Goal -eq 'developer-cache') { $eligible = @($eligible | Where-Object { $_.itemId -match 'npm|pip|yarn|developer|shader|nvidia|chrome|edge|firefox' }) }
    $ordered = @($eligible | Sort-Object @{ Expression = { [double]$_.sizeBytes }; Descending = $true }, itemId)
    $bytes = 0.0
    foreach ($item in $ordered) { $bytes += [double]$item.sizeBytes }
    return [PSCustomObject][ordered]@{
        schemaVersion = 1
        goal = $Goal
        riskLevel = $RiskLevel
        proposedItemIds = @($ordered | ForEach-Object itemId)
        estimatedBytes = $bytes
        advisoryOnly = $true
        requiresUserConfirmation = $true
    }
}

function New-CDriveCloudCopilotPreview {
    param($CopilotSummary, [string]$Question)

    if (-not (Test-CDriveCopilotPayloadPrivacy $CopilotSummary)) { throw '[COPILOT_PRIVACY] Unsafe scan payload.' }
    $safeQuestion = [regex]::Replace([string]$Question, '(?i)(?:[a-z]:\\[^\s]+|\\\\[^\s]+|/users/[^\s]+|/home/[^\s]+)', '[redacted]')
    return [PSCustomObject][ordered]@{
        schemaVersion = 1
        purpose = 'read-only-cleanup-explanation'
        question = $safeQuestion
        scan = $CopilotSummary
        excluded = @('raw-paths', 'user-name', 'logs', 'file-content', 'shell-commands')
        requiresExplicitCloudConsent = $true
    }
}
