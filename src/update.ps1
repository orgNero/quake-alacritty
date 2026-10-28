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
    A ZIP install has nothing to pull, so its release archive is downloaded,
    checked against the SHA-256 published in the release notes, extracted to a
    temporary directory and handed to the extracted installer. Any failure
    falls back to the download link instead of half-applying an update. The
    running script never replaces itself in place: the installer is always
    launched as a child process.

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

function Invoke-QuakeZipUpdate {
    param([string]$Reason)

    if (-not [string]::IsNullOrWhiteSpace($Reason)) {
        Write-Host $Reason
    }

    $check = Invoke-QuakeUpdateCheck -InstalledVersion $installedVersion -TimeoutSeconds $TimeoutSeconds
    if ($check.Error) {
        Write-Host ("Could not check for updates: " + (Get-QuakeShortReason -Text ([string]$check.Error)) + ".")
        Write-Host ("Download the latest release: " + $releasesUrl)
        return 1
    }

    if (-not $check.UpdateAvailable) {
        Write-Host ("Already on the latest version (v{0})." -f $installedVersion)
        return 0
    }

    $availableVersion = [string]$check.AvailableVersion
    if (-not $check.CanAutoUpdate -or [string]::IsNullOrWhiteSpace([string]$check.DownloadUrl)) {
        Write-Host ("A newer version (v{0}) is available, but the release has no downloadable archive." -f $availableVersion)
        Write-Host ("Download manually: " + $releasesUrl)
        return 1
    }

    Write-Host ("Updating v{0} -> v{1}..." -f $installedVersion, $availableVersion)

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("quake-update-" + [guid]::NewGuid().ToString("N"))
    $zipPath = Join-Path $tempRoot ("quake-alacritty-v" + $availableVersion + ".zip")
    $extractDir = Join-Path $tempRoot "extract"

    try {
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

        Write-Host ("  [Download] " + [string]$check.DownloadUrl)
        $progressPreference = $ProgressPreference
        $ProgressPreference = "SilentlyContinue"
        try {
            $downloadParams = @{
                Uri         = [string]$check.DownloadUrl
                OutFile     = $zipPath
                TimeoutSec  = 300
                ErrorAction = "Stop"
            }
            # Windows PowerShell 5.1 needs the basic parser; PowerShell 7 dropped it.
            if ($PSVersionTable.PSVersion.Major -lt 6) { $downloadParams.UseBasicParsing = $true }
            Invoke-WebRequest @downloadParams
        } finally {
            $ProgressPreference = $progressPreference
        }

        $publishedHash = $null
        if (-not [string]::IsNullOrWhiteSpace([string]$check.ReleaseBody)) {
            # The notes carry a "**SHA-256** (`asset.zip`): `<hash>`" line.
            foreach ($line in ([string]$check.ReleaseBody -split "`r?`n")) {
                if ($line -notmatch '(?i)SHA-?256') { continue }
                $hashMatch = [regex]::Match($line, '(?i)\b[0-9a-f]{64}\b')
                if ($hashMatch.Success) {
                    $publishedHash = $hashMatch.Value.ToLowerInvariant()
                    break
                }
            }
        }

        if ($publishedHash) {
            $actualHash = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actualHash -ne $publishedHash) {
                Write-Host "The downloaded archive does not match the SHA-256 published in the release notes."
                Write-Host "Nothing was installed. Download manually: $releasesUrl"
                return 1
            }
            Write-Host "  [Verify] SHA-256 matches the release notes"
        } else {
            Write-Host "  [Verify] No SHA-256 in the release notes; downloaded over HTTPS from GitHub"
        }

        Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

        $installer = Join-Path $extractDir "src\install.ps1"
        if (-not (Test-Path $installer)) {
            # Archives predating the src/ layout keep the installer at the root.
            $installer = Join-Path $extractDir "install.ps1"
        }
        if (-not (Test-Path $installer)) {
            Write-Host "The downloaded archive does not contain install.ps1."
            Write-Host "Nothing was installed. Download manually: $releasesUrl"
            return 1
        }

        $archiveVersion = Get-QuakeVersionFromDir -Directory (Split-Path $installer -Parent)
        if ($archiveVersion -and $archiveVersion -ne $availableVersion) {
            Write-Host ("The downloaded archive is v{0}, but the release announced v{1}." -f $archiveVersion, $availableVersion)
            Write-Host "Nothing was installed. Download manually: $releasesUrl"
            return 1
        }

        $powerShellExe = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
        if (-not (Test-Path $powerShellExe)) { $powerShellExe = "powershell.exe" }

        # Same reason as the repo path: the call operator waits for this child
        # only, while Start-Process -Wait would also wait for the AHK grandchild.
        & $powerShellExe -NoProfile -ExecutionPolicy Bypass -File $installer -Shell keep -NonInteractive
        if ($LASTEXITCODE -ne 0) {
            Write-Host ("The installer failed (exit {0}). Your config was not removed. Run install.ps1 manually to see the details." -f $LASTEXITCODE)
            return 1
        }

        $newVersion = Get-QuakeVersionFromDir -Directory $targetDir
        if (-not $newVersion) {
            $newState = Read-QuakeInstallState -TargetDir $targetDir
            if ($newState -and $newState.version) { $newVersion = [string]$newState.version }
        }
        if (-not $newVersion) { $newVersion = $availableVersion }

        Write-Host ("Updated to v{0}. Toggle the visor once to retile." -f $newVersion)
        return 0
    } catch {
        Write-Host ("Could not apply the update: " + (Get-QuakeShortReason -Text $_.Exception.Message))
        Write-Host "Nothing was installed; you are still on v$installedVersion."
        if ($_.Exception.Message -match 'quarantine|virus|threat') {
            Write-Host "Antivirus software may have blocked the download. See the troubleshooting section in README.md."
        }
        Write-Host ("Download manually: " + $releasesUrl)
        return 1
    } finally {
        if (Test-Path $tempRoot) {
            Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
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
        return (Invoke-QuakeZipUpdate -Reason "The Git clone this install came from has moved or is no longer a repository.")
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
        # Tracking is local configuration and easy to lose (re-clone, VS Code,
        # a manual merge). Adopt the remote-tracking branch when it exists
        # instead of asking the user to push their local branch upstream.
        $branchName = (@($headRefResult.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) | Select-Object -First 1)
        $branchName = ([string]$branchName).Trim()

        $candidates = @()
        if (-not [string]::IsNullOrWhiteSpace($branchName)) {
            $refResult = Invoke-QuakeGit -Directory $SourceDir -Arguments @('for-each-ref', '--format=%(refname:short)', "refs/remotes/*/$branchName")
            $candidates = @($refResult.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { ([string]$_).Trim() })
        }

        $trackingRef = $null
        if ($candidates.Count -gt 0) {
            $originRef = "origin/$branchName"
            $trackingRef = @($candidates | Where-Object { $_ -eq $originRef }) | Select-Object -First 1
            if (-not $trackingRef -and $candidates.Count -eq 1) { $trackingRef = $candidates[0] }
        }

        if ($trackingRef) {
            $setResult = Invoke-QuakeGit -Directory $SourceDir -Arguments @('branch', ("--set-upstream-to=" + $trackingRef), $branchName)
            if ($setResult.ExitCode -eq 0) {
                Write-Host ("Branch '{0}' now tracks {1}." -f $branchName, $trackingRef)
                $upstream = $trackingRef
            }
        }

        if ([string]::IsNullOrWhiteSpace($upstream)) {
            Write-Host ("Your current branch '{0}' has no upstream and no remote-tracking branch to adopt." -f $branchName)
            Write-Host ("Set one with: git branch --set-upstream-to=origin/{0} {0}" -f $branchName)
            Write-Host "Then run 'quake-update' again."
            return 1
        }
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
        # No commits arrived, but the deployed copy can still lag behind this
        # clone: a manual merge/rebase, a fresh clone, or an earlier failed
        # install all leave the clone ahead of %APPDATA%\alacritty. Only report
        # "latest" when the deployment is not older than the clone's source.
        $sourceVersionDir = Join-Path $SourceDir "src"
        if (-not (Test-Path (Join-Path $sourceVersionDir "VERSION"))) {
            # Installs recorded before the src/ layout keep VERSION at the root.
            $sourceVersionDir = $SourceDir
        }
        $sourceVersion = Get-QuakeVersionFromDir -Directory $sourceVersionDir

        $needsRedeploy = $true
        if ($sourceVersion -and $installedVersion) {
            try {
                $needsRedeploy = (Compare-QuakeVersion -Left $sourceVersion -Right $installedVersion) -gt 0
            } catch {
                $needsRedeploy = ($sourceVersion -ne $installedVersion)
            }
        }

        # VERSION only moves at release prep, so the clone can advance without
        # a bump. The deploy records the short commit it was installed from;
        # compare as a prefix because git lengthens abbreviations over time.
        if (-not $needsRedeploy) {
            $deployedCommit = ""
            if ($null -ne $installState.PSObject.Properties['gitCommit']) {
                $deployedCommit = ([string]$installState.gitCommit).Trim()
            }
            if ($deployedCommit -and -not $headAfter.StartsWith($deployedCommit, [System.StringComparison]::OrdinalIgnoreCase)) {
                $needsRedeploy = $true
            }
        }

        if (-not $needsRedeploy) {
            Write-Host ("Already on the latest version (v{0})." -f $installedVersion)
            return 0
        }

        if ($sourceVersion -and $installedVersion -and $sourceVersion -ne $installedVersion) {
            Write-Host ("Your install (v{0}) is behind the clone (v{1}). Re-deploying." -f $installedVersion, $sourceVersion)
        } elseif ($installedVersion) {
            Write-Host ("Your install (v{0}) is not the clone's current commit. Re-deploying." -f $installedVersion)
        } elseif ($sourceVersion) {
            Write-Host ("Re-deploying the clone (v{0}) over the current install." -f $sourceVersion)
        } else {
            Write-Host "Re-deploying the clone over the current install."
        }
    }

    $installer = Join-Path $SourceDir "src\install.ps1"
    if (-not (Test-Path $installer)) {
        # Installs recorded before the src/ layout keep the installer at the root.
        $installer = Join-Path $SourceDir "install.ps1"
    }
    if (-not (Test-Path $installer)) {
        Write-Host "install.ps1 was not found in the updated clone (looked in src\ and the repository root). Run the installer manually to see the details."
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

$sourceType = ""
if ($null -ne $installState.PSObject.Properties['sourceType']) {
    $sourceType = [string]$installState.sourceType
}
$sourceDir = ""
if ($null -ne $installState.PSObject.Properties['sourceDir']) {
    $sourceDir = [string]$installState.sourceDir
}

if ($Check) {
    $result = Invoke-QuakeUpdateCheck -InstalledVersion $installedVersion -TimeoutSeconds $TimeoutSeconds
    if ($result.Error) {
        Write-Host ("Could not check for updates: " + (Get-QuakeShortReason -Text ([string]$result.Error)) + ".")
        exit 1
    }
    if (-not $result.UpdateAvailable) {
        Write-Host ("Already on the latest version (v{0})." -f $installedVersion)
        exit 0
    }

    if ($sourceType -eq "repo") {
        Write-Host ("Update available: v{0} (you have v{1}). Run 'quake-update' to install." -f $result.AvailableVersion, $installedVersion)
    } elseif ($result.CanAutoUpdate) {
        Write-Host ("Update available: v{0} (you have v{1}). Run 'quake-update' to download and install it." -f $result.AvailableVersion, $installedVersion)
    } else {
        Write-Host ("Update available: v{0} (you have v{1}). Download it from {2}" -f $result.AvailableVersion, $installedVersion, $releasesUrl)
    }
    exit 0
}

if ($sourceType -eq "repo") {
    if ([string]::IsNullOrWhiteSpace($sourceDir) -or -not (Test-Path $sourceDir)) {
        exit (Invoke-QuakeZipUpdate -Reason "The Git clone this install came from is no longer available.")
    }
    exit (Invoke-QuakeRepoUpdate -SourceDir $sourceDir)
}

exit (Invoke-QuakeZipUpdate)
