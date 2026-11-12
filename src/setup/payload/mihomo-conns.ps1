# Reads mihomo's live connection table via Clash Verge's local named pipe (read-only).
param([string]$ApiPath = '/connections', [switch]$Raw)
$cv = "$env:APPDATA\io.github.clash-verge-rev.clash-verge-rev\clash-verge.yaml"
$pipeFull = [System.IO.Directory]::GetFiles('\\.\pipe\') | Where-Object { $_ -match 'verge-mihomo-' } | Select-Object -First 1
$pipe = $pipeFull.Substring(9)   # strip '\\.\pipe\'
$secret = ((Select-String -Path $cv -Pattern '^secret:\s*(.+)$').Matches[0].Groups[1].Value.Trim())
$c = New-Object System.IO.Pipes.NamedPipeClientStream('.', $pipe, [System.IO.Pipes.PipeDirection]::InOut)
$c.Connect(3000)
$w = New-Object System.IO.StreamWriter($c); $w.NewLine = "`r`n"
$w.WriteLine("GET $ApiPath HTTP/1.1"); $w.WriteLine("Host: localhost"); $w.WriteLine("Authorization: Bearer $secret"); $w.WriteLine("Connection: close"); $w.WriteLine(""); $w.Flush()
$r = (New-Object System.IO.StreamReader($c)).ReadToEnd(); $c.Close()
$body = $r.Substring($r.IndexOf("`r`n`r`n") + 4)
if ($r -match 'Transfer-Encoding: chunked') {
  $sb = New-Object System.Text.StringBuilder; $i = 0
  while ($i -lt $body.Length) { $nl = $body.IndexOf("`r`n", $i); $n = [Convert]::ToInt32($body.Substring($i, $nl - $i), 16); if ($n -eq 0) { break }; [void]$sb.Append($body.Substring($nl + 2, $n)); $i = $nl + 2 + $n + 2 }
  $body = $sb.ToString() }
if ($Raw) { return $body }
$j = $body | ConvertFrom-Json
$j.connections | ForEach-Object { [pscustomobject]@{
  proc = $_.metadata.process; net = $_.metadata.network; host = $_.metadata.host
  dst = "$($_.metadata.destinationIP):$($_.metadata.destinationPort)"; chain = ($_.chains -join '>'); rule = $_.rule
  up = $_.upload; down = $_.download } }
