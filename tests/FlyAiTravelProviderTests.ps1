$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot 'core\FlyAiTravelProvider.ps1')

if (-not (Test-CDriveTravelIntent 'find a hotel in Shanghai')) { throw 'English travel intent was not detected.' }
if (Test-CDriveTravelIntent 'clean recommended cache') { throw 'Cleanup intent leaked into the travel provider.' }
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
console.log(JSON.stringify({ data: { nodeUseEnvProxy: process.env.NODE_USE_ENV_PROXY || '', httpsProxyPresent: Boolean(process.env.HTTPS_PROXY) } }));
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
    if ([string]$retryResult.result.data.nodeUseEnvProxy -ne '1' -or -not [bool]$retryResult.result.data.httpsProxyPresent) {
        throw 'FlyAI child process did not receive the proxy environment.'
    }
} finally {
    foreach ($path in @($fixturePath, $markerPath)) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
    }
}

Write-Output '[OK] FlyAI travel provider -> isolated intent, fixed command surface, read-only result formatting'
