function New-CDriveAgentEvent {
    param([string]$Type, [string]$TurnId, $Data)

    if ($Type -notmatch '^agent\.[a-z]+(?:\.[a-z]+)*$') { throw '[AGENT_EVENT_TYPE] Invalid event type.' }
    if ($TurnId -notmatch '^[a-f0-9]{32}$') { throw '[AGENT_EVENT_TURN] Invalid turn ID.' }
    return [PSCustomObject][ordered]@{
        schemaVersion = 1
        type = $Type
        turnId = $TurnId
        occurredAt = [DateTimeOffset]::UtcNow.ToString('o')
        data = $Data
    }
}

function Write-CDriveAgentEvent {
    param([string]$Path, [string]$Type, [string]$TurnId, $Data)

    $event = New-CDriveAgentEvent $Type $TurnId $Data
    $line = ($event | ConvertTo-Json -Depth 20 -Compress) + "`r`n"
    [System.IO.File]::AppendAllText([System.IO.Path]::GetFullPath($Path), $line, [System.Text.UTF8Encoding]::new($false))
}

function Test-CDriveAgentTextSafe {
    param([string]$Text)

    if ($Text.Length -gt 8000) { return $false }
    if ($Text -match '(?i)sk-[a-z0-9_-]{12,}|authorization\s*:\s*bearer|api[_ -]?key\s*[:=]') { return $false }
    if ($Text -match '(?i)[a-z]:\\|\\\\|/users/|/home/|powershell|cmd\.exe|remove-item|ignore\s+(?:all\s+)?(?:previous|rules)|忽略.{0,8}规则|替代.{0,8}确认') { return $false }
    foreach ($privateValue in @([string]$env:USERNAME, [string]$env:COMPUTERNAME)) {
        if ($privateValue.Length -ge 3 -and $Text.IndexOf($privateValue, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $false }
    }
    return $true
}

function Assert-CDriveAgentTurn {
    param($Turn)

    if ($null -eq $Turn -or [int]$Turn.schemaVersion -ne 1 -or [string]$Turn.turnId -notmatch '^[a-f0-9]{32}$') { throw '[AGENT_TURN_SCHEMA] Invalid turn.' }
    if (@($Turn.messages).Count -eq 0 -or @($Turn.messages).Count -gt 64) { throw '[AGENT_TURN_MESSAGES] Invalid message count.' }
    foreach ($message in @($Turn.messages)) {
        if ([string]$message.role -notin @('system', 'user', 'assistant', 'tool')) { throw '[AGENT_TURN_ROLE] Invalid message role.' }
        if (-not (Test-CDriveAgentTextSafe ([string]$message.content))) { throw '[AGENT_TURN_TEXT] Message is unsafe or too long.' }
        if ([string]$message.role -eq 'tool' -and [string]$message.callId -notmatch '^[a-zA-Z0-9_-]{1,128}$') { throw '[AGENT_TURN_CALL_ID] Tool output is missing a valid call ID.' }
        $priorCalls = if ($null -ne $message.PSObject.Properties['toolCalls']) { @($message.toolCalls | Where-Object { $null -ne $_ }) } else { @() }
        foreach ($call in $priorCalls) {
            if ([string]$call.callId -notmatch '^[a-zA-Z0-9_-]{1,128}$' -or [string]$call.name -notmatch '^[a-z][a-z0-9_]{1,63}$') { throw '[AGENT_TURN_TOOL_CALL] Invalid prior tool call.' }
            if ([string]$call.argumentsJson -notmatch '^\s*\{') { throw '[AGENT_TURN_TOOL_ARGUMENTS] Prior tool arguments must be JSON objects.' }
        }
    }
    return $true
}
