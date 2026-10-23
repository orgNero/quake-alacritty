[CmdletBinding()]
param(
    [switch]$InstallDependencies,
    [switch]$CreateStartupShortcut,
    [switch]$UseSymlinks,
    [switch]$NonInteractive,
    [ValidateSet("powershell", "pwsh", "wsl", "gitbash")]
    [string]$Shell,
    [ValidateSet("nordic", "us")]
    [string]$KeyboardLayout
)

<#
.SYNOPSIS
    Installs and configures Quake Alacritty Terminal with AutoHotkey v2.
    Supports both an interactive setup wizard and silent/scripted flags.
#>

$ErrorActionPreference = "Stop"

$SourceDir = $PSScriptRoot
$TargetDir = Join-Path $env:APPDATA "alacritty"

Write-Host "`n⚡ Quake Alacritty Setup" -ForegroundColor Cyan
Write-Host "=======================" -ForegroundColor DarkGray

# -----------------------------------------------------------------------------
# Helper: Detect Interactive Execution
# -----------------------------------------------------------------------------
$isInteractive = (-not $NonInteractive) -and 
                 (-not $PSBoundParameters.ContainsKey('Shell')) -and 
                 (-not $PSBoundParameters.ContainsKey('InstallDependencies')) -and 
                 [Environment]::UserInteractive

# -----------------------------------------------------------------------------
# Step 1: Prerequisites Check & Installation
# -----------------------------------------------------------------------------
$hasAlacritty = [bool](Get-Command alacritty -ErrorAction SilentlyContinue)
$hasAhk = [bool](Get-Command AutoHotkey64.exe -ErrorAction SilentlyContinue) -or 
          (Test-Path "C:\Users\$env:USERNAME\AppData\Local\Programs\AutoHotkey\v2\AutoHotkey64.exe") -or
          (Test-Path "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe")

if ($isInteractive) {
    Write-Host "`n[1/4] Checking Prerequisites:" -ForegroundColor Yellow
    
    $alacrittyStatus = if ($hasAlacritty) { "Installed" } else { "Not Found" }
    $alacrittyColor  = if ($hasAlacritty) { "Green" } else { "Red" }
    Write-Host "  Alacritty Terminal: $alacrittyStatus" -ForegroundColor $alacrittyColor

    $ahkStatus = if ($hasAhk) { "Installed" } else { "Not Found" }
    $ahkColor  = if ($hasAhk) { "Green" } else { "Red" }
    Write-Host "  AutoHotkey v2:      $ahkStatus" -ForegroundColor $ahkColor
    
    if (-not $hasAlacritty -or -not $hasAhk) {
        $installReq = Read-Host "`nWould you like to install missing prerequisites via winget? (Y/n) [default: Y]"
        if ($installReq -eq "" -or $installReq -match '^(y|yes)$') {
            $InstallDependencies = $true
        }
    }
}

if ($InstallDependencies) {
    Write-Host "`n📦 Installing prerequisites via winget..." -ForegroundColor Yellow
    
    if (-not $hasAlacritty) {
        Write-Host "  Installing Alacritty..." -ForegroundColor Gray
        winget install -e --id Alacritty.Alacritty --accept-source-agreements --accept-package-agreements
    }
    
    if (-not $hasAhk) {
        Write-Host "  Installing AutoHotkey v2..." -ForegroundColor Gray
        winget install -e --id AutoHotkey.AutoHotkey --accept-source-agreements --accept-package-agreements
    }
    
    Write-Host "  Installing JetBrainsMono Nerd Font..." -ForegroundColor Gray
    winget install -e --id DEVCOM.JetBrainsMonoNerdFont --accept-source-agreements --accept-package-agreements
}

# -----------------------------------------------------------------------------
# Step 2: Preferred Shell Selection
# -----------------------------------------------------------------------------
$selectedShell = $Shell
$gitBashPath = ""

