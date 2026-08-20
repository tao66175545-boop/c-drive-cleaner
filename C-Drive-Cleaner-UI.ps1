# ============================================================
#  C 盘清理 - 图形外壳  C-Drive-Cleaner-UI.ps1
#  只调用主程序 C-Drive-Cleaner.ps1，不重复实现删除逻辑。
#  扫描默认不删除；清理只走主程序安全项，空间大户/重复目录不会被删。
# ============================================================

if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    $arg = '-STA -NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath
    Start-Process -FilePath 'powershell.exe' -ArgumentList $arg
    exit 0
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies @('System.Drawing.dll', 'System.Windows.Forms.dll') -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Windows.Forms;

public class CDriveRoundedPanel : Panel {
    public int CornerRadius { get; set; }
    public Color BorderColor { get; set; }
    public CDriveRoundedPanel() {
        DoubleBuffered = true;
        ResizeRedraw = true;
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        CornerRadius = 8;
        BorderColor = Color.FromArgb(226, 229, 232);
    }
    private GraphicsPath PathFor(Rectangle bounds) {
        int radius = Math.Max(1, Math.Min(CornerRadius, Math.Min(bounds.Width, bounds.Height) / 2));
        int diameter = radius * 2;
        GraphicsPath path = new GraphicsPath();
        path.AddArc(bounds.Left, bounds.Top, diameter, diameter, 180, 90);
        path.AddArc(bounds.Right - diameter, bounds.Top, diameter, diameter, 270, 90);
        path.AddArc(bounds.Right - diameter, bounds.Bottom - diameter, diameter, diameter, 0, 90);
        path.AddArc(bounds.Left, bounds.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
        return path;
    }
    private void ApplyRoundedRegion() {
        if (Width < 2 || Height < 2) return;
        using (GraphicsPath path = PathFor(new Rectangle(0, 0, Width - 1, Height - 1))) {
            Region oldRegion = Region;
            Region = new Region(path);
            if (oldRegion != null) oldRegion.Dispose();
        }
    }
    protected override void OnResize(EventArgs e) { base.OnResize(e); Invalidate(); }
    private Color SurfaceBackColor() {
        Control surface = Parent;
        while (surface != null) {
            if (surface.BackColor.A == 255) return surface.BackColor;
            surface = surface.Parent;
        }
        return SystemColors.Control;
    }
    protected override void OnPaintBackground(PaintEventArgs e) {
        e.Graphics.CompositingQuality = CompositingQuality.HighQuality;
        e.Graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        e.Graphics.Clear(SurfaceBackColor());
        Rectangle rect = new Rectangle(0, 0, Width - 1, Height - 1);
        if (rect.Width < 2 || rect.Height < 2) return;
        using (GraphicsPath path = PathFor(rect))
        using (SolidBrush brush = new SolidBrush(BackColor)) e.Graphics.FillPath(brush, path);
    }
    protected override void OnPaint(PaintEventArgs e) {
        e.Graphics.CompositingQuality = CompositingQuality.HighQuality;
        e.Graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        Rectangle rect = new Rectangle(0, 0, Width - 1, Height - 1);
        if (rect.Width < 2 || rect.Height < 2) return;
        using (GraphicsPath path = PathFor(rect))
        using (Pen pen = new Pen(BorderColor)) e.Graphics.DrawPath(pen, path);
    }
}

public class CDriveRoundedButton : Control {
    private int cornerRadius = 8;
    private Color borderColor = Color.FromArgb(218, 222, 226);
    private Color hoverBackColor = Color.FromArgb(245, 245, 245);
    private Color pressedBackColor = Color.FromArgb(235, 235, 235);
    private bool hover;
    private bool pressed;
    private bool selected;
    private Color selectedBackColor = Color.Empty;
    private Color selectedForeColor = Color.Empty;
    private Color selectedBorderColor = Color.Empty;
    private Color selectedHoverBackColor = Color.Empty;
    private Color selectedPressedBackColor = Color.Empty;

    public int CornerRadius { get { return cornerRadius; } set { cornerRadius = Math.Max(0, value); Invalidate(); } }
    public Color BorderColor { get { return borderColor; } set { borderColor = value; Invalidate(); } }
    public Color HoverBackColor { get { return hoverBackColor; } set { hoverBackColor = value; Invalidate(); } }
    public Color PressedBackColor { get { return pressedBackColor; } set { pressedBackColor = value; Invalidate(); } }
    public bool Selected { get { return selected; } set { selected = value; Invalidate(); } }
    public Color SelectedBackColor { get { return selectedBackColor; } set { selectedBackColor = value; Invalidate(); } }
    public Color SelectedForeColor { get { return selectedForeColor; } set { selectedForeColor = value; Invalidate(); } }
    public Color SelectedBorderColor { get { return selectedBorderColor; } set { selectedBorderColor = value; Invalidate(); } }
    public Color SelectedHoverBackColor { get { return selectedHoverBackColor; } set { selectedHoverBackColor = value; Invalidate(); } }
    public Color SelectedPressedBackColor { get { return selectedPressedBackColor; } set { selectedPressedBackColor = value; Invalidate(); } }

    public CDriveRoundedButton() {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                 ControlStyles.ResizeRedraw | ControlStyles.Selectable, true);
        DoubleBuffered = true;
        TabStop = true;
        Cursor = Cursors.Hand;
        AccessibleRole = AccessibleRole.PushButton;
        BackColor = Color.White;
        ForeColor = Color.FromArgb(72, 86, 99);
    }

    private GraphicsPath PathFor(RectangleF bounds) {
        float radius = Math.Max(0.5f, Math.Min(cornerRadius, Math.Min(bounds.Width, bounds.Height) / 2f));
        float diameter = radius * 2f;
        GraphicsPath path = new GraphicsPath();
        path.AddArc(bounds.Left, bounds.Top, diameter, diameter, 180, 90);
        path.AddArc(bounds.Right - diameter, bounds.Top, diameter, diameter, 270, 90);
        path.AddArc(bounds.Right - diameter, bounds.Bottom - diameter, diameter, diameter, 0, 90);
        path.AddArc(bounds.Left, bounds.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
        return path;
    }

    private static Color FirstColor(Color primary, Color fallback) { return primary.IsEmpty ? fallback : primary; }
    private Color CurrentFill() {
        Color normal = selected ? FirstColor(selectedBackColor, BackColor) : BackColor;
        Color hoverColor = selected ? FirstColor(selectedHoverBackColor, HoverBackColor) : HoverBackColor;
        Color pressedColor = selected ? FirstColor(selectedPressedBackColor, PressedBackColor) : PressedBackColor;
        return pressed ? pressedColor : (hover ? hoverColor : normal);
    }
    private Color CurrentText() { return selected ? FirstColor(selectedForeColor, ForeColor) : ForeColor; }
    private Color CurrentBorder() { return selected ? FirstColor(selectedBorderColor, BorderColor) : BorderColor; }
    private Color SurfaceBackColor() {
        Control surface = Parent;
        while (surface != null) {
            if (surface.BackColor.A == 255) return surface.BackColor;
            surface = surface.Parent;
        }
        return SystemColors.Control;
    }

    protected override void OnPaintBackground(PaintEventArgs e) {
        e.Graphics.Clear(SurfaceBackColor());
    }
    protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { hover = false; pressed = false; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnMouseDown(MouseEventArgs e) {
        if (e.Button == MouseButtons.Left && Enabled) { Focus(); pressed = true; Invalidate(); }
        base.OnMouseDown(e);
    }
    protected override void OnMouseUp(MouseEventArgs e) { if (pressed) { pressed = false; Invalidate(); } base.OnMouseUp(e); }
    protected override void OnKeyDown(KeyEventArgs e) {
        if (Enabled && (e.KeyCode == Keys.Space || e.KeyCode == Keys.Enter)) { pressed = true; Invalidate(); e.Handled = true; }
        base.OnKeyDown(e);
    }
    protected override void OnKeyUp(KeyEventArgs e) {
        if (pressed && (e.KeyCode == Keys.Space || e.KeyCode == Keys.Enter)) { pressed = false; Invalidate(); OnClick(EventArgs.Empty); e.Handled = true; }
        base.OnKeyUp(e);
    }
    protected override void OnEnabledChanged(EventArgs e) { hover = false; pressed = false; Invalidate(); base.OnEnabledChanged(e); }
    protected override void OnParentBackColorChanged(EventArgs e) { Invalidate(); base.OnParentBackColorChanged(e); }
    protected override void OnPaint(PaintEventArgs e) {
        if (Width < 3 || Height < 3) return;
        e.Graphics.CompositingQuality = CompositingQuality.HighQuality;
        e.Graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
        e.Graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        e.Graphics.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;

        RectangleF rect = new RectangleF(0.5f, 0.5f, Width - 1f, Height - 1f);
        Color fill = Enabled ? CurrentFill() : Color.FromArgb(240, 241, 242);
        Color text = Enabled ? CurrentText() : Color.FromArgb(166, 171, 175);
        Color border = Enabled ? CurrentBorder() : Color.FromArgb(225, 228, 230);
        using (GraphicsPath path = PathFor(rect))
        using (SolidBrush brush = new SolidBrush(fill))
        using (Pen pen = new Pen(border, 1f)) {
            e.Graphics.FillPath(brush, path);
            e.Graphics.DrawPath(pen, path);
        }
        Rectangle textBounds = new Rectangle(8, 0, Math.Max(0, ClientSize.Width - 16), ClientSize.Height);
        TextRenderer.DrawText(e.Graphics, Text, Font, textBounds, text,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine |
            TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
    }
}
'@
[System.Windows.Forms.Application]::EnableVisualStyles()

$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
$mainScript = Join-Path $scriptDir 'C-Drive-Cleaner.ps1'
$processOrchestrator = Join-Path $scriptDir 'core\ProcessOrchestrator.ps1'
$ruleCatalogModule = Join-Path $scriptDir 'core\RuleCatalog.ps1'
$copilotModule = Join-Path $scriptDir 'core\Copilot.ps1'
$assistantRouterModule = Join-Path $scriptDir 'core\AssistantToolRouter.ps1'
$agentConfigModule = Join-Path $scriptDir 'core\AgentConfig.ps1'
$agentProtocolModule = Join-Path $scriptDir 'core\AgentProtocol.ps1'
$uiActionBrokerModule = Join-Path $scriptDir 'core\UiActionBroker.ps1'
$flyAiTravelProviderModule = Join-Path $scriptDir 'core\FlyAiTravelProvider.ps1'
$agentHostScript = Join-Path $scriptDir 'AgentHost.ps1'
$travelHostScript = Join-Path $scriptDir 'TravelHost.ps1'
$assistantContractPath = Join-Path $scriptDir 'contracts\assistant-tools.json'
$versionManifestPath = Join-Path $scriptDir 'version.json'
$localDataRoot = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'CDriveCleaner' } else { Join-Path $env:TEMP 'CDriveCleaner' }
$reportPath = Join-Path (Join-Path $localDataRoot 'reports') 'C盘清理诊断报告.html'
$spriteSheetPath = Join-Path $scriptDir 'assets\cleaning-sprite-source.png'
$logoSvgPath = Join-Path $scriptDir 'assets\logo-animated.svg'
$logoSpritePath = Join-Path $scriptDir 'assets\logo-animated-sprite.png'
$logoFallbackPath = Join-Path $scriptDir 'assets\sugon-cloud-logo-red.png'
$assistantAgentAvatarPaths = @(
    (Join-Path $scriptDir 'assets\assistant-agent-wave-v2.png'),
    (Join-Path $scriptDir 'assets\assistant-agent-wave.png')
)
$assistantUserAvatarPaths = @(
    (Join-Path $scriptDir 'assets\assistant-user-custom.png')
) + @(1..6 | ForEach-Object { Join-Path $scriptDir ("assets\assistant-user-{0}.png" -f $_) })

$displayVersion = '未知'
try {
    $versionManifest = Get-Content -LiteralPath $versionManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not [string]::IsNullOrWhiteSpace([string]$versionManifest.version)) {
        $displayVersion = 'v{0}' -f [string]$versionManifest.version
    }
} catch {
    # 版本信息不应阻止主界面启动。
}

if (-not (Test-Path -LiteralPath $mainScript)) {
    [System.Windows.Forms.MessageBox]::Show("找不到主程序：`n$mainScript", 'C盘清理', 'OK', 'Error') | Out-Null
    exit 1
}
if (-not (Test-Path -LiteralPath $processOrchestrator) -or -not (Test-Path -LiteralPath $ruleCatalogModule) -or
    -not (Test-Path -LiteralPath $copilotModule) -or -not (Test-Path -LiteralPath $assistantRouterModule) -or
    -not (Test-Path -LiteralPath $agentConfigModule) -or -not (Test-Path -LiteralPath $agentProtocolModule) -or
    -not (Test-Path -LiteralPath $uiActionBrokerModule) -or -not (Test-Path -LiteralPath $flyAiTravelProviderModule) -or
    -not (Test-Path -LiteralPath $agentHostScript) -or -not (Test-Path -LiteralPath $travelHostScript) -or
    -not (Test-Path -LiteralPath $assistantContractPath)) {
    [System.Windows.Forms.MessageBox]::Show('缺少核心模块或助手契约，程序无法安全启动。', 'C盘清理', 'OK', 'Error') | Out-Null
    exit 1
}
. $processOrchestrator
. $ruleCatalogModule
. $copilotModule
. $assistantRouterModule
. $agentConfigModule
. $agentProtocolModule
. $uiActionBrokerModule
. $flyAiTravelProviderModule
$copilotTargets = @(Get-CDriveCleanupTargets)

function Get-CFreeText {
    try {
        $free = (New-Object System.IO.DriveInfo 'C:\').AvailableFreeSpace
        if ($free -ge 1GB) { return ('C 盘可用 {0:F2} GB' -f ($free / 1GB)) }
        return ('C 盘可用 {0:F0} MB' -f ($free / 1MB))
    } catch { return 'C 盘可用空间：未知' }
}

function Append-Log {
    param($Box, [string]$Text)
    if ($null -eq $Text) { return }
    $Box.AppendText($Text + [Environment]::NewLine)
    $Box.SelectionStart = $Box.Text.Length
    $Box.ScrollToCaret()
}

function Format-UiBytes {
    param([double]$Bytes)
    if ($Bytes -ge 1TB) { return ('{0:F2} TB' -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ('{0:F2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:F1} MB' -f ($Bytes / 1MB)) }
    return ('{0:F0} KB' -f ($Bytes / 1KB))
}

function Get-CDriveMetrics {
    try {
        $drive = New-Object System.IO.DriveInfo 'C:\'
        $used = [double]($drive.TotalSize - $drive.AvailableFreeSpace)
        $usedPercent = if ($drive.TotalSize -gt 0) { [Math]::Round(($used / $drive.TotalSize) * 100, 1) } else { 0 }
        return [PSCustomObject]@{ Total = [double]$drive.TotalSize; Used = $used; Free = [double]$drive.AvailableFreeSpace; UsedPercent = $usedPercent }
    } catch {
        return [PSCustomObject]@{ Total = 0.0; Used = 0.0; Free = 0.0; UsedPercent = 0.0 }
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'C 盘智能清理'
$form.Size = New-Object System.Drawing.Size(1240, 800)
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = New-Object System.Drawing.Size(1060, 680)
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
$form.BackColor = [System.Drawing.Color]::FromArgb(239, 242, 245)

$sideBar = New-Object System.Windows.Forms.Panel
$sideBar.Dock = 'Left'
$sideBar.Width = 116
$sideBar.BackColor = [System.Drawing.Color]::White

$sideDivider = New-Object System.Windows.Forms.Panel
$sideDivider.Dock = 'Right'
$sideDivider.Width = 1
$sideDivider.BackColor = [System.Drawing.Color]::FromArgb(222, 228, 233)

$navOverview = New-Object CDriveRoundedButton
$navOverview.Text = '概览'
$navOverview.Location = New-Object System.Drawing.Point(12, 78)
$navOverview.Size = New-Object System.Drawing.Size(88, 38)
$navOverview.BackColor = [System.Drawing.Color]::FromArgb(247, 249, 250)
$navOverview.ForeColor = [System.Drawing.Color]::FromArgb(119, 127, 133)
$navOverview.BorderColor = [System.Drawing.Color]::FromArgb(238, 238, 238)
$navOverview.HoverBackColor = [System.Drawing.Color]::FromArgb(244, 247, 249)
$navOverview.PressedBackColor = [System.Drawing.Color]::FromArgb(238, 242, 245)
$navOverview.Selected = $true
$navOverview.SelectedBackColor = [System.Drawing.Color]::FromArgb(251, 229, 231)
$navOverview.SelectedForeColor = [System.Drawing.Color]::FromArgb(181, 30, 40)
$navOverview.SelectedBorderColor = [System.Drawing.Color]::FromArgb(247, 210, 214)
$navOverview.SelectedHoverBackColor = [System.Drawing.Color]::FromArgb(252, 236, 237)
$navOverview.SelectedPressedBackColor = [System.Drawing.Color]::FromArgb(247, 220, 223)
$navOverview.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9, [System.Drawing.FontStyle]::Bold)
$navOverview.Cursor = [System.Windows.Forms.Cursors]::Hand

$navLogs = New-Object CDriveRoundedButton
$navLogs.Text = '运行日志'
$navLogs.Location = New-Object System.Drawing.Point(12, 126)
$navLogs.Size = New-Object System.Drawing.Size(88, 38)
$navLogs.BackColor = [System.Drawing.Color]::FromArgb(247, 249, 250)
$navLogs.ForeColor = [System.Drawing.Color]::FromArgb(119, 127, 133)
$navLogs.BorderColor = [System.Drawing.Color]::FromArgb(238, 238, 238)
$navLogs.HoverBackColor = [System.Drawing.Color]::FromArgb(244, 247, 249)
$navLogs.PressedBackColor = [System.Drawing.Color]::FromArgb(238, 242, 245)
$navLogs.SelectedBackColor = [System.Drawing.Color]::FromArgb(251, 229, 231)
$navLogs.SelectedForeColor = [System.Drawing.Color]::FromArgb(181, 30, 40)
$navLogs.SelectedBorderColor = [System.Drawing.Color]::FromArgb(247, 210, 214)
$navLogs.SelectedHoverBackColor = [System.Drawing.Color]::FromArgb(252, 236, 237)
$navLogs.SelectedPressedBackColor = [System.Drawing.Color]::FromArgb(247, 220, 223)
$navLogs.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9, [System.Drawing.FontStyle]::Bold)
$navLogs.Cursor = [System.Windows.Forms.Cursors]::Hand

$navSelection = New-Object CDriveRoundedButton
$navSelection.Text = '清理清单'
$navSelection.Location = New-Object System.Drawing.Point(12, 174)
$navSelection.Size = New-Object System.Drawing.Size(88, 38)
$navSelection.BackColor = [System.Drawing.Color]::FromArgb(247, 249, 250)
$navSelection.ForeColor = [System.Drawing.Color]::FromArgb(119, 127, 133)
$navSelection.BorderColor = [System.Drawing.Color]::FromArgb(238, 238, 238)
$navSelection.HoverBackColor = [System.Drawing.Color]::FromArgb(244, 247, 249)
$navSelection.PressedBackColor = [System.Drawing.Color]::FromArgb(238, 242, 245)
$navSelection.SelectedBackColor = [System.Drawing.Color]::FromArgb(251, 229, 231)
$navSelection.SelectedForeColor = [System.Drawing.Color]::FromArgb(181, 30, 40)
$navSelection.SelectedBorderColor = [System.Drawing.Color]::FromArgb(247, 210, 214)
$navSelection.SelectedHoverBackColor = [System.Drawing.Color]::FromArgb(252, 236, 237)
$navSelection.SelectedPressedBackColor = [System.Drawing.Color]::FromArgb(247, 220, 223)
$navSelection.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9, [System.Drawing.FontStyle]::Bold)
$navSelection.Cursor = [System.Windows.Forms.Cursors]::Hand

$navAssistant = New-Object CDriveRoundedButton
$navAssistant.Text = '智能助手'
$navAssistant.Location = New-Object System.Drawing.Point(12, 222)
$navAssistant.Size = New-Object System.Drawing.Size(88, 38)
$navAssistant.BackColor = [System.Drawing.Color]::FromArgb(247, 249, 250)
$navAssistant.ForeColor = [System.Drawing.Color]::FromArgb(119, 127, 133)
$navAssistant.BorderColor = [System.Drawing.Color]::FromArgb(238, 238, 238)
$navAssistant.HoverBackColor = [System.Drawing.Color]::FromArgb(244, 247, 249)
$navAssistant.PressedBackColor = [System.Drawing.Color]::FromArgb(238, 242, 245)
$navAssistant.SelectedBackColor = [System.Drawing.Color]::FromArgb(251, 229, 231)
$navAssistant.SelectedForeColor = [System.Drawing.Color]::FromArgb(181, 30, 40)
$navAssistant.SelectedBorderColor = [System.Drawing.Color]::FromArgb(247, 210, 214)
$navAssistant.SelectedHoverBackColor = [System.Drawing.Color]::FromArgb(252, 236, 237)
$navAssistant.SelectedPressedBackColor = [System.Drawing.Color]::FromArgb(247, 220, 223)
$navAssistant.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9, [System.Drawing.FontStyle]::Bold)
$navAssistant.Cursor = [System.Windows.Forms.Cursors]::Hand

$sideFooter = New-Object System.Windows.Forms.Label
$sideFooter.Text = '版本号 {0}' -f $displayVersion
$sideFooter.Font = New-Object System.Drawing.Font('Segoe UI', 7)
$sideFooter.ForeColor = [System.Drawing.Color]::FromArgb(147, 159, 168)
$sideFooter.AutoSize = $true
$sideFooter.Location = New-Object System.Drawing.Point(20, 0)
$sideFooter.Anchor = 'Bottom,Left'
$sideFooter.Add_Layout({ $sideFooter.Top = $sideBar.ClientSize.Height - 28 })
$sideBar.Controls.AddRange(@($sideDivider, $navOverview, $navLogs, $navSelection, $navAssistant, $sideFooter))

$workspace = New-Object System.Windows.Forms.Panel
$workspace.Dock = 'Fill'
$workspace.BackColor = [System.Drawing.Color]::FromArgb(239, 242, 245)

# 内容宿主与顶部栏分层：内容区域永远从顶部栏下边界开始，切换视图不会遮挡顶部内容。
$contentHost = New-Object System.Windows.Forms.Panel
$contentHost.Dock = 'None'
$contentHost.Anchor = 'Top,Bottom,Left,Right'
$contentHost.BackColor = [System.Drawing.Color]::FromArgb(239, 242, 245)

$topBar = New-Object System.Windows.Forms.Panel
$topBar.Dock = 'Top'
$topBar.Height = 74
$topBar.BackColor = [System.Drawing.Color]::White

$topRule = New-Object System.Windows.Forms.Panel
$topRule.Dock = 'Top'
$topRule.Height = 1
$topRule.BackColor = [System.Drawing.Color]::FromArgb(216, 224, 230)

$topDivider = New-Object System.Windows.Forms.Panel
$topDivider.Dock = 'Bottom'
$topDivider.Height = 1
$topDivider.BackColor = [System.Drawing.Color]::FromArgb(216, 224, 230)

$title = New-Object System.Windows.Forms.Label
$title.Text = 'C 盘智能清理'
$title.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 14, [System.Drawing.FontStyle]::Bold)
$title.ForeColor = [System.Drawing.Color]::FromArgb(29, 39, 48)
$title.Location = New-Object System.Drawing.Point(20, 13)
$title.AutoSize = $true

