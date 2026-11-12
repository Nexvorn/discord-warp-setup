# DiscordWARP-Setup v1.3 - installer: Discord (only) via Cloudflare WARP on this PC, without Clash Verge.
# Installs: %ProgramFiles%\DiscordWARP (official mihomo engine + scripts + app), %ProgramData%\DiscordWARP (engine config,
# WARP account - SYSTEM/Administrators only), scheduled task "DiscordWARP-Engine" (SYSTEM, at startup) running Engine.ps1,
# NRPT for Discord names, app shortcuts, tray app at logon, Apps entry.
# Migrates a v1.0-1.2 setup (Clash Verge): reuses its WARP account (no new account), stops/disables Clash Verge's engine,
# optionally removes Clash Verge (-RemoveClashVerge).  Safe to re-run.  Never prints secrets.
# NOTE: contains Arabic UI text - saved as UTF-8 WITH BOM by build.ps1.
param([switch]$NoPopups, [string]$ProgressLog = '', [switch]$RemoveClashVerge)
# NOTE: PowerShell variable names are case-insensitive - the progress parameter must not be called LogFile.
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\DiscordWarpLib.ps1"
Add-Type -AssemblyName System.Windows.Forms

$pkg     = Split-Path $PSScriptRoot -Parent
$stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$prog    = Join-Path $env:ProgramFiles 'DiscordWARP'; $scripts = Join-Path $prog 'scripts'; $engineExe = Join-Path $prog 'mihomo.exe'
$data    = Join-Path $env:ProgramData 'DiscordWARP'; $acctDir = Join-Path $data 'account'; $engDir = Join-Path $data 'engine'
$cmdDir  = Join-Path $data 'cmd'; $logDir = Join-Path $data 'logs'
$userDir = Join-Path $env:LOCALAPPDATA 'DiscordWARP'
$oldDw   = Join-Path $env:USERPROFILE '.discord-warp'                       # v1.0-1.2 folder
$cvDir   = Join-Path $env:APPDATA 'io.github.clash-verge-rev.clash-verge-rev'; $cvHome = Join-Path $env:ProgramFiles 'Clash Verge'
New-Item -ItemType Directory -Force $logDir, $userDir | Out-Null
$logFile = Join-Path $logDir "install-$stamp.log"
$appLog = $ProgressLog   # extra copy of every log line for the app's progress view

function Log([string]$m) { $l = "$(Get-Date -Format 'HH:mm:ss') $m"; Write-Host $l; Add-Content -LiteralPath $logFile -Value $l -Encoding UTF8
  if ($appLog) { Add-Content -LiteralPath $appLog -Value $l -Encoding UTF8 } }
if (Test-Path (Join-Path $PSScriptRoot 'Dialog.ps1')) { . (Join-Path $PSScriptRoot 'Dialog.ps1') }
function Say([string]$text, [string]$icon = 'Information', [string]$buttons = 'OK') {
  if ($NoPopups) { Log "[popup] $icon"; return $(if ($buttons -eq 'YesNo') { 'Yes' } else { 'OK' }) }   # the app asked the user beforehand
  $k = @{ Information = 'info'; Question = 'question'; Warning = 'warning'; Error = 'error'; Success = 'success' }[$icon]; if (-not $k) { $k = 'info' }
  if (Get-Command Show-DwDialog -ErrorAction SilentlyContinue) { return (Show-DwDialog -Text $text -Buttons $buttons -Kind $k) }
  return [string][System.Windows.Forms.MessageBox]::Show($text, 'Discord WARP', $buttons, $icon) }
function Fail([string]$ar, [string]$en) { Log "FAILED: $en"; Say ("$ar`n`nلم يكتمل الإعداد. التفاصيل في الملف:`n$logFile") 'Error' | Out-Null; exit 1 }
function Invoke-Native([string]$exe, [string[]]$argList, [string]$outFile, [string]$cwd) {
  $p = Start-Process -FilePath $exe -ArgumentList $argList -Wait -PassThru -NoNewWindow -WorkingDirectory $cwd -RedirectStandardOutput "$outFile.out" -RedirectStandardError "$outFile.err"
  Get-Content "$outFile.out", "$outFile.err" -ErrorAction SilentlyContinue | Add-Content -LiteralPath $outFile -Encoding UTF8
  Remove-Item "$outFile.out", "$outFile.err" -ErrorAction SilentlyContinue; return $p.ExitCode }
