# DiscordWARP-Setup shared functions (PowerShell 5.1, ASCII only).
# Pure text/file helpers so they can be unit-tested without touching the live system.
# NEVER print secret values (private key). Callers log only presence/lengths.

$script:DW_Uid        = 'LdiscordWarp01'
# Bundled binaries (official GitHub releases; SHA-256 = GitHub API asset digest, checked 2026-11-11)
$script:DW_Bins = [ordered]@{
  'Clash.Verge_2.5.10_x64-setup.exe' = @{ sha = '929da9303b643b80ce309ab29f618e37a5562f515d1fa55ebf5b86c822504450'; url = 'https://github.com/clash-verge-rev/clash-verge-rev/releases/download/v2.5.10/Clash.Verge_2.5.10_x64-setup.exe' }
  'wgcf_2.3.1_windows_amd64.exe'     = @{ sha = 'e222fd9443d7cb3264d825a3e86967797fc9c938507c5d93e3cc21e4aed11dcc'; url = 'https://github.com/ViRb3/wgcf/releases/download/v2.3.1/wgcf_2.3.1_windows_amd64.exe' }
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
