# DiscordWARP Self-Heal - runs ONCE, 2 minutes after logon (user-level task, no admin, no periodic runs).
# Recreates the WARP WireGuard tunnel (by restarting Clash Verge) ONLY if it is confirmed broken,
# never during an active Discord call, at most 3 attempts. Otherwise it only logs (and alerts if it cannot fix).
# Touches nothing else: no config, protocol, DNS, routes, firewall or other programs.
$log = "$PSScriptRoot\selfheal.log"
$api = "$PSScriptRoot\mihomo-conns.ps1"
function Write-HealLog($t) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $t" | Out-File $log -Append -Encoding utf8 }
function Show-Alert($t) { msg.exe $env:USERNAME /TIME:0 "Discord WARP: $t" 2>$null }
if ((Test-Path $log) -and (Get-Item $log).Length -gt 512KB) { Move-Item $log "$log.old" -Force }
if (Test-Path "$PSScriptRoot\paused.flag") { Write-HealLog 'paused by the user (Discord WARP app) - nothing to do'; return }

# One round = 4 delay tests through WARP to the Discord API; round passes if >= 3 succeed under 300 ms.
# v3 (2026-11-11): was cp.cloudflare.com + 800 ms - that passed a slow tunnel (500-900 ms) and a tunnel that only
# reached Cloudflare's own sites while Discord timed out (TEST_LOG T-50, T-56).
function Test-Round {
  $good = 0; $res = @()
  1..4 | ForEach-Object {
    $d = 'fail'
    try { $r = & $api -ApiPath '/proxies/WARP/delay?url=https%3A%2F%2Fdiscord.com%2Fapi%2Fv9%2Fgateway&timeout=3000' -Raw | ConvertFrom-Json
      if ($r.delay) { $d = [int]$r.delay; if ($d -lt 300) { $good++ } } } catch {}
    $res += $d; Start-Sleep 3 }
  return @{ pass = ($good -ge 3); detail = ($res -join ',') }
}
# Broken only if 3 consecutive rounds (30 s apart) all fail.
function Test-Broken {
  for ($i = 1; $i -le 3; $i++) {
    $r = Test-Round
    Write-HealLog "  check round $i : delays(ms)=$($r.detail) -> $(if ($r.pass) {'OK'} else {'FAIL'})"
    if ($r.pass) { return $false }
    if ($i -lt 3) { Start-Sleep 30 }
  }
  return $true
}
function Test-InCall {
  try { $c = & $api; return [bool](@($c | Where-Object { $_.proc -eq 'Discord.exe' -and $_.net -eq 'udp' -and $_.dst -match '^(104\.(28|29)\.|66\.22\.|195\.62\.89\.)' }).Count) } catch { return $false }
}

Write-HealLog "=== logon check started ==="
# wait (up to 3 min) for Clash Verge + core, started by its own autostart
$t0 = Get-Date
while (-not ((Get-Process clash-verge -ErrorAction SilentlyContinue) -and (Get-Process verge-mihomo -ErrorAction SilentlyContinue)) -and ((Get-Date)-$t0).TotalMinutes -lt 3) { Start-Sleep 5 }
if (-not (Get-Process clash-verge -ErrorAction SilentlyContinue)) { Write-HealLog "Clash Verge not running - nothing to do"; Show-Alert "Clash Verge did not start. Open it from the Start menu."; return }
$cores = @(Get-Process verge-mihomo -ErrorAction SilentlyContinue).Count
if ($cores -ne 1) { Write-HealLog "unexpected number of mihomo cores: $cores - not touching anything"; Show-Alert "unexpected Clash state ($cores cores). Run verify.ps1."; return }
Start-Sleep 15
$direct = curl.exe -s --max-time 6 -o NUL -w "%{http_code}" http://cp.cloudflare.com/generate_204
if ($direct -ne '204') { Write-HealLog "internet itself is down (direct=$direct) - not a WARP problem, skipping"; return }

if (-not (Test-Broken)) { Write-HealLog "WARP healthy - done"; return }
Write-HealLog "WARP confirmed broken (3 failed rounds)"
$wait = @(0, 60, 120)
for ($a = 1; $a -le 3; $a++) {
  if ($wait[$a-1]) { Start-Sleep $wait[$a-1] }
  if (Test-InCall) { Write-HealLog "attempt $a skipped: Discord call active - will not restart during a call"; Show-Alert "WARP tunnel is degraded but you are in a call; not restarting. If audio is bad, quit and reopen Clash Verge."; return }
  Write-HealLog "attempt $a : restarting Clash Verge to recreate the tunnel"
  Stop-Process -Name clash-verge -Force -ErrorAction SilentlyContinue; Start-Sleep 2
  Start-Process 'C:\Program Files\Clash Verge\clash-verge.exe'; Start-Sleep 25
  $cores = @(Get-Process verge-mihomo -ErrorAction SilentlyContinue).Count
  Write-HealLog "attempt $a : mihomo cores after restart = $cores"
  if ($cores -ne 1) { Write-HealLog "unexpected core count - stopping"; Show-Alert "unexpected Clash state after restart. Run verify.ps1."; return }
  if (-not (Test-Broken)) { Write-HealLog "attempt $a : HEALED"; return }
}
Write-HealLog "still broken after 3 attempts - giving up"
Show-Alert "WARP tunnel is not working after 3 attempts. Discord may not connect. Run verify.ps1 or tell Claude."