$brandLogo = New-Object System.Windows.Forms.PictureBox
$brandLogo.Location = New-Object System.Drawing.Point(11, 14)
$brandLogo.Size = New-Object System.Drawing.Size(94, 38)
$brandLogo.SizeMode = 'Zoom'
$brandLogo.BackColor = [System.Drawing.Color]::White

# Logo 作为侧栏品牌锚点，顶部只保留产品标题与操作区。
$sideBar.Controls.Add($brandLogo)

$logoFrames = New-Object System.Collections.Generic.List[System.Drawing.Bitmap]
$logoSpriteSheet = $null
$logoStaticImage = $null
$logoLoadError = $null
if ((Test-Path -LiteralPath $logoSvgPath) -and (Test-Path -LiteralPath $logoSpritePath)) {
    try {
        $logoSpriteSheet = [System.Drawing.Bitmap]::new($logoSpritePath)
        # 浏览器从 SVG 原时间轴预渲染：135 帧、15 x 9 网格、94 x 38px/帧。
        # 图像已经是控件尺寸，播放时不发生缩放重采样。
        $logoColumns = 15
        $logoRows = 9
        $logoFrameWidth = [int]($logoSpriteSheet.Width / $logoColumns)
        $logoFrameHeight = [int]($logoSpriteSheet.Height / $logoRows)
        if ($logoFrameWidth -ne 94 -or $logoFrameHeight -ne 38) {
            throw 'Logo 序列图尺寸不符合 94 x 38px 帧规范。'
        }
        for ($row = 0; $row -lt $logoRows; $row++) {
            for ($column = 0; $column -lt $logoColumns; $column++) {
                $rect = [System.Drawing.Rectangle]::new(($column * $logoFrameWidth), ($row * $logoFrameHeight), $logoFrameWidth, $logoFrameHeight)
                [void]$logoFrames.Add($logoSpriteSheet.Clone($rect, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb))
            }
        }
    } catch {
        $logoLoadError = $_.Exception.Message
    }
}
# 静止状态直接使用 SVG 序列的最终稳定帧，保证动画结束和常驻 Logo 的尺寸、位置完全一致。
if ($logoFrames.Count -gt 0) {
    $logoStaticImage = $logoFrames[$logoFrames.Count - 1]
    $brandLogo.Image = $logoStaticImage
} elseif (Test-Path -LiteralPath $logoFallbackPath) {
    try {
        $logoStaticImage = [System.Drawing.Bitmap]::new($logoFallbackPath)
        $brandLogo.Image = $logoStaticImage
    } catch {
        if (-not $logoLoadError) { $logoLoadError = $_.Exception.Message }
    }
}

$hint = New-Object System.Windows.Forms.Label
$hint.Text = '安全扫描、缓存清理与前后空间对比'
$hint.Location = New-Object System.Drawing.Point(21, 43)
$hint.Size = New-Object System.Drawing.Size(270, 22)
$hint.ForeColor = [System.Drawing.Color]::FromArgb(122, 137, 149)

# 右上角动画：序列图按 4x2 网格切成 8 帧，仅在清理任务运行时播放。
$animationImage = New-Object System.Windows.Forms.PictureBox
$animationImage.Size = New-Object System.Drawing.Size(94, 74)
$animationImage.Dock = 'Right'
$animationImage.SizeMode = 'Zoom'
$animationImage.BackColor = [System.Drawing.Color]::Transparent

$spriteFrames = New-Object System.Collections.Generic.List[System.Drawing.Bitmap]
$spriteSheet = $null
$spriteLoadError = $null
if (Test-Path -LiteralPath $spriteSheetPath) {
    try {
        $spriteSheet = [System.Drawing.Bitmap]::new($spriteSheetPath)
        $frameWidth = [int]($spriteSheet.Width / 4)
        $frameHeight = [int]($spriteSheet.Height / 2)
        for ($row = 0; $row -lt 2; $row++) {
            for ($column = 0; $column -lt 4; $column++) {
                $rect = [System.Drawing.Rectangle]::new(($column * $frameWidth), ($row * $frameHeight), $frameWidth, $frameHeight)
                [void]$spriteFrames.Add($spriteSheet.Clone($rect, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb))
            }
        }
        if ($spriteFrames.Count -gt 0) { $animationImage.Image = $spriteFrames[0] }
    } catch {
        $spriteLoadError = $_.Exception.Message
    }
}

$animationState = @{ Timer = $null; Index = 0; Active = $false }
$animationTimer = New-Object System.Windows.Forms.Timer
$animationTimer.Interval = 150
$animationTimer.Add_Tick({
    if (-not $animationState.Active -or $spriteFrames.Count -eq 0) { return }
    $animationState.Index = ($animationState.Index + 1) % $spriteFrames.Count
    $animationImage.Image = $spriteFrames[$animationState.Index]
    if ($btnClean) {
        $btnClean.BackColor = if (($animationState.Index % 2) -eq 0) {
            [System.Drawing.Color]::White
        } else {
            [System.Drawing.Color]::FromArgb(252, 236, 237)
        }
    }
})
$animationState.Timer = $animationTimer

function Start-CleanAnimation {
    if ($spriteFrames.Count -eq 0) { return }
    $animationState.Index = 0
    $animationState.Active = $true
    $animationImage.Image = $spriteFrames[0]
    if ($btnClean) { $btnClean.Text = '正在清理' }
    $animationTimer.Start()
}

function Stop-CleanAnimation {
    $animationState.Active = $false
    $animationTimer.Stop()
    $animationState.Index = 0
    if ($spriteFrames.Count -gt 0) { $animationImage.Image = $spriteFrames[0] }
    if ($btnClean) {
        $btnClean.Text = '清理安全项'
        $btnClean.BackColor = [System.Drawing.Color]::White
    }
}

# Logo 默认显示 SVG 最终稳定帧；仅在悬停或点击时按 SVG 原速率播放一次。
# 使用真实经过时间定位帧，避免 UI Timer 在窗口繁忙时逐帧累积导致变慢或卡顿。
$logoAnimationDurationMs = 2220.0
$logoAnimationState = @{ Timer = $null; Clock = [System.Diagnostics.Stopwatch]::new(); Index = 0; Active = $false }
$logoAnimationTimer = New-Object System.Windows.Forms.Timer
$logoAnimationTimer.Interval = 15
$logoAnimationTimer.Add_Tick({
    if (-not $logoAnimationState.Active -or $logoFrames.Count -eq 0) { return }
    $elapsedMs = $logoAnimationState.Clock.Elapsed.TotalMilliseconds
    if ($elapsedMs -ge $logoAnimationDurationMs) {
        # 静止状态与最后一帧共用同一位图，消除结束处的位置跳变。
        $logoAnimationState.Index = $logoFrames.Count - 1
        $brandLogo.Image = $logoStaticImage
        Stop-LogoAnimation
        return
    }
    $nextIndex = [Math]::Min($logoFrames.Count - 1, [int][Math]::Floor(($elapsedMs / $logoAnimationDurationMs) * ($logoFrames.Count - 1)))
    if ($nextIndex -ne $logoAnimationState.Index) {
        $logoAnimationState.Index = $nextIndex
        $brandLogo.Image = $logoFrames[$nextIndex]
    }
})
$logoAnimationState.Timer = $logoAnimationTimer

function Start-LogoAnimation {
    if ($logoFrames.Count -lt 2 -or $logoAnimationState.Active) { return }
    $logoAnimationState.Index = 0
    $logoAnimationState.Active = $true
    $brandLogo.Image = $logoFrames[0]
    $logoAnimationState.Clock.Restart()
    $logoAnimationTimer.Start()
}

function Stop-LogoAnimation {
    $logoAnimationState.Active = $false
    $logoAnimationTimer.Stop()
    $logoAnimationState.Clock.Reset()
    $logoAnimationState.Index = 0
    if ($logoStaticImage) { $brandLogo.Image = $logoStaticImage }
    elseif ($logoFrames.Count -gt 0) { $brandLogo.Image = $logoFrames[0] }
}

$brandLogo.Add_MouseEnter({ Start-LogoAnimation })
$brandLogo.Add_Click({ Start-LogoAnimation })

$status = New-Object System.Windows.Forms.Label
$status.Text = Get-CFreeText
$status.ForeColor = [System.Drawing.Color]::FromArgb(181, 30, 40)
$status.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9, [System.Drawing.FontStyle]::Bold)
$status.AutoSize = $true
$status.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)

$statusPulse = New-Object System.Windows.Forms.Label
$statusPulse.Text = '●'
$statusPulse.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$statusPulse.ForeColor = [System.Drawing.Color]::FromArgb(181, 30, 40)
$statusPulse.Size = New-Object System.Drawing.Size(16, 24)
$statusPulse.TextAlign = 'MiddleCenter'
$statusPulse.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 0)

$statusCluster = New-Object System.Windows.Forms.FlowLayoutPanel
$statusCluster.Location = New-Object System.Drawing.Point(278, 25)
$statusCluster.Size = New-Object System.Drawing.Size(190, 28)
$statusCluster.FlowDirection = 'LeftToRight'
$statusCluster.WrapContents = $false
$statusCluster.Padding = New-Object System.Windows.Forms.Padding(0)
$statusCluster.BackColor = [System.Drawing.Color]::Transparent
$statusCluster.Controls.AddRange(@($statusPulse, $status))

function Set-ActionButtonStyle {
    param(
        [CDriveRoundedButton]$Button,
        [System.Drawing.Color]$BackColor,
        [System.Drawing.Color]$ForeColor,
        [System.Drawing.Color]$BorderColor,
        [System.Drawing.Color]$HoverColor,
        [System.Drawing.Color]$PressedColor
    )
    $Button.BackColor = $BackColor
    $Button.ForeColor = $ForeColor
    $Button.BorderColor = $BorderColor
    $Button.HoverBackColor = $HoverColor
    $Button.PressedBackColor = $PressedColor
    $Button.CornerRadius = 8
    $Button.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9, [System.Drawing.FontStyle]::Bold)
    $Button.Cursor = [System.Windows.Forms.Cursors]::Hand
}

$toolbar = New-Object System.Windows.Forms.FlowLayoutPanel
$toolbar.Size = New-Object System.Drawing.Size(440, 74)
$toolbar.Dock = 'Right'
$toolbar.Padding = New-Object System.Windows.Forms.Padding(0, 18, 0, 0)
$toolbar.FlowDirection = 'LeftToRight'
$toolbar.WrapContents = $false
$toolbar.BackColor = [System.Drawing.Color]::Transparent

$btnScan = New-Object CDriveRoundedButton
$btnScan.Text = '开始扫描'
$btnScan.Size = New-Object System.Drawing.Size(104, 36)
$btnScan.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
Set-ActionButtonStyle $btnScan ([System.Drawing.Color]::FromArgb(181, 30, 40)) ([System.Drawing.Color]::White) ([System.Drawing.Color]::FromArgb(181, 30, 40)) ([System.Drawing.Color]::FromArgb(160, 26, 35)) ([System.Drawing.Color]::FromArgb(140, 21, 30))

$btnReport = New-Object CDriveRoundedButton
$btnReport.Text = '打开报告'
$btnReport.Size = New-Object System.Drawing.Size(104, 36)
$btnReport.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
Set-ActionButtonStyle $btnReport ([System.Drawing.Color]::White) ([System.Drawing.Color]::FromArgb(72, 86, 99)) ([System.Drawing.Color]::FromArgb(214, 222, 228)) ([System.Drawing.Color]::FromArgb(244, 247, 249)) ([System.Drawing.Color]::FromArgb(235, 240, 243))

$btnClean = New-Object CDriveRoundedButton
$btnClean.Text = '清理安全项'
$btnClean.Size = New-Object System.Drawing.Size(104, 36)
$btnClean.Margin = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
Set-ActionButtonStyle $btnClean ([System.Drawing.Color]::White) ([System.Drawing.Color]::FromArgb(181, 30, 40)) ([System.Drawing.Color]::FromArgb(214, 222, 228)) ([System.Drawing.Color]::FromArgb(252, 236, 237)) ([System.Drawing.Color]::FromArgb(247, 220, 223))

$btnExit = New-Object CDriveRoundedButton
$btnExit.Text = '退出'
$btnExit.Size = New-Object System.Drawing.Size(104, 36)
$btnExit.Margin = New-Object System.Windows.Forms.Padding(0)
Set-ActionButtonStyle $btnExit ([System.Drawing.Color]::White) ([System.Drawing.Color]::FromArgb(122, 137, 149)) ([System.Drawing.Color]::FromArgb(214, 222, 228)) ([System.Drawing.Color]::FromArgb(244, 247, 249)) ([System.Drawing.Color]::FromArgb(235, 240, 243))

$toolbar.Controls.AddRange(@($btnScan, $btnReport, $btnClean, $btnExit))

