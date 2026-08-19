function ConvertTo-CDriveHashtable {
    param($Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Collections.IDictionary]) {
        $result = @{}
        foreach ($key in $Value.Keys) { $result[[string]$key] = ConvertTo-CDriveHashtable $Value[$key] }
        return $result
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $result = @{}
        foreach ($property in $Value.PSObject.Properties) {
            $result[$property.Name] = ConvertTo-CDriveHashtable $property.Value
        }
        return $result
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        return @($Value | ForEach-Object { ConvertTo-CDriveHashtable $_ })
    }
    return $Value
}

function Expand-CDriveRuleValue {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) { return $Value }
    $allowed = @{
        TEMP = [string]$env:TEMP
        LOCALAPPDATA = [string]$env:LOCALAPPDATA
        USERPROFILE = [string]$env:USERPROFILE
        SYSTEMROOT = [string]$env:SystemRoot
    }
    $expanded = [regex]::Replace($Value, '\$\{(?<name>[A-Z]+)\}', {
        param($match)
        $name = $match.Groups['name'].Value
        if (-not $allowed.ContainsKey($name) -or [string]::IsNullOrWhiteSpace($allowed[$name])) {
            throw "Unsupported or unavailable rule variable: $name"
        }
        return $allowed[$name]
    })
    if ($expanded -match '\$\{') { throw "Unresolved rule variable in: $Value" }
    return $expanded
}

function Get-CDriveCleanupTargets {
    param([string]$CatalogPath)

    if ([string]::IsNullOrWhiteSpace($CatalogPath)) {
        $CatalogPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'rules\cleanup-rules.json'
    }
    if (-not (Test-Path -LiteralPath $CatalogPath -PathType Leaf)) { throw "Missing cleanup rule catalog: $CatalogPath" }
    $catalog = Get-Content -LiteralPath $CatalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$catalog.schemaVersion -ne 1) { throw "Unsupported cleanup rule schema: $($catalog.schemaVersion)" }

    $validTypes = @('FolderContents', 'Remove', 'PatternCache', 'RecycleBin', 'DNSCache', 'Detect', 'SpaceHog')
    $validLevels = @('Recommended', 'Review', 'NotRecommended')
    $ids = @{}
    $targets = @()
    foreach ($sourceRule in @($catalog.rules)) {
        $rule = ConvertTo-CDriveHashtable $sourceRule
        $id = [string]$rule.Id
        if ($id -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') { throw "Invalid cleanup rule ID: $id" }
        if ($ids.ContainsKey($id)) { throw "Duplicate cleanup rule ID: $id" }
        $ids[$id] = $true
        if ([string]::IsNullOrWhiteSpace([string]$rule.Name)) { throw "Cleanup rule name is missing: $id" }
        if ($validTypes -notcontains [string]$rule.Type) { throw "Invalid cleanup rule type for ${id}: $($rule.Type)" }
        if ($validLevels -notcontains [string]$rule.RecommendationLevel) { throw "Invalid recommendation level for ${id}: $($rule.RecommendationLevel)" }
        if ([string]::IsNullOrWhiteSpace([string]$rule.RecommendationLabel)) { throw "Recommendation label is missing: $id" }
        if ($rule.DefaultSelected -ne $false) { throw "Rules must not preselect cleanup actions: $id" }

        foreach ($field in @('Path', 'Pattern')) {
            if ($rule.ContainsKey($field)) { $rule[$field] = Expand-CDriveRuleValue ([string]$rule[$field]) }
        }
        if ([string]$rule.Type -in @('FolderContents', 'Remove', 'Detect', 'PatternCache') -and
            [string]::IsNullOrWhiteSpace([string]$rule.Path) -and [string]$rule.Type -notin @('RecycleBin', 'DNSCache')) {
            throw "Cleanup rule path is missing: $id"
        }
        if ([string]$rule.Type -eq 'PatternCache' -and [string]::IsNullOrWhiteSpace([string]$rule.SubDirs)) {
            throw "PatternCache subdirectories are missing: $id"
        }
        if ([bool]$rule.UserContent) {
            if ([string]$rule.RecommendationLevel -ne 'Review') { throw "User content must remain Review: $id" }
            if ([string]$rule.RecoveryMode -ne 'RecycleBin') { throw "User content must use the recoverable recycle-bin policy: $id" }
            if ([string]$rule.SubDirs -match '(?i)(^|[,\\/])(FileRecv|Msg|db)([,\\/]|$)') {
                throw "User content rule includes a protected data area: $id"
            }
        }
        $targets += $rule
    }
    if ($targets.Count -eq 0) { throw 'Cleanup rule catalog is empty.' }
    return $targets
}
