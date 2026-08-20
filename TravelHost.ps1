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
    $query = [string]$request.query
    $response = $null
    $usedKeywordFallback = $false
    try {
        $response = Invoke-CDriveFlyAiSearch -Query $query -Mode ([string]$request.mode)
    } catch {
        if ([string]$request.mode -ne 'ai-search' -or $_.Exception.Message -notmatch 'FLYAI_EMPTY') { throw }
        $response = Invoke-CDriveFlyAiSearch -Query $query -Mode 'keyword-search' -TimeoutSeconds 45
        $usedKeywordFallback = $true
        $response | Add-Member -NotePropertyName fallbackReason -NotePropertyValue 'ai-search-empty'
    }
    if ([string]$request.mode -eq 'ai-search') {
        try {
            $visualResult = if ($usedKeywordFallback) { $response } else { Invoke-CDriveFlyAiSearch -Query $query -Mode 'keyword-search' -TimeoutSeconds 20 -MaxAttempts 1 }
            if (-not $usedKeywordFallback) { $response | Add-Member -NotePropertyName visualResult -NotePropertyValue $visualResult }
            $mediaDirectory = $OutputPath + '.media'
            $visualMedia = Save-CDriveFlyAiPreviewImages $visualResult $mediaDirectory
            $response | Add-Member -NotePropertyName visualMedia -NotePropertyValue @($visualMedia)
        } catch {
            # The readable itinerary remains usable when optional visual recommendations fail.
        }
    }
    $payload = [PSCustomObject]@{ ok = $true; response = $response }
} catch {
    $code = if ($_.Exception.Message -match '\[([A-Z0-9_]+)\]') { [string]$Matches[1] } else { 'FLYAI_FAILED' }
    $payload = [PSCustomObject]@{ ok = $false; errorCode = $code; message = [string]$_.Exception.Message }
}

[System.IO.File]::WriteAllText($OutputPath, ($payload | ConvertTo-Json -Depth 20 -Compress), [System.Text.UTF8Encoding]::new($false))
if (-not $payload.ok) { exit 1 }
