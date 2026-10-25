[CmdletBinding()]
param(
    [switch]$Check,
    [int]$TimeoutSeconds = 3
)

<#
.SYNOPSIS
    Updates a Quake Alacritty installation from its original install source.

.DESCRIPTION
    Gives the user exactly one command to run. A repository install is updated
    with a fast-forward-only git pull followed by the freshly pulled installer.
    A ZIP install is told where to download the next release, because there is
    nothing to pull. The running script never replaces itself in place: the
    installer is always launched as a child process.

    The background update check remains advisory; this script is only ever run
    by a human.

.PARAMETER Check
    Only report whether a newer version is available. Nothing is pulled,
    installed or written.

.PARAMETER TimeoutSeconds
    HTTP timeout for the advisory version check (default 3).
#>

$ErrorActionPreference = "Stop"

$commonPath = Join-Path $PSScriptRoot "quake_common.ps1"
if (-not (Test-Path $commonPath)) {
    Write-Host "quake_common.ps1 was not found next to update.ps1. Run install.ps1 again, then retry."
    exit 1
}
. $commonPath

$releasesUrl = "https://github.com/orgNero/quake-alacritty/releases/latest"
$targetDir = Get-QuakeTargetDir
$installState = Read-QuakeInstallState -TargetDir $targetDir

if ($null -eq $installState) {
    Write-Host "Quake Alacritty install state was not found. Run install.ps1 again, then retry."
    exit 1
}

$installedVersion = Get-QuakeVersionFromDir -Directory $targetDir
if (-not $installedVersion -and $installState.version) {
    $installedVersion = [string]$installState.version
}

function Get-QuakeShortReason {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return "unknown error" }
    $line = ($Text -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($line)) { return "unknown error" }
    $line = $line.Trim()
    if ($line.Length -gt 200) { $line = $line.Substring(0, 200) + "..." }
    return $line
}

function Invoke-QuakeGit {
    param(
        [string]$Directory,
        [string[]]$Arguments
    )

    $stderrPath = Join-Path ([System.IO.Path]::GetTempPath()) ("quake-git-" + [guid]::NewGuid().ToString("N") + ".log")
    $output = @()
    $exitCode = 1
    $previousPreference = $ErrorActionPreference

    # Windows PowerShell 5.1 turns native stderr into a terminating
    # NativeCommandError when $ErrorActionPreference = "Stop", even when stderr
    # is redirected. Relax it for this call and restore it in finally.
    try {
        $ErrorActionPreference = "Continue"
        $output = @(& git -C $Directory @Arguments 2> $stderrPath | ForEach-Object { [string]$_ })
        $exitCode = $LASTEXITCODE
    } catch {
        $output = @()
        $exitCode = 1
    } finally {
        $ErrorActionPreference = $previousPreference
    }

    $stderrText = ""
    if (Test-Path $stderrPath) {
        $stderrText = [System.IO.File]::ReadAllText($stderrPath)
        Remove-Item -Path $stderrPath -Force -ErrorAction SilentlyContinue
    }

    $lines = @($output) + @($stderrText -split "`r?`n")
    return [pscustomobject]@{
        ExitCode  = $exitCode
        Output    = @($output)
        ErrorText = $stderrText
        Lines     = $lines
        Text      = ($lines -join "`n")
    }
}

function Get-QuakeGitLastLine {
    param([object[]]$Lines)

    $fallback = $null
    $diagnostic = $null
    foreach ($line in @($Lines)) {
        $text = ([string]$line).Trim()
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        if ($text -match '^(fatal|error|hint):') {
            $diagnostic = $text
        } elseif ($text -notmatch '^(\+|At |CategoryInfo|FullyQualifiedErrorId|Exception|    \+)') {
            $fallback = $text
        }
    }
    if ($diagnostic) { return $diagnostic }
    return $fallback
}

