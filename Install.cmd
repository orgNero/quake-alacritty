@echo off
chcp 65001 >nul
if not exist "%~dp0install.ps1" (
    echo Extract the whole ZIP - install.ps1 is missing.
    pause
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
if errorlevel 1 pause
