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
    [switch]$Report,                # 扫描结束后导出 HTML 诊断报告（写到脚本同目录）
    [string]$SelectionFile = "",    # UI 已勾选的项目 ID 清单；仅清理这些固定目标
    [string]$SelectionOutput = "",  # 扫描结果导出为 JSON，供 UI 展示与用户选择
    [switch]$SelfTest               # 仅运行安全闸自检后退出（不扫描、不删除）
)

$ErrorActionPreference = 'SilentlyContinue'

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
    $sum = (Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { ([int]$_.Attributes -band 0x400) -eq 0 } |
            Measure-Object -Property Length -Sum).Sum
    if ($null -eq $sum) { return 0.0 }
    return [double]$sum
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
$CleanupTargets = @(
    # ---- 用户级（无需管理员）----
    @{ Name = "用户临时文件";       Type = "FolderContents"; Path = $env:TEMP; RequiresAdmin = $false }
    @{ Name = "本地临时文件";       Type = "FolderContents"; Path = "$env:LOCALAPPDATA\Temp"; RequiresAdmin = $false }
    @{ Name = "用户崩溃转储";       Type = "FolderContents"; Path = "$env:LOCALAPPDATA\CrashDumps"; RequiresAdmin = $false }
    @{ Name = "缩略图缓存";         Type = "FolderContents"; Path = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"; RequiresAdmin = $false }
    @{ Name = "Chrome 缓存";        Type = "PatternCache";   Path = "$env:LOCALAPPDATA\Google\Chrome\User Data"; SubDirs = "Cache,Code Cache,GPUCache"; RequiresAdmin = $false }
    @{ Name = "Edge 缓存";          Type = "PatternCache";   Path = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"; SubDirs = "Cache,Code Cache,GPUCache"; RequiresAdmin = $false }
    @{ Name = "Firefox 缓存";       Type = "PatternCache";   Path = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"; SubDirs = "cache2"; RequiresAdmin = $false }
    @{ Name = "npm 缓存";           Type = "FolderContents"; Path = "$env:LOCALAPPDATA\npm-cache"; RequiresAdmin = $false }
    @{ Name = "pip 缓存";           Type = "FolderContents"; Path = "$env:LOCALAPPDATA\pip\Cache"; RequiresAdmin = $false }
    @{ Name = "NuGet 包仓库";       Type = "Detect";         Path = "$env:USERPROFILE\.nuget\packages"; RequiresAdmin = $false; Hint = "这是 NuGet 包仓库而非临时缓存。清空后需重新 restore；请自行确认后再手动删除。" }
    @{ Name = "Yarn 缓存";          Type = "FolderContents"; Path = "$env:LOCALAPPDATA\Yarn\Cache"; RequiresAdmin = $false }
    @{ Name = "DirectX 着色器缓存"; Type = "FolderContents"; Path = "$env:LOCALAPPDATA\D3DSCache"; RequiresAdmin = $false }
    @{ Name = "NVIDIA DXCache";     Type = "FolderContents"; Path = "$env:LOCALAPPDATA\NVIDIA\DXCache"; RequiresAdmin = $false }
    @{ Name = "NVIDIA GLCache";     Type = "FolderContents"; Path = "$env:LOCALAPPDATA\NVIDIA\GLCache"; RequiresAdmin = $false }
    @{ Name = "NVIDIA NV_Cache";    Type = "FolderContents"; Path = "$env:LOCALAPPDATA\NVIDIA Corporation\NV_Cache"; RequiresAdmin = $false }
    @{ Name = "Windows 错误报告";   Type = "FolderContents"; Path = "$env:LOCALAPPDATA\Microsoft\Windows\WER"; RequiresAdmin = $false }
    @{ Name = "剪贴板历史";         Type = "FolderContents"; Path = "$env:LOCALAPPDATA\Microsoft\Windows\Clipboard"; RequiresAdmin = $false }
    @{ Name = "微信文件";           Type = "Detect";         Path = "$env:USERPROFILE\Documents\WeChat Files"; RequiresAdmin = $false; Hint = "建议用微信内置：设置->文件管理->清理，避免误删聊天记录" }
    @{ Name = "QQ 文件";            Type = "Detect";         Path = "$env:USERPROFILE\Documents\Tencent Files"; RequiresAdmin = $false; Hint = "建议用 QQ 内置清理，或手动删除不再需要的已接收文件" }
    # 用户内容：只覆盖应用已分离的图片/视频附件目录；默认不勾选，绝不触及聊天数据库、FileRecv 或整个账号目录。
    @{ Id = "user-wechat-media"; Name = "微信图片与视频附件"; Type = "PatternCache"; Path = "$env:USERPROFILE\Documents\WeChat Files"; SubDirs = "FileStorage\Image,FileStorage\Video"; UserContent = $true; RequiresAdmin = $false; Advice = "包含微信聊天中的图片和视频附件。删除后不可恢复；请先在微信内确认不再需要。不会处理聊天记录、数据库或 FileRecv 文件。" }
    @{ Id = "user-qq-media"; Name = "QQ 图片与视频附件"; Type = "PatternCache"; Path = "$env:USERPROFILE\Documents\Tencent Files"; SubDirs = "Image,Video"; UserContent = $true; RequiresAdmin = $false; Advice = "包含 QQ 聊天中的图片和视频附件。删除后不可恢复；请先在 QQ 内确认不再需要。不会处理聊天记录或 FileRecv 文件。" }
    @{ Name = "回收站";             Type = "RecycleBin";     Path = ""; RequiresAdmin = $false }
    @{ Name = "DNS 缓存";           Type = "DNSCache";       Path = ""; RequiresAdmin = $false }

    # ---- 系统级（需管理员）----
    @{ Name = "Windows 临时文件";   Type = "FolderContents"; Path = "C:\Windows\Temp"; RequiresAdmin = $true }
    @{ Name = "Windows 更新缓存";   Type = "FolderContents"; Path = "C:\Windows\SoftwareDistribution\Download"; RequiresAdmin = $true }
    @{ Name = "预读取文件 Prefetch"; Type = "FolderContents"; Path = "C:\Windows\Prefetch"; RequiresAdmin = $true }
    @{ Name = "交付优化缓存";       Type = "FolderContents"; Path = "C:\Windows\SoftwareDistribution\DeliveryOptimization"; RequiresAdmin = $true }
    @{ Name = "系统崩溃转储";       Type = "FolderContents"; Path = "C:\Windows\Minidump"; RequiresAdmin = $true }
    @{ Name = "内存转储 MEMORY.DMP"; Type = "Remove";        Path = "C:\Windows\MEMORY.DMP"; RequiresAdmin = $true }
    @{ Name = "Windows.old 旧系统"; Type = "Detect";         Path = "C:\Windows.old"; RequiresAdmin = $true; Hint = "磁盘清理(cleanmgr)->清理系统文件->勾选'以前的 Windows 安装'" }
    @{ Name = "休眠文件 hiberfil.sys"; Type = "Detect";      Path = "C:\hiberfil.sys"; RequiresAdmin = $true; Hint = "管理员运行 powercfg /h off 可关闭休眠并释放约等于内存大小的空间" }
    @{ Name = "页面文件 pagefile.sys"; Type = "Detect";      Path = "C:\pagefile.sys"; RequiresAdmin = $true; Hint = "系统虚拟内存文件，不建议删除，可缩小或移至其他盘" }

    # ---- 空间大户诊断（仅诊断+处方，绝不自动删除）----
    # Pattern 支持通配符；Category=分类；Risk=风险分级（需人工决策 / 可重建）；Advice=处方
    @{ Name = "Claude Desktop 虚拟机磁盘"; Type = "SpaceHog"; Pattern = "$env:LOCALAPPDATA\Packages\Claude_*\LocalCache\Roaming\Claude\vm_bundles"; Category = "应用资源"; Risk = "需人工决策"; Advice = "Claude Desktop 的 Linux 虚拟机磁盘（rootfs.vhdx 等）。若不再使用，请通过'设置→应用'卸载 Claude Desktop 回收；仍在使用请勿删除。"; RequiresAdmin = $false }
    @{ Name = "Windows 字体缓存";          Type = "SpaceHog"; Pattern = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"; Category = "系统资源"; Risk = "需人工决策"; Advice = "Windows 字体缓存（约 2.7GB，含字体副本）。系统字体请勿直接删除；管理字体请用'设置→个性化→字体'。"; RequiresAdmin = $false }
    @{ Name = "剪映 JianyingPro";          Type = "SpaceHog"; Pattern = "$env:LOCALAPPDATA\JianyingPro"; Category = "应用资源"; Risk = "需人工决策"; Advice = "剪映客户端（含 CUDA 依赖约 2.4GB）。若不再使用建议卸载；或用剪映内置的缓存清理。"; RequiresAdmin = $false }
    @{ Name = "MiniConda3 环境";           Type = "SpaceHog"; Pattern = "$env:USERPROFILE\MiniConda3"; Category = "开发环境"; Risk = "需人工决策"; Advice = "MiniConda Python 环境。清理请用 conda clean，卸载请用官方卸载器；请勿直接删除目录。"; RequiresAdmin = $false }
    @{ Name = "下载目录";                  Type = "SpaceHog"; Pattern = "$env:USERPROFILE\Downloads"; Category = "用户数据"; Risk = "需人工决策"; Advice = "下载目录（含安装包等）。请手动确认后删除不再需要的文件。"; RequiresAdmin = $false }
    @{ Name = "Codex 运行时";              Type = "SpaceHog"; Pattern = "$env:USERPROFILE\.codex"; Category = "应用资源"; Risk = "需人工决策"; Advice = "OpenAI Codex CLI 及插件运行时（约 2.3GB）。若不再使用 Codex 建议卸载。"; RequiresAdmin = $false }
    @{ Name = "开发工具缓存 .cache";       Type = "SpaceHog"; Pattern = "$env:USERPROFILE\.cache"; Category = "可重建缓存"; Risk = "可重建"; Advice = "开发工具缓存（codex-runtimes 等）。可安全删除，工具下次使用时重建；删除后首次运行会重新下载。"; RequiresAdmin = $false }
    @{ Name = "Cursor 编辑器缓存";         Type = "SpaceHog"; Pattern = "$env:USERPROFILE\.cursor"; Category = "可重建缓存"; Risk = "可重建"; Advice = "Cursor 编辑器缓存/扩展。缓存可删除，扩展会随使用重建。"; RequiresAdmin = $false }
    @{ Name = "Gemini 浏览器录制数据";     Type = "SpaceHog"; Pattern = "$env:USERPROFILE\.gemini\*\browser_recordings"; Category = "录制数据"; Risk = "需人工决策"; Advice = "Gemini 的浏览器录制数据（antigravity 等多份副本）。可手动删除不再需要的录制；删除后历史录制不可恢复。"; RequiresAdmin = $false }
    @{ Name = "LM Studio 本地模型";        Type = "SpaceHog"; Pattern = "$env:USERPROFILE\.lmstudio"; Category = "应用资源"; Risk = "需人工决策"; Advice = "LM Studio 本地大模型运行环境（模型文件较大）。若不再使用建议卸载并删除模型。"; RequiresAdmin = $false }
)

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

# 为 UI 与命令行选择提供稳定 ID。选择文件只允许携带这些 ID，绝不接收路径或删除规则。
$targetIndex = 0
foreach ($t in $CleanupTargets) {
    $targetIndex++
    if (-not $t.Id) { $t.Id = ('clean-{0:D2}' -f $targetIndex) }
}
$cleanupTargetById = @{}
foreach ($t in $CleanupTargets) { $cleanupTargetById[[string]$t.Id] = $t }

function Get-CleanupRecommendation {
    param($Target)
    if ($Target.UserContent) {
        return [PSCustomObject]@{ Label = '谨慎选择'; Level = 'Review'; Advice = $Target.Advice }
    }
    if ($Target.Name -eq '预读取文件 Prefetch') {
        return [PSCustomObject]@{ Label = '不建议清理'; Level = 'NotRecommended'; Advice = '对可用空间帮助很小，删除后会暂时影响应用启动优化。' }
    }
    if ($Target.Type -eq 'DNSCache') {
        return [PSCustomObject]@{ Label = '无需清理'; Level = 'NotRecommended'; Advice = '这是内存缓存，不释放磁盘空间。' }
    }
    if ($Target.Type -eq 'RecycleBin' -or $Target.Type -eq 'Remove' -or $Target.RequiresAdmin) {
        return [PSCustomObject]@{ Label = '建议检查'; Level = 'Review'; Advice = '请确认内容不再需要后再选择。' }
    }
    return [PSCustomObject]@{ Label = '建议清理'; Level = 'Recommended'; Advice = '属于可重建缓存或临时文件，相关应用下次使用时可能重新生成。' }
}

$selectedTargetIds = $null
if ($SelectionFile) {
    if (-not (Test-Path -LiteralPath $SelectionFile)) {
        Write-Host ('错误：找不到选择清单：' + $SelectionFile) -ForegroundColor Red
        exit 1
    }
    try {
        $selectionPayload = Get-Content -LiteralPath $SelectionFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $requestedIds = @($selectionPayload.SelectedIds | Where-Object { $_ })
        $selectedTargetIds = @{}
        foreach ($id in $requestedIds) { $selectedTargetIds[[string]$id] = $true }
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
    if ($fail -gt 0) { Write-Host ("SelfTest 失败 {0} 项" -f $fail) -ForegroundColor Red; exit 1 }
    Write-Host "SelfTest 通过" -ForegroundColor Green
    exit 0
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

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
$totalFailed    = 0
$skippedCount   = 0
$totalDupWaste  = 0.0
$dupResults     = @()
$profileData    = [PSCustomObject]@{ Root = ''; FileCount = 0; TopDirs = @(); TopFiles = @() }

$scanResults = @()

# ---------- 阶段 1：扫描 ----------
foreach ($t in $CleanupTargets) {
    if ($Category -and $t.Name -notlike "*$Category*") { continue }
    if ($Clean -and $null -ne $selectedTargetIds -and -not $selectedTargetIds.ContainsKey($t.Id)) { continue }

    $displayPath = if ($t.Path) { $t.Path } elseif ($t.Pattern) { $t.Pattern } else { "(系统内置)" }
    Write-Host ("[{0}] {1}" -f $t.Name, $displayPath) -ForegroundColor White

    if ($t.RequiresAdmin -and -not $isAdmin) {
        Write-Host "    ⚠ 需要管理员权限，当前跳过（请以管理员身份运行以处理此项）" -ForegroundColor DarkYellow
        $skippedCount++
        $scanResults += [PSCustomObject]@{ Id = $t.Id; Name = $t.Name; Type = $t.Type; Path = $displayPath; Size = 0.0; Status = '需管理员'; Category = ''; Risk = ''; Advice = ''; Recommendation = (Get-CleanupRecommendation $t).Label; RecommendationLevel = (Get-CleanupRecommendation $t).Level; Note = '' }
        continue
    }

    $handler = $Handlers[$t.Type]
    if ($null -eq $handler) {
        Write-Host "    ✗ 未知类型 '$($t.Type)'，已跳过" -ForegroundColor Red
        continue
    }

    $r = & $handler $t 'scan'

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
        $scanResults += [PSCustomObject]@{ Id = $t.Id; Name = $t.Name; Type = $t.Type; Path = $displayPath; Size = $r.Size; Status = '可清理'; Category = ''; Risk = ''; Advice = $recommendation.Advice; Recommendation = $recommendation.Label; RecommendationLevel = $recommendation.Level; Note = $r.Note }
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
                }
            })
        $selectionExport = [PSCustomObject]@{
            SchemaVersion = 1
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

# ---------- 空间剖析：目录（任意层级）+ 大文件 ----------
Write-Host ""
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "  空间剖析（找出空间具体被什么占用）" -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan

# 确定剖析根目录
$profileRoots = @()
if ($Profile) {
    $profileRoots += $Profile
} elseif ($FullScan) {
    $profileRoots += "C:\"
    Write-Host "  已启用全盘剖析（建议管理员身份，否则系统目录大小不准确）" -ForegroundColor Yellow
} else {
    $profileRoots += $env:USERPROFILE
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
        if ($t.RequiresAdmin -and -not $isAdmin) { continue }
        if ($t.Type -in @('Detect', 'SpaceHog')) { continue }

        $handler = $Handlers[$t.Type]
        if ($null -eq $handler) { continue }

        $r = & $handler $t 'clean'
        $totalFreed += $r.Freed
        $totalFailed += $r.Failed

        Write-Host ("  [{0}]" -f $t.Name) -ForegroundColor White
        if ($r.Note) {
            Write-Host ("    ✓ {0}" -f $r.Note) -ForegroundColor Green
        } else {
            Write-Host ("    ✓ 已清理，释放 {0}" -f (Format-Bytes $r.Freed)) -ForegroundColor Green
        }
        if ($r.Failed -gt 0) { Write-Host ("    ⚠ 有 {0} 项未能删除（可能被占用）" -f $r.Failed) -ForegroundColor Yellow }
    }
}

# ---------- 汇总 ----------
$driveFreeAfter = (New-Object System.IO.DriveInfo 'C:\').AvailableFreeSpace
Write-Host ""
Write-Host "=====================================================" -ForegroundColor Cyan
if ($Clean) {
    Write-Host ("  清理完成，合计释放约 {0} 空间" -f (Format-Bytes $totalFreed)) -ForegroundColor Green
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
    $reportPath = Join-Path $PSScriptRoot "C盘清理诊断报告.html"
    try {
        [System.IO.File]::WriteAllText($reportPath, $html, (New-Object System.Text.UTF8Encoding($true)))
        Write-Host ""
        Write-Host ("  诊断报告已导出：{0}" -f $reportPath) -ForegroundColor Green
    } catch {
        Write-Host ("  ⚠ 报告导出失败：{0}" -f $_.Exception.Message) -ForegroundColor Red
    }
}
