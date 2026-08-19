# ============================================================
#  C 盘扫描清理程序 (重构版)  C-Drive-Cleaner.ps1
#  功能：
#    1) 循环扫描并清理 20+ 类安全可清理项（临时文件、各类缓存、回收站等）
#    2) 检测休眠文件 / Windows.old / 页面文件等大占用项并给出处理提示
#    3) 空间剖析：递归找出任意层级的最大目录与最大文件
#    4) 空间大户诊断：识别大占用项并给出分类/风险分级/处方（卸载建议、应用内清理等，绝不自动删除）
#    5) 重复目录诊断：通配命中多份时，用子项名+大小廉价比对，标出可删副本（绝不自动删除）
#    6) 图形外壳：C-Drive-Cleaner-UI.ps1（双击 C盘清理.bat 启动；只调用本脚本）
#    7) 删除安全闸：保护路径黑名单 + 跳过 junction/symlink；-SelfTest 可自检
#  架构：
#    - handler 分发表（替代 switch，易扩展、Type 拼写错误会被显式拦截）
#    - 两阶段：先扫描汇总 -> 确认 -> 再清理
#    - 清理目标路径自动去重
#    - 大小统计过滤 reparse point（junction/symlink），避免重复/循环
#  用法：
#    一键入口：        双击 C盘清理.bat（打开图形界面）
#    安全闸自检：      powershell -ExecutionPolicy Bypass -File .\C-Drive-Cleaner.ps1 -SelfTest
#    扫描模式(默认)：  powershell -ExecutionPolicy Bypass -File .\C-Drive-Cleaner.ps1
#    清理模式：        powershell -ExecutionPolicy Bypass -File .\C-Drive-Cleaner.ps1 -Clean
#    清理(跳过确认)：  powershell -ExecutionPolicy Bypass -File .\C-Drive-Cleaner.ps1 -Clean -Force
#    仅处理某一项：    powershell -ExecutionPolicy Bypass -File .\C-Drive-Cleaner.ps1 -Category "Chrome"
#    全盘剖析：        powershell -ExecutionPolicy Bypass -File .\C-Drive-Cleaner.ps1 -FullScan
#    剖析指定目录：    powershell -ExecutionPolicy Bypass -File .\C-Drive-Cleaner.ps1 -Profile "C:\Users\admin\Downloads"
#    调阈值/数量：     powershell -ExecutionPolicy Bypass -File .\C-Drive-Cleaner.ps1 -MinSizeMB 500 -Top 20
#    导出诊断报告：    powershell -ExecutionPolicy Bypass -File .\C-Drive-Cleaner.ps1 -Report
#    系统级清理请以【管理员身份】运行 PowerShell。
# ============================================================

param(
    [switch]$Clean,                 # 是否真正执行清理（默认仅扫描报告）
    [switch]$Force,                 # 配合 -Clean 使用：跳过清理前的确认
    [string]$Category = "",         # 仅处理名称包含该关键字的清理项（子串匹配，不区分大小写）
    [int]$Top = 15,                 # 目录剖析/大文件显示数量
    [double]$MinSizeMB = 100,       # 大文件最小阈值(MB)
    [switch]$FullScan,              # 是否剖析整个 C 盘（默认仅用户目录）
    [string]$Profile = "",          # 指定要剖析的根目录（覆盖默认；如 -Profile "C:\Users\admin\Downloads"）
    [switch]$Report,                # 扫描结束后导出 HTML 诊断报告（写到用户本地数据目录）
    [string]$SelectionFile = "",    # UI 已勾选的项目 ID 清单；仅清理这些固定目标
    [string]$SelectionOutput = "",  # 扫描结果导出为 JSON，供 UI 展示与用户选择
    [string]$EventOutput = "",      # 版本化 NDJSON 事件流，供 UI/自动化读取结构化进度
    [switch]$SkipProfile,            # 快速清理扫描：跳过用户目录空间剖析，仅扫描固定规则项
    [switch]$SelfTest               # 仅运行安全闸自检后退出（不扫描、不删除）
)

$ErrorActionPreference = 'SilentlyContinue'

# 程序目录保持可替换；报告等可变数据写入用户本地数据目录。
$localDataRoot = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'CDriveCleaner' } else { Join-Path $env:TEMP 'CDriveCleaner' }
$reportDirectory = Join-Path $localDataRoot 'reports'
$reportPath = Join-Path $reportDirectory 'C盘清理诊断报告.html'
$operationId = [guid]::NewGuid().ToString('N')
$ruleCatalogModule = Join-Path $PSScriptRoot 'core\RuleCatalog.ps1'
$eventProtocolModule = Join-Path $PSScriptRoot 'core\EventProtocol.ps1'
$scanProviderModule = Join-Path $PSScriptRoot 'core\ScanProvider.ps1'
$incrementalScanModule = Join-Path $PSScriptRoot 'core\IncrementalScanIndex.ps1'
$operationJournalModule = Join-Path $PSScriptRoot 'core\OperationJournal.ps1'
$executionBrokerModule = Join-Path $PSScriptRoot 'core\ExecutionBroker.ps1'
if (-not (Test-Path -LiteralPath $ruleCatalogModule) -or -not (Test-Path -LiteralPath $eventProtocolModule) -or
    -not (Test-Path -LiteralPath $scanProviderModule) -or -not (Test-Path -LiteralPath $incrementalScanModule) -or -not (Test-Path -LiteralPath $operationJournalModule) -or
    -not (Test-Path -LiteralPath $executionBrokerModule)) {
    Write-Host '错误：缺少核心契约模块，程序无法安全启动。' -ForegroundColor Red
    exit 1
}
. $ruleCatalogModule
. $eventProtocolModule
. $scanProviderModule
. $incrementalScanModule
. $operationJournalModule
. $executionBrokerModule
Initialize-CDriveEventStream $EventOutput $operationId
Write-CDriveEvent 'operation.started' @{ mode = $(if ($SelfTest) { 'self-test' } elseif ($Clean) { 'clean' } else { 'scan' }) }

