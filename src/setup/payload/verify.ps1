# Discord-via-WARP health check. Read-only, no admin needed. Run after reboot, after any update, or anytime:
#   powershell -ExecutionPolicy Bypass -File %USERPROFILE%\.discord-warp\verify.ps1
$ok = 0; $fail = 0; $warn = 0
function Check($state, $msg) { $c = @{PASS='Green';FAIL='Red';WARN='Yellow';INFO='Gray'}[$state]; Write-Host ("[{0}] {1}" -f $state, $msg) -ForegroundColor $c
  switch ($state) { 'PASS' { $script:ok++ } 'FAIL' { $script:fail++ } 'WARN' { $script:warn++ } } }
$cvDir = "$env:APPDATA\io.github.clash-verge-rev.clash-verge-rev"
$expectRoutes = '198.18.0.0/16','66.22.192.0/18','195.62.89.0/24','104.28.0.0/15'

# 1. components
$svc = Get-Service clash_verge_service -ErrorAction SilentlyContinue
if ($svc.Status -eq 'Running') { Check PASS "Clash Verge service running ($($svc.StartType))" } else { Check FAIL "Clash Verge service not running" }
if (Get-Process clash-verge -ErrorAction SilentlyContinue) { Check PASS "Clash Verge app running" } else { Check FAIL "Clash Verge app not running (start it from the Start menu)" }
$core = Get-Process verge-mihomo -ErrorAction SilentlyContinue
if ($core) { Check PASS "mihomo core running" } else { Check FAIL "mihomo core not running" }
$meta = Get-NetAdapter -Name Meta -ErrorAction SilentlyContinue
if ($meta.Status -eq 'Up') { Check PASS "TUN adapter 'Meta' up" } else { Check FAIL "TUN adapter 'Meta' missing/down (TUN mode off?)" }

# 2. routing: only Discord ranges in TUN, default route on physical NIC
if ($meta) {
  $have = @(Get-NetRoute -InterfaceIndex $meta.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object NextHop -eq '198.18.0.2').DestinationPrefix
  $missing = $expectRoutes | Where-Object { $have -notcontains $_ }
  $extra = $have | Where-Object { $expectRoutes -notcontains $_ }
  if (-not $missing) { Check PASS "TUN routes present: $($expectRoutes -join ', ')" } else { Check FAIL "TUN routes missing: $($missing -join ', ')" }
  if ($extra) { Check WARN "unexpected extra TUN routes: $($extra -join ', ')" }
}
$def = Get-NetRoute -DestinationPrefix 0.0.0.0/0 -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1
if ($def -and $def.InterfaceAlias -ne 'Meta') { Check PASS "default route via $($def.InterfaceAlias) ($($def.NextHop)) - other apps not in TUN" } else { Check FAIL "default route goes through the TUN!" }

