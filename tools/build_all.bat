@echo off
rem =====================================================================
rem Brine's Hollow Multi-Platform Build Launcher
rem Runs tools\build_all.ps1 via PowerShell
rem Usage:
rem   build_all.bat
rem   build_all.bat -Target windows
rem   build_all.bat -Target server -Mode release
rem =====================================================================

setlocal
cd /d "%~dp0\.."

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_all.ps1" %*
if errorlevel 1 (
    echo.
    echo [ERROR] Build failed!
    exit /b %errorlevel%
)

echo.
echo [SUCCESS] Build finished successfully.
exit /b 0