function New-StatCard {
    param([string]$Caption, [System.Drawing.Color]$Accent)
    $card = New-Object CDriveRoundedPanel
    $card.BackColor = [System.Drawing.Color]::White
    $card.Dock = 'Fill'
    $card.Padding = New-Object System.Windows.Forms.Padding(16, 13, 16, 12)

    $marker = New-Object System.Windows.Forms.Panel
    $marker.Location = New-Object System.Drawing.Point(16, 13)
    $marker.Size = New-Object System.Drawing.Size(4, 16)
    $marker.BackColor = $Accent

    $captionLabel = New-Object System.Windows.Forms.Label
    $captionLabel.Text = $Caption
    $captionLabel.ForeColor = [System.Drawing.Color]::FromArgb(118, 133, 145)
    $captionLabel.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 8)
    $captionLabel.Location = New-Object System.Drawing.Point(28, 12)
    $captionLabel.Size = New-Object System.Drawing.Size(180, 18)
    $captionLabel.AutoSize = $false
    $captionLabel.TextAlign = 'MiddleLeft'

    $valueLabel = New-Object System.Windows.Forms.Label
    $valueLabel.Text = '--'
    $valueLabel.ForeColor = [System.Drawing.Color]::FromArgb(32, 43, 53)
    $valueLabel.Font = New-Object System.Drawing.Font('Segoe UI', 18, [System.Drawing.FontStyle]::Bold)
    $valueLabel.Location = New-Object System.Drawing.Point(16, 33)
    $valueLabel.AutoSize = $true

    $detailLabel = New-Object System.Windows.Forms.Label
    $detailLabel.Text = '读取中'
    $detailLabel.ForeColor = [System.Drawing.Color]::FromArgb(144, 156, 166)
    $detailLabel.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 8)
    $detailBand = New-Object System.Windows.Forms.Panel
    $detailBand.Location = New-Object System.Drawing.Point(12, 73)
    $detailBand.Size = New-Object System.Drawing.Size(210, 20)
    $detailBand.Anchor = 'Top,Left'
    $detailBand.BackColor = [System.Drawing.Color]::FromArgb(248, 250, 251)

    $detailLabel.Location = New-Object System.Drawing.Point(6, 1)
    $detailLabel.Size = New-Object System.Drawing.Size(198, 18)
    $detailLabel.Anchor = 'Top,Left'
    $detailLabel.AutoSize = $false
    $detailLabel.TextAlign = 'MiddleLeft'
    $detailBand.Controls.Add($detailLabel)
    $card.Controls.AddRange(@($marker, $captionLabel, $valueLabel, $detailBand))
    return [PSCustomObject]@{ Panel = $card; Value = $valueLabel; Detail = $detailLabel }
}

$dashboardGrid = New-Object System.Windows.Forms.TableLayoutPanel
$dashboardGrid.Dock = 'Fill'
$dashboardGrid.Padding = New-Object System.Windows.Forms.Padding(18)
$dashboardGrid.BackColor = [System.Drawing.Color]::FromArgb(239, 242, 245)
$dashboardGrid.ColumnCount = 4
$dashboardGrid.RowCount = 4
for ($i = 0; $i -lt 4; $i++) {
    [void]$dashboardGrid.ColumnStyles.Add([System.Windows.Forms.ColumnStyle]::new([System.Windows.Forms.SizeType]::Percent, 25))
}
[void]$dashboardGrid.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Absolute, 104))
[void]$dashboardGrid.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Absolute, 218))
[void]$dashboardGrid.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Absolute, 32))
[void]$dashboardGrid.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Percent, 100))

$capacityCard = New-StatCard 'C 盘总容量' ([System.Drawing.Color]::FromArgb(181, 30, 40))
$usedCard = New-StatCard '已用空间' ([System.Drawing.Color]::FromArgb(112, 116, 120))
$freeCard = New-StatCard '当前可用空间' ([System.Drawing.Color]::FromArgb(145, 149, 153))
$freedCard = New-StatCard '本次释放空间' ([System.Drawing.Color]::FromArgb(203, 75, 65))
$statCards = @($capacityCard, $usedCard, $freeCard, $freedCard)
for ($i = 0; $i -lt $statCards.Count; $i++) {
    $statCards[$i].Panel.Margin = if ($i -lt ($statCards.Count - 1)) { New-Object System.Windows.Forms.Padding(0, 0, 10, 0) } else { New-Object System.Windows.Forms.Padding(0) }
    $dashboardGrid.Controls.Add($statCards[$i].Panel, $i, 0)
}

$diskCard = New-Object CDriveRoundedPanel
$diskCard.Dock = 'Fill'
$diskCard.Margin = New-Object System.Windows.Forms.Padding(0, 14, 6, 0)
$diskCard.BackColor = [System.Drawing.Color]::White

$diskTitle = New-Object System.Windows.Forms.Label
$diskTitle.Text = '磁盘状态'
$diskTitle.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10, [System.Drawing.FontStyle]::Bold)
$diskTitle.ForeColor = [System.Drawing.Color]::FromArgb(36, 48, 58)
$diskTitle.Location = New-Object System.Drawing.Point(18, 16)
$diskTitle.AutoSize = $true

$diskPercent = New-Object System.Windows.Forms.Label
$diskPercent.Text = '--% 已用'
$diskPercent.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$diskPercent.ForeColor = [System.Drawing.Color]::FromArgb(181, 30, 40)
$diskPercent.Location = New-Object System.Drawing.Point(18, 51)
$diskPercent.AutoSize = $true

$diskUsedText = New-Object System.Windows.Forms.Label
$diskUsedText.Text = '已用 --'
$diskUsedText.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 14, [System.Drawing.FontStyle]::Bold)
$diskUsedText.ForeColor = [System.Drawing.Color]::FromArgb(34, 44, 53)
$diskUsedText.Location = New-Object System.Drawing.Point(18, 74)
$diskUsedText.AutoSize = $true

$diskFreeText = New-Object System.Windows.Forms.Label
$diskFreeText.Text = '可用 --'
$diskFreeText.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
$diskFreeText.ForeColor = [System.Drawing.Color]::FromArgb(107, 126, 136)
$diskFreeText.Location = New-Object System.Drawing.Point(20, 113)
$diskFreeText.AutoSize = $true

$diskTrack = New-Object CDriveRoundedPanel
$diskTrack.Location = New-Object System.Drawing.Point(18, 146)
$diskTrack.Size = New-Object System.Drawing.Size(1, 10)
$diskTrack.Anchor = 'Top,Left,Right'
$diskTrack.BackColor = [System.Drawing.Color]::FromArgb(231, 236, 241)

$diskUsedBar = New-Object CDriveRoundedPanel
$diskUsedBar.Location = New-Object System.Drawing.Point(1, 1)
$diskUsedBar.Size = New-Object System.Drawing.Size(0, 8)
$diskUsedBar.BackColor = [System.Drawing.Color]::FromArgb(181, 30, 40)
$diskTrack.Controls.Add($diskUsedBar)

$diskLegend = New-Object System.Windows.Forms.Label
$diskLegend.Text = '红色为已用空间，灰色区域为可用空间'
$diskLegend.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 8)
$diskLegend.ForeColor = [System.Drawing.Color]::FromArgb(145, 157, 166)
$diskLegend.Location = New-Object System.Drawing.Point(18, 174)
$diskLegend.AutoSize = $true
$diskCard.Controls.AddRange(@($diskTitle, $diskPercent, $diskUsedText, $diskFreeText, $diskTrack, $diskLegend))

$compareCard = New-Object CDriveRoundedPanel
$compareCard.Dock = 'Fill'
$compareCard.Margin = New-Object System.Windows.Forms.Padding(6, 14, 0, 0)
$compareCard.BackColor = [System.Drawing.Color]::White

$compareTitle = New-Object System.Windows.Forms.Label
$compareTitle.Text = '清理前后对比'
$compareTitle.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10, [System.Drawing.FontStyle]::Bold)
$compareTitle.ForeColor = [System.Drawing.Color]::FromArgb(36, 48, 58)
$compareTitle.Location = New-Object System.Drawing.Point(18, 16)
$compareTitle.AutoSize = $true

$compareDescription = New-Object System.Windows.Forms.Label
$compareDescription.Text = '进度条表示可用空间占 C 盘总容量的比例'
$compareDescription.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 8)
$compareDescription.ForeColor = [System.Drawing.Color]::FromArgb(130, 145, 155)
$compareDescription.Location = New-Object System.Drawing.Point(18, 44)
$compareDescription.AutoSize = $true

$beforeCaption = New-Object System.Windows.Forms.Label
$beforeCaption.Text = '清理前'
$beforeCaption.ForeColor = [System.Drawing.Color]::FromArgb(122, 137, 149)
$beforeCaption.Location = New-Object System.Drawing.Point(18, 77)
$beforeCaption.AutoSize = $true

$beforeValue = New-Object System.Windows.Forms.Label
$beforeValue.Text = '等待清理'
$beforeValue.ForeColor = [System.Drawing.Color]::FromArgb(44, 56, 66)
$beforeValue.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$beforeValue.Location = New-Object System.Drawing.Point(88, 74)
$beforeValue.AutoSize = $true

$beforeTrack = New-Object CDriveRoundedPanel
$beforeTrack.Location = New-Object System.Drawing.Point(18, 106)
$beforeTrack.Size = New-Object System.Drawing.Size(1, 8)
$beforeTrack.Anchor = 'Top,Left,Right'
$beforeTrack.BackColor = [System.Drawing.Color]::FromArgb(233, 238, 242)
$beforeBar = New-Object CDriveRoundedPanel
$beforeBar.Location = New-Object System.Drawing.Point(1, 1)
$beforeBar.Size = New-Object System.Drawing.Size(0, 6)
$beforeBar.BackColor = [System.Drawing.Color]::FromArgb(142, 177, 241)
$beforeTrack.Controls.Add($beforeBar)

$afterCaption = New-Object System.Windows.Forms.Label
$afterCaption.Text = '清理后'
$afterCaption.ForeColor = [System.Drawing.Color]::FromArgb(122, 137, 149)
$afterCaption.Location = New-Object System.Drawing.Point(18, 126)
$afterCaption.AutoSize = $true

$afterValue = New-Object System.Windows.Forms.Label
$afterValue.Text = '等待清理'
$afterValue.ForeColor = [System.Drawing.Color]::FromArgb(44, 56, 66)
$afterValue.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$afterValue.Location = New-Object System.Drawing.Point(88, 123)
$afterValue.AutoSize = $true

$afterTrack = New-Object CDriveRoundedPanel
$afterTrack.Location = New-Object System.Drawing.Point(18, 155)
$afterTrack.Size = New-Object System.Drawing.Size(1, 8)
$afterTrack.Anchor = 'Top,Left,Right'
$afterTrack.BackColor = [System.Drawing.Color]::FromArgb(233, 238, 242)
$afterBar = New-Object CDriveRoundedPanel
$afterBar.Location = New-Object System.Drawing.Point(1, 1)
$afterBar.Size = New-Object System.Drawing.Size(0, 6)
$afterBar.BackColor = [System.Drawing.Color]::FromArgb(181, 30, 40)
$afterTrack.Controls.Add($afterBar)

$compareResult = New-Object System.Windows.Forms.Label
$compareResult.Text = '尚未执行清理，当前显示实时磁盘统计。'
$compareResult.ForeColor = [System.Drawing.Color]::FromArgb(109, 126, 136)
$compareResult.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 8)
$compareResult.Location = New-Object System.Drawing.Point(18, 181)
$compareResult.AutoSize = $true
$compareCard.Controls.AddRange(@($compareTitle, $compareDescription, $beforeCaption, $beforeValue, $beforeTrack, $afterCaption, $afterValue, $afterTrack, $compareResult))

$logHeader = New-Object System.Windows.Forms.Panel
$logHeader.Dock = 'Fill'
$logHeader.Margin = New-Object System.Windows.Forms.Padding(0, 12, 0, 0)
$logHeader.BackColor = [System.Drawing.Color]::Transparent

$logTitle = New-Object System.Windows.Forms.Label
$logTitle.Text = '运行日志'
$logTitle.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10, [System.Drawing.FontStyle]::Bold)
$logTitle.ForeColor = [System.Drawing.Color]::FromArgb(49, 62, 72)
$logTitle.Location = New-Object System.Drawing.Point(0, 4)
$logTitle.AutoSize = $true

$logMeta = New-Object System.Windows.Forms.Label
$logMeta.Text = 'LIVE OUTPUT'
$logMeta.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
$logMeta.ForeColor = [System.Drawing.Color]::FromArgb(181, 30, 40)
$logMeta.Location = New-Object System.Drawing.Point(78, 7)
$logMeta.AutoSize = $true
$logHeader.Controls.AddRange(@($logTitle, $logMeta))

$logShell = New-Object CDriveRoundedPanel
$logShell.Dock = 'Fill'
$logShell.Margin = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)
$logShell.Padding = New-Object System.Windows.Forms.Padding(1)
$logShell.BackColor = [System.Drawing.Color]::FromArgb(203, 213, 220)

$logContent = New-Object System.Windows.Forms.Panel
$logContent.Dock = 'Fill'
$logContent.Padding = New-Object System.Windows.Forms.Padding(10, 8, 10, 8)
$logContent.BackColor = [System.Drawing.Color]::FromArgb(18, 25, 29)

$log = New-Object System.Windows.Forms.TextBox
$log.Multiline = $true
$log.ScrollBars = 'Vertical'
$log.ReadOnly = $true
$log.WordWrap = $true
$log.BorderStyle = 'None'
$log.Dock = 'Fill'
$log.Font = New-Object System.Drawing.Font('Consolas', 9)
$log.BackColor = [System.Drawing.Color]::FromArgb(18, 25, 29)
$log.ForeColor = [System.Drawing.Color]::FromArgb(224, 224, 224)
$logContent.Controls.Add($log)
$logShell.Controls.Add($logContent)

# 扫描后的选择视图：候选项与建议分层展示，用户必须主动勾选后才可执行清理。
$selectionView = New-Object System.Windows.Forms.Panel
$selectionView.Dock = 'Fill'
$selectionView.BackColor = [System.Drawing.Color]::FromArgb(239, 242, 245)
$selectionView.Padding = New-Object System.Windows.Forms.Padding(18)
$selectionView.Visible = $false

$selectionLayout = New-Object System.Windows.Forms.TableLayoutPanel
$selectionLayout.Dock = 'Fill'
$selectionLayout.ColumnCount = 1
$selectionLayout.RowCount = 3
$selectionLayout.BackColor = [System.Drawing.Color]::Transparent
[void]$selectionLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Absolute, 58))
[void]$selectionLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Absolute, 50))
[void]$selectionLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Percent, 100))

$selectionHeader = New-Object System.Windows.Forms.Panel
$selectionHeader.Dock = 'Fill'
$selectionHeader.BackColor = [System.Drawing.Color]::Transparent
$selectionTitle = New-Object System.Windows.Forms.Label
$selectionTitle.Text = '清理清单'
$selectionTitle.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 13, [System.Drawing.FontStyle]::Bold)
$selectionTitle.ForeColor = [System.Drawing.Color]::FromArgb(35, 46, 55)
$selectionTitle.Location = New-Object System.Drawing.Point(0, 2)
$selectionTitle.AutoSize = $true
$selectionDescription = New-Object System.Windows.Forms.Label
$selectionDescription.Text = '扫描后逐项选择。建议只说明可重建性，不会替你做删除决定。'
$selectionDescription.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 8)
$selectionDescription.ForeColor = [System.Drawing.Color]::FromArgb(122, 137, 149)
$selectionDescription.Location = New-Object System.Drawing.Point(1, 31)
$selectionDescription.AutoSize = $true
$selectionHeader.Controls.AddRange(@($selectionTitle, $selectionDescription))

$selectionActionBar = New-Object CDriveRoundedPanel
$selectionActionBar.Dock = 'Fill'
$selectionActionBar.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
$selectionActionBar.BackColor = [System.Drawing.Color]::White
$selectionActionBar.BorderColor = [System.Drawing.Color]::FromArgb(221, 227, 232)
$selectionActionBar.CornerRadius = 8
$selectionSummary = New-Object System.Windows.Forms.Label
$selectionSummary.Text = '请先完成扫描'
$selectionSummary.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9, [System.Drawing.FontStyle]::Bold)
$selectionSummary.ForeColor = [System.Drawing.Color]::FromArgb(69, 83, 94)
$selectionSummary.Location = New-Object System.Drawing.Point(14, 13)
$selectionSummary.AutoSize = $true

$btnSelectSuggested = New-Object CDriveRoundedButton
$btnSelectSuggested.Text = '勾选建议项'
$btnSelectSuggested.Size = New-Object System.Drawing.Size(104, 30)
Set-ActionButtonStyle $btnSelectSuggested ([System.Drawing.Color]::FromArgb(251, 229, 231)) ([System.Drawing.Color]::FromArgb(181, 30, 40)) ([System.Drawing.Color]::FromArgb(247, 210, 214)) ([System.Drawing.Color]::FromArgb(252, 236, 237)) ([System.Drawing.Color]::FromArgb(247, 220, 223))

$btnClearSelection = New-Object CDriveRoundedButton
$btnClearSelection.Text = '清空选择'
$btnClearSelection.Size = New-Object System.Drawing.Size(88, 30)
Set-ActionButtonStyle $btnClearSelection ([System.Drawing.Color]::White) ([System.Drawing.Color]::FromArgb(97, 112, 123)) ([System.Drawing.Color]::FromArgb(214, 222, 228)) ([System.Drawing.Color]::FromArgb(244, 247, 249)) ([System.Drawing.Color]::FromArgb(235, 240, 243))
$selectionActionBar.Controls.AddRange(@($selectionSummary, $btnSelectSuggested, $btnClearSelection))

$selectionItemsPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$selectionItemsPanel.Dock = 'Fill'
$selectionItemsPanel.AutoScroll = $true
$selectionItemsPanel.HorizontalScroll.Enabled = $false
$selectionItemsPanel.HorizontalScroll.Visible = $false
$selectionItemsPanel.FlowDirection = 'TopDown'
$selectionItemsPanel.WrapContents = $false
$selectionItemsPanel.Padding = New-Object System.Windows.Forms.Padding(0, 0, 8, 0)
$selectionItemsPanel.BackColor = [System.Drawing.Color]::Transparent

$selectionLayout.Controls.Add($selectionHeader, 0, 0)
$selectionLayout.Controls.Add($selectionActionBar, 0, 1)
$selectionLayout.Controls.Add($selectionItemsPanel, 0, 2)
$selectionView.Controls.Add($selectionLayout)

$assistantView = New-Object System.Windows.Forms.Panel
$assistantView.Dock = 'Fill'
$assistantView.BackColor = [System.Drawing.Color]::FromArgb(239, 242, 245)
$assistantView.Padding = New-Object System.Windows.Forms.Padding(18)
$assistantView.Visible = $false

