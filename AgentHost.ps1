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

function ConvertTo-CDriveCurlConfigValue {
    param([string]$Value)
    if ($Value -match '[\r\n]') { throw '[AGENT_CURL_CONFIG] Transport value contains a line break.' }
    return $Value.Replace('\', '\\').Replace('"', '\"')
}

function Get-CDriveCurlErrorCode {
    param([int]$ExitCode)
    switch ($ExitCode) {
        6 { return 'AGENT_DNS_FAILED' }
        7 { return 'AGENT_CONNECT_FAILED' }
        28 { return 'AGENT_TIMEOUT' }
        35 { return 'AGENT_TLS_FAILED' }
        60 { return 'AGENT_CERTIFICATE_FAILED' }
        default { return 'AGENT_NETWORK_FAILED' }
    }
}

function Get-CDriveProviderHttpError {
    param([int]$StatusCode, [string[]]$BodyLines)
    $providerCode = ''
    try {
        $body = [string]::Join([Environment]::NewLine, $BodyLines)
        if ($body.Length -le 65536) {
            $payload = $body | ConvertFrom-Json
            $candidate = if ($payload.error.code) { [string]$payload.error.code } elseif ($payload.code) { [string]$payload.code } else { '' }
            if ($candidate -match '^[A-Za-z0-9_.-]{1,80}$') { $providerCode = $candidate }
        }
    } catch {}
    $suffix = if ($providerCode) { ':' + $providerCode } else { '' }
    return "[AGENT_HTTP_$StatusCode$suffix] Provider request failed."
}

function Invoke-CDriveCurlProvider {
    param($Config, $RequestBody, [string]$ApiKey, [string]$EventPath, [string]$TurnId)

    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($null -eq $curl) { throw '[AGENT_TRANSPORT_MISSING] Windows curl.exe is unavailable.' }
    $requestPath = Join-Path $env:TEMP ('cdc-agent-request-' + [guid]::NewGuid().ToString('N') + '.json')
    try {
        $json = $RequestBody | ConvertTo-Json -Depth 30 -Compress
        [System.IO.File]::WriteAllText($requestPath, $json, [System.Text.UTF8Encoding]::new($false))
        $endpoint = Get-CDriveProviderEndpoint $Config
        $configLines = @(
            'silent'
            'show-error'
            'no-buffer'
            'request = "POST"'
            ('url = "' + (ConvertTo-CDriveCurlConfigValue $endpoint) + '"')
            ('header = "Authorization: Bearer ' + (ConvertTo-CDriveCurlConfigValue $ApiKey) + '"')
            'header = "Content-Type: application/json"'
            ('data-binary = "@' + (ConvertTo-CDriveCurlConfigValue $requestPath) + '"')
            ('connect-timeout = "' + [Math]::Min(20, [int]$Config.timeoutSeconds) + '"')
            ('max-time = "' + [int]$Config.timeoutSeconds + '"')
            'write-out = "\n__CDC_HTTP_STATUS__:%{http_code}\n"'
        )

        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = [string]$curl.Source
        $startInfo.Arguments = '--config -'
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $startInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        if (-not $process.Start()) { throw '[AGENT_TRANSPORT_START] Secure transport did not start.' }
        try {
            $process.StandardInput.WriteLine(($configLines -join [Environment]::NewLine))
            $process.StandardInput.Close()
            $configLines = $null
            $bodyLines = New-Object System.Collections.Generic.List[string]
            $statusCode = 0
            while (-not $process.StandardOutput.EndOfStream) {
                $line = $process.StandardOutput.ReadLine()
                if ($line -match '^__CDC_HTTP_STATUS__:(\d{3})$') {
                    $statusCode = [int]$Matches[1]
                    continue
                }
                $bodyLines.Add($line)
                if ([bool]$Config.stream -and $line.StartsWith('data:')) {
                    $payload = $line.Substring(5).Trim()
                    if ($payload -ne '[DONE]') {
                        try {
                            $event = $payload | ConvertFrom-Json
                            $delta = if ([string]$Config.protocol -eq 'responses' -and [string]$event.type -eq 'response.output_text.delta') { [string]$event.delta } elseif ([string]$Config.protocol -ne 'responses') { [string]@($event.choices)[0].delta.content } else { '' }
                            if ($delta) { Write-CDriveAgentEvent $EventPath 'agent.text.delta' $TurnId ([PSCustomObject]@{ text = $delta }) }
                        } catch {}
                    }
                }
            }
            $errorText = $process.StandardError.ReadToEnd()
            $process.WaitForExit()
            if ($process.ExitCode -ne 0) {
                $code = Get-CDriveCurlErrorCode $process.ExitCode
                throw "[$code] Secure provider connection failed."
            }
            if ($statusCode -lt 200 -or $statusCode -ge 300) { throw (Get-CDriveProviderHttpError $statusCode $bodyLines.ToArray()) }
            if ([bool]$Config.stream) {
                return ConvertFrom-CDriveProviderSse $bodyLines.ToArray() ([string]$Config.protocol)
            }
            $body = [string]::Join([Environment]::NewLine, $bodyLines.ToArray())
            try { $payload = $body | ConvertFrom-Json }
            catch { throw '[AGENT_RESPONSE_JSON] Provider returned invalid JSON.' }
            return ConvertFrom-CDriveProviderResponse $payload ([string]$Config.protocol)
        } finally {
            if (-not $process.HasExited) { try { $process.Kill() } catch {} }
            $process.Dispose()
        }
    } finally {
        if (Test-Path -LiteralPath $requestPath -PathType Leaf) { Remove-Item -LiteralPath $requestPath -Force -ErrorAction SilentlyContinue }
    }
}

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
        try {
            $result = Invoke-CDriveCurlProvider $config $requestBody $apiKey $eventPath $turnId
        } finally {
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
