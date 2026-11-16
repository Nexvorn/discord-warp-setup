# Discord WARP v1.4 - engine supervisor. Runs as SYSTEM from the scheduled task "DiscordWARP-Engine" (at startup).
# - starts mihomo (%ProgramFiles%\DiscordWARP\mihomo.exe) with %ProgramData%\DiscordWARP\engine\config.yaml, restarts it if it exits
# - keeps the NRPT rule (Discord names -> 198.18.0.2) while running, removes it while paused
# - at boot: waits until Windows reports internet on a real network adapter before starting the engine (a tunnel
#   created while the network is still being identified stayed dead after a reboot, 2026-11-13)
# - other VPNs (v1.4): every 3 s checks which adapter Windows uses for internet traffic. While another full-tunnel VPN
#   (NordVPN, Windscribe, Proton, WireGuard, OpenVPN, the Cloudflare WARP app, ...) is connected, the engine is stopped and
#   the NRPT rule removed ("paused for another VPN" - Discord then simply uses that VPN). When the VPN has been gone for
#   ~20 s and the network is ready, the engine starts with a fresh tunnel. Background: WARP traffic that went out while NordVPN
#   connected/disconnected left the tunnel unusable for over an hour (2026-11-16, new connections needed 5-20 s).
# - network change (other adapter/gateway, back online): the tunnel is recreated once the network is ready
# - self-heal: 20 s after every start, then every 60 s: 4 delay tests (incl. opening the connection) to the Discord API
#   through WARP; after a failed round re-check every 30 s; 3 failed rounds in a row (2 within 3 min of a start) and no
#   active Discord call -> recreate the tunnel on the next WARP port (2408 -> 4500 -> 1701 -> 500; the ISP may throttle
#   one port, 2026-11-16); later attempts of the same failure streak wait 2, 5, 10, then 15 min; the working port is
#   remembered in engine\warp-port.txt (also over reinstalls/updates)
# - state for the app and verify.ps1: %ProgramData%\DiscordWARP\state.json  {state: running|paused|vpn, vpn: <name>}
# - commands from the app (no admin needed): files in %ProgramData%\DiscordWARP\cmd  ->  restart | pause | resume
# Never runs two engines with the same WARP key. ASCII only.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'DiscordWarpLib.ps1')   # other-VPN detection (Get-DwInternetRoute, Resolve-DwForeignVpn)
$prog = Join-Path $env:ProgramFiles 'DiscordWARP'
$data = Join-Path $env:ProgramData 'DiscordWARP'
$engDir = Join-Path $data 'engine'; $cfg = Join-Path $engDir 'config.yaml'
$cmdDir = Join-Path $data 'cmd'; $logDir = Join-Path $data 'logs'; $paused = Join-Path $data 'paused.flag'
$stateFile = Join-Path $data 'state.json'
$exe = Join-Path $prog 'mihomo.exe'
$pipe = 'discord-warp-mihomo'
New-Item -ItemType Directory -Force $logDir, $cmdDir | Out-Null
$log = Join-Path $logDir 'engine-supervisor.log'
function L([string]$m) {
  try { if ((Test-Path $log) -and (Get-Item $log).Length -gt 1MB) { Move-Item $log "$log.old" -Force }
        Add-Content -LiteralPath $log -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m" -Encoding UTF8 } catch {} }
$script:stateKey = ''
function Set-State([string]$s, [string]$vpn = '', [switch]$Force) {
  if ("$s|$vpn" -eq $script:stateKey -and -not $Force) { return }
  $script:stateKey = "$s|$vpn"
  try { Set-Content -LiteralPath $stateFile -Value (@{ state = $s; vpn = $vpn; since = (Get-Date -Format o) } | ConvertTo-Json -Compress) -Encoding UTF8 } catch {} }

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
# delay incl. opening the connection (unified-delay: false); -1 = failed or no answer within 5 s
function Get-DiscordDelay { $j = Invoke-Api '/proxies/WARP/delay?url=https%3A%2F%2Fdiscord.com%2Fapi%2Fv9%2Fgateway&timeout=5000'; try { $d = ($j | ConvertFrom-Json).delay; if ($d) { [int]$d } else { -1 } } catch { -1 } }
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
  $script:startedAt = Get-Date; $script:nextCheck = (Get-Date).AddSeconds(20); $script:failed = 0   # verify the new tunnel soon
  Set-State 'running' -Force   # new "since": the app shows "preparing the tunnel" for up to 90 s instead of an error
  L "engine started (mihomo pid $((Get-Process mihomo -ErrorAction SilentlyContinue | Select-Object -First 1).Id))" }
function Stop-Engine([string]$why) {
  if ($script:proc -and -not $script:proc.HasExited) { try { $script:proc.Kill(); [void]$script:proc.WaitForExit(5000) } catch {}; L "engine stopped ($why)" }
  Get-Process mihomo -ErrorAction SilentlyContinue | Stop-Process -Force
  $script:proc = $null }

function Wait-Network([int]$maxSec = 120) {
  $t0 = Get-Date
  while (((Get-Date) - $t0).TotalSeconds -lt $maxSec) {
    $p = @(Get-NetConnectionProfile -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceAlias -ne 'DiscordWARP' -and ($_.IPv4Connectivity -eq 'Internet' -or $_.IPv6Connectivity -eq 'Internet') })
    $r = Get-NetRoute -DestinationPrefix 0.0.0.0/0 -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceAlias -ne 'DiscordWARP' -and $_.NextHop -ne '0.0.0.0' }
    if ($p.Count -and $r) { L "network ready after $([int]((Get-Date) - $t0).TotalSeconds) s ($($p[0].InterfaceAlias))"; Start-Sleep 3; return }
    Start-Sleep 2 }
  L "network not reported ready after $maxSec s - starting anyway" }

