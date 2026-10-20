# Draw the same 18-point faceted tower as BabelstaarnetIcon.swift, then
# package native multi-resolution ICO resources for the tray and executable.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$root=Split-Path -Parent $PSScriptRoot
$assets=Join-Path $root 'Windows\Babelstaarnet.Windows\Assets'
New-Item -ItemType Directory -Force -Path $assets | Out-Null
function Write-Ico([string]$Path, [bool]$Active, [bool]$White, [bool]$Application) {
    $frames=[Collections.Generic.List[byte[]]]::new()
    $sizes=@(16,20,24,32,40,48,64,128,256)
    foreach ($size in $sizes) {
        $bitmap=[Drawing.Bitmap]::new($size,$size,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $graphics=[Drawing.Graphics]::FromImage($bitmap)
        $graphics.SmoothingMode=[Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.Clear([Drawing.Color]::Transparent)
        if ($Application) {
            $image=[Drawing.Image]::FromFile((Join-Path $root 'docs\images\logo.png'))
            $graphics.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.DrawImage($image,0,0,$size,$size)
            $image.Dispose()
        } else {
            $graphics.ScaleTransform($size/18.0,$size/18.0)
            $color=if ($White) { [Drawing.Color]::White } else { [Drawing.Color]::FromArgb(32,32,34) }
            $pen=[Drawing.Pen]::new($color,1.25)
            $brush=[Drawing.SolidBrush]::new($color)
            $top=[Drawing.PointF]::new(9,1.75); $right=[Drawing.PointF]::new(16.25,9)
            $bottom=[Drawing.PointF]::new(9,16.25); $left=[Drawing.PointF]::new(1.75,9)
            $junction=[Drawing.PointF]::new(9,5.1)
            $lowerLeft=[Drawing.PointF]::new(5.375,12.625); $lowerRight=[Drawing.PointF]::new(12.625,12.625)
            if ($Active) { $graphics.FillPolygon($brush,[Drawing.PointF[]]@($junction,$lowerLeft,$bottom,$lowerRight)) }
            $graphics.DrawPolygon($pen,[Drawing.PointF[]]@($top,$right,$bottom,$left))
            $graphics.DrawLine($pen,$top,$bottom)
            $graphics.DrawLine($pen,$junction,$lowerLeft); $graphics.DrawLine($pen,$junction,$lowerRight)
            $pen.Dispose(); $brush.Dispose()
        }
        $memory=[IO.MemoryStream]::new(); $bitmap.Save($memory,[Drawing.Imaging.ImageFormat]::Png)
        $frames.Add($memory.ToArray()); $memory.Dispose(); $graphics.Dispose(); $bitmap.Dispose()
    }
    $stream=[IO.File]::Create($Path); $writer=[IO.BinaryWriter]::new($stream)
    try {
        $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$frames.Count)
        $offset=6+16*$frames.Count
        for ($i=0;$i -lt $frames.Count;$i++) {
            $dimension=if ($sizes[$i] -eq 256) {0} else {$sizes[$i]}
            $writer.Write([byte]$dimension); $writer.Write([byte]$dimension)
            $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]32)
            $writer.Write([uint32]$frames[$i].Length); $writer.Write([uint32]$offset)
            $offset += $frames[$i].Length
        }
        foreach ($frame in $frames) { $writer.Write($frame) }
    } finally { $writer.Dispose() }
}
Write-Ico (Join-Path $assets 'Babelstaarnet.ico') $false $false $true
foreach ($state in @('inactive','active')) {
    foreach ($theme in @('light','dark')) {
        Write-Ico (Join-Path $assets "tray-$state-$theme.ico") ($state -eq 'active') ($theme -eq 'dark') $false
    }
}
Write-Host 'Generated executable and active/inactive light/dark tray icons.'
