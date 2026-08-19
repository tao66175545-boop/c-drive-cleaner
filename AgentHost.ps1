[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ConfigPath,
    [Parameter(Mandatory = $true)][string]$TurnPath,
    [Parameter(Mandatory = $true)][string]$ToolContractPath,
    [Parameter(Mandatory = $true)][string]$EventOutput,
    [string]$CredentialRoot = '',
    [string]$FixtureResponsePath = '',
    [string]$FixtureSsePath = ''
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSCommandPath
. (Join-Path $projectRoot 'core\AgentConfig.ps1')
. (Join-Path $projectRoot 'core\AgentProtocol.ps1')
. (Join-Path $projectRoot 'core\AgentProvider.ps1')

$eventPath = [System.IO.Path]::GetFullPath($EventOutput)
$eventDirectory = Split-Path -Parent $eventPath
if ($eventDirectory) { New-Item -ItemType Directory -Path $eventDirectory -Force | Out-Null }
[System.IO.File]::WriteAllText($eventPath, '', [System.Text.UTF8Encoding]::new($false))

$turn = Get-Content -LiteralPath $TurnPath -Raw -Encoding UTF8 | ConvertFrom-Json
$turnId = [string]$turn.turnId
try {
    $config = Get-CDriveAgentConfig $ConfigPath
    if ($null -eq $config) { throw '[AGENT_CONFIG_MISSING] Provider configuration is missing.' }
    $null = Assert-CDriveAgentTurn $turn
    if (-not (Test-CDriveAgentCloudConsent $config)) { throw '[AGENT_CLOUD_CONSENT] Cloud consent is missing or stale.' }
    $contract = Get-Content -LiteralPath $ToolContractPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$contract.schemaVersion -ne 2) { throw '[AGENT_TOOL_CONTRACT] Tool contract v2 is required.' }
    $requestBody = New-CDriveProviderRequest $config $turn $contract
    Write-CDriveAgentEvent $eventPath 'agent.request.started' $turnId ([PSCustomObject]@{ providerId = $config.providerId; protocol = $config.protocol; model = $config.model })

    $result = $null
    if ($FixtureSsePath) {
        $lines = @(Get-Content -LiteralPath $FixtureSsePath -Encoding UTF8)
        $result = ConvertFrom-CDriveProviderSse $lines ([string]$config.protocol)
    } elseif ($FixtureResponsePath) {
        $fixture = Get-Content -LiteralPath $FixtureResponsePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $result = ConvertFrom-CDriveProviderResponse $fixture ([string]$config.protocol)
    } else {
        $apiKey = Get-CDriveAgentCredential ([string]$config.credentialId) $CredentialRoot
        if ([string]::IsNullOrWhiteSpace($apiKey)) { throw '[AGENT_CREDENTIAL_MISSING] API credential is missing.' }
        Add-Type -AssemblyName System.Net.Http
        $handler = [System.Net.Http.HttpClientHandler]::new()
        $handler.AllowAutoRedirect = $false
        $client = [System.Net.Http.HttpClient]::new($handler)
        try {
            $client.Timeout = [TimeSpan]::FromSeconds([int]$config.timeoutSeconds)
            $client.DefaultRequestHeaders.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $apiKey)
            $json = $requestBody | ConvertTo-Json -Depth 30 -Compress
            $content = [System.Net.Http.StringContent]::new($json, [System.Text.Encoding]::UTF8, 'application/json')
            $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Post, (Get-CDriveProviderEndpoint $config))
            $request.Content = $content
            if ([bool]$config.stream) {
                $response = $client.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
            } else {
                $response = $client.SendAsync($request).GetAwaiter().GetResult()
            }
            if (-not $response.IsSuccessStatusCode) { throw "[AGENT_HTTP_$([int]$response.StatusCode)] Provider request failed." }
            if ([bool]$config.stream) {
                $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
                $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8)
                $lines = New-Object System.Collections.Generic.List[string]
                try {
                    while (-not $reader.EndOfStream) {
                        $line = $reader.ReadLine()
                        $lines.Add($line)
                        if ($line.StartsWith('data:')) {
                            $payload = $line.Substring(5).Trim()
                            if ($payload -ne '[DONE]') {
                                try {
                                    $event = $payload | ConvertFrom-Json
                                    $delta = if ([string]$config.protocol -eq 'responses' -and [string]$event.type -eq 'response.output_text.delta') { [string]$event.delta } elseif ([string]$config.protocol -ne 'responses') { [string]@($event.choices)[0].delta.content } else { '' }
                                    if ($delta) { Write-CDriveAgentEvent $eventPath 'agent.text.delta' $turnId ([PSCustomObject]@{ text = $delta }) }
                                } catch { }
                            }
                        }
                    }
                } finally { $reader.Dispose(); $stream.Dispose() }
                $result = ConvertFrom-CDriveProviderSse $lines.ToArray() ([string]$config.protocol)
            } else {
                $payload = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
                $result = ConvertFrom-CDriveProviderResponse $payload ([string]$config.protocol)
            }
        } finally {
            if ($client) { $client.Dispose() }
            if ($handler) { $handler.Dispose() }
            $apiKey = $null
        }
    }

    if ($result.text -and (-not [bool]$config.stream -or $FixtureResponsePath -or $FixtureSsePath)) {
        Write-CDriveAgentEvent $eventPath 'agent.text.delta' $turnId ([PSCustomObject]@{ text = [string]$result.text })
    }
    Write-CDriveAgentEvent $eventPath 'agent.turn.completed' $turnId ([PSCustomObject]@{
        text = [string]$result.text
        toolCalls = @($result.toolCalls)
        responseId = [string]$result.responseId
        protocol = [string]$config.protocol
    })
    exit 0
} catch {
    if ($turnId -notmatch '^[a-f0-9]{32}$') { $turnId = '00000000000000000000000000000000' }
    Write-CDriveAgentEvent $eventPath 'agent.turn.failed' $turnId ([PSCustomObject]@{ code = 'AGENT_TURN_FAILED'; message = $_.Exception.Message })
    exit 1
}
