@echo off
rem Builds the Brine's Hollow native extension into ..\bin on Windows (MSVC).
rem   build.bat            debug template (used by editor + dev runs)
rem   build.bat release    release template (exports)
setlocal
cd /d "%~dp0"
set TARGET=template_debug
if /i "%~1"=="release" set TARGET=template_release

where cl >nul 2>nul
if errorlevel 1 (
    for /f "usebackq delims=" %%i in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set VSPATH=%%i
)
if defined VSPATH call "%VSPATH%\VC\Auxiliary\Build\vcvars64.bat" >nul

cmake -S . -B "build-%TARGET%" -DGODOTCPP_TARGET=%TARGET% -DCMAKE_BUILD_TYPE=Release || exit /b 1
cmake --build "build-%TARGET%" --config Release --parallel || exit /b 1
