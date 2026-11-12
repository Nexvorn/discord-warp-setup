<#
.SYNOPSIS
  Compile app\*.cs into DiscordWARP.exe with the C# compiler that ships with Windows (.NET Framework 4.8, C# 5).
  No SDK or Visual Studio needed. Also creates app.ico (16/32/48/256 px) and embeds it.
.OUTPUTS
  app\bin\DiscordWARP.exe, app\bin\app.ico
#>
param([string]$Version = '')
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot; $bin = Join-Path $here 'bin'; New-Item -ItemType Directory -Force $bin | Out-Null
$fw = "$env:windir\Microsoft.NET\Framework64\v4.0.30319"
$csc = Join-Path $fw 'csc.exe'

# ---- icon: purple circle with a white dot, PNG-compressed multi-size .ico ----
Add-Type -AssemblyName System.Drawing
$ico = Join-Path $bin 'app.ico'
$sizes = 16, 32, 48, 256; $pngs = @()
foreach ($s in $sizes) {
  $bmp = New-Object Drawing.Bitmap $s, $s; $g = [Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode = 'AntiAlias'
  $g.FillEllipse((New-Object Drawing.SolidBrush ([Drawing.ColorTranslator]::FromHtml('#5865F2'))), [float]($s * 0.03), [float]($s * 0.03), [float]($s * 0.94), [float]($s * 0.94))
  $d = $s * 0.32; $g.FillEllipse((New-Object Drawing.SolidBrush ([Drawing.Color]::White)), [float](($s - $d) / 2), [float](($s - $d) / 2), [float]$d, [float]$d); $g.Dispose()
  $ms = New-Object IO.MemoryStream; $bmp.Save($ms, [Drawing.Imaging.ImageFormat]::Png); $pngs += , $ms.ToArray(); $bmp.Dispose() }
$fs = [IO.File]::Create($ico); $w = New-Object IO.BinaryWriter $fs
$w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$sizes.Count)
$off = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) { $s = $sizes[$i]; $w.Write([byte]($s % 256)); $w.Write([byte]($s % 256)); $w.Write([byte]0); $w.Write([byte]0); $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]$pngs[$i].Length); $w.Write([uint32]$off); $off += $pngs[$i].Length }
foreach ($p in $pngs) { $w.Write($p) }; $w.Close()

# ---- assembly info (version shows in the file properties) ----
$v = if ($Version) { $Version } else { (Get-Content (Join-Path (Split-Path $here -Parent) 'src\setup\version.txt') -Raw).Trim() }
$ai = Join-Path $bin 'AssemblyInfo.cs'
Set-Content $ai -Encoding UTF8 -Value @"
[assembly: System.Reflection.AssemblyTitle("Discord WARP")]
[assembly: System.Reflection.AssemblyProduct("Discord WARP")]
[assembly: System.Reflection.AssemblyDescription("Discord only through Cloudflare WARP")]
[assembly: System.Reflection.AssemblyCompany("discord-warp-setup")]
[assembly: System.Reflection.AssemblyCopyright("MIT License")]
[assembly: System.Reflection.AssemblyVersion("$v.0")]
[assembly: System.Reflection.AssemblyFileVersion("$v.0")]
"@

$refs = @("$fw\WPF\PresentationFramework.dll", "$fw\WPF\PresentationCore.dll", "$fw\WPF\WindowsBase.dll", "$fw\System.Xaml.dll",
          "$fw\System.Windows.Forms.dll", "$fw\System.Drawing.dll", "$fw\System.ServiceProcess.dll", "$fw\System.Web.Extensions.dll",
          "$fw\System.Core.dll", "$fw\System.dll") | ForEach-Object { "/r:`"$_`"" }
$src = @(Get-ChildItem $here -Filter *.cs | ForEach-Object { "`"$($_.FullName)`"" }) + "`"$ai`""
$out = Join-Path $bin 'DiscordWARP.exe'
$args = @('/nologo', '/target:winexe', '/optimize+', '/codepage:65001', "/out:`"$out`"", "/win32icon:`"$ico`"") + $refs + $src
$p = Start-Process $csc -ArgumentList $args -NoNewWindow -Wait -PassThru -RedirectStandardOutput (Join-Path $bin 'csc.log')
Get-Content (Join-Path $bin 'csc.log') | Where-Object { $_ -match 'error|warning' } | Select-Object -First 40
if ($p.ExitCode -ne 0) { throw "csc failed (exit $($p.ExitCode))" }
"built $out ($([math]::Round((Get-Item $out).Length / 1KB)) KB) version $v"
