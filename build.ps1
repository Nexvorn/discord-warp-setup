<#
.SYNOPSIS
  Build the one-click package  dist\DiscordWARP-Setup\  and  dist\DiscordWARP-Setup.zip  from src\.
.DESCRIPTION
  - Copies src\ (cmd files, Arabic guide, setup scripts, profile template, helper scripts).
  - Downloads the official binaries once into cache\ (Clash Verge Rev x64 setup, wgcf) and checks their SHA-256
    against the GitHub asset digests pinned in src\setup\DiscordWarpLib.ps1.
  - Re-encodes setup\*.ps1 as UTF-8 WITH BOM (Windows PowerShell 5.1 needs it for the Arabic UI text) and parse-checks every script.
  - Adds LICENSE and THIRD_PARTY_NOTICES.md, writes SHA256SUMS.txt, zips.
  The package contains NO secrets: every PC creates its own free WARP registration at install time.
#>
param([switch]$NoZip)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\src\setup\DiscordWarpLib.ps1"
$src = Join-Path $PSScriptRoot 'src'
$dist = Join-Path $PSScriptRoot 'dist\DiscordWARP-Setup'
$cache = Join-Path $PSScriptRoot 'cache'
if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }
New-Item -ItemType Directory -Force $dist, "$dist\bin", $cache | Out-Null
Copy-Item "$src\*" $dist -Recurse -Force
Copy-Item "$PSScriptRoot\LICENSE", "$PSScriptRoot\THIRD_PARTY_NOTICES.md" $dist -Force
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
foreach ($name in $script:DW_Bins.Keys) {
  $c = Join-Path $cache $name; $want = $script:DW_Bins[$name].sha
  if (-not (Test-Path $c) -or (Get-FileHash $c -Algorithm SHA256).Hash.ToLower() -ne $want) {
    Write-Host "downloading $name"; Invoke-WebRequest -Uri $script:DW_Bins[$name].url -OutFile $c -UseBasicParsing }
  $h = (Get-FileHash $c -Algorithm SHA256).Hash.ToLower()
  if ($h -ne $want) { throw "SHA-256 mismatch for $name : $h" }
  Copy-Item $c "$dist\bin\$name" -Force
  Write-Host "ok  $name  sha256 $h"
}
foreach ($f in Get-ChildItem "$dist\setup" -Filter *.ps1 -File) {
  $t = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
  [IO.File]::WriteAllText($f.FullName, $t, (New-Object Text.UTF8Encoding($true)))
}
foreach ($f in Get-ChildItem $dist -Recurse -Filter *.ps1 -File) {
  $err = $null; [void][Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$err)
  if ($err) { throw "parse error in $($f.Name): $($err[0].Message) line $($err[0].Extent.StartLineNumber)" }
}
$sums = Get-ChildItem $dist -Recurse -File | Where-Object Name -ne 'SHA256SUMS.txt' | Sort-Object FullName | ForEach-Object {
  "$((Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower())  $($_.FullName.Substring($dist.Length + 1))" }
[IO.File]::WriteAllText("$dist\SHA256SUMS.txt", (($sums -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding($false)))
$ver = (Get-Content "$src\setup\version.txt" -Raw).Trim()
if (-not $NoZip) {
  $zip = Join-Path $PSScriptRoot 'dist\DiscordWARP-Setup.zip'
  if (Test-Path $zip) { Remove-Item $zip -Force }
  Compress-Archive -Path $dist -DestinationPath $zip
  Write-Host "zip: $zip ($([math]::Round((Get-Item $zip).Length / 1MB, 1)) MB) sha256 $((Get-FileHash $zip).Hash.ToLower())"
}
Write-Host "package v$ver : $dist"
