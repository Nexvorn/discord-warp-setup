# DiscordWARP-Setup - remove the Discord-via-WARP setup from this PC (run via Uninstall-DiscordWARP.cmd, admin).
# Removes: NRPT rules, self-heal task, autostart, TUN; optionally the Clash Verge program + service.
# Keeps %USERPROFILE%\.discord-warp (contains this PC's WARP account + logs) - delete it by hand if not needed.
# NOTE: contains Arabic UI text - saved as UTF-8 WITH BOM by build.ps1.
$ErrorActionPreference = 'Continue'
. "$PSScriptRoot\DiscordWarpLib.ps1"
Add-Type -AssemblyName System.Windows.Forms
$dw = Join-Path $env:USERPROFILE '.discord-warp'; New-Item -ItemType Directory -Force $dw | Out-Null
$logFile = Join-Path $dw "uninstall-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
$cvDir = Join-Path $env:APPDATA 'io.github.clash-verge-rev.clash-verge-rev'
$cvHome = Join-Path $env:ProgramFiles 'Clash Verge'
function Log([string]$m) { $l = "$(Get-Date -Format 'HH:mm:ss') $m"; Write-Host $l; Add-Content -LiteralPath $logFile -Value $l -Encoding UTF8 }
function Say([string]$t, [string]$icon = 'Information', [string]$b = 'OK') { [string][System.Windows.Forms.MessageBox]::Show($t, 'Discord WARP', $b, $icon, [System.Windows.Forms.MessageBoxDefaultButton]::Button2, [System.Windows.Forms.MessageBoxOptions]'RtlReading, RightAlign') }

$a = Say ("إزالة إعداد ديسكورد عبر WARP من هذا الكمبيوتر.`n`n" +
  "نعم (Yes): إزالة الإعداد وحذف برنامج Clash Verge أيضاً.`n" +
  "لا (No): إزالة الإعداد فقط مع إبقاء البرنامج.`n" +
  "إلغاء (Cancel): عدم تغيير أي شيء.`n`n" +
  "بعد الإزالة سيعود ديسكورد محجوباً كما كان.") 'Warning' 'YesNoCancel'
if ($a -eq 'Cancel') { Log 'cancelled'; exit 2 }

Unregister-ScheduledTask -TaskName 'DiscordWARP-SelfHeal' -Confirm:$false -ErrorAction SilentlyContinue; Log 'task DiscordWARP-SelfHeal removed'
Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'Clash Verge' -ErrorAction SilentlyContinue; Log 'autostart value removed'
Get-DnsClientNrptRule | Where-Object Comment -eq 'DiscordWARP' | ForEach-Object { Remove-DnsClientNrptRule -Name $_.Name -Force }
Clear-DnsClientCache; Log 'NRPT DiscordWARP rules removed'
Remove-Item (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Discord WARP') -Recurse -Force -ErrorAction SilentlyContinue; Log 'Start menu shortcuts removed'
Get-Process clash-verge -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep 2
$vy = Join-Path $cvDir 'verge.yaml'
if (Test-Path $vy) { Write-Utf8NoBom $vy (Set-YamlTopKeys (Read-TextNoBom $vy) ([ordered]@{ enable_tun_mode = 'false'; enable_auto_launch = 'false'; enable_silent_start = 'false' })); Log 'Clash Verge: TUN and autostart switched off' }
if ($a -eq 'Yes') {
  $su = Join-Path $cvHome 'resources\clash-verge-service-uninstall.exe'
  if (Test-Path $su) { Start-Process $su -Wait; Log 'clash_verge_service uninstalled' }
  Get-Process verge-mihomo -ErrorAction SilentlyContinue | Stop-Process -Force
  $un = Join-Path $cvHome 'uninstall.exe'
  if (Test-Path $un) { Start-Process $un -ArgumentList '/S' -Wait; Log 'Clash Verge uninstalled' }
}
Log 'done'
Say ("تمت الإزالة.`n`nملف حساب WARP الخاص بهذا الكمبيوتر بقي في:`n$dw`nيمكنك حذفه يدوياً إذا لا تحتاجه.") | Out-Null
