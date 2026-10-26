@echo off
chcp 65001 >nul
if not exist "%~dp0src\install.ps1" (
    echo Extract the whole ZIP - src\install.ps1 is missing.
    pause
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0src\install.ps1" %*
if errorlevel 1 pause