# ---- WARP port: self-heal moves to the next port (2408 -> 4500 -> 1701 -> 500), the port that works is remembered ----
$portFile = Join-Path $engDir 'warp-port.txt'
function Get-WarpPort { try { Get-DwWarpPort ([IO.File]::ReadAllText($cfg)) } catch { 0 } }
function Set-WarpPort([int]$port) {
  try { $t = [IO.File]::ReadAllText($cfg); $n = Set-DwWarpPort $t $port
        if ($n -ne $t) { Write-Utf8NoBom $cfg $n; L "WARP endpoint port set to $($port)" } } catch { L "could not set the WARP port: $($_.Exception.Message)" } }
function Save-WarpPort { try { Set-Content -LiteralPath $portFile -Value (Get-WarpPort) -Encoding ASCII } catch {} }
function Use-NextWarpPort { $p = Get-DwNextWarpPort (Get-WarpPort); Set-WarpPort $p; return $p }

# ---- other VPN / network watch: route key = interface|prefix|next hop of the route to 1.1.1.1 ----
$script:routeKey = $null; $script:vpn = $null
function Update-Route {
  # returns $true when the internet route changed since the last call; sets $script:vpn ($null or the VPN name)
  $r = Get-DwInternetRoute
  $key = if ($r) { "$($r.InterfaceIndex)|$($r.DestinationPrefix)|$($r.NextHop)" } else { '' }
  if ($key -eq $script:routeKey) { return $false }
  $script:routeKey = $key   # classify only when the route changed (Get-NetAdapter ~100 ms)
  $script:vpn = if ($r) { Resolve-DwForeignVpn $r (Get-NetAdapter -IncludeHidden -InterfaceIndex $r.InterfaceIndex -ErrorAction SilentlyContinue) } else { $null }
  return $true }
function Enter-VpnPause {
  L "other VPN connected ($script:vpn; internet route $script:routeKey) - Discord WARP paused automatically until it disconnects"
  $script:vpnPaused = $true; $script:vpnClear = 0; Stop-Engine 'other VPN'; Set-Nrpt $false; Set-State 'vpn' $script:vpn }
function Start-Running([string]$why) {
  Wait-Network 60; Set-Nrpt $true; Start-Engine; $script:healStreak = 0; $script:nextHeal = [datetime]::MinValue; Set-State 'running'; if ($why) { L $why } }

L "=== supervisor start (version $(try { (Get-Content (Join-Path $data 'version.txt') -Raw).Trim() } catch { '?' }))"
$nextCheck = (Get-Date).AddMinutes(2); $failed = 0; $startedAt = Get-Date; $crash = 0; $lastCrash = [datetime]::MinValue
$script:vpnPaused = $false; $script:vpnClear = 0; $nextVpnCheck = Get-Date
$script:healStreak = 0; $script:nextHeal = [datetime]::MinValue; $healGapMin = 0, 2, 5, 10, 15   # minutes before the next recreation in one failure streak
$script:lastRoundFailed = $false
# a (re)install writes port 2408 again: go back to the port that worked last time
try { $saved = [int]((Get-Content $portFile -Raw -ErrorAction Stop).Trim()); if ($saved -and $saved -ne (Get-WarpPort)) { L "remembered WARP port $saved"; Set-WarpPort $saved } } catch {}
if (Test-Path $paused) { L 'paused by the user - engine not started'; Set-Nrpt $false; Set-State 'paused' }
else {
  Wait-Network; [void](Update-Route)
  if ($script:vpn) { Enter-VpnPause } else { Set-Nrpt $true; Start-Engine; Set-State 'running' } }

