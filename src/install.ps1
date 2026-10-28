[CmdletBinding()]
param(
    [switch]$InstallDependencies,
    [switch]$UpgradeDependencies,
    [switch]$CreateStartupShortcut,
    [switch]$UseSymlinks,
    [switch]$NonInteractive,
    [switch]$ResetConfig,
    [switch]$DryRun,
    [switch]$CheckForUpdates,
    [switch]$PassThru,
    [switch]$VerifyVersion,
    [ValidateSet("powershell", "pwsh", "wsl", "gitbash", "keep")]
    [string]$Shell,
    [ValidateSet("nordic", "us")]
    [string]$KeyboardLayout
)

<#
.SYNOPSIS
    Installs, upgrades and configures Quake Alacritty Terminal with AutoHotkey v2.

.DESCRIPTION
    Re-running this script is safe: it detects an existing installation from
    %APPDATA%\alacritty\.install-state.json, preserves user configuration by
    default (appending only missing config.ini keys), and stops any running
    AutoHotkey instance gracefully before redeploying.

.PARAMETER InstallDependencies
    Install missing prerequisites (Alacritty, AutoHotkey v2, Nerd Font) via winget.

.PARAMETER UpgradeDependencies
    Report installed dependency versions and run winget upgrade for each package.

.PARAMETER CreateStartupShortcut
    Create the Windows Startup shortcut without prompting.

.PARAMETER UseSymlinks
    Symlink repository files instead of copying (development mode).

.PARAMETER NonInteractive
    Never prompt; use defaults for anything not supplied.

.PARAMETER ResetConfig
    Deliberately restore factory config.ini and alacritty.toml (timestamped backups
    are written first). Without this flag user configuration is preserved.

.PARAMETER DryRun
    Print every planned file write, shortcut, registry key, profile edit and process
    action without applying it. This is not PowerShell ShouldProcess/-WhatIf.

.PARAMETER CheckForUpdates
    Read the newest published GitHub release and print an advisory notice. Works
    standalone (runs the check and exits). Never downloads or executes anything.

.PARAMETER PassThru
    With -CheckForUpdates, emit a result object to the pipeline.

.PARAMETER VerifyVersion
    Validate VERSION against the newest CHANGELOG.md heading and (when present)
    the nearest git tag. Exits with code 1 on mismatch.

.PARAMETER Shell
    powershell | pwsh | wsl | gitbash | keep. "keep" leaves alacritty.toml untouched.

.PARAMETER KeyboardLayout
    nordic | us. Only rewrites ToggleVisor when supplied.

.EXAMPLE
    .\src\install.ps1 -Shell wsl -KeyboardLayout us -CreateStartupShortcut

.EXAMPLE
    .\src\install.ps1 -DryRun -Shell keep

.EXAMPLE
    .\src\install.ps1 -CheckForUpdates -PassThru
#>

$ErrorActionPreference = "Stop"

# Two installers (or an install racing an uninstall) would interleave file
# copies, registry writes and AHK restarts. Hold a session-local mutex for the
# process lifetime; Windows releases it if this process dies.
$installerMutex = $null
try {
    $installerMutex = New-Object System.Threading.Mutex($false, "Local\QuakeAlacrittyInstaller")
    try {
        if (-not $installerMutex.WaitOne(0)) {
            Write-Host "Another Quake Alacritty install or update is already running. Wait for it to finish, then retry."
            exit 1
        }
    } catch [System.Threading.AbandonedMutexException] {
        # The previous holder died without releasing; this process now owns it.
    }
} catch {
    $installerMutex = $null
}

$SourceDir = $PSScriptRoot
$RepoRoot = Split-Path $SourceDir -Parent
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = $SourceDir }
$TargetDir = Join-Path $env:APPDATA "alacritty"
$RepositoryUrl = "https://github.com/orgNero/quake-alacritty"
$script:ConfigBackups = @{}

$commonPath = Join-Path $SourceDir "quake_common.ps1"
if (Test-Path $commonPath) {
    . $commonPath
} else {
    Write-Warning "quake_common.ps1 was not found next to install.ps1. Re-download the complete project or release archive."
    exit 1
}

# -----------------------------------------------------------------------------
# Helper functions
# -----------------------------------------------------------------------------
function Test-ShouldApply {
    param([string]$Description)
    if ($DryRun) {
        Write-Host "  [DryRun] $Description" -ForegroundColor DarkCyan
        return $false
    }
    return $true
}

function Write-QuakeTextFile {
    param(
        [string]$Path,
        [string]$Content,
        [bool]$ForceBom = $false
    )

    $useBom = $ForceBom
    if (-not $useBom -and (Test-Path $Path)) {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            $useBom = $true
        }
    }
    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($useBom)))
}

# Normalizes the [Hotkeys] section so generated and migrated files match
# src\config.ini: comments on their own line, values with no inline "; text".
# AHK now strips the comment at read time, so this is presentation rather than
# correctness - but a file that still carries the old shape looks like it should
# work and hides what the effective binding is. Idempotent: output has no inline
# comments left to move.
function Convert-QuakeHotkeyComments {
    param([string]$Content)

    if ([string]::IsNullOrEmpty($Content)) { return $Content }

    $eol = if ($Content -match "`r`n") { "`r`n" } else { "`n" }
    $lines = $Content -split "\r?\n"
    $output = New-Object System.Collections.Generic.List[string]
    $inHotkeys = $false

    foreach ($line in $lines) {
        if ($line -match '^\s*\[([^\]]+)\]\s*$') {
            $inHotkeys = ($matches[1].Trim() -ieq "Hotkeys")
            $output.Add($line)
            continue
        }

        # Only the [Hotkeys] section: values in other sections may legitimately
        # contain ';' (paths, colors with odd comments), and are left untouched.
        if ($inHotkeys -and $line -match '^(\s*)([^;#=\s][^=]*?)\s*=\s*(.*?)\s*;\s*(.+?)\s*$') {
            $indent = $matches[1]
            $name   = $matches[2]
            $value  = $matches[3]
            $note   = $matches[4]
            if ($value) {
                $output.Add("$indent; $note")
                $output.Add("$indent$name=$value")
                continue
            }
        }

        $output.Add($line)
    }

    return ($output -join $eol)
}

function Backup-QuakeConfigOnce {
    param(
        [string]$Path,
        [bool]$ExistedBefore
    )

    if (-not $ExistedBefore) { return $null }
    if ($script:ConfigBackups.ContainsKey($Path)) { return $script:ConfigBackups[$Path] }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = "$Path.$timestamp.bak"
    Copy-Item -Path $Path -Destination $backupPath -Force
    $script:ConfigBackups[$Path] = $backupPath
    Write-Host "  [Backup] $backupPath" -ForegroundColor DarkYellow
    return $backupPath
}

