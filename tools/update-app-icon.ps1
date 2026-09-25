# Convert the existing rhythmstar-web artwork into Android launcher densities.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$projectRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $projectRoot 'assets/branding/app-icon.png'
$sourceImage = [System.Drawing.Image]::FromFile($sourcePath)
try {
    $densities = @{ mdpi = 48; hdpi = 72; xhdpi = 96; xxhdpi = 144; xxxhdpi = 192 }
    foreach ($density in $densities.GetEnumerator()) {
        $size = [int]$density.Value
        $bitmap = [System.Drawing.Bitmap]::new($size, $size)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $attributes = [System.Drawing.Imaging.ImageAttributes]::new()
        try {
            $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $attributes.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)
            $bounds = [System.Drawing.Rectangle]::new(0, 0, $size, $size)
            $graphics.DrawImage($sourceImage, $bounds, 0, 0, $sourceImage.Width, $sourceImage.Height,
                [System.Drawing.GraphicsUnit]::Pixel, $attributes)
            $destination = Join-Path $projectRoot "android/app/src/main/res/mipmap-$($density.Key)/ic_launcher.png"
            $bitmap.Save($destination, [System.Drawing.Imaging.ImageFormat]::Png)
            Write-Output "$($density.Key): ${size}x${size}"
        } finally {
            $attributes.Dispose()
            $graphics.Dispose()
            $bitmap.Dispose()
        }
    }
} finally {
    $sourceImage.Dispose()
}
