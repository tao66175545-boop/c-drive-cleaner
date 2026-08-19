function Get-CDriveAssistantToolContract {
    param([string]$ContractPath)
    if (-not (Test-Path -LiteralPath $ContractPath -PathType Leaf)) { throw 'Assistant tool contract is missing.' }
    $contract = Get-Content -LiteralPath $ContractPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$contract.schemaVersion -ne 1) { throw 'Unsupported assistant tool contract.' }
    return $contract
}

function Test-CDriveAssistantArgumentsSafe {
    param($Arguments)
    if ($null -eq $Arguments) { return $true }
    $json = $Arguments | ConvertTo-Json -Depth 8 -Compress
    if ($json -match '(?i)[a-z]:\\|\\\\|/users/|/home/|powershell|cmd\.exe|wscript|cscript|remove-item|del(?:ete)?\s') { return $false }
    if ($json -match '(?i)"(?:path|command|shell|script|approval|approved)"\s*:') { return $false }
    return $true
}

function Assert-CDriveStableIds {
    param([object[]]$Ids)
    foreach ($id in @($Ids)) {
        if ([string]$id -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') { throw "[ASSISTANT_ITEM_ID] Invalid stable item ID: $id" }
    }
}

function Invoke-CDriveAssistantTool {
    param(
        [string]$ToolName,
        $Arguments,
        $Context,
        [string]$ContractPath
    )

    $contract = Get-CDriveAssistantToolContract $ContractPath
    $allowed = @($contract.tools | ForEach-Object name)
    if ($allowed -notcontains $ToolName) { throw "[ASSISTANT_TOOL_DENIED] Tool is not allowlisted: $ToolName" }
    if (-not (Test-CDriveAssistantArgumentsSafe $Arguments)) { throw '[ASSISTANT_ARGUMENT_DENIED] Arguments contain a path, command, or approval capability.' }

    switch ($ToolName) {
        'get_scan_summary' {
            return ConvertTo-CDriveCopilotSummary $Context.ScanPayload
        }
        'explain_item' {
            Assert-CDriveStableIds @([string]$Arguments.itemId)
            return Get-CDriveCopilotItemExplanation ([string]$Arguments.itemId) @($Context.Targets)
        }
        'propose_selection' {
            $summary = ConvertTo-CDriveCopilotSummary $Context.ScanPayload
            return Get-CDriveCopilotProposal $summary ([string]$Arguments.goal) ([string]$Arguments.riskLevel)
        }
        'set_selection' {
            $ids = @($Arguments.itemIds)
            Assert-CDriveStableIds $ids
            $known = @{}
            foreach ($item in @($Context.ScanPayload.Items)) { $known[[string]$item.Id] = $true }
            $unknown = @($ids | Where-Object { -not $known.ContainsKey([string]$_) })
            if ($unknown.Count -gt 0) { throw ('[ASSISTANT_UNKNOWN_ID] Selection contains an unavailable scan item: ' + ($unknown -join ',')) }
            return [PSCustomObject]@{ schemaVersion = 1; selectedItemIds = @($ids | Sort-Object -Unique); reversibleUiState = $true; cleanupStarted = $false }
        }
        'show_cleanup_confirmation' {
            if ([string]$Arguments.planId -notmatch '^[a-fA-F0-9]{32}$') { throw '[ASSISTANT_PLAN_ID] A validated plan ID is required.' }
            return [PSCustomObject]@{ schemaVersion = 1; planId = [string]$Arguments.planId; action = 'open-ui-confirmation'; cleanupStarted = $false; userApprovalRequired = $true }
        }
        'start_scan' {
            if ([string]$Arguments.scope -notin @('recommended', 'user-profile', 'full-diagnostic')) { throw '[ASSISTANT_SCAN_SCOPE] Unsupported scan scope.' }
            return [PSCustomObject]@{ schemaVersion = 1; action = 'request-ui-scan'; scope = [string]$Arguments.scope; readOnly = $true }
        }
        'open_system_settings' {
            if ([string]$Arguments.settingId -notin @('storage', 'apps', 'temporary-files')) { throw '[ASSISTANT_SETTING_ID] Setting is not allowlisted.' }
            return [PSCustomObject]@{ schemaVersion = 1; action = 'open-allowlisted-setting'; settingId = [string]$Arguments.settingId }
        }
        'compare_cleanup_results' {
            return [PSCustomObject]@{ schemaVersion = 1; beforeFreeBytes = [double]$Context.BeforeFreeBytes; afterFreeBytes = [double]$Context.AfterFreeBytes; deltaBytes = ([double]$Context.AfterFreeBytes - [double]$Context.BeforeFreeBytes); readOnly = $true }
        }
        default { throw '[ASSISTANT_TOOL_DENIED] Tool has no dispatcher implementation.' }
    }
}

function Resolve-CDriveAssistantIntent {
    param([string]$Text, [object[]]$Targets)

    if ([string]::IsNullOrWhiteSpace($Text)) { return [PSCustomObject]@{ Intent = 'help'; Arguments = @{} } }
    if ($Text -match '(?i)[a-z]:\\|\\\\|powershell|cmd\.exe|remove-item|delete\s+path|approve\s+cleanup|ignore\s+(?:all\s+)?(?:previous|rules)|\u5ffd\u7565.{0,8}\u89c4\u5219|\u4ee3\u66ff.{0,8}\u786e\u8ba4') {
        return [PSCustomObject]@{ Intent = 'denied'; Arguments = @{}; Code = 'PROMPT_INJECTION_OR_UNSAFE_REQUEST' }
    }
    foreach ($target in @($Targets)) {
        if ($Text -match [regex]::Escape([string]$target.Id) -or $Text -match [regex]::Escape([string]$target.Name)) {
            return [PSCustomObject]@{ Intent = 'explain_item'; Arguments = @{ itemId = [string]$target.Id } }
        }
    }
    if ($Text -match '(?i)developer|dev|npm|pip|yarn|cache|\u5f00\u53d1|\u7f13\u5b58') { return [PSCustomObject]@{ Intent = 'propose_selection'; Arguments = @{ goal = 'developer-cache'; riskLevel = 'recommended-only' } } }
    if ($Text -match '(?i)space|free|largest|most|recommend|safe|low.risk|\u7a7a\u95f4|\u91ca\u653e|\u63a8\u8350|\u5b89\u5168') { return [PSCustomObject]@{ Intent = 'propose_selection'; Arguments = @{ goal = 'low-risk'; riskLevel = 'recommended-only' } } }
    return [PSCustomObject]@{ Intent = 'get_scan_summary'; Arguments = @{} }
}