function Set-PrivateAcl([string]$dir) { & icacls.exe $dir /inheritance:r /grant:r 'SYSTEM:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null }   # SYSTEM + Administrators only

Log "=== DiscordWARP-Setup v$((Get-Content (Join-Path $PSScriptRoot 'version.txt') -Raw).Trim()) started (package: $pkg) ==="

# ---------- 0. preflight ----------
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { Fail 'يجب تشغيل التثبيت بصلاحيات المسؤول.' 'not elevated' }
$console = (Get-CimInstance Win32_ComputerSystem).UserName
Log "user: $($id.Name) | console user: $console | OS: $((Get-CimInstance Win32_OperatingSystem).Caption) $([Environment]::OSVersion.Version)"
if ($console -and $console -ne $id.Name) { Fail "التثبيت يعمل باسم مستخدم مختلف ($($id.Name)) عن المستخدم الحالي ($console).`nسجّل الدخول بحساب له صلاحية المسؤول ثم حاول مرة أخرى." 'elevated as a different user' }
if (-not [Environment]::Is64BitOperatingSystem -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64') { Fail 'هذه الأداة لأجهزة Windows بنظام 64-bit (x64) فقط.' 'unsupported architecture' }
Get-ChildItem $pkg -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
foreach ($name in $script:DW_Bins.Keys) {
  $p = Join-Path $pkg "bin\$name"
  if (-not (Test-Path $p)) { Fail "ملف ناقص في الحزمة: bin\$name`nانسخ المجلد كاملاً من جديد." "missing $name" }
  if ((Get-FileHash $p -Algorithm SHA256).Hash.ToLower() -ne $script:DW_Bins[$name].sha) { Fail "الملف bin\$name تالف أو مختلف عن النسخة الرسمية." "sha256 mismatch $name" } }
Log 'package files: SHA-256 OK'
$ErrorActionPreference = 'Continue'; $code = curl.exe -s --max-time 8 -o NUL -w "%{http_code}" http://cp.cloudflare.com/generate_204; $ErrorActionPreference = 'Stop'
if ($code -ne '204') { Fail 'لا يوجد اتصال بالإنترنت. تأكد من الإنترنت ثم حاول مرة أخرى.' "internet check http=$code" }
$def = Get-NetRoute -DestinationPrefix 0.0.0.0/0 -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1
$nic = if ($def) { Get-NetAdapter -InterfaceIndex $def.ifIndex -ErrorAction SilentlyContinue }
Log "default route: $($def.InterfaceAlias) ($($nic.InterfaceDescription)) via $($def.NextHop)"
if ($nic -and $nic.InterfaceDescription -match 'TAP|Wintun|WireGuard|NordLynx|TunnelBear|Windscribe|OpenVPN|Cloudflare|Meta Tunnel|DiscordWARP|VPN') {
  Fail "يوجد برنامج VPN شغّال الآن ($($nic.InterfaceDescription)).`nأطفئ (Disconnect) أي برنامج VPN ثم حاول مرة أخرى." 'a VPN carries the default route' }
$warpCli = Join-Path $env:ProgramFiles 'Cloudflare\Cloudflare WARP\warp-cli.exe'
if (Test-Path $warpCli) {
  $ErrorActionPreference = 'Continue'; $ws = (& $warpCli status 2>&1 | Out-String); $ErrorActionPreference = 'Stop'
  Log "official WARP client: $(($ws -split "`n")[0].Trim())"
  if ($ws -match 'Status update:\s*Connected') {
    if ((Say "برنامج Cloudflare WARP الرسمي متصل الآن، وهذا يتعارض مع الإعداد.`nهل تريد فصله (Disconnect)؟" 'Question' 'YesNo') -ne 'Yes') { Fail 'افصل برنامج Cloudflare WARP ثم حاول مرة أخرى.' 'user kept official WARP connected' }
    & $warpCli disconnect | Out-Null; Log 'official WARP client disconnected (user approved)' } }
if (-not $NoPopups) {
  if ((Say "سيتم إعداد ديسكورد ليعمل عبر Cloudflare WARP على هذا الكمبيوتر (باقي البرامج لا تتأثر).`nيستغرق دقيقة إلى 3 دقائق.`n`nمتابعة؟" 'Question' 'YesNo') -ne 'Yes') { Log 'cancelled by user'; exit 2 } }

try {
# ---------- 1. previous setup (v1.0-1.2 with Clash Verge, or an older v1.3) ----------
Stop-ScheduledTask -TaskName 'DiscordWARP-Engine' -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match '\\(\.discord-warp|DiscordWARP\\scripts)\\App\.ps1' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Get-Process mihomo -ErrorAction SilentlyContinue | Stop-Process -Force
$hadCv = (Test-Path (Join-Path $cvHome 'clash-verge.exe')) -or [bool](Get-Service clash_verge_service -ErrorAction SilentlyContinue)
if ($hadCv) {
  Get-Process clash-verge -ErrorAction SilentlyContinue | Stop-Process -Force
  Stop-Service clash_verge_service -Force -ErrorAction SilentlyContinue; Set-Service clash_verge_service -StartupType Disabled -ErrorAction SilentlyContinue
  Get-Process verge-mihomo, verge-mihomo-alpha -ErrorAction SilentlyContinue | Stop-Process -Force   # its engine uses the same WARP key - never run both
  Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'Clash Verge' -ErrorAction SilentlyContinue
  $vy = Join-Path $cvDir 'verge.yaml'
  if (Test-Path $vy) { Write-Utf8NoBom $vy (Set-YamlTopKeys (Read-TextNoBom $vy) ([ordered]@{ enable_tun_mode = 'false'; enable_auto_launch = 'false'; enable_silent_start = 'false' })) }
  if ($RemoveClashVerge) {
    $su = Join-Path $cvHome 'resources\clash-verge-service-uninstall.exe'; if (Test-Path $su) { Start-Process $su -Wait }
    $un = Join-Path $cvHome 'uninstall.exe'; if (Test-Path $un) { Start-Process $un -ArgumentList '/S' -Wait; Start-Sleep 3 }
    foreach ($d in $cvDir, (Join-Path $env:LOCALAPPDATA 'io.github.clash-verge-rev.clash-verge-rev'), (Join-Path $env:ProgramData 'clash-verge-service'), $cvHome) { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
    Log 'old setup: Clash Verge removed (program, service and its data incl. the old profile)'
  } else { Log 'old setup: Clash Verge stopped and disabled (its service Disabled, autostart and TUN off; program kept)' }
}
Unregister-ScheduledTask -TaskName 'DiscordWARP-SelfHeal' -Confirm:$false -ErrorAction SilentlyContinue
Log "old setup: $(if ($hadCv) { 'migrated from Clash Verge' } else { 'none' })"

# ---------- 2. program files ----------
New-Item -ItemType Directory -Force $prog, $scripts, $data, $cmdDir | Out-Null
$zip = Join-Path $pkg 'bin\mihomo-windows-amd64-compatible-v1.19.33.zip'
$tmpX = Join-Path $env:TEMP "dw-engine-$stamp"; Expand-Archive $zip $tmpX -Force
Copy-Item (Get-ChildItem $tmpX -Filter '*.exe' | Select-Object -First 1).FullName $engineExe -Force; Remove-Item $tmpX -Recurse -Force
foreach ($f in 'App.ps1', 'DiscordWarpLib.ps1', 'Dialog.ps1', 'Update.ps1', 'Uninstall.ps1', 'Engine.ps1', 'version.txt') { Copy-Item (Join-Path $PSScriptRoot $f) $scripts -Force }
Copy-Item (Join-Path $PSScriptRoot 'payload\*') $scripts -Recurse -Force
Copy-Item (Join-Path $PSScriptRoot 'app.ico') $prog -Force
$ver = (Get-Content (Join-Path $PSScriptRoot 'version.txt') -Raw).Trim()
Set-Content -LiteralPath (Join-Path $data 'version.txt') -Value $ver -Encoding ASCII
& icacls.exe $cmdDir /grant '*S-1-5-32-545:(OI)(CI)M' | Out-Null   # users may drop restart/pause/resume commands for the engine supervisor
Log "program files installed: $prog (engine $((& $engineExe -v) -join ' '))"

# ---------- 3. WARP registration for THIS PC (kept private) ----------
New-Item -ItemType Directory -Force $acctDir | Out-Null; Set-PrivateAcl $acctDir
$acct = Join-Path $acctDir 'wgcf-account.toml'; $prof = Join-Path $acctDir 'wgcf-profile.conf'; $wgLog = Join-Path $acctDir 'wgcf-output.log'
$oldSec = Join-Path $oldDw 'secrets'
if (-not (Test-Path $acct) -and (Test-Path (Join-Path $oldSec 'wgcf-account.toml'))) {
  Copy-Item (Join-Path $oldSec 'wgcf-account.toml') $acct -Force
  if (Test-Path (Join-Path $oldSec 'wgcf-profile.conf')) { Copy-Item (Join-Path $oldSec 'wgcf-profile.conf') $prof -Force }
  Log 'existing WARP registration from v1.x moved over (no new account)' }
$wgcf = Join-Path $pkg 'bin\wgcf_2.3.1_windows_amd64.exe'
if (-not (Test-Path $acct)) {
  Log 'creating a new free WARP registration for this PC (wgcf register --accept-tos)'
  $rc = Invoke-Native $wgcf @('--config', "`"$acct`"", 'register', '--accept-tos') $wgLog $acctDir
  if ($rc -ne 0 -or -not (Test-Path $acct)) { Fail "تعذّر إنشاء حساب WARP (رمز $rc).`nحاول مرة أخرى بعد دقائق." "wgcf register exit $rc" }
} else { Log 'WARP registration found - reused (no new account)' }
if (-not (Test-Path $prof)) {
  $rc = Invoke-Native $wgcf @('--config', "`"$acct`"", 'generate', '--profile', "`"$prof`"") $wgLog $acctDir
  if ($rc -ne 0 -or -not (Test-Path $prof)) { Fail "تعذّر إنشاء ملف WARP (رمز $rc)." "wgcf generate exit $rc" } }
$wg = Get-WgcfValues $prof
Log "WARP profile parsed: private key present=$([bool]$wg.priv), v4=$($wg.v4), v6 present=$([bool]$wg.v6)"

# ---------- 4. engine configuration (validated before it is written) ----------
New-Item -ItemType Directory -Force $engDir | Out-Null; Set-PrivateAcl $engDir
$secretFile = Join-Path $data 'api-secret.txt'
$secret = if (Test-Path $secretFile) { (Get-Content $secretFile -Raw).Trim() } else { [guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N') }
Set-Content -LiteralPath $secretFile -Value $secret -Encoding ASCII   # local API secret for the app (pipe only, no network port)
$dnsBoot = Get-BootstrapDns; if (-not $dnsBoot) { $dnsBoot = '1.1.1.1' }
$cfgText = New-EngineConfig (New-ProfileText (Read-TextNoBom (Join-Path $PSScriptRoot 'profile.template.yaml')) $wg $dnsBoot) $secret
$v = Test-EngineConfig $engineExe $cfgText (Join-Path $acctDir "validate-$stamp")
Log "engine config test: $(if ($v.Ok) { 'successful' } else { 'FAILED: ' + $v.Output })"
if (-not $v.Ok) { Fail 'ملف إعداد المحرك لم يجتز الفحص.' 'mihomo -t failed' }
$cfgFile = Join-Path $engDir 'config.yaml'
if (Test-Path $cfgFile) { Copy-Item $cfgFile (Join-Path $engDir "config.backup-$stamp.yaml") -Force }
Write-Utf8NoBom $cfgFile $cfgText
Log "engine config written (bootstrap DNS $dnsBoot)"

# ---------- 5. engine task (SYSTEM, at startup) ----------
Remove-Item -LiteralPath (Join-Path $data 'paused.flag') -Force -ErrorAction SilentlyContinue   # a (re)install always resumes
$act = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scripts\Engine.ps1`""
$trg = New-ScheduledTaskTrigger -AtStartup
$pri = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -DontStopOnIdleEnd -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew -StartWhenAvailable
Register-ScheduledTask -TaskName 'DiscordWARP-Engine' -Action $act -Trigger $trg -Principal $pri -Settings $set -Force -Description 'Discord WARP engine supervisor (mihomo + NRPT + self-heal)' | Out-Null
Start-ScheduledTask -TaskName 'DiscordWARP-Engine'
$t0 = Get-Date
while (-not ((Get-NetAdapter -Name 'DiscordWARP' -ErrorAction SilentlyContinue).Status -eq 'Up' -and (Get-Process mihomo -ErrorAction SilentlyContinue)) -and ((Get-Date) - $t0).TotalSeconds -lt 60) { Start-Sleep 2 }
if (-not (Get-Process mihomo -ErrorAction SilentlyContinue)) { Fail 'تعذّر تشغيل محرك الاتصال.' 'engine did not start' }
Log "engine: running (task DiscordWARP-Engine, TUN $((Get-NetAdapter -Name 'DiscordWARP' -ErrorAction SilentlyContinue).Status))"

# ---------- 6. NRPT (the supervisor keeps it in place; checked here) ----------
$t0 = Get-Date; while (-not @(Get-DnsClientNrptRule | Where-Object Comment -eq 'DiscordWARP').Count -and ((Get-Date) - $t0).TotalSeconds -lt 20) { Start-Sleep 1 }
$n = @(Get-DnsClientNrptRule | Where-Object Comment -eq 'DiscordWARP')
if (-not $n.Count) { Fail 'تعذّر ضبط توجيه أسماء الديسكورد.' 'NRPT missing' }
Log "NRPT: $(@($n[0].Namespace).Count) Discord namespaces -> $($n[0].NameServers)"

# ---------- 7. app, shortcuts, tray at logon, Apps entry, v1.x leftovers ----------
$psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"; $ico = Join-Path $prog 'app.ico'
$appArgs = "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scripts\App.ps1`""
$sm = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Discord WARP'; New-Item -ItemType Directory -Force $sm | Out-Null
Get-ChildItem $sm -Filter *.lnk | Remove-Item -Force
$ws = New-Object -ComObject WScript.Shell
foreach ($lp in (Join-Path $sm 'Discord WARP.lnk'), (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Discord WARP.lnk')) {
  $l = $ws.CreateShortcut($lp); $l.TargetPath = $psExe; $l.Arguments = $appArgs; $l.IconLocation = "$ico,0"; $l.Description = 'Discord WARP'; $l.Save() }
$l = $ws.CreateShortcut((Join-Path $sm 'Discord WARP - Uninstall.lnk')); $l.TargetPath = $psExe
$l.Arguments = "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scripts\Uninstall.ps1`""; $l.IconLocation = "$ico,0"; $l.Save()
Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'Discord WARP Tray' -Value "`"$psExe`" $appArgs -Tray"
$ak = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\DiscordWARP'; New-Item -Path $ak -Force | Out-Null
$props = [ordered]@{ DisplayName = 'Discord WARP'; DisplayVersion = $ver; Publisher = 'discord-warp-setup'; InstallLocation = $prog; DisplayIcon = $ico
  UninstallString = "$psExe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scripts\Uninstall.ps1`""; URLInfoAbout = 'https://github.com/Nexvorn/discord-warp-setup' }
foreach ($k in $props.Keys) { Set-ItemProperty -Path $ak -Name $k -Value $props[$k] }
Set-ItemProperty -Path $ak -Name NoModify -Value 1 -Type DWord; Set-ItemProperty -Path $ak -Name NoRepair -Value 1 -Type DWord
Set-Content -LiteralPath (Join-Path $userDir 'first-run.flag') -Value $ver -Encoding ASCII
if (Test-Path $oldDw) {   # v1.x: remove the old app files; keep logs/backups; old verify/mihomo-conns now forward to the new ones
  foreach ($f in 'App.ps1', 'Update.ps1', 'Uninstall.ps1', 'Dialog.ps1', 'DiscordWarpLib.ps1', 'version.txt', 'installed-version.txt', 'app.ico', 'first-run.flag', 'update-snooze.txt', 'warp-selfheal.ps1', 'warp-selfheal-launch.vbs', 'paused.flag') {
    Remove-Item (Join-Path $oldDw $f) -Force -ErrorAction SilentlyContinue }
  foreach ($f in 'verify.ps1', 'mihomo-conns.ps1') { if (Test-Path (Join-Path $oldDw $f)) {
    Write-Utf8NoBom (Join-Path $oldDw $f) "# moved in Discord WARP v1.3 - forwards to the installed script`r`n& '$scripts\$f' @args`r`n" } }
  Set-Content -LiteralPath (Join-Path $oldDw 'MOVED-TO-v1.3.txt') -Value "Discord WARP v1.3 lives in $prog and $data. The WARP account was moved to $acctDir. This folder keeps old logs/backups only." -Encoding ASCII }
Log "shortcuts: Start menu + desktop, tray at logon, Apps entry 'Discord WARP' v$ver"

# ---------- 8. verify ----------
function Invoke-Verify {
  $ErrorActionPreference = 'Continue'
  $o = & $psExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scripts 'verify.ps1') 2>&1 | Out-String -Width 250
  $o | Out-File (Join-Path $logDir "install-verify-$stamp.txt") -Append -Encoding utf8
  $m = [regex]::Match($o, 'RESULT: (\d+) passed, (\d+) warnings, (\d+) failed')
  [pscustomobject]@{ Text = $o; Pass = [int]$m.Groups[1].Value; Warn = [int]$m.Groups[2].Value; Fail = $(if ($m.Success) { [int]$m.Groups[3].Value } else { 99 }) } }
Start-Sleep 8
$r = Invoke-Verify; Log "verify #1: $($r.Pass) passed, $($r.Warn) warnings, $($r.Fail) failed"
if ($r.Fail -gt 0) {
  Log 'restarting the engine once to recreate the tunnel'
  Set-Content -LiteralPath (Join-Path $cmdDir 'restart') -Value '1' -Encoding ASCII; Start-Sleep 20
  $r = Invoke-Verify; Log "verify #2: $($r.Pass) passed, $($r.Warn) warnings, $($r.Fail) failed" }
($r.Text -split "`n" | Where-Object { $_ -match '^\[(PASS|FAIL|WARN|INFO)\]|RESULT' }) | ForEach-Object { Log "  $($_.Trim())" }
} catch { Fail "حدث خطأ غير متوقع:`n$($_.Exception.Message)" "exception: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)" }

if (-not $NoPopups) { Start-Process explorer.exe -ArgumentList "`"$(Join-Path $sm 'Discord WARP.lnk')`"" }
if ($r.Fail -eq 0) {
  Log '=== SETUP OK ==='
  Say ("تم الإعداد بنجاح ✔ ($($r.Pass) فحص ناجح)`n`nافتح تطبيق Discord WARP من سطح المكتب أو قائمة ابدأ، وأيقونته بجانب الساعة.") 'Information' | Out-Null
  exit 0
} else {
  Log '=== SETUP FINISHED WITH FAILED CHECKS ==='
  Say ("انتهى الإعداد لكن $($r.Fail) فحص لم ينجح.`nأعد تشغيل الكمبيوتر ثم افتح تطبيق Discord WARP واضغط فحص شامل.`n`nالسجل: $logFile") 'Warning' | Out-Null
  exit 3
}
