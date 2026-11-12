# Adds NRPT rules so ONLY Discord domain names are resolved by mihomo (198.18.0.2, inside the Clash TUN).
# All rules are tagged with Comment "DiscordWARP". Remove with: nrpt-remove.ps1
$domains = 'discord.com','discordapp.com','discordapp.net','discord.gg','discord.media','discordcdn.com',
           'discordstatus.com','discord.co','discord.dev','discord.gift','discord.new','dis.gd'
$ns = @()
foreach ($d in $domains) { $ns += $d; $ns += ".$d" }
$ns += 'discord-attachments-uploads-prd.storage.googleapis.com'
Add-DnsClientNrptRule -Namespace $ns -NameServers '198.18.0.2' -Comment 'DiscordWARP' -DisplayName 'Discord via Clash WARP'
Clear-DnsClientCache
Get-DnsClientNrptRule | Where-Object Comment -eq 'DiscordWARP' | Select-Object Name, Namespace, NameServers |
  Out-File "$PSScriptRoot\nrpt-add.result.txt" -Encoding utf8 -Width 300