# ---------- 工具函数 ----------
function Format-Bytes {
    param([double]$Bytes)
    if ($Bytes -ge 1GB) { return ("{0:F2} GB" -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ("{0:F2} MB" -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ("{0:F2} KB" -f ($Bytes / 1KB)) }
    return ("{0:N0} B" -f $Bytes)
}

function Encode-Html {
    param($Value)
    if ($null -eq $Value) { return '' }
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

# 计算目录大小：递归统计文件长度，过滤 reparse point（junction/symlink）避免重复
function Get-DirSize {
    param([string]$Path)
    return [double](Measure-CDrivePathSize $Path).Size
}

# 统一计算路径大小（兼容单个文件与目录）
function Get-PathSize {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return 0.0 }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) { return 0.0 }
    if (-not $item.PSIsContainer) { return [double]$item.Length }
    return Get-DirSize $Path
}

# 清理路径安全闸：拒绝盘根/系统根/用户主目录/脚本目录及其祖先，防止清单写错导致灾难性删除
function Test-SafeCleanPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $fullNorm = $null
    try { $fullNorm = [System.IO.Path]::GetFullPath($Path).TrimEnd('\').ToLowerInvariant() } catch { return $false }
    if (-not $fullNorm -or $fullNorm.Length -lt 4) { return $false }

    $protected = @(
        'c:',
        'c:\windows',
        'c:\windows\system32',
        'c:\windows\syswow64',
        'c:\users',
        'c:\program files',
        'c:\program files (x86)',
        'c:\programdata'
    )
    if ($env:SystemRoot) { $protected += $env:SystemRoot.TrimEnd('\').ToLowerInvariant() }
    if ($env:USERPROFILE) { $protected += $env:USERPROFILE.TrimEnd('\').ToLowerInvariant() }
    if ($PSScriptRoot) { $protected += $PSScriptRoot.TrimEnd('\').ToLowerInvariant() }

    foreach ($p in $protected) {
        if (-not $p) { continue }
        if ($fullNorm -eq $p) { return $false }
        if ($p.StartsWith($fullNorm + '\')) { return $false }
    }
    return $true
}

function Test-ReparsePoint {
    param($Item)
    if ($null -eq $Item) { return $false }
    try { return (([int]$Item.Attributes -band 0x400) -ne 0) } catch { return $false }
}

# 删除文件夹内的所有内容（保留文件夹本身），返回释放量与失败项数
function Clear-FolderContents {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return [PSCustomObject]@{ Freed = 0.0; Failed = 0 } }
    if (-not (Test-SafeCleanPath $Path)) { return [PSCustomObject]@{ Freed = 0.0; Failed = 1 } }
    $before = Get-PathSize $Path
    $failed = 0
    Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if (Test-ReparsePoint $_) { return }
        try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop }
        catch { $failed++ }
    }
    $after = Get-PathSize $Path
    return [PSCustomObject]@{ Freed = [double]($before - $after); Failed = $failed }
}

# 删除指定路径本身（文件或目录），返回释放量与失败数
function Remove-Target {
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return [PSCustomObject]@{ Freed = 0.0; Failed = 0 } }
    if (-not (Test-SafeCleanPath $Path)) { return [PSCustomObject]@{ Freed = 0.0; Failed = 1 } }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if (Test-ReparsePoint $item) { return [PSCustomObject]@{ Freed = 0.0; Failed = 1 } }
    $before = Get-PathSize $Path
    $failed = 0
    try { Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop }
    catch { $failed = 1 }
    $after = Get-PathSize $Path
    return [PSCustomObject]@{ Freed = [double]($before - $after); Failed = $failed }
}

# 空间剖析：一次枚举同时完成"大文件收集"与"目录子树大小聚合"
# 算法（两遍法，性能 O(文件数 + 目录数)）：
#   第1遍 LOOP：遍历每个文件 -> 累加到其"直接父目录"
#   第2遍 LOOP：目录按深度自底向上累加子树大小（避免逐文件向上遍历的 O(文件数×深度)）
function Get-SpaceProfile {
    param([string]$Root, [int]$Top, [double]$MinMB)
    $min = $MinMB * 1MB
    $rootKey = $Root.TrimEnd('\').ToLowerInvariant()
    $direct = @{}          # 目录 -> 直接文件大小
    $bigFiles = New-Object System.Collections.ArrayList
    $fileCount = 0

    # 第1遍：一次枚举，收集大文件 + 直接目录大小
    # 注意：必须先 @() 完整收集再遍历；若 foreach 直接包裹 Get-ChildItem，
    #       枚举途中遇 Win32Exception（失效 junction/临时文件）会中断流，导致漏统计
    $allFiles = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force -ErrorAction SilentlyContinue)
    foreach ($file in $allFiles) {
        $fileCount++
        if ($file.Length -ge $min) { [void]$bigFiles.Add($file) }
        $d = $file.DirectoryName
        if ($direct.ContainsKey($d)) { $direct[$d] += $file.Length }
        else { $direct[$d] = [double]$file.Length }
    }

    # 第2遍：自底向上累加子树大小（剖析根本身不再往上累加，避免统计到其祖先）
    $subtree = @{}
    $dirs = @($direct.Keys) | Sort-Object { ($_ -split '\\').Count } -Descending
    foreach ($d in $dirs) {
        $s = $direct[$d]
        if ($subtree.ContainsKey($d)) { $s += $subtree[$d] }
        $subtree[$d] = $s
        if ($d.ToLowerInvariant() -eq $rootKey) { continue }
        $parent = Split-Path -Path $d -Parent
        if ($parent) {
            if ($subtree.ContainsKey($parent)) { $subtree[$parent] += $s }
            else { $subtree[$parent] = $s }
        }
    }

    # 排除剖析根本身，只展示其内部子目录
    $topDirs = @($subtree.GetEnumerator() | Where-Object { $_.Key.ToLowerInvariant() -ne $rootKey } | Sort-Object Value -Descending | Select-Object -First $Top | ForEach-Object {
        [PSCustomObject]@{ FullName = $_.Key; Size = $_.Value }
    })
    $topFiles = @($bigFiles | Sort-Object Length -Descending | Select-Object -First $Top)

    return [PSCustomObject]@{ TopDirs = $topDirs; TopFiles = $topFiles; FileCount = $fileCount }
}

# 廉价目录指纹：只看直接子项名称集合 + 已有大小，不递归、不做全量 MD5
function Get-DirLiteFingerprint {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $children = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
    $names = @($children | ForEach-Object { $_.Name } | Sort-Object)
    return [PSCustomObject]@{
        Path       = $Path
        NameKey    = ($names -join '|')
        ChildCount = $children.Count
    }
}

# 在一组路径中选“更像主副本”的那条：不含 backup/old/copy/ide 的优先，其次路径更短
function Select-CanonicalPath {
    param([string[]]$Paths)
    $best = $null
    $bestPenalty = 999
    $bestLen = 99999
    foreach ($p in $Paths) {
        $n = $p.ToLowerInvariant()
        $penalty = 0
        if ($n -match 'backup|bak|\bold\b|copy|-ide') { $penalty++ }
        $len = $p.Length
        if (($penalty -lt $bestPenalty) -or (($penalty -eq $bestPenalty) -and ($len -lt $bestLen))) {
            $best = $p
            $bestPenalty = $penalty
            $bestLen = $len
        }
    }
    return $best
}

# 在已带 Size 的匹配项中找出“子项名集合 + 大小完全一致”的重复组（仅诊断）
function Find-DuplicateDirGroups {
    param($Matches, [double]$MinBytes = 10MB)
    $items = @()
    foreach ($m in @($Matches)) {
        if (-not $m.FullName) { continue }
        if ($m.Size -lt $MinBytes) { continue }
        $fp = Get-DirLiteFingerprint $m.FullName
        if ($null -eq $fp) { continue }
        $items += [PSCustomObject]@{
            Path       = $m.FullName
            Size       = [double]$m.Size
            NameKey    = $fp.NameKey
            ChildCount = $fp.ChildCount
        }
    }
    if ($items.Count -lt 2) { return @() }

    $buckets = @{}
    foreach ($it in $items) {
        $key = "{0}#{1}" -f $it.NameKey, $it.Size
        if (-not $buckets.ContainsKey($key)) { $buckets[$key] = @() }
        $buckets[$key] += $it
    }

    $result = @()
    foreach ($key in $buckets.Keys) {
        $group = @($buckets[$key])
        if ($group.Count -lt 2) { continue }
        $allPaths = @($group | ForEach-Object { $_.Path })
        $keep = Select-CanonicalPath $allPaths
        $drops = @($allPaths | Where-Object { $_ -ne $keep })
        $waste = 0.0
        foreach ($d in $drops) {
            $hit = $group | Where-Object { $_.Path -eq $d } | Select-Object -First 1
            if ($hit) { $waste += $hit.Size }
        }
        $result += [PSCustomObject]@{
            Keep       = $keep
            Drops      = $drops
            CopyCount  = $group.Count
            EachSize   = $group[0].Size
            Waste      = $waste
            ChildCount = $group[0].ChildCount
        }
    }
    return $result
}

# ---------- 清理目标清单 ----------
# Type 说明：
#   FolderContents : 清空文件夹内容、保留文件夹（临时目录/缓存）
#   Remove         : 删除文件夹/文件本身
#   PatternCache   : 遍历父目录下各子目录内的指定缓存子目录（如浏览器 profile 缓存）
#   RecycleBin     : 清空回收站
#   DNSCache       : 刷新 DNS 缓存
#   Detect         : 仅检测大小并提示手动处理方式（不自动删除）
#   SpaceHog       : 空间大户诊断——识别大占用项并给出分类/风险/处方（绝不自动删除）
# RequiresAdmin   : 是否必须管理员权限
$CleanupTargets = @(Get-CDriveCleanupTargets)

# ---------- 清单校验与去重（fail fast，避免拼写错误静默误删 / 重复统计）----------
$validTypes = @('FolderContents', 'Remove', 'PatternCache', 'RecycleBin', 'DNSCache', 'Detect', 'SpaceHog')
foreach ($t in $CleanupTargets) {
    if ($validTypes -notcontains $t.Type) {
        Write-Host ("错误：清理目标 '{0}' 的类型 '{1}' 无效，已中止（请检查清单拼写）" -f $t.Name, $t.Type) -ForegroundColor Red
        exit 1
    }
}

$seen = @{}
$deduped = @()
foreach ($t in $CleanupTargets) {
    # 同一根目录可承载不同的受限子目录（如应用根目录诊断与图片附件候选项），去重必须包含类型和子目录规则。
    $key = if ($t.Path) { ('{0}|{1}|{2}' -f $t.Type, $t.Path.ToLowerInvariant(), [string]$t.SubDirs) } elseif ($t.Pattern) { ('{0}|{1}' -f $t.Type, $t.Pattern.ToLowerInvariant()) } else { $t.Type }
    if (-not $seen.ContainsKey($key)) {
        $seen[$key] = $true
        $deduped += $t
    }
}
$CleanupTargets = $deduped

# 为 UI 与命令行选择提供稳定 ID。所有目标必须显式声明 ID，禁止按列表位置生成。
$missingIds = @($CleanupTargets | Where-Object { [string]::IsNullOrWhiteSpace([string]$_['Id']) })
if ($missingIds.Count -gt 0) {
    Write-Host ('错误：清理目标缺少稳定 ID：' + (($missingIds | ForEach-Object Name) -join '、')) -ForegroundColor Red
    exit 1
}
$idCounts = @{}
foreach ($target in $CleanupTargets) {
    $id = [string]$target['Id']
    if (-not $idCounts.ContainsKey($id)) { $idCounts[$id] = 0 }
    $idCounts[$id]++
}
$duplicateIds = @($idCounts.GetEnumerator() | Where-Object Value -gt 1 | ForEach-Object Key)
if ($duplicateIds.Count -gt 0) {
    Write-Host ('错误：清理目标存在重复 ID：' + ($duplicateIds -join '、')) -ForegroundColor Red
    exit 1
}
$cleanupTargetById = @{}
foreach ($t in $CleanupTargets) { $cleanupTargetById[[string]$t['Id']] = $t }

$targetManifest = @($CleanupTargets | ForEach-Object {
    [ordered]@{
        Id = [string]$_['Id']
        Type = [string]$_['Type']
        Path = [string]$_['Path']
        Pattern = [string]$_['Pattern']
        SubDirs = [string]$_['SubDirs']
        RequiresAdmin = [bool]$_['RequiresAdmin']
        RecoveryMode = [string]$_['RecoveryMode']
    }
} | ConvertTo-Json -Depth 5 -Compress)
$sha256 = [System.Security.Cryptography.SHA256]::Create()
try {
    $targetManifestHashBytes = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($targetManifest))
    $targetManifestHash = -join @($targetManifestHashBytes | ForEach-Object { $_.ToString('x2') })
} finally {
    $sha256.Dispose()
}
$scanId = [guid]::NewGuid().ToString('N')

function Get-CleanupRecommendation {
    param($Target)
    return [PSCustomObject]@{
        Label = [string]$Target.RecommendationLabel
        Level = [string]$Target.RecommendationLevel
        Advice = [string]$Target.Advice
    }
}

$selectedTargetIds = $null
$expectedSizeById = @{}
if ($SelectionFile) {
    if (-not (Test-Path -LiteralPath $SelectionFile)) {
        Write-Host ('错误：找不到选择清单：' + $SelectionFile) -ForegroundColor Red
        exit 1
    }
    try {
        $selectionPayload = Get-Content -LiteralPath $SelectionFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([int]$selectionPayload.SchemaVersion -ne 2) {
            throw '[PLAN_SCHEMA] 清理计划版本不受支持，请重新扫描。'
        }
        if ([string]$selectionPayload.ManifestHash -ne $targetManifestHash) {
            throw '[PLAN_MANIFEST] 清理计划与当前清理规则不一致，请重新扫描。'
        }
        if ([string]$selectionPayload.ScanId -notmatch '^[a-fA-F0-9]{32}$') {
            throw '[PLAN_SCAN_ID] 清理计划缺少扫描编号，请重新扫描。'
        }
        $scannedAt = [DateTimeOffset]::MinValue
        if (-not [DateTimeOffset]::TryParse([string]$selectionPayload.ScannedAt, [ref]$scannedAt)) {
            throw '[PLAN_SCANNED_AT] 清理计划缺少有效的扫描时间，请重新扫描。'
        }
        $nowUtc = [DateTimeOffset]::UtcNow
        if ($scannedAt.ToUniversalTime() -gt $nowUtc.AddMinutes(5)) {
            throw '[PLAN_CLOCK] 清理计划时间晚于当前系统时间，请检查时钟并重新扫描。'
        }
        if ($nowUtc - $scannedAt.ToUniversalTime() -gt [TimeSpan]::FromMinutes(30)) {
            throw '[PLAN_EXPIRED] 清理计划已超过 30 分钟，请重新扫描以确认当前内容。'
        }
        $requestedIds = @($selectionPayload.SelectedIds | Where-Object { $_ })
        $selectedTargetIds = @{}
        foreach ($id in $requestedIds) { $selectedTargetIds[[string]$id] = $true }
        foreach ($item in @($selectionPayload.Items)) {
            if ($item.Id -and $null -ne $item.Size -and [double]$item.Size -ge 0) {
                $expectedSizeById[[string]$item.Id] = [double]$item.Size
            }
        }
        $missingSnapshots = @($requestedIds | Where-Object { -not $expectedSizeById.ContainsKey([string]$_) })
        if ($missingSnapshots.Count -gt 0) {
            throw ('[PLAN_SNAPSHOT] 清理计划缺少项目快照：' + ($missingSnapshots -join ', '))
        }
    } catch {
        Write-Host ('错误：选择清单格式无效：' + $_.Exception.Message) -ForegroundColor Red
        exit 1
    }
    $knownTargetIds = @{}
    foreach ($target in $CleanupTargets) { $knownTargetIds[[string]$target.Id] = $true }
    $unknownIds = @($selectedTargetIds.Keys | Where-Object { -not $knownTargetIds.ContainsKey($_) })
    if ($unknownIds.Count -gt 0) {
        Write-Host ('错误：选择清单包含未知项目 ID：' + ($unknownIds -join ', ')) -ForegroundColor Red
        exit 1
    }
    if ($Clean -and $selectedTargetIds.Count -eq 0) {
        Write-Host '未选择任何清理项，已取消，不会删除文件。' -ForegroundColor Yellow
        exit 0
    }
}
if ($Clean -and [string]::IsNullOrWhiteSpace($SelectionFile)) {
    Write-CDriveEvent 'operation.failed' @{ code = 'PLAN_REQUIRED' }
    Write-Host '错误：[PLAN_REQUIRED] 清理必须使用本次扫描生成的选择清单；未执行任何删除。' -ForegroundColor Red
    exit 1
}

# ---------- Handler 分发表 ----------
# 每个 handler 接收 (target, action)，action ∈ { scan, clean }，返回统一结构：
#   @{ Size; Freed; Failed; Detected; Hint; Note }
$Handlers = @{
    'FolderContents' = {
        param($t, $a)
        if ($a -eq 'scan') {
            return [PSCustomObject]@{ Size = (Get-PathSize $t.Path); Freed = 0.0; Failed = 0; Detected = $false; Hint = ''; Note = '' }
        }
        if (-not (Test-Path -LiteralPath $t.Path)) { return [PSCustomObject]@{ Size = 0; Freed = 0.0; Failed = 0; Detected = $false; Hint = ''; Note = '' } }
        $cr = Clear-FolderContents $t.Path
        return [PSCustomObject]@{ Size = 0; Freed = $cr.Freed; Failed = $cr.Failed; Detected = $false; Hint = ''; Note = '' }
    }
    'Remove' = {
        param($t, $a)
        if ($a -eq 'scan') {
            return [PSCustomObject]@{ Size = (Get-PathSize $t.Path); Freed = 0.0; Failed = 0; Detected = $false; Hint = ''; Note = '' }
        }
        if (-not (Test-Path -LiteralPath $t.Path)) { return [PSCustomObject]@{ Size = 0; Freed = 0.0; Failed = 0; Detected = $false; Hint = ''; Note = '' } }
        $cr = Remove-Target $t.Path
        return [PSCustomObject]@{ Size = 0; Freed = $cr.Freed; Failed = $cr.Failed; Detected = $false; Hint = ''; Note = '' }
    }
    'PatternCache' = {
        param($t, $a)
        $parent = $t.Path
        $subs = ($t.SubDirs -split ',') | ForEach-Object { $_.Trim() }
        $subPaths = @()
        if (Test-Path -LiteralPath $parent) {
            Get-ChildItem -LiteralPath $parent -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
                foreach ($s in $subs) {
                    $sp = Join-Path $_.FullName $s
                    if (Test-Path -LiteralPath $sp) { $subPaths += $sp }
                }
            }
        }
        if ($a -eq 'scan') {
            $size = 0.0
            foreach ($sp in $subPaths) { $size += Get-PathSize $sp }
            return [PSCustomObject]@{ Size = $size; Freed = 0.0; Failed = 0; Detected = $false; Hint = ''; Note = ("缓存目录数: {0}" -f @($subPaths).Count) }
        }
        $freed = 0.0; $failed = 0
        foreach ($sp in $subPaths) {
            $cr = Clear-FolderContents $sp
            $freed += $cr.Freed; $failed += $cr.Failed
        }
        return [PSCustomObject]@{ Size = 0; Freed = $freed; Failed = $failed; Detected = $false; Hint = ''; Note = '' }
    }
    'RecycleBin' = {
        param($t, $a)
        $rbSize = 0.0
        foreach ($d in [System.IO.DriveInfo]::GetDrives()) {
            if ($d.DriveType -eq 'Fixed') {
                $rbPath = Join-Path $d.Name '$Recycle.Bin'
                if (Test-Path -LiteralPath $rbPath) { $rbSize += Get-PathSize $rbPath }
            }
        }
        if ($a -eq 'scan') {
            return [PSCustomObject]@{ Size = $rbSize; Freed = 0.0; Failed = 0; Detected = $false; Hint = ''; Note = '' }
        }
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        return [PSCustomObject]@{ Size = 0; Freed = $rbSize; Failed = 0; Detected = $false; Hint = ''; Note = '' }
    }
    'DNSCache' = {
        param($t, $a)
        if ($a -eq 'scan') {
            return [PSCustomObject]@{ Size = 0; Freed = 0.0; Failed = 0; Detected = $false; Hint = ''; Note = '内存缓存，不计入磁盘' }
        }
        & ipconfig /flushdns | Out-Null
        return [PSCustomObject]@{ Size = 0; Freed = 0.0; Failed = 0; Detected = $false; Hint = ''; Note = '已刷新 DNS 缓存' }
    }
    'Detect' = {
        param($t, $a)
        $size = Get-PathSize $t.Path
        $exists = Test-Path -LiteralPath $t.Path
        return [PSCustomObject]@{ Size = $size; Freed = 0.0; Failed = 0; Detected = $true; Hint = $t.Hint; Note = '' }
    }
    'SpaceHog' = {
        param($t, $a)
        # 匹配实际存在的路径（Pattern 支持通配符，如 Claude_* 动态包名）
        $matches = @()
        if ($t.Pattern) {
            if ($t.Pattern -match '[\*\?]') {
                # 含通配符：Get-ChildItem 返回匹配到的项本身
                $matches = @(Get-ChildItem -Path $t.Pattern -Force -ErrorAction SilentlyContinue)
            } else {
                # 无通配符：Get-Item 返回项本身（避免 Get-ChildItem 展开成目录内容）
                $item = Get-Item -LiteralPath $t.Pattern -Force -ErrorAction SilentlyContinue
                if ($item) { $matches = @($item) }
            }
        }
        # 统计总大小（仅诊断，绝不删除）；每个匹配带 Size，供后续重复检测复用
        $size = 0.0
        $enriched = @()
        foreach ($m in $matches) {
            $sz = Get-PathSize $m.FullName
            $size += $sz
            $enriched += [PSCustomObject]@{ FullName = $m.FullName; Size = $sz }
        }
        return [PSCustomObject]@{
            Size     = $size
            Freed    = 0.0
            Failed   = 0
            Detected = $true
            Hint     = $t.Advice
            Note     = ("{0} | 风险：{1}" -f $t.Category, $t.Risk)
            Matches  = $enriched
        }
    }
}

if ($SelfTest) {
    $fail = 0
    $cases = @(
        @{ Name = '盘根 C:\'; Path = 'C:\'; Expect = $false }
        @{ Name = '用户主目录'; Path = $env:USERPROFILE; Expect = $false }
        @{ Name = 'Windows 目录'; Path = $env:SystemRoot; Expect = $false }
        @{ Name = '脚本自身目录'; Path = $PSScriptRoot; Expect = $false }
        @{ Name = '用户 Temp'; Path = "$env:LOCALAPPDATA\Temp"; Expect = $true }
        @{ Name = 'Windows\Temp'; Path = 'C:\Windows\Temp'; Expect = $true }
        @{ Name = 'NVIDIA DXCache'; Path = "$env:LOCALAPPDATA\NVIDIA\DXCache"; Expect = $true }
    )
    foreach ($c in $cases) {
        $got = Test-SafeCleanPath $c.Path
        $ok = ($got -eq $c.Expect)
        if (-not $ok) { $fail++ }
        $mark = if ($ok) { 'OK' } else { 'FAIL' }
        Write-Host ("[{0}] {1}  path={2}  safe={3}  expect={4}" -f $mark, $c.Name, $c.Path, $got, $c.Expect)
    }
    $mediaTargets = @($CleanupTargets | Where-Object { $_.UserContent })
    $mediaOk = $mediaTargets.Count -eq 2
    foreach ($target in $mediaTargets) {
        $mediaOk = $mediaOk -and ($target.Type -eq 'PatternCache') -and ($target.SubDirs -notmatch 'FileRecv|Msg|db') -and ((Get-CleanupRecommendation $target).Level -eq 'Review')
    }
    if (-not $mediaOk) { $fail++ }
    $mediaMark = if ($mediaOk) { 'OK' } else { 'FAIL' }
    Write-Host ("[{0}] 用户图片/视频候选项  count={1}  bounded={2}" -f $mediaMark, $mediaTargets.Count, $mediaOk)
    $stableIdsOk = ($missingIds.Count -eq 0) -and ($duplicateIds.Count -eq 0) -and
        (@($CleanupTargets | Where-Object { [string]$_['Id'] -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$' }).Count -eq 0)
    if (-not $stableIdsOk) { $fail++ }
    $stableIdsMark = if ($stableIdsOk) { 'OK' } else { 'FAIL' }
    Write-Host ("[{0}] 稳定清理目标 ID  count={1}  unique={2}" -f $stableIdsMark, $CleanupTargets.Count, ($duplicateIds.Count -eq 0))
    $manifestOk = $targetManifestHash -match '^[a-f0-9]{64}$'
    if (-not $manifestOk) { $fail++ }
    $manifestMark = if ($manifestOk) { 'OK' } else { 'FAIL' }
    Write-Host ("[{0}] 清理规则清单哈希  sha256={1}" -f $manifestMark, $targetManifestHash)
    $dataPathOk = $reportPath.StartsWith($localDataRoot, [System.StringComparison]::OrdinalIgnoreCase) -and
        -not $reportPath.StartsWith($PSScriptRoot, [System.StringComparison]::OrdinalIgnoreCase)
    if (-not $dataPathOk) { $fail++ }
    $dataPathMark = if ($dataPathOk) { 'OK' } else { 'FAIL' }
    Write-Host ("[{0}] 报告目录与程序目录分离  path={1}" -f $dataPathMark, $reportPath)
    if ($fail -gt 0) {
        Write-CDriveEvent 'operation.failed' @{ code = 'SELF_TEST_FAILED'; failures = $fail }
        Write-Host ("SelfTest 失败 {0} 项" -f $fail) -ForegroundColor Red
        exit 1
    }
    Write-CDriveEvent 'operation.completed' @{ status = 'passed'; mode = 'self-test'; ruleCount = $CleanupTargets.Count; manifestHash = $targetManifestHash }
    Write-Host "SelfTest 通过" -ForegroundColor Green
    exit 0
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$incrementalSession = $null
if (-not $Clean) {
    $incrementalSession = New-CDriveIncrementalSession (Join-Path $localDataRoot 'scan-index-v1.json') $targetManifestHash 'C:'
    Write-CDriveEvent 'scan.provider.selected' @{ provider = [string]$incrementalSession.Mode; reason = [string]$incrementalSession.Reason }
}
$operationJournal = $null
$executionContext = $null
if ($Clean) {
    try {
        $executionContext = New-CDriveExecutionContext $CleanupTargets @($selectedTargetIds.Keys) $isAdmin
        $operationJournal = New-CDriveOperationJournal (Join-Path $localDataRoot 'journals') $operationId $targetManifestHash @($selectedTargetIds.Keys) $isAdmin
        $executionContext.Journal = $operationJournal
        Write-Host ('  操作日志：' + $operationJournal.Path) -ForegroundColor DarkGray
    } catch {
        Write-CDriveEvent 'operation.failed' @{ code = 'BROKER_PLAN_REJECTED'; message = $_.Exception.Message }
        Write-Host ('错误：执行代理拒绝清理计划：' + $_.Exception.Message) -ForegroundColor Red
        exit 1
    }
}

# 记录清理前磁盘可用空间（用于清理后对比）
# 注：受限环境下 Get-PSDrive 的 Free 属性不可用，改用 System.IO.DriveInfo
$driveFreeBefore = (New-Object System.IO.DriveInfo 'C:\').AvailableFreeSpace

Write-Host ""
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "  C 盘扫描清理程序（重构版）" -ForegroundColor Cyan
if ($Clean) { Write-Host "  模式：清理（将真正删除文件）" -ForegroundColor Yellow }
else        { Write-Host "  模式：扫描（仅统计，不删除任何文件）" -ForegroundColor Green }
Write-Host "  管理员权限：$(if ($isAdmin) { '是' } else { '否' })"
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host ""

$totalCleanable = 0.0
$totalDetected  = 0.0
$totalFreed     = 0.0
$totalStagedForRecovery = 0.0
$totalFailed    = 0
$skippedCount   = 0
$totalDupWaste  = 0.0
$dupResults     = @()
$profileData    = [PSCustomObject]@{ Root = ''; FileCount = 0; TopDirs = @(); TopFiles = @() }

$scanResults = @()
$planMismatches = @()
$scanPosition = 0
$scanTotal = @($CleanupTargets | Where-Object {
    (-not $Category -or $_.Name -like "*$Category*") -and
    (-not $Clean -or $null -eq $selectedTargetIds -or $selectedTargetIds.ContainsKey($_.Id))
}).Count

# ---------- 阶段 1：扫描 ----------
foreach ($t in $CleanupTargets) {
    if ($Category -and $t.Name -notlike "*$Category*") { continue }
    if ($Clean -and $null -ne $selectedTargetIds -and -not $selectedTargetIds.ContainsKey($t.Id)) { continue }

    $scanPosition++
    $displayPath = if ($t.Path) { $t.Path } elseif ($t.Pattern) { $t.Pattern } else { "(系统内置)" }
    Write-Host ("[{0}] {1}" -f $t.Name, $displayPath) -ForegroundColor White
    Write-CDriveEvent 'scan.item.started' @{ itemId = [string]$t.Id; name = [string]$t.Name; index = $scanPosition; total = $scanTotal }

    if ($t.RequiresAdmin -and -not $isAdmin) {
        Write-Host "    ⚠ 需要管理员权限，当前跳过（请以管理员身份运行以处理此项）" -ForegroundColor DarkYellow
        $skippedCount++
        $scanResults += [PSCustomObject]@{ Id = $t.Id; Name = $t.Name; Type = $t.Type; Path = $displayPath; Size = 0.0; Status = '需管理员'; Category = ''; Risk = ''; Advice = ''; Recommendation = (Get-CleanupRecommendation $t).Label; RecommendationLevel = (Get-CleanupRecommendation $t).Level; Note = '' }
        Write-CDriveEvent 'scan.item.completed' @{ itemId = [string]$t.Id; size = 0.0; status = 'requires-admin' }
        continue
    }

    $handler = $Handlers[$t.Type]
    if ($null -eq $handler) {
        Write-Host "    ✗ 未知类型 '$($t.Type)'，已跳过" -ForegroundColor Red
        continue
    }

    $cachedSize = if (-not $Clean) { Get-CDriveIncrementalCachedSize $incrementalSession ([string]$t.Id) } else { $null }
    if ($null -ne $cachedSize) {
        $r = [PSCustomObject]@{ Size = [double]$cachedSize; Freed = 0.0; Failed = 0; Detected = $false; Hint = ''; Note = '增量索引未发现变化，已复用上次结果'; IncrementalReused = $true }
    } else {
        $r = & $handler $t 'scan'
        if (-not $Clean -and -not $r.Detected) { Update-CDriveIncrementalEntry $incrementalSession $t ([double]$r.Size) }
    }

    if ($Clean -and $expectedSizeById.ContainsKey([string]$t.Id)) {
        $expectedSize = [double]$expectedSizeById[[string]$t.Id]
        $actualSize = [double]$r.Size
        if ($t.UserContent -and $expectedSize -ne $actualSize) {
            $planMismatches += [PSCustomObject]@{
                Id = [string]$t.Id
                Name = [string]$t.Name
                Expected = $expectedSize
                Actual = $actualSize
            }
        } elseif ($expectedSize -ne $actualSize) {
            Write-Host ('    提示：扫描后大小由 {0} 变化为 {1}，已按当前固定缓存范围重新核验。' -f (Format-Bytes $expectedSize), (Format-Bytes $actualSize)) -ForegroundColor DarkGray
        }
    }

    # 空间大户：独立输出（分类 + 风险 + 处方 + 匹配路径），仅诊断不删除
    if ($t.Type -eq 'SpaceHog') {
        if (@($r.Matches).Count -gt 0) {
            $totalDetected += $r.Size
            Write-Host ("    分类：{0}  风险：{1}" -f $t.Category, $t.Risk) -ForegroundColor Gray
            Write-Host ("    当前占用：{0}  ⚠ 仅诊断，程序不自动删除" -f (Format-Bytes $r.Size)) -ForegroundColor DarkYellow
            Write-Host ("    处方：{0}" -f $t.Advice) -ForegroundColor Gray
            foreach ($m in $r.Matches) {
                Write-Host ("      · {0}" -f $m.FullName) -ForegroundColor DarkGray
            }
            if (@($r.Matches).Count -ge 2) {
                $groups = @(Find-DuplicateDirGroups $r.Matches 10MB)
                foreach ($dg in $groups) {
                    $dg | Add-Member -NotePropertyName Source -NotePropertyValue $t.Name -Force
                    $dupResults += $dg
                    $totalDupWaste += $dg.Waste
                    Write-Host ("    ★ 发现 {0} 份结构+大小完全一致的副本（每份 {1}，直接子项 {2} 个）" -f $dg.CopyCount, (Format-Bytes $dg.EachSize), $dg.ChildCount) -ForegroundColor Yellow
                    Write-Host ("      建议保留：{0}" -f $dg.Keep) -ForegroundColor Gray
                    foreach ($drop in $dg.Drops) {
                        Write-Host ("      可删副本：{0}" -f $drop) -ForegroundColor DarkGray
                    }
                    Write-Host ("      删副本约可省 {0}（仅诊断，程序不删除）" -f (Format-Bytes $dg.Waste)) -ForegroundColor DarkYellow
                }
            }
            $scanResults += [PSCustomObject]@{ Id = $t.Id; Name = $t.Name; Type = $t.Type; Path = $displayPath; Size = $r.Size; Status = '诊断'; Category = $t.Category; Risk = $t.Risk; Advice = $t.Advice; Recommendation = '仅诊断'; RecommendationLevel = 'NotRecommended'; Note = $r.Note }
        } else {
            Write-Host "    未检测到" -ForegroundColor Gray
        }
        Write-CDriveEvent 'scan.item.completed' @{ itemId = [string]$t.Id; size = [double]$r.Size; status = 'diagnostic' }
        continue
    }

    if ($r.Detected) {
        if ((Test-Path -LiteralPath $t.Path)) {
            $totalDetected += $r.Size
            Write-Host ("    当前占用：{0}  ⚠ 需手动处理（程序不自动删除）" -f (Format-Bytes $r.Size)) -ForegroundColor DarkYellow
            if ($r.Hint) { Write-Host ("    提示：{0}" -f $r.Hint) -ForegroundColor Gray }
            $scanResults += [PSCustomObject]@{ Id = $t.Id; Name = $t.Name; Type = $t.Type; Path = $displayPath; Size = $r.Size; Status = '需手动'; Category = ''; Risk = ''; Advice = $r.Hint; Recommendation = '仅诊断'; RecommendationLevel = 'NotRecommended'; Note = $r.Note }
        } else {
            Write-Host "    不存在，无需处理" -ForegroundColor Gray
        }
    } else {
        $note = if ($r.Note) { "  ($($r.Note))" } else { "" }
        Write-Host ("    当前占用：{0}{1}" -f (Format-Bytes $r.Size), $note) -ForegroundColor Gray
        $totalCleanable += $r.Size
        $recommendation = Get-CleanupRecommendation $t
        $scanResults += [PSCustomObject]@{ Id = $t.Id; Name = $t.Name; Type = $t.Type; Path = $displayPath; Size = $r.Size; Status = '可清理'; Category = ''; Risk = ''; Advice = $recommendation.Advice; Recommendation = $recommendation.Label; RecommendationLevel = $recommendation.Level; Note = $r.Note; UserContent = [bool]$t.UserContent; RecoveryMode = [string]$t.RecoveryMode }
    }
    Write-CDriveEvent 'scan.item.completed' @{ itemId = [string]$t.Id; size = [double]$r.Size; status = $(if ($r.Detected) { 'diagnostic' } else { 'cleanable' }) }
}

if (-not $Clean -and $incrementalSession) {
    $indexSaved = Save-CDriveIncrementalSession $incrementalSession
    Write-CDriveEvent 'scan.incremental.completed' @{
        mode = [string]$incrementalSession.Mode
        reason = [string]$incrementalSession.Reason
        reusedItems = [int]$incrementalSession.ReusedIds.Count
        updatedItems = [int]$incrementalSession.UpdatedIds.Count
        indexSaved = [bool]$indexSaved
    }
}

# 仅导出已扫描到的固定安全目标，供图形界面展示、勾选和回传 ID。
if ($SelectionOutput) {
    try {
        $selectionItems = @($scanResults |
            Where-Object { $_.Status -eq '可清理' -and $_.Size -gt 0 } |
            ForEach-Object {
                [PSCustomObject]@{
                    Id                  = $_.Id
                    Name                = $_.Name
                    Type                = $_.Type
                    Path                = $_.Path
                    Size                = [double]$_.Size
                    Recommendation      = $_.Recommendation
                    RecommendationLevel = $_.RecommendationLevel
                    Advice              = $_.Advice
                    Note                = $_.Note
                    SafetyLevel         = if ($cleanupTargetById[[string]$_.Id].UserContent) { 'UserContent' } else { 'Standard' }
                    RecoveryMode        = [string]$cleanupTargetById[[string]$_.Id].RecoveryMode
                }
            })
        $selectionExport = [PSCustomObject]@{
            SchemaVersion = 2
            ScanId        = $scanId
            ManifestHash  = $targetManifestHash
            ScannedAt     = (Get-Date).ToString('o')
            Items         = $selectionItems
        }
        $selectionJson = $selectionExport | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($SelectionOutput, $selectionJson, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host ('  已导出可选清理项：' + $SelectionOutput) -ForegroundColor DarkGray
    } catch {
        Write-Host ('  ⚠ 导出可选清理项失败：' + $_.Exception.Message) -ForegroundColor Yellow
    }
}

if ($Clean -and $planMismatches.Count -gt 0) {
    Write-CDriveJournalOperationCompleted $operationJournal 'rejected' 0 0 0 'PLAN_CHANGED'
    Write-Host ''
    Write-Host '清理计划已变化，出于安全考虑本次未执行删除。请重新扫描后再选择。' -ForegroundColor Yellow
    foreach ($mismatch in $planMismatches) {
        Write-Host ('  [{0}] 扫描时 {1}，当前 {2}' -f $mismatch.Name, (Format-Bytes $mismatch.Expected), (Format-Bytes $mismatch.Actual)) -ForegroundColor DarkYellow
    }
    exit 2
}

# ---------- 空间剖析：目录（任意层级）+ 大文件 ----------
Write-Host ""
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "  空间剖析（找出空间具体被什么占用）" -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan

# 确定剖析根目录。UI 快速清理扫描显式跳过，深度诊断仍可通过 -Profile / -FullScan 使用。
$profileRoots = @()
if (-not $SkipProfile) {
    if ($Profile) {
        $profileRoots += $Profile
    } elseif ($FullScan) {
        $profileRoots += "C:\"
        Write-Host "  已启用全盘剖析（建议管理员身份，否则系统目录大小不准确）" -ForegroundColor Yellow
    } else {
        $profileRoots += $env:USERPROFILE
    }
} else {
    Write-Host "  已启用快速清理扫描，空间剖析已跳过。" -ForegroundColor DarkGray
}

foreach ($root in $profileRoots) {
    if (-not (Test-Path -LiteralPath $root)) {
        Write-Host ""
        Write-Host ("  ⚠ 剖析目录不存在：{0}" -f $root) -ForegroundColor Yellow
        continue
    }
    Write-Host ""
    Write-Host ("▶ 剖析目录：{0}" -f $root) -ForegroundColor White

    # 一次枚举完成所有空间统计
    $prof = Get-SpaceProfile $root $Top $MinSizeMB
    Write-Host ("  已扫描 {0:N0} 个文件" -f $prof.FileCount) -ForegroundColor DarkGray
    $profileData = [PSCustomObject]@{ Root = $root; FileCount = $prof.FileCount; TopDirs = @($prof.TopDirs); TopFiles = @($prof.TopFiles) }

    # 1) 目录剖析（任意层级 Top N）
    Write-Host ("  【占用最大的子目录 Top {0}（任意层级）】" -f $Top) -ForegroundColor Yellow
    $topDirs = @($prof.TopDirs)
    if ($topDirs.Count -gt 0) {
        $i = 1
        foreach ($d in $topDirs) {
            Write-Host ("    {0,3}. {1,12}  {2}" -f $i, (Format-Bytes $d.Size), $d.FullName) -ForegroundColor Gray
            $i++
        }
    } else {
        Write-Host "    （未统计到内容）" -ForegroundColor Gray
    }

    # 2) 大文件（阈值 + Top N）
    Write-Host ("  【最大的文件（≥{0} MB，最多 {1} 个）】" -f $MinSizeMB, $Top) -ForegroundColor Yellow
    $bigFiles = @($prof.TopFiles)
    if ($bigFiles.Count -gt 0) {
        $i = 1
        foreach ($f in $bigFiles) {
            Write-Host ("    {0,3}. {1,12}  {2}" -f $i, (Format-Bytes $f.Length), $f.FullName) -ForegroundColor Gray
            $i++
        }
    } else {
        Write-Host "    （未发现超过阈值的文件）" -ForegroundColor Gray
    }
}

# ---------- 阶段 2：清理（仅 -Clean）----------
if ($Clean) {
    Write-Host ""
    Write-Host "=====================================================" -ForegroundColor Cyan
    Write-Host ("  可安全清理项合计约 {0}，需手动/检测项约 {1}" -f (Format-Bytes $totalCleanable), (Format-Bytes $totalDetected)) -ForegroundColor White
    Write-Host "=====================================================" -ForegroundColor Cyan

    if (-not $Force) {
        $resp = Read-Host "  即将执行清理，删除上述可清理项。是否继续？(y/N)"
        if ($resp -notmatch '^[yY]') {
            Write-CDriveJournalOperationCompleted $operationJournal 'cancelled' 0 0 0 'USER_CANCELLED'
            Write-Host "  已取消清理，未删除任何文件。" -ForegroundColor Yellow
            Write-Host "=====================================================" -ForegroundColor Cyan
            exit 0
        }
    }

    Write-Host ""
    Write-Host "  开始清理..." -ForegroundColor Yellow
    foreach ($t in $CleanupTargets) {
        if ($Category -and $t.Name -notlike "*$Category*") { continue }
        if ($null -ne $selectedTargetIds -and -not $selectedTargetIds.ContainsKey($t.Id)) { continue }
        if ($t.Type -in @('Detect', 'SpaceHog')) { continue }

        $r = Invoke-CDriveBrokeredCleanup $executionContext ([string]$t.Id) $Handlers
        $totalFreed += $r.Freed
        $totalStagedForRecovery += [double]$r.StagedForRecovery
        $totalFailed += $r.Failed

        Write-Host ("  [{0}]" -f $t.Name) -ForegroundColor White
        if ($r.Status -eq 'skipped') {
            Write-Host ("    - {0}" -f $r.Note) -ForegroundColor DarkYellow
        } elseif ($r.Note) {
            Write-Host ("    ✓ {0}" -f $r.Note) -ForegroundColor Green
        } else {
            Write-Host ("    ✓ 已清理，释放 {0}" -f (Format-Bytes $r.Freed)) -ForegroundColor Green
        }
        if ($r.Failed -gt 0) { Write-Host ("    ⚠ 有 {0} 项未能删除（可能被占用）" -f $r.Failed) -ForegroundColor Yellow }
        Write-CDriveEvent 'cleanup.item.completed' @{ itemId = [string]$t.Id; freed = [double]$r.Freed; stagedForRecovery = [double]$r.StagedForRecovery; failed = [int]$r.Failed; status = [string]$r.Status }
    }
}

# ---------- 汇总 ----------
$driveFreeAfter = (New-Object System.IO.DriveInfo 'C:\').AvailableFreeSpace
Write-Host ""
Write-Host "=====================================================" -ForegroundColor Cyan
if ($Clean) {
    Write-Host ("  清理完成，合计释放约 {0} 空间" -f (Format-Bytes $totalFreed)) -ForegroundColor Green
    if ($totalStagedForRecovery -gt 0) { Write-Host ("  已移入回收站约 {0}，清空回收站前可恢复" -f (Format-Bytes $totalStagedForRecovery)) -ForegroundColor Yellow }
    Write-Host ("  磁盘可用空间：清理前 {0} → 清理后 {1}" -f (Format-Bytes $driveFreeBefore), (Format-Bytes $driveFreeAfter)) -ForegroundColor Green
    if ($totalFailed -gt 0) { Write-Host ("  ⚠ 有 {0} 项因被占用等原因未能删除" -f $totalFailed) -ForegroundColor Yellow }
    if ($skippedCount -gt 0) { Write-Host ("  ⚠ 有 {0} 项因需要管理员权限被跳过" -f $skippedCount) -ForegroundColor DarkYellow }
} else {
    Write-Host ("  可安全清理项合计约 {0}" -f (Format-Bytes $totalCleanable)) -ForegroundColor Green
    Write-Host ("  需手动/检测项合计约 {0}（含休眠文件、Windows.old 等）" -f (Format-Bytes $totalDetected)) -ForegroundColor DarkYellow
    Write-Host ("  当前磁盘可用空间：{0}" -f (Format-Bytes $driveFreeAfter)) -ForegroundColor Green
    if ($totalDupWaste -gt 0) { Write-Host ("  发现完全重复目录，删副本约可省 {0}（仅诊断，未删除）" -f (Format-Bytes $totalDupWaste)) -ForegroundColor DarkYellow }
    if ($skippedCount -gt 0) { Write-Host ("  ⚠ 有 {0} 项因需要管理员权限被跳过" -f $skippedCount) -ForegroundColor DarkYellow }
    Write-Host "  扫描完成，尚未删除任何文件。" -ForegroundColor Green
    Write-Host "  确认后请运行： powershell -ExecutionPolicy Bypass -File .\C-Drive-Cleaner.ps1 -Clean" -ForegroundColor Yellow
    Write-Host "  或双击「C盘清理.bat」选择菜单。" -ForegroundColor Yellow
    Write-Host "  系统级项目请以【管理员身份】运行 PowerShell。" -ForegroundColor Yellow
}
Write-Host "=====================================================" -ForegroundColor Cyan

# ---------- 报告导出（仅 -Report）----------
function Get-ReportHtml {
    param($ScanResults, $ProfileData, $Meta, $DupGroups)

    # 清理目标行（非诊断项）
    $rowsTarget = @()
    foreach ($r in $ScanResults) {
        if ($r.Status -ne '诊断') {
            $rowsTarget += "<tr><td>$(Encode-Html $r.Name)</td><td>$(Encode-Html (Format-Bytes $r.Size))</td><td>$(Encode-Html $r.Status)</td><td class='small'>$(Encode-Html $r.Path)</td></tr>"
        }
    }
    # 大户诊断行
    $rowsHog = @()
    foreach ($r in $ScanResults) {
        if ($r.Status -eq '诊断') {
            $rowsHog += "<tr><td>$(Encode-Html $r.Name)</td><td>$(Encode-Html $r.Category)</td><td class='risk-$(Encode-Html $r.Risk)'>$(Encode-Html $r.Risk)</td><td>$(Encode-Html (Format-Bytes $r.Size))</td><td class='advice'>$(Encode-Html $r.Advice)</td></tr>"
        }
    }
    # Top 目录行
    $rowsDir = @()
    $i = 1
    foreach ($d in @($ProfileData.TopDirs)) {
        $rowsDir += "<tr><td>$i</td><td>$(Encode-Html (Format-Bytes $d.Size))</td><td class='small'>$(Encode-Html $d.FullName)</td></tr>"
        $i++
    }
    # Top 文件行
    $rowsFile = @()
    $i = 1
    foreach ($f in @($ProfileData.TopFiles)) {
        $rowsFile += "<tr><td>$i</td><td>$(Encode-Html (Format-Bytes $f.Length))</td><td class='small'>$(Encode-Html $f.FullName)</td></tr>"
        $i++
    }
    # 重复目录行
    $rowsDup = @()
    foreach ($g in @($DupGroups)) {
        $dropHtml = (@($g.Drops | ForEach-Object { Encode-Html $_ }) -join '<br>')
        $rowsDup += "<tr><td>$(Encode-Html $g.Source)</td><td>$($g.CopyCount)</td><td>$(Encode-Html (Format-Bytes $g.EachSize))</td><td>$(Encode-Html (Format-Bytes $g.Waste))</td><td class='small'>$(Encode-Html $g.Keep)</td><td class='small'>$dropHtml</td></tr>"
    }
    if ($rowsDup.Count -eq 0) {
        $rowsDup += "<tr><td colspan='6'>未发现结构+大小完全一致的大目录副本</td></tr>"
    }

    # 磁盘可用空间行（清理模式显示前后对比，扫描模式显示当前值）
    $freeLine = if ($Meta.Mode -eq '清理') {
        "磁盘可用空间：清理前 $(Format-Bytes $Meta.FreeBefore) → 清理后 $(Format-Bytes $Meta.FreeAfter)"
    } else {
        "磁盘可用空间：$(Format-Bytes $Meta.FreeAfter)"
    }

    $html = @"
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<title>C盘清理诊断报告</title>
<style>
body { font-family: "Microsoft YaHei", "Segoe UI", sans-serif; margin: 24px; color: #333; }
h1 { border-bottom: 3px solid #2a7; padding-bottom: 10px; }
h2 { color: #2a7; margin-top: 28px; border-left: 4px solid #2a7; padding-left: 8px; }
table { border-collapse: collapse; width: 100%; margin: 8px 0 20px; }
th, td { border: 1px solid #ddd; padding: 6px 10px; text-align: left; font-size: 13px; vertical-align: top; }
th { background: #f0f7f2; }
.meta { color: #666; font-size: 13px; line-height: 1.7; }
.risk-需人工决策 { color: #c60; font-weight: bold; }
.risk-可重建 { color: #2a7; font-weight: bold; }
.advice { color: #555; max-width: 520px; }
.small { color: #888; font-size: 12px; word-break: break-all; }
</style>
</head>
<body>
<h1>C 盘清理诊断报告</h1>
<p class="meta">
生成时间：$($Meta.Time)<br>
运行模式：$($Meta.Mode)<br>
管理员权限：$($Meta.IsAdmin)<br>
可安全清理项：$(Format-Bytes $Meta.TotalCleanable)　需手动/诊断项：$(Format-Bytes $Meta.TotalDetected)　跳过（需管理员）：$($Meta.SkippedCount)<br>
$freeLine
</p>
<h2>一、清理目标</h2>
<table>
<tr><th>名称</th><th>占用</th><th>状态</th><th>路径</th></tr>
$($rowsTarget -join "`n")
</table>
<h2>二、空间大户诊断（仅诊断，不自动删除）</h2>
<table>
<tr><th>名称</th><th>分类</th><th>风险</th><th>占用</th><th>处方</th></tr>
$($rowsHog -join "`n")
</table>
<h2>三、空间剖析：占用最大的目录（任意层级）</h2>
<table>
<tr><th>#</th><th>占用</th><th>路径</th></tr>
$($rowsDir -join "`n")
</table>
<h2>四、空间剖析：最大的文件</h2>
<table>
<tr><th>#</th><th>占用</th><th>路径</th></tr>
$($rowsFile -join "`n")
</table>
<h2>五、重复目录（仅诊断，不自动删除）</h2>
<table>
<tr><th>来源</th><th>份数</th><th>每份大小</th><th>删副本可省</th><th>建议保留</th><th>可删副本</th></tr>
$($rowsDup -join "`n")
</table>
<p class="small">本报告由 C-Drive-Cleaner.ps1 生成。空间大户与重复目录仅供诊断参考，请按“处方”自行处理。</p>
</body>
</html>
"@
    return $html
}

if ($Report) {
    $modeStr = if ($Clean) { '清理' } else { '扫描（仅统计）' }
    $adminStr = if ($isAdmin) { '是' } else { '否' }
    $meta = [PSCustomObject]@{
        Time           = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Mode           = $modeStr
        IsAdmin        = $adminStr
        TotalCleanable = $totalCleanable
        TotalDetected  = $totalDetected
        SkippedCount   = $skippedCount
        FreeBefore     = $driveFreeBefore
        FreeAfter      = $driveFreeAfter
    }
    $html = Get-ReportHtml $scanResults $profileData $meta $dupResults
    try {
        New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
        [System.IO.File]::WriteAllText($reportPath, $html, (New-Object System.Text.UTF8Encoding($true)))
        Write-Host ""
        Write-Host ("  诊断报告已导出：{0}" -f $reportPath) -ForegroundColor Green
    } catch {
        Write-Host ("  ⚠ 报告导出失败：{0}" -f $_.Exception.Message) -ForegroundColor Red
    }
}

Write-CDriveEvent 'operation.completed' @{
    status = 'passed'
    mode = $(if ($Clean) { 'clean' } else { 'scan' })
    cleanable = [double]$totalCleanable
    detected = [double]$totalDetected
    freed = [double]$totalFreed
    stagedForRecovery = [double]$totalStagedForRecovery
    failed = [int]$totalFailed
    freeBefore = [double]$driveFreeBefore
    freeAfter = [double]$driveFreeAfter
}
if ($Clean) {
    Write-CDriveJournalOperationCompleted $operationJournal 'completed' $totalFreed $totalStagedForRecovery $totalFailed ''
}
