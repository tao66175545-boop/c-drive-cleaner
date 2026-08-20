[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [string]$OutputDirectory = '',
    [string]$AgentFileName = 'assistant-agent-wave-v2.png',
    [switch]$AgentOnly
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$toolDirectory = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path (Split-Path -Parent $toolDirectory) 'assets'
}

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

function Save-PngAtomically {
    param([System.Drawing.Bitmap]$Bitmap, [string]$DestinationPath)
    $temporaryPath = Join-Path (Split-Path -Parent $DestinationPath) ('.' + [System.IO.Path]::GetFileNameWithoutExtension($DestinationPath) + '-' + [guid]::NewGuid().ToString('N') + '.png')
    try {
        $Bitmap.Save($temporaryPath, [System.Drawing.Imaging.ImageFormat]::Png)
        [System.IO.File]::Copy($temporaryPath, $DestinationPath, $true)
    } finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) { Remove-Item -LiteralPath $temporaryPath -Force }
    }
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
            $cropSize = [Math]::Min($source.Width, $source.Height)
            $cropSize = [Math]::Floor($cropSize * 0.86)
            $cropX = [Math]::Max(0, [Math]::Floor(($source.Width - $cropSize) * 0.45))
            $cropY = [Math]::Max(0, [Math]::Floor(($source.Height - $cropSize) * 0.54))
            if ($cropX + $cropSize -gt $source.Width) { $cropX = $source.Width - $cropSize }
            if ($cropY + $cropSize -gt $source.Height) { $cropY = $source.Height - $cropSize }
            $sourceRect = [System.Drawing.Rectangle]::new($cropX, $cropY, $cropSize, $cropSize)
            $graphics.DrawImage($source, [System.Drawing.Rectangle]::new(4, 4, 248, 248), $sourceRect, [System.Drawing.GraphicsUnit]::Pixel)
            $graphics.ResetClip()
        } finally { $circle.Dispose() }

        $border = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(225, 216, 207), 3)
        try { $graphics.DrawEllipse($border, 5, 5, 246, 246) } finally { $border.Dispose() }
        Save-PngAtomically $bitmap (Join-Path $OutputDirectory $AgentFileName)
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
        Save-PngAtomically $bitmap (Join-Path $OutputDirectory ("assistant-user-{0}.png" -f $Index))
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
if (-not $AgentOnly) {
    for ($index = 0; $index -lt $palettes.Count; $index++) {
        Save-UserAvatar ($index + 1) $palettes[$index][0] $palettes[$index][1] $palettes[$index][2]
    }
}

Write-Output ([PSCustomObject]@{
    AgentAvatar = (Join-Path $OutputDirectory $AgentFileName)
    UserAvatars = if ($AgentOnly) { @() } else { 1..$palettes.Count | ForEach-Object { Join-Path $OutputDirectory ("assistant-user-{0}.png" -f $_) } }
})
