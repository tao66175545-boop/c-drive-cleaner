$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot 'core\FlyAiTravelProvider.ps1')

if (-not (Test-CDriveTravelIntent 'find a hotel in Shanghai')) { throw 'English travel intent was not detected.' }
if (Test-CDriveTravelIntent 'clean recommended cache') { throw 'Cleanup intent leaked into the travel provider.' }
$reportedTravelQuery = -join ([char[]]@(0x98DE, 0x732A, 0x89C4, 0x5212, 0x5317, 0x4EAC, 0x5468, 0x672B, 0x4E00, 0x65E5, 0x6E38))
if (-not (Test-CDriveTravelIntent $reportedTravelQuery)) { throw 'Explicit FlyAI day-tour request was not detected.' }
if (-not (Test-CDriveTravelQueryComplete $reportedTravelQuery)) { throw 'Explicit FlyAI day-tour request was incorrectly treated as incomplete.' }
if ((Resolve-CDriveAssistantProviderRoute $reportedTravelQuery) -ne 'travel') { throw 'Reported FlyAI request did not route to the travel provider.' }
foreach ($tourVariant in @('北京一日游', '杭州周末游', '云南自由行', '成都跟团游', '川西自驾游')) {
    if ((Resolve-CDriveAssistantProviderRoute $tourVariant) -ne 'travel') { throw ('Tour form was not routed to travel: ' + $tourVariant) }
}
foreach ($nonTravelText in @('周末整理一下桌面', '飞猪清理 C盘缓存', '扫描并勾选建议清理项')) {
    if ((Resolve-CDriveAssistantProviderRoute $nonTravelText) -ne 'assistant') { throw ('Non-travel request leaked into travel routing: ' + $nonTravelText) }
}
if (Test-CDriveTravelQueryComplete 'plan a trip') { throw 'Underspecified travel request was sent to FlyAI instead of requesting details.' }
$genericChineseTravel = -join ([char[]]@(0x98DE, 0x732A, 0x89C4, 0x5212, 0x4E00, 0x6B21, 0x65C5, 0x884C))
if (Test-CDriveTravelQueryComplete $genericChineseTravel) { throw 'Underspecified Chinese travel request was sent to FlyAI instead of requesting details.' }
if (-not (Test-CDriveTravelQueryComplete 'Hangzhou, two days, from Shanghai')) { throw 'Travel clarification details were incorrectly rejected.' }
if ((Join-CDriveTravelQuestion 'plan a trip' 'Hangzhou, two days') -ne 'plan a trip; additional details: Hangzhou, two days') { throw 'Travel clarification context was not combined deterministically.' }

$quotedArgument = ConvertTo-CDriveProcessArgument 'plan "West Lake" trip'
if ($quotedArgument -ne '"plan \"West Lake\" trip"') { throw 'Windows process argument quoting is not strict.' }

$proxySettings = ConvertFrom-CDriveWinInetProxyServer 'http=127.0.0.1:8080;https=127.0.0.1:8443'
if ($proxySettings.HttpProxy -ne 'http://127.0.0.1:8080' -or $proxySettings.HttpsProxy -ne 'http://127.0.0.1:8443' -or $proxySettings.Source -ne 'wininet') {
    throw 'WinINET proxy mapping was not normalized for the FlyAI child process.'
}
if ((Get-CDriveFlyAiFailureCode 'Client network socket disconnected before secure TLS connection was established (ECONNRESET)') -ne 'FLYAI_TLS') {
    throw 'FlyAI TLS failures are not classified correctly.'
}
if ((Get-CDriveFlyAiFailureCode 'connect ETIMEDOUT') -ne 'FLYAI_NETWORK') {
    throw 'FlyAI network failures are not classified correctly.'
}
$emptyPayload = [PSCustomObject]@{ data = ''; message = 'success'; status = 0 }
$emptyListPayload = [PSCustomObject]@{ data = [PSCustomObject]@{ itemList = @() }; message = 'success'; status = 0 }
$markdownPayload = [PSCustomObject]@{ data = 'Beijing weekend itinerary'; message = 'success'; status = 0 }
$itemPayload = [PSCustomObject]@{ data = [PSCustomObject]@{ itemList = @([PSCustomObject]@{ info = [PSCustomObject]@{ title = 'Beijing day tour' } }) }; message = 'success'; status = 0 }
if ((Test-CDriveFlyAiPayloadHasDisplayData $emptyPayload) -or (Test-CDriveFlyAiPayloadHasDisplayData $emptyListPayload)) {
    throw 'FlyAI successful-but-empty payload was accepted as displayable.'
}
if (-not (Test-CDriveFlyAiPayloadHasDisplayData $markdownPayload) -or -not (Test-CDriveFlyAiPayloadHasDisplayData $itemPayload)) {
    throw 'FlyAI displayable Markdown or item-list payload was rejected.'
}

