# DiscordWARP-Setup - one-click installer: Discord (only) via Cloudflare WARP on this PC.
# Sets up: Clash Verge Rev 2.5.10 (service mode, selective TUN),
# a NEW free WARP WireGuard registration for THIS PC (wgcf 2.3.1), NRPT for Discord names, autostart, logon self-heal.
# Run through Install-DiscordWARP.cmd (asks for admin). Safe to re-run: reuses the existing WARP account on this PC.
# Never prints secrets. Log: %USERPROFILE%\.discord-warp\install-<stamp>.log
# NOTE: this file contains Arabic UI text - it must be saved as UTF-8 WITH BOM for Windows PowerShell 5.1 (build.ps1 does that).
param([switch]$NoPopups, [string]$LogFile = '')   # -NoPopups + -LogFile: driven by the app (App.ps1 shows the progress)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\DiscordWarpLib.ps1"
Add-Type -AssemblyName System.Windows.Forms

$pkg    = Split-Path $PSScriptRoot -Parent
$stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$dw     = Join-Path $env:USERPROFILE '.discord-warp'
$sec    = Join-Path $dw 'secrets'
$cvDir  = Join-Path $env:APPDATA 'io.github.clash-verge-rev.clash-verge-rev'
$cvHome = Join-Path $env:ProgramFiles 'Clash Verge'
$cvExe  = Join-Path $cvHome 'clash-verge.exe'
$mihomo = Join-Path $cvHome 'verge-mihomo.exe'
$res    = Join-Path $cvHome 'resources'
New-Item -ItemType Directory -Force $dw | Out-Null
$logFile = Join-Path $dw "install-$stamp.log"
$appLog = $LogFile   # extra copy of every log line for the app's progress view

function Log([string]$m) { $l = "$(Get-Date -Format 'HH:mm:ss') $m"; Write-Host $l; Add-Content -LiteralPath $logFile -Value $l -Encoding UTF8
  if ($appLog) { Add-Content -LiteralPath $appLog -Value $l -Encoding UTF8 } }
function Say([string]$text, [string]$icon = 'Information', [string]$buttons = 'OK') {
  if ($NoPopups) { Log "[popup] $icon"; return $(if ($buttons -eq 'YesNo') { 'Yes' } else { 'OK' }) }   # the app asked the user beforehand
  return [string][System.Windows.Forms.MessageBox]::Show($text, 'Discord WARP', $buttons, $icon,
    [System.Windows.Forms.MessageBoxDefaultButton]::Button1, [System.Windows.Forms.MessageBoxOptions]'RtlReading, RightAlign')
}
function Fail([string]$ar, [string]$en) {
  Log "FAILED: $en"
  Say ("$ar`n`nلم يكتمل الإعداد. التفاصيل في الملف:`n$logFile") 'Error' | Out-Null
  exit 1
}
function Start-AsUser([string]$exe) {
  # Start the GUI WITHOUT admin rights (explorer launches it in the normal user context).
  Start-Process explorer.exe -ArgumentList "`"$exe`""
  $t0 = Get-Date
  while (-not (Get-Process clash-verge -ErrorAction SilentlyContinue) -and ((Get-Date) - $t0).TotalSeconds -lt 20) { Start-Sleep 1 }
  if (-not (Get-Process clash-verge -ErrorAction SilentlyContinue)) { Log 'explorer launch did not start the GUI - starting it directly'; Start-Process $exe }
}
function Stop-Gui { Get-Process clash-verge -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep 2 }
function Invoke-Native([string]$exe, [string[]]$argList, [string]$outFile) {
  $p = Start-Process -FilePath $exe -ArgumentList $argList -Wait -PassThru -NoNewWindow -WorkingDirectory $sec `
       -RedirectStandardOutput "$outFile.out" -RedirectStandardError "$outFile.err"
  Get-Content "$outFile.out", "$outFile.err" -ErrorAction SilentlyContinue | Add-Content -LiteralPath $outFile -Encoding UTF8
  Remove-Item "$outFile.out", "$outFile.err" -ErrorAction SilentlyContinue
  return $p.ExitCode
}

Log "=== DiscordWARP-Setup started (package: $pkg) ==="

