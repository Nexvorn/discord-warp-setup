@echo off
rem Remove the Discord-via-WARP setup from this PC.
setlocal
title Discord WARP Uninstall
fltmc >nul 2>&1 || (
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup\Uninstall.ps1"
echo.
echo Finished. Press any key to close this window.
pause >nul