$assistantLayout = New-Object System.Windows.Forms.TableLayoutPanel
$assistantLayout.Dock = 'Fill'
$assistantLayout.ColumnCount = 1
$assistantLayout.RowCount = 3
$assistantLayout.BackColor = [System.Drawing.Color]::Transparent
[void]$assistantLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Absolute, 58))
[void]$assistantLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Percent, 100))
[void]$assistantLayout.RowStyles.Add([System.Windows.Forms.RowStyle]::new([System.Windows.Forms.SizeType]::Absolute, 54))

$assistantHeader = New-Object System.Windows.Forms.Panel
$assistantHeader.Dock = 'Fill'
$assistantHeader.BackColor = [System.Drawing.Color]::Transparent
$assistantTitle = New-Object System.Windows.Forms.Label
$assistantTitle.Text = '智能助手'
$assistantTitle.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 13, [System.Drawing.FontStyle]::Bold)
$assistantTitle.ForeColor = [System.Drawing.Color]::FromArgb(35, 46, 55)
$assistantTitle.Location = New-Object System.Drawing.Point(0, 2)
$assistantTitle.AutoSize = $true
$assistantStatus = New-Object System.Windows.Forms.Label
$assistantStatus.Text = 'LOCAL  ·  SAFE MODE'
$assistantStatus.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
$assistantStatus.ForeColor = [System.Drawing.Color]::FromArgb(181, 30, 40)
$assistantStatus.Location = New-Object System.Drawing.Point(92, 7)
$assistantStatus.AutoSize = $true
$assistantDescription = New-Object System.Windows.Forms.Label
$assistantDescription.Text = '可对话清理磁盘，也可用飞猪规划旅行；最终操作由你确认。'
$assistantDescription.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 8)
$assistantDescription.ForeColor = [System.Drawing.Color]::FromArgb(122, 137, 149)
$assistantDescription.Location = New-Object System.Drawing.Point(1, 31)
$assistantDescription.AutoSize = $true
$assistantHeader.Controls.AddRange(@($assistantTitle, $assistantStatus, $assistantDescription))

$assistantShell = New-Object CDriveRoundedPanel
$assistantShell.Dock = 'Fill'
$assistantShell.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
$assistantShell.Padding = New-Object System.Windows.Forms.Padding(8, 12, 4, 8)
$assistantShell.BackColor = [System.Drawing.Color]::FromArgb(247, 249, 250)
$assistantShell.BorderColor = [System.Drawing.Color]::FromArgb(220, 226, 231)
$assistantShell.CornerRadius = 8
$assistantChatSurface = New-Object System.Windows.Forms.FlowLayoutPanel
$assistantChatSurface.Dock = 'Fill'
$assistantChatSurface.AutoScroll = $true
$assistantChatSurface.FlowDirection = 'TopDown'
$assistantChatSurface.WrapContents = $false
$assistantChatSurface.Padding = New-Object System.Windows.Forms.Padding(4, 2, 8, 6)
$assistantChatSurface.BackColor = [System.Drawing.Color]::Transparent
$assistantChatSurface.HorizontalScroll.Enabled = $false
$assistantChatSurface.HorizontalScroll.Visible = $false

# Kept as a non-visual accessibility and test transcript. Chat bubbles are the user-facing renderer.
$assistantTranscript = New-Object System.Windows.Forms.RichTextBox
$assistantTranscript.Visible = $false
$assistantTranscript.ReadOnly = $true
$assistantTranscript.Text = ''
$assistantShell.Controls.Add($assistantChatSurface)

$assistantAgentAvatarImage = $null
$assistantUserAvatarImage = $null
try {
    $availableAgentAvatar = @($assistantAgentAvatarPaths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }) | Select-Object -First 1
    if ($availableAgentAvatar) {
        $assistantAgentAvatarImage = [System.Drawing.Image]::FromFile([string]$availableAgentAvatar)
    }
    $availableUserAvatars = @($assistantUserAvatarPaths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
    if ($availableUserAvatars.Count -gt 0) {
        $assistantUserAvatarImage = [System.Drawing.Image]::FromFile([string]$availableUserAvatars[0])
    }
} catch {
    $assistantAgentAvatarImage = $null
    $assistantUserAvatarImage = $null
}

$assistantComposer = New-Object CDriveRoundedPanel
$assistantComposer.Dock = 'Fill'
$assistantComposer.BackColor = [System.Drawing.Color]::White
$assistantComposer.BorderColor = [System.Drawing.Color]::FromArgb(220, 226, 231)
$assistantComposer.CornerRadius = 8
$assistantInput = New-Object System.Windows.Forms.TextBox
$assistantInput.BorderStyle = 'None'
$assistantInput.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
$assistantInput.ForeColor = [System.Drawing.Color]::FromArgb(48, 62, 72)
$assistantInput.Location = New-Object System.Drawing.Point(14, 17)
$assistantInput.Anchor = 'Top,Left,Right'
$assistantInput.Width = 1
$assistantInput.Text = '哪些项目建议清理？'

$btnAssistantApply = New-Object CDriveRoundedButton
$btnAssistantApply.Text = '应用建议'
$btnAssistantApply.Size = New-Object System.Drawing.Size(92, 32)
Set-ActionButtonStyle $btnAssistantApply ([System.Drawing.Color]::White) ([System.Drawing.Color]::FromArgb(181, 30, 40)) ([System.Drawing.Color]::FromArgb(214, 222, 228)) ([System.Drawing.Color]::FromArgb(252, 236, 237)) ([System.Drawing.Color]::FromArgb(247, 220, 223))
$btnAssistantApply.Enabled = $false

$btnAssistantSettings = New-Object CDriveRoundedButton
$btnAssistantSettings.Text = '配置'
$btnAssistantSettings.Size = New-Object System.Drawing.Size(58, 32)
Set-ActionButtonStyle $btnAssistantSettings ([System.Drawing.Color]::White) ([System.Drawing.Color]::FromArgb(97, 112, 123)) ([System.Drawing.Color]::FromArgb(214, 222, 228)) ([System.Drawing.Color]::FromArgb(244, 247, 249)) ([System.Drawing.Color]::FromArgb(235, 240, 243))

$btnAssistantStop = New-Object CDriveRoundedButton
$btnAssistantStop.Text = '停止'
$btnAssistantStop.Size = New-Object System.Drawing.Size(58, 32)
Set-ActionButtonStyle $btnAssistantStop ([System.Drawing.Color]::White) ([System.Drawing.Color]::FromArgb(181, 30, 40)) ([System.Drawing.Color]::FromArgb(235, 194, 198)) ([System.Drawing.Color]::FromArgb(252, 236, 237)) ([System.Drawing.Color]::FromArgb(247, 220, 223))
$btnAssistantStop.Visible = $false

$btnAssistantSend = New-Object CDriveRoundedButton
$btnAssistantSend.Text = '发送'
$btnAssistantSend.Size = New-Object System.Drawing.Size(72, 32)
Set-ActionButtonStyle $btnAssistantSend ([System.Drawing.Color]::FromArgb(181, 30, 40)) ([System.Drawing.Color]::White) ([System.Drawing.Color]::FromArgb(181, 30, 40)) ([System.Drawing.Color]::FromArgb(160, 26, 35)) ([System.Drawing.Color]::FromArgb(140, 21, 30))
$assistantComposer.Controls.AddRange(@($assistantInput, $btnAssistantSettings, $btnAssistantStop, $btnAssistantApply, $btnAssistantSend))

$assistantLayout.Controls.Add($assistantHeader, 0, 0)
$assistantLayout.Controls.Add($assistantShell, 0, 1)
$assistantLayout.Controls.Add($assistantComposer, 0, 2)
$assistantView.Controls.Add($assistantLayout)

$dashboardGrid.Controls.Add($diskCard, 0, 1)
$dashboardGrid.SetColumnSpan($diskCard, 2)
$dashboardGrid.Controls.Add($compareCard, 2, 1)
$dashboardGrid.SetColumnSpan($compareCard, 2)
$dashboardGrid.Controls.Add($logHeader, 0, 2)
$dashboardGrid.SetColumnSpan($logHeader, 4)
$dashboardGrid.Controls.Add($logShell, 0, 3)
$dashboardGrid.SetColumnSpan($logShell, 4)

$topBar.Controls.AddRange(@($title, $hint, $statusCluster, $toolbar, $animationImage, $topRule, $topDivider))
$contentHost.Controls.AddRange(@($dashboardGrid, $selectionView, $assistantView))
$workspace.Controls.AddRange(@($contentHost, $topBar))
$form.Controls.AddRange(@($workspace, $sideBar))

$buttons = @($btnScan, $btnReport, $btnClean, $btnExit)
$jobState = @{ Process = $null; LastLen = 0; EventLines = 0; LogFile = ''; EventFile = ''; SelectionOutput = ''; SelectionFile = '' }
$dashboardState = @{ CleanBeforeFree = $null; CleanAfterFree = $null; IsCleaning = $false; LastAction = '尚未执行操作'; LastFinished = $null; SelectionItems = @(); SelectedIds = @{}; SelectionCheckboxes = @(); ScanId = ''; ManifestHash = ''; ScannedAt = '' }
$navigationState = @{ View = 'overview' }
$agentDataRoot = Join-Path $localDataRoot 'agent'
$agentConfigPath = Join-Path $agentDataRoot 'provider.json'
$assistantState = @{
    LastProposedIds = @()
    Process = $null
    EventFile = ''
    EventLines = 0
    LogFile = ''
    TurnFile = ''
    TurnId = ''
    Messages = New-Object System.Collections.Generic.List[object]
    ReplayCache = @{}
    ModelCalls = 0
    ToolCalls = 0
    AssistantBubbleOpen = $false
    ActiveBubble = $null
    PendingCleanupAfterScan = $false
    Config = $null
    FixtureResponsePath = ''
    FixtureSsePath = ''
}
$travelState = @{
    Process = $null
    RequestFile = ''
    OutputFile = ''
    LogFile = ''
    Consent = $false
}

$toolTips = New-Object System.Windows.Forms.ToolTip
$toolTips.InitialDelay = 350
$toolTips.ReshowDelay = 120
$toolTips.SetToolTip($navOverview, '概览：统计、磁盘状态和清理对比')
$toolTips.SetToolTip($navSelection, '清理清单：查看扫描到的候选项并自行选择')
$toolTips.SetToolTip($navLogs, '日志：专注查看实时输出')
$toolTips.SetToolTip($navAssistant, '智能助手：解释扫描结果并提供可撤销的勾选建议')
$toolTips.SetToolTip($btnScan, '扫描可安全清理项，不会删除文件')
$toolTips.SetToolTip($btnReport, '打开最新的 HTML 诊断报告')
$toolTips.SetToolTip($btnClean, '清理缓存和临时文件，执行前会再次确认')
$toolTips.SetToolTip($btnExit, '关闭清理工具')
$toolTips.SetToolTip($brandLogo, '悬停或点击播放 Logo 动画')

$livePulseTimer = New-Object System.Windows.Forms.Timer
$livePulseTimer.Interval = 700
$livePulseState = $false
$livePulseTimer.Add_Tick({
    $livePulseState = -not $livePulseState
    $statusPulse.ForeColor = if ($livePulseState) {
        [System.Drawing.Color]::FromArgb(181, 30, 40)
    } else {
        [System.Drawing.Color]::FromArgb(232, 166, 170)
    }
})
$livePulseTimer.Start()

function Update-SelectionActionLayout {
    $right = $selectionActionBar.ClientSize.Width - 14
    $btnClearSelection.Left = [Math]::Max(14, $right - $btnClearSelection.Width)
    $btnClearSelection.Top = [Math]::Max(0, [int][Math]::Floor(($selectionActionBar.ClientSize.Height - $btnClearSelection.Height) / 2))
    $btnSelectSuggested.Left = [Math]::Max(14, $btnClearSelection.Left - 8 - $btnSelectSuggested.Width)
    $btnSelectSuggested.Top = [Math]::Max(0, [int][Math]::Floor(($selectionActionBar.ClientSize.Height - $btnSelectSuggested.Height) / 2))
}

function Update-AssistantComposerLayout {
    $right = $assistantComposer.ClientSize.Width - 12
    $btnAssistantSend.Left = [Math]::Max(12, $right - $btnAssistantSend.Width)
    $btnAssistantSend.Top = [Math]::Max(0, [int][Math]::Floor(($assistantComposer.ClientSize.Height - $btnAssistantSend.Height) / 2))
    $btnAssistantApply.Left = [Math]::Max(12, $btnAssistantSend.Left - 8 - $btnAssistantApply.Width)
    $btnAssistantApply.Top = $btnAssistantSend.Top
    $btnAssistantStop.Left = [Math]::Max(12, $btnAssistantApply.Left - 8 - $btnAssistantStop.Width)
    $btnAssistantStop.Top = $btnAssistantSend.Top
    $btnAssistantSettings.Left = [Math]::Max(12, $btnAssistantStop.Left - 8 - $btnAssistantSettings.Width)
    $btnAssistantSettings.Top = $btnAssistantSend.Top
    $assistantInput.Width = [Math]::Max(80, $btnAssistantSettings.Left - 26)
}

$assistantComposer.Add_Resize({ Update-AssistantComposerLayout })
$assistantComposer.Add_Layout({ Update-AssistantComposerLayout })

function Update-AssistantChatRowLayout {
    param($Row)
    if ($null -eq $Row -or $null -eq $Row.Tag) { return }
    $refs = $Row.Tag
    $rowWidth = [Math]::Max(260, $assistantChatSurface.ClientSize.Width - 18)
    $Row.Width = $rowWidth
    $avatarSize = 40
    $gap = 10
    $bubblePaddingX = 14
    $bubblePaddingY = 10
    $bubbleMinimumWidth = 100
    $bubbleMinimumHeight = 42
    $maximumBubbleWidth = [Math]::Max(180, [Math]::Floor(($rowWidth - $avatarSize - $gap) * 0.72))
    $textMaximumWidth = [Math]::Max(140, $maximumBubbleWidth - ($bubblePaddingX * 2))
    $flags = [System.Windows.Forms.TextFormatFlags]::WordBreak -bor [System.Windows.Forms.TextFormatFlags]::NoPrefix -bor [System.Windows.Forms.TextFormatFlags]::TextBoxControl -bor [System.Windows.Forms.TextFormatFlags]::NoPadding
    $singleLine = [System.Windows.Forms.TextRenderer]::MeasureText([string]$refs.Label.Text, $refs.Label.Font)
    $textWidth = [Math]::Min($textMaximumWidth, [Math]::Max(72, $singleLine.Width))
    $measured = [System.Windows.Forms.TextRenderer]::MeasureText([string]$refs.Label.Text, $refs.Label.Font, [System.Drawing.Size]::new($textWidth, 10000), $flags)
    $bubbleWidth = [Math]::Min($maximumBubbleWidth, [Math]::Max($bubbleMinimumWidth, $measured.Width + ($bubblePaddingX * 2)))
    $labelWidth = [Math]::Max(72, $bubbleWidth - ($bubblePaddingX * 2))
    $measured = [System.Windows.Forms.TextRenderer]::MeasureText([string]$refs.Label.Text, $refs.Label.Font, [System.Drawing.Size]::new($labelWidth, 10000), $flags)
    $bubbleHeight = [Math]::Max($bubbleMinimumHeight, $measured.Height + ($bubblePaddingY * 2))
    $Row.Height = [Math]::Max($avatarSize, $bubbleHeight) + 10
    $refs.Avatar.Size = [System.Drawing.Size]::new($avatarSize, $avatarSize)
    $refs.Avatar.Top = 0
    $refs.Bubble.Size = [System.Drawing.Size]::new($bubbleWidth, $bubbleHeight)
    $refs.Bubble.Top = 0
    $textControlHeight = [Math]::Min($bubbleHeight - ($bubblePaddingY * 2), [Math]::Max($refs.Label.Font.Height + 2, $measured.Height + 2))
    $textControlTop = [Math]::Max($bubblePaddingY, [int][Math]::Floor(($bubbleHeight - $textControlHeight) / 2))
    $refs.Label.Location = [System.Drawing.Point]::new($bubblePaddingX, $textControlTop)
    $refs.Label.Size = [System.Drawing.Size]::new($labelWidth, $textControlHeight)
    if ([string]$refs.Role -eq 'user') {
        $refs.Avatar.Left = [Math]::Max(0, $rowWidth - $avatarSize)
        $refs.Bubble.Left = [Math]::Max(0, $refs.Avatar.Left - $gap - $bubbleWidth)
    } else {
        $refs.Avatar.Left = 0
        $refs.Bubble.Left = $avatarSize + $gap
    }
}

function Update-AssistantChatLayout {
    foreach ($row in @($assistantChatSurface.Controls)) { Update-AssistantChatRowLayout $row }
}

$assistantChatSurface.Add_Resize({ Update-AssistantChatLayout })
$assistantChatSurface.Add_Layout({ Update-AssistantChatLayout })

function Update-CleanupSelectionRows {
    $rowWidth = [Math]::Max(1, $selectionItemsPanel.ClientSize.Width - 8)
    foreach ($row in @($selectionItemsPanel.Controls)) {
        $row.Width = $rowWidth
        Update-CleanupSelectionRowLayout $row
    }
}

$selectionRowTopInset = 10
$selectionRowRightInset = 14
$selectionRowSizeWidth = 94
$selectionRowSizeHeight = 22

function Update-CleanupSelectionRowLayout {
    param($Row)
    $refs = $Row.Tag
    if ($null -eq $refs) { return }
    $clientWidth = $Row.ClientSize.Width
    $refs.SizeLabel.Size = New-Object System.Drawing.Size($selectionRowSizeWidth, $selectionRowSizeHeight)
    $refs.SizeLabel.Left = [Math]::Max(128, $clientWidth - $selectionRowRightInset - $refs.SizeLabel.Width)
    $refs.SizeLabel.Top = $selectionRowTopInset
    $refs.NameLabel.Width = [Math]::Max(72, $refs.SizeLabel.Left - 58)
    $refs.AdviceLabel.Width = [Math]::Max(72, $clientWidth - 142)
}

function Get-SelectedCleanupItems {
    return @($dashboardState.SelectionItems | Where-Object { $dashboardState.SelectedIds.ContainsKey([string]$_.Id) })
}

