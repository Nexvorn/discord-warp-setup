@echo off
rem Check GitHub for a newer version of this tool and install it (asks first).
title Discord WARP Update
if exist "%USERPROFILE%\.discord-warp\Update.ps1" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.discord-warp\Update.ps1"
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup\Update.ps1"
)
