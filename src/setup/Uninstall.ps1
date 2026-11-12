# DiscordWARP-Setup uninstaller (self-contained; started from the package, the Start menu or Windows "Apps").
# Modes:  Full     = remove EVERYTHING: our settings, Clash Verge (service + program + all its data), the WARP account
#                    folder %USERPROFILE%\.discord-warp (logs, backups), Start menu + Apps entries.
#         Settings = remove our settings only (task, autostart, NRPT, TUN off, shortcuts); keep Clash Verge and the
#                    WARP account (a later re-install reuses it).
# -DryRun lists what would be removed and changes nothing (no admin needed).
# Asks for admin itself and runs from a TEMP copy so it can delete its own folder.
# NOTE: contains Arabic UI text - saved as UTF-8 WITH BOM by build.ps1.
param([ValidateSet('', 'Full', 'Settings')][string]$Mode = '', [switch]$DryRun, [switch]$Relaunched)
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Windows.Forms
$dw     = Join-Path $env:USERPROFILE '.discord-warp'
$cvHome = Join-Path $env:ProgramFiles 'Clash Verge'
$cvData = @((Join-Path $env:APPDATA 'io.github.clash-verge-rev.clash-verge-rev'), (Join-Path $env:LOCALAPPDATA 'io.github.clash-verge-rev.clash-verge-rev'),
            (Join-Path $env:ProgramData 'clash-verge-service'), $cvHome)
$startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Discord WARP'
$appsKey   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\DiscordWARP'
if (Test-Path (Join-Path $PSScriptRoot 'Dialog.ps1')) { . (Join-Path $PSScriptRoot 'Dialog.ps1') }
function Say([string]$t, [string]$icon = 'Information', [string]$b = 'OK', [string[]]$labels = $null) {
  if ($DryRun) { return 'OK' }
  $__k = @{ Information = 'info'; Question = 'question'; Warning = 'warning'; Error = 'error'; Success = 'success' }[$icon]; if (-not $__k) { $__k = 'info' }
  if (Get-Command Show-DwDialog -ErrorAction SilentlyContinue) { return (Show-DwDialog -Text $t -Buttons $b -Kind $__k -Owner $null -Labels $labels) }   # styled dialog (Dialog.ps1)
  # RLM at both ends of every line: bullets/brackets/Latin words stay in the right order in RTL message boxes
  $t = (($t -split "`n") | ForEach-Object { [string][char]0x200F + $_ + [string][char]0x200F }) -join "`n"
  if ($DryRun) { return 'OK' }
  [string][System.Windows.Forms.MessageBox]::Show($t, 'Discord WARP', $b, $icon, [System.Windows.Forms.MessageBoxDefaultButton]::Button2, [System.Windows.Forms.MessageBoxOptions]'RtlReading, RightAlign') }
$logFile = Join-Path $env:TEMP "discord-warp-uninstall-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
function Log([string]$m) { $l = "$(Get-Date -Format 'HH:mm:ss') $m"; Write-Host $l; Add-Content -LiteralPath $logFile -Value $l -Encoding UTF8 }
function Act([string]$what, [scriptblock]$do) { if ($DryRun) { Log "[dry-run] would $what" } else { try { & $do; Log "done: $what" } catch { Log "FAILED: $what - $($_.Exception.Message)" } } }

# 1. ask (before elevation, so the question appears once)
if (-not $Mode) {
  if ($DryRun) { $Mode = 'Full' } else {
    $a = Say ("إزالة ديسكورد عبر WARP من هذا الكمبيوتر:`n`n" +
      "نعم (Yes) = حذف نهائي لكل شيء: الإعدادات + برنامج Clash Verge وكل ملفاته + حساب WARP والسجلات.`n" +
      "لا (No) = حذف الإعدادات فقط، مع إبقاء Clash Verge وحساب WARP (لإعادة التثبيت لاحقاً).`n" +
      "إلغاء (Cancel) = لا تغيّر شيئاً.`n`n" +
      "تنبيه: إذا كنت تستخدم Clash Verge لأشياء أخرى، اختر (لا).`nبعد الإزالة يعود ديسكورد محجوباً كما كان.") 'Warning' 'YesNoCancel'
    if ($a -eq 'Cancel') { exit 2 }
    $Mode = if ($a -eq 'Yes') { 'Full' } else { 'Settings' }
  }
}

