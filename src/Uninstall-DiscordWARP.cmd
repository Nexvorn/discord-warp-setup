@echo off
rem Remove the Discord-via-WARP setup (asks: full removal of everything, or settings only). Asks for admin itself.
title Discord WARP Uninstall
if exist "%ProgramFiles%\DiscordWARP\scripts\Uninstall.ps1" (
  powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%ProgramFiles%\DiscordWARP\scripts\Uninstall.ps1"
) else (
  powershell -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0setup\Uninstall.ps1"
)
