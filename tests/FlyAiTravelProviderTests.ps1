$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot 'core\FlyAiTravelProvider.ps1')

if (-not (Test-CDriveTravelIntent 'find a hotel in Shanghai')) { throw 'English travel intent was not detected.' }
if (Test-CDriveTravelIntent 'clean recommended cache') { throw 'Cleanup intent leaked into the travel provider.' }

$quotedArgument = ConvertTo-CDriveProcessArgument 'plan "West Lake" trip'
if ($quotedArgument -ne '"plan \"West Lake\" trip"') { throw 'Windows process argument quoting is not strict.' }

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

Write-Output '[OK] FlyAI travel provider -> isolated intent, fixed command surface, read-only result formatting'