# 2. elevate + run from a TEMP copy (the Full mode deletes the folder this script may live in)
$isAdmin = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $DryRun -and (-not $isAdmin -or -not $Relaunched)) {
  $cdir = Join-Path $env:TEMP 'discord-warp-uninstall'; New-Item -ItemType Directory -Force $cdir | Out-Null
  $copy = Join-Path $cdir 'Uninstall.ps1'
  Copy-Item -LiteralPath $PSCommandPath $copy -Force
  $dlg = Join-Path $PSScriptRoot 'Dialog.ps1'; if (Test-Path $dlg) { Copy-Item $dlg $cdir -Force }
  Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList "-NoProfile -STA -ExecutionPolicy Bypass -File `"$copy`" -Mode $Mode -Relaunched"
  exit 0
}
Log "=== DiscordWARP uninstall, mode=$Mode, dry-run=$DryRun, user=$env:USERNAME ==="

# 3. our settings (both modes)
Act 'remove scheduled task DiscordWARP-SelfHeal' { Unregister-ScheduledTask -TaskName 'DiscordWARP-SelfHeal' -Confirm:$false -ErrorAction Stop }
Act 'remove autostart value HKCU Run "Clash Verge"' { Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'Clash Verge' -ErrorAction Stop }
Act "remove NRPT rules DiscordWARP ($(@(Get-DnsClientNrptRule | Where-Object Comment -eq 'DiscordWARP').Count))" {
  Get-DnsClientNrptRule | Where-Object Comment -eq 'DiscordWARP' | ForEach-Object { Remove-DnsClientNrptRule -Name $_.Name -Force }; Clear-DnsClientCache }
Act "remove Start menu folder $startMenu" { if (Test-Path $startMenu) { Remove-Item $startMenu -Recurse -Force } }
Act "remove Apps entry $appsKey" { if (Test-Path $appsKey) { Remove-Item $appsKey -Force } }
Act 'stop the Discord WARP app (tray)' { Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like "*$dw\App.ps1*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force } }
Act 'remove autostart value HKCU Run "Discord WARP Tray"' { Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'Discord WARP Tray' -ErrorAction Stop }
$desk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Discord WARP.lnk'
Act "remove desktop shortcut $desk" { if (Test-Path $desk) { Remove-Item $desk -Force } }
Act 'stop Clash Verge GUI' { Get-Process clash-verge -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep 2 }

if ($Mode -eq 'Settings') {
  $vy = Join-Path $cvData[0] 'verge.yaml'
  Act 'Clash Verge: TUN + autostart off (verge.yaml)' {
    if (Test-Path $vy) {
      $t = [IO.File]::ReadAllText($vy)
      foreach ($k in 'enable_tun_mode', 'enable_auto_launch', 'enable_silent_start') { $t = [regex]::Replace($t, "(?m)^${k}:.*$", "${k}: false") }
      [IO.File]::WriteAllText($vy, $t, (New-Object Text.UTF8Encoding($false))) } }
  Act 'undo a pause (service back to Automatic, remove paused flag)' {
    Set-Service clash_verge_service -StartupType Automatic -ErrorAction SilentlyContinue; Remove-Item (Join-Path $dw 'paused.flag') -Force -ErrorAction SilentlyContinue }
} else {
  # 4. Full: Clash Verge service + program + data, then our folder
  $su = Join-Path $cvHome 'resources\clash-verge-service-uninstall.exe'
  Act 'uninstall service clash_verge_service' { if (Test-Path $su) { Start-Process $su -Wait } elseif (Get-Service clash_verge_service -ErrorAction SilentlyContinue) { Stop-Service clash_verge_service -Force; & sc.exe delete clash_verge_service | Out-Null } }
  Act 'stop mihomo core' { Get-Process verge-mihomo, verge-mihomo-alpha -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep 2 }
  $un = Join-Path $cvHome 'uninstall.exe'
  Act 'uninstall Clash Verge program (silent)' { if (Test-Path $un) { Start-Process $un -ArgumentList '/S' -Wait; Start-Sleep 3 } }
  foreach ($d in $cvData) { $dd = $d; Act "delete folder $dd" { if (Test-Path $dd) { Remove-Item $dd -Recurse -Force } } }
  Act "delete folder $dw (WARP account, logs, backups)" { if (Test-Path $dw) { Remove-Item $dw -Recurse -Force } }
}
Log '=== done ==='
if (-not $DryRun) {
  if ($Mode -eq 'Full') { Say "تم الحذف النهائي لكل شيء.`nسجل العملية: $logFile" | Out-Null }
  else { Say "تمت إزالة الإعدادات.`nبقي برنامج Clash Verge وحساب WARP في:`n$dw`nسجل العملية: $logFile" | Out-Null }
}
