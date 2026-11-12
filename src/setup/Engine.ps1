# Discord WARP v1.3 - engine supervisor. Runs as SYSTEM from the scheduled task "DiscordWARP-Engine" (at startup).
# - starts mihomo (%ProgramFiles%\DiscordWARP\mihomo.exe) with %ProgramData%\DiscordWARP\engine\config.yaml, restarts it if it exits
# - keeps the NRPT rule (Discord names -> 198.18.0.2) while running, removes it while paused
# - self-heal: every 2 min 4 delay tests to the Discord API through WARP; 3 failed rounds in a row and no active
#   Discord call -> recreate the tunnel (restart mihomo), at most 3 times per hour
# - commands from the app (no admin needed): files in %ProgramData%\DiscordWARP\cmd  ->  restart | pause | resume
# Never runs two engines with the same WARP key. ASCII only.
$ErrorActionPreference = 'Continue'
$prog = Join-Path $env:ProgramFiles 'DiscordWARP'
$data = Join-Path $env:ProgramData 'DiscordWARP'
$engDir = Join-Path $data 'engine'; $cfg = Join-Path $engDir 'config.yaml'
$cmdDir = Join-Path $data 'cmd'; $logDir = Join-Path $data 'logs'; $paused = Join-Path $data 'paused.flag'
$exe = Join-Path $prog 'mihomo.exe'
$pipe = 'discord-warp-mihomo'
New-Item -ItemType Directory -Force $logDir, $cmdDir | Out-Null
$log = Join-Path $logDir 'engine-supervisor.log'
function L([string]$m) {
  try { if ((Test-Path $log) -and (Get-Item $log).Length -gt 1MB) { Move-Item $log "$log.old" -Force }
        Add-Content -LiteralPath $log -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m" -Encoding UTF8 } catch {} }

$domains = 'discord.com', 'discordapp.com', 'discordapp.net', 'discord.gg', 'discord.media', 'discordcdn.com', 'discordstatus.com', 'discord.co', 'discord.dev', 'discord.gift', 'discord.new', 'dis.gd'
function Set-Nrpt([bool]$on) {
  $r = @(Get-DnsClientNrptRule | Where-Object Comment -eq 'DiscordWARP')
  if ($on -and -not $r.Count) {
    $ns = @(); foreach ($d in $domains) { $ns += $d; $ns += ".$d" }; $ns += 'discord-attachments-uploads-prd.storage.googleapis.com'
    Add-DnsClientNrptRule -Namespace $ns -NameServers '198.18.0.2' -Comment 'DiscordWARP' -DisplayName 'Discord via WARP' | Out-Null; L 'NRPT added' }
  elseif (-not $on -and $r.Count) { $r | ForEach-Object { Remove-DnsClientNrptRule -Name $_.Name -Force }; L 'NRPT removed' }
  Clear-DnsClientCache }

function Get-Secret { try { (Get-Content (Join-Path $data 'api-secret.txt') -Raw).Trim() } catch { '' } }
function Invoke-Api([string]$path, [int]$timeoutMs = 6000) {
  try {
    $c = New-Object IO.Pipes.NamedPipeClientStream('.', $pipe, [IO.Pipes.PipeDirection]::InOut); $c.Connect(3000)
    $w = New-Object IO.StreamWriter($c); $w.NewLine = "`r`n"
    $w.WriteLine("GET $path HTTP/1.1"); $w.WriteLine('Host: localhost'); $w.WriteLine("Authorization: Bearer $(Get-Secret)"); $w.WriteLine('Connection: close'); $w.WriteLine(''); $w.Flush()
    $r = (New-Object IO.StreamReader($c)).ReadToEnd(); $c.Close()
    $body = $r.Substring($r.IndexOf("`r`n`r`n") + 4)
    if ($r -match 'Transfer-Encoding: chunked') { $sb = New-Object Text.StringBuilder; $i = 0
      while ($i -lt $body.Length) { $nl = $body.IndexOf("`r`n", $i); if ($nl -lt 0) { break }; $n = [Convert]::ToInt32($body.Substring($i, $nl - $i), 16); if ($n -eq 0) { break }; [void]$sb.Append($body.Substring($nl + 2, $n)); $i = $nl + 2 + $n + 2 }
      $body = $sb.ToString() }
    return $body } catch { return $null } }
function Get-DiscordDelay { $j = Invoke-Api '/proxies/WARP/delay?url=https%3A%2F%2Fdiscord.com%2Fapi%2Fv9%2Fgateway&timeout=3000'; try { $d = ($j | ConvertFrom-Json).delay; if ($d) { [int]$d } else { -1 } } catch { -1 } }
function Test-InCall {
  try { $c = (Invoke-Api '/connections') | ConvertFrom-Json
        [bool](@($c.connections | Where-Object { $_.metadata.process -eq 'Discord.exe' -and $_.metadata.network -eq 'udp' -and $_.metadata.destinationIP -match '^(104\.(28|29)\.|66\.22\.|195\.62\.89\.)' }).Count) } catch { $false } }

$script:proc = $null
function Start-Engine {
  if ($script:proc -and -not $script:proc.HasExited) { return }
  Get-Process mihomo -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep 1   # never two engines with the same WARP key
  # engine output goes straight to engine.log through cmd.exe (a redirected pipe that nobody drains could block the engine);
  # the config uses log-level warning, and the log is rotated before each start
  $elog = Join-Path $logDir 'engine.log'; if ((Test-Path $elog) -and (Get-Item $elog).Length -gt 2MB) { Move-Item $elog "$elog.old" -Force }
  $psi = New-Object Diagnostics.ProcessStartInfo "$env:SystemRoot\System32\cmd.exe", "/d /c `"`"$exe`" -d `"$engDir`" -f `"$cfg`" >> `"$elog`" 2>&1`""
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.WorkingDirectory = $engDir
  $script:proc = [Diagnostics.Process]::Start($psi)   # cmd.exe waits for mihomo, so HasExited = engine exited
  Start-Sleep 2
  L "engine started (mihomo pid $((Get-Process mihomo -ErrorAction SilentlyContinue | Select-Object -First 1).Id))" }
function Stop-Engine([string]$why) {
  if ($script:proc -and -not $script:proc.HasExited) { try { $script:proc.Kill(); [void]$script:proc.WaitForExit(5000) } catch {}; L "engine stopped ($why)" }
  Get-Process mihomo -ErrorAction SilentlyContinue | Stop-Process -Force
  $script:proc = $null }

L "=== supervisor start (version $(try { (Get-Content (Join-Path $data 'version.txt') -Raw).Trim() } catch { '?' }))"
if (Test-Path $paused) { L 'paused by the user - engine not started'; Set-Nrpt $false } else { Set-Nrpt $true; Start-Engine }
$nextCheck = (Get-Date).AddMinutes(2); $failed = 0; $restarts = 0; $hour = Get-Date; $crash = 0; $lastCrash = [datetime]::MinValue

while ($true) {
  Start-Sleep -Seconds 2
  # ---- commands from the app ----
  foreach ($f in @(Get-ChildItem $cmdDir -File -ErrorAction SilentlyContinue)) {
    $c = $f.Name.ToLower(); Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue
    switch ($c) {
      'restart' { L 'app: restart engine (repair)'; Stop-Engine 'repair'; Start-Sleep 1; if (-not (Test-Path $paused)) { Set-Nrpt $true; Start-Engine } }
      'pause'   { L 'app: pause'; Set-Content -LiteralPath $paused -Value (Get-Date -Format o) -Encoding ASCII; Stop-Engine 'pause'; Set-Nrpt $false }
      'resume'  { L 'app: resume'; Remove-Item $paused -Force -ErrorAction SilentlyContinue; Set-Nrpt $true; Start-Engine }
      default   { L "unknown command '$c' ignored" } } }
  if (Test-Path $paused) { continue }
  # ---- keep the engine alive ----
  if (-not $script:proc -or $script:proc.HasExited) {
    $code = try { $script:proc.ExitCode } catch { -1 }
    $crash = if (((Get-Date) - $lastCrash).TotalMinutes -lt 10) { $crash + 1 } else { 1 }; $lastCrash = Get-Date
    $wait = [Math]::Min(60, 5 * $crash); L "engine not running (exit $code) - restart in $wait s"
    Start-Sleep $wait; $script:proc = $null; Set-Nrpt $true; Start-Engine; $nextCheck = (Get-Date).AddMinutes(2); continue }
  # ---- self-heal ----
  if ((Get-Date) -lt $nextCheck) { continue }
  $nextCheck = (Get-Date).AddMinutes(2)
  $res = @(); $good = 0
  1..4 | ForEach-Object { $d = Get-DiscordDelay; $res += $(if ($d -lt 0) { 'fail' } else { $d }); if ($d -ge 0 -and $d -lt 300) { $good++ }; Start-Sleep 2 }
  if ($good -ge 3) { if ($failed) { L "check OK again: $($res -join ',')" }; $failed = 0; continue }
  $failed++; L "check round failed ($failed/3): $($res -join ',')"
  if ($failed -lt 3) { continue }
  $failed = 0
  if (((Get-Date) - $hour).TotalHours -ge 1) { $hour = Get-Date; $restarts = 0 }
  if ($restarts -ge 3) { L 'self-heal: limit of 3 restarts per hour reached - waiting'; continue }
  if (Test-InCall) { L 'self-heal: Discord call active - not restarting'; continue }
  $restarts++; L "self-heal: recreating the WARP tunnel (restart $restarts/3 this hour)"
  Stop-Engine 'self-heal'; Start-Sleep 1; Start-Engine
}
