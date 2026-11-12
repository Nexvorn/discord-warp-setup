# Discord WARP v1.3 - read the engine's REST API through its local named pipe (read-only; no network port).
#   mihomo-conns.ps1                     -> live connections as objects (proc, net, host, dst, chain, rule, up, down)
#   mihomo-conns.ps1 -ApiPath /x -Raw    -> raw JSON body of GET /x
param([string]$ApiPath = '/connections', [switch]$Raw)
$secret = try { (Get-Content (Join-Path $env:ProgramData 'DiscordWARP\api-secret.txt') -Raw).Trim() } catch { '' }
$c = New-Object System.IO.Pipes.NamedPipeClientStream('.', 'discord-warp-mihomo', [System.IO.Pipes.PipeDirection]::InOut)
$c.Connect(3000)
$w = New-Object System.IO.StreamWriter($c); $w.NewLine = "`r`n"
$w.WriteLine("GET $ApiPath HTTP/1.1"); $w.WriteLine("Host: localhost"); $w.WriteLine("Authorization: Bearer $secret"); $w.WriteLine("Connection: close"); $w.WriteLine(""); $w.Flush()
$r = (New-Object System.IO.StreamReader($c)).ReadToEnd(); $c.Close()
$body = $r.Substring($r.IndexOf("`r`n`r`n") + 4)
if ($r -match 'Transfer-Encoding: chunked') {
  $sb = New-Object System.Text.StringBuilder; $i = 0
  while ($i -lt $body.Length) { $nl = $body.IndexOf("`r`n", $i); if ($nl -lt 0) { break }; $n = [Convert]::ToInt32($body.Substring($i, $nl - $i), 16); if ($n -eq 0) { break }; [void]$sb.Append($body.Substring($nl + 2, $n)); $i = $nl + 2 + $n + 2 }
  $body = $sb.ToString() }
if ($Raw) { return $body }
$j = $body | ConvertFrom-Json
$j.connections | ForEach-Object { [pscustomobject]@{
  proc = $_.metadata.process; net = $_.metadata.network; host = $_.metadata.host
  dst = "$($_.metadata.destinationIP):$($_.metadata.destinationPort)"; chain = ($_.chains -join '>'); rule = $_.rule
  up = $_.upload; down = $_.download } }
