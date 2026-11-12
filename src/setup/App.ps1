# Discord WARP - desktop app (Windows PowerShell 5.1 + WPF, Arabic UI, single page + tray icon).
# Modes:  (default)  show the window (+ tray icon; closing the window keeps the tray icon)
#         -Tray      start hidden in the tray (used at logon)
#         -Action Pause|Resume   admin helper (started elevated by the app itself)
#         -SelfTest  build the window without showing it, run the status/check logic, print results, exit
# In the package folder (not installed yet) the window offers "Install" and shows the installer's progress.
# NOTE: contains Arabic UI text - saved as UTF-8 WITH BOM by build.ps1.
param([switch]$Tray, [ValidateSet('', 'Pause', 'Resume')][string]$Action = '', [switch]$SelfTest, [switch]$AutoInstall, [switch]$Preview)
$ErrorActionPreference = 'Continue'
$here = $PSScriptRoot
. (Join-Path $here 'DiscordWarpLib.ps1')
$dw         = Join-Path $env:USERPROFILE '.discord-warp'
$cvExe      = Join-Path $env:ProgramFiles 'Clash Verge\clash-verge.exe'
$pausedFlag = Join-Path $dw 'paused.flag'
$Repo       = 'Nexvorn/discord-warp-setup'
$isPackage  = (Test-Path (Join-Path $here 'Install.ps1')) -and ($here.TrimEnd('\') -ne $dw.TrimEnd('\'))
if ($Preview) { $isPackage = $false }   # -Preview: show the installed-app view from any folder; Pause/Update/Uninstall disabled
$appVersion = if (Test-Path (Join-Path $here 'version.txt')) { (Get-Content (Join-Path $here 'version.txt') -Raw).Trim() } else { '?' }

# ======================= admin helper actions (run elevated, no window) =======================
if ($Action) {
  $log = Join-Path $dw 'app-actions.log'
  function ALog($m) { Add-Content -LiteralPath $log -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Action] $m" -Encoding UTF8 }
  if ($Action -eq 'Pause') {
    Set-Content -LiteralPath $pausedFlag -Value (Get-Date -Format o) -Encoding ASCII
    Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'Clash Verge' -ErrorAction SilentlyContinue
    Get-Process clash-verge -ErrorAction SilentlyContinue | Stop-Process -Force
    Stop-Service clash_verge_service -Force -ErrorAction SilentlyContinue
    Set-Service clash_verge_service -StartupType Manual -ErrorAction SilentlyContinue
    Get-Process verge-mihomo -ErrorAction SilentlyContinue | Stop-Process -Force
    Get-DnsClientNrptRule | Where-Object Comment -eq 'DiscordWARP' | ForEach-Object { Remove-DnsClientNrptRule -Name $_.Name -Force }
    Clear-DnsClientCache
    ALog 'paused: GUI+core stopped, service Manual, NRPT removed, autostart removed'
  } else {
    Set-Service clash_verge_service -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service clash_verge_service -ErrorAction SilentlyContinue
    if (-not @(Get-DnsClientNrptRule | Where-Object Comment -eq 'DiscordWARP').Count) {
      $ns = @(); foreach ($d in $script:DW_NrptDomains) { $ns += $d; $ns += ".$d" }; $ns += 'discord-attachments-uploads-prd.storage.googleapis.com'
      Add-DnsClientNrptRule -Namespace $ns -NameServers '198.18.0.2' -Comment 'DiscordWARP' -DisplayName 'Discord via Clash WARP' | Out-Null }
    Clear-DnsClientCache
    Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'Clash Verge' -Value "`"$cvExe`""
    Remove-Item -LiteralPath $pausedFlag -Force -ErrorAction SilentlyContinue
    Start-Process explorer.exe -ArgumentList "`"$cvExe`""     # GUI without admin rights
    ALog 'resumed: service Automatic+started, NRPT restored, autostart restored, GUI started'
  }
  exit 0
}

# ======================= background work (each runs in its own runspace) =======================
$StatusWork = {
  param($dw, $cvExe)
  $r = @{ installed = (Test-Path (Join-Path $dw 'verify.ps1')) -and (Test-Path $cvExe); paused = Test-Path (Join-Path $dw 'paused.flag') }
  if (-not $r.installed -or $r.paused) { return $r }
  $r.svc  = (Get-Service clash_verge_service -ErrorAction SilentlyContinue).Status -eq 'Running'
  $r.gui  = [bool](Get-Process clash-verge -ErrorAction SilentlyContinue)
  $r.core = [bool](Get-Process verge-mihomo -ErrorAction SilentlyContinue)
  $r.meta = (Get-NetAdapter -Name Meta -ErrorAction SilentlyContinue).Status -eq 'Up'
  $r.nrpt = @(Get-DnsClientNrptRule -ErrorAction SilentlyContinue | Where-Object Comment -eq 'DiscordWARP').Count -gt 0
  if ($r.core) {
    try { $x = & (Join-Path $dw 'mihomo-conns.ps1') -ApiPath '/proxies/WARP/delay?url=https%3A%2F%2Fdiscord.com%2Fapi%2Fv9%2Fgateway&timeout=5000' -Raw | ConvertFrom-Json
          $r.delay = $x.delay; $r.err = $x.message } catch { $r.err = $_.Exception.Message } }
  return $r
}
$CheckWork = { param($dw) & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dw 'verify.ps1') 2>&1 | Out-String -Width 250 }
$RepairWork = {
  param($cvExe)
  Get-Process clash-verge -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep 2
  Start-Process $cvExe; Start-Sleep 25; 'ok'
}
$ReportWork = {
  param($dw, $cvExe)
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $tmp = Join-Path $env:TEMP "DiscordWARP-report-$stamp"; New-Item -ItemType Directory -Force $tmp | Out-Null
  function Mask([string]$t) { $t = [regex]::Replace($t, '(?m)(private-key|PrivateKey|secret|access_token|license_key|device_id)(\s*[:=]\s*)\S+', '$1$2<hidden>')
    [regex]::Replace($t, 'ip=(\d+\.\d+)\.\d+\.\d+', 'ip=$1.x.x') }
  $sys = @()
  $sys += "report: $stamp | app version: $(if (Test-Path "$dw\installed-version.txt") { (Get-Content "$dw\installed-version.txt" -Raw).Trim() } else { '?' })"
  $sys += "OS: $((Get-CimInstance Win32_OperatingSystem).Caption) $([Environment]::OSVersion.Version) | last boot: $((Get-CimInstance Win32_OperatingSystem).LastBootUpTime)"
  $sys += "Clash Verge: $((Get-Item $cvExe -ErrorAction SilentlyContinue).VersionInfo.ProductVersion) | paused: $(Test-Path "$dw\paused.flag")"
  $sys += "service: $((Get-Service clash_verge_service -ErrorAction SilentlyContinue).Status) / $((Get-Service clash_verge_service -ErrorAction SilentlyContinue).StartType)"
  $sys += "processes: " + ((Get-Process clash-verge, verge-mihomo, Discord, 'Cloudflare WARP' -ErrorAction SilentlyContinue | Group-Object Name | ForEach-Object { "$($_.Name) x$($_.Count)" }) -join ', ')
  $sys += "adapters up: " + ((Get-NetAdapter | Where-Object Status -eq 'Up' | ForEach-Object { "$($_.Name) [$($_.InterfaceDescription)]" }) -join '; ')
  $sys += "default routes: " + ((Get-NetRoute -DestinationPrefix 0.0.0.0/0 -ErrorAction SilentlyContinue | ForEach-Object { "$($_.InterfaceAlias) m$($_.RouteMetric)" }) -join '; ')
  $sys += "NRPT DiscordWARP rules: $(@(Get-DnsClientNrptRule | Where-Object Comment -eq 'DiscordWARP').Count)"
  $sys += "official WARP: " + ((& "$env:ProgramFiles\Cloudflare\Cloudflare WARP\warp-cli.exe" status 2>&1) -join ' ')
  Set-Content (Join-Path $tmp 'system.txt') (Mask ($sys -join "`r`n")) -Encoding UTF8
  if (Test-Path "$dw\verify.ps1") { Set-Content (Join-Path $tmp 'verify.txt') (Mask (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$dw\verify.ps1" 2>&1 | Out-String -Width 250)) -Encoding UTF8 }
  foreach ($f in @(Get-ChildItem $dw -Filter 'install-*.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 2) + @(Get-Item "$dw\selfheal.log", "$dw\app-actions.log" -ErrorAction SilentlyContinue)) {
    Set-Content (Join-Path $tmp $f.Name) (Mask (Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue)) -Encoding UTF8 }
  $cl = Join-Path $env:APPDATA 'io.github.clash-verge-rev.clash-verge-rev\logs\latest.log'
  if (Test-Path $cl) { Set-Content (Join-Path $tmp 'clash-verge-latest.log') (Mask (Get-Content $cl -Raw)) -Encoding UTF8 }
  $zip = Join-Path ([Environment]::GetFolderPath('Desktop')) "DiscordWARP-report-$stamp.zip"
  Compress-Archive -Path "$tmp\*" -DestinationPath $zip -Force; Remove-Item $tmp -Recurse -Force
  $zip
}
$UpdateCheckWork = {
  param($repo)
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  try { $rel = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -TimeoutSec 20 -Headers @{ 'User-Agent' = 'discord-warp-app' }
        @{ ok = $true; tag = ($rel.tag_name -replace '^v', ''); body = [string]$rel.body } } catch { @{ ok = $false; err = $_.Exception.Message } }
}

# ======================= translation of verify.ps1 lines =======================
$Tr = @(
  @('Clash Verge service running', 'خدمة Clash Verge تعمل'), @('Clash Verge service not running', 'خدمة Clash Verge متوقفة'),
  @('Clash Verge app running', 'برنامج Clash Verge يعمل'), @('Clash Verge app not running', 'برنامج Clash Verge مغلق'),
  @('mihomo core running', 'محرك الاتصال يعمل'), @('mihomo core not running', 'محرك الاتصال متوقف'),
  @("TUN adapter 'Meta' up", 'محوّل النفق يعمل'), @('TUN adapter', 'محوّل النفق لا يعمل'),
  @('TUN routes present', 'مسارات الديسكورد داخل النفق'), @('TUN routes missing', 'بعض مسارات الديسكورد مفقودة'),
  @('default route via', 'باقي البرامج تستخدم الإنترنت العادي'), @('default route goes through the TUN', 'كل الإنترنت يمر بالنفق (خطأ)'),
  @('NRPT Discord rule present', 'أسماء الديسكورد توجَّه إلى النفق'), @('NRPT Discord rule missing', 'توجيه أسماء الديسكورد مفقود'),
  @('TUN does not take over system DNS', 'إعدادات DNS للكمبيوتر لم تتغير'),
  @('discord.com ->', 'اسم discord.com يمر عبر النفق'), @('www.google.com ->', 'المواقع الأخرى تعمل بشكل عادي'),
  @('other apps:', 'باقي البرامج على إنترنتك الأصلي'),
  @('WARP tunnel reachable', 'نفق WARP متصل'), @('WARP tunnel test failed', 'نفق WARP لا يستجيب'),
  @('Discord API via WARP failed', 'خوادم الديسكورد لا تستجيب عبر WARP'), @('Discord API via WARP slow', 'خوادم الديسكورد بطيئة عبر WARP'), @('Discord API via WARP', 'خوادم الديسكورد تستجيب عبر WARP'),
  @('DISCORD group = WARP only', 'لا تسريب: الديسكورد عبر WARP فقط'),
  @('Discord app:', 'تطبيق الديسكورد: كل اتصالاته عبر WARP'), @('Discord app not running', 'تطبيق الديسكورد مغلق حالياً'), @('Discord running but idle', 'تطبيق الديسكورد مفتوح بدون اتصالات الآن'),
  @('Discord connections NOT via WARP', 'بعض اتصالات الديسكورد لا تمر عبر WARP'),
  @('no non-Discord process uses WARP', 'لا يوجد برنامج آخر يستخدم WARP'), @('non-Discord processes using WARP', 'برامج أخرى تستخدم WARP'),
  @('last call', 'آخر مكالمة صوتية مرّت عبر WARP'), @('last media server', 'خادم آخر مكالمة داخل النفق'),
  @('no voice call found', 'لا توجد مكالمة سابقة للفحص'), @('mihomo API not reachable', 'تعذّر الاتصال بمحرك Clash'))
function Convert-VerifyLine([string]$line) {
  $m = [regex]::Match($line, '^\[(PASS|FAIL|WARN|INFO)\]\s+(.*)$'); if (-not $m.Success) { return $null }
  $st = $m.Groups[1].Value; $txt = $m.Groups[2].Value
  if ($st -eq 'INFO' -and $txt -match '^Discord app-') { return $null }
  $ar = $null; foreach ($t in $Tr) { if ($txt.StartsWith($t[0])) { $ar = $t[1]; break } }
  $ms = [regex]::Match($txt, '(\d+) ms'); if ($ar -and $ms.Success) { $ar += " ($($ms.Groups[1].Value) ms)" }
  if (-not $ar) { $ar = $txt }
  [pscustomobject]@{ State = $st; Text = $ar }
}

if ($SelfTest) {
  "isPackage=$isPackage appVersion=$appVersion"
  $s = & $StatusWork $dw $cvExe; "status: " + (($s.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ' ')
  if ($s.installed) { $out = & $CheckWork $dw; $rows = @($out -split "`r?`n" | ForEach-Object { Convert-VerifyLine $_ } | Where-Object { $_ })
    "check rows: $($rows.Count)"; $rows | ForEach-Object { "  [$($_.State)] $($_.Text)" }; "untranslated: $(@($rows | Where-Object { $_.Text -match '^[A-Za-z]' }).Count)" }
}

# ======================= single instance =======================
$mutexName = if ($isPackage) { 'Local\DiscordWARP-Setup' } else { 'Local\DiscordWARP-App' }
$createdNew = $false
$mutex = New-Object Threading.Mutex($true, $mutexName, [ref]$createdNew)
$showEvt = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::AutoReset, "$mutexName-Show")
if (-not $createdNew -and -not $SelfTest) { [void]$showEvt.Set(); exit 0 }

# ======================= UI =======================
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing
$app = New-Object Windows.Application; $app.ShutdownMode = 'OnExplicitShutdown'
# own taskbar identity: without this the window is grouped under (and shows the icon of) Windows PowerShell
try { Add-Type -Namespace DW -Name Shell -MemberDefinition '[DllImport("shell32.dll")] public static extern int SetCurrentProcessExplicitAppUserModelID([MarshalAs(UnmanagedType.LPWStr)] string AppID);'
      [void][DW.Shell]::SetCurrentProcessExplicitAppUserModelID('DiscordWARP.App') } catch {}
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Discord WARP" Width="600" Height="760" WindowStartupLocation="CenterScreen" ResizeMode="CanMinimize"
        FlowDirection="RightToLeft" Background="#1E1F22" FontFamily="Segoe UI" FontSize="14" Foreground="#DBDEE1">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Foreground" Value="#F2F3F5"/><Setter Property="Background" Value="#2B2D31"/>
      <Setter Property="BorderBrush" Value="#3F4147"/><Setter Property="Height" Value="46"/><Setter Property="Margin" Value="5"/>
      <Setter Property="Cursor" Value="Hand"/><Setter Property="FontSize" Value="14"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="b" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="8">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="#5865F2"/></Trigger>
            <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.4"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate></Setter.Value></Setter>
    </Style>
  </Window.Resources>
  <Grid Margin="20">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <DockPanel Grid.Row="0" Margin="2,0,2,14">
      <TextBlock x:Name="Ver" DockPanel.Dock="Right" Foreground="#80848E" VerticalAlignment="Bottom" FontSize="12"/>
      <TextBlock Text="Discord WARP" FontSize="24" FontWeight="SemiBold" Foreground="#F2F3F5"/>
    </DockPanel>
    <Border Grid.Row="1" Background="#2B2D31" CornerRadius="12" Padding="18" Margin="0,0,0,12">
      <StackPanel Orientation="Horizontal">
        <Ellipse x:Name="Dot" Width="26" Height="26" Fill="#80848E" Margin="0,0,16,0" VerticalAlignment="Center"/>
        <StackPanel VerticalAlignment="Center">
          <TextBlock x:Name="StatusTitle" Text="جارٍ الفحص..." FontSize="19" FontWeight="SemiBold" Foreground="#F2F3F5"/>
          <TextBlock x:Name="StatusSub" Text="" Foreground="#B5BAC1" Margin="0,4,0,0" TextWrapping="Wrap" MaxWidth="440"/>
        </StackPanel>
      </StackPanel>
    </Border>
    <Grid Grid.Row="2" Margin="0,0,0,12">
      <Button x:Name="BtnInstall" Content="تثبيت" Height="56" FontSize="17" FontWeight="SemiBold" Background="#5865F2" BorderBrush="#5865F2" Visibility="Collapsed"/>
      <StackPanel x:Name="Actions">
        <TextBlock Text="الديسكورد" Foreground="#80848E" FontSize="12" Margin="7,0,0,0"/>
        <UniformGrid Rows="1" Columns="3">
          <Button x:Name="BtnOpenDiscord" Content="فتح الديسكورد"/>
          <Button x:Name="BtnGetDiscord" Content="تحميل وتثبيت الديسكورد"/>
          <Button x:Name="BtnWebDiscord" Content="الديسكورد من المتصفح"/>
        </UniformGrid>
        <TextBlock Text="الصيانة" Foreground="#80848E" FontSize="12" Margin="7,8,0,0"/>
        <UniformGrid Rows="2" Columns="3">
          <Button x:Name="BtnCheck" Content="فحص شامل"/>
          <Button x:Name="BtnRepair" Content="إصلاح"/>
          <Button x:Name="BtnPause" Content="إيقاف مؤقت"/>
          <Button x:Name="BtnUpdate" Content="تحديث"/>
          <Button x:Name="BtnReport" Content="تقرير للمساعدة"/>
          <Button x:Name="BtnUninstall" Content="إزالة"/>
        </UniformGrid>
      </StackPanel>
    </Grid>
    <Border Grid.Row="3" Background="#2B2D31" CornerRadius="12" Padding="14">
      <DockPanel>
        <TextBlock x:Name="ListTitle" DockPanel.Dock="Top" Text="التفاصيل" Foreground="#80848E" FontSize="12" Margin="0,0,0,8"/>
        <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel x:Name="ListPanel"/></ScrollViewer>
      </DockPanel>
    </Border>
    <StackPanel Grid.Row="4" Margin="2,12,2,0">
      <ProgressBar x:Name="Busy" Height="4" IsIndeterminate="True" Visibility="Hidden" Foreground="#5865F2" Background="#2B2D31" BorderThickness="0"/>
      <TextBlock x:Name="Foot" Foreground="#80848E" FontSize="12" Margin="0,6,0,0" TextWrapping="Wrap"/>
    </StackPanel>
  </Grid>
</Window>
'@
$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$uiNames = 'Ver','Dot','StatusTitle','StatusSub','BtnInstall','Actions','BtnCheck','BtnRepair','BtnPause','BtnUpdate','BtnReport','BtnUninstall','ListTitle','ListPanel','Busy','Foot','BtnOpenDiscord','BtnGetDiscord','BtnWebDiscord'
$ui = @{}; foreach ($n in $uiNames) { $ui[$n] = $win.FindName($n) }
$ui.Ver.Text = "الإصدار $appVersion" + $(if ($Preview) { '  (معاينة)' } else { '' })
if ($SelfTest) { "ui controls found: $(@($ui.Values | Where-Object { $_ }).Count)/$($uiNames.Count)"; exit 0 }

$colors = @{ green = '#23A55A'; red = '#F23F43'; orange = '#F0B232'; grey = '#80848E' }
function New-Brush($hex) { New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($hex)) }
function New-DotIcon($hex) {
  $bmp = New-Object Drawing.Bitmap 32, 32; $g = [Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode = 'AntiAlias'
  $g.FillEllipse((New-Object Drawing.SolidBrush ([Drawing.ColorTranslator]::FromHtml('#2B2D31'))), 0, 0, 31, 31)
  $g.FillEllipse((New-Object Drawing.SolidBrush ([Drawing.ColorTranslator]::FromHtml($hex))), 6, 6, 19, 19); $g.Dispose()
  [Drawing.Icon]::FromHandle($bmp.GetHicon()) }
$icons = @{}; foreach ($k in $colors.Keys) { $icons[$k] = New-DotIcon $colors[$k] }
$abmp = New-Object Drawing.Bitmap 64, 64; $ag = [Drawing.Graphics]::FromImage($abmp); $ag.SmoothingMode = 'AntiAlias'   # app icon (same as the installed app.ico)
$ag.FillEllipse((New-Object Drawing.SolidBrush ([Drawing.ColorTranslator]::FromHtml('#5865F2'))), 2, 2, 60, 60)
$ag.FillEllipse((New-Object Drawing.SolidBrush ([Drawing.Color]::White)), 22, 22, 20, 20); $ag.Dispose()
$win.Icon = [Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon($abmp.GetHicon(), [Windows.Int32Rect]::Empty, [Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions())

function Say([string]$t, [string]$icon = 'Information', [string]$b = 'OK') {
  [string][System.Windows.MessageBox]::Show($win, $t, 'Discord WARP', $b, $icon, 'None', [System.Windows.MessageBoxOptions]::RtlReading) }
function Set-Busy([bool]$on, [string]$msg = '') {
  $ui.Busy.Visibility = if ($on) { 'Visible' } else { 'Hidden' }; $ui.Foot.Text = $msg
  foreach ($b in 'BtnCheck','BtnRepair','BtnPause','BtnUpdate','BtnReport','BtnUninstall','BtnInstall','BtnOpenDiscord','BtnGetDiscord','BtnWebDiscord') { $ui[$b].IsEnabled = -not $on }
  if (-not $on) { Update-DiscordButtons } }
function Clear-List([string]$title) { $ui.ListPanel.Children.Clear(); $ui.ListTitle.Text = $title }
function Add-Row([string]$state, [string]$text) {
  $sym = @{ PASS = '✓'; FAIL = '✗'; WARN = '!'; INFO = '•'; RUN = '…'; TODO = '○' }[$state]
  $col = @{ PASS = $colors.green; FAIL = $colors.red; WARN = $colors.orange; INFO = $colors.grey; RUN = '#5865F2'; TODO = '#4E5058' }[$state]
  $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'; $sp.Margin = '0,3,0,3'
  $a = New-Object Windows.Controls.TextBlock; $a.Text = $sym; $a.Width = 22; $a.FontWeight = 'Bold'; $a.Foreground = New-Brush $col
  $b = New-Object Windows.Controls.TextBlock; $b.Text = $text; $b.TextWrapping = 'Wrap'; $b.MaxWidth = 470
  [void]$sp.Children.Add($a); [void]$sp.Children.Add($b); [void]$ui.ListPanel.Children.Add($sp) }

# ---- async runner: a runspace per job, completion polled on the UI thread ----
$script:jobs = New-Object System.Collections.ArrayList
function Start-Bg([scriptblock]$work, [object[]]$argList, [scriptblock]$done) {
  $ps = [powershell]::Create(); [void]$ps.AddScript($work); foreach ($a in $argList) { [void]$ps.AddArgument($a) }
  [void]$script:jobs.Add(@{ ps = $ps; h = $ps.BeginInvoke(); done = $done }) }
$pump = New-Object Windows.Threading.DispatcherTimer; $pump.Interval = [TimeSpan]::FromMilliseconds(300)
$pump.Add_Tick({
  foreach ($j in @($script:jobs)) { if ($j.h.IsCompleted) {
    [void]$script:jobs.Remove($j); $res = $null
    try { $res = $j.ps.EndInvoke($j.h) } catch { $res = $null }
    $j.ps.Dispose()
    try { & $j.done $res } catch { Set-Busy $false "خطأ: $($_.Exception.Message)" } } }
  if ($showEvt.WaitOne(0)) { Show-Main } })

# ---- tray ----
$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = $icons.grey; $notify.Text = 'Discord WARP'; $notify.Visible = -not $isPackage
$menu = New-Object System.Windows.Forms.ContextMenuStrip; $menu.RightToLeft = 'Yes'
$miOpen = $menu.Items.Add('فتح'); $miRepair = $menu.Items.Add('إصلاح'); $miPause = $menu.Items.Add('إيقاف مؤقت'); [void]$menu.Items.Add('-'); $miExit = $menu.Items.Add('خروج')
$notify.ContextMenuStrip = $menu
function Show-Main { $win.Show(); if ($win.WindowState -eq 'Minimized') { $win.WindowState = 'Normal' }; [void]$win.Activate(); Update-Status }
$notify.Add_DoubleClick({ Show-Main }); $notify.Add_BalloonTipClicked({ Show-Main }); $miOpen.Add_Click({ Show-Main })
$script:quit = $false
$miExit.Add_Click({ $script:quit = $true; $notify.Visible = $false; $win.Close(); [Windows.Application]::Current.Shutdown() })
$win.Add_Closing({ param($s, $e) if (-not $script:quit -and -not $isPackage) { $e.Cancel = $true; $win.Hide()
  if (-not $script:hintShown) { $script:hintShown = $true; $notify.ShowBalloonTip(3000, 'Discord WARP', 'التطبيق ما زال يعمل هنا بجانب الساعة.', 'Info') } } })
$win.Add_Closed({ $notify.Visible = $false; [Windows.Application]::Current.Shutdown() })

# ---- status ----
$script:lastState = ''
function Apply-Status($r) {
  $state = 'grey'; $title = ''; $sub = ''
  if (-not $r) { $title = 'تعذّر الفحص' }
  elseif (-not $r.installed) { $title = 'غير مثبّت'; $sub = if ($isPackage) { 'اضغط "تثبيت" للبدء. يستغرق 2 إلى 5 دقائق.' } else { 'شغّل ملف التثبيت.' } }
  elseif ($r.paused -and $isPackage) { $title = 'مثبّت (متوقف مؤقتاً)'; $sub = 'التثبيت سيعيد التشغيل.' }
  elseif ($r.paused) { $title = 'متوقف مؤقتاً'; $sub = 'الديسكورد لا يمر عبر WARP الآن. اضغط "تشغيل" للعودة.' }
  elseif (-not ($r.svc -and $r.core -and $r.meta)) { $state = 'red'; $title = 'Clash Verge لا يعمل'; $sub = 'اضغط "إصلاح".' }
  elseif (-not $r.nrpt) { $state = 'red'; $title = 'إعداد ناقص'; $sub = 'توجيه أسماء الديسكورد مفقود. أعد التثبيت.' }
  elseif (-not $r.delay) { $state = 'red'; $title = 'نفق WARP لا يستجيب'; $sub = 'اضغط "إصلاح". إذا استمرت المشكلة اضغط "تقرير للمساعدة".' }
  elseif ($r.delay -gt 300) { $state = 'orange'; $title = 'الاتصال بطيء'; $sub = "السرعة: $($r.delay) ms. جرّب ""إصلاح"" إذا كان الديسكورد بطيئاً." }
  else { $state = 'green'; $title = 'الديسكورد يعمل عبر WARP'; $sub = "السرعة: $($r.delay) ms  |  آخر فحص: $(Get-Date -Format 'HH:mm')" }
  $ui.Dot.Fill = New-Brush $colors[$state]; $ui.StatusTitle.Text = $title; $ui.StatusSub.Text = $sub
  $notify.Icon = $icons[$state]; $notify.Text = ("Discord WARP: $title").Substring(0, [Math]::Min(63, ("Discord WARP: $title").Length))
  $installed = $r -and $r.installed
  $ui.BtnInstall.Visibility = if ($isPackage) { 'Visible' } else { 'Collapsed' }
  $ui.Actions.Visibility = if ($isPackage) { 'Collapsed' } else { 'Visible' }
  if ($isPackage) { $ui.BtnInstall.Content = if ($installed) { "تثبيت النسخة $appVersion (تحديث / إصلاح)" } else { 'تثبيت' } }
  if ($isPackage -and $AutoInstall -and -not $script:autoDone) { $script:autoDone = $true; $script:skipConfirm = $true
    $ui.BtnInstall.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent))) }
  $paused = $r -and $r.paused
  $ui.BtnPause.Content = if ($paused) { 'تشغيل' } else { 'إيقاف مؤقت' }; $miPause.Text = $ui.BtnPause.Content
  foreach ($b in 'BtnCheck','BtnRepair') { $ui[$b].IsEnabled = $installed -and -not $paused }
  Update-DiscordButtons
  if ($script:lastState -in 'green','orange' -and $state -eq 'red') { $notify.ShowBalloonTip(5000, 'Discord WARP', "$title - افتح التطبيق واضغط ""إصلاح"".", 'Warning') }
  $script:lastState = $state
}
function Update-Status { Start-Bg $StatusWork @($dw, $cvExe) { param($res) Apply-Status ($res | Select-Object -Last 1) } }

# ---- buttons ----
$ui.BtnCheck.Add_Click({
  Set-Busy $true 'جارٍ الفحص الشامل... (حوالي 15 ثانية)'; Clear-List 'نتيجة الفحص الشامل'
  Start-Bg $CheckWork @($dw) { param($res)
    $rows = @(([string]($res -join "`n")) -split "`r?`n" | ForEach-Object { Convert-VerifyLine $_ } | Where-Object { $_ })
    foreach ($row in $rows) { Add-Row $row.State $row.Text }
    $f = @($rows | Where-Object State -eq 'FAIL').Count; $p = @($rows | Where-Object State -eq 'PASS').Count
    Set-Busy $false $(if ($f) { "$f فحص لم ينجح. جرّب ""إصلاح""." } else { "كل الفحوصات سليمة ($p)." }); Update-Status } })

$ui.BtnRepair.Add_Click({
  $inCall = $false
  try { $inCall = [bool](@(& (Join-Path $dw 'mihomo-conns.ps1') | Where-Object { $_.proc -eq 'Discord.exe' -and $_.net -eq 'udp' -and $_.dst -match '^(104\.(28|29)\.|66\.22\.|195\.62\.89\.)' }).Count) } catch {}
  if ($inCall -and (Say 'أنت في مكالمة ديسكورد الآن. الإصلاح سيقطعها لثوانٍ. متابعة؟' 'Warning' 'YesNo') -ne 'Yes') { return }
  Set-Busy $true 'جارٍ إعادة تشغيل الاتصال... (حوالي 30 ثانية)'; Clear-List 'إصلاح'; Add-Row 'RUN' 'إعادة تشغيل Clash Verge وإنشاء نفق WARP جديد'
  Start-Bg $RepairWork @($cvExe) { param($res) Clear-List 'إصلاح'; Add-Row 'PASS' 'تمت إعادة التشغيل'; Set-Busy $false 'انتهى الإصلاح. يتم تحديث الحالة...'; Update-Status } })

function Test-PreviewBlock { if ($Preview) { Say 'هذه معاينة فقط: الإيقاف والتحديث والإزالة معطّلة هنا.' | Out-Null; return $true }; $false }
$ui.BtnPause.Add_Click({
  if (Test-PreviewBlock) { return }
  $paused = Test-Path $pausedFlag
  $q = if ($paused) { 'تشغيل مرور الديسكورد عبر WARP مرة ثانية؟ (سيطلب Windows صلاحية المسؤول)' } else { "إيقاف مؤقت: الديسكورد سيتوقف عن المرور عبر WARP (سيعود محجوباً) حتى تضغط ""تشغيل"".`nمفيد إذا أردت استخدام VPN آخر. يبقى الإيقاف حتى بعد إعادة تشغيل الكمبيوتر.`nسيطلب Windows صلاحية المسؤول. متابعة؟" }
  if ((Say $q 'Question' 'YesNo') -ne 'Yes') { return }
  $act = if ($paused) { 'Resume' } else { 'Pause' }
  try { Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Action $act" } catch { return }
  Set-Busy $true $(if ($paused) { 'جارٍ التشغيل... (حوالي 30 ثانية)' } else { 'جارٍ الإيقاف...' })
  $script:waitUntil = (Get-Date).AddSeconds($(if ($paused) { 35 } else { 8 }))
  $t = New-Object Windows.Threading.DispatcherTimer; $t.Interval = [TimeSpan]::FromSeconds(1)
  $t.Add_Tick({ if ((Get-Date) -ge $script:waitUntil) { $this.Stop(); Set-Busy $false ''; Update-Status } }); $t.Start() })
$miPause.Add_Click({ Show-Main; $ui.BtnPause.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent))) })
$miRepair.Add_Click({ Show-Main; $ui.BtnRepair.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent))) })