# Auto-detect Git Bash path
$commonGitPaths = @(
    "C:\Program Files\Git\bin\bash.exe",
    "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe",
    "C:\Program Files (x86)\Git\bin\bash.exe"
)
foreach ($p in $commonGitPaths) {
    if (Test-Path $p) {
        $gitBashPath = $p
        break
    }
}
if (-not $gitBashPath) {
    $cmdBash = Get-Command bash.exe -ErrorAction SilentlyContinue
    if ($cmdBash -and $cmdBash.Source -like "*Git*") {
        $gitBashPath = $cmdBash.Source
    }
}

if ($isInteractive -and -not $selectedShell) {
    Write-Host "`n[2/4] Choose your default terminal shell:" -ForegroundColor Yellow
    Write-Host "  [1] PowerShell (Default - Windows PowerShell / pwsh)" -ForegroundColor Cyan
    Write-Host "  [2] WSL Bash   (Linux / Ubuntu via wsl.exe)" -ForegroundColor Cyan
    Write-Host "  [3] Git Bash   (MSYS2 bash.exe)" -ForegroundColor Cyan
    Write-Host "  [4] Keep existing configuration" -ForegroundColor Cyan
    
    $shellChoice = Read-Host "`nSelect shell [1-4] (default: 1)"
    switch ($shellChoice.Trim()) {
        "2" { $selectedShell = "wsl" }
        "3" { $selectedShell = "gitbash" }
        "4" { $selectedShell = "keep" }
        default { $selectedShell = "powershell" }
    }
}

if (-not $selectedShell) {
    $selectedShell = "powershell"
}

# Validate selected shell environment
if ($selectedShell -eq "wsl") {
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        Write-Warning "WSL was selected, but 'wsl.exe' was not found in PATH. You may need to run 'wsl --install'."
    }
} elseif ($selectedShell -eq "gitbash") {
    if (-not $gitBashPath) {
        Write-Warning "Git Bash was selected, but 'bash.exe' was not found in standard paths. Defaulting to 'C:\Program Files\Git\bin\bash.exe'."
        $gitBashPath = "C:\Program Files\Git\bin\bash.exe"
    }
}

# -----------------------------------------------------------------------------
# Step 3: Keyboard Layout & Toggle Hotkey Selection
# -----------------------------------------------------------------------------
$selectedLayout = $KeyboardLayout

if ($isInteractive -and -not $selectedLayout) {
    Write-Host "`n[3/4] Choose your keyboard layout for the visor toggle hotkey:" -ForegroundColor Yellow
    Write-Host "  [1] Nordic / Swedish layout (Win + §, key below Escape) [Default]" -ForegroundColor Cyan
    Write-Host "  [2] US / Standard ANSI layout (Win + backtick, key below Escape)" -ForegroundColor Cyan
    
    $layoutChoice = Read-Host "`nSelect layout [1-2] (default: 1)"
    switch ($layoutChoice.Trim()) {
        "2" { $selectedLayout = "us" }
        default { $selectedLayout = "nordic" }
    }
}

if (-not $selectedLayout) {
    $selectedLayout = "nordic"
}

# -----------------------------------------------------------------------------
# Step 4: Windows Startup Shortcut
# -----------------------------------------------------------------------------
$startupDir = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startupDir "quake_alacritty.lnk"
$shouldCreateStartup = $CreateStartupShortcut

if ($isInteractive -and -not $PSBoundParameters.ContainsKey('CreateStartupShortcut')) {
    Write-Host "`n[4/4] Windows Startup Integration:" -ForegroundColor Yellow
    $startupPrompt = Read-Host "Launch Quake Alacritty automatically when Windows starts? (Y/n) [default: Y]"
    if ($startupPrompt -eq "" -or $startupPrompt -match '^(y|yes)$') {
        $shouldCreateStartup = $true
    }
} elseif (-not $PSBoundParameters.ContainsKey('CreateStartupShortcut') -and -not (Test-Path $shortcutPath)) {
    $shouldCreateStartup = $true
}

