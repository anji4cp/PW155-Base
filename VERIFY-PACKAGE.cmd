@echo off
setlocal
cd /d "%~dp0"
title Verifikasi Paket PWKU
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0verify-package.ps1"
echo.
pause
