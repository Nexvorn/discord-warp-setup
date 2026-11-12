# Lists every TCP/UDP socket owned by Discord processes and classifies it:
#   TUNNEL = local address is the Clash TUN (198.18.0.1) -> goes through WARP
#   LEAK   = bound to the physical NIC with a non-LAN remote -> bypasses the tunnel
#   LOCAL  = loopback / LAN / unconnected listener
$pids = @(Get-Process Discord -ErrorAction SilentlyContinue).Id
if (-not $pids) { "Discord is not running"; return }
$tun = (Get-NetIPAddress -InterfaceAlias Meta -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
function Classify($la, $ra) {
  if ($la -eq $tun) { return 'TUNNEL' }
  if ($ra -match '^(127\.|::1|0\.0\.0\.0|::$|\*|192\.168\.|10\.|172\.(1[6-9]|2\d|3[01])\.|fe80|$)') { return 'LOCAL' }
  return 'LEAK' }
$tcp = Get-NetTCPConnection -OwningProcess $pids -ErrorAction SilentlyContinue | ForEach-Object {
  [pscustomobject]@{ proto='TCP'; local="$($_.LocalAddress):$($_.LocalPort)"; remote="$($_.RemoteAddress):$($_.RemotePort)"; state=$_.State; class=(Classify $_.LocalAddress $_.RemoteAddress) } }
$udp = Get-NetUDPEndpoint -OwningProcess $pids -ErrorAction SilentlyContinue | ForEach-Object {
  $cls = if ($_.LocalAddress -eq $tun) { 'TUNNEL' } elseif ($_.LocalAddress -match '^(127\.|::1)') { 'LOCAL' } elseif ($_.LocalAddress -match '^(0\.0\.0\.0|::)$') { 'UNBOUND' } else { 'CHECK' }
  [pscustomobject]@{ proto='UDP'; local="$($_.LocalAddress):$($_.LocalPort)"; remote='(n/a)'; state=''; class=$cls } }
$all = @($tcp) + @($udp)
"TUN address: $tun | Discord PIDs: $($pids -join ',')"
$all | Group-Object proto, class | Select-Object Count, Name | Format-Table -AutoSize
$all | Where-Object { $_.class -in 'LEAK','CHECK' } | Format-Table -AutoSize