function Update-CleanupSelectionSummary {
    $selected = @(Get-SelectedCleanupItems)
    $selectedSize = 0.0
    $recoverableSize = 0.0
    foreach ($item in $selected) {
        if ([string]$item.RecoveryMode -eq 'RecycleBin') { $recoverableSize += [double]$item.Size }
        else { $selectedSize += [double]$item.Size }
    }
    $available = @($dashboardState.SelectionItems).Count
    $selectionSummary.Text = if ($available -eq 0) {
        '本次扫描没有发现可释放的缓存或临时文件'
    } elseif ($selected.Count -eq 0) {
        ('已发现 {0} 项；尚未选择' -f $available)
    } elseif ($recoverableSize -gt 0 -and $selectedSize -gt 0) {
        ('已选择 {0} / {1} 项，预计立即释放 {2}；另有 {3} 移入回收站' -f $selected.Count, $available, (Format-UiBytes $selectedSize), (Format-UiBytes $recoverableSize))
    } elseif ($recoverableSize -gt 0) {
        ('已选择 {0} / {1} 项，约 {2} 将移入回收站（暂不释放空间）' -f $selected.Count, $available, (Format-UiBytes $recoverableSize))
    } else {
        ('已选择 {0} / {1} 项，预计释放 {2}' -f $selected.Count, $available, (Format-UiBytes $selectedSize))
    }
    $canClean = (-not $jobState.Process) -and $selected.Count -gt 0
    $btnClean.Text = if ($selected.Count -gt 0) { '执行所选项' } else { '清理安全项' }
    $btnClean.Enabled = $canClean
    $btnSelectSuggested.Enabled = (-not $jobState.Process) -and $available -gt 0
    $btnClearSelection.Enabled = (-not $jobState.Process) -and $selected.Count -gt 0
}

function New-CleanupSelectionRow {
    param($Item)
    $row = New-Object CDriveRoundedPanel
    $row.Height = 76
    $row.Width = [Math]::Max(1, $selectionItemsPanel.ClientSize.Width - 8)
    $row.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
    $row.BackColor = [System.Drawing.Color]::White
    $row.BorderColor = [System.Drawing.Color]::FromArgb(220, 226, 231)
    $row.CornerRadius = 8

    $choice = New-Object System.Windows.Forms.CheckBox
    $choice.Location = New-Object System.Drawing.Point(14, 27)
    $choice.Size = New-Object System.Drawing.Size(22, 22)
    $choice.Cursor = [System.Windows.Forms.Cursors]::Hand
    $choice.Tag = $Item

    $name = New-Object System.Windows.Forms.Label
    $name.Text = [string]$Item.Name
    $name.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9, [System.Drawing.FontStyle]::Bold)
    $name.ForeColor = [System.Drawing.Color]::FromArgb(40, 52, 61)
    $name.Location = New-Object System.Drawing.Point(47, 11)
    $name.Height = 22
    $name.AutoEllipsis = $true

    $size = New-Object System.Windows.Forms.Label
    $size.Text = Format-UiBytes ([double]$Item.Size)
    $size.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
    $size.ForeColor = [System.Drawing.Color]::FromArgb(181, 30, 40)
    $size.BackColor = [System.Drawing.Color]::Transparent
    $size.Location = New-Object System.Drawing.Point(0, $selectionRowTopInset)
    $size.Size = New-Object System.Drawing.Size($selectionRowSizeWidth, $selectionRowSizeHeight)
    $size.TextAlign = 'MiddleRight'
    $size.Anchor = 'Top,Right'

    $tag = New-Object CDriveRoundedPanel
    $tag.Location = New-Object System.Drawing.Point(47, 41)
    $tag.Size = New-Object System.Drawing.Size(72, 22)
    $tag.CornerRadius = 6
    $tag.BorderColor = [System.Drawing.Color]::Transparent
    if ($Item.RecommendationLevel -eq 'Recommended') {
        $tag.BackColor = [System.Drawing.Color]::FromArgb(251, 229, 231)
        $tagTextColor = [System.Drawing.Color]::FromArgb(181, 30, 40)
    } elseif ($Item.RecommendationLevel -eq 'Review') {
        $tag.BackColor = [System.Drawing.Color]::FromArgb(252, 244, 230)
        $tagTextColor = [System.Drawing.Color]::FromArgb(161, 103, 24)
    } else {
        $tag.BackColor = [System.Drawing.Color]::FromArgb(239, 242, 245)
        $tagTextColor = [System.Drawing.Color]::FromArgb(100, 114, 125)
    }
    $tagLabel = New-Object System.Windows.Forms.Label
    $tagLabel.Text = [string]$Item.Recommendation
    $tagLabel.Dock = 'Fill'
    $tagLabel.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 7)
    $tagLabel.ForeColor = $tagTextColor
    $tagLabel.TextAlign = 'MiddleCenter'
    $tag.Controls.Add($tagLabel)

    $advice = New-Object System.Windows.Forms.Label
    $advice.Text = if ($Item.Note) { ([string]$Item.Advice + '  ' + [string]$Item.Note) } else { [string]$Item.Advice }
    $advice.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 8)
    $advice.ForeColor = [System.Drawing.Color]::FromArgb(124, 139, 149)
    $advice.Location = New-Object System.Drawing.Point(128, 40)
    $advice.Height = 24
    $advice.AutoEllipsis = $true

    $row.Controls.AddRange(@($choice, $name, $size, $tag, $advice))
    $row.Tag = [PSCustomObject]@{ NameLabel = $name; SizeLabel = $size; AdviceLabel = $advice }
    $row.Add_Resize({
        param($sender, $eventArgs)
        Update-CleanupSelectionRowLayout $sender
    })
    $row.Add_Layout({ param($sender, $eventArgs) Update-CleanupSelectionRowLayout $sender })
    Update-CleanupSelectionRowLayout $row
    $choice.Add_CheckedChanged({
        param($sender, $eventArgs)
        $id = [string]$sender.Tag.Id
        if ($sender.Checked) { $dashboardState.SelectedIds[$id] = $true }
        else { $dashboardState.SelectedIds.Remove($id) | Out-Null }
        Update-CleanupSelectionSummary
    })
    $dashboardState.SelectionCheckboxes += $choice
    return $row
}

function Show-CleanupSelection {
    param([string]$Path)
    try {
        $payload = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([int]$payload.SchemaVersion -ne 2) { throw '不支持的清单版本，请重新扫描。' }
        $dashboardState.SelectionItems = @($payload.Items | Where-Object { $_.Id })
        $dashboardState.ScanId = [string]$payload.ScanId
        $dashboardState.ManifestHash = [string]$payload.ManifestHash
        $dashboardState.ScannedAt = [string]$payload.ScannedAt
        $dashboardState.SelectedIds = @{}
        $dashboardState.SelectionCheckboxes = @()
        $assistantState.LastProposedIds = @()
        $btnAssistantApply.Enabled = $false
        foreach ($control in @($selectionItemsPanel.Controls)) { $control.Dispose() }
        $selectionItemsPanel.Controls.Clear()
        if ($dashboardState.SelectionItems.Count -eq 0) {
            $empty = New-Object System.Windows.Forms.Label
            $empty.Text = '本次扫描未发现可释放的缓存或临时文件。'
            $empty.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
            $empty.ForeColor = [System.Drawing.Color]::FromArgb(117, 132, 143)
            $empty.AutoSize = $true
            $empty.Margin = New-Object System.Windows.Forms.Padding(4, 10, 0, 0)
            $selectionItemsPanel.Controls.Add($empty)
        } else {
            foreach ($item in $dashboardState.SelectionItems) {
                $selectionItemsPanel.Controls.Add((New-CleanupSelectionRow $item))
            }
        }
        Update-CleanupSelectionRows
        Update-CleanupSelectionSummary
        Set-DashboardView 'selection'
    } catch {
        Append-Log $log ('读取清理清单失败：' + $_.Exception.Message)
        [System.Windows.Forms.MessageBox]::Show('扫描结果无法生成清理清单，请查看运行日志。', 'C盘清理', 'OK', 'Error') | Out-Null
    }
}

function New-SelectedCleanupFile {
    $selectedIds = @($dashboardState.SelectedIds.Keys | Sort-Object)
    if ($selectedIds.Count -eq 0) { return $null }
    $path = Join-Path $env:TEMP ('cdc-selection-{0}.json' -f [guid]::NewGuid().ToString('N'))
    $selectedItems = @($dashboardState.SelectionItems | Where-Object { $dashboardState.SelectedIds.ContainsKey([string]$_.Id) } | ForEach-Object {
        [PSCustomObject]@{ Id = [string]$_.Id; Size = [double]$_.Size }
    })
    $payload = [PSCustomObject]@{
        SchemaVersion = 2
        ScanId = $dashboardState.ScanId
        ManifestHash = $dashboardState.ManifestHash
        ScannedAt = $dashboardState.ScannedAt
        SelectedIds = $selectedIds
        Items = $selectedItems
    }
    [System.IO.File]::WriteAllText($path, ($payload | ConvertTo-Json -Depth 3), (New-Object System.Text.UTF8Encoding($false)))
    return $path
}

$selectionActionBar.Add_Resize({ Update-SelectionActionLayout })
$selectionActionBar.Add_Layout({ Update-SelectionActionLayout })
$selectionItemsPanel.Add_Resize({ Update-CleanupSelectionRows })

function Set-DashboardView {
    param([ValidateSet('overview', 'selection', 'logs', 'assistant')][string]$View)
    $navigationState.View = $View
    $isOverview = $View -eq 'overview'
    $isSelection = $View -eq 'selection'
    $isAssistant = $View -eq 'assistant'
    foreach ($card in $statCards) { $card.Panel.Visible = $isOverview }
    $diskCard.Visible = $isOverview
    $compareCard.Visible = $isOverview
    $dashboardGrid.Visible = (-not $isSelection) -and (-not $isAssistant)
    $selectionView.Visible = $isSelection
    $assistantView.Visible = $isAssistant
    if ($isSelection) {
        Update-SelectionViewLayout
        $selectionView.PerformLayout()
        $selectionLayout.PerformLayout()
        Update-SelectionActionLayout
        Update-CleanupSelectionRows
        $selectionView.BringToFront()
    } elseif ($isAssistant) {
        Update-AssistantComposerLayout
        $assistantView.BringToFront()
    } else {
        $dashboardGrid.BringToFront()
    }
    $dashboardGrid.RowStyles[0].Height = if ($isOverview) { 104 } else { 0 }
    $dashboardGrid.RowStyles[1].Height = if ($isOverview) { 218 } else { 0 }
    $logHeader.Margin = if ($isOverview) { New-Object System.Windows.Forms.Padding(0, 12, 0, 0) } else { New-Object System.Windows.Forms.Padding(0, 0, 0, 0) }

    $navOverview.Selected = $isOverview
    $navSelection.Selected = $isSelection
    $navLogs.Selected = $View -eq 'logs'
    $navAssistant.Selected = $isAssistant
    $dashboardGrid.PerformLayout()
}

function Update-TopBarLayout {
    $compact = $topBar.ClientSize.Width -lt 1050
    $hint.Visible = -not $compact
    $statusCluster.Visible = -not $compact
    Update-SelectionViewLayout
}

function Update-SelectionViewLayout {
    $contentHost.Location = New-Object System.Drawing.Point(0, $topBar.Bottom)
    $contentHost.Size = New-Object System.Drawing.Size($workspace.ClientSize.Width, [Math]::Max(1, $workspace.ClientSize.Height - $topBar.Height))
}

function Update-TrackLayout {
    foreach ($track in @($diskTrack, $beforeTrack, $afterTrack)) {
        if ($track.Parent) {
            # 进度条左右保持 18px 外边距，避免不同窗口宽度下贴边。
            $track.Width = [Math]::Max(1, $track.Parent.ClientSize.Width - 36)
        }
    }
}

function Update-StatDetailLayout {
    foreach ($stat in $statCards) {
        $panel = $stat.Panel
        $detailBand = $stat.Detail.Parent
        if ($panel.ClientSize.Width -gt 0) {
            $detailBand.Left = 12
            $detailBand.Width = [Math]::Max(1, $panel.ClientSize.Width - 24)
            # 固定底部说明区，避免字体/DPI 变化时压住标题或超出统计卡。
            $detailBand.Top = [Math]::Max(48, $panel.ClientSize.Height - 31)
            $stat.Detail.Left = 6
            $stat.Detail.Width = [Math]::Max(1, $detailBand.ClientSize.Width - 12)
        }
    }
}

function Set-ProgressWidth {
    param($Bar, $Track, [double]$Percent)
    $trackWidth = [Math]::Max(0, $Track.ClientSize.Width - 2)
    $barWidth = [Math]::Max(0, [int][Math]::Round($trackWidth * [Math]::Max(0, [Math]::Min(100, $Percent)) / 100))
    $Bar.Height = [Math]::Max(0, $Track.ClientSize.Height - 2)
    $Bar.Width = $barWidth
}

function Update-Dashboard {
    Update-TrackLayout
    Update-StatDetailLayout
    $metrics = Get-CDriveMetrics
    $capacityCard.Value.Text = Format-UiBytes $metrics.Total
    $capacityCard.Detail.Text = 'C 盘总容量'
    $usedCard.Value.Text = Format-UiBytes $metrics.Used
    $usedCard.Detail.Text = ('占用 {0:F1}%' -f $metrics.UsedPercent)
    $freeCard.Value.Text = Format-UiBytes $metrics.Free
    $freeCard.Detail.Text = '当前可用空间'

    $diskPercent.Text = ('{0:F1}% 已用' -f $metrics.UsedPercent)
    $diskUsedText.Text = ('已用 ' + (Format-UiBytes $metrics.Used))
    $diskFreeText.Text = ('可用 ' + (Format-UiBytes $metrics.Free))
    Set-ProgressWidth $diskUsedBar $diskTrack $metrics.UsedPercent

    if ($null -ne $dashboardState.CleanBeforeFree) {
        $before = [double]$dashboardState.CleanBeforeFree
        $after = if ($null -ne $dashboardState.CleanAfterFree) { [double]$dashboardState.CleanAfterFree } else { [double]$metrics.Free }
        $delta = $after - $before
        $beforePercent = if ($metrics.Total -gt 0) { ($before / $metrics.Total) * 100 } else { 0 }
        $afterPercent = if ($metrics.Total -gt 0) { ($after / $metrics.Total) * 100 } else { 0 }
        $beforeValue.Text = Format-UiBytes $before
        $afterValue.Text = Format-UiBytes $after
        Set-ProgressWidth $beforeBar $beforeTrack $beforePercent
        Set-ProgressWidth $afterBar $afterTrack $afterPercent
        $freedCard.Value.Text = if ($delta -ge 0) { Format-UiBytes $delta } else { '-' + (Format-UiBytes ([Math]::Abs($delta))) }
        $freedCard.Detail.Text = if ($dashboardState.IsCleaning) { '清理进行中，实时更新' } else { '按可用空间变化计算' }
        $compareResult.Text = if ($dashboardState.IsCleaning) {
            '正在清理安全项，完成后将锁定本次对比结果。'
        } elseif ($delta -ge 0) {
            ('本次清理后，C 盘可用空间增加 ' + (Format-UiBytes $delta) + '。')
        } else {
            ('清理期间系统占用增加 ' + (Format-UiBytes ([Math]::Abs($delta))) + '，请以报告明细为准。')
        }
    } else {
        $freedCard.Value.Text = '--'
        $freedCard.Detail.Text = '执行清理后记录'
        $beforeValue.Text = '等待清理'
        $afterValue.Text = '等待清理'
        $beforeBar.Width = 0
        $afterBar.Width = 0
        $compareResult.Text = if ($dashboardState.LastAction -like '扫描完成*') {
            '扫描已完成，未删除文件；执行清理后可查看前后空间对比。'
        } else {
            '尚未执行清理，当前显示实时磁盘统计。'
        }
    }

}

function Set-UiBusy([bool]$Busy) {
    foreach ($b in @($btnScan, $btnReport)) { $b.Enabled = (-not $Busy) }
    $btnClean.Enabled = $false
    $btnSelectSuggested.Enabled = -not $Busy
    $btnClearSelection.Enabled = $false
    $btnExit.Enabled = $true
    $btnExit.Text = if ($Busy) { '取消任务' } else { '退出' }
    $toolTips.SetToolTip($btnExit, $(if ($Busy) { '停止当前扫描或清理任务' } else { '关闭清理工具' }))
    if (-not $Busy) { Update-CleanupSelectionSummary }
}

function Stop-UiJob([bool]$Cancel = $false) {
    $elapsed = 0
    if ($jobState.Process) {
        try {
            if ($Cancel -and -not $jobState.Process.HasExited) { $elapsed = $jobState.Process.Cancel(2000) }
            else { $jobState.Process.Dispose() }
        } catch {
            Append-Log $log ('停止任务失败：' + $_.Exception.Message)
        }
        $jobState.Process = $null
    }
    return $elapsed
}

function Read-OperationEvents {
    $eventFile = $jobState.EventFile
    if (-not $eventFile -or -not (Test-Path -LiteralPath $eventFile)) { return }
    try {
        $lines = @(Get-Content -LiteralPath $eventFile -Encoding UTF8)
        if ($lines.Count -le $jobState.EventLines) { return }
        for ($index = $jobState.EventLines; $index -lt $lines.Count; $index++) {
            if ([string]::IsNullOrWhiteSpace($lines[$index])) { continue }
            $event = $lines[$index] | ConvertFrom-Json
            switch ([string]$event.type) {
                'scan.item.started' {
                    $status.Text = ('正在扫描 {0}/{1}：{2}' -f $event.data.index, $event.data.total, $event.data.name)
                }
                'scan.provider.selected' {
                    $status.Text = switch ([string]$event.data.provider) {
                        'Incremental' { '正在使用增量扫描…' }
                        'Baseline' { '正在建立增量扫描索引…' }
                        default { '正在使用快速兼容扫描…' }
                    }
                }
                'scan.incremental.completed' {
                    if ([int]$event.data.reusedItems -gt 0) {
                        Append-Log $log ('增量扫描：复用 {0} 项，重新扫描 {1} 项。' -f $event.data.reusedItems, $event.data.updatedItems)
                    }
                }
                'cleanup.item.completed' {
                    $status.Text = ('正在清理：已完成 {0}' -f $event.data.itemId)
                }
                'operation.failed' {
                    Append-Log $log ('结构化错误：' + [string]$event.data.code)
                }
            }
        }
        $jobState.EventLines = $lines.Count
    } catch {
        Append-Log $log ('读取结构化进度失败：' + $_.Exception.Message)
    }
}

