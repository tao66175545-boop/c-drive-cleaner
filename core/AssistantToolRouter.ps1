function Get-CDriveAssistantToolContract {
    param([string]$ContractPath)
    if (-not (Test-Path -LiteralPath $ContractPath -PathType Leaf)) { throw 'Assistant tool contract is missing.' }
    $contract = Get-Content -LiteralPath $ContractPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$contract.schemaVersion -notin @(1, 2)) { throw 'Unsupported assistant tool contract.' }
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

function New-CDriveAssistantControlCommand {
    param(
        [bool]$Matched,
        [string]$Action = '',
        [string]$ToolName = '',
        $Arguments = $null,
        [string]$Code = ''
    )

    if ($null -eq $Arguments) { $Arguments = [PSCustomObject]@{} }
    return [PSCustomObject]@{
        Matched = $Matched
        Action = $Action
        ToolName = $ToolName
        Arguments = $Arguments
        Code = $Code
    }
}

function Resolve-CDriveAssistantControlCommand {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return New-CDriveAssistantControlCommand $false }
    $value = $Text.Trim()

    if ($value -match '(?i)[a-z]:\\|\\\\|/users/|/home/|powershell|cmd\.exe|wscript|cscript|remove-item|del(?:ete)?\s+(?:path|file)|忽略.{0,8}(?:规则|限制)|绕过.{0,8}(?:规则|确认)|替(?:我|用户).{0,8}(?:确认|同意)|代替.{0,8}(?:确认|同意)') {
        return New-CDriveAssistantControlCommand $true 'denied' '' $null 'UNSAFE_CONTROL_REQUEST'
    }

    if ($value -match '(?i)(?:不(?:要|用|必|需要|想|再)?|别|禁止|拒绝|don''t|do\s+not|never)\s*.{0,8}(?:扫描|清理|删除|打开|切换|勾选|选择|启动|scan|clean|delete|open|select|start)') {
        return New-CDriveAssistantControlCommand $true 'no-op' '' $null 'NEGATED_CONTROL_REQUEST'
    }

    if ($value -match '(?i)(?:取消|停止|终止|stop|cancel).{0,6}(?:扫描|scan)|(?:扫描|scan).{0,6}(?:取消|停止|终止|stop|cancel)') {
        return New-CDriveAssistantControlCommand $true 'tool' 'cancel_scan'
    }
    if ($value -match '(?i)(?:清空|取消|移除|重置|clear|reset).{0,6}(?:勾选|选择|已选|selection)|(?:勾选|选择).{0,6}(?:清空|取消|重置|clear|reset)') {
        return New-CDriveAssistantControlCommand $true 'tool' 'clear_selection'
    }
    if ($value -match '(?i)(?:打开|进入|切换到?|查看|显示|go\s+to|open|show).{0,8}(?:概览|主页|首页|总览|overview|dashboard)') {
        return New-CDriveAssistantControlCommand $true 'tool' 'navigate_view' ([PSCustomObject]@{ view = 'overview' })
    }
    if ($value -match '(?i)(?:打开|进入|切换到?|查看|显示|go\s+to|open|show).{0,8}(?:清理清单|清理列表|可清理项|选择页|selection|cleanup\s+list)') {
        return New-CDriveAssistantControlCommand $true 'tool' 'navigate_view' ([PSCustomObject]@{ view = 'selection' })
    }
    if ($value -match '(?i)(?:打开|进入|切换到?|查看|显示|go\s+to|open|show).{0,8}(?:运行日志|日志|logs?)') {
        return New-CDriveAssistantControlCommand $true 'tool' 'navigate_view' ([PSCustomObject]@{ view = 'logs' })
    }
    if ($value -match '(?i)(?:打开|进入|切换到?|查看|显示|go\s+to|open|show).{0,8}(?:智能助手|助手页|assistant|chat)') {
        return New-CDriveAssistantControlCommand $true 'tool' 'navigate_view' ([PSCustomObject]@{ view = 'assistant' })
    }
    if ($value -match '(?i)(?:开始|启动|执行|重新|帮我|请|run|start|scan).{0,8}(?:完整|全面|深度|诊断|full).{0,6}(?:扫描|scan)|(?:完整|全面|深度|诊断|full).{0,6}(?:扫描|scan)') {
        return New-CDriveAssistantControlCommand $true 'tool' 'start_scan' ([PSCustomObject]@{ scope = 'full-diagnostic' })
    }
    if ($value -match '(?i)(?:开始|启动|执行|重新|帮我|请|run|start|scan).{0,8}(?:用户目录|个人目录|用户文件|user\s*profile).{0,6}(?:扫描|scan)|(?:用户目录|个人目录|用户文件|user\s*profile).{0,6}(?:扫描|scan)') {
        return New-CDriveAssistantControlCommand $true 'tool' 'start_scan' ([PSCustomObject]@{ scope = 'user-profile' })
    }
    if ($value -match '(?i)(?:开始|启动|执行|重新|帮我|请|现在|立即|run|start).{0,10}(?:扫描|检测|scan)|^(?:扫描|检测)(?:一下)?(?:C盘|磁盘|缓存)?[。.!！?？\s]*$|^scan(?:\s+(?:drive|cache|recommended))?[。.!！?？\s]*$') {
        return New-CDriveAssistantControlCommand $true 'tool' 'start_scan' ([PSCustomObject]@{ scope = 'recommended' })
    }
    if ($value -match '(?i)(?:勾选|选中|只选|选择|应用).{0,10}(?:建议项|推荐项|低风险|安全项|recommended|low.risk)|(?:建议项|推荐项|低风险|安全项).{0,8}(?:勾选|选中|选择|应用)') {
        return New-CDriveAssistantControlCommand $true 'select-recommended'
    }
    if ($value -match '(?i)(?:帮我|请|开始|执行|立即|现在).{0,10}(?:清理|释放空间)|(?:清理|释放).{0,10}(?:C盘|磁盘|缓存|低风险|建议项)|clean.{0,10}(?:drive|cache|recommended)') {
        return New-CDriveAssistantControlCommand $true 'prepare-cleanup'
    }
    if ($value -match '(?i)(?:打开|查看|显示|open|show).{0,8}(?:最新)?(?:清理)?报告|(?:清理)?报告.{0,6}(?:打开|查看|显示)') {
        return New-CDriveAssistantControlCommand $true 'tool' 'open_latest_report'
    }
    if ($value -match '(?i)(?:查看|显示|对比|比较|compare|show).{0,10}(?:清理前后|前后效果|空间变化|cleanup\s+results?)|(?:清理前后|前后效果).{0,8}(?:对比|比较|查看|显示)') {
        return New-CDriveAssistantControlCommand $true 'tool' 'compare_cleanup_results'
    }
    if ($value -match '(?i)(?:打开|进入|open).{0,8}(?:临时文件|temporary.files).{0,6}(?:设置|settings)?') {
        return New-CDriveAssistantControlCommand $true 'tool' 'open_system_settings' ([PSCustomObject]@{ settingId = 'temporary-files' })
    }
    if ($value -match '(?i)(?:打开|进入|open).{0,8}(?:应用|程序|apps?).{0,6}(?:设置|settings)') {
        return New-CDriveAssistantControlCommand $true 'tool' 'open_system_settings' ([PSCustomObject]@{ settingId = 'apps' })
    }
    if ($value -match '(?i)(?:打开|进入|open).{0,8}(?:存储|磁盘|storage).{0,6}(?:设置|settings)') {
        return New-CDriveAssistantControlCommand $true 'tool' 'open_system_settings' ([PSCustomObject]@{ settingId = 'storage' })
    }
    if ($value -match '(?i)^(?:当前|现在)?(?:程序|应用|扫描|清理)?(?:状态|情况)(?:怎么样|如何)?[。.!！?？\s]*$|^(?:show|get|what(?:''s|\s+is))\s+(?:the\s+)?(?:app\s+)?state[。.!！?？\s]*$') {
        return New-CDriveAssistantControlCommand $true 'tool' 'get_app_state'
    }
    if ($value -match '(?i)^(?:帮助|指令|命令|你能做什么|怎么控制|如何控制|help|commands?|what\s+can\s+you\s+do)[。.!！?？\s]*$') {
        return New-CDriveAssistantControlCommand $true 'help'
    }

    return New-CDriveAssistantControlCommand $false
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