function Set-QuakeTomlShellBlock {
    param(
        [string]$Content,
        [string]$ShellBlock
    )

    $eol = "`n"
    if ($Content -match "`r`n") { $eol = "`r`n" }

    $ShellBlock = $ShellBlock -replace "`r`n", "`n"
    if ($eol -eq "`r`n") { $ShellBlock = $ShellBlock -replace "`n", "`r`n" }

    $pattern = '(?ms)^\[terminal\.shell\].*?(?=^\[|\Z)'
    if ($Content -match $pattern) {
        $replacement = $ShellBlock + $eol + $eol
        return ($Content -replace $pattern, $replacement)
    }
    return ($Content.TrimEnd() + $eol + $eol + $ShellBlock + $eol)
}

function Test-QuakeNerdFontInstalled {
    $fontKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts",
        "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
    )
    foreach ($key in $fontKeys) {
        if (-not (Test-Path $key)) { continue }
        try {
            $properties = Get-ItemProperty -Path $key -ErrorAction Stop
            foreach ($property in $properties.PSObject.Properties) {
                if ($property.Name -like "*JetBrainsMono Nerd Font*") { return $true }
            }
        } catch { }
    }
    return $false
}

function Get-QuakeAlacrittyVersion {
    $executable = Get-QuakeAlacrittyExecutable
    if (-not $executable) { return $null }
    try {
        # Alacritty is a GUI-subsystem executable: PowerShell's native call
        # operator does not capture its stdout, so read the redirected pipe.
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $executable
        $startInfo.Arguments = "--version"
        $startInfo.RedirectStandardOutput = $true
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $process = [System.Diagnostics.Process]::Start($startInfo)
        $output = $process.StandardOutput.ReadToEnd()
        $process.WaitForExit()
        if ($output -match '(\d+\.\d+\.\d+)') { return $matches[1] }
    } catch { }
    return $null
}

function Get-QuakeAhkVersion {
    $executable = Get-QuakeAhkExecutable
    if (-not $executable) { return $null }
    try {
        $info = (Get-Item $executable).VersionInfo
        if ($info.FileVersion) { return $info.FileVersion.Trim() }
        if ($info.ProductVersion) { return $info.ProductVersion.Trim() }
    } catch { }
    return $null
}

function Get-QuakeWingetUpgradeMap {
    $map = @{}
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) { return $map }

    $lines = @()
    try {
        $lines = & winget upgrade --include-unknown --accept-source-agreements --disable-interactivity 2>$null
        if ($LASTEXITCODE -ne 0) {
            $lines = & winget upgrade --include-unknown --accept-source-agreements 2>$null
        }
    } catch {
        return $map
    }

    foreach ($line in $lines) {
        $clean = ([string]$line) -replace "`b", ""
        $clean = $clean.Trim()
        if ([string]::IsNullOrWhiteSpace($clean)) { continue }

        $parts = @($clean -split '\s+')
        if ($parts.Count -lt 5) { continue }

        $id = $parts[$parts.Count - 4]
        $available = $parts[$parts.Count - 2]
        if ($id -match '^(Alacritty\.Alacritty|AutoHotkey\.AutoHotkey|DEVCOM\.JetBrainsMonoNerdFont)$') {
            $map[$id] = $available
        }
    }
    return $map
}

function Register-QuakeUninstallEntry {
    param(
        [string]$InstallDir,
        [string]$Version,
        [string]$DisplayIcon
    )

    $keyPath = Get-QuakeUninstallRegistryPath
    $estimatedSize = 0
    if (Test-Path $InstallDir) {
        try {
            $totalBytes = (Get-ChildItem -Path $InstallDir -File -Recurse -ErrorAction SilentlyContinue |
                Measure-Object -Property Length -Sum).Sum
            if ($totalBytes) { $estimatedSize = [int][Math]::Ceiling($totalBytes / 1KB) }
        } catch { }
    }

    $entries = [ordered]@{
        "DisplayName"          = "Quake Alacritty Terminal"
        "DisplayVersion"       = $Version
        "Publisher"            = "orgNero"
        "InstallLocation"      = $InstallDir
        "EstimatedSize"        = $estimatedSize
        "NoModify"             = 1
        "NoRepair"             = 1
        "UninstallString"      = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$InstallDir\uninstall.ps1`""
        "QuietUninstallString" = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$InstallDir\uninstall.ps1`" -NonInteractive"
    }
    if ($DisplayIcon) { $entries["DisplayIcon"] = $DisplayIcon }

    if (-not (Test-ShouldApply "Write HKCU Add/Remove Programs entry 'QuakeAlacritty' (version $Version)")) {
        return
    }

    if (-not (Test-Path $keyPath)) {
        New-Item -Path $keyPath -Force | Out-Null
    }

    foreach ($name in $entries.Keys) {
        $value = $entries[$name]
        if ($value -is [int]) {
            New-ItemProperty -Path $keyPath -Name $name -Value $value -PropertyType DWord -Force | Out-Null
        } else {
            New-ItemProperty -Path $keyPath -Name $name -Value $value -PropertyType String -Force | Out-Null
        }
    }
    Write-Host "  [Registry] Registered 'Quake Alacritty Terminal' in Windows Installed Apps" -ForegroundColor Green
}

function Test-QuakeVersionConsistency {
    param(
        [string]$Directory,
        [string]$RepositoryRoot = $Directory
    )

    $problems = New-Object System.Collections.Generic.List[string]
    $versionPath = Join-Path $Directory "VERSION"
    $changelogPath = Join-Path $RepositoryRoot "CHANGELOG.md"
    $version = $null

    if (-not (Test-Path $versionPath)) {
        $problems.Add("VERSION file is missing at $versionPath")
    } else {
        $version = (Get-Content -Path $versionPath -Raw).Trim()
        if ($version -notmatch '^\d+\.\d+\.\d+([-+].*)?$') {
            $problems.Add("VERSION '$version' is not a valid semantic version (expected x.y.z)")
        }
    }

    if (-not (Test-Path $changelogPath)) {
        $problems.Add("CHANGELOG.md is missing at $changelogPath")
    } elseif ($version) {
        $changelog = Get-Content -Path $changelogPath -Raw
        if ($changelog -match '(?m)^##\s*\[(\d+\.\d+\.\d+)\]') {
            $changelogVersion = $matches[1]
            if ($changelogVersion -ne $version) {
                $problems.Add("CHANGELOG.md newest heading ($changelogVersion) does not match VERSION ($version)")
            }
        } else {
            $problems.Add("CHANGELOG.md has no '## [x.y.z]' version heading")
        }
    }

    try {
        $tag = & git -C $Directory describe --tags --abbrev=0 2>$null
        if ($LASTEXITCODE -eq 0 -and $tag) {
            $tagVersion = ($tag.Trim() -replace '^v', '')
            if ($tagVersion -match '^\d+\.\d+\.\d+([-+].*)?$' -and $tagVersion -ne $version) {
                $problems.Add("git tag $($tag.Trim()) does not match VERSION ($version)")
            }
        }
    } catch { }

    return [pscustomobject]@{
        Version  = $version
        Problems = @($problems)
        IsValid  = ($problems.Count -eq 0)
    }
}