$poll = New-Object System.Windows.Forms.Timer
$poll.Interval = 400
$poll.Add_Tick({
    Read-OperationEvents
    $file = $jobState.LogFile
    if ($file -and (Test-Path -LiteralPath $file)) {
        try {
            $fs = [System.IO.File]::Open($file, 'Open', 'Read', 'ReadWrite')
            $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::Default)
            $text = $sr.ReadToEnd()
            $sr.Close(); $fs.Close()
            if ($text.Length -gt $jobState.LastLen) {
                $chunk = $text.Substring($jobState.LastLen)
                $jobState.LastLen = $text.Length
                $log.AppendText($chunk)
                $log.SelectionStart = $log.Text.Length
                $log.ScrollToCaret()
            }
        } catch {}
    }
    $process = $jobState.Process
    if ($process -and $process.HasExited) {
        $poll.Stop()
        $exitCode = 1
        try { $exitCode = [int]$process.Complete() } catch { Append-Log $log ('读取任务结果失败：' + $_.Exception.Message) }
        $jobState.Process = $null
        Read-OperationEvents
        $succeeded = ($exitCode -eq 0)
        $selectionOutput = $jobState.SelectionOutput
        $selectionFile = $jobState.SelectionFile
        Set-UiBusy $false
        if ($animationState.Active) { Stop-CleanAnimation }
        $status.Text = Get-CFreeText
        if ($dashboardState.IsCleaning) {
            $dashboardState.CleanAfterFree = (Get-CDriveMetrics).Free
            $dashboardState.IsCleaning = $false
            $dashboardState.LastAction = if ($succeeded) { '清理完成' } else { '清理已中止或失败' }
        } else {
            $dashboardState.LastAction = if ($succeeded) { '扫描完成（未删除文件）' } else { '扫描失败' }
        }
        $dashboardState.LastFinished = Get-Date
        Update-Dashboard
        if ($succeeded -and $selectionOutput -and (Test-Path -LiteralPath $selectionOutput)) {
            Show-CleanupSelection $selectionOutput
        }
        if ($succeeded -and -not $dashboardState.IsCleaning -and $assistantState.PendingCleanupAfterScan -and @($dashboardState.SelectionItems).Count -gt 0) {
            $assistantState.PendingCleanupAfterScan = $false
            $form.BeginInvoke([System.Action]{ Invoke-AssistantCleanupWorkflow }) | Out-Null
        } elseif (-not $succeeded -and $assistantState.PendingCleanupAfterScan) {
            $assistantState.PendingCleanupAfterScan = $false
            Add-AssistantMessage '助手' '只读扫描未成功完成，因此没有选择或执行任何清理项。'
        }
        $jobState.SelectionOutput = ''
        $jobState.SelectionFile = ''
        Append-Log $log $(if ($succeeded) { '--- 完成 ---' } else { ('--- 已中止或失败（退出码 {0}）---' -f $exitCode) })
        if ($succeeded -and (Test-Path -LiteralPath $reportPath)) {
            Append-Log $log ('报告：' + $reportPath)
        }
        foreach ($temporaryPath in @($selectionOutput, $selectionFile, $jobState.LogFile, $jobState.EventFile)) {
            if ($temporaryPath -and (Test-Path -LiteralPath $temporaryPath)) {
                try { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue } catch {}
            }
        }
        $jobState.LogFile = ''
        $jobState.EventFile = ''
        $jobState.EventLines = 0
    }
})

function Invoke-Main {
    param([string[]]$Arguments, [string]$StatusText, [bool]$IsCleaning = $false, [string]$SelectionOutput = '', [string]$SelectionFile = '')
    if ($jobState.Process) { return }
    $jobState.LogFile = Join-Path $env:TEMP ('cdc-ui-{0}.log' -f [guid]::NewGuid().ToString('N'))
    $jobState.EventFile = Join-Path $env:TEMP ('cdc-ui-{0}.ndjson' -f [guid]::NewGuid().ToString('N'))
    $jobState.LastLen = 0
    $jobState.EventLines = 0
    $jobState.SelectionOutput = $SelectionOutput
    $jobState.SelectionFile = $SelectionFile
    Set-UiBusy $true
    $status.Text = $StatusText
    if ($IsCleaning) {
        $dashboardState.CleanBeforeFree = (Get-CDriveMetrics).Free
        $dashboardState.CleanAfterFree = $null
        $dashboardState.IsCleaning = $true
        $dashboardState.LastAction = '正在清理安全项'
    } else {
        $dashboardState.LastAction = '正在扫描（不删除文件）'
    }
    $dashboardState.LastFinished = $null
    Update-Dashboard
    Append-Log $log ''
    $engineArguments = @($Arguments) + @('-EventOutput', $jobState.EventFile)
    Append-Log $log ('启动主程序  ' + ($engineArguments -join ' '))
    try {
        $jobState.Process = Start-CDriveEngineProcess $mainScript $engineArguments $scriptDir $jobState.LogFile
    } catch {
        Set-UiBusy $false
        Append-Log $log ('启动主程序失败：' + $_.Exception.Message)
        [System.Windows.Forms.MessageBox]::Show('无法启动扫描或清理进程，请查看运行日志。', 'C盘清理', 'OK', 'Error') | Out-Null
        return
    }

    $poll.Start()
}

function New-AssistantChatRow {
    param(
        [ValidateSet('assistant', 'user')][string]$Role,
        [string]$Text
    )
    $row = New-Object System.Windows.Forms.Panel
    $row.BackColor = [System.Drawing.Color]::Transparent
    $row.Margin = New-Object System.Windows.Forms.Padding(0)
    $row.TabStop = $false

    $avatar = New-Object System.Windows.Forms.PictureBox
    $avatar.SizeMode = 'Zoom'
    $avatar.BackColor = [System.Drawing.Color]::Transparent
    $avatar.TabStop = $false
    $avatar.Image = if ($Role -eq 'user') { $assistantUserAvatarImage } else { $assistantAgentAvatarImage }
    $avatar.AccessibleName = if ($Role -eq 'user') { '用户头像' } else { '智能助手挥手头像' }

    $bubble = New-Object CDriveRoundedPanel
    $bubble.CornerRadius = 8
    if ($Role -eq 'user') {
        $bubble.BackColor = [System.Drawing.Color]::FromArgb(181, 30, 40)
        $bubble.BorderColor = [System.Drawing.Color]::FromArgb(181, 30, 40)
    } else {
        $bubble.BackColor = [System.Drawing.Color]::White
        $bubble.BorderColor = [System.Drawing.Color]::FromArgb(220, 226, 231)
    }

    $label = New-Object System.Windows.Forms.TextBox
    $label.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
    $label.ForeColor = if ($Role -eq 'user') { [System.Drawing.Color]::White } else { [System.Drawing.Color]::FromArgb(49, 62, 72) }
    $label.BackColor = $bubble.BackColor
    $label.Text = $Text
    $label.ReadOnly = $true
    $label.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $label.Multiline = $true
    $label.ScrollBars = [System.Windows.Forms.ScrollBars]::None
    $label.WordWrap = $true
    $label.ShortcutsEnabled = $true
    $label.HideSelection = $false
    $label.TabStop = $true
    $label.Cursor = [System.Windows.Forms.Cursors]::IBeam
    $label.AccessibleRole = [System.Windows.Forms.AccessibleRole]::StaticText
    $label.AccessibleName = if ($Role -eq 'user') { '你的消息' } else { '智能助手消息' }

    $messageMenu = New-Object System.Windows.Forms.ContextMenuStrip
    $copyMessage = $messageMenu.Items.Add('复制')
    $selectAllMessage = $messageMenu.Items.Add('全选')
    $messageMenu.Add_Opening({
        param($sender, $eventArgs)
        $copyMessage.Enabled = $label.SelectionLength -gt 0
        $selectAllMessage.Enabled = $label.TextLength -gt 0
    }.GetNewClosure())
    $copyMessage.Add_Click({ if ($label.SelectionLength -gt 0) { $label.Copy() } }.GetNewClosure())
    $selectAllMessage.Add_Click({ $label.SelectAll(); $label.Focus() }.GetNewClosure())
    $label.ContextMenuStrip = $messageMenu

    $bubble.Controls.Add($label)
    $row.Controls.AddRange(@($avatar, $bubble))
    $row.Tag = [PSCustomObject]@{ Role = $Role; Avatar = $avatar; Bubble = $bubble; Label = $label }
    $assistantChatSurface.Controls.Add($row)
    Update-AssistantChatRowLayout $row
    $assistantChatSurface.ScrollControlIntoView($row)
    return $row
}

function Add-AssistantMessage {
    param([string]$Role, [string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return }
    $assistantTranscript.AppendText($Role + '  ' + $Text + "`r`n`r`n")
    $chatRole = if ($Role -eq '你') { 'user' } else { 'assistant' }
    $null = New-AssistantChatRow $chatRole $Text
}

function Add-AssistantDelta {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return }
    if (-not $assistantState.AssistantBubbleOpen) {
        $assistantTranscript.AppendText('助手  ')
        $row = New-AssistantChatRow 'assistant' ''
        $assistantState.ActiveBubble = $row.Tag
        $assistantState.AssistantBubbleOpen = $true
    }
    $assistantTranscript.AppendText($Text)
    $assistantState.ActiveBubble.Label.Text += $Text
    Update-AssistantChatRowLayout $assistantState.ActiveBubble.Bubble.Parent
    $assistantChatSurface.ScrollControlIntoView($assistantState.ActiveBubble.Bubble.Parent)
}

function Complete-AssistantDelta {
    if (-not $assistantState.AssistantBubbleOpen) { return }
    $assistantTranscript.AppendText([Environment]::NewLine + [Environment]::NewLine)
    $assistantState.AssistantBubbleOpen = $false
    $assistantState.ActiveBubble = $null
}

Add-AssistantMessage '助手' '你好，我是你的智能助手。你可以让我扫描并清理低风险缓存；想换个心情时，也可以让我用飞猪规划一次旅行。最终清理和旅行预订都由你确认。'

function Update-AgentMode {
    $assistantState.Config = $null
    try {
        $config = Get-CDriveAgentConfig $agentConfigPath
        if ($null -ne $config -and (Test-CDriveAgentCloudConsent $config)) {
            $credential = Get-CDriveAgentCredential ([string]$config.credentialId) $agentDataRoot
            if (-not [string]::IsNullOrWhiteSpace($credential)) {
                $assistantState.Config = $config
                $assistantStatus.Text = 'CLOUD · READY'
                $assistantDescription.Text = '云端 Agent 可调用受控工具；最终清理由你确认。'
                $toolTips.SetToolTip($assistantStatus, ('模型：' + [string]$config.model))
                $credential = $null
                return
            }
        }
    } catch {
        Append-Log $log ('Agent 配置未启用：' + $_.Exception.Message)
    }
    $assistantStatus.Text = 'LOCAL · SAFE MODE'
    $assistantDescription.Text = '本地助手可解释扫描结果并调整勾选；最终清理由你确认。'
    $toolTips.SetToolTip($assistantStatus, '未配置云端模型，当前不发送网络请求')
}

function Show-AgentSettingsDialog {
    $current = $null
    try { $current = Get-CDriveAgentConfig $agentConfigPath } catch {}

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = 'AI Agent 配置'
    $dialog.StartPosition = 'CenterParent'
    $dialog.FormBorderStyle = 'FixedDialog'
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.ShowInTaskbar = $false
    $dialog.ClientSize = New-Object System.Drawing.Size(500, 350)
    $dialog.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)
    $dialog.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)

    $labels = @('API 基础地址', '模型名称', '接口协议', 'API Key')
    for ($i = 0; $i -lt $labels.Count; $i++) {
        $label = New-Object System.Windows.Forms.Label
        $label.Text = $labels[$i]
        $label.Location = New-Object System.Drawing.Point(24, (28 + ($i * 58)))
        $label.Size = New-Object System.Drawing.Size(100, 22)
        $label.ForeColor = [System.Drawing.Color]::FromArgb(70, 82, 91)
        $dialog.Controls.Add($label)
    }

    $baseUrlBox = New-Object System.Windows.Forms.TextBox
    $baseUrlBox.Location = New-Object System.Drawing.Point(130, 25)
    $baseUrlBox.Size = New-Object System.Drawing.Size(340, 28)
    $baseUrlBox.Text = if ($current) { [string]$current.baseUrl } else { 'https://api.openai.com/v1' }

    $modelBox = New-Object System.Windows.Forms.TextBox
    $modelBox.Location = New-Object System.Drawing.Point(130, 83)
    $modelBox.Size = New-Object System.Drawing.Size(340, 28)
    $modelBox.Text = if ($current) { [string]$current.model } else { '' }

    $protocolBox = New-Object System.Windows.Forms.ComboBox
    $protocolBox.Location = New-Object System.Drawing.Point(130, 141)
    $protocolBox.Size = New-Object System.Drawing.Size(210, 28)
    $protocolBox.DropDownStyle = 'DropDownList'
    [void]$protocolBox.Items.AddRange(@('responses', 'chat-completions', 'text-only'))
    $protocolBox.SelectedItem = if ($current) { [string]$current.protocol } else { 'responses' }

    $keyBox = New-Object System.Windows.Forms.TextBox
    $keyBox.Location = New-Object System.Drawing.Point(130, 199)
    $keyBox.Size = New-Object System.Drawing.Size(340, 28)
    $keyBox.UseSystemPasswordChar = $true
    $keyBox.Text = ''

    $keyHint = New-Object System.Windows.Forms.Label
    $keyHint.Text = '留空会保留已保存的 Key；程序不会回显或写入项目文件。'
    $keyHint.Location = New-Object System.Drawing.Point(130, 229)
    $keyHint.Size = New-Object System.Drawing.Size(340, 22)
    $keyHint.ForeColor = [System.Drawing.Color]::FromArgb(122, 137, 149)
    $keyHint.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 8)

    $streamBox = New-Object System.Windows.Forms.CheckBox
    $streamBox.Text = '启用流式响应'
    $streamBox.Location = New-Object System.Drawing.Point(130, 258)
    $streamBox.Size = New-Object System.Drawing.Size(140, 24)
    $streamBox.Checked = if ($current) { [bool]$current.stream } else { $true }

    $saveButton = New-Object System.Windows.Forms.Button
    $saveButton.Text = '保存并启用'
    $saveButton.Location = New-Object System.Drawing.Point(350, 300)
    $saveButton.Size = New-Object System.Drawing.Size(120, 34)
    $saveButton.DialogResult = 'None'

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = '取消'
    $cancelButton.Location = New-Object System.Drawing.Point(260, 300)
    $cancelButton.Size = New-Object System.Drawing.Size(80, 34)
    $cancelButton.DialogResult = 'Cancel'

    $disableButton = New-Object System.Windows.Forms.Button
    $disableButton.Text = '禁用并移除凭据'
    $disableButton.Location = New-Object System.Drawing.Point(24, 300)
    $disableButton.Size = New-Object System.Drawing.Size(140, 34)
    $disableButton.Enabled = ($null -ne $current)

    $dialog.Controls.AddRange(@($baseUrlBox, $modelBox, $protocolBox, $keyBox, $keyHint, $streamBox, $saveButton, $cancelButton, $disableButton))
    $dialog.CancelButton = $cancelButton

    $disableButton.Add_Click({
        $confirmation = [System.Windows.Forms.MessageBox]::Show('将删除本机保存的 Agent 配置和加密 API Key，离线助手仍可继续使用。是否继续？', '禁用云端 Agent', 'YesNo', 'Warning', 'Button2')
        if ($confirmation -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        try {
            Remove-CDriveAgentCredential 'default' $agentDataRoot
            if (Test-Path -LiteralPath $agentConfigPath -PathType Leaf) { Remove-Item -LiteralPath $agentConfigPath -Force }
            $dialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $dialog.Close()
        } catch {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '无法禁用云端 Agent', 'OK', 'Warning') | Out-Null
        }
    })

    $saveButton.Add_Click({
        try {
            $candidate = [PSCustomObject]@{
                schemaVersion = 1
                providerId = 'custom-openai-compatible'
                protocol = [string]$protocolBox.SelectedItem
                baseUrl = ([string]$baseUrlBox.Text).Trim()
                model = ([string]$modelBox.Text).Trim()
                stream = [bool]$streamBox.Checked
                timeoutSeconds = 90
                maxOutputTokens = 2048
                credentialId = 'default'
                cloudConsent = $null
            }
            $null = Assert-CDriveAgentConfig $candidate
            $existingKey = Get-CDriveAgentCredential 'default' $agentDataRoot
            if ([string]::IsNullOrWhiteSpace([string]$keyBox.Text) -and [string]::IsNullOrWhiteSpace($existingKey)) {
                throw '请输入 API Key。'
            }
            $consentText = '云端模式会发送你输入的问题，以及清理项稳定 ID、大小、风险和恢复方式；不会发送原始路径、用户名、机器名、文件内容或运行日志。是否同意按此范围发送数据？'
            $consent = [System.Windows.Forms.MessageBox]::Show($consentText, '云端数据授权', 'YesNo', 'Question', 'Button2')
            if ($consent -ne [System.Windows.Forms.DialogResult]::Yes) { return }
            if (-not [string]::IsNullOrWhiteSpace([string]$keyBox.Text)) {
                $null = Set-CDriveAgentCredential ([string]$keyBox.Text) 'default' $agentDataRoot
            }
            $candidate = Grant-CDriveAgentCloudConsent $candidate
            $null = Save-CDriveAgentConfig $candidate $agentConfigPath
            $keyBox.Clear()
            $dialog.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $dialog.Close()
        } catch {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '配置未保存', 'OK', 'Warning') | Out-Null
        }
    })

    if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        Update-AgentMode
        if ($null -ne $assistantState.Config) {
            Add-AssistantMessage '助手' '云端 Agent 已启用。所有页面操作仍受工具白名单约束，清理前必须由你在原生确认框中同意。'
        } else {
            Add-AssistantMessage '助手' '云端 Agent 已禁用，本机凭据已移除，当前使用本地安全助手。'
        }
    }
    $dialog.Dispose()
}

