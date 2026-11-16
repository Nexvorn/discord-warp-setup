# Offline unit tests for the WARP port rotation helpers (Get-DwWarpPort, Set-DwWarpPort, Get-DwNextWarpPort).
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-WarpPort.ps1
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\setup\DiscordWarpLib.ps1')
$fail = 0; $n = 0
function Check([string]$case, $got, $want) {
  $script:n++; if ("$got" -eq "$want") { Write-Host "ok   $case -> $got" } else { $script:fail++; Write-Host "FAIL $case -> $got (want $want)" -ForegroundColor Red } }

$tpl = Read-TextNoBom (Join-Path $PSScriptRoot '..\src\setup\profile.template.yaml')
$cfg = "mixed-port: 7890`ntun:`n  enable: true`n" + $tpl          # a "port" key before the WARP proxy must stay untouched
Check 'template port'               (Get-DwWarpPort $cfg) 2408
$c2 = Set-DwWarpPort $cfg 4500
Check 'after set 4500'              (Get-DwWarpPort $c2) 4500
Check 'mixed-port untouched'        ([bool]($c2 -match '(?m)^mixed-port: 7890$')) $true
Check 'only one line changed'       (@(Compare-Object ($cfg -split "`n") ($c2 -split "`n")).Count) 2
Check 'server untouched'            ([bool]($c2 -match '(?m)^\s+server: 162\.159\.192\.1\s*$')) $true
Check 'no WARP block -> unchanged'  ((Set-DwWarpPort 'proxies: []' 4500) -eq 'proxies: []') $true
Check 'no WARP block -> port 0'     (Get-DwWarpPort 'proxies: []') 0
Check 'next after 2408'             (Get-DwNextWarpPort 2408) 4500
Check 'next after 4500'             (Get-DwNextWarpPort 4500) 1701
Check 'next after 1701'             (Get-DwNextWarpPort 1701) 500
Check 'next after 500 (wraps)'      (Get-DwNextWarpPort 500) 2408
Check 'next after unknown port'     (Get-DwNextWarpPort 0) 2408
$c3 = $cfg; foreach ($i in 1..4) { $c3 = Set-DwWarpPort $c3 (Get-DwNextWarpPort (Get-DwWarpPort $c3)) }
Check 'full cycle back to 2408'     (Get-DwWarpPort $c3) 2408
Check 'full cycle text identical'   ($c3 -eq $cfg) $true

Write-Host ''
if ($fail) { Write-Host "$fail of $n FAILED" -ForegroundColor Red; exit 1 } else { Write-Host "all $n passed" -ForegroundColor Green }
