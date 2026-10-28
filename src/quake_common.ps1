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
        [string]$Layout,
        [ValidateSet("repo", "zip", "")]
        [string]$SourceType,
        [string]$SourceDir
    )

    $statePath = Get-QuakeInstallStatePath -TargetDir $TargetDir
    $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    if ([string]::IsNullOrWhiteSpace($InstalledAt)) { $InstalledAt = $now }

    # Preserve install-source fields when a caller does not supply them, so an
    # older call site (or a future one) never blanks them.
    $existing = $null
    if (Test-Path $statePath) {
        try {
            $raw = Get-Content -Path $statePath -Raw -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace($raw)) { $existing = $raw | ConvertFrom-Json }
        } catch {
            Write-Verbose "Could not read existing install state: $_"
        }
    }
    if ([string]::IsNullOrWhiteSpace($SourceType) -and $null -ne $existing -and
        $null -ne $existing.PSObject.Properties['sourceType']) {
        $SourceType = [string]$existing.sourceType
    }
    if ([string]::IsNullOrWhiteSpace($SourceDir) -and $null -ne $existing -and
        $null -ne $existing.PSObject.Properties['sourceDir']) {
        $SourceDir = [string]$existing.sourceDir
    }

    $state = [ordered]@{
        version      = $Version
        configSchema = $ConfigSchema
        gitCommit    = $GitCommit
        installedAt  = $InstalledAt
        updatedAt    = $now
        shell        = $Shell
        layout       = $Layout
        targetDir    = $TargetDir
        sourceType   = $SourceType
        sourceDir    = $SourceDir
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

# Rebuilds $env:Path from the Machine and User registry values. winget writes a
# new install directory to the registry, not into an already-running process, so
# a freshly installed Alacritty stays invisible for the rest of the session until
# this runs. Registry entries come first (Machine, then User) and are deduped
# case-insensitively; session-only entries are kept at the end so tools that are
# available only in the current shell keep working.
function Reset-QuakeProcessPath {
    [CmdletBinding()]
    param()

    $sources = New-Object System.Collections.Generic.List[string]
    foreach ($scope in @('Machine', 'User')) {
        $raw = [Environment]::GetEnvironmentVariable('Path', $scope)
        if (-not [string]::IsNullOrWhiteSpace($raw)) { $sources.Add($raw) }
    }
    if (-not [string]::IsNullOrWhiteSpace($env:Path)) { $sources.Add($env:Path) }

    $entries = New-Object System.Collections.Generic.List[string]
    $seen = @{}

    foreach ($raw in $sources) {
        foreach ($entry in ($raw -split ';')) {
            $expanded = [Environment]::ExpandEnvironmentVariables($entry.Trim())
            if ([string]::IsNullOrWhiteSpace($expanded)) { continue }
            if ($seen.ContainsKey($expanded)) { continue }
            $seen[$expanded] = $true
            $entries.Add($expanded)
        }
    }

    $env:Path = ($entries -join ';')
}

# Mirrors the runtime resolver in quake_alacritty.ahk: optional configured path ->
# PATH -> standard install locations. The installer uses it to probe, to report
# the Alacritty version and to decide whether the visor can actually launch a
# terminal. It never assumes a single hard-coded directory.
function Get-QuakeAlacrittyExecutable {
    [CmdletBinding()]
    param(
        [string]$ConfiguredPath,
        [switch]$RefreshPath
    )

    if ($RefreshPath) { Reset-QuakeProcessPath }

    if (-not [string]::IsNullOrWhiteSpace($ConfiguredPath)) {
        $expanded = [Environment]::ExpandEnvironmentVariables($ConfiguredPath.Trim())
        if (Test-Path -LiteralPath $expanded -PathType Leaf) {
            return (Resolve-Path -LiteralPath $expanded).Path
        }
    }

    # Scan PATH ourselves instead of trusting Get-Command's discovery cache.
    if (-not [string]::IsNullOrWhiteSpace($env:Path)) {
        foreach ($entry in ($env:Path -split ';')) {
            $directory = [Environment]::ExpandEnvironmentVariables($entry.Trim().Trim('"'))
            if ([string]::IsNullOrWhiteSpace($directory)) { continue }
            $candidate = Join-Path $directory "alacritty.exe"
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        }
    }

    $candidates = @()
    if ($env:LOCALAPPDATA) {
        $candidates += (Join-Path $env:LOCALAPPDATA "Programs\Alacritty\alacritty.exe")
    }
    if ($env:ProgramFiles) {
        $candidates += (Join-Path $env:ProgramFiles "Alacritty\alacritty.exe")
    }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }

    return $null
}

