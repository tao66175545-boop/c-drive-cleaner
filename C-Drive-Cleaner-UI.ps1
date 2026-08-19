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
$localDataRoot = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'CDriveCleaner' } else { Join-Path $env:TEMP 'CDriveCleaner' }
$reportPath = Join-Path (Join-Path $localDataRoot 'reports') 'C盘清理诊断报告.html'
$spriteSheetPath = Join-Path $scriptDir 'assets\cleaning-sprite-source.png'
$logoSvgPath = Join-Path $scriptDir 'assets\logo-animated.svg'
$logoSpritePath = Join-Path $scriptDir 'assets\logo-animated-sprite.png'
$logoFallbackPath = Join-Path $scriptDir 'assets\sugon-cloud-logo-red.png'

if (-not (Test-Path -LiteralPath $mainScript)) {
    [System.Windows.Forms.MessageBox]::Show("找不到主程序：`n$mainScript", 'C盘清理', 'OK', 'Error') | Out-Null
    exit 1
}

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

$sideFooter = New-Object System.Windows.Forms.Label
$sideFooter.Text = '本地工具'
$sideFooter.Font = New-Object System.Drawing.Font('Segoe UI', 7)
$sideFooter.ForeColor = [System.Drawing.Color]::FromArgb(147, 159, 168)
$sideFooter.AutoSize = $true
$sideFooter.Location = New-Object System.Drawing.Point(20, 0)
$sideFooter.Anchor = 'Bottom,Left'
$sideFooter.Add_Layout({ $sideFooter.Top = $sideBar.ClientSize.Height - 28 })
$sideBar.Controls.AddRange(@($sideDivider, $navOverview, $navLogs, $navSelection, $sideFooter))

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

$dashboardGrid.Controls.Add($diskCard, 0, 1)
$dashboardGrid.SetColumnSpan($diskCard, 2)
$dashboardGrid.Controls.Add($compareCard, 2, 1)
$dashboardGrid.SetColumnSpan($compareCard, 2)
$dashboardGrid.Controls.Add($logHeader, 0, 2)
$dashboardGrid.SetColumnSpan($logHeader, 4)
$dashboardGrid.Controls.Add($logShell, 0, 3)
$dashboardGrid.SetColumnSpan($logShell, 4)

$topBar.Controls.AddRange(@($title, $hint, $statusCluster, $toolbar, $animationImage, $topRule, $topDivider))
$contentHost.Controls.AddRange(@($dashboardGrid, $selectionView))
$workspace.Controls.AddRange(@($contentHost, $topBar))
$form.Controls.AddRange(@($workspace, $sideBar))

$buttons = @($btnScan, $btnReport, $btnClean, $btnExit)
$jobState = @{ Job = $null; LastLen = 0; LogFile = ''; SelectionOutput = ''; SelectionFile = '' }
$dashboardState = @{ CleanBeforeFree = $null; CleanAfterFree = $null; IsCleaning = $false; LastAction = '尚未执行操作'; LastFinished = $null; SelectionItems = @(); SelectedIds = @{}; SelectionCheckboxes = @(); ScanId = ''; ManifestHash = ''; ScannedAt = '' }
$navigationState = @{ View = 'overview' }

$toolTips = New-Object System.Windows.Forms.ToolTip
$toolTips.InitialDelay = 350
$toolTips.ReshowDelay = 120
$toolTips.SetToolTip($navOverview, '概览：统计、磁盘状态和清理对比')
$toolTips.SetToolTip($navSelection, '清理清单：查看扫描到的候选项并自行选择')
$toolTips.SetToolTip($navLogs, '日志：专注查看实时输出')
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

function Update-CleanupSelectionRows {
    $rowWidth = [Math]::Max(1, $selectionItemsPanel.ClientSize.Width - 8)
    foreach ($row in @($selectionItemsPanel.Controls)) {
        $row.Width = $rowWidth
        Update-CleanupSelectionRowLayout $row
    }
}

function Update-CleanupSelectionRowLayout {
    param($Row)
    $refs = $Row.Tag
    if ($null -eq $refs) { return }
    $clientWidth = $Row.ClientSize.Width
    $refs.SizeLabel.Left = [Math]::Max(128, $clientWidth - 108)
    $refs.NameLabel.Width = [Math]::Max(72, $refs.SizeLabel.Left - 58)
    $refs.AdviceLabel.Width = [Math]::Max(72, $clientWidth - 142)
}

function Get-SelectedCleanupItems {
    return @($dashboardState.SelectionItems | Where-Object { $dashboardState.SelectedIds.ContainsKey([string]$_.Id) })
}

