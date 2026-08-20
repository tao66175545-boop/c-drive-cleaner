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
if ($formatted -notmatch 'West Lake Hotel' -or $formatted -notmatch 'https://example.com/hotel' -or $formatted -notmatch 'never places an order') {
    throw 'FlyAI result formatting lost required safety or display content.'
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
