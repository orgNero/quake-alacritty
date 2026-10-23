# Quake Alacritty - In-Terminal Welcome Banner & Cheat Sheet
[CmdletBinding()]
param(
    [switch]$TipOnly,
    [switch]$EnvInfo
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

function global:Show-QuakeTip {
    $esc      = [char]27
    $cSub     = $esc + "[38;2;148;163;184m"    # Slate 400
    $cKey     = $esc + "[1;38;2;56;189;248m"   # Bright Cyan (#38bdf8)
    $cYellow  = $esc + "[38;2;251;191;36m"    # Amber 400
    $cReset   = $esc + "[0m"
    $chBulb   = [char]::ConvertFromUtf32(0x1F4A1) # ðŸ’¡

    Write-Host ""
    Write-Host ("  " + $cYellow + $chBulb + " " + $cSub + "Tip: Type '" + $cKey + "quake-help" + $cSub + "' to view keyboard shortcuts." + $cReset)
    Write-Host ""
}

function global:Show-QuakeCheatsheet {
    # Resolve config.ini location (%APPDATA%\alacritty\config.ini or local script directory)
    $configPath = Join-Path $env:APPDATA "alacritty\config.ini"
    if (-not (Test-Path $configPath)) {
        $localConfig = Join-Path $PSScriptRoot "config.ini"
        if (Test-Path $localConfig) { $configPath = $localConfig }
    }

    $chSection  = [string][char]0x00A7  # Â§
    $chBullet   = [string][char]0x2022  # â€¢
    $chBolt     = [string][char]0x26A1  # âš¡
    $chBulb     = [char]::ConvertFromUtf32(0x1F4A1) # ðŸ’¡

    # Box-drawing glyphs defined as strings for cross-version string multiplication & encoding safety
    $chTopLeft  = [string][char]0x250C  # â”Œ
    $chHoriz    = [string][char]0x2500  # â”€
    $chTopRight = [string][char]0x2510  # â”
    $chVert     = [string][char]0x2502  # â”‚
    $chTLeft    = [string][char]0x251C  # â”œ
    $chTRight   = [string][char]0x2524  # â”¤
    $chBotLeft  = [string][char]0x2514  # â””
    $chBotRight = [string][char]0x2518  # â”˜

    # Helper: Convert AHK shortcut notation to human-readable label
    function Convert-AhkKey([string]$ahkKey, [string]$defaultLabel) {
        if (-not $ahkKey) { return $defaultLabel }
        $ahkKey = $ahkKey.Trim()
        $parts = @()
        if ($ahkKey.Contains('#')) { $parts += 'Win' }
        if ($ahkKey.Contains('!')) { $parts += 'Alt' }
        if ($ahkKey.Contains('^')) { $parts += 'Ctrl' }
        if ($ahkKey.Contains('+')) { $parts += 'Shift' }

        $key = $ahkKey -replace '[\#\^\!\+]', ''
        switch ($key.ToLower()) {
            'sc029' { $key = [string][char]0x00A7 }
            'enter' { $key = 'Enter' }
            'space' { $key = 'Space' }
            'left'  { $key = 'Left' }
            'right' { $key = 'Right' }
            'up'    { $key = 'Up' }
            'down'  { $key = 'Down' }
            default { $key = $key.ToUpper() }
        }
        $parts += $key
        return ($parts -join ' + ')
    }

    # Default hotkey mapping (fallback if config is absent or partial)
    $hotkeys = @{
        ToggleVisor = ("Win + " + [string][char]0x00A7)
        SplitWindow = "Alt + Enter"
        CloseWindow = "Alt + W"
        Retile      = "Alt + R"
        CycleLayout = "Alt + L"
        Focus       = "Alt + Arrows"
        Swap        = "Alt + Shift + Arrows"
        RotatePanes = "Alt + Shift + Space"
        MoveVisor   = "Alt + Ctrl + Left/Right"
        Reload      = "Alt + Ctrl + R"
    }

    if (Test-Path $configPath) {
        try {
            $lines = Get-Content -Path $configPath -ErrorAction SilentlyContinue
            $inHotkeys = $false
            foreach ($line in $lines) {
                $trimmed = $line.Trim()
                if ($trimmed.StartsWith(';') -or $trimmed.StartsWith('#')) { continue }
                if ($trimmed -match '^\[Hotkeys\]') { $inHotkeys = $true; continue }
                if ($trimmed.StartsWith('[') -and -not ($trimmed -match '^\[Hotkeys\]')) { $inHotkeys = $false; continue }
                if ($inHotkeys -and ($trimmed -match '^([^=]+)=(.*)$')) {
                    $k = $Matches[1].Trim()
                    $v = ($Matches[2] -split ';')[0].Trim()
                    switch ($k) {
                        'ToggleVisor' { $hotkeys.ToggleVisor = Convert-AhkKey $v ("Win + " + [string][char]0x00A7) }
                        'SplitWindow' { $hotkeys.SplitWindow = Convert-AhkKey $v 'Alt + Enter' }
                        'CloseWindow' { $hotkeys.CloseWindow = Convert-AhkKey $v 'Alt + W' }
                        'Retile'      { $hotkeys.Retile      = Convert-AhkKey $v 'Alt + R' }
                        'CycleLayout' { $hotkeys.CycleLayout = Convert-AhkKey $v 'Alt + L' }
                        'FocusLeft'   {
                            $baseMod = Convert-AhkKey $v 'Alt + Left'
                            $hotkeys.Focus = ($baseMod -replace 'Left', 'Arrows')
                        }
                        'SwapLeft'    {
                            $baseMod = Convert-AhkKey $v 'Alt + Shift + Left'
                            $hotkeys.Swap = ($baseMod -replace 'Left', 'Arrows')
                        }
                        'RotatePanes' { $hotkeys.RotatePanes = Convert-AhkKey $v 'Alt + Shift + Space' }
                        'MoveVisorLeft' {
                            $baseMod = Convert-AhkKey $v 'Alt + Ctrl + Left'
                            $hotkeys.MoveVisor = ($baseMod -replace 'Left', 'Left/Right')
                        }
                        'ReloadScript'{ $hotkeys.Reload      = Convert-AhkKey $v 'Alt + Ctrl + R' }
                    }
                }
            }
        } catch {}
    }

    $esc      = [char]27
    $cBorder  = $esc + "[38;2;56;189;248m"    # Electric Cyan (#38bdf8)
    $cTitle   = $esc + "[1;38;2;255;255;255m"  # Bold White
    $cSub     = $esc + "[38;2;148;163;184m"    # Slate 400
    $cKey     = $esc + "[1;38;2;255;255;255m"  # Bright White
    $cAction  = $esc + "[38;2;203;213;225m"    # Slate 300
    $cYellow  = $esc + "[38;2;251;191;36m"    # Amber 400
    $cReset   = $esc + "[0m"

    $items = @(
        @{ Key = $hotkeys.ToggleVisor; Action = "Toggle Visor (mouse-aware screen toggle)" },
        @{ Key = $hotkeys.SplitWindow; Action = "Split window (1 -> 2 -> 3 -> 4 quad grid)" },
        @{ Key = $hotkeys.CloseWindow; Action = "Close active split & auto-rebalance" },
        @{ Key = $hotkeys.Retile;      Action = "Force re-tile & seam alignment" },
        @{ Key = $hotkeys.CycleLayout; Action = "Cycle layout / master orientation" },
        @{ Key = $hotkeys.Focus;       Action = "Switch typing focus between panes" },
        @{ Key = $hotkeys.Swap;        Action = "Swap active pane position" },
        @{ Key = $hotkeys.RotatePanes; Action = "Rotate all panes clockwise" },
        @{ Key = $hotkeys.MoveVisor;   Action = "Move / swap visor across monitors" },
        @{ Key = $hotkeys.Reload;      Action = "Reload config.ini" }
    )

    $boxWidth = 74
    Write-Host ""
    Write-Host ($cBorder + $chTopLeft + ($chHoriz * ($boxWidth - 2)) + $chTopRight + $cReset)
    
    # Title row
    $titleLeft  = "  " + $chBolt + " Quake Alacritty"
    $titleRight = "Quickstart Cheat Sheet  "
    $pad = $boxWidth - 2 - $titleLeft.Length - $titleRight.Length - 3
    if ($pad -lt 1) { $pad = 1 }
    Write-Host ($cBorder + $chVert + $cTitle + $titleLeft + " " + $cSub + $chBullet + " " + $titleRight + (" " * $pad) + $cBorder + $chVert + $cReset)
    
    Write-Host ($cBorder + $chTLeft + ($chHoriz * ($boxWidth - 2)) + $chTRight + $cReset)
    
    # Header row
    $headerKey = "  Shortcut"
    $headerAct = "Action"
    $hPad = 26 - $headerKey.Length
    $hPadEnd = $boxWidth - 2 - 26 - $headerAct.Length
    Write-Host ($cBorder + $chVert + $cYellow + $headerKey + (" " * $hPad) + $cTitle + $headerAct + (" " * $hPadEnd) + $cBorder + $chVert + $cReset)
    Write-Host ($cBorder + $chTLeft + ($chHoriz * ($boxWidth - 2)) + $chTRight + $cReset)

    foreach ($item in $items) {
        $k = "  " + $item.Key
        $a = $item.Action
        $kPad = 26 - $k.Length
        if ($kPad -lt 1) { $kPad = 1 }
        $aPad = $boxWidth - 2 - 26 - $a.Length
        if ($aPad -lt 1) { $aPad = 1 }
        Write-Host ($cBorder + $chVert + $cKey + $k + (" " * $kPad) + $cAction + $a + (" " * $aPad) + $cBorder + $chVert + $cReset)
    }

    Write-Host ($cBorder + $chTLeft + ($chHoriz * ($boxWidth - 2)) + $chTRight + $cReset)
    $tipPrefix = "  " + $chBulb + " Tip: Type '"
    $tipCmd    = "quake-help"
    $tipSuffix = "' anytime to redisplay this cheat sheet."
    $tipTotalLen = $tipPrefix.Length + $tipCmd.Length + $tipSuffix.Length
    $tipPad = $boxWidth - 2 - $tipTotalLen
    if ($tipPad -lt 0) { $tipPad = 0 }
    Write-Host ($cBorder + $chVert + $cYellow + "  " + $chBulb + " " + $cSub + "Tip: Type '" + $cKey + $tipCmd + $cSub + "' anytime to redisplay this cheat sheet." + (" " * $tipPad) + $cBorder + $chVert + $cReset)
    Write-Host ($cBorder + $chBotLeft + ($chHoriz * ($boxWidth - 2)) + $chBotRight + $cReset)
    Write-Host ("  " + $cSub + "Report bugs & suggest features: " + $cBorder + "https://github.com/orgNero/quake-alacritty/issues" + $cReset)
    Write-Host ""
}

function global:Show-QuakeEnvironment {
    param([switch]$NoClip)

    $o = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue)
    $winVer = if ($o -and $o.DisplayVersion) { "Windows 11 $($o.DisplayVersion) (Build $($o.CurrentBuild))" } else { "Windows 11" }

    $ahk = @(
        "AutoHotkey64.exe",
        "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe",
        "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
    ) | ForEach-Object {
        if ($_ -and (Test-Path $_ -PathType Leaf -ErrorAction SilentlyContinue)) { $_ } else { (Get-Command $_ -ErrorAction SilentlyContinue).Source }
    } | Where-Object { $_ } | Select-Object -First 1

    $ahkVer = if ($ahk) { (Get-Item $ahk).VersionInfo.ProductVersion } else { "Not found" }

    $alacVer = try {
        $p = [Diagnostics.Process]::Start([Diagnostics.ProcessStartInfo]@{
            FileName = "alacritty"
            Arguments = "--version"
            RedirectStandardOutput = $true
            UseShellExecute = $false
            CreateNoWindow = $true
        })
        $p.StandardOutput.ReadToEnd().Trim() -replace '^alacritty\s*', ''
    } catch { "Not found" }

    Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
    $screens = try {
        ([Windows.Forms.Screen]::AllScreens | ForEach-Object {
            "$($_.Bounds.Width)x$($_.Bounds.Height)$(if ($_.Primary) { ' (Primary)' })"
        }) -join ', '
    } catch { "Unknown" }

    $shellName = if ($PSVersionTable.PSEdition) {
        "$($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion)"
    } else {
        "PowerShell 5.1"
    }

    $md = @"
- **OS**: $winVer
- **AutoHotkey Version**: $ahkVer
- **Alacritty Version**: $alacVer
- **Monitor Setup**: $screens
- **Shell**: $shellName
"@

    Write-Host ""
    Write-Host $md
    Write-Host ""

    if (-not $NoClip) {
        try {
            if (Get-Command Set-Clipboard -ErrorAction SilentlyContinue) {
                $md | Set-Clipboard
            } else {
                $md | clip.exe
            }
            Write-Host "  ✨ Copied environment info to clipboard!" -ForegroundColor Green
            Write-Host "  💡 Open an issue: https://github.com/orgNero/quake-alacritty/issues/new/choose" -ForegroundColor DarkGray
            Write-Host ""
        } catch {}
    }
}

# Define global helper functions so user can run 'quake-help' or 'quake-env' anytime in their session
function global:quake-help {
    Show-QuakeCheatsheet
}

function global:quake-env {
    Show-QuakeEnvironment
}

if ($EnvInfo) {
    Show-QuakeEnvironment
} elseif ($TipOnly) {
    Show-QuakeTip
} else {
    Show-QuakeCheatsheet
}