# ---------- 0. preflight ----------
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Fail 'يجب تشغيل الأداة بصلاحيات المسؤول. شغّل الملف Install-DiscordWARP.cmd ووافق على رسالة Windows.' 'not elevated' }
$console = (Get-CimInstance Win32_ComputerSystem).UserName
Log "user: $($id.Name) | console user: $console | OS: $((Get-CimInstance Win32_OperatingSystem).Caption) $([Environment]::OSVersion.Version)"
if ($console -and $console -ne $id.Name) {
  Fail "الأداة تعمل باسم مستخدم مختلف ($($id.Name)) عن المستخدم الحالي ($console).`nسجّل الدخول بحساب له صلاحية المسؤول ثم شغّلها مرة أخرى." 'elevated as a different user' }
if (-not [Environment]::Is64BitOperatingSystem -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64') { Fail 'هذه الأداة لأجهزة Windows بنظام 64-bit (x64) فقط.' 'unsupported architecture' }

Get-ChildItem $pkg -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
foreach ($name in $script:DW_Bins.Keys) {
  $p = Join-Path $pkg "bin\$name"
  if (-not (Test-Path $p)) { Fail "ملف ناقص في الحزمة: bin\$name`nانسخ المجلد كاملاً من جديد." "missing $name" }
  $h = (Get-FileHash $p -Algorithm SHA256).Hash.ToLower()
  if ($h -ne $script:DW_Bins[$name].sha) { Fail "الملف bin\$name تالف أو مختلف عن النسخة الرسمية.`nانسخ المجلد كاملاً من جديد." "sha256 mismatch $name" }
}
Log 'package binaries: SHA-256 OK'

$ErrorActionPreference = 'Continue'
$code = curl.exe -s --max-time 8 -o NUL -w "%{http_code}" http://cp.cloudflare.com/generate_204
$ErrorActionPreference = 'Stop'
if ($code -ne '204') { Fail 'لا يوجد اتصال بالإنترنت. تأكد من الإنترنت ثم شغّل الأداة مرة أخرى.' "internet check http=$code" }

$def = Get-NetRoute -DestinationPrefix 0.0.0.0/0 -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1
$nic = if ($def) { Get-NetAdapter -InterfaceIndex $def.ifIndex -ErrorAction SilentlyContinue }
Log "default route: $($def.InterfaceAlias) ($($nic.InterfaceDescription)) via $($def.NextHop)"
if ($nic -and $nic.InterfaceDescription -match 'TAP|Wintun|WireGuard|NordLynx|TunnelBear|Windscribe|OpenVPN|Cloudflare|Meta Tunnel|VPN') {
  Fail "يوجد برنامج VPN شغّال الآن ($($nic.InterfaceDescription)).`nأطفئ (Disconnect) أي برنامج VPN ثم شغّل الأداة مرة أخرى." 'a VPN carries the default route' }

$warpCli = Join-Path $env:ProgramFiles 'Cloudflare\Cloudflare WARP\warp-cli.exe'
if (Test-Path $warpCli) {
  $ErrorActionPreference = 'Continue'; $ws = (& $warpCli status 2>&1 | Out-String); $ErrorActionPreference = 'Stop'
  Log "official WARP client: $(($ws -split "`n")[0].Trim())"
  if ($ws -match 'Status update:\s*Connected') {
    $a = Say "برنامج Cloudflare WARP الرسمي متصل الآن، وهذا يتعارض مع الإعداد.`nهل تريد فصله (Disconnect)؟ يمكنك تشغيله لاحقاً متى احتجته." 'Question' 'YesNo'
    if ($a -ne 'Yes') { Fail 'افصل برنامج Cloudflare WARP ثم شغّل الأداة مرة أخرى.' 'user kept official WARP connected' }
    & $warpCli disconnect | Out-Null; Log 'official WARP client disconnected (user approved)'
  }
}

$go = Say ("سيتم الآن إعداد ديسكورد ليعمل عبر Cloudflare WARP على هذا الكمبيوتر.`n" +
  "باقي البرامج تبقى على الإنترنت العادي.`n`n" +
  "سيتم: تثبيت Clash Verge، إنشاء حساب WARP مجاني لهذا الكمبيوتر، وضبط التشغيل التلقائي.`n" +
  "يستغرق 2 إلى 5 دقائق. لا تغلق النافذة السوداء.`n`nاضغط OK للبدء.") 'Information' 'OKCancel'
