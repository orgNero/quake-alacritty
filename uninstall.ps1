[CmdletBinding()]
param(
    [switch]$RemoveConfigs,
    [switch]$NonInteractive
)

<#
.SYNOPSIS
    Uninstalls Quake Alacritty Terminal and cleans up system shortcuts and profile hooks.
#>

$ErrorActionPreference = "Stop"

$TargetDir = Join-Path $env:APPDATA "alacritty"
$startupDir = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startupDir "quake_alacritty.lnk"

Write-Host "`n🗑️  Quake Alacritty Uninstaller" -ForegroundColor Red
Write-Host "=============================" -ForegroundColor DarkGray

# 1. Stop running AutoHotkey process
Write-Host "`n🛑 Stopping Quake Alacritty process..." -ForegroundColor Yellow
$stopped = 0
Get-Process AutoHotkey64 -ErrorAction SilentlyContinue | Where-Object {
    $_.MainWindowTitle -like "*quake_alacritty*" -or $_.CommandLine -like "*quake_alacritty*"
} | ForEach-Object {
    Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    $stopped++
}
if ($stopped -gt 0) {
    Write-Host "  Stopped $stopped running Quake Alacritty process(es)." -ForegroundColor Green
} else {
    Write-Host "  No active Quake Alacritty processes found." -ForegroundColor Gray
}

# 2. Remove Windows Startup shortcut
Write-Host "`n🚀 Removing Windows Startup shortcut..." -ForegroundColor Yellow
if (Test-Path $shortcutPath) {
    Remove-Item $shortcutPath -Force
    Write-Host "  Removed startup shortcut: $shortcutPath" -ForegroundColor Green
} else {
    Write-Host "  Startup shortcut not present." -ForegroundColor Gray
}

# 3. Clean up PowerShell Profile hook
Write-Host "`n📜 Cleaning up PowerShell profile..." -ForegroundColor Yellow
if (Test-Path $PROFILE) {
    try {
        $profileContent = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
        if ($profileContent -match 'quake-help') {
            # Remove comment and function line
            $cleaned = $profileContent -replace '(?m)^\s*# Quake Alacritty Cheat Sheet\s*[\r\n]+', ''
            $cleaned = $cleaned -replace '(?m)^\s*function quake-help\s*\{[^}]*\}\s*[\r\n]+', ''
            $cleaned = $cleaned.TrimEnd() + "`r`n"
            Set-Content -Path $PROFILE -Value $cleaned -Encoding UTF8
            Write-Host "  Removed 'quake-help' registration from `$PROFILE." -ForegroundColor Green
        } else {
            Write-Host "  'quake-help' not found in `$PROFILE." -ForegroundColor Gray
        }
    } catch {
        Write-Warning "  Could not update PowerShell profile: $_"
    }
}

# 4. Remove deployed scripts
Write-Host "`n📁 Removing installed application files..." -ForegroundColor Yellow
$coreFiles = @("quake_alacritty.ahk", "welcome.ps1", "uninstall.ps1")
foreach ($file in $coreFiles) {
    $filePath = Join-Path $TargetDir $file
    if (Test-Path $filePath) {
        Remove-Item $filePath -Force
        Write-Host "  Removed $file" -ForegroundColor Green
    }
}

# 5. Handle Configuration Files (config.ini, alacritty.toml)
$shouldRemoveConfigs = $RemoveConfigs
if (-not $RemoveConfigs -and -not $NonInteractive -and [Environment]::UserInteractive) {
    Write-Host ""
    $resp = Read-Host "Do you also want to remove your configuration files (alacritty.toml and config.ini)? (y/N) [default: N]"
    if ($resp -match '^(y|yes)$') {
        $shouldRemoveConfigs = $true
    }
}

if ($shouldRemoveConfigs) {
    $configFiles = @("alacritty.toml", "config.ini")
    foreach ($file in $configFiles) {
        $filePath = Join-Path $TargetDir $file
        if (Test-Path $filePath) {
            Remove-Item $filePath -Force
            Write-Host "  Removed $file" -ForegroundColor Green
        }
    }
    if ((Test-Path $TargetDir) -and (Get-ChildItem $TargetDir).Count -eq 0) {
        Remove-Item $TargetDir -Force
        Write-Host "  Removed empty folder: $TargetDir" -ForegroundColor Green
    }
} else {
    Write-Host "  Preserved user configuration files in: $TargetDir" -ForegroundColor Cyan
}

Write-Host "`n✨ Quake Alacritty has been successfully uninstalled!" -ForegroundColor Green