function Test-QuakeGitRepoRoot {
    param([string]$Directory)

    if ([string]::IsNullOrWhiteSpace($Directory) -or -not (Test-Path $Directory)) { return $false }
    $result = Invoke-QuakeGit -Directory $Directory -Arguments @('rev-parse', '--show-toplevel')
    if ($result.ExitCode -ne 0) { return $false }

    $topLevel = (@($result.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($topLevel)) { return $false }

    try {
        $topPath = [System.IO.Path]::GetFullPath(([string]$topLevel).Trim()).TrimEnd('\')
        $directoryPath = [System.IO.Path]::GetFullPath($Directory).TrimEnd('\')
        return [string]::Equals($topPath, $directoryPath, [System.StringComparison]::OrdinalIgnoreCase)
    } catch {
        return $false
    }
}

function Invoke-QuakeZipInstructions {
    param([string]$Reason)

    if (-not [string]::IsNullOrWhiteSpace($Reason)) {
        Write-Host $Reason
    }

    $check = Invoke-QuakeUpdateCheck -InstalledVersion $installedVersion -TimeoutSeconds $TimeoutSeconds
    if ($check.Error) {
        Write-Host ("Could not check for updates: " + (Get-QuakeShortReason -Text ([string]$check.Error)) + ".")
        Write-Host ("Download the latest release: " + $releasesUrl)
        return 0
    }

    if (-not $check.UpdateAvailable) {
        Write-Host ("Already on the latest version (v{0})." -f $installedVersion)
        return 0
    }

    Write-Host ("A newer version (v{0}) is available." -f $check.AvailableVersion)
    Write-Host "This install was made from a ZIP, so there is nothing to pull."
    Write-Host ("Download: " + $releasesUrl)
    Write-Host "Extract it, then run Install.cmd."
    return 0
}

function Invoke-QuakeRepoUpdate {
    param([string]$SourceDir)

    $gitCommand = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitCommand) {
        Write-Host "Git is not installed or not on PATH."
        Write-Host ("Download the latest release instead: " + $releasesUrl)
        return 1
    }

    if (-not (Test-QuakeGitRepoRoot -Directory $SourceDir)) {
        return (Invoke-QuakeZipInstructions -Reason "The Git clone this install came from has moved or is no longer a repository.")
    }

    $statusResult = Invoke-QuakeGit -Directory $SourceDir -Arguments @('status', '--porcelain', '--untracked-files=no')
    if ($statusResult.ExitCode -ne 0) {
        Write-Host "Could not inspect the Git clone. Run install.ps1 again, then retry."
        return 1
    }
    if (-not [string]::IsNullOrWhiteSpace((@($statusResult.Output | Where-Object { $_ }) -join ""))) {
        Write-Host "Your repo has uncommitted changes. Commit or stash them, then run 'quake-update' again."
        return 1
    }

    $headRefResult = Invoke-QuakeGit -Directory $SourceDir -Arguments @('symbolic-ref', '--quiet', '--short', 'HEAD')
    if ($headRefResult.ExitCode -ne 0) {
        Write-Host "Your repo is in detached HEAD state. Check out a branch, then try again."
        return 1
    }

    $upstreamResult = Invoke-QuakeGit -Directory $SourceDir -Arguments @('rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}')
    $upstream = (@($upstreamResult.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) | Select-Object -First 1)
    if ($upstreamResult.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($upstream)) {
        Write-Host "Your current branch has no upstream. Set one with 'git push -u origin <branch>', then try again."
        return 1
    }

    $headBeforeResult = Invoke-QuakeGit -Directory $SourceDir -Arguments @('rev-parse', 'HEAD')
    $headBefore = (@($headBeforeResult.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) | Select-Object -First 1)
    $headBefore = ([string]$headBefore).Trim()

    $pullResult = Invoke-QuakeGit -Directory $SourceDir -Arguments @('pull', '--ff-only')
    if ($pullResult.ExitCode -ne 0) {
        $pullText = $pullResult.Text
        $lastLine = Get-QuakeGitLastLine -Lines $pullResult.Lines

        if ($pullText -match 'Not possible to fast-forward|diverged|non-fast-forward') {
            Write-Host "Your branch has diverged from GitHub. Merge or rebase it manually, then try again."
        } else {
            Write-Host "Could not update from GitHub. Check your connection and try again."
        }
        if (-not [string]::IsNullOrWhiteSpace($lastLine)) {
            Write-Host ("  " + $lastLine) -ForegroundColor DarkGray
        }
        return 1
    }

    $headAfterResult = Invoke-QuakeGit -Directory $SourceDir -Arguments @('rev-parse', 'HEAD')
    $headAfter = (@($headAfterResult.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) | Select-Object -First 1)
    $headAfter = ([string]$headAfter).Trim()

    if ($headBefore -and $headAfter -and $headBefore -eq $headAfter) {
        Write-Host ("Already on the latest version (v{0})." -f $installedVersion)
        return 0
    }

    $installer = Join-Path $SourceDir "install.ps1"
    if (-not (Test-Path $installer)) {
        Write-Host "install.ps1 was not found in the updated clone. Run the installer manually to see the details."
        return 1
    }

    $powerShellExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path $powerShellExe)) { $powerShellExe = "powershell.exe" }

    # The call operator waits for this child process only. Start-Process -Wait
    # also waits for grandchildren (the installer relaunches AutoHotkey), which
    # would block forever.
    $installerExitCode = 1
    try {
        & $powerShellExe -NoProfile -ExecutionPolicy Bypass -File $installer -Shell keep -NonInteractive
        $installerExitCode = $LASTEXITCODE
    } catch {
        Write-Host ("The installer could not be started: " + (Get-QuakeShortReason -Text $_.Exception.Message))
        Write-Host "Your config was not removed. Run install.ps1 manually to see the details."
        return 1
    }

    if ($installerExitCode -ne 0) {
        Write-Host ("The installer failed (exit {0}). Your config was not removed. Run install.ps1 manually to see the details." -f $installerExitCode)
        return 1
    }

    $newVersion = Get-QuakeVersionFromDir -Directory $targetDir
    if (-not $newVersion) {
        $newState = Read-QuakeInstallState -TargetDir $targetDir
        if ($newState -and $newState.version) { $newVersion = [string]$newState.version }
    }
    if (-not $newVersion) { $newVersion = "the latest version" }

    Write-Host ("Updated to v{0}. Toggle the visor once to retile." -f $newVersion)
    return 0
}

