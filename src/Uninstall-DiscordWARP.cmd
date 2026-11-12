@echo off
rem Remove the Discord-via-WARP setup (asks: full removal of everything, or settings only). Asks for admin itself.
title Discord WARP Uninstall
if exist "%USERPROFILE%\.discord-warp\Uninstall.ps1" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.discord-warp\Uninstall.ps1"
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup\Uninstall.ps1"
)
