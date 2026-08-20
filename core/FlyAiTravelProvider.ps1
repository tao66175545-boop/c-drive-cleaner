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

    $travelSubjectPattern = '(?i)\u65c5\u884c|\u65c5\u6e38|\u51fa\u884c|\u5ea6\u5047|\u884c\u7a0b|\u653b\u7565|\u9152\u5e97|\u4f4f\u5bbf|\u6c11\u5bbf|\u673a\u7968|\u822a\u73ed|\u706b\u8f66|\u9ad8\u94c1|\u666f\u70b9|\u95e8\u7968|\u7b7e\u8bc1|\u90ae\u8f6e|\u79df\u8f66|(?:[\u4e00-\u5341\d]+\u65e5\u6e38|\u5468\u672b\u6e38|\u81ea\u7531\u884c|\u8ddf\u56e2\u6e38|\u81ea\u9a7e\u6e38)|trip|travel|hotel|flight|train|itinerary|vacation'
    $cleanupPattern = '(?i)\u6e05\u7406|\u626b\u63cf|\u5220\u9664|\u52fe\u9009|\u53d6\u6d88\u52fe\u9009|\u7f13\u5b58|\u5783\u573e|C\s*\u76d8|\u56de\u6536\u7ad9|clean|scan|delete|cache|recycle\s*bin'
    $hasTravelSubject = $Text -match $travelSubjectPattern

    # Provider-name-only cleanup commands belong to the cleaner, not the travel host.
    if ($Text -match $cleanupPattern -and -not $hasTravelSubject) { return $false }
    if ($Text -match '(?i)\u98de\u732a|flyai|fliggy') { return $true }
    return $hasTravelSubject
}

function Resolve-CDriveAssistantProviderRoute {
    param([string]$Text)
    if (Test-CDriveTravelIntent $Text) { return 'travel' }
    return 'assistant'
}

function Test-CDriveTravelQueryComplete {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    if ($Text.Trim() -match '^(?i:\u968f\u4fbf|\u90fd\u884c|\u4f60\u770b|\u4e0d\u77e5\u9053|\u6ca1\u60f3\u597d|\u518d\u8bf4|whatever|anywhere|not sure)[\p{P}\p{S}\s]*$') { return $false }

    $specific = $Text
    $specific = $specific -replace '(?i)\b(flyai|please|help|me|plan|find|search|show|a|an|the|trip|travel|vacation|itinerary|hotel|flight|train|for|to|from|in)\b', ''
    $specific = $specific -replace '\u98de\u732a|\u8bf7|\u5e2e\u6211|\u7ed9\u6211|\u7528|\u8ba9|\u6211\u60f3|\u60f3\u8981|\u60f3|\u53ef\u4ee5|\u80fd\u5426|\u89c4\u5212|\u5b89\u6392|\u63a8\u8350|\u67e5\u8be2|\u641c\u7d22|\u67e5\u627e|\u67e5|\u4e00\u6b21|\u4e00\u8d9f|\u4e00\u4e2a|\u65c5\u884c|\u65c5\u6e38|\u51fa\u884c|\u5ea6\u5047|\u884c\u7a0b|\u653b\u7565|\u9152\u5e97|\u4f4f\u5bbf|\u6c11\u5bbf|\u673a\u7968|\u822a\u73ed|\u706b\u8f66|\u9ad8\u94c1|\u666f\u70b9|\u95e8\u7968|\u7b7e\u8bc1|\u90ae\u8f6e|\u79df\u8f66|\u4e00\u4e0b|\u5427', ''
    $specific = $specific -replace '[\p{P}\p{S}\s]', ''
    return $specific.Length -ge 2
}

