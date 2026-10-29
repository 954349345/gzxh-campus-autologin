@echo off
cd /d "%~dp0"
echo Logging in to campus network...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0CampusLogin.ps1" -Action login
echo.
pause
