function Get-CDriveFlyAiExecutable {
    $command = Get-Command 'flyai.cmd' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) { $command = Get-Command 'flyai' -ErrorAction SilentlyContinue | Select-Object -First 1 }
    if ($command) {
        $commandDirectory = Split-Path -Parent ([string]$command.Source)
        $bundle = Join-Path $commandDirectory 'node_modules\@fly-ai\flyai-cli\dist\flyai-bundle.cjs'
        if (Test-Path -LiteralPath $bundle -PathType Leaf) { return $bundle }
    }
    return ''
}

function Test-CDriveTravelIntent {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    return $Text -match '(?i)\u65c5\u884c|\u65c5\u6e38|\u51fa\u884c|\u5ea6\u5047|\u884c\u7a0b|\u653b\u7565|\u9152\u5e97|\u4f4f\u5bbf|\u6c11\u5bbf|\u673a\u7968|\u822a\u73ed|\u706b\u8f66|\u9ad8\u94c1|\u666f\u70b9|\u95e8\u7968|\u7b7e\u8bc1|\u90ae\u8f6e|\u79df\u8f66|trip|travel|hotel|flight|train|itinerary|vacation'
}

function ConvertTo-CDriveProcessArgument {
    param([AllowEmptyString()][string]$Value)
    if ($Value -notmatch '[\s"]') { return $Value }
    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.Append('"')
    $backslashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') {
            $backslashes++
            continue
        }
        if ($character -eq '"') {
            [void]$builder.Append(('\' * (($backslashes * 2) + 1)))
            [void]$builder.Append('"')
            $backslashes = 0
            continue
        }
        if ($backslashes -gt 0) {
            [void]$builder.Append(('\' * $backslashes))
            $backslashes = 0
        }
        [void]$builder.Append($character)
    }
    if ($backslashes -gt 0) { [void]$builder.Append(('\' * ($backslashes * 2))) }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Invoke-CDriveFlyAiSearch {
    param(
        [Parameter(Mandatory = $true)][string]$Query,
        [ValidateSet('ai-search', 'keyword-search')][string]$Mode = 'ai-search',
        [int]$TimeoutSeconds = 45,
        [string]$ExecutablePath = ''
    )

    if ([string]::IsNullOrWhiteSpace($Query) -or $Query.Length -gt 500) {
        throw '[FLYAI_QUERY] Travel query must contain 1 to 500 characters.'
    }
    if ([string]::IsNullOrWhiteSpace($ExecutablePath)) { $ExecutablePath = Get-CDriveFlyAiExecutable }
    if ([string]::IsNullOrWhiteSpace($ExecutablePath) -or -not (Test-Path -LiteralPath $ExecutablePath -PathType Leaf)) {
        throw '[FLYAI_NOT_INSTALLED] Official FlyAI CLI was not found.'
    }

    $nodeCommand = Get-Command 'node.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $nodeCommand) { $nodeCommand = Get-Command 'node' -ErrorAction SilentlyContinue | Select-Object -First 1 }
    if (-not $nodeCommand) { throw '[FLYAI_NODE] FlyAI requires Node.js 18 or later.' }

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = [string]$nodeCommand.Source
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $startInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    if ($null -ne $startInfo.ArgumentList) {
        $startInfo.ArgumentList.Add($ExecutablePath)
        $startInfo.ArgumentList.Add($Mode)
        $startInfo.ArgumentList.Add('--query')
        $startInfo.ArgumentList.Add($Query)
    } else {
        $startInfo.Arguments = @(
            (ConvertTo-CDriveProcessArgument $ExecutablePath)
            $Mode
            '--query'
            (ConvertTo-CDriveProcessArgument $Query)
        ) -join ' '
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw '[FLYAI_START] Unable to start FlyAI.' }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit([Math]::Max(1, $TimeoutSeconds) * 1000)) {
            try { $process.Kill() } catch {}
            throw '[FLYAI_TIMEOUT] FlyAI travel search timed out.'
        }
        $stdout = $stdoutTask.GetAwaiter().GetResult().Trim()
        $stderr = $stderrTask.GetAwaiter().GetResult().Trim()
        if ([string]::IsNullOrWhiteSpace($stdout)) { throw '[FLYAI_EMPTY] FlyAI returned no result.' }
        try { $payload = $stdout | ConvertFrom-Json }
        catch { throw '[FLYAI_JSON] FlyAI returned invalid JSON.' }
        $knownNode24ExitAssertion = $stderr -match 'Assertion failed:\s*!\(handle->flags\s*&\s*UV_HANDLE_CLOSING\)'
        if ($process.ExitCode -ne 0 -and -not $knownNode24ExitAssertion) { throw ('[FLYAI_FAILED] ' + $stderr) }
        return [PSCustomObject]@{
            schemaVersion = 1
            provider = 'FlyAI'
            mode = $Mode
            query = $Query
            result = $payload
            readOnly = $true
            bookingExecuted = $false
            runtimeWarning = $(if ($knownNode24ExitAssertion) { 'node24-windows-exit-assertion' } else { '' })
        }
    } finally { $process.Dispose() }
}

function Format-CDriveFlyAiResult {
    param($Response)
    if ($null -eq $Response -or $null -eq $Response.result) { return 'FlyAI did not return a displayable travel result.' }
    $result = $Response.result
    if ($result.PSObject.Properties['data'] -and $result.data -is [string]) {
        return [string]$result.data
    }
    $items = @()
    if ($result.data -and $result.data.PSObject.Properties['itemList']) { $items = @($result.data.itemList) }
    if ($items.Count -eq 0) {
        $compact = $result | ConvertTo-Json -Depth 8 -Compress
        return ('FlyAI real-time result: ' + $compact)
    }
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('FlyAI real-time travel suggestions:')
    $rank = 0
    foreach ($item in @($items | Select-Object -First 5)) {
        $rank++
        $name = @([string]$item.name, [string]$item.hotelName, [string]$item.transportNo) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
        if (-not $name) { $name = "Option $rank" }
        $details = @([string]$item.price, [string]$item.adultPrice, [string]$item.scoreDesc, [string]$item.address) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        $lines.Add(("{0}. {1}{2}" -f $rank, $name, $(if ($details.Count) { ' - ' + ($details -join ', ') } else { '' })))
        $link = @([string]$item.jumpUrl, [string]$item.detailUrl) | Where-Object { $_ -match '^https://' } | Select-Object -First 1
        if ($link) { $lines.Add(('   Details: ' + $link)) }
    }
    if ($result.systemMessage) { $lines.Add(('Platform note: ' + [string]$result.systemMessage)) }
    $lines.Add('Travel search never places an order. Verify dates, prices, and refund rules on the details page.')
    return ($lines -join "`r`n")
}