if ($Check) {
    $result = Invoke-QuakeUpdateCheck -InstalledVersion $installedVersion -TimeoutSeconds $TimeoutSeconds
    if ($result.Error) {
        Write-Host ("Could not check for updates: " + (Get-QuakeShortReason -Text ([string]$result.Error)) + ".")
        exit 1
    }
    if ($result.UpdateAvailable) {
        Write-Host ("Update available: v{0} (you have v{1}). Run 'quake-update' to install." -f $result.AvailableVersion, $installedVersion)
    } else {
        Write-Host ("Already on the latest version (v{0})." -f $installedVersion)
    }
    exit 0
}

$sourceType = ""
if ($null -ne $installState.PSObject.Properties['sourceType']) {
    $sourceType = [string]$installState.sourceType
}
$sourceDir = ""
if ($null -ne $installState.PSObject.Properties['sourceDir']) {
    $sourceDir = [string]$installState.sourceDir
}

if ($sourceType -eq "repo") {
    if ([string]::IsNullOrWhiteSpace($sourceDir) -or -not (Test-Path $sourceDir)) {
        exit (Invoke-QuakeZipInstructions -Reason "The Git clone this install came from is no longer available.")
    }
    exit (Invoke-QuakeRepoUpdate -SourceDir $sourceDir)
}

exit (Invoke-QuakeZipInstructions)
