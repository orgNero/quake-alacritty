[CmdletBinding()]
param(
    [switch]$RemoveConfigs,
    [switch]$NonInteractive
)

<#
.SYNOPSIS
    Uninstalls Quake Alacritty Terminal and cleans up system shortcuts, registry
    entries, install metadata and profile hooks.

.DESCRIPTION
    Removes every artifact written by install.ps1 - including .install-state.json,
    VERSION, CONFIG_SCHEMA and timestamped .bak backups - so it never leaves a
    stale folder or a dangling "Installed Apps" entry behind. User configuration
    files are preserved unless -RemoveConfigs is supplied.

.PARAMETER RemoveConfigs
    Also delete config.ini, alacritty.toml and their timestamped backups.

.PARAMETER NonInteractive
    Never prompt; keep configuration files unless -RemoveConfigs is supplied.
#>

$ErrorActionPreference = "Stop"

$TargetDir = Join-Path $env:APPDATA "alacritty"
$SourceDir = $PSScriptRoot
$startupDir = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startupDir "quake_alacritty.lnk"

$commonPath = Join-Path $SourceDir "quake_common.ps1"
if (Test-Path $commonPath) {
    . $commonPath
} else {
    Write-Warning "quake_common.ps1 was not found next to uninstall.ps1; falling back to built-in teardown logic."
}

Write-Host "`n🗑️  Quake Alacritty Uninstaller" -ForegroundColor Red
Write-Host "=============================" -ForegroundColor DarkGray

$installState = $null
$installedVersion = $null
if (Get-Command Read-QuakeInstallState -ErrorAction SilentlyContinue) {
    $installState = Read-QuakeInstallState -TargetDir $TargetDir
    $installedVersion = Get-QuakeVersionFromDir -Directory $TargetDir
    if (-not $installedVersion -and $installState -and $installState.version) {
        $installedVersion = $installState.version
    }
}
if ($installedVersion) {
    Write-Host "`n📦 Installed version: v$installedVersion" -ForegroundColor Cyan
}

# 1. Stop running AutoHotkey processes (graceful WM_CLOSE, then force-kill fallback)
Write-Host "`n🛑 Stopping Quake Alacritty process..." -ForegroundColor Yellow
if (Get-Command Stop-QuakeAhkProcess -ErrorAction SilentlyContinue) {
    $allowedScripts = @(
        (Join-Path $TargetDir "quake_alacritty.ahk"),
        (Join-Path $SourceDir "quake_alacritty.ahk")
    )
    $stopped = Stop-QuakeAhkProcess -AllowedScriptPaths $allowedScripts
} else {
    $stopped = 0
    Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64.exe' OR Name='AutoHotkey32.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -match 'quake_alacritty\.ahk' } |
        ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
            $stopped++
        }
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
        if ($profileContent -match 'quake-help|quake-env') {
            # Remove comment and function line
            $cleaned = $profileContent -replace '(?m)^\s*# Quake Alacritty Cheat Sheet.*\s*[\r\n]+', ''
            $cleaned = $cleaned -replace '(?m)^\s*function quake-help\s*\{[^}]*\}\s*[\r\n]+', ''
            $cleaned = $cleaned -replace '(?m)^\s*function quake-env\s*\{[^}]*\}\s*[\r\n]+', ''
            $cleaned = $cleaned.TrimEnd() + "`r`n"
            Set-Content -Path $PROFILE -Value $cleaned -Encoding UTF8
            Write-Host "  Removed 'quake-help' and 'quake-env' registrations from `$PROFILE." -ForegroundColor Green
        } else {
            Write-Host "  'quake-help' / 'quake-env' not found in `$PROFILE." -ForegroundColor Gray
        }
    } catch {
        Write-Warning "  Could not update PowerShell profile: $_"
    }
}

