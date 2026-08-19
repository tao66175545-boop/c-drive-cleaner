$script:CDriveEventOutput = ''
$script:CDriveEventOperationId = ''

function Initialize-CDriveEventStream {
    param([string]$Path, [string]$OperationId)

    $script:CDriveEventOutput = [string]$Path
    $script:CDriveEventOperationId = [string]$OperationId
    if ([string]::IsNullOrWhiteSpace($script:CDriveEventOutput)) { return }

    $fullPath = [System.IO.Path]::GetFullPath($script:CDriveEventOutput)
    $directory = Split-Path -Parent $fullPath
    if ($directory) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    [System.IO.File]::WriteAllText($fullPath, '', (New-Object System.Text.UTF8Encoding($false)))
    $script:CDriveEventOutput = $fullPath
}

function Write-CDriveEvent {
    param(
        [Parameter(Mandatory = $true)][string]$Type,
        [hashtable]$Data = @{}
    )

    if ([string]::IsNullOrWhiteSpace($script:CDriveEventOutput)) { return }
    if ($Type -notmatch '^[a-z]+(?:\.[a-z]+)+$') { throw "Invalid event type: $Type" }

    $event = [ordered]@{
        schemaVersion = 1
        type = $Type
        operationId = $script:CDriveEventOperationId
        occurredAt = [DateTimeOffset]::UtcNow.ToString('o')
        data = $Data
    }
    $line = ($event | ConvertTo-Json -Depth 8 -Compress) + "`r`n"
    [System.IO.File]::AppendAllText($script:CDriveEventOutput, $line, (New-Object System.Text.UTF8Encoding($false)))
}
