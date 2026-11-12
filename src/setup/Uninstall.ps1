# DiscordWARP-Setup v1.3 uninstaller (self-contained; started from the app, the Start menu or Windows "Apps").
# Modes:  Full     = remove EVERYTHING: engine task + engine, NRPT, %ProgramFiles%\DiscordWARP, %ProgramData%\DiscordWARP
#                    (WARP account, logs), app data, shortcuts, Apps entry; plus v1.x leftovers (Clash Verge, .discord-warp).
#         Settings = remove the setup but keep the WARP account (%ProgramData%\DiscordWARP\account) for a later re-install.
# -DryRun lists what would be removed and changes nothing (no admin needed).
# Asks for admin itself and runs from a TEMP copy so it can delete its own folder.
# NOTE: contains Arabic UI text - saved as UTF-8 WITH BOM by build.ps1.
param([ValidateSet('', 'Full', 'Settings')][string]$Mode = '', [switch]$DryRun, [switch]$Relaunched)
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Windows.Forms
$prog = Join-Path $env:ProgramFiles 'DiscordWARP'; $data = Join-Path $env:ProgramData 'DiscordWARP'; $userDir = Join-Path $env:LOCALAPPDATA 'DiscordWARP'
$oldDw = Join-Path $env:USERPROFILE '.discord-warp'
$cvHome = Join-Path $env:ProgramFiles 'Clash Verge'
$cvData = @((Join-Path $env:APPDATA 'io.github.clash-verge-rev.clash-verge-rev'), (Join-Path $env:LOCALAPPDATA 'io.github.clash-verge-rev.clash-verge-rev'), (Join-Path $env:ProgramData 'clash-verge-service'), $cvHome)
$startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Discord WARP'
$appsKey   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\DiscordWARP'
if (Test-Path (Join-Path $PSScriptRoot 'Dialog.ps1')) { . (Join-Path $PSScriptRoot 'Dialog.ps1') }
function Say([string]$t, [string]$icon = 'Information', [string]$b = 'OK', [string[]]$labels = $null) {
  if ($DryRun) { return 'OK' }
  $k = @{ Information = 'info'; Question = 'question'; Warning = 'warning'; Error = 'error'; Success = 'success' }[$icon]; if (-not $k) { $k = 'info' }
  if (Get-Command Show-DwDialog -ErrorAction SilentlyContinue) { return (Show-DwDialog -Text $t -Buttons $b -Kind $k -Owner $null -Labels $labels) }
  [string][System.Windows.Forms.MessageBox]::Show($t, 'Discord WARP', $b, $icon) }
$logFile = Join-Path $env:TEMP "discord-warp-uninstall-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
function Log([string]$m) { $l = "$(Get-Date -Format 'HH:mm:ss') $m"; Write-Host $l; Add-Content -LiteralPath $logFile -Value $l -Encoding UTF8 }
function Act([string]$what, [scriptblock]$do) { if ($DryRun) { Log "[dry-run] would $what" } else { try { & $do; Log "done: $what" } catch { Log "FAILED: $what - $($_.Exception.Message)" } } }

# 1. ask (before elevation, so the question appears once)
if (-not $Mode) {
  if ($DryRun) { $Mode = 'Full' } else {
    $a = Say ("إزالة Discord WARP من هذا الكمبيوتر:`n`nحذف كل شيء: البرنامج ومحرك الاتصال وحساب WARP والسجلات.`nالإعدادات فقط: يبقى حساب WARP (لإعادة التثبيت لاحقاً).`n`nبعد الإزالة يعود ديسكورد محجوباً كما كان.") 'Warning' 'YesNoCancel' @('حذف كل شيء', 'الإعدادات فقط', 'إلغاء')
    if ($a -eq 'Cancel') { exit 2 }
    $Mode = if ($a -eq 'Yes') { 'Full' } else { 'Settings' } } }

