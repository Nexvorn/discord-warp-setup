# DiscordWARP-Setup shared functions (PowerShell 5.1, ASCII only).
# Pure text/file helpers so they can be unit-tested without touching the live system.
# NEVER print secret values (private key). Callers log only presence/lengths.

$script:DW_Uid        = 'LdiscordWarp01'
# Bundled binaries (official GitHub releases; SHA-256 = GitHub API asset digest, checked 2026-11-11)
$script:DW_Bins = [ordered]@{
  # official mihomo engine (MetaCubeX), x86-64 "compatible" build; allowed by Windows Smart App Control (tested 2026-11-12)
  'mihomo-windows-amd64-compatible-v1.19.33.zip' = @{ sha = '7aaf636a4f2172dcd8ec34ac4f52797b059195e5afd6409508c963e545f8864d'; url = 'https://github.com/MetaCubeX/mihomo/releases/download/v1.19.33/mihomo-windows-amd64-compatible-v1.19.33.zip' }
  'wgcf_2.3.1_windows_amd64.exe'                 = @{ sha = 'e222fd9443d7cb3264d825a3e86967797fc9c938507c5d93e3cc21e4aed11dcc'; url = 'https://github.com/ViRb3/wgcf/releases/download/v2.3.1/wgcf_2.3.1_windows_amd64.exe' }
}
$script:DW_RouteAddr  = @('198.18.0.0/16', 'fdfe:dcba:9876::/64', '66.22.192.0/18', '195.62.89.0/24', '104.28.0.0/15', '2a0e:5940::/29')
$script:DW_NrptDomains = @('discord.com', 'discordapp.com', 'discordapp.net', 'discord.gg', 'discord.media', 'discordcdn.com',
                           'discordstatus.com', 'discord.co', 'discord.dev', 'discord.gift', 'discord.new', 'dis.gd')

function Write-Utf8NoBom([string]$Path, [string]$Text) {
  $d = Split-Path $Path
  if ($d -and -not (Test-Path $d)) { New-Item -ItemType Directory -Force $d | Out-Null }
  [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}
function Read-TextNoBom([string]$Path) {
  $t = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
  if ($t.Length -and $t[0] -eq [char]0xFEFF) { $t = $t.Substring(1) }
  return $t
}
function Split-Lines([string]$Text) { return ,@($Text -split "`r?`n") }

function Get-WgcfValues([string]$ConfPath) {
  # Parses a wgcf-profile.conf. Handles "Address = v4/32, v6/128" and separate Address lines.
  $conf = Get-Content -LiteralPath $ConfPath
  function V($name) { ($conf | Where-Object { $_ -match "^\s*$name\s*=" } | Select-Object -First 1) -replace "^\s*$name\s*=\s*", '' }
  $addr = $conf | Where-Object { $_ -match '^\s*Address\s*=' } | ForEach-Object { ($_ -replace '^\s*Address\s*=\s*', '') -split '\s*,\s*' }
  $o = [pscustomobject]@{
    priv = (V 'PrivateKey').Trim()
    peer = (V 'PublicKey').Trim()
    v4   = (($addr | Where-Object { $_ -match '\.' } | Select-Object -First 1) -replace '/\d+$', '').Trim()
    v6   = (($addr | Where-Object { $_ -match ':' } | Select-Object -First 1) -replace '/\d+$', '').Trim()
  }
  foreach ($k in 'priv', 'peer', 'v4') { if (-not $o.$k) { throw "wgcf profile incomplete: '$k' missing" } }
  if ($o.priv -notmatch '^[A-Za-z0-9+/]{42,43}=?$') { throw 'wgcf profile: private key has unexpected format' }
  return $o
}

function New-ProfileText([string]$Template, $Wg, [string]$BootstrapDns) {
  $t = $Template.Replace('__WG_STAMP__', (Get-Date -Format 'yyyy-MM-dd HH:mm'))
  $t = $t.Replace('__WG_IPV4__', $Wg.v4).Replace('__WG_PEER_PUBLIC_KEY__', $Wg.peer).Replace('__WG_BOOTSTRAP_DNS__', $BootstrapDns)
  if ($Wg.v6) { $t = $t.Replace('__WG_IPV6__', $Wg.v6) } else { $t = ($t -split "`n" | Where-Object { $_ -notmatch '__WG_IPV6__' }) -join "`n" }
  $t = $t.Replace('__WG_PRIVATE_KEY__', $Wg.priv)
  if ($t -match '__WG_') { throw 'profile template: unreplaced placeholder' }
  return ($t -replace "`r`n", "`n")
}

function Update-TunBlock([string]$Text) {
  # Replaces the top-level "tun:" block of Clash Verge's config.yaml with the Discord-only TUN settings.
  # Keeps the existing "enable" and "stack" values (Clash Verge manages them; its default stack is "mips").
  $lines = Split-Lines $Text
  $start = -1; for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^tun:\s*$') { $start = $i; break } }
  $enable = 'false'; $stack = 'mips'
  $end = $start
  if ($start -ge 0) {
    $end = $start + 1
    while ($end -lt $lines.Count -and ($lines[$end] -match '^\s' -or $lines[$end] -eq '')) {
      if ($lines[$end] -match '^\s+enable:\s*(\S+)') { $enable = $Matches[1] }
      if ($lines[$end] -match '^\s+stack:\s*(\S+)') { $stack = $Matches[1] }
      $end++
    }
  }
  $block = @('tun:', "  enable: $enable", "  stack: $stack", '  auto-route: true', '  strict-route: false', '  auto-detect-interface: true',
             '  dns-mode: disabled', '  dns-hijack:', '  - 198.18.0.2:53', '  route-address:') + ($script:DW_RouteAddr | ForEach-Object { "  - $_" })
  if ($start -ge 0) {
    $before = if ($start -gt 0) { $lines[0..($start - 1)] } else { @() }
    $after = if ($end -lt $lines.Count) { $lines[$end..($lines.Count - 1)] } else { @() }
    $new = @($before) + $block + @($after)
  } else {
    $idx = -1; for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^secret:') { $idx = $i; break } }
    if ($idx -gt 0) { $new = @($lines[0..($idx - 1)]) + $block + @($lines[$idx..($lines.Count - 1)]) }
    else { $new = @($lines | Where-Object { $_ -ne '' }) + $block }
  }
  return (($new -join "`n").TrimEnd() + "`n")
}

function Set-YamlTopKeys([string]$Text, [hashtable]$Values) {
  # Sets simple top-level "key: value" lines (verge.yaml); appends missing keys.
  $lines = [Collections.Generic.List[string]](Split-Lines $Text.TrimEnd())
  foreach ($k in $Values.Keys) {
    $found = $false
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match ('^' + [regex]::Escape($k) + ':(\s|$)')) { $lines[$i] = "${k}: $($Values[$k])"; $found = $true; break } }
    if (-not $found) { $lines.Add("${k}: $($Values[$k])") }
  }
  return (($lines -join "`n") + "`n")
}

