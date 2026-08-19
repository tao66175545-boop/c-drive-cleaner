function Get-CDriveAssistantToolDefinition {
    param($Contract, [string]$ToolName)

    return @($Contract.tools | Where-Object { [string]$_.name -eq $ToolName }) | Select-Object -First 1
}

function Assert-CDriveJsonObjectKeys {
    param($Value, $Schema, [string]$Prefix = 'arguments')

    if ($null -eq $Value) { $Value = [PSCustomObject]@{} }
    $properties = @($Value.PSObject.Properties.Name)
    $allowed = @($Schema.properties.PSObject.Properties.Name)
    foreach ($name in $properties) { if ($allowed -notcontains $name) { throw "[AGENT_TOOL_SCHEMA] Unknown field: $Prefix.$name" } }
    foreach ($required in @($Schema.required)) { if ($properties -notcontains [string]$required) { throw "[AGENT_TOOL_SCHEMA] Missing field: $Prefix.$required" } }
    foreach ($name in $properties) {
        $rule = $Schema.properties.$name
        $current = $Value.$name
        switch ([string]$rule.type) {
            'string' {
                if ($current -isnot [string]) { throw "[AGENT_TOOL_SCHEMA] $Prefix.$name must be a string." }
                if ($rule.pattern -and [string]$current -notmatch [string]$rule.pattern) { throw "[AGENT_TOOL_SCHEMA] $Prefix.$name has an invalid format." }
                if ($rule.enum -and @($rule.enum) -notcontains [string]$current) { throw "[AGENT_TOOL_SCHEMA] $Prefix.$name is not allowlisted." }
            }
            'array' {
                $values = @($current)
                if ($values.Count -gt [int]$rule.maxItems) { throw "[AGENT_TOOL_SCHEMA] $Prefix.$name contains too many items." }
                foreach ($entry in $values) {
                    if ($rule.items.type -eq 'string' -and $entry -isnot [string]) { throw "[AGENT_TOOL_SCHEMA] $Prefix.$name entries must be strings." }
                    if ($rule.items.pattern -and [string]$entry -notmatch [string]$rule.items.pattern) { throw "[AGENT_TOOL_SCHEMA] $Prefix.$name contains an invalid value." }
                }
            }
        }
    }
    return $true
}

function Invoke-CDriveUiActionBroker {
    param(
        [string]$CallId,
        [string]$ToolName,
        $Arguments,
        $Context,
        [string]$ContractPath,
        [hashtable]$Handlers,
        [hashtable]$ReplayCache
    )

    if ($CallId -notmatch '^[a-zA-Z0-9_-]{1,128}$') { throw '[AGENT_CALL_ID] Invalid tool call ID.' }
    if ($ReplayCache.ContainsKey($CallId)) { throw '[AGENT_TOOL_REPLAY] Tool call was already handled.' }
    $contract = Get-Content -LiteralPath $ContractPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$contract.schemaVersion -ne 2) { throw '[AGENT_TOOL_CONTRACT] Unsupported tool contract.' }
    $definition = Get-CDriveAssistantToolDefinition $contract $ToolName
    if ($null -eq $definition) { throw "[AGENT_TOOL_DENIED] Tool is not allowlisted: $ToolName" }
    $null = Assert-CDriveJsonObjectKeys $Arguments $definition.parameters
    if (-not (Test-CDriveAssistantArgumentsSafe $Arguments)) { throw '[ASSISTANT_ARGUMENT_DENIED] Arguments contain a path, command, or approval capability.' }

    $result = switch ($ToolName) {
        'get_app_state' { & $Handlers.get_app_state $Arguments $Context }
        'navigate_view' { & $Handlers.navigate_view $Arguments $Context }
        'start_scan' { & $Handlers.start_scan $Arguments $Context }
        'cancel_scan' { & $Handlers.cancel_scan $Arguments $Context }
        'set_selection' {
            if ($Handlers.ContainsKey('set_selection') -and $Handlers.set_selection -is [scriptblock]) { & $Handlers.set_selection $Arguments $Context }
            else { Invoke-CDriveAssistantTool $ToolName $Arguments $Context $ContractPath }
        }
        'clear_selection' { & $Handlers.clear_selection $Arguments $Context }
        'show_cleanup_confirmation' {
            if ($Handlers.ContainsKey('show_cleanup_confirmation') -and $Handlers.show_cleanup_confirmation -is [scriptblock]) { & $Handlers.show_cleanup_confirmation $Arguments $Context }
            else { Invoke-CDriveAssistantTool $ToolName $Arguments $Context $ContractPath }
        }
        'open_latest_report' { & $Handlers.open_latest_report $Arguments $Context }
        'open_system_settings' {
            if ($Handlers.ContainsKey('open_system_settings') -and $Handlers.open_system_settings -is [scriptblock]) { & $Handlers.open_system_settings $Arguments $Context }
            else { Invoke-CDriveAssistantTool $ToolName $Arguments $Context $ContractPath }
        }
        default { Invoke-CDriveAssistantTool $ToolName $Arguments $Context $ContractPath }
    }
    $ReplayCache[$CallId] = $true
    return $result
}
