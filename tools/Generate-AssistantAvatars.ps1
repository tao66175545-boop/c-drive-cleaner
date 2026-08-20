[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'assets')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
    throw "Avatar source image was not found: $SourcePath"
}
if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

function New-CirclePath {
    param([float]$X, [float]$Y, [float]$Size)
    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $path.AddEllipse($X, $Y, $Size, $Size)
    return $path
}

function Enable-QualityDrawing {
    param([System.Drawing.Graphics]$Graphics)
    $Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $Graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $Graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $Graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
}

function Save-AgentAvatar {
    $source = [System.Drawing.Image]::FromFile($SourcePath)
    $bitmap = [System.Drawing.Bitmap]::new(256, 256, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        Enable-QualityDrawing $graphics
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $circle = New-CirclePath 4 4 248
        try {
            $graphics.SetClip($circle)
            $graphics.Clear([System.Drawing.Color]::FromArgb(251, 242, 233))
            $sourceRect = [System.Drawing.Rectangle]::new(184, 112, 660, 660)
            $graphics.DrawImage($source, [System.Drawing.Rectangle]::new(0, 0, 256, 256), $sourceRect, [System.Drawing.GraphicsUnit]::Pixel)

            # Recompose a raised arm from the character palette so the small avatar reads as a wave.
            $skin = [System.Drawing.Color]::FromArgb(246, 195, 143)
            $skinLight = [System.Drawing.Color]::FromArgb(255, 215, 170)
            $shirt = [System.Drawing.Color]::FromArgb(190, 37, 31)
            $armPath = [System.Drawing.Drawing2D.GraphicsPath]::new()
            try {
                $armPath.AddBezier(184, 185, 198, 157, 203, 121, 207, 91)
                $armPath.AddBezier(207, 91, 220, 91, 229, 101, 226, 116)
                $armPath.AddBezier(226, 116, 220, 151, 215, 181, 207, 204)
                $armPath.CloseFigure()
                $shirtBrush = [System.Drawing.SolidBrush]::new($shirt)
                $skinBrush = [System.Drawing.SolidBrush]::new($skin)
                try {
                    $graphics.FillPath($shirtBrush, $armPath)
                    $graphics.FillEllipse($skinBrush, 194, 66, 39, 48)
                    $graphics.FillEllipse($skinBrush, 198, 57, 9, 30)
                    $graphics.FillEllipse($skinBrush, 207, 53, 9, 32)
                    $graphics.FillEllipse($skinBrush, 216, 56, 9, 30)
                    $graphics.FillEllipse($skinBrush, 225, 63, 9, 25)
                    $highlight = [System.Drawing.Pen]::new($skinLight, 2)
                    try { $graphics.DrawArc($highlight, 199, 70, 27, 24, 205, 105) } finally { $highlight.Dispose() }
                } finally {
                    $shirtBrush.Dispose()
                    $skinBrush.Dispose()
                }
            } finally { $armPath.Dispose() }
            $graphics.ResetClip()
        } finally { $circle.Dispose() }

        $border = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(225, 216, 207), 3)
        try { $graphics.DrawEllipse($border, 5, 5, 246, 246) } finally { $border.Dispose() }
        $bitmap.Save((Join-Path $OutputDirectory 'assistant-agent-wave.png'), [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
        $source.Dispose()
    }
}

function Save-UserAvatar {
    param([int]$Index, [System.Drawing.Color]$Background, [System.Drawing.Color]$Accent, [System.Drawing.Color]$Skin)
    $bitmap = [System.Drawing.Bitmap]::new(128, 128, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        Enable-QualityDrawing $graphics
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $backgroundBrush = [System.Drawing.SolidBrush]::new($Background)
        $accentBrush = [System.Drawing.SolidBrush]::new($Accent)
        $skinBrush = [System.Drawing.SolidBrush]::new($Skin)
        $hairBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(62, 68, 74))
        try {
            $graphics.FillEllipse($backgroundBrush, 2, 2, 124, 124)
            $graphics.FillEllipse($accentBrush, 22, 78, 84, 60)
            $graphics.FillEllipse($skinBrush, 39, 30, 50, 58)
            if ($Index % 3 -eq 0) {
                $graphics.FillPie($hairBrush, 35, 23, 58, 48, 180, 180)
            } elseif ($Index % 3 -eq 1) {
                $graphics.FillEllipse($hairBrush, 36, 23, 56, 34)
                $graphics.FillRectangle($hairBrush, 36, 39, 9, 24)
            } else {
                $graphics.FillPie($hairBrush, 34, 20, 60, 54, 185, 170)
                $graphics.FillEllipse($hairBrush, 29, 30, 18, 22)
            }
            $eyeBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(66, 55, 51))
            try {
                $graphics.FillEllipse($eyeBrush, 52, 57, 5, 7)
                $graphics.FillEllipse($eyeBrush, 71, 57, 5, 7)
            } finally { $eyeBrush.Dispose() }
        } finally {
            $backgroundBrush.Dispose()
            $accentBrush.Dispose()
            $skinBrush.Dispose()
            $hairBrush.Dispose()
        }
        $border = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(220, 226, 231), 2)
        try { $graphics.DrawEllipse($border, 3, 3, 122, 122) } finally { $border.Dispose() }
        $bitmap.Save((Join-Path $OutputDirectory ("assistant-user-{0}.png" -f $Index)), [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

Save-AgentAvatar
$palettes = @(
    @([System.Drawing.Color]::FromArgb(235, 241, 244), [System.Drawing.Color]::FromArgb(91, 125, 143), [System.Drawing.Color]::FromArgb(238, 190, 153)),
    @([System.Drawing.Color]::FromArgb(247, 234, 235), [System.Drawing.Color]::FromArgb(181, 30, 40), [System.Drawing.Color]::FromArgb(246, 205, 170)),
    @([System.Drawing.Color]::FromArgb(237, 242, 235), [System.Drawing.Color]::FromArgb(86, 120, 91), [System.Drawing.Color]::FromArgb(212, 164, 128)),
    @([System.Drawing.Color]::FromArgb(241, 238, 246), [System.Drawing.Color]::FromArgb(114, 99, 135), [System.Drawing.Color]::FromArgb(244, 200, 165)),
    @([System.Drawing.Color]::FromArgb(244, 241, 232), [System.Drawing.Color]::FromArgb(129, 105, 76), [System.Drawing.Color]::FromArgb(190, 137, 102)),
    @([System.Drawing.Color]::FromArgb(232, 240, 244), [System.Drawing.Color]::FromArgb(73, 112, 139), [System.Drawing.Color]::FromArgb(224, 177, 139))
)
for ($index = 0; $index -lt $palettes.Count; $index++) {
    Save-UserAvatar ($index + 1) $palettes[$index][0] $palettes[$index][1] $palettes[$index][2]
}

Write-Output ([PSCustomObject]@{
    AgentAvatar = (Join-Path $OutputDirectory 'assistant-agent-wave.png')
    UserAvatars = 1..$palettes.Count | ForEach-Object { Join-Path $OutputDirectory ("assistant-user-{0}.png" -f $_) }
})
