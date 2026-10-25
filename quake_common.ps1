# Quake Alacritty - Shared installer helper functions
# Dot-sourced by install.ps1 and uninstall.ps1 so both use the same install
# detection, version metadata, process enumeration and graceful teardown logic.

# -----------------------------------------------------------------------------
# Paths, version metadata & install state
# -----------------------------------------------------------------------------

function Get-QuakeTargetDir {
    [CmdletBinding()]
    param()
    return (Join-Path $env:APPDATA "alacritty")
}

function Get-QuakeVersionFromDir {
    [CmdletBinding()]
    param([string]$Directory)

    if ([string]::IsNullOrWhiteSpace($Directory)) { return $null }

    $versionPath = Join-Path $Directory "VERSION"
    if (-not (Test-Path $versionPath)) { return $null }

    try {
        $raw = (Get-Content -Path $versionPath -Raw -ErrorAction Stop).Trim()
    } catch {
        return $null
    }

    if ($raw -match '^v?(\d+\.\d+\.\d+([-+].*)?)$') { return $matches[1] }
    return $null
}

function Get-QuakeConfigSchemaFromDir {
    [CmdletBinding()]
    param([string]$Directory)

    if ([string]::IsNullOrWhiteSpace($Directory)) { return $null }

    $schemaPath = Join-Path $Directory "CONFIG_SCHEMA"
    if (-not (Test-Path $schemaPath)) { return $null }

    try {
        $raw = (Get-Content -Path $schemaPath -Raw -ErrorAction Stop).Trim()
    } catch {
        return $null
    }

    $value = 0
    if ([int]::TryParse($raw, [ref]$value)) { return $value }
    return $null
}

function Get-QuakeInstallStatePath {
    [CmdletBinding()]
    param([string]$TargetDir = (Get-QuakeTargetDir))
    return (Join-Path $TargetDir ".install-state.json")
}

function Read-QuakeInstallState {
    [CmdletBinding()]
    param([string]$TargetDir = (Get-QuakeTargetDir))

    $statePath = Get-QuakeInstallStatePath -TargetDir $TargetDir
    if (-not (Test-Path $statePath)) { return $null }

    try {
        $raw = Get-Content -Path $statePath -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ($raw | ConvertFrom-Json)
    } catch {
        Write-Verbose "Could not read install state: $_"
        return $null
    }
}

function Write-QuakeInstallState {
    [CmdletBinding()]
    param(
        [string]$TargetDir = (Get-QuakeTargetDir),
        [string]$Version,
        [int]$ConfigSchema,
        [string]$GitCommit,
        [string]$InstalledAt,
        [string]$Shell,
        [string]$Layout
    )

    $statePath = Get-QuakeInstallStatePath -TargetDir $TargetDir
    $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    if ([string]::IsNullOrWhiteSpace($InstalledAt)) { $InstalledAt = $now }

    $state = [ordered]@{
        version      = $Version
        configSchema = $ConfigSchema
        gitCommit    = $GitCommit
        installedAt  = $InstalledAt
        updatedAt    = $now
        shell        = $Shell
        layout       = $Layout
        targetDir    = $TargetDir
    }

    $json = $state | ConvertTo-Json -Depth 4
    [System.IO.File]::WriteAllText($statePath, $json, (New-Object System.Text.UTF8Encoding($false)))
    return $statePath
}

# -----------------------------------------------------------------------------
# Add/Remove Programs (HKCU) registration
# -----------------------------------------------------------------------------

function Get-QuakeUninstallRegistryPath {
    [CmdletBinding()]
    param()
    return "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\QuakeAlacritty"
}

function Remove-QuakeUninstallEntry {
    [CmdletBinding()]
    param()

    $keyPath = Get-QuakeUninstallRegistryPath
    if (Test-Path $keyPath) {
        Remove-Item -Path $keyPath -Recurse -Force -ErrorAction SilentlyContinue
        return $true
    }
    return $false
}

# -----------------------------------------------------------------------------
# Dependency probing
# -----------------------------------------------------------------------------

function Get-QuakeAhkExecutable {
    [CmdletBinding()]
    param()

    $command = Get-Command AutoHotkey64.exe -ErrorAction SilentlyContinue
    if ($command -and $command.Source -and (Test-Path $command.Source)) { return $command.Source }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Programs\AutoHotkey\v2\AutoHotkey64.exe"),
        "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return $candidate }
    }
    return $null
}