while ($true) {
  Start-Sleep -Seconds 2
  # ---- commands from the app ----
  foreach ($f in @(Get-ChildItem $cmdDir -File -ErrorAction SilentlyContinue)) {
    $c = $f.Name.ToLower(); Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue
    switch ($c) {
      'restart' { if ($script:vpnPaused) { L "app: repair ignored - paused for another VPN ($script:vpn)" }
                  else { L 'app: restart engine (repair)'; Stop-Engine 'repair'; Start-Sleep 1
                         if ($script:lastRoundFailed) { [void](Use-NextWarpPort) }   # the user repairs a slow/dead tunnel: also try the next port
                         if (-not (Test-Path $paused)) { Set-Nrpt $true; Start-Engine; $script:healStreak = 0; $script:nextHeal = [datetime]::MinValue } } }
      'pause'   { L 'app: pause'; Set-Content -LiteralPath $paused -Value (Get-Date -Format o) -Encoding ASCII; Stop-Engine 'pause'; Set-Nrpt $false; $script:vpnPaused = $false; Set-State 'paused' }
      'resume'  { L 'app: resume'; Remove-Item $paused -Force -ErrorAction SilentlyContinue; $script:routeKey = $null; [void](Update-Route)
                  if ($script:vpn) { Enter-VpnPause } else { Set-Nrpt $true; Start-Engine; Set-State 'running' } }
      default   { L "unknown command '$c' ignored" } } }
  if (Test-Path $paused) { Set-State 'paused'; continue }
  # ---- other VPN / network change (every 3 s) ----
  if ((Get-Date) -ge $nextVpnCheck) {
    $nextVpnCheck = (Get-Date).AddSeconds(3)
    $hadKey = $script:routeKey
    $changed = Update-Route
    if ($script:vpn) {
      if (-not $script:vpnPaused) { Enter-VpnPause }
      elseif ($changed) { L "other VPN still connected ($script:vpn; internet route $script:routeKey)"; Set-State 'vpn' $script:vpn }
      $script:vpnClear = 0; continue }
    if ($script:vpnPaused) {
      # VPN gone: wait until the internet route stayed on the real adapter for ~20 s (7 checks), then for the network.
      # A tunnel created ~10 s after NordVPN disconnected started slow twice (2026-11-16 19:50, 21:35); recreated later it was fine.
      $script:vpnClear++
      if ($changed) { $script:vpnClear = 1 }
      if ($script:vpnClear -lt 7) { continue }
      $script:vpnPaused = $false
      Start-Running "other VPN disconnected (internet route $script:routeKey) - Discord WARP resumed with a fresh tunnel"; continue }
    if ($changed -and $null -ne $hadKey -and $script:routeKey -and $script:proc -and -not $script:proc.HasExited) {
      L "network changed ($hadKey -> $script:routeKey) - recreating the WARP tunnel"
      Stop-Engine 'network change'; Start-Running ''; continue }
  }
  if ($script:vpnPaused) { continue }
  # ---- keep the engine alive ----
  if (-not $script:proc -or $script:proc.HasExited) {
    $code = try { $script:proc.ExitCode } catch { -1 }
    $crash = if (((Get-Date) - $lastCrash).TotalMinutes -lt 10) { $crash + 1 } else { 1 }; $lastCrash = Get-Date
    $wait = [Math]::Min(60, 5 * $crash); L "engine not running (exit $code) - restart in $wait s"
    Start-Sleep $wait; $script:proc = $null; Set-Nrpt $true; Start-Engine; continue }
  # ---- self-heal ----
  if ((Get-Date) -lt $nextCheck) { continue }
  $nextCheck = (Get-Date).AddSeconds(60)
  $res = @(); $good = 0; $moved = $false
  foreach ($i in 1..4) {
    $d = Get-DiscordDelay; $res += $(if ($d -lt 0) { 'fail' } else { $d }); if ($d -ge 0 -and $d -lt 2000) { $good++ }
    $k = $script:routeKey; if (Update-Route) { $script:routeKey = $k; $moved = $true; break }   # network/VPN changed: let the watch above handle it
    Start-Sleep 2 }
  if ($moved) { $nextCheck = Get-Date; continue }
  if ($good -ge 3) {
    if ($failed -or $script:healStreak -or $script:lastRoundFailed) { L "check OK again: $($res -join ',') (WARP port $(Get-WarpPort))"; Save-WarpPort }
    $failed = 0; $script:healStreak = 0; $script:nextHeal = [datetime]::MinValue; $script:lastRoundFailed = $false; continue }
  $script:lastRoundFailed = $true
  $need = if (((Get-Date) - $startedAt).TotalMinutes -lt 3) { 2 } else { 3 }   # a fresh tunnel that does not work is recreated sooner
  $failed++; L "check round failed ($failed/$need): $($res -join ',')"
  $nextCheck = (Get-Date).AddSeconds(30)
  if ($failed -lt $need) { continue }
  $failed = 0
  if ((Get-Date) -lt $script:nextHeal) { L "self-heal: next tunnel recreation not before $($script:nextHeal.ToString('HH:mm:ss'))"; continue }
  if (Test-InCall) { L 'self-heal: Discord call active - not restarting'; continue }
  $script:healStreak++
  $script:nextHeal = (Get-Date).AddMinutes($healGapMin[[Math]::Min($script:healStreak, $healGapMin.Count - 1)])
  Stop-Engine 'self-heal'; Start-Sleep 1
  $np = Use-NextWarpPort
  L "self-heal: recreating the WARP tunnel on port $np (attempt $script:healStreak of this failure; next one not before $($script:nextHeal.ToString('HH:mm:ss')))"
  Start-Engine
}