$fixture = [PSCustomObject]@{
    result = [PSCustomObject]@{
        data = [PSCustomObject]@{
            itemList = @([PSCustomObject]@{ name = 'West Lake Hotel'; price = 'CNY 618'; detailUrl = 'https://example.com/hotel' })
        }
        systemMessage = 'Prices change in real time.'
    }
}
$formatted = Format-CDriveFlyAiResult $fixture
if ($formatted -notmatch 'West Lake Hotel' -or $formatted -notmatch 'https://example.com/hotel' -or $formatted -notmatch '不会自动预订或下单') {
    throw 'FlyAI result formatting lost required safety or display content.'
}
$displayModel = ConvertTo-CDriveFlyAiDisplayModel $fixture
$displaySections = [object[]]$displayModel.Sections
$displayItems = [object[]]$displaySections[0].Items
if ($displayModel.Title -ne '飞猪旅行规划' -or $displaySections.Count -ne 1 -or $displayItems.Count -eq 0) {
    throw 'FlyAI structured display model lost keyword-search results.'
}

$markdownFixture = [PSCustomObject]@{
    result = [PSCustomObject]@{
        data = "基于实时结果整理两日行程。`r`n`r`n## 交通`r`n- **G7509**：上海南 10:43 → 杭州东 11:53`r`n`r`n## 人文景点`r`n**[浙江省博物馆](https://router.feizhu.com/detail)**`r`n- **亮点**：了解浙江历史`r`n- **权衡**：周一闭馆`r`n`r`n## 预算`r`n- **合计**：约 1000 元"
        systemMessage = '*当前为体验模式*'
    }
    visualResult = [PSCustomObject]@{
        result = [PSCustomObject]@{
            data = [PSCustomObject]@{
                itemList = @([PSCustomObject]@{ info = [PSCustomObject]@{ title = '杭州安静酒店'; star = '3'; jumpUrl = 'https://router.feizhu.com/hotel'; picUrl = 'https://img.alicdn.com/hotel.jpg' } })
            }
        }
    }
}
$markdownModel = ConvertTo-CDriveFlyAiDisplayModel $markdownFixture
$markdownSections = [object[]]$markdownModel.Sections
$markdownFormatted = Format-CDriveFlyAiResult $markdownFixture
if ($markdownModel.Summary -notmatch '两日行程' -or $markdownSections.Count -ne 4 -or $markdownFormatted -match '\*\*|##') {
    throw 'FlyAI Markdown was not converted into a readable hierarchy.'
}
if (-not $markdownModel.HasImages -or [string]$markdownSections[3].Items[0].ImageUrl -notmatch '^https://img\.alicdn\.com/') {
    throw 'FlyAI trusted visual recommendation was not retained.'
}
if (Get-CDriveFlyAiSafeImageUrl 'https://tracking.example.com/photo.jpg') { throw 'Untrusted travel image domain was accepted.' }
if (Get-CDriveFlyAiSafeHttpsUrl 'http://router.feizhu.com/insecure') { throw 'Insecure travel detail URL was accepted.' }
if ((Remove-CDriveFlyAiMarkdownDecoration '*当前为体验模式*') -ne '当前为体验模式') { throw 'Markdown notice decoration was not removed.' }
$calendarEmoji = -join ([char[]]@(0xD83D, 0xDDD3, 0xFE0F))
$subwayEmoji = -join ([char[]]@(0xD83D, 0xDE87, 0xFE0F))
$sunEmoji = -join ([char[]]@(0x2600, 0xFE0F))
$compassEmoji = -join ([char[]]@(0xD83E, 0xDDED))
if ((Remove-CDriveFlyAiMarkdownDecoration ($calendarEmoji + ' 北京一日游规划')) -ne '北京一日游规划' -or
    (Remove-CDriveFlyAiMarkdownDecoration ($subwayEmoji + ' 推荐路线')) -ne '推荐路线' -or
    (Remove-CDriveFlyAiMarkdownDecoration ($sunEmoji + ' 上午行程')) -ne '上午行程' -or
    (Remove-CDriveFlyAiMarkdownDecoration ('今天适合游览！' + $compassEmoji)) -ne '今天适合游览！') {
    throw 'FlyAI emoji decoration or orphaned variation selector was retained.'
}
$cleanedUnicode = Remove-CDriveFlyAiMarkdownDecoration ($calendarEmoji + ' 北京 → 故宫 ' + $compassEmoji)
if ($cleanedUnicode -match '[\uFE0E\uFE0F\u200D\uD83C-\uD83E]' -or $cleanedUnicode -ne '北京 → 故宫') {
    throw 'FlyAI display text retained an unsupported Unicode modifier or lost meaningful route text.'
}
$providerSource = Get-Content -LiteralPath (Join-Path $projectRoot 'core\FlyAiTravelProvider.ps1') -Raw -Encoding UTF8
if ($providerSource -notmatch "ValidateRange\(1, 3\).*MaximumImages" -or
    $providerSource -notmatch 'Select-Object -First \$MaximumImages' -or
    $providerSource -notmatch "ValidateRange\(262144, 5242880\).*MaximumBytes" -or
    $providerSource -notmatch "ContentType -notmatch '\^image/" -or
    $providerSource -notmatch 'Image\]::FromStream\(\$bufferStream, \$true, \$true\)' -or
    $providerSource -notmatch "Accept = 'image/jpeg,image/png") {
    throw 'FlyAI preview image count, size, or content-type boundary is missing.'
}

