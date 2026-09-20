@echo off
setlocal
cd /d "%~dp0"
title Terapkan Safe Revive PWKU
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0apply-safe-revive.ps1"
echo.
pause
