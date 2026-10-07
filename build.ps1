# Builds ClawdPet.exe with the C# compiler that ships with Windows (.NET Framework 4.x).
# Nothing to install. Run:  powershell -ExecutionPolicy Bypass -File build.ps1
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$fw = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319"
$ico = Join-Path $here 'clawd.ico'

# Draw the app icon (a 256px PNG wrapped in an .ico container)
Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap 256, 256
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::Transparent)
$o = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(0xF2, 0x65, 0x22))
$k = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(0x1A, 0x19, 0x15))
$c = 14; $x0 = 128; $y0 = 198   # cell size, centre, foot line
function Cell($b, [int]$cx, [int]$cy, [int]$w, [int]$h) { $g.FillRectangle($b, $x0 + $cx * $c, $y0 + $cy * $c, $w * $c, $h * $c) }
Cell $o -7 -10 14 8
Cell $o -9 -7 18 2
foreach ($lx in -6, -4, 3, 5) { Cell $o $lx -2 1 2 }
Cell $k -4 -8 1 2
Cell $k 3 -8 1 2
$g.Dispose()
$ms = New-Object System.IO.MemoryStream
$bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
$png = $ms.ToArray()
$fs = [System.IO.File]::Create($ico)
$bw = New-Object System.IO.BinaryWriter $fs
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]1)
$bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([byte]0)
$bw.Write([uint16]1); $bw.Write([uint16]32)
$bw.Write([uint32]$png.Length); $bw.Write([uint32]22)
$bw.Write($png)
$bw.Close()

& "$fw\csc.exe" /nologo /target:winexe /optimize+ /codepage:65001 `
    "/out:$here\ClawdPet.exe" "/win32icon:$ico" `
    "/r:$fw\WPF\PresentationCore.dll" "/r:$fw\WPF\PresentationFramework.dll" "/r:$fw\WPF\WindowsBase.dll" `
    /r:System.Xaml.dll /r:System.Windows.Forms.dll /r:System.Drawing.dll `
    "$here\ClawdPet.cs"
if ($LASTEXITCODE -ne 0) { throw "Build failed" }
Write-Host "Done: $here\ClawdPet.exe"
