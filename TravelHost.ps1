[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RequestPath,
    [Parameter(Mandatory = $true)][string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
. (Join-Path $projectRoot 'core\FlyAiTravelProvider.ps1')

try {
    if (-not (Test-Path -LiteralPath $RequestPath -PathType Leaf)) { throw '[FLYAI_REQUEST] Travel request file is missing.' }
    $request = Get-Content -LiteralPath $RequestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $response = Invoke-CDriveFlyAiSearch -Query ([string]$request.query) -Mode ([string]$request.mode)
    $payload = [PSCustomObject]@{ ok = $true; response = $response }
} catch {
    $code = if ($_.Exception.Message -match '\[([A-Z0-9_]+)\]') { [string]$Matches[1] } else { 'FLYAI_FAILED' }
    $payload = [PSCustomObject]@{ ok = $false; errorCode = $code; message = [string]$_.Exception.Message }
}

[System.IO.File]::WriteAllText($OutputPath, ($payload | ConvertTo-Json -Depth 20 -Compress), [System.Text.UTF8Encoding]::new($false))
if (-not $payload.ok) { exit 1 }