# -----------------------------------------------------------------------------
# Version metadata (VERSION / CONFIG_SCHEMA are the source of truth)
# -----------------------------------------------------------------------------
$AppVersion = Get-QuakeVersionFromDir -Directory $SourceDir
if (-not $AppVersion) {
    $AppVersion = "0.0.0-dev"
    Write-Warning "VERSION file is missing or invalid next to install.ps1; using $AppVersion."
}
$ConfigSchema = Get-QuakeConfigSchemaFromDir -Directory $SourceDir
if ($null -eq $ConfigSchema) { $ConfigSchema = 1 }

Write-Host "`n⚡ Quake Alacritty Setup (v$AppVersion)" -ForegroundColor Cyan
Write-Host "=======================" -ForegroundColor DarkGray

# -----------------------------------------------------------------------------
# Standalone modes: -VerifyVersion and -CheckForUpdates
# -----------------------------------------------------------------------------
if ($VerifyVersion) {
    $verification = Test-QuakeVersionConsistency -Directory $SourceDir -RepositoryRoot $RepoRoot
    if ($verification.IsValid) {
        Write-Host "`n✅ Version metadata is consistent (v$($verification.Version))." -ForegroundColor Green
        exit 0
    }
    Write-Host "`n❌ Version metadata is inconsistent:" -ForegroundColor Red
    foreach ($problem in $verification.Problems) {
        Write-Host "   - $problem" -ForegroundColor Red
    }
    exit 1
}

$checkOnly = $true
foreach ($boundParameter in $PSBoundParameters.Keys) {
    if ($boundParameter -notin @('CheckForUpdates', 'PassThru', 'NonInteractive')) { $checkOnly = $false }
}

if ($CheckForUpdates) {
    $installedVersion = Get-QuakeVersionFromDir -Directory $TargetDir
    if (-not $installedVersion) { $installedVersion = $AppVersion }

    $updateCheck = Invoke-QuakeUpdateCheck -InstalledVersion $installedVersion
    if ($updateCheck.Error) {
        Write-Warning "Update check failed (continuing): $($updateCheck.Error)"
    } elseif ($updateCheck.UpdateAvailable) {
        Write-Host "`n⬆️  Update available: v$($updateCheck.InstalledVersion) -> v$($updateCheck.AvailableVersion)" -ForegroundColor Yellow
        Write-Host "   $($updateCheck.CompareUrl)" -ForegroundColor DarkGray
        Write-Host "   Advisory only - nothing was downloaded or installed." -ForegroundColor DarkGray
    } else {
        Write-Host "`n✅ Quake Alacritty is up to date (v$($updateCheck.InstalledVersion))." -ForegroundColor Green
    }

    if ($PassThru) { $updateCheck }
    if ($checkOnly) { exit 0 }
}

# -----------------------------------------------------------------------------
# Helper: Detect Interactive Execution
# -----------------------------------------------------------------------------
$explicitInstallParameters = @(
    'InstallDependencies', 'UpgradeDependencies', 'CreateStartupShortcut',
    'UseSymlinks', 'Shell', 'KeyboardLayout', 'ResetConfig'
)
$hasExplicitInstallParameter = $false
foreach ($name in $explicitInstallParameters) {
    if ($PSBoundParameters.ContainsKey($name)) { $hasExplicitInstallParameter = $true; break }
}

$isInteractive = (-not $NonInteractive) -and
                 (-not $hasExplicitInstallParameter) -and
                 (-not $DryRun) -and
                 (-not $CheckForUpdates) -and
                 (-not $VerifyVersion) -and
                 [Environment]::UserInteractive

# -----------------------------------------------------------------------------
# Detect existing installation (fresh install vs. upgrade)
# -----------------------------------------------------------------------------
$installState = Read-QuakeInstallState -TargetDir $TargetDir
$statePath = Get-QuakeInstallStatePath -TargetDir $TargetDir
$deployedScript = Join-Path $TargetDir "quake_alacritty.ahk"

$installedVersion = $null
if ($installState -and $installState.version) {
    $installedVersion = $installState.version
} else {
    $installedVersion = Get-QuakeVersionFromDir -Directory $TargetDir
}

$isUpgrade = $false
if ($installState -or (Test-Path $statePath)) {
    $isUpgrade = $true
} elseif (Test-Path $deployedScript) {
    $isUpgrade = $true
}

if ($isUpgrade) {
    $installedLabel = if ($installedVersion) { "v$installedVersion" } else { "version unknown" }
    if (-not $installedVersion) { $installedVersion = Get-QuakeVersionFromDir -Directory $TargetDir }
    Write-Host "`n📦 Existing install found ($installedLabel) -> upgrading to v$AppVersion" -ForegroundColor Cyan

    if ($installedVersion) {
        $comparison = Compare-QuakeVersion -Left $AppVersion -Right $installedVersion
        if ($comparison -lt 0) {
            Write-Warning "You are installing v$AppVersion over the newer v$installedVersion."
            if ($isInteractive) {
                $downgradeAnswer = Read-Host "Continue with the downgrade? (y/N) [default: N]"
                if ($downgradeAnswer -notmatch '^(y|yes)$') {
                    Write-Host "Aborted. No files were changed." -ForegroundColor Yellow
                    exit 1
                }
            } else {
                Write-Host "  Continuing because the session is non-interactive." -ForegroundColor DarkYellow
            }
        }
    }
} else {
    Write-Host "`n🚀 No existing install detected -> fresh install of v$AppVersion" -ForegroundColor Cyan
}

# -----------------------------------------------------------------------------
# Step 1: Prerequisites Check & Installation
# -----------------------------------------------------------------------------
# Optional [General] AlacrittyPath override from an existing deployment or the
# repository template (the installer never writes this key itself).
$alacrittyConfigPath = Join-Path $TargetDir "config.ini"
if (-not (Test-Path -LiteralPath $alacrittyConfigPath)) {
    $alacrittyConfigPath = Join-Path $SourceDir "config.ini"
}
$configuredAlacrittyPath = Get-QuakeAlacrittyConfiguredPath -ConfigPath $alacrittyConfigPath

$alacrittyPath = Get-QuakeAlacrittyExecutable -ConfiguredPath $configuredAlacrittyPath
$hasAlacritty = [bool]$alacrittyPath
$ahkExe = Get-QuakeAhkExecutable
$hasAhk = [bool]$ahkExe
$hasFont = Test-QuakeNerdFontInstalled

