@echo off
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0postinstall.ps1"
REM Once it works, hide the console by using this line instead:
REM powershell -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0postinstall.ps1"
