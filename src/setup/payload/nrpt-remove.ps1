# Removes the Discord NRPT rules added by nrpt-add.ps1 (run as Administrator).
Get-DnsClientNrptRule | Where-Object Comment -eq 'DiscordWARP' | ForEach-Object { Remove-DnsClientNrptRule -Name $_.Name -Force }
Clear-DnsClientCache
"Remaining DiscordWARP rules: " + @(Get-DnsClientNrptRule | Where-Object Comment -eq 'DiscordWARP').Count