if ($isInteractive) {
    Write-Host "`n[1/4] Checking Prerequisites:" -ForegroundColor Yellow

    $alacrittyStatus = if ($hasAlacritty) { "Installed" } else { "Not Found" }
    $alacrittyColor  = if ($hasAlacritty) { "Green" } else { "Red" }
    Write-Host "  Alacritty Terminal: $alacrittyStatus" -ForegroundColor $alacrittyColor

    $ahkStatus = if ($hasAhk) { "Installed" } else { "Not Found" }
    $ahkColor  = if ($hasAhk) { "Green" } else { "Red" }
    Write-Host "  AutoHotkey v2:      $ahkStatus" -ForegroundColor $ahkColor

    $fontStatus = if ($hasFont) { "Installed" } else { "Not Found" }
    $fontColor  = if ($hasFont) { "Green" } else { "Red" }
    Write-Host "  JetBrainsMono Font: $fontStatus" -ForegroundColor $fontColor

    if (-not $hasAlacritty -or -not $hasAhk -or -not $hasFont) {
        $installReq = Read-Host "`nWould you like to install missing prerequisites via winget? (Y/n) [default: Y]"
        if ($installReq -eq "" -or $installReq -match '^(y|yes)$') {
            $InstallDependencies = $true
        }
    }
}

if ($InstallDependencies) {
    Write-Host "`n📦 Installing missing prerequisites via winget..." -ForegroundColor Yellow

    if (-not $hasAlacritty) {
        if (Test-ShouldApply "winget install --id Alacritty.Alacritty") {
            Write-Host "  Installing Alacritty..." -ForegroundColor Gray
            winget install -e --id Alacritty.Alacritty --accept-source-agreements --accept-package-agreements
        }
    }

    if (-not $hasAhk) {
        if (Test-ShouldApply "winget install --id AutoHotkey.AutoHotkey") {
            Write-Host "  Installing AutoHotkey v2..." -ForegroundColor Gray
            winget install -e --id AutoHotkey.AutoHotkey --accept-source-agreements --accept-package-agreements
        }
    }

    if (-not $hasFont) {
        if (Test-ShouldApply "winget install --id DEVCOM.JetBrainsMonoNerdFont") {
            Write-Host "  Installing JetBrainsMono Nerd Font..." -ForegroundColor Gray
            winget install -e --id DEVCOM.JetBrainsMonoNerdFont --accept-source-agreements --accept-package-agreements
        }
    }
}

# winget writes new install directories to PATH in the registry, never into this
# already-running process. Rebuild PATH from the registry before probing again,
# otherwise a fresh Alacritty stays "not found" for the rest of the session and
# the AutoHotkey child inherits the same stale environment.
if (-not $DryRun) {
    Reset-QuakeProcessPath
}

# The pre-install probe is stale by definition on a fresh machine. Recompute the
# dependency flags so status output, ARP registration and the final success
# message all reflect what is actually on disk.
$alacrittyPath = Get-QuakeAlacrittyExecutable -ConfiguredPath $configuredAlacrittyPath
$hasAlacritty = [bool]$alacrittyPath
$ahkExe = Get-QuakeAhkExecutable
$hasAhk = [bool]$ahkExe

if ($UpgradeDependencies) {
    Write-Host "`n⬆️  Dependency versions:" -ForegroundColor Yellow

    $installedAlacritty = Get-QuakeAlacrittyVersion
    $installedAhk = Get-QuakeAhkVersion
    $installedFont = if ($hasFont) { "installed" } else { "not found" }
    $availableUpgrades = Get-QuakeWingetUpgradeMap

    $dependencies = @(
        [pscustomobject]@{
            Name    = "Alacritty"
            Id      = "Alacritty.Alacritty"
            Current = $(if ($installedAlacritty) { $installedAlacritty } else { "not found" })
        },
        [pscustomobject]@{
            Name    = "AutoHotkey v2"
            Id      = "AutoHotkey.AutoHotkey"
            Current = $(if ($installedAhk) { $installedAhk } else { "not found" })
        },
        [pscustomobject]@{
            Name    = "JetBrainsMono Nerd Font"
            Id      = "DEVCOM.JetBrainsMonoNerdFont"
            Current = $installedFont
        }
    )

    foreach ($dependency in $dependencies) {
        $available = $availableUpgrades[$dependency.Id]
        $suffix = if ($available) { "-> $available available" } else { "(no upgrade reported)" }
        Write-Host ("  {0,-26} {1}  {2}" -f $dependency.Name, $dependency.Current, $suffix) -ForegroundColor Gray
    }

    foreach ($dependency in $dependencies) {
        if (-not (Test-ShouldApply "winget upgrade --id $($dependency.Id)")) { continue }
        Write-Host "  Upgrading $($dependency.Name)..." -ForegroundColor Gray
        try {
            winget upgrade -e --id $dependency.Id --accept-source-agreements --accept-package-agreements
        } catch {
            Write-Warning "  Could not upgrade $($dependency.Name): $_"
        }
    }
}

# -----------------------------------------------------------------------------
# Step 2: Preferred Shell Selection
# -----------------------------------------------------------------------------
$selectedShell = $null
$shellWasChosen = $false
if ($PSBoundParameters.ContainsKey('Shell')) {
    $selectedShell = $Shell
    $shellWasChosen = ($Shell -ne "keep")
}

function Find-GitBashPath {
    # 1. Registry detection (Git for Windows standard installer keys)
    $regKeys = @(
        "HKLM:\SOFTWARE\GitForWindows",
        "HKCU:\SOFTWARE\GitForWindows",
        "HKLM:\SOFTWARE\WOW6432Node\GitForWindows"
    )
    foreach ($regKey in $regKeys) {
        $installPath = Get-ItemPropertyValue -Path $regKey -Name "InstallPath" -ErrorAction SilentlyContinue
        if ($installPath) {
            $cand = Join-Path $installPath "bin\bash.exe"
            if (Test-Path $cand) { return $cand }
            $candUsr = Join-Path $installPath "usr\bin\bash.exe"
            if (Test-Path $candUsr) { return $candUsr }
        }
    }

    # 2. Derive from git.exe in PATH (handles custom installation directories)
    $cmdGit = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($cmdGit -and $cmdGit.Source) {
        $cmdDir = Split-Path $cmdGit.Source -Parent
        $gitRoot = Split-Path $cmdDir -Parent
        $gitRootCandidates = @(
            (Join-Path $gitRoot "bin\bash.exe"),
            (Join-Path $gitRoot "usr\bin\bash.exe"),
            (Join-Path $cmdDir "..\bin\bash.exe"),
            (Join-Path $cmdDir "..\usr\bin\bash.exe"),
            (Join-Path $cmdDir "bash.exe")
        )
        foreach ($cand in $gitRootCandidates) {
            if ($cand -and (Test-Path $cand)) {
                return (Resolve-Path $cand).Path
            }
        }
    }

    # 3. Standard common installation paths
    $commonGitPaths = @(
        "C:\Program Files\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe",
        "C:\Program Files (x86)\Git\bin\bash.exe",
        "$env:ProgramW6432\Git\bin\bash.exe",
        "C:\Program Files\Git\usr\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\usr\bin\bash.exe"
    )
    foreach ($cand in $commonGitPaths) {
        if ($cand -and (Test-Path $cand)) {
            return $cand
        }
    }

    # 4. Command bash.exe in PATH (skip WindowsApps 0-byte execution alias stub)
    $cmdBash = Get-Command bash.exe -ErrorAction SilentlyContinue
    if ($cmdBash -and $cmdBash.Source -and ($cmdBash.Source -notlike "*WindowsApps*") -and (Test-Path $cmdBash.Source)) {
        return $cmdBash.Source
    }

    return ""
}