if ($go -ne 'OK') { Log 'cancelled by user'; exit 2 }

try {
# ---------- 1. Clash Verge ----------
$cvSetup = Get-ChildItem (Join-Path $pkg 'bin') -Filter 'Clash.Verge_*_x64-setup.exe' | Select-Object -First 1
$bundledVer = [version](([regex]::Match($cvSetup.Name, 'Clash\.Verge_([\d\.]+)_')).Groups[1].Value)
$haveVer = if (Test-Path $cvExe) { try { [version]((Get-Item $cvExe).VersionInfo.ProductVersion -replace '[^\d\.].*$', '') } catch { [version]'0.0' } } else { $null }
if (-not $haveVer -or $haveVer -lt $bundledVer) {
  Stop-Gui
  Log "installing Clash Verge Rev $bundledVer (silent; installed before: $(if ($haveVer) { $haveVer } else { 'none' }))"
  $p = Start-Process $cvSetup.FullName -ArgumentList '/S' -Wait -PassThru
  Log "installer exit code: $($p.ExitCode)"
  if (-not (Test-Path $cvExe)) { Fail 'فشل تثبيت Clash Verge.' 'Clash Verge not installed after setup' }
} else { Log "Clash Verge already installed: $haveVer (bundled $bundledVer) - kept" }
Stop-Gui

# ---------- 2. Clash Verge service (runs the core with TUN rights) ----------
$svc = Get-Service clash_verge_service -ErrorAction SilentlyContinue
if (-not $svc) {
  Log 'installing clash_verge_service'
  $p = Start-Process (Join-Path $res 'clash-verge-service-install.exe') -Wait -PassThru
  Log "service installer exit code: $($p.ExitCode)"
}
$t0 = Get-Date
while (((Get-Service clash_verge_service -ErrorAction SilentlyContinue).Status -ne 'Running') -and ((Get-Date) - $t0).TotalSeconds -lt 30) {
  Start-Service clash_verge_service -ErrorAction SilentlyContinue; Start-Sleep 2 }
$svc = Get-Service clash_verge_service -ErrorAction SilentlyContinue
if ($svc.Status -ne 'Running') { Fail 'تعذّر تشغيل خدمة Clash Verge.' 'service not running' }
Log "service: $($svc.Status) / $($svc.StartType)"

# ---------- 3. first start of Clash Verge to create its config files ----------
$need = 'verge.yaml', 'config.yaml', 'profiles.yaml' | Where-Object { -not (Test-Path (Join-Path $cvDir $_)) }
if ($need) {
  Log "first start of Clash Verge (missing: $($need -join ', '))"
  Start-AsUser $cvExe
  $t0 = Get-Date
  while (('verge.yaml', 'config.yaml', 'profiles.yaml' | Where-Object { -not (Test-Path (Join-Path $cvDir $_)) }) -and ((Get-Date) - $t0).TotalSeconds -lt 120) { Start-Sleep 2 }
  Start-Sleep 5
  if ('verge.yaml', 'config.yaml', 'profiles.yaml' | Where-Object { -not (Test-Path (Join-Path $cvDir $_)) }) { Fail 'لم يُنشئ Clash Verge ملفات الإعداد.' 'config files not created' }
}
Stop-Gui
Log 'Clash Verge GUI closed for configuration'

# ---------- 4. WARP registration for THIS PC (kept private) ----------
New-Item -ItemType Directory -Force $sec | Out-Null
& icacls.exe $dw /inheritance:r /grant:r "$($id.Name):(OI)(CI)F" 'SYSTEM:(OI)(CI)F' | Out-Null
$acct = Join-Path $sec 'wgcf-account.toml'; $prof = Join-Path $sec 'wgcf-profile.conf'; $wgLog = Join-Path $sec 'wgcf-output.log'
$wgcf = Join-Path $pkg 'bin\wgcf_2.3.1_windows_amd64.exe'
if (-not (Test-Path $acct)) {
  Log 'creating a new free WARP registration for this PC (wgcf register --accept-tos)'
  $rc = Invoke-Native $wgcf @('--config', "`"$acct`"", 'register', '--accept-tos') $wgLog
  if ($rc -ne 0 -or -not (Test-Path $acct)) { Fail "تعذّر إنشاء حساب WARP (رمز $rc).`nحاول مرة أخرى بعد دقائق." "wgcf register exit $rc" }
} else { Log 'existing WARP registration found on this PC - reused (no new account)' }
if (-not (Test-Path $prof)) {
  $rc = Invoke-Native $wgcf @('--config', "`"$acct`"", 'generate', '--profile', "`"$prof`"") $wgLog
  if ($rc -ne 0 -or -not (Test-Path $prof)) { Fail "تعذّر إنشاء ملف WARP (رمز $rc)." "wgcf generate exit $rc" }
}
$wg = Get-WgcfValues $prof
Log "WARP profile parsed: private key present=$([bool]$wg.priv), v4=$($wg.v4), v6 present=$([bool]$wg.v6)"

# ---------- 5. Clash Verge configuration (GUI closed) ----------
$bk = Join-Path $dw "backup-$stamp\clash-verge"
New-Item -ItemType Directory -Force (Join-Path $bk 'profiles') | Out-Null
foreach ($f in 'config.yaml', 'verge.yaml', 'profiles.yaml') { Copy-Item (Join-Path $cvDir $f) $bk -Force }
Get-ChildItem (Join-Path $cvDir 'profiles') -File -ErrorAction SilentlyContinue | Copy-Item -Destination (Join-Path $bk 'profiles') -Force
Log "backup of Clash Verge config: $bk"

$dnsBoot = Get-BootstrapDns; if (-not $dnsBoot) { $dnsBoot = '1.1.1.1' }
Log "bootstrap DNS for the profile: $dnsBoot"
$profileText = New-ProfileText (Read-TextNoBom (Join-Path $PSScriptRoot 'profile.template.yaml')) $wg $dnsBoot
$configText  = Update-TunBlock (Read-TextNoBom (Join-Path $cvDir 'config.yaml'))
$vergeText   = Set-YamlTopKeys (Read-TextNoBom (Join-Path $cvDir 'verge.yaml')) ([ordered]@{ enable_tun_mode = 'true'; enable_auto_launch = 'true'; enable_silent_start = 'true'; enable_system_proxy = 'false' })
$profilesTxt = Update-ProfilesYaml (Read-TextNoBom (Join-Path $cvDir 'profiles.yaml')) ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())

$v = Test-MihomoConfig $mihomo $res $configText $profileText (Join-Path $sec "validate-$stamp")
Log "mihomo config test: $(if ($v.Ok) { 'successful' } else { 'FAILED: ' + $v.Output })"
if (-not $v.Ok) { Fail 'ملف الإعداد لم يجتز الفحص، لم يتم تغيير شيء في Clash Verge.' 'mihomo -t failed' }

Write-Utf8NoBom (Join-Path $cvDir "profiles\$($script:DW_Uid).yaml") $profileText
Write-Utf8NoBom (Join-Path $cvDir 'config.yaml') $configText
Write-Utf8NoBom (Join-Path $cvDir 'verge.yaml') $vergeText
Write-Utf8NoBom (Join-Path $cvDir 'profiles.yaml') $profilesTxt
Log 'Clash Verge: profile Discord-WARP written + current, TUN (Discord routes only, dns-mode disabled), autostart flags set'

# ---------- 6. NRPT: only Discord names are resolved by mihomo ----------
Get-DnsClientNrptRule | Where-Object Comment -eq 'DiscordWARP' | ForEach-Object { Remove-DnsClientNrptRule -Name $_.Name -Force }
$ns = @(); foreach ($d in $script:DW_NrptDomains) { $ns += $d; $ns += ".$d" }; $ns += 'discord-attachments-uploads-prd.storage.googleapis.com'
Add-DnsClientNrptRule -Namespace $ns -NameServers '198.18.0.2' -Comment 'DiscordWARP' -DisplayName 'Discord via Clash WARP' | Out-Null
Clear-DnsClientCache
Log "NRPT: $($ns.Count) Discord namespaces -> 198.18.0.2"

# ---------- 7. helper scripts ----------
Copy-Item (Join-Path $PSScriptRoot 'payload\*') $dw -Recurse -Force
# UTF-16 LE with BOM: wscript reads it correctly even if the user name contains non-ASCII (e.g. Arabic) letters
[IO.File]::WriteAllText((Join-Path $dw 'warp-selfheal-launch.vbs'), ("' Hidden launcher for warp-selfheal.ps1 (generated by DiscordWARP-Setup)`r`n" +
  "CreateObject(""WScript.Shell"").Run ""powershell.exe -NoProfile -ExecutionPolicy Bypass -File """"$dw\warp-selfheal.ps1"""""", 0, False`r`n"), [Text.Encoding]::Unicode)
Log "helper scripts copied to $dw"
# app + updater + uninstaller, installed version, icon, shortcuts (Start menu + desktop), tray at logon
$ver = (Get-Content (Join-Path $PSScriptRoot 'version.txt') -Raw).Trim()
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like "*$dw\App.ps1*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }   # old app instance
foreach ($f in 'App.ps1', 'DiscordWarpLib.ps1', 'Update.ps1', 'Uninstall.ps1', 'version.txt') { Copy-Item (Join-Path $PSScriptRoot $f) $dw -Force }
Set-Content -LiteralPath (Join-Path $dw 'installed-version.txt') -Value $ver -Encoding ASCII
Add-Type -AssemblyName System.Drawing
$bmp = New-Object Drawing.Bitmap 64, 64; $g = [Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode = 'AntiAlias'
$g.FillEllipse((New-Object Drawing.SolidBrush ([Drawing.ColorTranslator]::FromHtml('#5865F2'))), 2, 2, 60, 60)
$g.FillEllipse((New-Object Drawing.SolidBrush ([Drawing.Color]::White)), 22, 22, 20, 20); $g.Dispose()
$icoPath = Join-Path $dw 'app.ico'; $fs = [IO.File]::Create($icoPath); ([Drawing.Icon]::FromHandle($bmp.GetHicon())).Save($fs); $fs.Close()
$psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$appArgs = "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$dw\App.ps1`""
$sm = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Discord WARP'
New-Item -ItemType Directory -Force $sm | Out-Null
Remove-Item (Join-Path $sm 'Discord WARP - Check.lnk'), (Join-Path $sm 'Discord WARP - Update.lnk') -ErrorAction SilentlyContinue   # v1.0/1.1 shortcuts
$ws = New-Object -ComObject WScript.Shell
foreach ($lp in (Join-Path $sm 'Discord WARP.lnk'), (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Discord WARP.lnk')) {
  $lnk = $ws.CreateShortcut($lp); $lnk.TargetPath = $psExe; $lnk.Arguments = $appArgs; $lnk.IconLocation = "$icoPath,0"; $lnk.Description = 'Discord WARP'; $lnk.Save() }
$lnk = $ws.CreateShortcut((Join-Path $sm 'Discord WARP - Uninstall.lnk'))
$lnk.TargetPath = $psExe; $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$dw\Uninstall.ps1`""; $lnk.IconLocation = "$icoPath,0"
$lnk.Save()
Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'Discord WARP Tray' -Value "`"$psExe`" $appArgs -Tray"
Remove-Item -LiteralPath (Join-Path $dw 'paused.flag') -Force -ErrorAction SilentlyContinue   # a (re)install always resumes
Set-Service clash_verge_service -StartupType Automatic -ErrorAction SilentlyContinue
# Windows Settings -> Apps -> "Discord WARP" -> Uninstall (per-user entry)
$ak = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\DiscordWARP'
New-Item -Path $ak -Force | Out-Null
$props = [ordered]@{ DisplayName = 'Discord WARP'; DisplayVersion = $ver; Publisher = 'discord-warp-setup'; InstallLocation = $dw
  DisplayIcon = $icoPath; UninstallString = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$dw\Uninstall.ps1`""
  URLInfoAbout = 'https://github.com/Nexvorn/discord-warp-setup' }
foreach ($k in $props.Keys) { Set-ItemProperty -Path $ak -Name $k -Value $props[$k] }
Set-ItemProperty -Path $ak -Name NoModify -Value 1 -Type DWord; Set-ItemProperty -Path $ak -Name NoRepair -Value 1 -Type DWord
Log "version $ver; app + updater + uninstaller; shortcuts (Start menu + desktop); tray at logon; Apps entry 'Discord WARP'"

# ---------- 8. autostart + self-heal task ----------
Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'Clash Verge' -Value "`"$cvExe`""
$act = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "`"$dw\warp-selfheal-launch.vbs`""
$trg = New-ScheduledTaskTrigger -AtLogOn -User $id.Name; $trg.Delay = 'PT2M'
$pri = New-ScheduledTaskPrincipal -UserId $id.Name -LogonType Interactive -RunLevel Limited
$set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 20) -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName 'DiscordWARP-SelfHeal' -Action $act -Trigger $trg -Principal $pri -Settings $set -Force `
  -Description "Once at logon: recreate the Clash/WARP tunnel only if confirmed broken (no admin, no periodic runs). Log: $dw\selfheal.log" | Out-Null
Log 'autostart: HKCU Run "Clash Verge"; task DiscordWARP-SelfHeal (logon + 2 min, Limited)'

# ---------- 9. start + verify ----------
function Start-AndWait {
  Stop-Gui; Start-AsUser $cvExe
  $t0 = Get-Date
  while (-not ((Get-NetAdapter -Name Meta -ErrorAction SilentlyContinue).Status -eq 'Up' -and (Get-Process verge-mihomo -ErrorAction SilentlyContinue)) -and ((Get-Date) - $t0).TotalSeconds -lt 90) { Start-Sleep 2 }
  Start-Sleep 10
}
function Invoke-Verify {
  $ErrorActionPreference = 'Continue'
  $o = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dw 'verify.ps1') 2>&1 | Out-String -Width 250
  $o | Out-File (Join-Path $dw "install-verify-$stamp.txt") -Append -Encoding utf8
  $m = [regex]::Match($o, 'RESULT: (\d+) passed, (\d+) warnings, (\d+) failed')
  return [pscustomobject]@{ Text = $o; Pass = [int]$m.Groups[1].Value; Warn = [int]$m.Groups[2].Value; Fail = $(if ($m.Success) { [int]$m.Groups[3].Value } else { 99 }) }
}
Start-AndWait
$r = Invoke-Verify
Log "verify #1: $($r.Pass) passed, $($r.Warn) warnings, $($r.Fail) failed"
if ($r.Fail -gt 0) {
  # a freshly created WireGuard tunnel is sometimes degraded (seen in testing): recreate it once
  Log 'restarting Clash Verge once to recreate the tunnel'
  Start-AndWait; $r = Invoke-Verify
  Log "verify #2: $($r.Pass) passed, $($r.Warn) warnings, $($r.Fail) failed"
}
($r.Text -split "`n" | Where-Object { $_ -match '^\[(PASS|FAIL|WARN|INFO)\]|RESULT' }) | ForEach-Object { Log "  $($_.Trim())" }
} catch {
  Fail "حدث خطأ غير متوقع:`n$($_.Exception.Message)" "exception: $($_.Exception.Message) at line $($_.InvocationInfo.ScriptLineNumber)"
}

if (-not $NoPopups) { Start-Process explorer.exe -ArgumentList "`"$(Join-Path $sm 'Discord WARP.lnk')`"" }   # classic run: open the app (unelevated)
if ($r.Fail -eq 0) {
  Log '=== SETUP OK ==='
  Say ("تم الإعداد بنجاح ✔ ($($r.Pass) فحص ناجح)`n`n" +
    "• افتح تطبيق Discord وسيعمل مباشرة.`n" +
    "• إذا لم يكن Discord مثبتاً: افتح discord.com في المتصفح ونزّله من هناك.`n" +
    "• كل شيء يعمل تلقائياً بعد إعادة تشغيل الكمبيوتر.`n" +
    "• لا تحذف برنامج Clash Verge، فهو الذي يشغّل ديسكورد.`n`n" +
    "تطبيق Discord WARP (فحص، إصلاح، تحديث، إزالة): على سطح المكتب وفي قائمة ابدأ، وأيقونته بجانب الساعة.") 'Information' | Out-Null
  exit 0
} else {
  Log '=== SETUP FINISHED WITH FAILED CHECKS ==='
  Say ("انتهى الإعداد لكن $($r.Fail) فحص لم ينجح.`n`n" +
    "جرّب: أعد تشغيل الكمبيوتر، انتظر 3 دقائق، ثم افتح تطبيق Discord WARP واضغط فحص شامل.`n" +
    "إذا بقيت المشكلة أرسل هذا الملف لمن يساعدك:`n$logFile") 'Warning' | Out-Null
  exit 3
}