function Get-AssistantScanPayload {
    return [PSCustomObject]@{
        SchemaVersion = 2
        ScanId = $dashboardState.ScanId
        ManifestHash = $dashboardState.ManifestHash
        ScannedAt = $dashboardState.ScannedAt
        Items = @($dashboardState.SelectionItems | ForEach-Object {
            [PSCustomObject]@{
                Id = [string]$_.Id
                Size = [double]$_.Size
                RecommendationLevel = [string]$_.RecommendationLevel
                SafetyLevel = [string]$_.SafetyLevel
                RecoveryMode = [string]$_.RecoveryMode
            }
        })
    }
}

function Get-AssistantToolContext {
    return [PSCustomObject]@{
        ScanPayload = Get-AssistantScanPayload
        Targets = $copilotTargets
        BeforeFreeBytes = if ($null -ne $dashboardState.CleanBeforeFree) { [double]$dashboardState.CleanBeforeFree } else { 0.0 }
        AfterFreeBytes = if ($null -ne $dashboardState.CleanAfterFree) { [double]$dashboardState.CleanAfterFree } else { 0.0 }
    }
}

function Invoke-OfflineAssistantQuery {
    param([string]$Question = '', [bool]$ShowUser = $true)
    $question = if ([string]::IsNullOrWhiteSpace($Question)) { [string]$assistantInput.Text } else { $Question }
    if ([string]::IsNullOrWhiteSpace($question)) { return }
    if ($ShowUser) {
        Add-AssistantMessage '你' $question
        $assistantInput.Clear()
    }
    if (Test-CDriveTravelIntent $question) {
        Invoke-AssistantTravelQuery $question
        return
    }
    if (Test-AssistantCleanupCommand $question) {
        Invoke-AssistantCleanupWorkflow
        return
    }
    if (@($dashboardState.SelectionItems).Count -eq 0) {
        Add-AssistantMessage '助手' '还没有可分析的扫描结果。请先点击“开始扫描”。扫描过程不会删除文件。'
        return
    }
    try {
        $intent = Resolve-CDriveAssistantIntent $question $copilotTargets
        if ($intent.Intent -eq 'denied') {
            Add-AssistantMessage '助手' '这个请求涉及路径、命令、绕过规则或替代最终确认，已被安全边界拒绝。你可以询问清理项含义，或让我提供低风险勾选建议。'
            return
        }
        $context = Get-AssistantToolContext
        $result = Invoke-CDriveAssistantTool ([string]$intent.Intent) $intent.Arguments $context $assistantContractPath
        switch ([string]$intent.Intent) {
            'explain_item' {
                $level = switch ([string]$result.recommendationLevel) { 'Recommended' { '建议清理' } 'Review' { '谨慎选择' } default { '不建议自动处理' } }
                $recovery = if ([string]$result.recovery -match 'Recycle Bin') { '执行后进入系统回收站，清空前可恢复。' } elseif ([string]$result.recovery -match 'diagnostic') { '仅诊断，助手和清理程序都不会删除。' } else { '属于永久缓存清理，应用可能在之后重新生成。' }
                Add-AssistantMessage '助手' ("$($result.displayName)`r`n建议：$level`r`n说明：$($result.whyConsiderIt)`r`n恢复：$recovery`r`n最终是否执行仍由你在清理清单中确认。")
            }
            'propose_selection' {
                $assistantState.LastProposedIds = @($result.proposedItemIds)
                $btnAssistantApply.Enabled = $assistantState.LastProposedIds.Count -gt 0
                if ($assistantState.LastProposedIds.Count -eq 0) {
                    Add-AssistantMessage '助手' '本次扫描没有符合“建议清理且低风险”条件的项目，我没有改变任何勾选。'
                } else {
                    $names = @($dashboardState.SelectionItems | Where-Object { $assistantState.LastProposedIds -contains [string]$_.Id } | ForEach-Object Name)
                    $proposalText = ('建议勾选 {0} 项，预计 {1}：{2}。' -f $names.Count, (Format-UiBytes ([double]$result.estimatedBytes)), ($names -join '、'))
                    $proposalText += "`r`n点击应用建议只会改变勾选，不会开始清理。"
                    Add-AssistantMessage '助手' $proposalText
                }
            }
            default {
                Add-AssistantMessage '助手' ("本次有 $($result.itemCount) 个可选项目，候选大小合计 $(Format-UiBytes ([double]$result.totalCandidateBytes))。可以继续询问某个项目名称，或让我给出低风险建议。")
            }
        }
    } catch {
        Add-AssistantMessage '助手' ('请求未执行：' + $_.Exception.Message)
    }
}

function Test-AssistantCleanupCommand {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    if ($Text -match '(?i)(不(?:要|用|必|需要|想|再)?|别|取消|停止|拒绝|禁止|not|don''t|do not|cancel|stop).{0,12}(清理|删除|释放|clean|delete|free)') { return $false }
    return $Text -match '(?i)(帮我|请|开始|执行|立即|现在).{0,10}(清理|释放空间)|(清理|释放).{0,10}(C盘|磁盘|缓存|低风险|建议项)|clean.{0,10}(drive|cache|recommended)'
}

function Invoke-AssistantCleanupWorkflow {
    if ($jobState.Process) {
        Add-AssistantMessage '助手' '当前已有扫描或清理任务在运行。我会保留现有任务，完成后你可以继续让我处理建议项。'
        return
    }
    if (@($dashboardState.SelectionItems).Count -eq 0) {
        $assistantState.PendingCleanupAfterScan = $true
        Add-AssistantMessage '助手' '我先执行只读扫描；扫描完成后会自动勾选低风险建议项，并打开原生清理确认。扫描不会删除文件。'
        $selectionOutput = Join-Path $env:TEMP ('cdc-assistant-cleanup-scan-' + [guid]::NewGuid().ToString('N') + '.json')
        Invoke-Main -Arguments @('-Report', '-SkipProfile', '-SelectionOutput', $selectionOutput) -StatusText '助手正在执行只读扫描…' -IsCleaning $false -SelectionOutput $selectionOutput
        return
    }

    foreach ($choice in @($dashboardState.SelectionCheckboxes)) {
        $choice.Checked = $choice.Tag.RecommendationLevel -eq 'Recommended'
    }
    Update-CleanupSelectionSummary
    $selected = @(Get-SelectedCleanupItems)
    if ($selected.Count -eq 0) {
        Add-AssistantMessage '助手' '本次扫描没有低风险建议项，我没有替你勾选或执行任何清理。你可以在“清理清单”中查看谨慎项目。'
        Set-DashboardView 'selection'
        return
    }
    $assistantState.PendingCleanupAfterScan = $false
    Add-AssistantMessage '助手' ('已选择 {0} 个低风险建议项。接下来打开系统原生确认框；只有你点击“是”后才会执行清理。' -f $selected.Count)
    Set-DashboardView 'selection'
    Invoke-SelectedCleanupConfirmation
}

function Invoke-AssistantTravelQuery {
    param([string]$Question)
    $flyAi = Get-CDriveFlyAiExecutable
    if ([string]::IsNullOrWhiteSpace($flyAi)) {
        Add-AssistantMessage '助手' '我可以帮你做一次“心理空间清洁”，规划旅行、查询酒店、机票、火车和景点。当前未安装飞猪官方 FlyAI CLI；管理员安装后即可启用，C 盘清理功能不受影响。'
        return
    }
    if (-not $travelState.Consent) {
        $consent = [System.Windows.Forms.MessageBox]::Show('旅行问题将发送给飞猪 FlyAI，用于检索实时酒店、交通和景点信息。不会发送扫描结果、文件路径、日志或 API Key。是否同意本次程序运行期间启用？', '启用飞猪旅行建议', 'YesNo', 'Information', 'Button2')
        if ($consent -ne [System.Windows.Forms.DialogResult]::Yes) {
            Add-AssistantMessage '助手' '已取消飞猪旅行搜索，没有发送任何数据。'
            return
        }
        $travelState.Consent = $true
    }
    if ($travelState.Process) {
        Add-AssistantMessage '助手' '上一条旅行建议仍在查询，请稍等。'
        return
    }
    $travelState.RequestFile = Join-Path $env:TEMP ('cdc-flyai-request-' + [guid]::NewGuid().ToString('N') + '.json')
    $travelState.OutputFile = Join-Path $env:TEMP ('cdc-flyai-output-' + [guid]::NewGuid().ToString('N') + '.json')
    $travelState.LogFile = Join-Path $env:TEMP ('cdc-flyai-log-' + [guid]::NewGuid().ToString('N') + '.txt')
    [System.IO.File]::WriteAllText($travelState.RequestFile, ([PSCustomObject]@{ query = $Question; mode = 'ai-search' } | ConvertTo-Json -Compress), [System.Text.UTF8Encoding]::new($false))
    $travelState.Process = Start-CDriveEngineProcess $travelHostScript @('-RequestPath', $travelState.RequestFile, '-OutputPath', $travelState.OutputFile) $scriptDir $travelState.LogFile
    Set-AgentBusy $true
    $assistantStatus.Text = 'FLYAI · SEARCHING'
    $travelPoll.Start()
}

function Remove-TravelTurnFiles {
    foreach ($path in @($travelState.RequestFile, $travelState.OutputFile, $travelState.LogFile)) {
        if ($path -and (Test-Path -LiteralPath $path -PathType Leaf)) { try { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue } catch {} }
    }
    $travelState.RequestFile = ''
    $travelState.OutputFile = ''
    $travelState.LogFile = ''
}

function Stop-TravelQuery {
    param([bool]$ShowMessage = $false)
    $travelPoll.Stop()
    if ($travelState.Process) {
        try { $travelState.Process.Dispose() } catch {}
        $travelState.Process = $null
    }
    Remove-TravelTurnFiles
    Set-AgentBusy $false
    Update-AgentMode
    if ($ShowMessage) { Add-AssistantMessage '助手' '已停止本次旅行搜索，扫描和清理状态未改变。' }
}

$travelPoll = New-Object System.Windows.Forms.Timer
$travelPoll.Interval = 150
$travelPoll.Add_Tick({
    if (-not $travelState.Process -or -not $travelState.Process.HasExited) { return }
    $travelPoll.Stop()
    try { $exitCode = [int]$travelState.Process.Complete() } catch { $exitCode = 1 }
    $travelState.Process = $null
    try {
        $payload = Get-Content -LiteralPath $travelState.OutputFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $payload.ok) { throw ('[' + [string]$payload.errorCode + '] ' + [string]$payload.message) }
        Add-AssistantMessage '助手' (Format-CDriveFlyAiResult $payload.response)
    } catch {
        $message = if ($_.Exception.Message -match 'FLYAI_NOT_INSTALLED') { '飞猪 FlyAI 尚未安装，暂时不能查询旅行建议。' } elseif ($_.Exception.Message -match 'FLYAI_TIMEOUT') { '飞猪旅行搜索超时，请稍后重试。' } else { '飞猪旅行搜索失败，未改变任何清理或界面状态。' }
        Add-AssistantMessage '助手' $message
    }
    Remove-TravelTurnFiles
    Set-AgentBusy $false
    Update-AgentMode
})

function Set-AgentBusy {
    param([bool]$Busy)
    $btnAssistantSend.Enabled = -not $Busy
    $btnAssistantSettings.Enabled = -not $Busy
    $btnAssistantStop.Visible = $Busy
    $assistantInput.Enabled = -not $Busy
    Update-AssistantComposerLayout
}

function Remove-AgentTurnFiles {
    foreach ($path in @($assistantState.EventFile, $assistantState.LogFile, $assistantState.TurnFile)) {
        if ($path -and (Test-Path -LiteralPath $path -PathType Leaf)) {
            try { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue } catch {}
        }
    }
    $assistantState.EventFile = ''
    $assistantState.LogFile = ''
    $assistantState.TurnFile = ''
    $assistantState.EventLines = 0
}

function Stop-AgentTurn {
    param([bool]$ShowMessage = $false)
    $agentPoll.Stop()
    if ($assistantState.Process) {
        try {
            if (-not $assistantState.Process.HasExited) { $null = $assistantState.Process.Cancel(2000) }
            else { $assistantState.Process.Dispose() }
        } catch {
            Append-Log $log ('停止 Agent 失败：' + $_.Exception.Message)
        }
        $assistantState.Process = $null
    }
    Complete-AssistantDelta
    Remove-AgentTurnFiles
    Set-AgentBusy $false
    if ($ShowMessage) { Add-AssistantMessage '助手' '本次 Agent 请求已停止，扫描和清理任务不受影响。' }
}

function Get-AgentSystemPrompt {
    return @'
你是 C 盘智能清理工具内的受控助手。只使用提供的工具和稳定项目 ID。
不得请求、推断或输出原始路径、用户名、文件内容、命令、脚本、API Key 或运行日志。
扫描是只读操作。选择项目是可撤销的界面状态，不能视为用户同意清理。
如需执行清理，只能打开原生确认框，并明确最终决定必须由用户点击。
微信、QQ 等用户媒体应谨慎说明，默认不要建议选择。
回答简洁、使用中文，并优先解释当前界面和扫描结果。
'@
}

function Convert-AgentToolResultText {
    param($Result)
    if ($null -eq $Result) { return '{"ok":true}' }
    return ($Result | ConvertTo-Json -Depth 12 -Compress)
}

function Get-AgentFailureDisplayText {
    param([string]$Message)
    if ($Message -match 'AGENT_HTTP_(401|403)') { return '云端鉴权失败，请在“配置”中检查 API Key、模型权限和账户状态。' }
    if ($Message -match 'AGENT_HTTP_404') { return '云端接口路径不存在，请检查 API 基础地址是否包含供应商要求的 /v1。' }
    if ($Message -match 'AGENT_HTTP_429') { return '云端请求达到速率或额度限制，请稍后重试并检查账户额度。' }
    if ($Message -match 'AGENT_HTTP_5\d\d') { return '云端供应商或其上游模型暂时异常，请稍后重试；当前界面状态未改变。' }
    if ($Message -match 'AGENT_DNS_FAILED') { return '无法解析云端域名，请检查网络或 API 基础地址。' }
    if ($Message -match 'AGENT_CONNECT_FAILED') { return '无法连接云端服务，请检查端口、防火墙或服务状态。' }
    if ($Message -match 'AGENT_TLS_FAILED') { return '云端 TLS 握手失败，请检查服务端 TLS 配置。' }
    if ($Message -match 'AGENT_CERTIFICATE_FAILED') { return '云端证书验证失败；程序不会绕过证书校验。' }
    if ($Message -match 'AGENT_TIMEOUT') { return '云端响应超时，请稍后重试，或在配置中关闭流式响应。' }
    if ($Message -match 'AGENT_RESPONSE_JSON|AGENT_SSE_JSON') { return '云端返回格式与所选协议不匹配，请检查 Responses / Chat Completions 设置。' }
    return '云端请求失败，已保留现有界面状态。请检查 API 地址、协议、模型和网络后重试。'
}

function Invoke-AgentUiTool {
    param($Call)
    $arguments = [PSCustomObject]@{}
    try {
        if (-not [string]::IsNullOrWhiteSpace([string]$Call.argumentsJson)) {
            $arguments = [string]$Call.argumentsJson | ConvertFrom-Json
        }
    } catch {
        throw '[AGENT_TOOL_ARGUMENTS] 工具参数不是有效 JSON。'
    }

    $handlers = @{
        get_app_state = {
            param($a, $c)
            [PSCustomObject]@{
                schemaVersion = 1
                view = [string]$navigationState.View
                scanRunning = ($null -ne $jobState.Process -and -not $dashboardState.IsCleaning)
                cleanupRunning = [bool]$dashboardState.IsCleaning
                scanId = [string]$dashboardState.ScanId
                candidateCount = @($dashboardState.SelectionItems).Count
                selectedCount = @($dashboardState.SelectedIds.Keys).Count
                canPrepareCleanup = ((-not $jobState.Process) -and @($dashboardState.SelectedIds.Keys).Count -gt 0)
            }
        }
        navigate_view = {
            param($a, $c)
            Set-DashboardView ([string]$a.view)
            [PSCustomObject]@{ schemaVersion = 1; view = [string]$navigationState.View; reversibleUiState = $true }
        }
        start_scan = {
            param($a, $c)
            if ($jobState.Process) { throw '[AGENT_SCAN_BUSY] 当前已有扫描或清理任务。' }
            $selectionOutput = Join-Path $env:TEMP ('cdc-agent-scan-' + [guid]::NewGuid().ToString('N') + '.json')
            $argumentsForScan = switch ([string]$a.scope) {
                'recommended' { @('-Report', '-SkipProfile', '-SelectionOutput', $selectionOutput) }
                'user-profile' { @('-Report', '-SelectionOutput', $selectionOutput) }
                'full-diagnostic' { @('-Report', '-FullScan', '-SelectionOutput', $selectionOutput) }
                default { throw '[AGENT_SCAN_SCOPE] 不支持的扫描范围。' }
            }
            Invoke-Main -Arguments $argumentsForScan -StatusText 'Agent 已请求只读扫描…' -IsCleaning $false -SelectionOutput $selectionOutput
            [PSCustomObject]@{ schemaVersion = 1; action = 'scan-started'; scope = [string]$a.scope; readOnly = $true; completed = $false }
        }
        cancel_scan = {
            param($a, $c)
            if (-not $jobState.Process -or $dashboardState.IsCleaning) { throw '[AGENT_SCAN_NOT_RUNNING] 当前没有可取消的扫描。' }
            $poll.Stop()
            $elapsed = Stop-UiJob $true
            Set-UiBusy $false
            $dashboardState.LastAction = '扫描已取消'
            $dashboardState.LastFinished = Get-Date
            foreach ($temporaryPath in @($jobState.SelectionOutput, $jobState.SelectionFile, $jobState.LogFile, $jobState.EventFile)) {
                if ($temporaryPath -and (Test-Path -LiteralPath $temporaryPath)) {
                    try { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue } catch {}
                }
            }
            $jobState.SelectionOutput = ''
            $jobState.SelectionFile = ''
            $jobState.LogFile = ''
            $jobState.EventFile = ''
            $jobState.EventLines = 0
            Update-Dashboard
            [PSCustomObject]@{ schemaVersion = 1; action = 'scan-cancelled'; elapsedMilliseconds = $elapsed; cleanupAffected = $false }
        }
        set_selection = {
            param($a, $c)
            $selection = Invoke-CDriveAssistantTool 'set_selection' $a $c $assistantContractPath
            foreach ($choice in @($dashboardState.SelectionCheckboxes)) {
                $choice.Checked = @($selection.selectedItemIds) -contains [string]$choice.Tag.Id
            }
            Update-CleanupSelectionSummary
            [PSCustomObject]@{ schemaVersion = 1; selectedItemIds = @($selection.selectedItemIds); selectedCount = @($selection.selectedItemIds).Count; reversibleUiState = $true; cleanupStarted = $false }
        }
        clear_selection = {
            param($a, $c)
            foreach ($choice in @($dashboardState.SelectionCheckboxes)) { $choice.Checked = $false }
            Update-CleanupSelectionSummary
            [PSCustomObject]@{ schemaVersion = 1; selectedItemIds = @(); reversibleUiState = $true; cleanupStarted = $false }
        }
        show_cleanup_confirmation = {
            param($a, $c)
            if ([string]::IsNullOrWhiteSpace([string]$dashboardState.ScanId) -or [string]$a.planId -ne [string]$dashboardState.ScanId) {
                throw '[AGENT_PLAN_STALE] 确认请求不属于当前扫描。'
            }
            if (@(Get-SelectedCleanupItems).Count -eq 0) { throw '[AGENT_SELECTION_EMPTY] 尚未选择清理项。' }
            Set-DashboardView 'selection'
            Invoke-SelectedCleanupConfirmation
            [PSCustomObject]@{ schemaVersion = 1; planId = [string]$a.planId; action = 'native-confirmation-shown'; cleanupStarted = [bool]$dashboardState.IsCleaning; userApprovalRequired = $true }
        }
        open_latest_report = {
            param($a, $c)
            if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) { throw '[AGENT_REPORT_MISSING] 还没有可打开的报告。' }
            Start-Process -FilePath $reportPath
            [PSCustomObject]@{ schemaVersion = 1; action = 'report-opened' }
        }
        open_system_settings = {
            param($a, $c)
            $uri = switch ([string]$a.settingId) {
                'storage' { 'ms-settings:storagesense' }
                'apps' { 'ms-settings:appsfeatures' }
                'temporary-files' { 'ms-settings:storagerecommendations' }
                default { throw '[AGENT_SETTING_ID] 不支持的设置页。' }
            }
            Start-Process -FilePath $uri
            [PSCustomObject]@{ schemaVersion = 1; action = 'setting-opened'; settingId = [string]$a.settingId }
        }
    }

    return Invoke-CDriveUiActionBroker ([string]$Call.callId) ([string]$Call.name) $arguments (Get-AssistantToolContext) $assistantContractPath $handlers $assistantState.ReplayCache
}

