[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ScriptPath,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$ScriptArguments = @()
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$global:OutputEncoding = $utf8

if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
    throw 'Engine script does not exist.'
}

$command = Get-Command -Name $ScriptPath -ErrorAction Stop
$parameterNames = @{}
foreach ($name in @($command.Parameters.Keys)) { $parameterNames[$name.ToLowerInvariant()] = $name }
$boundArguments = @{}
$positionalArguments = @()
for ($index = 0; $index -lt $ScriptArguments.Count;) {
    $token = [string]$ScriptArguments[$index]
    if ($token -notmatch '^-(?<name>[A-Za-z][A-Za-z0-9]*)$') {
        $positionalArguments += $token
        $index++
        continue
    }

    $lookup = $Matches.name.ToLowerInvariant()
    if (-not $parameterNames.ContainsKey($lookup)) { throw 'Unknown engine parameter.' }
    $name = [string]$parameterNames[$lookup]
    if ($boundArguments.ContainsKey($name)) { throw 'Duplicate engine parameter.' }
    $metadata = $command.Parameters[$name]
    if ($metadata.ParameterType -eq [System.Management.Automation.SwitchParameter]) {
        $boundArguments[$name] = $true
        $index++
        continue
    }
    if (($index + 1) -ge $ScriptArguments.Count) { throw 'Engine parameter value is missing.' }
    $boundArguments[$name] = [string]$ScriptArguments[$index + 1]
    $index += 2
}

& $ScriptPath @boundArguments @positionalArguments
if (-not $?) { exit 1 }
exit 0
