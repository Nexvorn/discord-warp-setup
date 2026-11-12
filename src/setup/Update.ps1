# DiscordWARP-Setup updater: checks GitHub Releases for a newer version, ASKS the user, downloads the release zip,
# verifies its SHA-256 against the digest GitHub publishes for the asset, and runs the new installer
# (the installer is re-runnable: it updates settings/scripts and keeps this PC's WARP account).
# Never updates silently. Works only while the repository is public.
# NOTE: contains Arabic UI text - saved as UTF-8 WITH BOM by build.ps1.
param([string]$Repo = 'Nexvorn/discord-warp-setup', [switch]$CheckOnly, [switch]$Yes)   # -Yes: the app already asked the user
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
$dw = Join-Path $env:USERPROFILE '.discord-warp'
if (Test-Path (Join-Path $PSScriptRoot 'Dialog.ps1')) { . (Join-Path $PSScriptRoot 'Dialog.ps1') }
function Say([string]$t, [string]$icon = 'Information', [string]$b = 'OK', [string[]]$labels = $null) {
  $__k = @{ Information = 'info'; Question = 'question'; Warning = 'warning'; Error = 'error'; Success = 'success' }[$icon]; if (-not $__k) { $__k = 'info' }
  if (Get-Command Show-DwDialog -ErrorAction SilentlyContinue) { return (Show-DwDialog -Text $t -Buttons $b -Kind $__k -Owner $null -Labels $labels) }   # styled dialog (Dialog.ps1)
  # RLM at both ends of every line: bullets/brackets/Latin words stay in the right order in RTL message boxes
  $t = (($t -split "`n") | ForEach-Object { [string][char]0x200F + $_ + [string][char]0x200F }) -join "`n"
  [string][System.Windows.Forms.MessageBox]::Show($t, 'Discord WARP', $b, $icon, [System.Windows.Forms.MessageBoxDefaultButton]::Button1, [System.Windows.Forms.MessageBoxOptions]'RtlReading, RightAlign') }

$cur = '0.0.0'
$vf = Join-Path $dw 'installed-version.txt'
if (Test-Path $vf) { $cur = (Get-Content $vf -Raw).Trim() }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try {
  $hdr = @{ 'User-Agent' = 'discord-warp-setup-updater'; 'Accept' = 'application/vnd.github+json' }
  if ($env:DWARP_GH_TOKEN) { $hdr['Authorization'] = "Bearer $env:DWARP_GH_TOKEN" }   # testing a private repo only; never stored
  $rel = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest" -TimeoutSec 20 -Headers $hdr
} catch {
  Say "تعذّر فحص التحديثات.`nتأكد من الإنترنت، أو أن صفحة الأداة على GitHub متاحة (عامة).`n`n$($_.Exception.Message)" 'Warning' | Out-Null; exit 1
}
$latest = ($rel.tag_name -replace '^v', '').Trim()
if ([version]$latest -le [version]$cur) { Say "لديك آخر نسخة ($cur). لا يوجد تحديث." | Out-Null; exit 0 }
if ($CheckOnly) { "update available: $cur -> $latest"; exit 0 }

$notes = ((([string]$rel.body) -split "\r?\n") | Where-Object { $_ -match '[\u0600-\u06FF]' }) -join "`n"   # Arabic lines of the release notes only (English text breaks in RTL)
  if ($notes.Length -gt 400) { $notes = $notes.Substring(0, 400) + ' ...' }
if (-not $Yes) {
  $a = Say ("توجد نسخة جديدة: $latest (نسختك: $cur)`n`n$notes`n`nهل تريد التحديث الآن؟ سيطلب Windows صلاحية المسؤول.") 'Question' 'YesNo'
  if ($a -ne 'Yes') { exit 0 } }

$asset = $rel.assets | Where-Object { $_.name -eq 'DiscordWARP-Setup.zip' } | Select-Object -First 1
if (-not $asset -or -not $asset.digest -or $asset.digest -notmatch '^sha256:([0-9a-f]{64})$') {
  Say 'ملف التحديث غير موجود أو بدون بصمة SHA-256، لم يتم التحديث.' 'Error' | Out-Null; exit 1 }
$want = $Matches[1]
$tmp = Join-Path $env:TEMP "discord-warp-update-$latest"
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
New-Item -ItemType Directory -Force $tmp | Out-Null
$zip = Join-Path $tmp 'DiscordWARP-Setup.zip'
$ProgressPreference = 'SilentlyContinue'
if ($env:DWARP_GH_TOKEN) { Invoke-WebRequest $asset.url -OutFile $zip -UseBasicParsing -Headers @{ 'User-Agent' = 'discord-warp-setup-updater'; 'Accept' = 'application/octet-stream'; 'Authorization' = "Bearer $env:DWARP_GH_TOKEN" } }
else { Invoke-WebRequest $asset.browser_download_url -OutFile $zip -UseBasicParsing -Headers @{ 'User-Agent' = 'discord-warp-setup-updater' } }
$got = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
if ($got -ne $want) { Remove-Item $tmp -Recurse -Force; Say 'بصمة الملف المحمّل لا تطابق البصمة المنشورة. تم إلغاء التحديث.' 'Error' | Out-Null; exit 1 }
Expand-Archive $zip -DestinationPath $tmp -Force
$appPs = Get-ChildItem $tmp -Recurse -Filter 'App.ps1' | Where-Object { Test-Path (Join-Path $_.DirectoryName 'Install.ps1') } | Select-Object -First 1
if ($appPs) {   # v1.2+: the new package's app installs with a progress view (no second question)
  Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -STA -ExecutionPolicy Bypass -File `"$($appPs.FullName)`" -AutoInstall"
} else {
  $cmd = Get-ChildItem $tmp -Recurse -Filter 'Install-DiscordWARP.cmd' | Select-Object -First 1
  if (-not $cmd) { Say 'ملف التثبيت غير موجود داخل التحديث.' 'Error' | Out-Null; exit 1 }
  Start-Process -FilePath $cmd.FullName -WorkingDirectory $cmd.DirectoryName }