# -----------------------------------------------------------------------------
# Step 5: Deploy Config & Application Files
# -----------------------------------------------------------------------------
Write-Host "`n📁 Deploying files to: $TargetDir" -ForegroundColor Yellow
if (-not (Test-Path $TargetDir)) {
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
}

$filesToDeploy = @("quake_alacritty.ahk", "alacritty.toml", "config.ini", "welcome.ps1", "uninstall.ps1")
foreach ($file in $filesToDeploy) {
    $src = Join-Path $SourceDir $file
    $dst = Join-Path $TargetDir $file
    
    if (Test-Path $src) {
        if ($UseSymlinks) {
            if (Test-Path $dst) { Remove-Item $dst -Force }
            New-Item -ItemType SymbolicLink -Path $dst -Target $src -Force | Out-Null
            Write-Host "  [Link] $file -> $dst" -ForegroundColor Green
        } else {
            if ($file -eq "config.ini" -and (Test-Path $dst) -and ($selectedShell -eq "keep")) {
                Write-Host "  [Skip] $file already exists at destination (preserving user configuration)" -ForegroundColor Cyan
            } else {
                Copy-Item -Path $src -Destination $dst -Force
                Write-Host "  [Copy] $file -> $dst" -ForegroundColor Green
            }
        }
    }
}

# -----------------------------------------------------------------------------
# Step 6: Configure alacritty.toml and config.ini
# -----------------------------------------------------------------------------
$destToml = Join-Path $TargetDir "alacritty.toml"
$destIni  = Join-Path $TargetDir "config.ini"

if ((Test-Path $destToml) -and ($selectedShell -ne "keep")) {
    $tomlContent = Get-Content $destToml -Raw
    
    $newShellBlock = ""
    switch ($selectedShell) {
        "powershell" {
            $newShellBlock = "[terminal.shell]`r`nprogram = `"powershell.exe`""
        }
        "pwsh" {
            $newShellBlock = "[terminal.shell]`r`nprogram = `"pwsh.exe`""
        }
        "wsl" {
            $newShellBlock = "[terminal.shell]`r`nprogram = `"wsl.exe`"`r`nargs = [`"~`"]"
        }
        "gitbash" {
            $escapedGitPath = $gitBashPath.Replace("\", "\\")
            $newShellBlock = "[terminal.shell]`r`nprogram = `"$escapedGitPath`"`r`nargs = [`"--login`", `"-i`"]"
        }
    }
    
    # Replace existing [terminal.shell] section or append
    if ($tomlContent -match '(?ms)\[terminal\.shell\].*?(?=\r?\n\[|\Z)') {
        $tomlContent = $tomlContent -replace '(?ms)\[terminal\.shell\].*?(?=\r?\n\[|\Z)', $newShellBlock
    } else {
        $tomlContent = $tomlContent.TrimEnd() + "`r`n`r`n" + $newShellBlock + "`r`n"
    }
    
    Set-Content -Path $destToml -Value $tomlContent -Encoding UTF8
    Write-Host "  [Config] Configured $selectedShell shell in alacritty.toml" -ForegroundColor Green
}