try { $null = Invoke-CDriveFlyAiSearch -Query 'Hangzhou travel' -ExecutablePath (Join-Path $env:TEMP 'missing-flyai.cjs'); throw 'Missing FlyAI executable was accepted.' }
catch { if ($_.Exception.Message -notmatch 'FLYAI_NOT_INSTALLED') { throw } }

$fixturePath = Join-Path $env:TEMP ('flyai-retry-fixture-' + [guid]::NewGuid().ToString('N') + '.cjs')
$markerPath = Join-Path $env:TEMP ('flyai-retry-marker-' + [guid]::NewGuid().ToString('N'))
$fixtureSource = @'
const fs = require('fs');
const queryIndex = process.argv.indexOf('--query');
const query = queryIndex >= 0 ? process.argv[queryIndex + 1] : '';
const marker = query.startsWith('retry:') ? query.substring(6) : '';
if (marker && !fs.existsSync(marker)) {
  fs.writeFileSync(marker, 'first-attempt');
  console.error('Client network socket disconnected before secure TLS connection was established (ECONNRESET)');
  process.exit(1);
}
console.log(JSON.stringify({ data: { itemList: [{ info: { title: 'fixture', nodeUseEnvProxy: process.env.NODE_USE_ENV_PROXY || '', httpsProxyPresent: Boolean(process.env.HTTPS_PROXY) } }] } }));
'@
try {
    [System.IO.File]::WriteAllText($fixturePath, $fixtureSource, [System.Text.UTF8Encoding]::new($false))
    $retryResult = Invoke-CDriveFlyAiSearch `
        -Query ('retry:' + $markerPath) `
        -ExecutablePath $fixturePath `
        -TimeoutSeconds 10 `
        -MaxAttempts 2 `
        -ProxySettings ([PSCustomObject]@{ HttpProxy = 'http://127.0.0.1:8080'; HttpsProxy = 'http://127.0.0.1:8443'; Source = 'test-proxy' })
    if ($retryResult.attempts -ne 2 -or $retryResult.networkRoute -ne 'test-proxy') {
        throw 'FlyAI did not recover from a transient TLS failure with one bounded retry.'
    }
    $retryInfo = $retryResult.result.data.itemList[0].info
    if ([string]$retryInfo.nodeUseEnvProxy -ne '1' -or -not [bool]$retryInfo.httpsProxyPresent) {
        throw 'FlyAI child process did not receive the proxy environment.'
    }
} finally {
    foreach ($path in @($fixturePath, $markerPath)) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
    }
}

$emptyFixturePath = Join-Path $env:TEMP ('flyai-empty-fixture-' + [guid]::NewGuid().ToString('N') + '.cjs')
$emptyFixtureSource = "console.log(JSON.stringify({ data: '', message: 'success', status: 0 }));"
try {
    [System.IO.File]::WriteAllText($emptyFixturePath, $emptyFixtureSource, [System.Text.UTF8Encoding]::new($false))
    try {
        $null = Invoke-CDriveFlyAiSearch -Query 'Beijing day tour' -ExecutablePath $emptyFixturePath -TimeoutSeconds 10 -MaxAttempts 2
        throw 'FlyAI successful-but-empty process result was accepted.'
    } catch {
        if ($_.Exception.Message -notmatch 'FLYAI_EMPTY') { throw }
    }
} finally {
    if (Test-Path -LiteralPath $emptyFixturePath) { Remove-Item -LiteralPath $emptyFixturePath -Force -ErrorAction SilentlyContinue }
}

$travelHostSource = Get-Content -LiteralPath (Join-Path $projectRoot 'TravelHost.ps1') -Raw -Encoding UTF8
if ($travelHostSource -notmatch "fallbackReason.*ai-search-empty" -or
    $travelHostSource -notmatch "Mode 'keyword-search'.*TimeoutSeconds 45") {
    throw 'Travel Host does not fall back to keyword search when AI search is empty.'
}

$fallbackFixtureRoot = Join-Path $PSScriptRoot 'fixtures\flyai-empty-fallback'
$fallbackRequestPath = Join-Path $env:TEMP ('flyai-fallback-request-' + [guid]::NewGuid().ToString('N') + '.json')
$fallbackOutputPath = Join-Path $env:TEMP ('flyai-fallback-output-' + [guid]::NewGuid().ToString('N') + '.json')
$previousPath = $env:PATH
try {
    [System.IO.File]::WriteAllText(
        $fallbackRequestPath,
        ([PSCustomObject]@{ query = 'Beijing weekend day tour'; mode = 'ai-search' } | ConvertTo-Json -Compress),
        [System.Text.UTF8Encoding]::new($false)
    )
    $env:PATH = $fallbackFixtureRoot + ';' + $previousPath
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot 'TravelHost.ps1') -RequestPath $fallbackRequestPath -OutputPath $fallbackOutputPath
    if ($LASTEXITCODE -ne 0) { throw 'Travel Host empty-result fallback fixture failed.' }
    $fallbackPayload = Get-Content -LiteralPath $fallbackOutputPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $fallbackModel = ConvertTo-CDriveFlyAiDisplayModel $fallbackPayload.response
    $fallbackSections = [object[]]$fallbackModel.Sections
    if (-not $fallbackPayload.ok -or [string]$fallbackPayload.response.fallbackReason -ne 'ai-search-empty' -or
        $fallbackModel.Summary -notmatch '自动切换.*实时搜索' -or $fallbackSections.Count -ne 1 -or
        [string]$fallbackSections[0].Items[0].Title -ne 'Beijing day-tour fallback result') {
        throw 'Travel Host did not convert an empty AI result into a displayable keyword fallback.'
    }
} finally {
    $env:PATH = $previousPath
    foreach ($path in @($fallbackRequestPath, $fallbackOutputPath)) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
    }
}

Write-Output '[OK] FlyAI travel provider -> isolated intent, fixed command surface, read-only result formatting'
