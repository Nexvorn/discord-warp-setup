@echo off
rem Health check (read-only, no admin): is Discord on WARP and everything else on the normal connection?
title Discord WARP Check
powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.discord-warp\verify.ps1"
echo.
echo RESULT line above: "0 failed" = everything OK. Press any key to close.
pause >nul