function Update-CleanupSelectionSummary {
    $selected = @(Get-SelectedCleanupItems)
    $selectedSize = 0.0
    foreach ($item in $selected) { $selectedSize += [double]$item.Size }
    $available = @($dashboardState.SelectionItems).Count
    $selectionSummary.Text = if ($available -eq 0) {
        '本次扫描没有发现可释放的缓存或临时文件'
    } elseif ($selected.Count -eq 0) {
        ('已发现 {0} 项；尚未选择' -f $available)
    } else {
        ('已选择 {0} / {1} 项，预计释放 {2}' -f $selected.Count, $available, (Format-UiBytes $selectedSize))
    }
    $canClean = (-not $jobState.Job) -and $selected.Count -gt 0
    $btnClean.Text = if ($selected.Count -gt 0) { '执行所选项' } else { '清理安全项' }
    $btnClean.Enabled = $canClean
    $btnSelectSuggested.Enabled = (-not $jobState.Job) -and $available -gt 0
    $btnClearSelection.Enabled = (-not $jobState.Job) -and $selected.Count -gt 0
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
    $size.Size = New-Object System.Drawing.Size(94, 22)
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
    param([ValidateSet('overview', 'selection', 'logs')][string]$View)
    $navigationState.View = $View
    $isOverview = $View -eq 'overview'
    $isSelection = $View -eq 'selection'
    foreach ($card in $statCards) { $card.Panel.Visible = $isOverview }
    $diskCard.Visible = $isOverview
    $compareCard.Visible = $isOverview
    $dashboardGrid.Visible = -not $isSelection
    $selectionView.Visible = $isSelection
    if ($isSelection) {
        Update-SelectionViewLayout
        $selectionView.PerformLayout()
        $selectionLayout.PerformLayout()
        Update-SelectionActionLayout
        Update-CleanupSelectionRows
        $selectionView.BringToFront()
    } else {
        $dashboardGrid.BringToFront()
    }
    $dashboardGrid.RowStyles[0].Height = if ($isOverview) { 104 } else { 0 }
    $dashboardGrid.RowStyles[1].Height = if ($isOverview) { 218 } else { 0 }
    $logHeader.Margin = if ($isOverview) { New-Object System.Windows.Forms.Padding(0, 12, 0, 0) } else { New-Object System.Windows.Forms.Padding(0, 0, 0, 0) }

    $navOverview.Selected = $isOverview
    $navSelection.Selected = $isSelection
    $navLogs.Selected = $View -eq 'logs'
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
    foreach ($b in @($btnScan, $btnReport, $btnExit)) { $b.Enabled = (-not $Busy) }
    $btnClean.Enabled = $false
    $btnSelectSuggested.Enabled = -not $Busy
    $btnClearSelection.Enabled = $false
    if (-not $Busy) { Update-CleanupSelectionSummary }
}

function Stop-UiJob {
    if ($jobState.Job) {
        try { Stop-Job $jobState.Job -ErrorAction SilentlyContinue } catch {}
        try { Remove-Job $jobState.Job -Force -ErrorAction SilentlyContinue } catch {}
        $jobState.Job = $null
    }
}

$poll = New-Object System.Windows.Forms.Timer
$poll.Interval = 400
$poll.Add_Tick({
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
    $j = $jobState.Job
    if ($j -and $j.State -in @('Completed', 'Failed', 'Stopped')) {
        $poll.Stop()
        $jobOutput = @()
        try { $jobOutput = @(Receive-Job $j -ErrorAction SilentlyContinue) } catch {}
        $exitCode = if ($jobOutput.Count -gt 0 -and $jobOutput[-1] -is [int]) { [int]$jobOutput[-1] } else { 1 }
        $succeeded = ($j.State -eq 'Completed') -and ($exitCode -eq 0)
        $selectionOutput = $jobState.SelectionOutput
        $selectionFile = $jobState.SelectionFile
        Stop-UiJob
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
        $jobState.SelectionOutput = ''
        $jobState.SelectionFile = ''
        Append-Log $log $(if ($succeeded) { '--- 完成 ---' } else { ('--- 已中止或失败（退出码 {0}）---' -f $exitCode) })
        if ($succeeded -and (Test-Path -LiteralPath $reportPath)) {
            Append-Log $log ('报告：' + $reportPath)
        }
        foreach ($temporaryPath in @($selectionOutput, $selectionFile, $jobState.LogFile)) {
            if ($temporaryPath -and (Test-Path -LiteralPath $temporaryPath)) {
                try { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue } catch {}
            }
        }
        $jobState.LogFile = ''
    }
})

