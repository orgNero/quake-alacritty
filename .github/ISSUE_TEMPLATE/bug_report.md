---
name: Bug report
about: Report a bug, crash, or unexpected behavior in Quake Alacritty
title: 'fix: '
labels: bug
assignees: ''
---

## Description
A clear and concise description of what the bug is.

## Steps to Reproduce
1. Press `...` or run command `...`
2. Perform action `...`
3. Observe unexpected behavior: `...`

## Expected Behavior
A clear and concise description of what you expected to happen.

## Environment
<!--
💡 Quick Tip:
If you are using Quake Alacritty (PowerShell), type `quake-env` in your terminal to automatically format and copy your environment info to your clipboard.

Alternatively, paste this one-liner into PowerShell to extract and copy your environment info:
& { $o = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"); $a = @("AutoHotkey64.exe", "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe", "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe") | ForEach-Object { if ($_ -and (Test-Path $_ -PathType Leaf -ErrorAction SilentlyContinue)) { $_ } else { (Get-Command $_ -ErrorAction SilentlyContinue).Source } } | Where-Object { $_ } | Select-Object -First 1; $av = if ($a) { (Get-Item $a).VersionInfo.ProductVersion } else { "N/A" }; $lv = try { $p = [Diagnostics.Process]::Start([Diagnostics.ProcessStartInfo]@{FileName="alacritty";Arguments="--version";RedirectStandardOutput=$true;UseShellExecute=$false;CreateNoWindow=$true}); $p.StandardOutput.ReadToEnd().Trim() -replace '^alacritty\s*','' } catch { "N/A" }; Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue; $s = try { ([Windows.Forms.Screen]::AllScreens | ForEach-Object { "$($_.Bounds.Width)x$($_.Bounds.Height)$(if($_.Primary){' (Primary)'})" }) -join ', ' } catch { "Unknown" }; $b = "- **OS**: Windows 11 $($o.DisplayVersion) (Build $($o.CurrentBuild))`n- **AutoHotkey Version**: $av`n- **Alacritty Version**: $lv`n- **Monitor Setup**: $s`n- **Shell**: $($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion)"; $b; if (Get-Command Set-Clipboard -ErrorAction SilentlyContinue) { $b | Set-Clipboard } else { $b | clip.exe }; Write-Host "`n(Copied to clipboard!)" -ForegroundColor Green }
-->
- **OS**: Windows 11 (e.g., 23H2 / 24H2)
- **AutoHotkey Version**: (e.g., v2.0.18)
- **Alacritty Version**: (e.g., 0.17.0)
- **Monitor Setup**: (e.g., Dual monitor, Primary 100%, Secondary 125% DPI)
- **Shell**: (PowerShell 5.1 / PowerShell 7 / Git Bash / WSL / CMD)

## Configuration & Logs
- Any custom options in `config.ini` or `alacritty.toml`?
- Error dialog or tray icon notification details (if any):

## Screenshots / Additional Context
Add screenshots, GIFs, or any extra context here.