$gitBashPath = Find-GitBashPath

if ($isInteractive -and -not $selectedShell) {
    Write-Host "`n[2/4] Choose your default terminal shell:" -ForegroundColor Yellow
    Write-Host "  [1] PowerShell (Default - Windows PowerShell / pwsh)" -ForegroundColor Cyan
    Write-Host "  [2] WSL Bash   (Linux / Ubuntu via wsl.exe)" -ForegroundColor Cyan
    if ($gitBashPath) {
        Write-Host "  [3] Git Bash   (MSYS2 bash.exe)" -ForegroundColor Cyan
    } else {
        Write-Host "  [3] Git Bash   (MSYS2 bash.exe - not found)" -ForegroundColor DarkGray
    }
    Write-Host "  [4] Keep existing configuration" -ForegroundColor Cyan

    $shellChoice = Read-Host "`nSelect shell [1-4] (default: 1)"
    switch ($shellChoice.Trim()) {
        "2" { $selectedShell = "wsl" }
        "3" { $selectedShell = "gitbash" }
        "4" { $selectedShell = "keep" }
        default { $selectedShell = "powershell" }
    }
    $shellWasChosen = ($selectedShell -ne "keep")
}

if (-not $selectedShell) {
    $selectedShell = "powershell"
}

if ($shellWasChosen) {
    if ($selectedShell -eq "wsl") {
        if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
            Write-Warning "WSL was selected, but 'wsl.exe' was not found in PATH. You may need to run 'wsl --install'."
        }
    } elseif ($selectedShell -eq "pwsh") {
        if (-not (Get-Command pwsh.exe -ErrorAction SilentlyContinue)) {
            Write-Warning "PowerShell 7 (pwsh.exe) was selected, but was not found in PATH. Falling back to Windows PowerShell (powershell.exe)."
            $selectedShell = "powershell"
        }
    } elseif ($selectedShell -eq "gitbash") {
        if (-not $gitBashPath) {
            if ($isInteractive) {
                Write-Warning "Git Bash was selected, but 'bash.exe' was not automatically found."
                $customPath = Read-Host "Enter full path to bash.exe (or press Enter to fallback to PowerShell)"
                if ($customPath -and (Test-Path $customPath.Trim())) {
                    $gitBashPath = $customPath.Trim()
                } else {
                    Write-Warning "Valid bash.exe not provided. Falling back to PowerShell default shell."
                    $selectedShell = "powershell"
                }
            } else {
                Write-Warning "Git Bash was selected, but 'bash.exe' was not found on this system. Falling back to PowerShell to avoid terminal crash."
                $selectedShell = "powershell"
            }
        }
    }
}

# -----------------------------------------------------------------------------
# Step 3: Keyboard Layout & Toggle Hotkey Selection
# -----------------------------------------------------------------------------
$selectedLayout = $null
$layoutWasChosen = $false
if ($PSBoundParameters.ContainsKey('KeyboardLayout')) {
    $selectedLayout = $KeyboardLayout
    $layoutWasChosen = $true
}

