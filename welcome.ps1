# Quake Alacritty - In-Terminal Welcome Banner & Cheat Sheet
[CmdletBinding()]
param()

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

function Show-QuakeCheatsheet {
    # Resolve config.ini location (%APPDATA%\alacritty\config.ini or local script directory)
    $configPath = Join-Path $env:APPDATA "alacritty\config.ini"
    if (-not (Test-Path $configPath)) {
        $localConfig = Join-Path $PSScriptRoot "config.ini"
        if (Test-Path $localConfig) { $configPath = $localConfig }
    }

    $chSection  = [string][char]0x00A7  # §
    $chBullet   = [string][char]0x2022  # •
    $chBolt     = [string][char]0x26A1  # ⚡
    $chBulb     = [char]::ConvertFromUtf32(0x1F4A1) # 💡

    # Box-drawing glyphs defined as strings for cross-version string multiplication & encoding safety
    $chTopLeft  = [string][char]0x250C  # ┌
    $chHoriz    = [string][char]0x2500  # ─
    $chTopRight = [string][char]0x2510  # ┐
    $chVert     = [string][char]0x2502  # │
    $chTLeft    = [string][char]0x251C  # ├
    $chTRight   = [string][char]0x2524  # ┤
    $chBotLeft  = [string][char]0x2514  # └
    $chBotRight = [string][char]0x2518  # ┘

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
                    $v = $Matches[2].Trim()
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
    Write-Host ""
}

# Define global helper function so user can run 'quake-help' anytime in their session
function global:quake-help {
    Show-QuakeCheatsheet
}

# Display immediately on execution
Show-QuakeCheatsheet