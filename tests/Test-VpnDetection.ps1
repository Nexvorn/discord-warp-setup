# Offline unit tests for the other-VPN detection (Resolve-DwForeignVpn). No network access, no admin.
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-VpnDetection.ps1
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\setup\DiscordWarpLib.ps1')
$fail = 0; $n = 0
function Rt($alias, $idx = 1) { [pscustomobject]@{ InterfaceAlias = $alias; InterfaceIndex = $idx } }
function Ad($name, $desc, [bool]$hw) { [pscustomobject]@{ Name = $name; InterfaceDescription = $desc; HardwareInterface = $hw } }
function T([string]$case, $route, $adapter, $want) {
  $script:n++; $got = Resolve-DwForeignVpn $route $adapter
  if ("$got" -eq "$want") { Write-Host "ok   $case -> '$got'" } else { $script:fail++; Write-Host "FAIL $case -> '$got' (want '$want')" -ForegroundColor Red } }

# real connections: never a VPN
T 'ethernet (no VPN)'                 (Rt 'Ethernet 2') (Ad 'Ethernet 2' 'Realtek Gaming 2.5GbE Family Controller' $true) $null
T 'wi-fi (no VPN)'                    (Rt 'Wi-Fi') (Ad 'Wi-Fi' 'Intel(R) Wi-Fi 6 AX201 160MHz' $true) $null
T 'Hyper-V external switch'           (Rt 'vEthernet (External)') (Ad 'vEthernet (External)' 'Hyper-V Virtual Ethernet Adapter #2' $false) $null
T 'NIC team'                          (Rt 'Team1') (Ad 'Team1' 'Microsoft Network Adapter Multiplexor Driver' $false) $null
T 'USB tethering'                     (Rt 'Ethernet 5') (Ad 'Ethernet 5' 'Remote NDIS based Internet Sharing Device' $false) $null
T 'offline (no route)'                $null $null $null
T 'own TUN (never)'                   (Rt 'DiscordWARP') (Ad 'DiscordWARP' 'Meta Tunnel' $false) $null
# VPNs
T 'NordVPN OpenVPN (def1 via TAP)'    (Rt 'Local Area Connection 2') (Ad 'Local Area Connection 2' 'TAP-NordVPN Windows Adapter V9' $false) 'NordVPN'
T 'NordVPN NordLynx'                  (Rt 'NordLynx') (Ad 'NordLynx' 'NordLynx Tunnel' $false) 'NordVPN'
T 'Windscribe WireGuard'              (Rt 'Windscribe') (Ad 'Windscribe' 'Windscribe Windtun420' $false) 'Windscribe'
T 'Proton VPN (wintun)'               (Rt 'ProtonVPN') (Ad 'ProtonVPN' 'ProtonVPN Tunnel' $false) 'Proton VPN'
T 'Cloudflare WARP app'               (Rt 'CloudflareWARP') (Ad 'CloudflareWARP' 'Cloudflare WARP Interface Tunnel' $false) 'Cloudflare WARP'
T 'ExpressVPN Lightway'               (Rt 'ExpressVPN') (Ad 'ExpressVPN' 'ExpressVPN Wintun Driver' $false) 'ExpressVPN'
T 'Mullvad'                           (Rt 'Mullvad') (Ad 'Mullvad' 'Mullvad Tunnel' $false) 'Mullvad VPN'
T 'plain WireGuard client'            (Rt 'wg-home') (Ad 'wg-home' 'WireGuard Tunnel' $false) 'WireGuard'
T 'OpenVPN Connect (DCO)'             (Rt 'OpenVPN Data Channel Offload') (Ad 'OpenVPN Data Channel Offload' 'OpenVPN Data Channel Offload' $false) 'OpenVPN'
T 'generic TAP'                       (Rt 'Local Area Connection') (Ad 'Local Area Connection' 'TAP-Windows Adapter V9' $false) 'OpenVPN'
T 'Tailscale exit node'               (Rt 'Tailscale') (Ad 'Tailscale' 'Tailscale Tunnel' $false) 'Tailscale'
T 'Windows VPN (PPP, no NetAdapter)'  (Rt 'Work VPN') $null 'Work VPN'
T 'unknown virtual adapter'           (Rt 'Tunnel7') (Ad 'Tunnel7' 'Some Tunnel Driver' $false) 'Tunnel7'

Write-Host ''
if ($fail) { Write-Host "$fail of $n FAILED" -ForegroundColor Red; exit 1 } else { Write-Host "all $n passed" -ForegroundColor Green }