if ($isInteractive -and -not $selectedLayout) {
    Write-Host "`n[3/4] Choose your keyboard layout for the visor toggle hotkey:" -ForegroundColor Yellow
    Write-Host "  [1] Nordic / Swedish layout (Win + §, key below Escape) [Default]" -ForegroundColor Cyan
    Write-Host "  [2] US / Standard ANSI layout (Win + backtick, key below Escape)" -ForegroundColor Cyan

    $layoutChoice = Read-Host "`nSelect layout [1-2] (default: 1)"
    switch ($layoutChoice.Trim()) {
        "2" { $selectedLayout = "us" }
        default { $selectedLayout = "nordic" }
    }
    $layoutWasChosen = $true
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
# Step 5: Deploy Application Files & Version Metadata
# -----------------------------------------------------------------------------
Write-Host "`n📁 Deploying files to: $TargetDir" -ForegroundColor Yellow

if (-not (Test-Path $TargetDir)) {
    if (Test-ShouldApply "Create directory $TargetDir") {
        New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
    }
}

$destToml = Join-Path $TargetDir "alacritty.toml"
$destIni  = Join-Path $TargetDir "config.ini"
$destTomlExisted = Test-Path $destToml
$destIniExisted  = Test-Path $destIni

$appFiles = @("quake_alacritty.ahk", "welcome.ps1", "uninstall.ps1", "quake_common.ps1", "update.ps1", "update-check.ps1", "VERSION", "CONFIG_SCHEMA")
foreach ($file in $appFiles) {
    $source = Join-Path $SourceDir $file
    $destination = Join-Path $TargetDir $file

    if (-not (Test-Path $source)) {
        Write-Warning "  Skipping missing source file: $file"
        continue
    }

    if ($UseSymlinks) {
        if (Test-ShouldApply "Symlink $file -> $destination") {
            if (Test-Path $destination) { Remove-Item $destination -Force }
            New-Item -ItemType SymbolicLink -Path $destination -Target $source -Force | Out-Null
            Write-Host "  [Link] $file -> $destination" -ForegroundColor Green
        }
    } elseif (Test-ShouldApply "Copy $file -> $destination") {
        Copy-Item -Path $source -Destination $destination -Force
        Write-Host "  [Copy] $file -> $destination" -ForegroundColor Green
    }
}

# A stale update-check cache would keep advertising the version we just deployed.
$updateCachePath = Join-Path $TargetDir ".update-check.json"
if (-not $DryRun -and (Test-Path $updateCachePath)) {
    Remove-Item -Path $updateCachePath -Force -ErrorAction SilentlyContinue
    Write-Host "  [Cache] Cleared stale update-check cache" -ForegroundColor Green
}

# A stale notice marker would hide a notice for a version that is still pending.
$updateNoticePath = Join-Path $TargetDir ".update-notice"
if (-not $DryRun -and (Test-Path $updateNoticePath)) {
    Remove-Item -Path $updateNoticePath -Force -ErrorAction SilentlyContinue
    Write-Host "  [Cache] Cleared stale update notice marker" -ForegroundColor Green
}

# Config files are user-owned: copy only when absent, merge when present, replace on -ResetConfig.
foreach ($file in @("alacritty.toml", "config.ini")) {
    $source = Join-Path $SourceDir $file
    $destination = Join-Path $TargetDir $file

    if (-not (Test-Path $source)) {
        Write-Warning "  Skipping missing source file: $file"
        continue
    }

    if ($UseSymlinks) {
        if (Test-ShouldApply "Symlink $file -> $destination") {
            if (Test-Path $destination) { Remove-Item $destination -Force }
            New-Item -ItemType SymbolicLink -Path $destination -Target $source -Force | Out-Null
            Write-Host "  [Link] $file -> $destination" -ForegroundColor Green
        }
        continue
    }

    if (-not (Test-Path $destination)) {
        if (Test-ShouldApply "Copy $file -> $destination") {
            Copy-Item -Path $source -Destination $destination -Force
            Write-Host "  [Copy] $file -> $destination" -ForegroundColor Green
        }
    } elseif ($ResetConfig) {
        if (Test-ShouldApply "Reset $file to factory defaults (backup first)") {
            Backup-QuakeConfigOnce -Path $destination -ExistedBefore $true | Out-Null
            Copy-Item -Path $source -Destination $destination -Force
            Write-Host "  [Reset] $file restored to factory defaults" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [Preserve] $file (use -ResetConfig to restore factory defaults)" -ForegroundColor Cyan
    }
}

# -----------------------------------------------------------------------------
# Step 6: Merge Missing config.ini Keys & Configure Preferred Shell
# -----------------------------------------------------------------------------
$templateIni = Join-Path $SourceDir "config.ini"
if ($destIniExisted -and -not $ResetConfig -and -not $UseSymlinks -and (Test-Path $templateIni)) {
    if ($DryRun -and -not (Test-Path $destIni)) {
        Write-Host "  [DryRun] Merge missing keys from config.ini template into $destIni" -ForegroundColor DarkCyan
    } else {
        $templateText = [System.IO.File]::ReadAllText($templateIni)
        $destinationText = [System.IO.File]::ReadAllText($destIni)
        $merge = Merge-QuakeIniContent -TemplateText $templateText -DestinationText $destinationText

        if ($merge.AddedKeys.Count -gt 0 -or $merge.AddedSections.Count -gt 0) {
            $details = @()
            if ($merge.AddedSections.Count -gt 0) { $details += "section(s): " + ($merge.AddedSections -join ", ") }
            if ($merge.AddedKeys.Count -gt 0) { $details += "key(s): " + ($merge.AddedKeys -join ", ") }
            if (Test-ShouldApply "Merge config.ini additions -> $($details -join '; ')") {
                Backup-QuakeConfigOnce -Path $destIni -ExistedBefore $true | Out-Null
                Write-QuakeTextFile -Path $destIni -Content $merge.Text
                Write-Host "  [Merge] config.ini: added $($details -join '; ')" -ForegroundColor Green
            }
        } else {
            Write-Host "  [Config] config.ini already has every template key" -ForegroundColor DarkGray
        }
    }
}

if ($shellWasChosen -and ($selectedShell -ne "keep")) {
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

    if (Test-Path $destToml) {
        $tomlContent = [System.IO.File]::ReadAllText($destToml)
        $updatedToml = Set-QuakeTomlShellBlock -Content $tomlContent -ShellBlock $newShellBlock

        if ($updatedToml -ne $tomlContent) {
            if (Test-ShouldApply "Configure $selectedShell shell in alacritty.toml") {
                Backup-QuakeConfigOnce -Path $destToml -ExistedBefore $destTomlExisted | Out-Null
                Write-QuakeTextFile -Path $destToml -Content $updatedToml
                Write-Host "  [Config] Configured $selectedShell shell in alacritty.toml" -ForegroundColor Green
            }
        } else {
            Write-Host "  [Config] alacritty.toml already configured for $selectedShell" -ForegroundColor DarkGray
        }
    } elseif ($DryRun) {
        Write-Host "  [DryRun] Configure $selectedShell shell in alacritty.toml" -ForegroundColor DarkCyan
    }
}

if (Test-Path $destIni) {
    $iniContent = [System.IO.File]::ReadAllText($destIni)
    $iniEol = if ($iniContent -match "`r`n") { "`r`n" } else { "`n" }
    $updatedIni = Convert-QuakeHotkeyComments -Content $iniContent

    # Note: In AutoHotkey, scan code sc029 is the key directly below Esc on both Swedish (§) and US (`).
    if ($layoutWasChosen) {
        $layoutNote = if ($selectedLayout -eq "us") {
            '; Win + backtick (key below Esc on US ANSI)'
        } else {
            '; Win + § (key below Esc on Swedish ISO)'
        }
        $toggleBlock = $layoutNote + $iniEol + 'ToggleVisor=#sc029'

        if ($updatedIni -match '(?m)^\s*ToggleVisor=') {
            # Consume the layout note we wrote last time (or the one shipped in the
            # template) together with the key line, so re-running cannot stack notes.
            $updatedIni = $updatedIni -replace '(?m)^(?:;[ \t]*(?:Win \+|#sc029 is Win \+)[^\r\n]*\r?\n)?[ \t]*ToggleVisor=[^\r\n]*', $toggleBlock
        } else {
            $updatedIni = $updatedIni.TrimEnd() + $iniEol + $iniEol + "[Hotkeys]" + $iniEol + $toggleBlock + $iniEol
        }
    }

    if ($updatedIni -ne $iniContent) {
        if (Test-ShouldApply "Update config.ini hotkey/startup settings") {
            Backup-QuakeConfigOnce -Path $destIni -ExistedBefore $destIniExisted | Out-Null
            Write-QuakeTextFile -Path $destIni -Content $updatedIni
            Write-Host "  [Config] Updated config.ini settings" -ForegroundColor Green
        }
    } elseif ($layoutWasChosen) {
        Write-Host "  [Config] Configured $selectedLayout keyboard layout in config.ini" -ForegroundColor DarkGray
    }
}

# -----------------------------------------------------------------------------
# Step 7: Windows Startup Shortcut Registration
# -----------------------------------------------------------------------------
if ($shouldCreateStartup) {
    Write-Host "`n🚀 Setting up Windows Startup shortcut..." -ForegroundColor Yellow
    if (Test-ShouldApply "Create startup shortcut $shortcutPath") {
        $WshShell = New-Object -ComObject WScript.Shell
        $shortcut = $WshShell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = Join-Path $TargetDir "quake_alacritty.ahk"
        $shortcut.WorkingDirectory = $TargetDir
        $shortcut.Description = "Quake Alacritty Terminal Visor"
        $shortcut.Save()
        Write-Host "  Created startup shortcut: $shortcutPath" -ForegroundColor Green
    }
}

# -----------------------------------------------------------------------------
# Step 8: Shell Profile Registration (PowerShell & Git Bash)
# -----------------------------------------------------------------------------
# One idempotent block per shell, delimited by markers. On every run the block
# is removed and rewritten, and legacy unmarked lines are cleaned up, so running
# the installer twice can never duplicate a function.

$profileBlockPattern = '(?s)\r?\n?# >>> Quake Alacritty >>>.*?# <<< Quake Alacritty <<<[ \t]*\r?\n?'
$legacyProfilePattern = '(?m)^\s*# Quake Alacritty Cheat Sheet[^\r\n]*[\r\n]+|^\s*function quake-(help|env|update)\s*\{[^}]*\}\s*[\r\n]*'
$legacyBashPattern = '(?m)^\s*# Quake Alacritty Cheat Sheet[^\r\n]*[\r\n]+|^\s*quake-(help|env|update)\(\)\s*\{[^\r\n]*\}\s*[\r\n]*'
$legacyBashHintPattern = '(?ms)^if \[ -n "\$QUAKE_SHOW_HELP" \].*?^fi[ \t]*[\r\n]*'

$powerShellBlock = @'
# >>> Quake Alacritty >>>
function quake-help  { & "$env:APPDATA\alacritty\welcome.ps1" @args }
function quake-env   { & "$env:APPDATA\alacritty\welcome.ps1" -EnvInfo }
function quake-update { & "$env:APPDATA\alacritty\update.ps1" @args }
# <<< Quake Alacritty <<<
'@ -replace "`r?`n", "`r`n"
$powerShellBlock = $powerShellBlock.TrimEnd() + "`r`n"

$bashBlock = @'
# >>> Quake Alacritty >>>
quake-help() { powershell.exe -NoLogo -ExecutionPolicy Bypass -File "$APPDATA/alacritty/welcome.ps1" "$@"; }
quake-env() { powershell.exe -NoLogo -ExecutionPolicy Bypass -File "$APPDATA/alacritty/welcome.ps1" -EnvInfo; }
quake-update() { local a=(); for x in "$@"; do if [ "$x" = "--check" ]; then a+=("-Check"); else a+=("$x"); fi; done; powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$APPDATA/alacritty/update.ps1" "${a[@]}"; }
quake_version_is_newer() {
    local a=${1#v} b=${2#v}
    a=${a%%[-+]*} b=${b%%[-+]*}
    local IFS=.
    local -a av=($a) bv=($b)
    local i x y
    for ((i = 0; i < 3; i++)); do
        x=${av[i]:-0}
        y=${bv[i]:-0}
        [[ $x =~ ^[0-9]+$ && $y =~ ^[0-9]+$ ]] || return 1
        x=$((10#$x))
        y=$((10#$y))
        ((x > y)) && return 0
        ((x < y)) && return 1
    done
    return 1
}
quake_update_notice() {
    [ -n "$APPDATA" ] || return 0
    local dir="$APPDATA/alacritty" raw latest installed shown today
    [ -f "$dir/.update-check.json" ] || return 0
    raw=$(<"$dir/.update-check.json")
    [[ $raw =~ \"latestVersion\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && latest=${BASH_REMATCH[1]}
    [[ $raw =~ \"installedVersion\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && installed=${BASH_REMATCH[1]}
    if [ -f "$dir/VERSION" ]; then
        installed=$(<"$dir/VERSION")
    fi
    latest=${latest#v}
    installed=${installed#v}
    installed=${installed//[[:space:]]/}
    [ -n "$latest" ] && [ -n "$installed" ] || return 0
    [[ $latest =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 0
    quake_version_is_newer "$latest" "$installed" || return 0

    today=$(printf "%(%Y%m%d)T" -1)
    if [ -f "$dir/.update-notice" ]; then
        shown=$(<"$dir/.update-notice")
        [ "${shown//[[:space:]]/}" = "$today" ] && return 0
    fi

    printf '%b\n' "  \033[38;2;251;191;36m⬆ \033[38;2;148;163;184mUpdate available: v$latest (you have v$installed). Type '\033[1;38;2;56;189;248mquake-update\033[0;38;2;148;163;184m'.\033[0m"
    printf '%s\n' "$today" > "$dir/.update-notice" 2>/dev/null || true
}
if [ -n "$QUAKE_SHOW_HELP" ] && [ "$QUAKE_SHOW_HELP" != "none" ]; then
    if [ "$QUAKE_SHOW_HELP" = "banner" ]; then
        powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$APPDATA/alacritty/welcome.ps1" -Startup
    else
        printf '%b\n' "\n  \033[38;2;251;191;36m💡 \033[38;2;148;163;184mTip: Type '\033[1;38;2;56;189;248mquake-help\033[0;38;2;148;163;184m' to view keyboard shortcuts.\033[0m\n"
        quake_update_notice
    fi
fi
# <<< Quake Alacritty <<<
'@ -replace "`r`n", "`n"
$bashBlock = $bashBlock.TrimEnd() + "`n"

# 8a: PowerShell profile registration
if (Test-Path $PROFILE) {
    try {
        $profileContent = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
        if ($null -eq $profileContent) { $profileContent = "" }

        $updatedProfile = [regex]::Replace($profileContent, $profileBlockPattern, "`r`n")
        $updatedProfile = [regex]::Replace($updatedProfile, $legacyProfilePattern, '')
        $updatedProfile = $updatedProfile.TrimEnd()
        if ($updatedProfile.Length -gt 0) { $updatedProfile += "`r`n`r`n" }
        $updatedProfile += $powerShellBlock.TrimEnd()
        $updatedProfile = $updatedProfile.TrimEnd() + "`r`n"

        if ($updatedProfile -ceq $profileContent) {
            Write-Host "  [Profile] quake-help, quake-env and quake-update already registered in `$PROFILE" -ForegroundColor DarkGray
        } elseif (Test-ShouldApply "Register 'quake-help', 'quake-env' and 'quake-update' in `$PROFILE") {
            Write-QuakeTextFile -Path $PROFILE -Content $updatedProfile -ForceBom $true
            Write-Host "  [Profile] Registered 'quake-help', 'quake-env' and 'quake-update' in `$PROFILE" -ForegroundColor Green
        }
    } catch {
        Write-Warning "  Could not update PowerShell profile: $_"
    }
}

# 8b: Git Bash profile registration (~/.bashrc)
$bashrcPath = Join-Path $env:USERPROFILE ".bashrc"
if ($selectedShell -eq "gitbash" -or (Test-Path $bashrcPath)) {
    try {
        $bashrcContent = if (Test-Path $bashrcPath) { Get-Content $bashrcPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue } else { "" }
        if ($null -eq $bashrcContent) { $bashrcContent = "" }

        $updatedBashrc = [regex]::Replace($bashrcContent, $profileBlockPattern, "`n")
        $updatedBashrc = [regex]::Replace($updatedBashrc, $legacyBashPattern, '')
        $updatedBashrc = [regex]::Replace($updatedBashrc, $legacyBashHintPattern, '')
        $updatedBashrc = $updatedBashrc.TrimEnd()
        if ($updatedBashrc.Length -gt 0) { $updatedBashrc += "`n`n" }
        $updatedBashrc += $bashBlock.TrimEnd()
        $updatedBashrc = $updatedBashrc.TrimEnd() + "`n"

        if ($updatedBashrc -ceq $bashrcContent) {
            Write-Host "  [Profile] quake-help, quake-env and quake-update already registered in $bashrcPath" -ForegroundColor DarkGray
        } elseif (Test-ShouldApply "Register 'quake-help', 'quake-env' and 'quake-update' in $bashrcPath") {
            [System.IO.File]::WriteAllText($bashrcPath, $updatedBashrc, (New-Object System.Text.UTF8Encoding($false)))
            Write-Host "  [Profile] Registered 'quake-help', 'quake-env' and 'quake-update' in $bashrcPath" -ForegroundColor Green
        }
    } catch {
        Write-Warning "  Could not update .bashrc: $_"
    }
}

# -----------------------------------------------------------------------------
# Step 9: Windows "Installed Apps" (ARP) Registration
# -----------------------------------------------------------------------------
Write-Host "`n🧾 Windows Installed Apps registration..." -ForegroundColor Yellow
$defaultTarget = (Get-QuakeTargetDir)
$isDefaultTarget = ([System.IO.Path]::GetFullPath($TargetDir).TrimEnd('\') -ieq [System.IO.Path]::GetFullPath($defaultTarget).TrimEnd('\'))

if (-not $isDefaultTarget) {
    Write-Host "  [Skip] Deploy target is not $defaultTarget (portable mode)" -ForegroundColor DarkGray
} elseif ($UseSymlinks) {
    Write-Host "  [Skip] Symlink development deployments are not registered as installed apps" -ForegroundColor DarkGray
} else {
    $displayIcon = $null
    if ($alacrittyPath) { $displayIcon = "$alacrittyPath,0" }
    elseif ($ahkExe) { $displayIcon = "$ahkExe,0" }

    Register-QuakeUninstallEntry -InstallDir $TargetDir -Version $AppVersion -DisplayIcon $displayIcon
}

# -----------------------------------------------------------------------------
# Step 10: Persist Install State
# -----------------------------------------------------------------------------
$gitCommit = $null
try {
    $gitOutput = & git -C $SourceDir rev-parse --short HEAD 2>$null
    if ($LASTEXITCODE -eq 0 -and $gitOutput) { $gitCommit = $gitOutput.Trim() }
} catch { }

$previousInstalledAt = $null
if ($installState -and $installState.installedAt) { $previousInstalledAt = $installState.installedAt }

$stateShell = "keep"
if ($shellWasChosen) { $stateShell = $selectedShell }
elseif ($installState -and $installState.shell) { $stateShell = $installState.shell }

$stateLayout = "keep"
if ($layoutWasChosen) { $stateLayout = $selectedLayout }
elseif ($installState -and $installState.layout) { $stateLayout = $installState.layout }

# Record how this copy was obtained. "repo" only when src/ belongs to a git
# work tree whose root is its parent; a ZIP extracted inside another repository
# must stay "zip". sourceDir always points at the tree root (Install.cmd/README
# for a ZIP, the clone root for a repository), never at the src/ folder.
$sourceType = "zip"
$sourceDirResolved = $null
try {
    $sourceDirResolved = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd('\')
    $gitTopLevel = & git -C $SourceDir rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($gitTopLevel)) {
        $gitTopResolved = [System.IO.Path]::GetFullPath(([string]$gitTopLevel).Trim()).TrimEnd('\')
        if ([string]::Equals($gitTopResolved, $sourceDirResolved, [System.StringComparison]::OrdinalIgnoreCase)) {
            $sourceType = "repo"
        }
    }
} catch {
    $sourceType = "zip"
}
if (-not $sourceDirResolved) { $sourceDirResolved = "" }

if (Test-ShouldApply "Write install state to $statePath (v$AppVersion, schema $ConfigSchema)") {
    Write-QuakeInstallState -TargetDir $TargetDir -Version $AppVersion -ConfigSchema $ConfigSchema `
        -GitCommit $gitCommit -InstalledAt $previousInstalledAt -Shell $stateShell -Layout $stateLayout `
        -SourceType $sourceType -SourceDir $sourceDirResolved | Out-Null
    Write-Host "  [State] Recorded install state: v$AppVersion (config schema $ConfigSchema, source $sourceType)" -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# Step 11: Graceful Teardown & Relaunch
# -----------------------------------------------------------------------------
Write-Host "`n🔄 Starting AutoHotkey script..." -ForegroundColor Yellow
$allowedScriptPaths = @(
    (Join-Path $TargetDir "quake_alacritty.ahk"),
    (Join-Path $SourceDir "quake_alacritty.ahk")
)

if ($DryRun) {
    Write-Host "  [DryRun] Stop running Quake Alacritty AutoHotkey instance(s) (graceful quit, then force)" -ForegroundColor DarkCyan
    Write-Host "  [DryRun] Start $TargetDir\quake_alacritty.ahk" -ForegroundColor DarkCyan
} else {
    $stoppedCount = Stop-QuakeAhkProcess -AllowedScriptPaths $allowedScriptPaths
    if ($stoppedCount -gt 0) {
        Write-Host "  Stopped $stoppedCount running instance(s)." -ForegroundColor Green
    }

    $ahkExe = Get-QuakeAhkExecutable
    if ($ahkExe -and (Test-Path $ahkExe)) {
        Start-Process -FilePath $ahkExe -ArgumentList "`"$TargetDir\quake_alacritty.ahk`""
        $toggleKeyDesc = if ($layoutWasChosen) {
            if ($selectedLayout -eq "us") { "Win + backtick (tilde)" } else { "Win + §" }
        } else {
            "your configured ToggleVisor hotkey"
        }

        # Never claim success for a visor that cannot find its terminal. The
        # same resolver order is used by quake_alacritty.ahk at launch time;
        # re-read the override because -ResetConfig may have removed it.
        $configuredAlacrittyPath = Get-QuakeAlacrittyConfiguredPath -ConfigPath $alacrittyConfigPath
        $terminalPath = Get-QuakeAlacrittyExecutable -ConfiguredPath $configuredAlacrittyPath
        if ($terminalPath) {
            Write-Host "  AutoHotkey visor is running! Press $toggleKeyDesc to toggle." -ForegroundColor Green
        } else {
            Write-Host "  AutoHotkey is running, but Alacritty could not be found yet." -ForegroundColor Yellow
            Write-Host "  Log out or restart Windows once so the updated PATH reaches AutoHotkey," -ForegroundColor Yellow
            Write-Host "  then start the visor again (the Startup shortcut does this automatically)" -ForegroundColor Yellow
            Write-Host "  and press $toggleKeyDesc. Re-running this installer is not required." -ForegroundColor Yellow
            Write-Host "  If Alacritty is not installed at all: winget install -e --id Alacritty.Alacritty" -ForegroundColor DarkGray
            Write-Host "  If Alacritty is installed in a custom folder, add AlacrittyPath=<full path to alacritty.exe> to $TargetDir\config.ini." -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  AutoHotkey executable not found in standard path. Please launch quake_alacritty.ahk manually." -ForegroundColor Red
    }
}

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
$actionLabel = if ($isUpgrade) { "upgraded" } else { "installed" }
Write-Host "`n✨ Quake Alacritty v$AppVersion $actionLabel!" -ForegroundColor Cyan
Write-Host "💡 Check for newer versions anytime: .\src\install.ps1 -CheckForUpdates" -ForegroundColor DarkGray
Write-Host "💡 To uninstall anytime, run: powershell -File `"$TargetDir\uninstall.ps1`"" -ForegroundColor DarkGray
Write-Host "💬 Have feedback, bugs, or feature ideas? Open an issue: $RepositoryUrl/issues`n" -ForegroundColor DarkGray
