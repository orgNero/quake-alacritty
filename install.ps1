<#
.SYNOPSIS
    Installs and configures Quake Alacritty Terminal with AutoHotkey v2.
#>

[CmdletBinding()]
param(
    [switch]$InstallDependencies,
    [switch]$CreateStartupShortcut,
    [switch]$UseSymlinks
)

$ErrorActionPreference = "Stop"

$SourceDir = $PSScriptRoot
$TargetDir = Join-Path $env:APPDATA "alacritty"

Write-Host "⚡ Quake Alacritty Setup" -ForegroundColor Cyan
Write-Host "=======================" -ForegroundColor DarkGray

# 1. Optional Dependency Installation
if ($InstallDependencies) {
    Write-Host "`n📦 Installing prerequisites via winget..." -ForegroundColor Yellow
    
    if (-not (Get-Command alacritty -ErrorAction SilentlyContinue)) {
        Write-Host "Installing Alacritty..." -ForegroundColor Gray
        winget install -e --id Alacritty.Alacritty --accept-source-agreements --accept-package-agreements
    }
    
    if (-not (Get-Command AutoHotkey64.exe -ErrorAction SilentlyContinue)) {
        Write-Host "Installing AutoHotkey v2..." -ForegroundColor Gray
        winget install -e --id AutoHotkey.AutoHotkey --accept-source-agreements --accept-package-agreements
    }
    
    Write-Host "Installing JetBrainsMono Nerd Font..." -ForegroundColor Gray
    winget install -e --id DEVCOM.JetBrainsMonoNerdFont --accept-source-agreements --accept-package-agreements
}

# 2. Deploy Config Files
Write-Host "`n📁 Deploying files to: $TargetDir" -ForegroundColor Yellow
if (-not (Test-Path $TargetDir)) {
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
}

$filesToDeploy = @("quake_alacritty.ahk", "alacritty.toml", "config.ini", "welcome.ps1")
foreach ($file in $filesToDeploy) {
    $src = Join-Path $SourceDir $file
    $dst = Join-Path $TargetDir $file
    
    if (Test-Path $src) {
        if ($UseSymlinks) {
            if (Test-Path $dst) { Remove-Item $dst -Force }
            New-Item -ItemType SymbolicLink -Path $dst -Target $src -Force | Out-Null
            Write-Host "  [Link] $file -> $dst" -ForegroundColor Green
        } else {
            if ($file -eq "config.ini" -and (Test-Path $dst)) {
                Write-Host "  [Skip] $file already exists at destination (preserving user configuration)" -ForegroundColor Cyan
            } else {
                Copy-Item -Path $src -Destination $dst -Force
                Write-Host "  [Copy] $file -> $dst" -ForegroundColor Green
            }
        }
    }
}

# 3. Create Windows Startup Shortcut
$startupDir = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startupDir "quake_alacritty.lnk"

if ($CreateStartupShortcut -or (-not (Test-Path $shortcutPath))) {
    Write-Host "`n🚀 Setting up Windows Startup shortcut..." -ForegroundColor Yellow
    $WshShell = New-Object -ComObject WScript.Shell
    $shortcut = $WshShell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = Join-Path $TargetDir "quake_alacritty.ahk"
    $shortcut.WorkingDirectory = $TargetDir
    $shortcut.Description = "Quake Alacritty Terminal Visor"
    $shortcut.Save()
    Write-Host "  Created startup shortcut: $shortcutPath" -ForegroundColor Green
}

# 4. Optional: Register 'quake-help' in PowerShell profile
if (Test-Path $PROFILE) {
    try {
        $profileContent = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
        if ($profileContent -notmatch 'quake-help') {
            $welcomePath = Join-Path $TargetDir "welcome.ps1"
            Add-Content -Path $PROFILE -Value "`n# Quake Alacritty Cheat Sheet`nfunction quake-help { & `"$welcomePath`" }"
            Write-Host "  [Profile] Registered 'quake-help' in `$PROFILE" -ForegroundColor Green
        }
    } catch {}
}

# 5. Restart running script
Write-Host "`n🔄 Starting AutoHotkey script..." -ForegroundColor Yellow
Get-Process AutoHotkey64 -ErrorAction SilentlyContinue | Where-Object {
    $_.MainWindowTitle -like "*quake_alacritty*" -or $_.CommandLine -like "*quake_alacritty*"
} | Stop-Process -Force -ErrorAction SilentlyContinue

$ahkExe = Get-Command AutoHotkey64.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
if (-not $ahkExe) {
    $ahkExe = "C:\Users\$env:USERNAME\AppData\Local\Programs\AutoHotkey\v2\AutoHotkey64.exe"
}

if (Test-Path $ahkExe) {
    Start-Process -FilePath $ahkExe -ArgumentList "`"$TargetDir\quake_alacritty.ahk`""
    Write-Host "  AutoHotkey visor is running! Press Win + § to toggle." -ForegroundColor Green
} else {
    Write-Host "  AutoHotkey executable not found in standard path. Please launch quake_alacritty.ahk manually." -ForegroundColor Red
}

Write-Host "`n✨ Installation complete!" -ForegroundColor Cyan