function Update-ProfilesYaml([string]$Text, [long]$Unix) {
  # Registers the Discord-WARP local profile in Clash Verge's profiles.yaml and makes it current.
  $uid = $script:DW_Uid
  $item = @("- uid: $uid", '  type: local', '  name: Discord-WARP', '  desc: Discord only via Cloudflare WARP (WireGuard); everything else untouched',
            "  file: $uid.yaml", "  updated: $Unix")
  $lines = Split-Lines $Text.TrimEnd()   # (Split-Lines already returns an array; @() would nest it)
  $hasItem = [bool]($lines | Where-Object { $_ -match "^\s*-?\s*uid:\s*$uid\s*$" })
  $itemsIdx = -1; for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^items:') { $itemsIdx = $i; break } }
  if (-not $hasItem) {
    if ($itemsIdx -lt 0) { $lines = @($lines) + @('items:') + $item }
    elseif ($lines[$itemsIdx] -match '^items:\s*(null|\[\])?\s*$' -and $lines[$itemsIdx] -notmatch '^items:\s*$') {
      $lines[$itemsIdx] = 'items:'
      $before = $lines[0..$itemsIdx]; $after = if ($itemsIdx + 1 -lt $lines.Count) { $lines[($itemsIdx + 1)..($lines.Count - 1)] } else { @() }
      $lines = @($before) + $item + @($after)
    } else {
      $before = $lines[0..$itemsIdx]; $after = if ($itemsIdx + 1 -lt $lines.Count) { $lines[($itemsIdx + 1)..($lines.Count - 1)] } else { @() }
      $lines = @($before) + $item + @($after)
    }
  }
  $cur = -1; for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^current:') { $cur = $i; break } }
  if ($cur -ge 0) { $lines[$cur] = "current: $uid" } else { $lines = @("current: $uid") + @($lines) }
  return (($lines -join "`n") + "`n")
}