# 3b. Clean up Git Bash profile hook (~/.bashrc)
$bashrcPath = Join-Path $env:USERPROFILE ".bashrc"
if (Test-Path $bashrcPath) {
    try {
        $bashrcContent = Get-Content $bashrcPath -Raw -ErrorAction SilentlyContinue
        if ($bashrcContent -match 'quake-help|quake-env|QUAKE_SHOW_HELP') {
            $cleaned = $bashrcContent -replace '(?m)^\s*# Quake Alacritty Cheat Sheet.*\s*[\r\n]+', ''
            $cleaned = $cleaned -replace '(?m)^\s*quake-help\(\)\s*\{[^}]*\}\s*[\r\n]+', ''
            $cleaned = $cleaned -replace '(?m)^\s*quake-env\(\)\s*\{[^}]*\}\s*[\r\n]+', ''
            $cleaned = $cleaned -replace '(?s)if \[ -n "\$QUAKE_SHOW_HELP" \].*?fi\s*[\r\n]*', ''
            $cleaned = $cleaned.TrimEnd() + "`n"
            [System.IO.File]::WriteAllText($bashrcPath, $cleaned, (New-Object System.Text.UTF8Encoding($false)))
            Write-Host "  Removed 'quake-help' and 'quake-env' registrations from $bashrcPath." -ForegroundColor Green
        } else {
            Write-Host "  'quake-help' / 'quake-env' not found in $bashrcPath." -ForegroundColor Gray
        }
    } catch {
        Write-Warning "  Could not update .bashrc: $_"
    }
}

# 4. Remove Windows "Installed Apps" (ARP) entry - unconditionally
Write-Host "`n🧾 Removing Windows Installed Apps entry..." -ForegroundColor Yellow
$entryRemoved = $false
if (Get-Command Remove-QuakeUninstallEntry -ErrorAction SilentlyContinue) {
    $entryRemoved = Remove-QuakeUninstallEntry
}
if ($entryRemoved) {
    Write-Host "  Removed HKCU uninstall entry 'QuakeAlacritty'." -ForegroundColor Green
} else {
    Write-Host "  No HKCU uninstall entry found." -ForegroundColor Gray
}

# 5. Remove deployed application files and installer metadata
Write-Host "`n📁 Removing installed application files..." -ForegroundColor Yellow
$artifactFiles = @(
    "quake_alacritty.ahk",
    "welcome.ps1",
    "quake_common.ps1",
    "VERSION",
    "CONFIG_SCHEMA",
    ".install-state.json",
    "uninstall.ps1"
)
foreach ($file in $artifactFiles) {
    $filePath = Join-Path $TargetDir $file
    if (Test-Path $filePath) {
        Remove-Item $filePath -Force
        Write-Host "  Removed $file" -ForegroundColor Green
    }
}

# 6. Handle Configuration Files (config.ini, alacritty.toml) and backups
$shouldRemoveConfigs = $RemoveConfigs
if (-not $RemoveConfigs -and -not $NonInteractive -and [Environment]::UserInteractive) {
    Write-Host ""
    $response = Read-Host "Do you also want to remove your configuration files (alacritty.toml and config.ini)? (y/N) [default: N]"
    if ($response -match '^(y|yes)$') {
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

    # Timestamped backups written by the installer are artifacts, not user files.
    $backupFiles = @(Get-ChildItem -Path $TargetDir -Filter "*.bak" -File -ErrorAction SilentlyContinue)
    foreach ($backup in $backupFiles) {
        Remove-Item $backup.FullName -Force -ErrorAction SilentlyContinue
        Write-Host "  Removed backup $($backup.Name)" -ForegroundColor Green
    }
} else {
    Write-Host "  Preserved user configuration files in: $TargetDir" -ForegroundColor Cyan
}

# 7. Remove the deploy folder when nothing user-owned remains
if ((Test-Path $TargetDir) -and (Get-ChildItem -Path $TargetDir -Force -ErrorAction SilentlyContinue).Count -eq 0) {
    Remove-Item $TargetDir -Force
    Write-Host "  Removed empty folder: $TargetDir" -ForegroundColor Green
}

Write-Host "`n✨ Quake Alacritty has been successfully uninstalled!" -ForegroundColor Green