function Invoke-Main {
    param([string]$ExtraArgs, [string]$StatusText, [bool]$IsCleaning = $false, [string]$SelectionOutput = '', [string]$SelectionFile = '')
    if ($jobState.Job) { return }
    $jobState.LogFile = Join-Path $env:TEMP ('cdc-ui-{0}.log' -f [guid]::NewGuid().ToString('N'))
    $jobState.LastLen = 0
    $jobState.SelectionOutput = $SelectionOutput
    $jobState.SelectionFile = $SelectionFile
    Set-Content -LiteralPath $jobState.LogFile -Value '' -Encoding Default
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
    Append-Log $log ('启动主程序  ' + $ExtraArgs)

    $jobState.Job = Start-Job -ScriptBlock {
        param($script, $extra, $logPath, $workDir)
        Set-Location -LiteralPath $workDir
        $line = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "{0}" {1} > "{2}" 2>&1' -f $script, $extra, $logPath
        cmd.exe /c $line
        return $LASTEXITCODE
    } -ArgumentList $mainScript, $ExtraArgs, $jobState.LogFile, $scriptDir

    $poll.Start()
}

$btnScan.Add_Click({
    $selectionOutput = Join-Path $env:TEMP ('cdc-scan-selection-{0}.json' -f [guid]::NewGuid().ToString('N'))
    $args = '-Report -SelectionOutput "{0}"' -f $selectionOutput
    Invoke-Main -ExtraArgs $args -StatusText '正在扫描（不删除任何文件）…' -IsCleaning $false -SelectionOutput $selectionOutput
})

$navOverview.Add_Click({ Set-DashboardView 'overview' })
$navSelection.Add_Click({ Set-DashboardView 'selection' })
$navLogs.Add_Click({ Set-DashboardView 'logs' })

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

$btnClean.Add_Click({
    $selected = @(Get-SelectedCleanupItems)
    if ($selected.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('请先完成扫描，并在「清理清单」中勾选需要执行的项目。', '尚未选择清理项', 'OK', 'Information') | Out-Null
        Set-DashboardView 'selection'
        return
    }
    $selectedSize = 0.0
    foreach ($item in $selected) { $selectedSize += [double]$item.Size }
    $userContent = @($selected | Where-Object { $_.SafetyLevel -eq 'UserContent' })
    $userContentWarning = if ($userContent.Count -gt 0) {
        "`r`n`r`n注意：已选择用户内容项目：$($userContent.Name -join '、')。其中的图片/视频附件删除后不可恢复，聊天记录、数据库与 FileRecv 文件不会被处理。"
    } else { '' }
    $msg = "即将清理您勾选的 $($selected.Count) 项，预计释放 $(Format-UiBytes $selectedSize)。$userContentWarning`r`n`r`n只会执行清理清单中已勾选的固定目标；不会删除空间大户、重复目录、聊天数据库、FileRecv、休眠/页面文件。`r`n`r`n是否继续？"
    $r = [System.Windows.Forms.MessageBox]::Show($msg, '确认清理', 'YesNo', 'Warning', 'Button2')
    if ($r -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    $selectionFile = New-SelectedCleanupFile
    if (-not $selectionFile) { return }
    Start-CleanAnimation
    $args = '-Clean -Force -Report -SelectionFile "{0}"' -f $selectionFile
    Invoke-Main -ExtraArgs $args -StatusText '正在清理已选项目…' -IsCleaning $true -SelectionFile $selectionFile
})

$btnExit.Add_Click({ $form.Close() })
$form.Add_FormClosing({
    $poll.Stop()
    $livePulseTimer.Stop()
    Stop-LogoAnimation
    Stop-CleanAnimation
    Stop-UiJob
    foreach ($temporaryPath in @($jobState.SelectionOutput, $jobState.SelectionFile, $jobState.LogFile)) {
        if ($temporaryPath -and (Test-Path -LiteralPath $temporaryPath)) {
            try { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue } catch {}
        }
    }
    foreach ($frame in $spriteFrames) { try { $frame.Dispose() } catch {} }
    if ($spriteSheet) { try { $spriteSheet.Dispose() } catch {} }
    foreach ($frame in $logoFrames) { try { $frame.Dispose() } catch {} }
    if ($logoSpriteSheet) { try { $logoSpriteSheet.Dispose() } catch {} }
    if ($logoStaticImage -and $logoFrames.Count -eq 0) { try { $logoStaticImage.Dispose() } catch {} }
})

Append-Log $log '就绪。点「开始扫描」只诊断，不会删文件。'
Append-Log $log ('主程序：' + $mainScript)
if ($spriteLoadError) { Append-Log $log ('动画资源加载失败：' + $spriteLoadError) }
if ($logoLoadError) { Append-Log $log ('Logo 动画资源加载失败：' + $logoLoadError) }
Update-Dashboard
$topBar.Add_Resize({ Update-TopBarLayout })
$form.Add_Shown({ Update-TopBarLayout; Update-TrackLayout; Update-Dashboard })
$form.Add_Shown({ Set-DashboardView 'overview' })
$form.Add_Resize({ Update-Dashboard })

[void]$form.ShowDialog()
