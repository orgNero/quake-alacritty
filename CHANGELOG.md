# Changelog

All notable changes to this project will be documented in this file.
Every merge from a development branch into `main` must add an entry describing what was included.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

## Features
### Major
_None_
### Minor
_None_

## Fixes
### Major
_None_
### Minor
_None_

## Window Management & Multi-Monitor
_None_

## Styling & Appearance
_None_

## Configuration & Tooling
_None_

---

## [0.2.0] - 2026-10-15

## Features
### Major
_None_
### Minor
- **Pane Position Swapping (`Alt + Shift + Arrows`)**: Swap the active terminal pane with its adjacent neighbor (left, right, up, down) using geometric center-point proximity calculation and continuous keyboard focus retention.
- **Cyclic Pane Rotation (`Alt + Shift + Space`)**: Cyclically rotate all pane positions clockwise across the active grid layout with zero directional ambiguity.
- **Development Script Reload (`Alt + Ctrl + R`)**: Instant in-process AutoHotkey reload for immediate development feedback and configuration updates without terminal intervention.

## Fixes
### Major
_None_
### Minor
_None_

## Window Management & Multi-Monitor
- **Instant Snap Performance (`SetWinDelay -1`)**: Disabled artificial AutoHotkey window delays (`SetWinDelay -1`, `SetControlDelay -1`), eliminating 100ms pauses between individual `WinMove` / `WinShow` calls for instantaneous pane swapping.
- **Adaptive Split Spawning**: Replaced static `Sleep 350` and `Sleep 200` delays in `Alt + Enter`, `Alt + W`, and `#§` with adaptive 15ms polling loops, shaving up to ~250ms off terminal split launch and collapse times.

## Styling & Appearance
_None_

## Configuration & Tooling
_None_

---

## [0.1.0] - 2026-10-14

## Features
### Major
- **Drop-Down Visor (`Win + §`)**: Global hotkey toggling terminal visor from top of screen on the display currently holding the mouse cursor; seamlessly hops screens if already open elsewhere.
- **Smart Dynamic 2×2 Tiling (`Alt + Enter`, `Alt + W`, `Alt + R`)**:
  - Automatically balances layouts for 1 (top visor), 2 (top split), 3 (T-split), and 4 (2×2 quad grid) terminals.
  - Automatically rebalances and collapses splits when closing any pane with `Alt + W`.

### Minor
- **Keyboard Pane Navigation (`Alt + Arrows`)**: Move active typing focus between left/right and top/bottom panes without touching the mouse.
- **Automated PowerShell Installer (`install.ps1`)**: Streamlined installation script supporting winget dependency installation, configuration directory setup, symbolic links, and Windows Startup shortcut generation.

## Fixes
### Major
_Initial release_
### Minor
_Initial release_

## Window Management & Multi-Monitor
- Multi-monitor coordinate detection with per-monitor DPI scaling awareness (`-DPIScale`).
- Taskbar work area awareness via `MonitorGetWorkArea` to support left/right/custom taskbar docking.

## Styling & Appearance
- Windows 11 acrylic blur effect and 0.70 background opacity via Alacritty config.
- Click-through electric cyan seam dividers (`+E0x20` / `WS_EX_TRANSPARENT`) rendered exclusively between neighboring panes with no outer border bleed.

## Configuration & Tooling
- Base `alacritty.toml` configuring JetBrainsMono Nerd Font, window padding, and decorations.
- Configurable global variables for border thickness (`g_BorderGap`) and seam color (`g_BorderColor`) in `quake_alacritty.ahk`.