# -----------------------------------------------------------------------------
# Process detection & graceful teardown
# -----------------------------------------------------------------------------

# Finds AutoHotkey processes running quake_alacritty.ahk. Win32_Process.CommandLine
# is the only reliable discriminator (Get-Process exposes no CommandLine property in
# Windows PowerShell 5.1), and the parsed script path is validated against the
# allow-list so a similarly named script from elsewhere is never touched.
function Get-QuakeAhkProcesses {
    [CmdletBinding()]
    param([string[]]$AllowedScriptPaths = @())

    $normalizedAllowed = New-Object System.Collections.Generic.List[string]
    foreach ($path in $AllowedScriptPaths) {
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        try { $normalizedAllowed.Add([System.IO.Path]::GetFullPath($path)) } catch { }
    }

    $results = New-Object System.Collections.Generic.List[object]

    try {
        $cimProcesses = Get-CimInstance -ClassName Win32_Process `
            -Filter "Name='AutoHotkey64.exe' OR Name='AutoHotkey32.exe' OR Name='AutoHotkey.exe'" `
            -ErrorAction Stop
    } catch {
        Write-Verbose "Could not enumerate AutoHotkey processes: $_"
        return @()
    }

    foreach ($process in $cimProcesses) {
        $commandLine = $process.CommandLine
        if ([string]::IsNullOrWhiteSpace($commandLine)) { continue }
        if ($commandLine -notmatch 'quake_alacritty\.ahk') { continue }

        $scriptPath = $null
        if ($commandLine -match '"([^"]+\.ahk)"') {
            $scriptPath = $matches[1]
        } elseif ($commandLine -match '(\S+\.ahk)') {
            $scriptPath = $matches[1]
        }

        if ($scriptPath) {
            try { $scriptPath = [System.IO.Path]::GetFullPath($scriptPath) } catch { }
        }

        if ($normalizedAllowed.Count -gt 0) {
            if (-not $scriptPath) { continue }
            $isAllowed = $false
            foreach ($allowed in $normalizedAllowed) {
                if ([string]::Equals($scriptPath, $allowed, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $isAllowed = $true
                    break
                }
            }
            if (-not $isAllowed) { continue }
        }

        $results.Add([pscustomobject]@{
            ProcessId   = [int]$process.ProcessId
            Name        = $process.Name
            CommandLine = $commandLine
            ScriptPath  = $scriptPath
        })
    }

    if ($results.Count -eq 0) { return @() }
    return $results.ToArray()
}

# Stops Quake Alacritty AutoHotkey instances. Posts WM_CLOSE to the process windows
# first so AHK's OnExit cleanup (orphan divider removal) can run, then force-kills
# anything that is still alive after the grace period.
function Stop-QuakeAhkProcess {
    [CmdletBinding()]
    param(
        [string[]]$AllowedScriptPaths = @(),
        [int]$GracePeriodMs = 3000
    )

    $targets = @(Get-QuakeAhkProcesses -AllowedScriptPaths $AllowedScriptPaths)
    if ($targets.Count -eq 0) { return 0 }

    $processIds = @($targets | ForEach-Object { $_.ProcessId })

    $source = @'
using System;
using System.Runtime.InteropServices;

public static class QuakeWindowCloser
{
    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll")]
    private static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

    public static int PostCloseToProcess(int processId)
    {
        int posted = 0;
        uint target = (uint)processId;
        EnumWindows(delegate(IntPtr hWnd, IntPtr lParam)
        {
            uint pid;
            GetWindowThreadProcessId(hWnd, out pid);
            if (pid == target)
            {
                if (PostMessage(hWnd, 0x0010, IntPtr.Zero, IntPtr.Zero))
                {
                    posted++;
                }
            }
            return true;
        }, IntPtr.Zero);
        return posted;
    }
}
'@

    try {
        if (-not ("QuakeWindowCloser" -as [type])) {
            Add-Type -TypeDefinition $source -ErrorAction Stop
        }
        foreach ($processId in $processIds) {
            [void][QuakeWindowCloser]::PostCloseToProcess($processId)
        }
    } catch {
        Write-Verbose "Graceful close unavailable, falling back to force-kill: $_"
    }

    $deadline = (Get-Date).AddMilliseconds($GracePeriodMs)
    while ((Get-Date) -lt $deadline) {
        $alive = @($processIds | Where-Object { Get-Process -Id $_ -ErrorAction SilentlyContinue })
        if ($alive.Count -eq 0) { break }
        Start-Sleep -Milliseconds 100
    }

    foreach ($processId in $processIds) {
        if (Get-Process -Id $processId -ErrorAction SilentlyContinue) {
            Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
        }
    }

    return $targets.Count
}

# -----------------------------------------------------------------------------
# config.ini merge
# -----------------------------------------------------------------------------

# Appends only keys/sections that are missing from the destination template.
# Existing lines (including user edits, comments and ordering) are left untouched.
function Merge-QuakeIniContent {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$TemplateText,
        [AllowEmptyString()][string]$DestinationText
    )

    $eol = "`n"
    if ($DestinationText -match "`r`n") { $eol = "`r`n" }

    $destinationLines = @($DestinationText -split "`r?`n")
    $templateLines = @($TemplateText -split "`r?`n")

    # Index existing destination keys per section (case-insensitive).
    $destinationKeys = @{}
    $currentSection = ""
    foreach ($line in $destinationLines) {
        if ($line -match '^\s*\[([^\]]+)\]') {
            $currentSection = $matches[1].Trim().ToLowerInvariant()
            if (-not $destinationKeys.ContainsKey($currentSection)) {
                $destinationKeys[$currentSection] = New-Object 'System.Collections.Generic.HashSet[string]'
            }
            continue
        }
        if ($line -match '^\s*([^=;#\s\[][^=]*?)\s*=') {
            $key = $matches[1].Trim().ToLowerInvariant()
            if (-not $destinationKeys.ContainsKey($currentSection)) {
                $destinationKeys[$currentSection] = New-Object 'System.Collections.Generic.HashSet[string]'
            }
            [void]$destinationKeys[$currentSection].Add($key)
        }
    }

    # Parse the template into ordered sections with their raw body lines.
    $templateSections = New-Object System.Collections.Generic.List[object]
    $templateSection = $null
    foreach ($line in $templateLines) {
        if ($line -match '^\s*\[([^\]]+)\]') {
            $templateSection = [pscustomobject]@{
                Name   = $matches[1].Trim()
                Header = $line
                Body   = New-Object System.Collections.Generic.List[string]
            }
            $templateSections.Add($templateSection)
            continue
        }
        if ($null -eq $templateSection) { continue }
        $templateSection.Body.Add($line)
    }

    $missingBlocks = @{}
    $newSections = New-Object System.Collections.Generic.List[object]
    $addedKeys = New-Object System.Collections.Generic.List[string]
    $addedSections = New-Object System.Collections.Generic.List[string]

    foreach ($section in $templateSections) {
        $sectionName = $section.Name.ToLowerInvariant()

        if (-not $destinationKeys.ContainsKey($sectionName)) {
            $body = New-Object System.Collections.Generic.List[string]
            foreach ($line in $section.Body) { $body.Add($line) }
            while ($body.Count -gt 0 -and [string]::IsNullOrWhiteSpace($body[$body.Count - 1])) {
                $body.RemoveAt($body.Count - 1)
            }
            $newSections.Add([pscustomobject]@{ Header = $section.Header; Body = $body })
            $addedSections.Add($section.Name)
            continue
        }

        $blocks = New-Object System.Collections.Generic.List[object]
        $pendingComments = New-Object System.Collections.Generic.List[string]
        foreach ($line in $section.Body) {
            if ([string]::IsNullOrWhiteSpace($line)) {
                $pendingComments.Clear()
                continue
            }
            if ($line -match '^\s*[;#]') {
                $pendingComments.Add($line)
                continue
            }
            if ($line -notmatch '^\s*([^=;#\s\[][^=]*?)\s*=') {
                $pendingComments.Clear()
                continue
            }
            $key = $matches[1].Trim()
            if (-not $destinationKeys[$sectionName].Contains($key.ToLowerInvariant())) {
                $blockLines = New-Object System.Collections.Generic.List[string]
                foreach ($comment in $pendingComments) { $blockLines.Add($comment) }
                $blockLines.Add($line)
                $blocks.Add([pscustomobject]@{ Lines = $blockLines })
                $addedKeys.Add($key)
            }
            $pendingComments.Clear()
        }

        if ($blocks.Count -gt 0) { $missingBlocks[$sectionName] = $blocks }
    }

    # Rebuild the destination, inserting missing keys at the end of their section.
    $output = New-Object System.Collections.Generic.List[string]
    $emitted = @{}
    $current = ""

    foreach ($line in $destinationLines) {
        if ($line -match '^\s*\[([^\]]+)\]') {
            if ($missingBlocks.ContainsKey($current) -and -not $emitted.ContainsKey($current)) {
                if ($output.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($output[$output.Count - 1])) {
                    $output.Add("")
                }
                foreach ($block in $missingBlocks[$current]) {
                    foreach ($blockLine in $block.Lines) { $output.Add($blockLine) }
                }
                $output.Add("")
                $emitted[$current] = $true
            }
            $current = $matches[1].Trim().ToLowerInvariant()
        }
        $output.Add($line)
    }

    if ($missingBlocks.ContainsKey($current) -and -not $emitted.ContainsKey($current)) {
        if ($output.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($output[$output.Count - 1])) {
            $output.Add("")
        }
        foreach ($block in $missingBlocks[$current]) {
            foreach ($blockLine in $block.Lines) { $output.Add($blockLine) }
        }
        $output.Add("")
        $emitted[$current] = $true
    }

    foreach ($section in $newSections) {
        if ($output.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($output[$output.Count - 1])) {
            $output.Add("")
        }
        $output.Add($section.Header)
        foreach ($line in $section.Body) { $output.Add($line) }
    }
    $output.Add("")

    return [pscustomobject]@{
        Text          = ($output -join $eol)
        AddedKeys     = @($addedKeys)
        AddedSections = @($addedSections)
    }
}

