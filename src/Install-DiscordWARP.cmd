@echo off
rem Discord via Cloudflare WARP - one-click setup. Double-click this file.
setlocal
title Discord WARP Setup
fltmc >nul 2>&1 || (
  echo Requesting administrator rights...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup\Install.ps1"
echo.
echo Finished. Press any key to close this window.
pause >nul
