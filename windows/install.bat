@echo off
setlocal
cd /d "%~dp0"
if /i "%~1"=="uninstall" goto un
if /i "%~1"=="test" goto test

echo ============================================
echo   Campus network auto-login - INSTALL
echo ============================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-CampusLogin.ps1" -RunNow
goto end

:un
echo Removing scheduled task...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-CampusLogin.ps1" -Uninstall
goto end

:test
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0CampusLogin.ps1" -Action login

:end
echo.
pause