function Get-BootstrapDns {
  # IPv4 DNS server of the interface that carries the default route (router/ISP DNS), else the gateway.
  $def = Get-NetRoute -DestinationPrefix 0.0.0.0/0 -ErrorAction SilentlyContinue | Sort-Object { $_.RouteMetric + (Get-NetIPInterface -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).InterfaceMetric } | Select-Object -First 1
  if (-not $def) { return $null }
  $dns = (Get-DnsClientServerAddress -InterfaceIndex $def.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1
  if ($dns) { return $dns }
  return $def.NextHop
}

# ---------- other VPN detection (v1.4) ----------
# A full-tunnel VPN (NordVPN, Windscribe, Proton VPN, WireGuard, OpenVPN, the Cloudflare WARP app, a Windows VPN connection, ...)
# is "connected" when Windows would send ordinary internet traffic (probe 1.1.1.1) through a virtual adapter instead of the
# real network adapter - whether the VPN replaced the default route or added 0.0.0.0/1 + 128.0.0.0/1 (OpenVPN "def1").
# Virtual adapters that can carry the real connection (Hyper-V external switch, bridge, NIC team, USB tethering) are not VPNs.
# Our own TUN "DiscordWARP" only carries Discord ranges, so it is never the route to 1.1.1.1.
$script:DW_RealVirtual = 'Hyper-V Virtual Ethernet|Network Adapter Multiplexor|MAC Bridge|Remote NDIS|Mobile Broadband|Wi-Fi Direct'
$script:DW_VpnNames = [ordered]@{
  'NordLynx|NordVPN' = 'NordVPN'; 'Windscribe' = 'Windscribe'; 'Proton' = 'Proton VPN'; 'ExpressVPN|Lightway' = 'ExpressVPN'
  'Mullvad' = 'Mullvad VPN'; 'Surfshark' = 'Surfshark'; 'Cloudflare' = 'Cloudflare WARP'; 'Private Internet Access|\bPIA\b' = 'Private Internet Access'
  'Hotspot Shield|Hydra|AnchorFree' = 'Hotspot Shield'; 'TunnelBear' = 'TunnelBear'; 'CyberGhost' = 'CyberGhost'; 'IPVanish' = 'IPVanish'
  'PureVPN' = 'PureVPN'; 'hide\.me' = 'hide.me'; 'Psiphon' = 'Psiphon'; 'Urban' = 'Urban VPN'; 'Tailscale' = 'Tailscale'; 'ZeroTier' = 'ZeroTier'
  'Kaspersky' = 'Kaspersky VPN'; 'Avast|AVG' = 'Avast VPN'; 'Norton' = 'Norton VPN'; 'Bitdefender' = 'Bitdefender VPN'; 'Planet' = 'PlanetVPN'
  'WireGuard' = 'WireGuard'; 'TAP-Windows|OpenVPN|ovpn-dco' = 'OpenVPN'; 'WAN Miniport' = 'Windows VPN'
}
function Get-DwVpnName([string]$Name, [string]$Description) {
  foreach ($k in $script:DW_VpnNames.Keys) { if ("$Name $Description" -match $k) { return $script:DW_VpnNames[$k] } }
  if ($Name) { return $Name }; if ($Description) { return $Description }; return 'VPN'
}
function Resolve-DwForeignVpn($Route, $Adapter) {
  # Pure (unit-tested): $Route = best route to an internet address (InterfaceAlias, InterfaceIndex), $Adapter = the
  # Get-NetAdapter object of that interface or $null. Returns $null (no other VPN) or the VPN's display name.
  if (-not $Route) { return $null }                                   # offline: not a VPN question
  if ($Route.InterfaceAlias -eq 'DiscordWARP') { return $null }
  if (-not $Adapter) { return (Get-DwVpnName $Route.InterfaceAlias '') }   # PPP/IKEv2 (Windows VPN) interfaces have no NetAdapter object
  if ($Adapter.Name -eq 'DiscordWARP') { return $null }
  if ($Adapter.HardwareInterface) { return $null }
  if ($Adapter.InterfaceDescription -match $script:DW_RealVirtual) { return $null }
  return (Get-DwVpnName $Adapter.Name $Adapter.InterfaceDescription)
}
function Get-DwInternetRoute {
  # The route Windows would use for ordinary internet traffic right now (~45 ms).
  Find-NetRoute -RemoteIPAddress 1.1.1.1 -ErrorAction SilentlyContinue | Where-Object { $_.DestinationPrefix } | Select-Object -First 1
}
# ---------- WARP endpoint port (v1.4) ----------
# The ISP may throttle new WireGuard flows to WARP's default port 2408: on 2026-11-16 new tunnels to 162.159.192.1:2408
# failed while ports 4500 and 1701 of the same Cloudflare address answered in ~40 ms. WARP accepts all four ports below.
$script:DW_WarpPorts = @(2408, 4500, 1701, 500)
function Get-DwWarpPort([string]$ConfigText) {
  # Pure: the "port:" of the WARP proxy in an engine config, or 0.
  $i = $ConfigText.IndexOf('- name: WARP'); if ($i -lt 0) { return 0 }
  $m = [regex]::Match($ConfigText.Substring($i), '(?m)^\s+port:\s*(\d+)'); if ($m.Success) { return [int]$m.Groups[1].Value }; return 0
}
function Set-DwWarpPort([string]$ConfigText, [int]$Port) {
  # Pure: the config text with the WARP proxy's port replaced (only that one line; other text unchanged).
  $i = $ConfigText.IndexOf('- name: WARP'); if ($i -lt 0) { return $ConfigText }
  $re = New-Object Text.RegularExpressions.Regex '(?m)^(\s+port:\s*)\d+'
  return $ConfigText.Substring(0, $i) + $re.Replace($ConfigText.Substring($i), ('${1}' + $Port), 1)
}
function Get-DwNextWarpPort([int]$Current) {
  # Pure: the next port to try after $Current (unknown port -> the first one).
  $idx = [array]::IndexOf($script:DW_WarpPorts, $Current)
  return $script:DW_WarpPorts[($idx + 1) % $script:DW_WarpPorts.Count]
}

function Get-DwForeignVpn {
  # Live check: $null or the name of the connected full-tunnel VPN.
  $r = Get-DwInternetRoute; if (-not $r) { return $null }
  Resolve-DwForeignVpn $r (Get-NetAdapter -IncludeHidden -InterfaceIndex $r.InterfaceIndex -ErrorAction SilentlyContinue)
}

function Test-MihomoConfig([string]$MihomoExe, [string]$ResourceDir, [string]$ConfigText, [string]$ProfileText, [string]$WorkDir) {
  # Validates "config.yaml tun block (enabled) + profile" with "verge-mihomo -t" in a private work dir; deletes it afterwards.
  $ErrorActionPreference = 'Continue'   # native stderr must not become a terminating error
  New-Item -ItemType Directory -Force $WorkDir | Out-Null
  try {
    foreach ($f in 'geosite.dat', 'geoip.dat', 'Country.mmdb', 'ASN.mmdb') { $s = Join-Path $ResourceDir $f; if (Test-Path $s) { Copy-Item $s $WorkDir -Force } }
    $lines = Split-Lines $ConfigText; $tun = @(); $in = $false
    foreach ($l in $lines) { if ($l -match '^tun:') { $in = $true; $tun += $l; continue }; if ($in -and $l -match '^\S') { break }; if ($in) { $tun += ($l -replace '^(\s+enable:\s*)\S+', '${1}true') } }
    $merged = (($tun -join "`n") + "`n" + $ProfileText)
    $mf = Join-Path $WorkDir 'merged.yaml'; Write-Utf8NoBom $mf $merged
    $out = & $MihomoExe -t -d $WorkDir -f $mf 2>&1 | Out-String
    return [pscustomobject]@{ Ok = ($out -match 'test is successful'); Output = ($out.Trim() -split "`n" | Select-Object -Last 3) -join ' | ' }
  } finally { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}

function New-EngineConfig([string]$ProfileText, [string]$Secret) {
  # Complete mihomo config for the DiscordWARP engine (v1.3+, no Clash Verge): header + selective TUN + the Discord profile.
  # Same TUN settings as the tested Clash Verge setup (stack "mips", dns-mode disabled, Discord routes only); no TCP API port,
  # API only on the local named pipe \\.\pipe\discord-warp-mihomo with a random secret.
  # unified-delay false (v1.4): delay tests include opening the connection (TCP + TLS through WARP). With true, mihomo
  # reported only a second request on an already open connection, so a tunnel that needed 5-20 s per new connection
  # still showed ~25 ms and passed every check (2026-11-16).
  $routes = ($script:DW_RouteAddr | ForEach-Object { "  - $_" }) -join "`n"
  $head = @"
# Discord WARP engine configuration - generated by Install.ps1 $(Get-Date -Format 'yyyy-MM-dd HH:mm'). Contains the WARP private key.
mode: rule
log-level: warning
allow-lan: false
unified-delay: false
external-controller: ''
external-controller-pipe: \\.\pipe\discord-warp-mihomo
secret: $Secret
tun:
  enable: true
  device: DiscordWARP
  stack: mips
  auto-route: true
  strict-route: false
  auto-detect-interface: true
  dns-mode: disabled
  dns-hijack:
  - 198.18.0.2:53
  route-address:
$routes

"@
  return ($head + ($ProfileText -replace "`r`n", "`n"))
}

function Test-EngineConfig([string]$MihomoExe, [string]$ConfigText, [string]$WorkDir) {
  # mihomo -t on the complete config in a private work dir (deleted afterwards). No geodata needed (no GEOSITE/GEOIP rules).
  $ErrorActionPreference = 'Continue'
  New-Item -ItemType Directory -Force $WorkDir | Out-Null
  try {
    $f = Join-Path $WorkDir 'config.yaml'; Write-Utf8NoBom $f $ConfigText
    $out = & $MihomoExe -t -d $WorkDir -f $f 2>&1 | Out-String
    return [pscustomobject]@{ Ok = ($out -match 'test is successful'); Output = ($out.Trim() -split "`n" | Select-Object -Last 3) -join ' | ' }
  } finally { Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
}