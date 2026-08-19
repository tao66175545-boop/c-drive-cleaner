[CmdletBinding(DefaultParameterSetName = 'Generate')]
param(
    [Parameter(ParameterSetName = 'Generate')]
    [string]$OutputPath,

    [Parameter(ParameterSetName = 'Generate')]
    [string]$BaseCommit = '',

    [Parameter(Mandatory = $true, ParameterSetName = 'Verify')]
    [switch]$Verify,

    [Parameter(ParameterSetName = 'Verify')]
    [string]$ManifestPath
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$policyPath = Join-Path $projectRoot 'source-policy.json'
$versionPath = Join-Path $projectRoot 'version.json'

function Convert-ToRelativePath {
    param([string]$Path)

    $rootWithSeparator = $projectRoot.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if (-not $fullPath.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Source path is outside the project: $fullPath"
    }
    return $fullPath.Substring($rootWithSeparator.Length).Replace('\', '/')
}

function Get-Sha256Text {
    param([string]$Text)

    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        return ([BitConverter]::ToString($algorithm.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $algorithm.Dispose()
    }
}

function Get-GitBlobSha1 {
    param([string]$Path)

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $header = [System.Text.Encoding]::ASCII.GetBytes("blob $($bytes.Length)`0")
    $payload = New-Object byte[] ($header.Length + $bytes.Length)
    [Array]::Copy($header, 0, $payload, 0, $header.Length)
    [Array]::Copy($bytes, 0, $payload, $header.Length, $bytes.Length)
    $algorithm = [System.Security.Cryptography.SHA1]::Create()
    try {
        return ([BitConverter]::ToString($algorithm.ComputeHash($payload))).Replace('-', '').ToLowerInvariant()
    } finally {
        $algorithm.Dispose()
    }
}

if (-not (Test-Path -LiteralPath $policyPath)) { throw "Missing source policy: $policyPath" }
if (-not (Test-Path -LiteralPath $versionPath)) { throw "Missing version manifest: $versionPath" }

$policy = Get-Content -LiteralPath $policyPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($policy.schemaVersion -ne 1) { throw "Unsupported source policy schema: $($policy.schemaVersion)" }

$paths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($relativePath in @($policy.requiredFiles)) {
    $fullPath = Join-Path $projectRoot ([string]$relativePath)
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "Required public source file is missing: $relativePath"
    }
    [void]$paths.Add((Convert-ToRelativePath $fullPath))
}

foreach ($relativeDirectory in @($policy.requiredDirectories)) {
    $directoryPath = Join-Path $projectRoot ([string]$relativeDirectory)
    if (-not (Test-Path -LiteralPath $directoryPath -PathType Container)) {
        throw "Required public source directory is missing: $relativeDirectory"
    }
    foreach ($file in Get-ChildItem -LiteralPath $directoryPath -Recurse -File) {
        [void]$paths.Add((Convert-ToRelativePath $file.FullName))
    }
}

foreach ($pattern in @($policy.rootPatterns)) {
    $matches = @(Get-ChildItem -LiteralPath $projectRoot -File -Filter ([string]$pattern))
    if ($matches.Count -eq 0) { throw "Source policy pattern matched no files: $pattern" }
    foreach ($file in $matches) {
        [void]$paths.Add((Convert-ToRelativePath $file.FullName))
    }
}

[void]$paths.Remove('source-manifest.json')
$fileRecords = @(
    foreach ($relativePath in @($paths) | Sort-Object) {
        $fullPath = Join-Path $projectRoot $relativePath.Replace('/', '\')
        [ordered]@{
            path = $relativePath
            sha256 = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
            gitBlobSha1 = Get-GitBlobSha1 $fullPath
            size = (Get-Item -LiteralPath $fullPath).Length
        }
    }
)

$fingerprintInput = (($fileRecords | ForEach-Object { "$($_.path)`0$($_.sha256)" }) -join "`n") + "`n"
$fingerprint = Get-Sha256Text $fingerprintInput
$version = (Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8 | ConvertFrom-Json).version

if ($Verify) {
    if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
        $ManifestPath = Join-Path $projectRoot 'source-manifest.json'
    }
    if (-not (Test-Path -LiteralPath $ManifestPath)) { throw "Missing source manifest: $ManifestPath" }
    $expected = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

    if ($expected.schemaVersion -ne 1) { throw "Unsupported source manifest schema: $($expected.schemaVersion)" }
    if ([string]$expected.version -ne [string]$version) {
        throw "Source manifest version mismatch: manifest=$($expected.version), version.json=$version"
    }
    if ([string]$expected.sourceFingerprint -ne $fingerprint) {
        throw "Source fingerprint mismatch: manifest=$($expected.sourceFingerprint), actual=$fingerprint"
    }

    $expectedFiles = @($expected.files)
    if ($expectedFiles.Count -ne $fileRecords.Count) {
        throw "Source manifest file count mismatch: manifest=$($expectedFiles.Count), actual=$($fileRecords.Count)"
    }
    for ($index = 0; $index -lt $fileRecords.Count; $index++) {
        if ([string]$expectedFiles[$index].path -ne [string]$fileRecords[$index].path -or
            [string]$expectedFiles[$index].sha256 -ne [string]$fileRecords[$index].sha256 -or
            [string]$expectedFiles[$index].gitBlobSha1 -ne [string]$fileRecords[$index].gitBlobSha1 -or
            [long]$expectedFiles[$index].size -ne [long]$fileRecords[$index].size) {
            throw "Source manifest entry mismatch at index $index ($($fileRecords[$index].path))."
        }
    }

    [PSCustomObject]@{
        Version = [string]$version
        SourceFingerprint = $fingerprint
        FileCount = $fileRecords.Count
        BaseCommit = [string]$expected.baseCommit
    }
    return
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $projectRoot 'source-manifest.json'
}

$manifest = [ordered]@{
    schemaVersion = 1
    version = [string]$version
    baseCommit = [string]$BaseCommit
    sourceFingerprint = $fingerprint
    generatedAt = [DateTime]::UtcNow.ToString('o')
    files = $fileRecords
}
$json = $manifest | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText(
    [System.IO.Path]::GetFullPath($OutputPath),
    $json + "`r`n",
    (New-Object System.Text.UTF8Encoding($false))
)

[PSCustomObject]@{
    Version = [string]$version
    SourceFingerprint = $fingerprint
    FileCount = $fileRecords.Count
    BaseCommit = [string]$BaseCommit
    ManifestPath = [System.IO.Path]::GetFullPath($OutputPath)
}