if (Test-Path $destIni) {
    $iniContent = Get-Content $destIni -Raw
    
    # If a non-PowerShell shell is chosen, silence welcome tip in config.ini as well
    if ($selectedShell -in @("wsl", "gitbash")) {
        if ($iniContent -match 'ShowHelpOnStart=\w+') {
            $iniContent = $iniContent -replace 'ShowHelpOnStart=\w+', 'ShowHelpOnStart=none'
        }
    }
    
    # Update ToggleVisor hotkey
    # Note: In AutoHotkey, scan code sc029 is the key directly below Esc on both Swedish (§) and US (`)
    if ($selectedLayout -eq "us") {
        $iniContent = $iniContent -replace 'ToggleVisor=.*', 'ToggleVisor=#sc029 ; Win + backtick (key below Esc on US ANSI)'
    } else {
        $iniContent = $iniContent -replace 'ToggleVisor=.*', 'ToggleVisor=#sc029 ; Win + § (key below Esc on Swedish ISO)'
    }
    
    Set-Content -Path $destIni -Value $iniContent -Encoding UTF8
    Write-Host "  [Config] Configured $selectedLayout keyboard layout in config.ini" -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# Step 7: Windows Startup Shortcut Registration
# -----------------------------------------------------------------------------
if ($shouldCreateStartup) {
    Write-Host "`n🚀 Setting up Windows Startup shortcut..." -ForegroundColor Yellow
    $WshShell = New-Object -ComObject WScript.Shell
    $shortcut = $WshShell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = Join-Path $TargetDir "quake_alacritty.ahk"
    $shortcut.WorkingDirectory = $TargetDir
    $shortcut.Description = "Quake Alacritty Terminal Visor"
    $shortcut.Save()
    Write-Host "  Created startup shortcut: $shortcutPath" -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# Step 8: Optional PowerShell Profile Registration
# -----------------------------------------------------------------------------
if (($selectedShell -in @("powershell", "pwsh")) -and (Test-Path $PROFILE)) {
    try {
        $profileContent = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
        $welcomePath = Join-Path $TargetDir "welcome.ps1"
        if ($profileContent -notmatch 'quake-help') {
            Add-Content -Path $PROFILE -Value "`n# Quake Alacritty Cheat Sheet & Environment Helper`nfunction quake-help { & `"$welcomePath`" }`nfunction quake-env { & `"$welcomePath`" -EnvInfo }"
            Write-Host "  [Profile] Registered 'quake-help' and 'quake-env' in `$PROFILE" -ForegroundColor Green
        } elseif ($profileContent -notmatch 'quake-env') {
            Add-Content -Path $PROFILE -Value "`nfunction quake-env { & `"$welcomePath`" -EnvInfo }"
            Write-Host "  [Profile] Registered 'quake-env' in `$PROFILE" -ForegroundColor Green
        }
    } catch {}
}

# -----------------------------------------------------------------------------
# Step 9: Launch / Restart Running Script
# -----------------------------------------------------------------------------
Write-Host "`n🔄 Starting AutoHotkey script..." -ForegroundColor Yellow
Get-Process AutoHotkey64 -ErrorAction SilentlyContinue | Where-Object {
    $_.MainWindowTitle -like "*quake_alacritty*" -or $_.CommandLine -like "*quake_alacritty*"
} | Stop-Process -Force -ErrorAction SilentlyContinue

$ahkExe = Get-Command AutoHotkey64.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
if (-not $ahkExe) {
    $commonAhkPaths = @(
        "C:\Users\$env:USERNAME\AppData\Local\Programs\AutoHotkey\v2\AutoHotkey64.exe",
        "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
    )
    foreach ($p in $commonAhkPaths) {
        if (Test-Path $p) {
            $ahkExe = $p
            break
        }
    }
}

if ($ahkExe -and (Test-Path $ahkExe)) {
    Start-Process -FilePath $ahkExe -ArgumentList "`"$TargetDir\quake_alacritty.ahk`""
    $toggleKeyDesc = if ($selectedLayout -eq "us") { "Win + backtick (tilde)" } else { "Win + §" }
    Write-Host "  AutoHotkey visor is running! Press $toggleKeyDesc to toggle." -ForegroundColor Green
} else {
    Write-Host "  AutoHotkey executable not found in standard path. Please launch quake_alacritty.ahk manually." -ForegroundColor Red
}

Write-Host "`n✨ Installation complete!" -ForegroundColor Cyan
Write-Host "💡 To uninstall anytime, run: powershell -File `"$TargetDir\uninstall.ps1`"" -ForegroundColor DarkGray
Write-Host "💬 Have feedback, bugs, or feature ideas? Open an issue: https://github.com/orgNero/quake-alacritty/issues`n" -ForegroundColor DarkGray