# 3. DNS: NRPT for Discord only, system DNS untouched
$nrpt = @(Get-DnsClientNrptRule | Where-Object Comment -eq 'DiscordWARP')
if ($nrpt.Count) { Check PASS "NRPT Discord rule present ($(@($nrpt.Namespace).Count) namespaces -> $($nrpt[0].NameServers))" } else { Check FAIL "NRPT Discord rule missing (run nrpt-add.ps1 as admin)" }
$metaDns = (Get-DnsClientServerAddress -InterfaceAlias Meta -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses
if (-not $metaDns) { Check PASS "TUN does not take over system DNS" } else { Check WARN "TUN adapter has DNS $metaDns (dns-mode changed?)" }
Clear-DnsClientCache
$d = (Resolve-DnsName discord.com -Type A -ErrorAction SilentlyContinue | Where-Object Type -eq A | Select-Object -First 1).IPAddress
$g = (Resolve-DnsName www.google.com -Type A -ErrorAction SilentlyContinue | Where-Object Type -eq A | Select-Object -First 1).IPAddress
if ($d -like '198.18.*') { Check PASS "discord.com -> $d (via mihomo)" } else { Check FAIL "discord.com -> $d (not via mihomo)" }
if ($g -and $g -notlike '198.18.*') { Check PASS "www.google.com -> $g (normal DNS)" } else { Check FAIL "www.google.com -> $g" }

# 4. other apps use the original connection
$t = curl.exe -s --max-time 10 https://1.1.1.1/cdn-cgi/trace
$ip = ($t | Select-String '^ip=').Line; $w = ($t | Select-String '^warp=').Line
if ($w -eq 'warp=off') { Check PASS "other apps: $ip $w (original ISP connection)" } else { Check FAIL "other apps: $ip $w" }

# 5. WARP tunnel health (mihomo API, via local named pipe)
$api = Join-Path $PSScriptRoot 'mihomo-conns.ps1'
try {
  $px = & $api -ApiPath '/proxies/WARP' -Raw | ConvertFrom-Json
  $dl = & $api -ApiPath '/proxies/WARP/delay?url=https%3A%2F%2Fwww.cloudflare.com%2Fcdn-cgi%2Ftrace&timeout=6000' -Raw | ConvertFrom-Json
  if ($dl.delay) { Check PASS "WARP tunnel reachable (delay $($dl.delay) ms)" } else { Check FAIL "WARP tunnel test failed: $($dl.message)" }
  # added 2026-11-11: Cloudflare's own sites can work while traffic to Discord through WARP fails (TEST_LOG T-56)
  $dd = & $api -ApiPath '/proxies/WARP/delay?url=https%3A%2F%2Fdiscord.com%2Fapi%2Fv9%2Fgateway&timeout=6000' -Raw | ConvertFrom-Json
  if ($dd.delay -and $dd.delay -lt 300) { Check PASS "Discord API via WARP ($($dd.delay) ms)" } elseif ($dd.delay) { Check WARN "Discord API via WARP slow ($($dd.delay) ms)" } else { Check FAIL "Discord API via WARP failed: $($dd.message)" }
  $grp = & $api -ApiPath '/proxies/DISCORD' -Raw | ConvertFrom-Json
  if ((@($grp.all) -join ',') -eq 'WARP') { Check PASS "DISCORD group = WARP only (no DIRECT fallback)" } else { Check FAIL "DISCORD group members: $($grp.all -join ',')" }
  $conns = & $api
  $dc = @($conns | Where-Object proc -eq 'Discord.exe')
  $bad = @($dc | Where-Object chain -notmatch 'WARP')
  $nonDiscord = @($conns | Where-Object { $_.chain -match 'WARP' -and $_.proc -notmatch '^(Discord\.exe|chrome\.exe|msedge\.exe)$' })
  if (Get-Process Discord -ErrorAction SilentlyContinue) {
    if ($dc.Count -and -not $bad.Count) { Check PASS "Discord app: $($dc.Count) live connections, all via WARP" } elseif ($bad.Count) { Check FAIL "Discord connections NOT via WARP: $($bad.Count)" } else { Check INFO "Discord running but idle (no connections right now)" }
  } else { Check INFO "Discord app not running (skip live connection check)" }
  if ($nonDiscord.Count) { Check WARN "non-Discord processes using WARP: $(($nonDiscord.proc | Sort-Object -Unique) -join ', ')" } else { Check PASS "no non-Discord process uses WARP" }
} catch { Check FAIL "mihomo API not reachable: $($_.Exception.Message)" }

# 6. last Discord call: media source address as seen by Discord's media server
$log = "$env:APPDATA\discord\logs\renderer_js.log"
if (Test-Path $log) {
  $last = Select-String -Path $log -Pattern 'Connected with local address ([\d\.]+):\d+ and protocol: udp' | Select-Object -Last 1
  if ($last) { $src = $last.Matches[0].Groups[1].Value; $when = $last.Line.Substring(1,19)
    $isp = ($ip -replace 'ip=','')
    if ($src -eq $isp) { Check FAIL "last call ($when): media server saw your ISP address $src -> LEAK" }
    elseif ($src -like '104.28.*' -or $src -like '104.29.*') { Check PASS "last call ($when): media server saw WARP address $src" }
    else { Check WARN "last call ($when): media source address $src (unknown range - check)" }
    $srv = (Select-String -Path $log -Pattern 'RTC connected to media server: ([\d\.]+):' | Select-Object -Last 1).Matches[0].Groups[1].Value
    $rt = (Find-NetRoute -RemoteIPAddress $srv -ErrorAction SilentlyContinue | Where-Object DestinationPrefix | Select-Object -First 1)
    if ($rt.InterfaceAlias -eq 'Meta') { Check PASS "last media server $srv is routed into the TUN ($($rt.DestinationPrefix))" } else { Check FAIL "last media server $srv routes via $($rt.InterfaceAlias) -> new media range! add it to route-address" }
  } else { Check INFO "no voice call found in Discord log yet" }
}

# 7. version drift (informational)
$dv = (Get-ChildItem "$env:LOCALAPPDATA\Discord\app-*" -Directory | Sort-Object Name | Select-Object -Last 1).Name
$mv = ((& "C:\Program Files\Clash Verge\verge-mihomo.exe" -v) -split ' ')[2]
Check INFO "Discord $dv | mihomo $mv | Clash Verge $((Get-Item 'C:\Program Files\Clash Verge\clash-verge.exe').VersionInfo.ProductVersion)"
Write-Host ""; Write-Host "RESULT: $ok passed, $warn warnings, $fail failed" -ForegroundColor $(if ($fail) {'Red'} elseif ($warn) {'Yellow'} else {'Green'})