$ui.BtnReport.Add_Click({
  Set-Busy $true 'جارٍ تجهيز التقرير... (حوالي 20 ثانية)'
  Start-Bg $ReportWork @($dw, $cvExe) { param($res) $zip = [string]($res | Select-Object -Last 1)
    Set-Busy $false "تم حفظ التقرير على سطح المكتب: $zip"
    Say "تم حفظ التقرير على سطح المكتب:`n$zip`n`nأرسل هذا الملف لمن يساعدك. لا يحتوي على كلمات سر أو مفاتيح." | Out-Null
    Start-Process explorer.exe -ArgumentList "/select,`"$zip`"" } })

$ui.BtnUpdate.Add_Click({
  if (Test-PreviewBlock) { return }
  Set-Busy $true 'جارٍ البحث عن تحديث...'
  Start-Bg $UpdateCheckWork @($Repo) { param($res) $r = $res | Select-Object -Last 1; Set-Busy $false ''
    if (-not $r.ok) { Say "تعذّر فحص التحديثات الآن.`n(لا يوجد إنترنت، أو صفحة الأداة غير متاحة)" 'Warning' | Out-Null; return }
    $cur = if (Test-Path "$dw\installed-version.txt") { (Get-Content "$dw\installed-version.txt" -Raw).Trim() } else { '0.0.0' }
    if ([version]$r.tag -le [version]$cur) { Say "لديك آخر نسخة ($cur)." | Out-Null; return }
    $notes = $r.body; if ($notes.Length -gt 400) { $notes = $notes.Substring(0, 400) + ' ...' }
    if ((Say "توجد نسخة جديدة: $($r.tag) (نسختك: $cur)`n`n$notes`n`nتحديث الآن؟ سيطلب Windows صلاحية المسؤول." 'Question' 'YesNo') -ne 'Yes') { return }
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$dw\Update.ps1`" -Yes"
    $script:quit = $true; $notify.Visible = $false; $win.Close(); [Windows.Application]::Current.Shutdown() } })

# ---- Discord: open / download + install / browser ----
$discordUpdate = Join-Path $env:LOCALAPPDATA 'Discord\Update.exe'
function Update-DiscordButtons {
  $has = Test-Path $discordUpdate
  $ui.BtnOpenDiscord.IsEnabled = $has
  $ui.BtnGetDiscord.Content = if ($has) { 'إعادة تثبيت الديسكورد' } else { 'تحميل وتثبيت الديسكورد' }
  $ui.BtnGetDiscord.Background = New-Brush $(if ($has) { '#2B2D31' } else { '#5865F2' }) }
$GetDiscordWork = {
  $ProgressPreference = 'SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $out = Join-Path $env:TEMP 'DiscordSetup.exe'
  try {
    Invoke-WebRequest 'https://discord.com/api/downloads/distributions/app/installers/latest?channel=stable&platform=win&arch=x64' -OutFile $out -UseBasicParsing -TimeoutSec 600
    $sig = Get-AuthenticodeSignature $out
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Discord') { Remove-Item $out -Force -ErrorAction SilentlyContinue; return @{ ok = $false; err = "signature: $($sig.Status) $($sig.SignerCertificate.Subject)" } }
    @{ ok = $true; path = $out; mb = [math]::Round((Get-Item $out).Length / 1MB) }
  } catch { @{ ok = $false; err = $_.Exception.Message } }
}
$ui.BtnOpenDiscord.Add_Click({
  if (Test-Path $discordUpdate) { Start-Process $discordUpdate -ArgumentList '--processStart Discord.exe'; $ui.Foot.Text = 'جارٍ فتح الديسكورد...' }
  else { Say 'الديسكورد غير مثبّت على هذا الكمبيوتر. اضغط "تحميل وتثبيت الديسكورد".' | Out-Null } })
$ui.BtnGetDiscord.Add_Click({
  if ((Say "سيتم تحميل برنامج الديسكورد الرسمي (حوالي 160 ميغا) من موقع الديسكورد عبر WARP، ثم التأكد من توقيعه الرسمي وتثبيته.`nمتابعة؟" 'Question' 'YesNo') -ne 'Yes') { return }
  Set-Busy $true 'جارٍ تحميل الديسكورد... (حسب سرعة الإنترنت، عادةً 1 إلى 5 دقائق)'; Clear-List 'تحميل الديسكورد'; Add-Row 'RUN' 'تحميل المثبّت الرسمي من discord.com'
  Start-Bg $GetDiscordWork @() { param($res) $r = $res | Select-Object -Last 1; Clear-List 'تحميل الديسكورد'
    if ($r.ok) { Add-Row 'PASS' "تم التحميل ($($r.mb) ميغا)"; Add-Row 'PASS' 'التوقيع الرسمي من Discord سليم'; Add-Row 'RUN' 'جارٍ التثبيت... سيفتح الديسكورد وحده عند الانتهاء'
      Start-Process $r.path; Set-Busy $false 'بدأ تثبيت الديسكورد. سيفتح وحده خلال دقيقة.' }
    else { Add-Row 'FAIL' 'فشل التحميل أو التحقق من التوقيع'; Set-Busy $false "خطأ: $($r.err)"
      Say "تعذّر تحميل الديسكورد.`nتأكد أن الحالة خضراء ثم حاول مرة ثانية.`n`n$($r.err)" 'Warning' | Out-Null } } })
$ui.BtnWebDiscord.Add_Click({
  Start-Process 'https://discord.com/app'
  $ui.Foot.Text = 'تم فتح discord.com/app في متصفحك. إذا لم يفتح: عطّل خيار "DNS الآمن / Secure DNS" في إعدادات المتصفح.' })

$ui.BtnUninstall.Add_Click({
  if (Test-PreviewBlock) { return }
  Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$dw\Uninstall.ps1`""
  $script:quit = $true; $notify.Visible = $false; $win.Close(); [Windows.Application]::Current.Shutdown() })

# ---- install (package mode) ----
$steps = @(
  @('فحص الجهاز وملفات الحزمة', 'package binaries: SHA-256 OK'), @('تثبيت Clash Verge', 'installing Clash Verge|Clash Verge already installed'),
  @('تشغيل خدمة Clash Verge', '\d service: '), @('إنشاء حساب WARP مجاني لهذا الكمبيوتر', 'WARP profile parsed'),
  @('ضبط الإعدادات وفحصها', 'Clash Verge: profile Discord-WARP written'), @('توجيه أسماء الديسكورد', 'NRPT: '),
  @('التطبيق والتشغيل التلقائي والإصلاح الذاتي', 'autostart: '), @('الفحص النهائي', 'verify #'))
$ui.BtnInstall.Add_Click({
  $q = "سيتم إعداد ديسكورد ليعمل عبر Cloudflare WARP على هذا الكمبيوتر (باقي البرامج لا تتأثر):`n" +
       "• تثبيت Clash Verge`n• إنشاء حساب WARP مجاني لهذا الكمبيوتر`n• ضبط التشغيل التلقائي`n" +
       "• إذا كان برنامج Cloudflare WARP الرسمي متصلاً سيتم فصله`n`nأطفئ أي VPN آخر قبل البدء. سيطلب Windows صلاحية المسؤول. متابعة؟"
  if (-not $script:skipConfirm -and (Say $q 'Question' 'YesNo') -ne 'Yes') { return }
  $script:instLog = Join-Path $env:TEMP "discord-warp-install-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
  try { Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $here 'Install.ps1')`" -NoPopups -ProgressLog `"$script:instLog`"" }
  catch { Set-Busy $false 'تم إلغاء التثبيت (لم تتم الموافقة على صلاحية المسؤول).'; return }
  Set-Busy $true 'جارٍ التثبيت... لا تغلق النافذة (2 إلى 5 دقائق)'; $script:instStart = Get-Date
  $ui.StatusTitle.Text = 'جارٍ التثبيت...'; $ui.StatusSub.Text = ''
  $t = New-Object Windows.Threading.DispatcherTimer; $t.Interval = [TimeSpan]::FromSeconds(1)
  $t.Add_Tick({
    $lines = @(); if (Test-Path $script:instLog) { $lines = @(Get-Content $script:instLog -Encoding UTF8 -ErrorAction SilentlyContinue) }
    $all = $lines -join "`n"; Clear-List 'خطوات التثبيت'
    $reached = -1; for ($i = 0; $i -lt $steps.Count; $i++) { if ($all -match $steps[$i][1]) { $reached = $i } }
    $end = if ($all -match '=== SETUP OK ===') { 'ok' } elseif ($all -match 'SETUP FINISHED WITH FAILED CHECKS') { 'partial' } elseif ($all -match 'FAILED: |cancelled by user') { 'fail' } else { '' }
    for ($i = 0; $i -lt $steps.Count; $i++) {
      $st = if ($i -le $reached -and ($end -eq 'ok' -or $i -lt $reached)) { 'PASS' } elseif ($i -eq $reached -or ($i -eq $reached + 1 -and -not $end)) { if ($end -eq 'fail') { 'FAIL' } else { 'RUN' } } else { 'TODO' }
      Add-Row $st $steps[$i][0] }
    if (-not $end -and ((Get-Date) - $script:instStart).TotalMinutes -gt 12) { $end = 'fail' }
    if ($end) {
      $this.Stop(); Set-Busy $false ''
      if ($end -eq 'ok') {
        $ui.Dot.Fill = New-Brush $colors.green; $ui.StatusTitle.Text = 'تم التثبيت بنجاح'
        $ui.StatusSub.Text = 'افتح تطبيق الديسكورد. إذا لم يكن مثبتاً نزّله من discord.com.'
        Say "تم التثبيت بنجاح ✔`n`nسيفتح الآن تطبيق Discord WARP من مكانه الدائم، وتجده لاحقاً في قائمة ابدأ وعلى سطح المكتب.`nيمكنك حذف مجلد التثبيت هذا." | Out-Null
        $lnk = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Discord WARP\Discord WARP.lnk'
        $script:quit = $true; $win.Close(); $mutex.ReleaseMutex()
        if (Test-Path $lnk) { Start-Process explorer.exe -ArgumentList "`"$lnk`"" }
        [Windows.Application]::Current.Shutdown()
      } else {
        $why = ($lines | Where-Object { $_ -match 'FAILED: ' } | Select-Object -Last 1) -replace '^\S+ FAILED: ', ''
        $ui.Dot.Fill = New-Brush $colors.red; $ui.StatusTitle.Text = $(if ($end -eq 'partial') { 'انتهى التثبيت مع مشكلة' } else { 'لم يكتمل التثبيت' })
        $ui.StatusSub.Text = "السجل: $script:instLog"
        Say "$($ui.StatusTitle.Text).`n$why`n`nأعد تشغيل الكمبيوتر وحاول مرة ثانية، أو أرسل ملف السجل:`n$script:instLog" 'Warning' | Out-Null
      } } })
  $t.Start() })

# ---- start ----
$refresh = New-Object Windows.Threading.DispatcherTimer; $refresh.Interval = [TimeSpan]::FromMinutes(3); $refresh.Add_Tick({ Update-Status }); $refresh.Start()
$pump.Start()
$firstRun = Join-Path $dw 'first-run.flag'
if (-not $isPackage -and (Test-Path $firstRun)) {   # first start after (re)install: welcome + where to go next
  Remove-Item $firstRun -Force -ErrorAction SilentlyContinue; $Tray = $false
  Clear-List 'مرحباً! تم التثبيت'
  Add-Row 'PASS' 'الإعداد جاهز ويعمل تلقائياً مع Windows، وهذه الأيقونة تبقى بجانب الساعة.'
  if (Test-Path $discordUpdate) { Add-Row 'INFO' 'الديسكورد مثبّت عندك: اضغط "فتح الديسكورد".' }
  else { Add-Row 'INFO' 'ليس عندك ديسكورد؟ اضغط "تحميل وتثبيت الديسكورد" (الزر البنفسجي).' }
  Add-Row 'INFO' 'تفضّل المتصفح؟ اضغط "الديسكورد من المتصفح".' }
Update-DiscordButtons
if ($Tray -and -not $isPackage) { Update-Status } else { Show-Main }
[void]$app.Run()
$notify.Visible = $false; $notify.Dispose()
