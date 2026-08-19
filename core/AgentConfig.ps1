function Get-CDriveAgentDataRoot {
    param([string]$Root = '')

    if (-not [string]::IsNullOrWhiteSpace($Root)) {
        return [System.IO.Path]::GetFullPath($Root)
    }
    return (Join-Path $env:LOCALAPPDATA 'CDriveCleaner\agent')
}

function Test-CDriveAgentBaseUrl {
    param([Parameter(Mandatory = $true)][string]$BaseUrl)

    $uri = $null
    if (-not [uri]::TryCreate($BaseUrl, [System.UriKind]::Absolute, [ref]$uri)) { return $false }
    if ($uri.UserInfo -or $uri.Fragment) { return $false }
    if ($uri.Scheme -eq 'https') { return $true }
    if ($uri.Scheme -ne 'http') { return $false }
    return $uri.IsLoopback -and $uri.Host -in @('localhost', '127.0.0.1', '::1')
}

function Assert-CDriveAgentConfig {
    param($Config)

    if ($null -eq $Config -or [int]$Config.schemaVersion -ne 1) { throw '[AGENT_CONFIG_SCHEMA] Unsupported provider configuration.' }
    if ([string]$Config.protocol -notin @('responses', 'chat-completions', 'text-only')) { throw '[AGENT_CONFIG_PROTOCOL] Unsupported provider protocol.' }
    if (-not (Test-CDriveAgentBaseUrl ([string]$Config.baseUrl))) { throw '[AGENT_CONFIG_URL] Base URL must use HTTPS or loopback HTTP.' }
    if ([string]::IsNullOrWhiteSpace([string]$Config.model) -or ([string]$Config.model).Length -gt 200) { throw '[AGENT_CONFIG_MODEL] A valid model name is required.' }
    if ([int]$Config.timeoutSeconds -lt 5 -or [int]$Config.timeoutSeconds -gt 300) { throw '[AGENT_CONFIG_TIMEOUT] Timeout must be between 5 and 300 seconds.' }
    if ([int]$Config.maxOutputTokens -lt 64 -or [int]$Config.maxOutputTokens -gt 32768) { throw '[AGENT_CONFIG_TOKENS] Output token limit is invalid.' }
    if ([string]$Config.providerId -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') { throw '[AGENT_CONFIG_PROVIDER] Provider ID is invalid.' }
    return $true
}

function Save-CDriveAgentConfig {
    param($Config, [string]$Path = '')

    $null = Assert-CDriveAgentConfig $Config
    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Join-Path (Get-CDriveAgentDataRoot) 'provider.json' }
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $directory = Split-Path -Parent $fullPath
    if ($directory) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $safe = [ordered]@{
        schemaVersion = 1
        providerId = [string]$Config.providerId
        protocol = [string]$Config.protocol
        baseUrl = ([string]$Config.baseUrl).TrimEnd('/')
        model = [string]$Config.model
        stream = [bool]$Config.stream
        timeoutSeconds = [int]$Config.timeoutSeconds
        maxOutputTokens = [int]$Config.maxOutputTokens
        credentialId = [string]$Config.credentialId
        cloudConsent = if ($null -ne $Config.cloudConsent) { $Config.cloudConsent } else { $null }
    }
    $json = $safe | ConvertTo-Json -Depth 6
    [System.IO.File]::WriteAllText($fullPath, $json + "`r`n", [System.Text.UTF8Encoding]::new($false))
    return $fullPath
}

function Get-CDriveAgentConfig {
    param([string]$Path = '')

    if ([string]::IsNullOrWhiteSpace($Path)) { $Path = Join-Path (Get-CDriveAgentDataRoot) 'provider.json' }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $config = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $null = Assert-CDriveAgentConfig $config
    return $config
}

function Get-CDriveAgentEntropy {
    return [System.Text.Encoding]::UTF8.GetBytes('CDriveCleaner.AgentCredential.v1')
}

function Set-CDriveAgentCredential {
    param(
        [Parameter(Mandatory = $true)][string]$ApiKey,
        [string]$CredentialId = 'default',
        [string]$Root = ''
    )

    if ([string]::IsNullOrWhiteSpace($ApiKey) -or $ApiKey.Length -gt 8192) { throw '[AGENT_CREDENTIAL_VALUE] API key is empty or too long.' }
    if ($CredentialId -notmatch '^[a-zA-Z0-9._-]{1,100}$') { throw '[AGENT_CREDENTIAL_ID] Credential ID is invalid.' }
    Add-Type -AssemblyName System.Security
    $dataRoot = Get-CDriveAgentDataRoot $Root
    New-Item -ItemType Directory -Path $dataRoot -Force | Out-Null
    $path = Join-Path $dataRoot ($CredentialId + '.credential')
    $plainBytes = [System.Text.Encoding]::UTF8.GetBytes($ApiKey)
    try {
        $protected = [System.Security.Cryptography.ProtectedData]::Protect($plainBytes, (Get-CDriveAgentEntropy), [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
        [System.IO.File]::WriteAllBytes($path, $protected)
    } finally {
        [Array]::Clear($plainBytes, 0, $plainBytes.Length)
    }
    return $path
}

function Get-CDriveAgentCredential {
    param([string]$CredentialId = 'default', [string]$Root = '')

    if ($CredentialId -notmatch '^[a-zA-Z0-9._-]{1,100}$') { throw '[AGENT_CREDENTIAL_ID] Credential ID is invalid.' }
    Add-Type -AssemblyName System.Security
    $path = Join-Path (Get-CDriveAgentDataRoot $Root) ($CredentialId + '.credential')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    $protected = [System.IO.File]::ReadAllBytes($path)
    $plainBytes = [System.Security.Cryptography.ProtectedData]::Unprotect($protected, (Get-CDriveAgentEntropy), [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
    try { return [System.Text.Encoding]::UTF8.GetString($plainBytes) }
    finally { [Array]::Clear($plainBytes, 0, $plainBytes.Length) }
}

function Remove-CDriveAgentCredential {
    param([string]$CredentialId = 'default', [string]$Root = '')

    $path = Join-Path (Get-CDriveAgentDataRoot $Root) ($CredentialId + '.credential')
    if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force }
}

function Get-CDriveAgentConfigFingerprint {
    param($Config)

    $null = Assert-CDriveAgentConfig $Config
    $text = '{0}|{1}|{2}|{3}' -f $Config.providerId, $Config.protocol, ([string]$Config.baseUrl).TrimEnd('/'), $Config.model
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($algorithm.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($text)))).Replace('-', '').ToLowerInvariant() }
    finally { $algorithm.Dispose() }
}

function Grant-CDriveAgentCloudConsent {
    param($Config)

    $Config | Add-Member -NotePropertyName cloudConsent -NotePropertyValue ([PSCustomObject]@{
        schemaVersion = 1
        configFingerprint = Get-CDriveAgentConfigFingerprint $Config
        privacyPolicyVersion = 1
        grantedAt = [DateTimeOffset]::UtcNow.ToString('o')
    }) -Force
    return $Config
}

function Test-CDriveAgentCloudConsent {
    param($Config)

    if ($null -eq $Config.cloudConsent -or [int]$Config.cloudConsent.privacyPolicyVersion -ne 1) { return $false }
    return [string]$Config.cloudConsent.configFingerprint -eq (Get-CDriveAgentConfigFingerprint $Config)
}