function Join-CDriveTravelQuestion {
    param([string]$OriginalQuestion, [string]$Details)
    if ([string]::IsNullOrWhiteSpace($OriginalQuestion)) { return $Details.Trim() }
    return ('{0}; additional details: {1}' -f $OriginalQuestion.Trim(), $Details.Trim())
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

function ConvertTo-CDriveFlyAiProxyUri {
    param([AllowEmptyString()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $candidate = $Value.Trim()
    if ($candidate -notmatch '^[a-z][a-z0-9+.-]*://') { $candidate = 'http://' + $candidate }
    $uri = $null
    if (-not [uri]::TryCreate($candidate, [System.UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -notin @('http', 'https') -or [string]::IsNullOrWhiteSpace($uri.Host)) {
        return ''
    }
    return $uri.AbsoluteUri.TrimEnd('/')
}

function ConvertFrom-CDriveWinInetProxyServer {
    param([AllowEmptyString()][string]$ProxyServer)
    $values = @{}
    foreach ($part in @($ProxyServer -split ';')) {
        $candidate = $part.Trim()
        if (-not $candidate) { continue }
        if ($candidate -match '^(?<scheme>https?|socks)=(?<address>.+)$') {
            $values[$Matches.scheme.ToLowerInvariant()] = $Matches.address.Trim()
        } elseif (-not $values.ContainsKey('default')) {
            $values.default = $candidate
        }
    }
    $httpProxy = ConvertTo-CDriveFlyAiProxyUri $(if ($values.http) { $values.http } elseif ($values.default) { $values.default } elseif ($values.https) { $values.https } else { '' })
    $httpsProxy = ConvertTo-CDriveFlyAiProxyUri $(if ($values.https) { $values.https } elseif ($values.default) { $values.default } elseif ($values.http) { $values.http } else { '' })
    return [PSCustomObject]@{ HttpProxy = $httpProxy; HttpsProxy = $httpsProxy; Source = $(if ($httpProxy -or $httpsProxy) { 'wininet' } else { 'direct' }) }
}

function Get-CDriveFlyAiProxySettings {
    $environmentHttp = [Environment]::GetEnvironmentVariable('HTTP_PROXY')
    $environmentHttps = [Environment]::GetEnvironmentVariable('HTTPS_PROXY')
    if ($environmentHttp -or $environmentHttps) {
        return [PSCustomObject]@{
            HttpProxy = ConvertTo-CDriveFlyAiProxyUri $(if ($environmentHttp) { $environmentHttp } else { $environmentHttps })
            HttpsProxy = ConvertTo-CDriveFlyAiProxyUri $(if ($environmentHttps) { $environmentHttps } else { $environmentHttp })
            Source = 'environment'
        }
    }

    try {
        $internetSettings = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
        if ([int]$internetSettings.ProxyEnable -eq 1 -and -not [string]::IsNullOrWhiteSpace([string]$internetSettings.ProxyServer)) {
            return ConvertFrom-CDriveWinInetProxyServer ([string]$internetSettings.ProxyServer)
        }
    } catch {}
    return [PSCustomObject]@{ HttpProxy = ''; HttpsProxy = ''; Source = 'direct' }
}

function Set-CDriveFlyAiProcessProxy {
    param(
        [Parameter(Mandatory = $true)][System.Diagnostics.ProcessStartInfo]$StartInfo,
        [Parameter(Mandatory = $true)]$ProxySettings
    )
    if ($ProxySettings.HttpProxy) { $StartInfo.EnvironmentVariables['HTTP_PROXY'] = [string]$ProxySettings.HttpProxy }
    if ($ProxySettings.HttpsProxy) { $StartInfo.EnvironmentVariables['HTTPS_PROXY'] = [string]$ProxySettings.HttpsProxy }
    if ($ProxySettings.HttpProxy -or $ProxySettings.HttpsProxy) {
        # Node 24+ uses this switch for fetch/undici; older supported runtimes safely ignore it.
        $StartInfo.EnvironmentVariables['NODE_USE_ENV_PROXY'] = '1'
    }
}

function Get-CDriveFlyAiFailureCode {
    param([AllowEmptyString()][string]$ErrorText)
    if ($ErrorText -match '(?i)certificate|ERR_TLS|ERR_SSL|secure TLS|TLS connection|unable to verify|SELF_SIGNED|ECONNRESET') { return 'FLYAI_TLS' }
    if ($ErrorText -match '(?i)ENETUNREACH|EHOSTUNREACH|ECONNREFUSED|EAI_AGAIN|ENOTFOUND|ETIMEDOUT|UND_ERR_CONNECT') { return 'FLYAI_NETWORK' }
    return 'FLYAI_FAILED'
}

function Test-CDriveFlyAiPayloadHasDisplayData {
    param($Payload)
    if ($null -eq $Payload -or -not $Payload.PSObject.Properties['data']) { return $false }
    $data = $Payload.data
    if ($data -is [string]) { return -not [string]::IsNullOrWhiteSpace([string]$data) }
    if ($null -eq $data -or -not $data.PSObject.Properties['itemList']) { return $false }
    return @($data.itemList | Where-Object { $null -ne $_ }).Count -gt 0
}

function Invoke-CDriveFlyAiSearch {
    param(
        [Parameter(Mandatory = $true)][string]$Query,
        [ValidateSet('ai-search', 'keyword-search')][string]$Mode = 'ai-search',
        [int]$TimeoutSeconds = 0,
        [string]$ExecutablePath = '',
        [ValidateRange(1, 3)][int]$MaxAttempts = 2,
        $ProxySettings = $null
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
    if ($TimeoutSeconds -le 0) { $TimeoutSeconds = if ($Mode -eq 'ai-search') { 90 } else { 45 } }
    if ($TimeoutSeconds -lt 5 -or $TimeoutSeconds -gt 180) { throw '[FLYAI_TIMEOUT_CONFIG] FlyAI timeout must be between 5 and 180 seconds.' }
    if ($null -eq $ProxySettings) { $ProxySettings = Get-CDriveFlyAiProxySettings }

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = [string]$nodeCommand.Source
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $startInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
        Set-CDriveFlyAiProcessProxy $startInfo $ProxySettings
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
            if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
                try { $process.Kill() } catch {}
                try { [void]$process.WaitForExit(2000) } catch {}
                throw ('[FLYAI_TIMEOUT] FlyAI travel search exceeded {0} seconds.' -f $TimeoutSeconds)
            }
            $stdout = $stdoutTask.GetAwaiter().GetResult().Trim()
            $stderr = $stderrTask.GetAwaiter().GetResult().Trim()
            $knownNode24ExitAssertion = $stderr -match 'Assertion failed:\s*!\(handle->flags\s*&\s*UV_HANDLE_CLOSING\)'
            if ($process.ExitCode -ne 0 -and -not $knownNode24ExitAssertion) {
                $failureCode = Get-CDriveFlyAiFailureCode $stderr
                if ($attempt -lt $MaxAttempts -and $failureCode -in @('FLYAI_TLS', 'FLYAI_NETWORK')) {
                    Start-Sleep -Milliseconds (500 * $attempt)
                    continue
                }
                $detail = if ($stderr.Length -gt 1200) { $stderr.Substring(0, 1200) } else { $stderr }
                throw ('[{0}] {1}' -f $failureCode, $detail)
            }
            if ([string]::IsNullOrWhiteSpace($stdout)) { throw '[FLYAI_EMPTY] FlyAI returned no result.' }
            try { $payload = $stdout | ConvertFrom-Json }
            catch { throw '[FLYAI_JSON] FlyAI returned invalid JSON.' }
            if (-not (Test-CDriveFlyAiPayloadHasDisplayData $payload)) {
                if ($attempt -lt $MaxAttempts) {
                    Start-Sleep -Milliseconds (300 * $attempt)
                    continue
                }
                throw '[FLYAI_EMPTY] FlyAI returned JSON without displayable travel data.'
            }
            return [PSCustomObject]@{
                schemaVersion = 1
                provider = 'FlyAI'
                mode = $Mode
                query = $Query
                result = $payload
                readOnly = $true
                bookingExecuted = $false
                attempts = $attempt
                networkRoute = [string]$ProxySettings.Source
                runtimeWarning = $(if ($knownNode24ExitAssertion) { 'node24-windows-exit-assertion' } else { '' })
            }
        } finally { $process.Dispose() }
    }
    throw '[FLYAI_FAILED] FlyAI travel search failed after retry.'
}

function Remove-CDriveFlyAiMarkdownDecoration {
    param([AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $value = $Text.Trim()
    $value = [regex]::Replace($value, '\[(?<label>[^\]]+)\]\(https://[^\s\)]+\)', '${label}')
    $value = $value -replace '\*\*|__|`', ''
    $value = $value.Trim('*', '_', ' ')
    $value = $value -replace '^[\s\u2600-\u27BF]+', ''
    $value = [regex]::Replace($value, '^[\uD800-\uDBFF][\uDC00-\uDFFF]\s*', '')
    return ($value -replace '\s{2,}', ' ').Trim()
}

function Get-CDriveFlyAiSafeHttpsUrl {
    param([AllowEmptyString()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $uri = $null
    if (-not [uri]::TryCreate($Value.Trim(), [System.UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne 'https') { return '' }
    return $uri.AbsoluteUri
}

function Get-CDriveFlyAiSafeImageUrl {
    param([AllowEmptyString()][string]$Value)
    $safeUrl = Get-CDriveFlyAiSafeHttpsUrl $Value
    if (-not $safeUrl) { return '' }
    $uri = [uri]$safeUrl
    $imageHost = $uri.DnsSafeHost.ToLowerInvariant()
    if ($imageHost -eq 'img.alicdn.com' -or $imageHost.EndsWith('.alicdn.com') -or $imageHost.EndsWith('.tbcdn.cn')) { return $safeUrl }
    return ''
}

function ConvertTo-CDriveFlyAiDisplayItem {
    param($Item, [int]$Rank = 1)
    if ($null -eq $Item) { return $null }
    $value = if ($Item.PSObject.Properties['info'] -and $null -ne $Item.info) { $Item.info } else { $Item }
    $title = @([string]$value.title, [string]$value.name, [string]$value.hotelName, [string]$value.transportNo) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
    if (-not $title) { $title = "推荐 $Rank" }
    $details = New-Object System.Collections.Generic.List[string]
    foreach ($pair in @(
        @('价格', [string]$value.price),
        @('成人价', [string]$value.adultPrice),
        @('评分', [string]$value.scoreDesc),
        @('星级', $(if ([string]$value.star) { [string]$value.star + ' 星' } else { '' })),
        @('地址', [string]$value.address)
    )) {
        if (-not [string]::IsNullOrWhiteSpace([string]$pair[1])) { $details.Add(('{0}：{1}' -f $pair[0], $pair[1])) }
    }
    $link = @([string]$value.jumpUrl, [string]$value.detailUrl) | ForEach-Object { Get-CDriveFlyAiSafeHttpsUrl $_ } | Where-Object { $_ } | Select-Object -First 1
    $image = @([string]$value.picUrl, [string]$value.imageUrl, [string]$value.image) | ForEach-Object { Get-CDriveFlyAiSafeImageUrl $_ } | Where-Object { $_ } | Select-Object -First 1
    return [PSCustomObject]@{
        Title = Remove-CDriveFlyAiMarkdownDecoration $title
        Details = $details.ToArray()
        Link = [string]$link
        ImageUrl = [string]$image
    }
}

function Save-CDriveFlyAiPreviewImages {
    param(
        $Response,
        [Parameter(Mandatory = $true)][string]$OutputDirectory,
        [ValidateRange(1, 3)][int]$MaximumImages = 3,
        [ValidateRange(5, 30)][int]$TimeoutSeconds = 6,
        [ValidateRange(262144, 5242880)][int]$MaximumBytes = 2621440
    )

    $saved = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Response -or $null -eq $Response.result -or $null -eq $Response.result.data -or
        -not $Response.result.data.PSObject.Properties['itemList']) { return $saved.ToArray() }
    [System.IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
    Add-Type -AssemblyName System.Drawing
    $rank = 0
    foreach ($entry in @($Response.result.data.itemList | Select-Object -First $MaximumImages)) {
        if ($saved.Count -ge $MaximumImages) { break }
        $rank++
        $item = ConvertTo-CDriveFlyAiDisplayItem $entry $rank
        if ($null -eq $item -or -not $item.ImageUrl) { continue }
        $request = $null
        $responseObject = $null
        $stream = $null
        $bufferStream = $null
        $image = $null
        $bitmap = $null
        try {
            $request = [System.Net.HttpWebRequest]::Create([string]$item.ImageUrl)
            $request.Method = 'GET'
            $request.Timeout = $TimeoutSeconds * 1000
            $request.ReadWriteTimeout = $TimeoutSeconds * 1000
            $request.AllowAutoRedirect = $true
            $request.MaximumAutomaticRedirections = 3
            $request.Accept = 'image/jpeg,image/png,image/gif,image/bmp;q=0.8'
            $responseObject = [System.Net.HttpWebResponse]$request.GetResponse()
            if ([int]$responseObject.StatusCode -ne 200) { continue }
            if ($responseObject.ContentLength -gt $MaximumBytes) { continue }
            # Alibaba CDN may advertise WebP while delivering JPEG bytes. Decode validation below remains authoritative.
            if ([string]$responseObject.ContentType -notmatch '^image/(?:jpeg|png|gif|bmp|webp)\b') { continue }
            $finalImageUrl = Get-CDriveFlyAiSafeImageUrl ([string]$responseObject.ResponseUri.AbsoluteUri)
            if (-not $finalImageUrl) { continue }
            $stream = $responseObject.GetResponseStream()
            $bufferStream = [System.IO.MemoryStream]::new()
            $buffer = New-Object byte[] 32768
            $total = 0
            while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $total += $read
                if ($total -gt $MaximumBytes) { throw '[FLYAI_IMAGE_SIZE] Preview image is too large.' }
                $bufferStream.Write($buffer, 0, $read)
            }
            if ($total -lt 128) { continue }
            $bufferStream.Position = 0
            $image = [System.Drawing.Image]::FromStream($bufferStream, $true, $true)
            if ($image.Width -lt 32 -or $image.Height -lt 32 -or $image.Width -gt 12000 -or $image.Height -gt 12000) { continue }
            $bitmap = [System.Drawing.Bitmap]::new($image)
            $path = Join-Path $OutputDirectory ('travel-preview-{0}.png' -f ($saved.Count + 1))
            $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
            $saved.Add([PSCustomObject]@{
                Title = [string]$item.Title
                Link = [string]$item.Link
                LocalPath = $path
            })
        } catch {
            continue
        } finally {
            if ($bitmap) { $bitmap.Dispose() }
            if ($image) { $image.Dispose() }
            if ($bufferStream) { $bufferStream.Dispose() }
            if ($stream) { $stream.Dispose() }
            if ($responseObject) { $responseObject.Dispose() }
        }
    }
    return $saved.ToArray()
}

function ConvertTo-CDriveFlyAiDisplayModel {
    param($Response)

    $emptyModel = [PSCustomObject]@{
        SchemaVersion = 1
        Title = '飞猪旅行规划'
        Summary = '飞猪没有返回可展示的旅行内容。'
        Sections = @()
        Notice = '旅行搜索不会自动预订或下单。'
        HasImages = $false
    }
    if ($null -eq $Response -or $null -eq $Response.result) { return $emptyModel }

    $sections = New-Object System.Collections.Generic.List[object]
    $summaryLines = New-Object System.Collections.Generic.List[string]
    $currentSection = $null
    $currentItem = $null
    $data = $Response.result.data

    if ($data -is [string]) {
        foreach ($rawLine in @(([string]$data) -split "`r?`n")) {
            $line = $rawLine.Trim()
            if (-not $line) { continue }
            if ($line -match '^#{1,3}\s+(?<title>.+)$') {
                $currentSection = [PSCustomObject]@{
                    Title = Remove-CDriveFlyAiMarkdownDecoration $Matches.title
                    Kind = 'general'
                    Lines = New-Object System.Collections.Generic.List[string]
                    Items = New-Object System.Collections.Generic.List[object]
                    Notes = New-Object System.Collections.Generic.List[string]
                }
                $sections.Add($currentSection)
                $currentItem = $null
                continue
            }
            if ($line -match '^\*{0,2}\[(?<title>[^\]]+)\]\((?<url>https://[^\s\)]+)\)\*{0,2}$') {
                if ($null -eq $currentSection) {
                    $currentSection = [PSCustomObject]@{
                        Title = '实时推荐'; Kind = 'recommendations'
                        Lines = New-Object System.Collections.Generic.List[string]
                        Items = New-Object System.Collections.Generic.List[object]
                        Notes = New-Object System.Collections.Generic.List[string]
                    }
                    $sections.Add($currentSection)
                }
                $currentItem = [PSCustomObject]@{
                    Title = Remove-CDriveFlyAiMarkdownDecoration $Matches.title
                    Details = New-Object System.Collections.Generic.List[string]
                    Link = Get-CDriveFlyAiSafeHttpsUrl $Matches.url
                    ImageUrl = ''
                }
                $currentSection.Items.Add($currentItem)
                continue
            }
            if ($line -match '^>\s*(?<note>.+)$') {
                $note = Remove-CDriveFlyAiMarkdownDecoration $Matches.note
                if ($currentSection) { $currentSection.Notes.Add($note) } else { $summaryLines.Add($note) }
                continue
            }
            if ($line -match '^[-*]\s+(?<content>.+)$') {
                $content = Remove-CDriveFlyAiMarkdownDecoration $Matches.content
                if ($currentItem -and $Matches.content -match '^\*\*(?<label>[^*]+)\*\*[：:]\s*(?<value>.*)$') {
                    $content = ('{0}：{1}' -f (Remove-CDriveFlyAiMarkdownDecoration $Matches.label), (Remove-CDriveFlyAiMarkdownDecoration $Matches.value))
                    $currentItem.Details.Add($content)
                } elseif ($currentSection) {
                    $currentSection.Lines.Add($content)
                } else {
                    $summaryLines.Add($content)
                }
                continue
            }
            $content = Remove-CDriveFlyAiMarkdownDecoration $line
            if ($currentItem) { $currentItem.Details.Add($content) }
            elseif ($currentSection) { $currentSection.Lines.Add($content) }
            else { $summaryLines.Add($content) }
        }
    } elseif ($null -ne $data -and $data.PSObject.Properties['itemList']) {
        $items = New-Object System.Collections.Generic.List[object]
        $rank = 0
        foreach ($entry in @($data.itemList | Select-Object -First 5)) {
            $rank++
            $item = ConvertTo-CDriveFlyAiDisplayItem $entry $rank
            if ($item) { $items.Add($item) }
        }
        if ($items.Count -gt 0) {
            $sections.Add([PSCustomObject]@{ Title = '飞猪实时推荐'; Kind = 'recommendations'; Lines = @(); Items = $items.ToArray(); Notes = @() })
        }
    }

    $visualItems = New-Object System.Collections.Generic.List[object]
    if ($Response.PSObject.Properties['visualResult'] -and $Response.visualResult -and
        $Response.visualResult.result -and $Response.visualResult.result.data -and
        $Response.visualResult.result.data.PSObject.Properties['itemList']) {
        $rank = 0
        foreach ($entry in @($Response.visualResult.result.data.itemList | Select-Object -First 3)) {
            $rank++
            $item = ConvertTo-CDriveFlyAiDisplayItem $entry $rank
            if ($item) { $visualItems.Add($item) }
        }
    }
    if ($visualItems.Count -gt 0) {
        $sections.Add([PSCustomObject]@{
            Title = '飞猪实时推荐'
            Kind = 'visual-recommendations'
            Lines = @('根据同一旅行问题补充的实时结果，价格和库存请在详情页确认。')
            Items = $visualItems.ToArray()
            Notes = @()
        })
    }

    foreach ($section in $sections.ToArray()) {
        $title = [string]$section.Title
        $section.Kind = if ($title -match '交通|车次|航班') { 'transport' }
            elseif ($title -match '景点|人文|游玩') { 'attractions' }
            elseif ($title -match '酒店|住宿|民宿') { 'lodging' }
            elseif ($title -match '预算|费用|价格') { 'budget' }
            elseif ($title -match '总结|提示') { 'summary' }
            else { [string]$section.Kind }
        $section.Lines = [object[]]$section.Lines
        $section.Items = [object[]]$section.Items
        $section.Notes = [object[]]$section.Notes
    }

    $notice = Remove-CDriveFlyAiMarkdownDecoration ([string]$Response.result.systemMessage)
    if (-not $notice) { $notice = '旅行搜索不会自动预订或下单；日期、价格、库存和退改规则以飞猪详情页为准。' }
    else { $notice += ' 旅行搜索不会自动预订或下单，实时信息以飞猪详情页为准。' }
    $summary = ($summaryLines.ToArray() -join "`r`n")
    if (-not $summary -and $sections.Count -gt 0) { $summary = '已按主题整理本次实时旅行建议。' }
    if ($Response.PSObject.Properties['fallbackReason'] -and [string]$Response.fallbackReason -eq 'ai-search-empty') {
        $summary = '完整行程生成暂未返回内容，已自动切换为飞猪实时搜索结果。'
    }
    return [PSCustomObject]@{
        SchemaVersion = 1
        Title = '飞猪旅行规划'
        Summary = $summary
        Sections = $sections.ToArray()
        Notice = $notice
        HasImages = @($sections.ToArray() | ForEach-Object Items | Where-Object { $_.ImageUrl }).Count -gt 0
    }
}

function Format-CDriveFlyAiResult {
    param($Response)
    $model = ConvertTo-CDriveFlyAiDisplayModel $Response
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add([string]$model.Title)
    if ($model.Summary) { $lines.Add([string]$model.Summary) }
    foreach ($section in @($model.Sections)) {
        $lines.Add('')
        $lines.Add([string]$section.Title)
        foreach ($line in @($section.Lines)) { $lines.Add(('• ' + [string]$line)) }
        $sectionItems = [object[]]$section.Items
        foreach ($item in $sectionItems) {
            $lines.Add([string]$item.Title)
            foreach ($detail in @($item.Details)) { $lines.Add(('  ' + [string]$detail)) }
            if ($item.Link) { $lines.Add(('  飞猪详情：' + [string]$item.Link)) }
        }
        foreach ($note in @($section.Notes)) { $lines.Add(('提示：' + [string]$note)) }
    }
    $lines.Add('')
    $lines.Add([string]$model.Notice)
    return ($lines.ToArray() -join "`r`n")
}
