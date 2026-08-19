function ConvertTo-CDriveCanonicalJsonObject {
    param([Parameter(Mandatory = $true)][string]$Json)

    try { $value = $Json | ConvertFrom-Json }
    catch { throw '[AGENT_TOOL_ARGUMENTS_JSON] Provider tool arguments are not valid JSON.' }
    if ($null -eq $value -or $value -isnot [PSCustomObject]) {
        throw '[AGENT_TOOL_ARGUMENTS_OBJECT] Provider tool arguments must be a JSON object.'
    }
    return ($value | ConvertTo-Json -Depth 20 -Compress)
}

function Split-CDriveConcatenatedJsonObjects {
    param([Parameter(Mandatory = $true)][string]$Json)

    $fragments = New-Object System.Collections.Generic.List[string]
    $index = 0
    while ($index -lt $Json.Length) {
        while ($index -lt $Json.Length -and [char]::IsWhiteSpace($Json[$index])) { $index++ }
        if ($index -ge $Json.Length) { break }
        if ($Json[$index] -ne '{') { throw '[AGENT_TOOL_ARGUMENTS_JSON] Provider tool arguments contain invalid trailing data.' }

        $start = $index
        $depth = 0
        $inString = $false
        $escaped = $false
        $complete = $false
        while ($index -lt $Json.Length) {
            $character = $Json[$index]
            if ($inString) {
                if ($escaped) { $escaped = $false }
                elseif ($character -eq '\') { $escaped = $true }
                elseif ($character -eq '"') { $inString = $false }
            } else {
                if ($character -eq '"') { $inString = $true }
                elseif ($character -eq '{') {
                    $depth++
                    if ($depth -gt 64) { throw '[AGENT_TOOL_ARGUMENTS_DEPTH] Provider tool arguments exceed the nesting limit.' }
                } elseif ($character -eq '}') {
                    $depth--
                    if ($depth -lt 0) { throw '[AGENT_TOOL_ARGUMENTS_JSON] Provider tool arguments have an unmatched closing brace.' }
                    if ($depth -eq 0) {
                        $index++
                        $fragments.Add($Json.Substring($start, $index - $start))
                        $complete = $true
                        break
                    }
                }
            }
            $index++
        }
        if (-not $complete -or $inString -or $depth -ne 0) {
            throw '[AGENT_TOOL_ARGUMENTS_JSON] Provider tool arguments contain an incomplete JSON object.'
        }
    }
    return $fragments.ToArray()
}

function Normalize-CDriveToolArgumentsJson {
    param([AllowEmptyString()][string]$ArgumentsJson)

    if ([string]::IsNullOrWhiteSpace($ArgumentsJson)) { throw '[AGENT_TOOL_ARGUMENTS_EMPTY] Provider tool arguments are empty.' }
    $candidate = $ArgumentsJson.Trim()
    if ($candidate.Length -gt 32768) { throw '[AGENT_TOOL_ARGUMENTS_SIZE] Provider tool arguments exceed the size limit.' }
    try { return ConvertTo-CDriveCanonicalJsonObject $candidate }
    catch {
        $fragments = @(Split-CDriveConcatenatedJsonObjects $candidate)
        if ($fragments.Count -lt 2) { throw }
        $canonical = @($fragments | ForEach-Object { ConvertTo-CDriveCanonicalJsonObject $_ })
        $meaningful = @($canonical | Where-Object { $_ -ne '{}' } | Select-Object -Unique)
        if ($meaningful.Count -eq 0) { return '{}' }
        if ($meaningful.Count -eq 1 -and @($canonical | Where-Object { $_ -ne '{}' -and $_ -ne $meaningful[0] }).Count -eq 0) {
            return [string]$meaningful[0]
        }
        throw '[AGENT_TOOL_ARGUMENTS_AMBIGUOUS] Provider returned conflicting concatenated tool arguments.'
    }
}

function ConvertTo-CDriveProviderTools {
    param($Contract, [ValidateSet('responses', 'chat-completions')][string]$Protocol)

    $result = New-Object System.Collections.Generic.List[object]
    foreach ($tool in @($Contract.tools)) {
        if ([string]$tool.availability -eq 'offline-only') { continue }
        $definition = [ordered]@{
            name = [string]$tool.name
            description = [string]$tool.description
            parameters = $tool.parameters
        }
        if ($Protocol -eq 'responses') {
            $definition.type = 'function'
            $definition.strict = $true
            $result.Add([PSCustomObject]$definition)
        } else {
            $result.Add([PSCustomObject][ordered]@{ type = 'function'; function = [PSCustomObject]($definition + @{ strict = $true }) })
        }
    }
    return $result.ToArray()
}

function New-CDriveProviderRequest {
    param($Config, $Turn, $Contract)

    if ([int]$Turn.schemaVersion -ne 1 -or [string]$Turn.turnId -notmatch '^[a-f0-9]{32}$') { throw '[AGENT_TURN_SCHEMA] Invalid turn request.' }
    $messages = @($Turn.messages)
    if ($messages.Count -eq 0 -or $messages.Count -gt 64) { throw '[AGENT_TURN_MESSAGES] Message count is invalid.' }
    $tools = if ([string]$Config.protocol -eq 'text-only') { @() } else { @(ConvertTo-CDriveProviderTools $Contract ([string]$Config.protocol)) }
    if ([string]$Config.protocol -eq 'responses') {
        $input = New-Object System.Collections.Generic.List[object]
        foreach ($message in $messages) {
            if ([string]$message.role -eq 'tool') {
                $input.Add([PSCustomObject][ordered]@{ type = 'function_call_output'; call_id = [string]$message.callId; output = [string]$message.content })
            } elseif ([string]$message.role -eq 'assistant' -and $null -ne $message.PSObject.Properties['toolCalls'] -and @($message.toolCalls | Where-Object { $null -ne $_ }).Count -gt 0) {
                foreach ($call in @($message.toolCalls | Where-Object { $null -ne $_ })) {
                    $argumentsJson = Normalize-CDriveToolArgumentsJson ([string]$call.argumentsJson)
                    $input.Add([PSCustomObject][ordered]@{ type = 'function_call'; call_id = [string]$call.callId; name = [string]$call.name; arguments = $argumentsJson })
                }
            } else {
                $input.Add([PSCustomObject][ordered]@{ role = [string]$message.role; content = [string]$message.content })
            }
        }
        return [PSCustomObject][ordered]@{
            model = [string]$Config.model
            input = $input.ToArray()
            tools = $tools
            stream = [bool]$Config.stream
            max_output_tokens = [int]$Config.maxOutputTokens
        }
    }
    $chatMessages = New-Object System.Collections.Generic.List[object]
    foreach ($message in $messages) {
        if ([string]$message.role -eq 'tool') {
            $chatMessages.Add([PSCustomObject][ordered]@{ role = 'tool'; tool_call_id = [string]$message.callId; content = [string]$message.content })
        } elseif ([string]$message.role -eq 'assistant' -and $null -ne $message.PSObject.Properties['toolCalls'] -and @($message.toolCalls | Where-Object { $null -ne $_ }).Count -gt 0) {
            $toolCalls = @($message.toolCalls | Where-Object { $null -ne $_ } | ForEach-Object {
                $argumentsJson = Normalize-CDriveToolArgumentsJson ([string]$_.argumentsJson)
                [PSCustomObject][ordered]@{ id = [string]$_.callId; type = 'function'; function = [PSCustomObject][ordered]@{ name = [string]$_.name; arguments = $argumentsJson } }
            })
            $chatMessages.Add([PSCustomObject][ordered]@{ role = 'assistant'; content = [string]$message.content; tool_calls = $toolCalls })
        } else {
            $chatMessages.Add([PSCustomObject][ordered]@{ role = [string]$message.role; content = [string]$message.content })
        }
    }
    $body = [ordered]@{
        model = [string]$Config.model
        messages = $chatMessages.ToArray()
        stream = [bool]$Config.stream
        max_tokens = [int]$Config.maxOutputTokens
    }
    if ($tools.Count -gt 0) { $body.tools = $tools; $body.tool_choice = 'auto' }
    return [PSCustomObject]$body
}

function Get-CDriveProviderEndpoint {
    param($Config)

    $base = ([string]$Config.baseUrl).TrimEnd('/')
    switch ([string]$Config.protocol) {
        'responses' { return $base + '/responses' }
        default { return $base + '/chat/completions' }
    }
}

function ConvertFrom-CDriveProviderResponse {
    param($Response, [string]$Protocol)

    $text = ''
    $calls = New-Object System.Collections.Generic.List[object]
    if ($Protocol -eq 'responses') {
        if ($Response.output_text) { $text = [string]$Response.output_text }
        foreach ($item in @($Response.output)) {
            if ([string]$item.type -eq 'function_call') {
                $argumentsJson = Normalize-CDriveToolArgumentsJson ([string]$item.arguments)
                $calls.Add([PSCustomObject]@{ callId = [string]$item.call_id; name = [string]$item.name; argumentsJson = $argumentsJson })
            } elseif ([string]$item.type -eq 'message') {
                foreach ($content in @($item.content)) { if ([string]$content.type -eq 'output_text') { $text += [string]$content.text } }
            }
        }
    } else {
        $message = @($Response.choices)[0].message
        $text = [string]$message.content
        foreach ($call in @($message.tool_calls)) {
            $argumentsJson = Normalize-CDriveToolArgumentsJson ([string]$call.function.arguments)
            $calls.Add([PSCustomObject]@{ callId = [string]$call.id; name = [string]$call.function.name; argumentsJson = $argumentsJson })
        }
    }
    return [PSCustomObject]@{ schemaVersion = 1; text = $text; toolCalls = $calls.ToArray(); responseId = [string]$Response.id }
}

function ConvertFrom-CDriveProviderSse {
    param([string[]]$Lines, [string]$Protocol)

    $text = New-Object System.Text.StringBuilder
    $calls = @{}
    foreach ($line in @($Lines)) {
        if ([string]::IsNullOrWhiteSpace($line) -or -not $line.StartsWith('data:')) { continue }
        $payload = $line.Substring(5).Trim()
        if ($payload -eq '[DONE]') { break }
        try { $event = $payload | ConvertFrom-Json } catch { throw '[AGENT_SSE_JSON] Provider returned invalid SSE JSON.' }
        if ($Protocol -eq 'responses') {
            if ([string]$event.type -eq 'response.output_text.delta') { [void]$text.Append([string]$event.delta) }
            if ([string]$event.type -eq 'response.function_call_arguments.delta') {
                $id = [string]$event.item_id
                if (-not $calls.ContainsKey($id)) { $calls[$id] = [ordered]@{ callId = $id; name = ''; argumentsJson = '' } }
                $calls[$id].argumentsJson += [string]$event.delta
            }
            if ([string]$event.type -eq 'response.output_item.done' -and [string]$event.item.type -eq 'function_call') {
                $id = [string]$event.item.id
                $calls[$id] = [ordered]@{ callId = [string]$event.item.call_id; name = [string]$event.item.name; argumentsJson = [string]$event.item.arguments }
            }
        } else {
            $delta = @($event.choices)[0].delta
            if ($delta.content) { [void]$text.Append([string]$delta.content) }
            foreach ($call in @($delta.tool_calls)) {
                if ($null -eq $call -or $null -eq $call.index) { continue }
                $index = [string]$call.index
                if (-not $calls.ContainsKey($index)) { $calls[$index] = [ordered]@{ callId = ''; name = ''; argumentsJson = '' } }
                if ($call.id) { $calls[$index].callId = [string]$call.id }
                if ($call.function.name) { $calls[$index].name += [string]$call.function.name }
                if ($call.function.arguments) { $calls[$index].argumentsJson += [string]$call.function.arguments }
            }
        }
    }
    $completedCalls = @($calls.Values | Where-Object { $_.callId -and $_.name -and $_.argumentsJson } | ForEach-Object {
        $_.argumentsJson = Normalize-CDriveToolArgumentsJson ([string]$_.argumentsJson)
        [PSCustomObject]$_
    })
    return [PSCustomObject]@{ schemaVersion = 1; text = $text.ToString(); toolCalls = $completedCalls; responseId = '' }
}