function Start-AgentModelCall {
    if ($assistantState.Process) { return }
    if ($assistantState.ModelCalls -ge 6) {
        Add-AssistantMessage '助手' '本轮已达到模型调用上限。请检查当前界面状态后再发起新问题。'
        Set-AgentBusy $false
        return
    }
    $assistantState.ModelCalls++
    $assistantState.TurnId = [guid]::NewGuid().ToString('N')
    $assistantState.TurnFile = Join-Path $env:TEMP ('cdc-agent-turn-' + $assistantState.TurnId + '.json')
    $assistantState.EventFile = Join-Path $env:TEMP ('cdc-agent-events-' + $assistantState.TurnId + '.ndjson')
    $assistantState.LogFile = Join-Path $env:TEMP ('cdc-agent-host-' + $assistantState.TurnId + '.log')
    $assistantState.EventLines = 0
    $turn = [PSCustomObject]@{ schemaVersion = 1; turnId = $assistantState.TurnId; messages = $assistantState.Messages.ToArray() }
    $null = Assert-CDriveAgentTurn $turn
    [System.IO.File]::WriteAllText($assistantState.TurnFile, ($turn | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
    try {
        $arguments = @('-ConfigPath', $agentConfigPath, '-TurnPath', $assistantState.TurnFile, '-ToolContractPath', $assistantContractPath, '-EventOutput', $assistantState.EventFile, '-CredentialRoot', $agentDataRoot)
        if ($assistantState.FixtureResponsePath) { $arguments += @('-FixtureResponsePath', [string]$assistantState.FixtureResponsePath) }
        if ($assistantState.FixtureSsePath) { $arguments += @('-FixtureSsePath', [string]$assistantState.FixtureSsePath) }
        $assistantState.Process = Start-CDriveEngineProcess $agentHostScript $arguments $scriptDir $assistantState.LogFile
        Set-AgentBusy $true
        $agentPoll.Start()
    } catch {
        Remove-AgentTurnFiles
        Set-AgentBusy $false
        throw
    }
}

function Complete-AgentProcess {
    param($CompletedEvent, [bool]$Succeeded)
    $agentPoll.Stop()
    if ($assistantState.Process) {
        try { $null = $assistantState.Process.Complete() } catch {}
        $assistantState.Process = $null
    }
    Complete-AssistantDelta
    if (-not $Succeeded -or $null -eq $CompletedEvent) {
        $failureMessage = if ($CompletedEvent -and $CompletedEvent.data.message) { [string]$CompletedEvent.data.message } else { '' }
        $detail = Get-AgentFailureDisplayText $failureMessage
        Add-AssistantMessage '助手' $detail
        Remove-AgentTurnFiles
        Set-AgentBusy $false
        return
    }

    $text = [string]$CompletedEvent.data.text
    $calls = @($CompletedEvent.data.toolCalls | Where-Object { $null -ne $_ })
    $assistantMessage = [PSCustomObject]@{ role = 'assistant'; content = $text; toolCalls = @($calls) }
    $assistantState.Messages.Add($assistantMessage)
    if ($calls.Count -eq 0) {
        Remove-AgentTurnFiles
        Set-AgentBusy $false
        return
    }
    foreach ($call in $calls) {
        if ($assistantState.ToolCalls -ge 8) {
            Add-AssistantMessage '助手' '本轮已达到工具调用上限，后续操作已停止。'
            Remove-AgentTurnFiles
            Set-AgentBusy $false
            return
        }
        $assistantState.ToolCalls++
        try {
            $result = Invoke-AgentUiTool $call
            $toolText = Convert-AgentToolResultText $result
        } catch {
            $errorCode = if ($_.Exception.Message -match '\[([A-Z0-9_]+)\]') { [string]$Matches[1] } else { 'AGENT_TOOL_FAILED' }
            $toolText = ([PSCustomObject]@{ ok = $false; errorCode = $errorCode } | ConvertTo-Json -Compress)
        }
        $assistantState.Messages.Add([PSCustomObject]@{ role = 'tool'; callId = [string]$call.callId; content = $toolText })
    }
    Remove-AgentTurnFiles
    Start-AgentModelCall
}

$agentPoll = New-Object System.Windows.Forms.Timer
$agentPoll.Interval = 100
$agentPoll.Add_Tick({
    $eventFile = [string]$assistantState.EventFile
    if ($eventFile -and (Test-Path -LiteralPath $eventFile -PathType Leaf)) {
        try {
            $lines = @(Get-Content -LiteralPath $eventFile -Encoding UTF8)
            if ($lines.Count -gt $assistantState.EventLines) {
                for ($index = $assistantState.EventLines; $index -lt $lines.Count; $index++) {
                    if ([string]::IsNullOrWhiteSpace($lines[$index])) { continue }
                    $event = $lines[$index] | ConvertFrom-Json
                    if ([string]$event.turnId -ne [string]$assistantState.TurnId) { continue }
                    if ([string]$event.type -eq 'agent.text.delta') { Add-AssistantDelta ([string]$event.data.text) }
                }
                $assistantState.EventLines = $lines.Count
            }
        } catch {
            Append-Log $log ('读取 Agent 事件失败：' + $_.Exception.Message)
        }
    }
    if ($assistantState.Process -and $assistantState.Process.HasExited) {
        $terminalEvent = $null
        try {
            $events = @(Get-Content -LiteralPath $assistantState.EventFile -Encoding UTF8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_ | ConvertFrom-Json })
            $terminalEvent = @($events | Where-Object { $_.type -in @('agent.turn.completed', 'agent.turn.failed') }) | Select-Object -Last 1
        } catch {}
        Complete-AgentProcess $terminalEvent ([string]$terminalEvent.type -eq 'agent.turn.completed')
    }
})

function Invoke-CloudAssistantQuery {
    param([string]$Question)
    if (-not (Test-CDriveAgentTextSafe $Question)) {
        Add-AssistantMessage '助手' '这个请求包含路径、命令、凭据或绕过确认的内容，已在联网前拒绝。'
        return
    }
    $assistantState.Messages.Clear()
    $assistantState.ReplayCache = @{}
    $assistantState.ModelCalls = 0
    $assistantState.ToolCalls = 0
    $assistantState.AssistantBubbleOpen = $false
    $assistantState.ActiveBubble = $null
    $assistantState.Messages.Add([PSCustomObject]@{ role = 'system'; content = Get-AgentSystemPrompt })
    if ([string]$assistantState.Config.protocol -eq 'text-only' -and @($dashboardState.SelectionItems).Count -gt 0) {
        $safeSummary = ConvertTo-CDriveCopilotSummary (Get-AssistantScanPayload)
        $summaryText = '当前扫描的字段白名单摘要：' + ($safeSummary | ConvertTo-Json -Depth 8 -Compress)
        $assistantState.Messages.Add([PSCustomObject]@{ role = 'system'; content = $summaryText })
    }
    $assistantState.Messages.Add([PSCustomObject]@{ role = 'user'; content = $Question })
    Start-AgentModelCall
}

function Invoke-AssistantQuery {
    $question = [string]$assistantInput.Text
    if ([string]::IsNullOrWhiteSpace($question) -or $assistantState.Process -or $travelState.Process) { return }
    Add-AssistantMessage '你' $question
    $assistantInput.Clear()
    if (Test-CDriveTravelIntent $question) {
        Invoke-AssistantTravelQuery $question
        return
    }
    if (Test-AssistantCleanupCommand $question) {
        Invoke-AssistantCleanupWorkflow
        return
    }
    if ($null -eq $assistantState.Config) {
        Invoke-OfflineAssistantQuery -Question $question -ShowUser $false
        return
    }
    try { Invoke-CloudAssistantQuery $question }
    catch {
        Add-AssistantMessage '助手' ('云端 Agent 未启动：' + $_.Exception.Message + ' 已切换本地安全助手。')
        Invoke-OfflineAssistantQuery -Question $question -ShowUser $false
    }
}

$btnScan.Add_Click({
    $selectionOutput = Join-Path $env:TEMP ('cdc-scan-selection-{0}.json' -f [guid]::NewGuid().ToString('N'))
    $arguments = @('-Report', '-SkipProfile', '-SelectionOutput', $selectionOutput)
    Invoke-Main -Arguments $arguments -StatusText '正在扫描（不删除任何文件）…' -IsCleaning $false -SelectionOutput $selectionOutput
})

$navOverview.Add_Click({ Set-DashboardView 'overview' })
$navSelection.Add_Click({ Set-DashboardView 'selection' })
$navLogs.Add_Click({ Set-DashboardView 'logs' })
$navAssistant.Add_Click({ Set-DashboardView 'assistant' })

$btnAssistantSend.Add_Click({ Invoke-AssistantQuery })
$btnAssistantSettings.Add_Click({ Show-AgentSettingsDialog })
$btnAssistantStop.Add_Click({ if ($travelState.Process) { Stop-TravelQuery $true } else { Stop-AgentTurn $true } })
$assistantInput.Add_KeyDown({
    param($sender, $eventArgs)
    if ($eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        $eventArgs.SuppressKeyPress = $true
        Invoke-AssistantQuery
    }
})
$btnAssistantApply.Add_Click({
    if (@($assistantState.LastProposedIds).Count -eq 0) { return }
    try {
        $context = Get-AssistantToolContext
        $selection = Invoke-CDriveAssistantTool 'set_selection' @{ itemIds = @($assistantState.LastProposedIds) } $context $assistantContractPath
        foreach ($choice in @($dashboardState.SelectionCheckboxes)) {
            $choice.Checked = @($selection.selectedItemIds) -contains [string]$choice.Tag.Id
        }
        Update-CleanupSelectionSummary
        Add-AssistantMessage '助手' '建议已应用到清理清单。你仍可逐项修改；只有点击“执行所选项”并在确认框同意后才会清理。'
        Set-DashboardView 'selection'
    } catch {
        Add-AssistantMessage '助手' ('无法应用建议：' + $_.Exception.Message)
    }
})

$btnSelectSuggested.Add_Click({
    foreach ($choice in @($dashboardState.SelectionCheckboxes)) {
        $choice.Checked = $choice.Tag.RecommendationLevel -eq 'Recommended'
    }
    Update-CleanupSelectionSummary
})

$btnClearSelection.Add_Click({
    foreach ($choice in @($dashboardState.SelectionCheckboxes)) { $choice.Checked = $false }
    Update-CleanupSelectionSummary
})

$btnReport.Add_Click({
    if (Test-Path -LiteralPath $reportPath) {
        Start-Process $reportPath
    } else {
        [System.Windows.Forms.MessageBox]::Show('还没有报告。请先点「开始扫描」。', 'C盘清理', 'OK', 'Information') | Out-Null
    }
})

function Invoke-SelectedCleanupConfirmation {
    $selected = @(Get-SelectedCleanupItems)
    if ($selected.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('请先完成扫描，并在「清理清单」中勾选需要执行的项目。', '尚未选择清理项', 'OK', 'Information') | Out-Null
        Set-DashboardView 'selection'
        return
    }
    $selectedSize = 0.0
    $recoverableSize = 0.0
    foreach ($item in $selected) {
        if ([string]$item.RecoveryMode -eq 'RecycleBin') { $recoverableSize += [double]$item.Size }
        else { $selectedSize += [double]$item.Size }
    }
    $userContent = @($selected | Where-Object { $_.SafetyLevel -eq 'UserContent' })
    if ($userContent.Count -gt 0 -and @($selected | Where-Object { $_.Id -eq 'recycle-bin' }).Count -gt 0) {
        [System.Windows.Forms.MessageBox]::Show('为保留微信/QQ 图片与视频的恢复机会，用户内容不能和“清空回收站”在同一批执行。请取消其中一类后重试。', '恢复策略冲突', 'OK', 'Warning') | Out-Null
        return
    }
    $userContentWarning = if ($userContent.Count -gt 0) {
        "`r`n`r`n注意：已选择用户内容项目：$($userContent.Name -join '、')。约 $(Format-UiBytes $recoverableSize) 会移入系统回收站，清空回收站前可恢复；聊天记录、数据库与 FileRecv 文件不会被处理。"
    } else { '' }
    $msg = "即将执行您勾选的 $($selected.Count) 项，预计立即释放 $(Format-UiBytes $selectedSize)。$userContentWarning`r`n`r`n只会执行清理清单中已勾选的固定目标；不会删除空间大户、重复目录、聊天数据库、FileRecv、休眠/页面文件。`r`n`r`n是否继续？"
    $r = [System.Windows.Forms.MessageBox]::Show($msg, '确认清理', 'YesNo', 'Warning', 'Button2')
    if ($r -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    $selectionFile = New-SelectedCleanupFile
    if (-not $selectionFile) { return }
    Start-CleanAnimation
    $arguments = @('-Clean', '-Force', '-Report', '-SelectionFile', $selectionFile)
    Invoke-Main -Arguments $arguments -StatusText '正在清理已选项目…' -IsCleaning $true -SelectionFile $selectionFile
}

$btnClean.Add_Click({ Invoke-SelectedCleanupConfirmation })

$btnExit.Add_Click({
    if ($jobState.Process) {
        $poll.Stop()
        $elapsed = Stop-UiJob $true
        $dashboardState.IsCleaning = $false
        $dashboardState.LastAction = '任务已取消'
        $dashboardState.LastFinished = Get-Date
        Set-UiBusy $false
        $status.Text = Get-CFreeText
        Append-Log $log ("--- 任务已取消，确认耗时 $elapsed ms ---")
        foreach ($temporaryPath in @($jobState.SelectionOutput, $jobState.SelectionFile, $jobState.LogFile, $jobState.EventFile)) {
            if ($temporaryPath -and (Test-Path -LiteralPath $temporaryPath)) {
                try { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue } catch {}
            }
        }
        $jobState.SelectionOutput = ''
        $jobState.SelectionFile = ''
        $jobState.LogFile = ''
        $jobState.EventFile = ''
        $jobState.EventLines = 0
        Update-Dashboard
        return
    }
    $form.Close()
})
$form.Add_FormClosing({
    $poll.Stop()
    $agentPoll.Stop()
    $travelPoll.Stop()
    $livePulseTimer.Stop()
    Stop-AgentTurn
    Stop-TravelQuery
    Stop-LogoAnimation
    Stop-CleanAnimation
    Stop-UiJob $true | Out-Null
    foreach ($temporaryPath in @($jobState.SelectionOutput, $jobState.SelectionFile, $jobState.LogFile, $jobState.EventFile)) {
        if ($temporaryPath -and (Test-Path -LiteralPath $temporaryPath)) {
            try { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue } catch {}
        }
    }
    foreach ($frame in $spriteFrames) { try { $frame.Dispose() } catch {} }
    if ($spriteSheet) { try { $spriteSheet.Dispose() } catch {} }
    foreach ($frame in $logoFrames) { try { $frame.Dispose() } catch {} }
    if ($logoSpriteSheet) { try { $logoSpriteSheet.Dispose() } catch {} }
    if ($logoStaticImage -and $logoFrames.Count -eq 0) { try { $logoStaticImage.Dispose() } catch {} }
    if ($assistantAgentAvatarImage) { try { $assistantAgentAvatarImage.Dispose() } catch {} }
    if ($assistantUserAvatarImage) { try { $assistantUserAvatarImage.Dispose() } catch {} }
})

Append-Log $log '就绪。点「开始扫描」只诊断，不会删文件。'
Append-Log $log ('主程序：' + $mainScript)
if ($spriteLoadError) { Append-Log $log ('动画资源加载失败：' + $spriteLoadError) }
if ($logoLoadError) { Append-Log $log ('Logo 动画资源加载失败：' + $logoLoadError) }
Update-AgentMode
Update-Dashboard
$topBar.Add_Resize({ Update-TopBarLayout })
$form.Add_Shown({ Update-TopBarLayout; Update-TrackLayout; Update-Dashboard })
$form.Add_Shown({ Set-DashboardView 'overview' })
$form.Add_Resize({ Update-Dashboard })

[void]$form.ShowDialog()