# Reads the optional [General] AlacrittyPath override from a config.ini. This key
# is intentionally absent from the shipped template; it only exists when a user
# adds it for a portable/custom Alacritty location.
function Get-QuakeAlacrittyConfiguredPath {
    [CmdletBinding()]
    param([string]$ConfigPath)

    if ([string]::IsNullOrWhiteSpace($ConfigPath) -or -not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        return $null
    }

    $inGeneral = $false
    try {
        foreach ($line in (Get-Content -LiteralPath $ConfigPath -ErrorAction Stop)) {
            if ($line -match '^\s*\[([^\]]+)\]') {
                $inGeneral = ($matches[1].Trim() -ieq 'General')
                continue
            }
            if (-not $inGeneral) { continue }
            if ($line -match '^\s*([^=;#\s\[][^=]*?)\s*=\s*(.*)$') {
                if ($matches[1].Trim() -ieq 'AlacrittyPath') {
                    $value = $matches[2].Trim()
                    if ($value -ne '') { return $value }
                }
            }
        }
    } catch {
        Write-Verbose "Could not read $ConfigPath`: $_"
    }
    return $null
}

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

# -----------------------------------------------------------------------------
# Window helpers (WM_CLOSE handshake)
# -----------------------------------------------------------------------------
# Shared by the AHK teardown and the uninstaller's terminal prompt. Compiled lazily
# so installs that never touch a running process pay nothing for it.
$script:QuakeWindowToolsSource = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class QuakeWindowTools
{
    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll")]
    private static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

    [DllImport("user32.dll")]
    private static extern IntPtr GetWindow(IntPtr hWnd, uint uCmd);

    [DllImport("user32.dll")]
    private static extern bool IsWindow(IntPtr hWnd);

    // GetWindowLongPtrW only exists in 64-bit user32; 32-bit hosts must call GetWindowLongW.
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    private static extern IntPtr GetWindowLongPtr64(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongW")]
    private static extern int GetWindowLong32(IntPtr hWnd, int nIndex);

    private const int GWL_EXSTYLE = -20;
    private const uint GW_OWNER = 4;
    private const long WS_EX_TOOLWINDOW = 0x80;

    // Alacritty's real terminal window. Must stay in sync with GetAlacrittyWindows in
    // quake_alacritty.ahk, which applies the same three tests.
    private const string AlacrittyPaneClass = "Window Class";

    private static long GetExStyle(IntPtr hWnd)
    {
        if (IntPtr.Size == 8) { return GetWindowLongPtr64(hWnd, GWL_EXSTYLE).ToInt64(); }
        return (long)GetWindowLong32(hWnd, GWL_EXSTYLE);
    }

    // A pane window has class "Window Class", is not a tool window and has no owner.
    // The title is deliberately not part of this test: Alacritty derives it from shell
    // escape sequences, so a pane can legitimately be untitled (cmd, a fresh PowerShell
    // pane, a shell that clears it). IME/framework helpers ("MSCTFIME UI",
    // "Default IME", "CiceroUIWndFrame") are titled but are not panes.
    public static bool IsPaneWindow(long handle)
    {
        IntPtr hWnd = new IntPtr(handle);
        StringBuilder className = new StringBuilder(256);
        if (GetClassName(hWnd, className, className.Capacity) <= 0) { return false; }
        if (className.ToString() != AlacrittyPaneClass) { return false; }
        if ((GetExStyle(hWnd) & WS_EX_TOOLWINDOW) != 0) { return false; }
        if (GetWindow(hWnd, GW_OWNER) != IntPtr.Zero) { return false; }
        return true;
    }

    public static bool IsWindowAlive(long handle)
    {
        return IsWindow(new IntPtr(handle));
    }

    // Posts WM_CLOSE to every top-level window owned by the process. Deliberately no
    // title or visibility filter: AutoHotkey's message window is hidden and untitled,
    // and closing it is what lets OnExit clean up the seam overlays.
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

    // Pane windows of the process, visible or hidden. Hidden panes keep their window
    // (the visor calls WinHide), so enumeration must not filter on visibility.
    public static long[] GetPaneWindows(int processId)
    {
        List<long> handles = new List<long>();
        uint target = (uint)processId;
        EnumWindows(delegate(IntPtr hWnd, IntPtr lParam)
        {
            uint pid;
            GetWindowThreadProcessId(hWnd, out pid);
            if (pid == target && IsPaneWindow(hWnd.ToInt64()))
            {
                handles.Add(hWnd.ToInt64());
            }
            return true;
        }, IntPtr.Zero);
        return handles.ToArray();
    }

    public static string GetTitle(long handle)
    {
        IntPtr hWnd = new IntPtr(handle);
        int length = GetWindowTextLength(hWnd);
        if (length <= 0) { return String.Empty; }
        StringBuilder builder = new StringBuilder(length + 1);
        GetWindowText(hWnd, builder, builder.Capacity);
        return builder.ToString();
    }

    public static bool IsVisible(long handle)
    {
        return IsWindowVisible(new IntPtr(handle));
    }

    public static bool PostClose(long handle)
    {
        return PostMessage(new IntPtr(handle), 0x0010, IntPtr.Zero, IntPtr.Zero);
    }
}
'@

function Initialize-QuakeWindowTools {
    if (-not ("QuakeWindowTools" -as [type])) {
        Add-Type -TypeDefinition $script:QuakeWindowToolsSource -ErrorAction Stop
    }
}

# Returns one object per running Alacritty pane window. Hidden panes keep their window,
# so they are included. Panes are identified by window class, not by title: a pane whose
# shell never sets a title would otherwise be invisible here and survive teardown.
function Get-QuakeTerminalWindows {
    [CmdletBinding()]
    param()

    $processes = @(Get-Process -Name 'alacritty' -ErrorAction SilentlyContinue)
    if ($processes.Count -eq 0) { return @() }

    Initialize-QuakeWindowTools

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($process in $processes) {
        foreach ($handle in [QuakeWindowTools]::GetPaneWindows($process.Id)) {
            $title = [QuakeWindowTools]::GetTitle($handle)
            if ([string]::IsNullOrWhiteSpace($title)) { $title = "Alacritty pane" }
            $results.Add([pscustomobject]@{
                ProcessId = $process.Id
                Handle    = $handle
                Title     = $title
                Visible   = [QuakeWindowTools]::IsVisible($handle)
            })
        }
    }

    if ($results.Count -eq 0) { return @() }
    return $results.ToArray()
}

# Running alacritty.exe processes that own no pane window at all. Nothing can be posted
# to a process without a window, so these can only be reported, never closed gracefully.
function Get-QuakeUntargetableTerminalProcesses {
    [CmdletBinding()]
    param()

    $processes = @(Get-Process -Name 'alacritty' -ErrorAction SilentlyContinue)
    if ($processes.Count -eq 0) { return @() }

    $windowedIds = @(Get-QuakeTerminalWindows | ForEach-Object { $_.ProcessId } | Sort-Object -Unique)
    $untargetable = @($processes | Where-Object { $windowedIds -notcontains $_.Id })
    if ($untargetable.Count -eq 0) { return @() }

    return @($untargetable | ForEach-Object {
        [pscustomobject]@{
            ProcessId = $_.Id
            Name      = $_.ProcessName
        }
    })
}

# Asks each pane window to close, waits, and returns the windows still alive. Never
# force-kills: a pane may be holding unsaved shell state or a confirmation prompt.
# Survivors are tested by window handle, not by process, so a pane that closed while its
# process is still tearing down is not reported as a failed close.
function Close-QuakeTerminalWindows {
    [CmdletBinding()]
    param(
        [object[]]$Windows = @(),
        [int]$GracePeriodMs = 5000
    )

    $open = @($Windows | Where-Object { $_ -and $_.Handle })
    if ($open.Count -eq 0) { return @() }

    Initialize-QuakeWindowTools
    foreach ($window in $open) {
        [void][QuakeWindowTools]::PostClose([long]$window.Handle)
    }

    $deadline = (Get-Date).AddMilliseconds($GracePeriodMs)
    while ((Get-Date) -lt $deadline) {
        $alive = @($open | Where-Object { [QuakeWindowTools]::IsWindowAlive([long]$_.Handle) })
        if ($alive.Count -eq 0) { break }
        Start-Sleep -Milliseconds 100
    }

    return @($open | Where-Object { [QuakeWindowTools]::IsWindowAlive([long]$_.Handle) })
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

    try {
        Initialize-QuakeWindowTools
        foreach ($processId in $processIds) {
            [void][QuakeWindowTools]::PostCloseToProcess($processId)
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
# Reads the newest *published* GitHub release, so a tag without a release is
# never advertised. Never downloads or installs anything; returns a result
# object instead.
function Invoke-QuakeUpdateCheck {
    [CmdletBinding()]
    param(
        [string]$InstalledVersion,
        [int]$TimeoutSeconds = 3,
        [string]$Url = "https://api.github.com/repos/orgNero/quake-alacritty/releases/latest"
    )

    $repositoryUrl = "https://github.com/orgNero/quake-alacritty"
    $result = [pscustomobject]@{
        InstalledVersion = $InstalledVersion
        AvailableVersion = $null
        UpdateAvailable  = $false
        CompareUrl       = $null
        DownloadUrl      = $null
        ReleaseBody      = $null
        CanAutoUpdate    = $false
        Error            = $null
    }

    $statusCode = $null
    $payload = $null
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $payload = Invoke-RestMethod -Uri $Url -TimeoutSec $TimeoutSeconds -ErrorAction Stop `
            -Headers @{
                "Accept"        = "application/vnd.github+json"
                "User-Agent"    = "quake-alacritty-update-check"
                "Cache-Control" = "no-cache"
                "Pragma"        = "no-cache"
            }
    } catch {
        # Invoke-RestMethod wraps HTTP failures; keep a short, plain message.
        try {
            if ($null -ne $_.Exception.Response -and $null -ne $_.Exception.Response.StatusCode) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }
        } catch { }

        if ($statusCode -eq 404) {
            $result.Error = "No published release found yet."
        } elseif ($statusCode -eq 403) {
            $result.Error = "GitHub API rate limit reached. Try again later."
        } else {
            $result.Error = $_.Exception.Message
        }
        return $result
    }

    $tag = $null
    if ($null -ne $payload -and $null -ne $payload.PSObject.Properties['tag_name']) {
        $tag = [string]$payload.tag_name
    }
    $remoteVersion = $tag.Trim() -replace '^v', ''

    if ($remoteVersion -notmatch '^\d+\.\d+\.\d+([-+].*)?$') {
        $result.Error = "Unexpected release payload from $Url"
        return $result
    }

    $result.AvailableVersion = $remoteVersion

    if ($null -ne $payload.PSObject.Properties['body']) {
        $result.ReleaseBody = [string]$payload.body
    }

    # The release carries exactly one asset: quake-alacritty-vX.Y.Z.zip. Prefer
    # the name that matches the tag, but keep a ZIP fallback so a republished
    # asset never blocks the update. Update.ps1 uses this for ZIP self-update.
    $expectedAsset = "quake-alacritty-v$remoteVersion.zip"
    $assetUrl = $null
    if ($null -ne $payload.PSObject.Properties['assets']) {
        foreach ($asset in @($payload.assets)) {
            if ($null -eq $asset) { continue }

            $assetName = ""
            if ($null -ne $asset.PSObject.Properties['name']) { $assetName = [string]$asset.name }
            $assetHref = ""
            if ($null -ne $asset.PSObject.Properties['browser_download_url']) { $assetHref = [string]$asset.browser_download_url }
            if ([string]::IsNullOrWhiteSpace($assetHref)) { continue }

            if ($assetName -eq $expectedAsset) {
                $assetUrl = $assetHref
                break
            }
            if (-not $assetUrl -and $assetName -match '(?i)^quake-alacritty-v.+\.zip$') {
                $assetUrl = $assetHref
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($assetUrl)) {
        $result.DownloadUrl = $assetUrl
        $result.CanAutoUpdate = $true
    }

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
