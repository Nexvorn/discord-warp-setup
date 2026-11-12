@echo off
rem Discord WARP - opens the setup app (Arabic window with an "Install" button and progress steps).
start "" powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0setup\App.ps1"