# -----------------------------------------------------------------------------
# Version helpers
# -----------------------------------------------------------------------------

function Compare-QuakeVersion {
    [CmdletBinding()]
    param(
        [string]$Left,
        [string]$Right
    )

    $leftCore = ($Left -replace '^v', '') -replace '[-+].*$', ''
    $rightCore = ($Right -replace '^v', '') -replace '[-+].*$', ''

    try {
        return ([version]$leftCore).CompareTo([version]$rightCore)
    } catch {
        return ([string]::Compare($leftCore, $rightCore, [System.StringComparison]::OrdinalIgnoreCase))
    }
}

# Advisory-only update check shared by install.ps1 (-CheckForUpdates),
# update-check.ps1 (background cache writer) and update.ps1 (-Check).
# Never downloads or installs anything; returns a result object instead.
function Invoke-QuakeUpdateCheck {
    [CmdletBinding()]
    param(
        [string]$InstalledVersion,
        [int]$TimeoutSeconds = 3,
        [string]$Url = "https://raw.githubusercontent.com/orgNero/quake-alacritty/main/VERSION"
    )

    $repositoryUrl = "https://github.com/orgNero/quake-alacritty"
    $result = [pscustomobject]@{
        InstalledVersion = $InstalledVersion
        AvailableVersion = $null
        UpdateAvailable  = $false
        CompareUrl       = $null
        Error            = $null
    }

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec $TimeoutSeconds `
            -Headers @{ "Cache-Control" = "no-cache"; "Pragma" = "no-cache" } -ErrorAction Stop
        $remoteVersion = ([string]$response.Content).Trim()
    } catch {
        $result.Error = $_.Exception.Message
        return $result
    }

    if ($remoteVersion -notmatch '^\d+\.\d+\.\d+([-+].*)?$') {
        $result.Error = "Unexpected VERSION payload from $Url"
        return $result
    }

    $result.AvailableVersion = $remoteVersion

    if ($InstalledVersion) {
        try {
            $result.UpdateAvailable = (Compare-QuakeVersion -Left $remoteVersion -Right $InstalledVersion) -gt 0
        } catch {
            $result.UpdateAvailable = ($remoteVersion -ne $InstalledVersion)
        }
    }

    if ($result.UpdateAvailable) {
        $result.CompareUrl = "$repositoryUrl/compare/v$InstalledVersion...v$remoteVersion"
    }

    return $result
}
