$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot

. (Join-Path $projectRoot 'core\RuleCatalog.ps1')
. (Join-Path $projectRoot 'core\EventProtocol.ps1')

$targets = @(Get-CDriveCleanupTargets)
if ($targets.Count -lt 40) { throw "Unexpected cleanup rule count: $($targets.Count)" }
$duplicates = @($targets | Group-Object { [string]$_['Id'] } | Where-Object Count -gt 1)
if ($duplicates.Count -gt 0) { throw 'Cleanup rule IDs are not unique.' }
if (@($targets | Where-Object DefaultSelected).Count -gt 0) { throw 'A cleanup rule is selected by default.' }
$userContent = @($targets | Where-Object UserContent)
if ($userContent.Count -ne 2) { throw "Expected exactly two bounded user-content rules, found $($userContent.Count)." }
if (@($userContent | Where-Object { $_.RecommendationLevel -ne 'Review' -or $_.SubDirs -match '(?i)FileRecv|Msg|db' }).Count -gt 0) {
    throw 'User-content rule boundary is unsafe.'
}
Write-Output "[OK] rule catalog -> $($targets.Count) stable rules"

$eventPath = Join-Path $env:TEMP ('cdc-event-contract-' + [guid]::NewGuid().ToString('N') + '.ndjson')
try {
    Initialize-CDriveEventStream $eventPath 'contract-test'
    Write-CDriveEvent 'operation.started' @{ mode = 'scan' }
    Write-CDriveEvent 'operation.completed' @{ status = 'passed' }
    $events = @(Get-Content -LiteralPath $eventPath -Encoding UTF8 | ForEach-Object { $_ | ConvertFrom-Json })
    if ($events.Count -ne 2 -or @($events | Where-Object schemaVersion -ne 1).Count -gt 0) { throw 'Event protocol output is invalid.' }
    if (@($events | Where-Object operationId -ne 'contract-test').Count -gt 0) { throw 'Event operation correlation is invalid.' }
    Write-Output '[OK] structured event protocol -> versioned NDJSON'
} finally {
    if (Test-Path -LiteralPath $eventPath) { Remove-Item -LiteralPath $eventPath -Force }
}

$assistantContract = Get-Content -LiteralPath (Join-Path $projectRoot 'contracts\assistant-tools.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($assistantContract.schemaVersion -ne 2 -or -not $assistantContract.policy.aiOptional -or -not $assistantContract.policy.strictToolSchemas) { throw 'AI tool policy must remain optional and strict.' }
$toolNames = @($assistantContract.tools | ForEach-Object name)
$forbidden = @($assistantContract.forbiddenCapabilities)
if (@($toolNames | Where-Object { $forbidden -contains $_ }).Count -gt 0) { throw 'AI exposes a forbidden capability.' }
$contractText = $assistantContract.tools | ConvertTo-Json -Depth 10 -Compress
if ($contractText -match '(?i)path|command|shell|powershell') { throw 'AI tool parameters expose paths or commands.' }
if ([string]$assistantContract.policy.finalCleanupApproval -ne 'user-interface-only') { throw 'AI must not own final cleanup approval.' }
foreach ($tool in @($assistantContract.tools)) {
    if ($tool.parameters.type -ne 'object' -or $tool.parameters.additionalProperties -ne $false) { throw "AI tool schema is not strict: $($tool.name)" }
}
Write-Output "[OK] AI tool boundary -> $($toolNames.Count) allowlisted tools"