# 2. elevate + run from a TEMP copy (Full deletes the folder this script lives in)
$isAdmin = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $DryRun -and (-not $isAdmin -or -not $Relaunched)) {
  $cdir = Join-Path $env:TEMP 'discord-warp-uninstall'; New-Item -ItemType Directory -Force $cdir | Out-Null
  $copy = Join-Path $cdir 'Uninstall.ps1'; Copy-Item -LiteralPath $PSCommandPath $copy -Force
  $dlg = Join-Path $PSScriptRoot 'Dialog.ps1'; if (Test-Path $dlg) { Copy-Item $dlg $cdir -Force }
  Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList "-NoProfile -STA -ExecutionPolicy Bypass -File `"$copy`" -Mode $Mode -Relaunched"
  exit 0 }
Log "=== DiscordWARP uninstall, mode=$Mode, dry-run=$DryRun, user=$env:USERNAME ==="

# 3. the setup (both modes)
Act 'stop the Discord WARP app (tray)' { Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match '\\(\.discord-warp|DiscordWARP\\scripts)\\App\.ps1' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force } }
Act 'stop + remove engine task DiscordWARP-Engine' { Stop-ScheduledTask -TaskName 'DiscordWARP-Engine' -ErrorAction SilentlyContinue; Unregister-ScheduledTask -TaskName 'DiscordWARP-Engine' -Confirm:$false -ErrorAction Stop }
Act 'stop the engine (mihomo)' { Get-Process mihomo -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep 2 }
Act "remove NRPT rules DiscordWARP ($(@(Get-DnsClientNrptRule | Where-Object Comment -eq 'DiscordWARP').Count))" {
  Get-DnsClientNrptRule | Where-Object Comment -eq 'DiscordWARP' | ForEach-Object { Remove-DnsClientNrptRule -Name $_.Name -Force }; Clear-DnsClientCache }
Act 'remove v1.x task DiscordWARP-SelfHeal (if any)' { Unregister-ScheduledTask -TaskName 'DiscordWARP-SelfHeal' -Confirm:$false -ErrorAction SilentlyContinue }
Act 'remove autostart values (Discord WARP Tray, Clash Verge)' { foreach ($n in 'Discord WARP Tray', 'Clash Verge') { Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name $n -ErrorAction SilentlyContinue } }
Act "remove Start menu folder $startMenu" { if (Test-Path $startMenu) { Remove-Item $startMenu -Recurse -Force } }
$desk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Discord WARP.lnk'
Act "remove desktop shortcut $desk" { if (Test-Path $desk) { Remove-Item $desk -Force } }
Act "remove Apps entry $appsKey" { if (Test-Path $appsKey) { Remove-Item $appsKey -Force } }
Act "delete program folder $prog" { if (Test-Path $prog) { Remove-Item $prog -Recurse -Force } }
Act "delete app data $userDir" { if (Test-Path $userDir) { Remove-Item $userDir -Recurse -Force } }

if ($Mode -eq 'Settings') {
  Act "delete $data except the WARP account" { if (Test-Path $data) { Get-ChildItem $data -Force | Where-Object Name -ne 'account' | Remove-Item -Recurse -Force } }
} else {
  Act "delete $data (WARP account, engine config, logs)" { if (Test-Path $data) { Remove-Item $data -Recurse -Force } }
  # v1.x leftovers: Clash Verge (installed by v1.0-1.2) and the old .discord-warp folder
  $su = Join-Path $cvHome 'resources\clash-verge-service-uninstall.exe'
  Act 'remove Clash Verge service (v1.x leftover)' { if (Test-Path $su) { Start-Process $su -Wait } elseif (Get-Service clash_verge_service -ErrorAction SilentlyContinue) { Stop-Service clash_verge_service -Force; & sc.exe delete clash_verge_service | Out-Null } }
  Act 'stop Clash Verge processes' { Get-Process clash-verge, verge-mihomo, verge-mihomo-alpha -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep 2 }
  $un = Join-Path $cvHome 'uninstall.exe'
  Act 'uninstall Clash Verge program (silent)' { if (Test-Path $un) { Start-Process $un -ArgumentList '/S' -Wait; Start-Sleep 3 } }
  foreach ($d in $cvData) { $dd = $d; Act "delete folder $dd" { if (Test-Path $dd) { Remove-Item $dd -Recurse -Force } } }
  Act "delete folder $oldDw (v1.x logs, backups, old WARP account copy)" { if (Test-Path $oldDw) { Remove-Item $oldDw -Recurse -Force } }
}
Log '=== done ==='
if (-not $DryRun) {
  if ($Mode -eq 'Full') { Say "تم الحذف النهائي لكل شيء.`nسجل العملية: $logFile" 'Success' | Out-Null }
  else { Say "تمت إزالة الإعداد.`nبقي حساب WARP فقط في:`n$data\account`nسجل العملية: $logFile" 'Success' | Out-Null } }
