@echo off
setlocal
cd /d "%~dp0"
title Installer PWKU Server 1.5.5
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-from-windows.ps1"
echo.
pause
