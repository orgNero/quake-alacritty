# ⚡ Quake Alacritty Terminal

A sleek, macOS/i3-style drop-down ("visor") terminal setup for **Windows 11** built with **Alacritty** and **AutoHotkey v2**.

Features mouse-aware multi-monitor detection, dynamic 2×2 quad grid tiling, acrylic background blur, and pixel-perfect DPI-aware click-through cyan seam dividers.

---

## 📸 Preview

![Quake Alacritty Demo](assets/quake_alacritty_preview.gif)

---

## 🚀 Key Features

* **Independent Per-Monitor Terminal Workspaces (`Win + §`):**
  * **Isolated Workspaces (`MultiMonitorMode=isolated`, Default):** Each physical monitor maintains its own independent terminal workspace, layout orientation, and seam dividers. Summoning or dismissing the visor on one screen never disturbs or flickers terminals running on another display.
  * **Hopping Mode (`MultiMonitorMode=hopping`):** Prefer a single floating visor? Switch mode to `hopping` in `config.ini` to let a single terminal pool travel between displays to follow your mouse.
  * **Display Topology Safety:** Automatically detects monitor disconnects and resolution shifts (`WM_DISPLAYCHANGE`), safely migrating any orphaned terminals to your primary display without losing session states.
* **Smart Dynamic Multi-Pane Tiling (`Alt + Enter`, `Alt + L`):**
  * **1 Terminal:** Top visor (100% width, 40% height) or side half-screen column (50% width, 100% height).
  * **2 Terminals:** 4 flexible modes cycled live via `Alt + L`:
    * `side-by-side-visor`: Top row side-by-side (50% / 50% width, 40% visor height).
    * `side-by-side-full`: 2 full-height columns (50% / 50% width, 100% height).
    * `left-stacked`: 2 vertically stacked panes on the Left half (50% width each), keeping the Right half open for background desktop apps.
    * `right-stacked`: 2 vertically stacked panes on the Right half (50% width each), keeping the Left half open for background desktop apps.
  * **3 Terminals:** 4 cardinal master orientations configured in `config.ini` and cycled via `Alt + L`:
    * `bottom`: 2 top panes (50% each), 1 bottom master pane (100% width).
    * `top`: 1 top master pane (100% width), 2 bottom panes (50% each).
    * `left`: 1 left master pane (100% height), 2 right stacked panes (50% height each).
    * `right`: 2 left stacked panes (50% height each), 1 right master pane (100% height).
  * **4 Terminals:** Clean 2×2 quad grid (50% width & 50% height each, cyan cross seams).
* **Adjacent Cyan Dividers:** 
  * Only borders between neighboring terminals are colored (outer screen edges and desktop boundaries remain completely clean and borderless).
  * Rendered as click-through overlay bars (`+E0x20` / `WS_EX_TRANSPARENT`), so mouse selections pass directly into the terminal without interference.
  * `-DPIScale` enforcement ensures pixel-perfect coordinates on high-DPI displays (125%, 150%, etc.) with zero bleed across monitors.
* **Auto-Rebalancing & Transitions (`Alt + W`):** Closing any terminal automatically collapses and re-tiles the remaining ones. Closing a stacked split preserves the remaining terminal on its half-screen column without snapping to full-width visor.
* **Keyboard Pane Navigation (`Alt + Arrows`):** Hop typing focus between splits without touching the mouse, featuring deterministic tie-breaking across asymmetrical master layouts.
* **Window Swapping & Rotation (`Alt + Shift + Arrows`, `Alt + Shift + Space`):** Rearrange panes on the fly by swapping with adjacent windows or rotating all positions cyclically without losing keyboard focus.
* **In-Terminal Startup Help Hint & Cheat Sheet (`quake-help`):** Displays a sleek 1-line reminder (`💡 Tip: Type 'quake-help' to view keyboard shortcuts`) on every terminal start. Configurable via `ShowHelpOnStart=tip` in `config.ini` (`tip` for sleek 1-line hint, `banner` for full 20-line table, `none` for silent startup). Running `quake-help` displays the full electric cyan quickstart cheat sheet on demand anytime.
* **Taskbar Awareness:** Respects custom work areas (such as left-docked taskbars) using `MonitorGetWorkArea`.

---

## ⌨️ Shortcuts Reference

| Shortcut | Context | Description |
| :--- | :--- | :--- |
| **`Win + §`** | **Global** | Toggle terminal visor (shows / hides on monitor under mouse cursor) |
| **`Alt + Enter`** | Inside Alacritty | Spawn a new split (auto-tiles into 1 → 2 → 3 → 4 layout) |
| **`Alt + W`** | Inside Alacritty | Close focused split and smoothly rebalance remaining windows |
| **`Alt + R`** | Inside Alacritty | Force re-tile / balance windows |
| **`Alt + L`** | Inside Alacritty | Cycle pane layout mode / master orientation live |
| **`Alt + Left` / `Right`** | Inside Alacritty | Move active typing focus between left & right panes |
| **`Alt + Up` / `Down`** | Inside Alacritty | Move active typing focus between top & bottom panes |
| **`Alt + Shift + Left` / `Right`** | Inside Alacritty | Swap active pane position with left / right neighbor |
| **`Alt + Shift + Up` / `Down`** | Inside Alacritty | Swap active pane position with top / bottom neighbor |
| **`Alt + Shift + Space`** | Inside Alacritty | Rotate all terminal pane positions cyclically clockwise |
| **`Alt + Ctrl + R`** | Inside Alacritty | Instant in-process script reload (development & config refresh) |

---

## 📦 Prerequisites

Run the following commands in PowerShell to install the prerequisites:

```powershell
# 1. Alacritty Terminal
winget install -e --id Alacritty.Alacritty

# 2. AutoHotkey v2 (required for window management)
winget install -e --id AutoHotkey.AutoHotkey

# 3. JetBrainsMono Nerd Font (icons & glyphs)
winget install -e --id DEVCOM.JetBrainsMonoNerdFont
```

---

## ⚡ Quick Start

### Option A: Using the Automated Install Script
Run PowerShell from inside the repository folder:

```powershell
# Standard deployment (copies files and sets up Windows Startup)
.\install.ps1

# Or with automatic dependency installation and symbolic links:
.\install.ps1 -InstallDependencies -UseSymlinks -CreateStartupShortcut
```

### Option B: Manual Setup
1. Copy `alacritty.toml`, `quake_alacritty.ahk`, `config.ini`, and `welcome.ps1` to your configuration folder:
   ```
   C:\Users\<YourUsername>\AppData\Roaming\alacritty\
   ```
2. Run `quake_alacritty.ahk` with AutoHotkey v2.
3. Press **`Win + §`** anywhere to summon your terminal!

---

## 🎨 Customization

Quake Alacritty uses a clean separation of concerns:
- **`config.ini`**: Governs wrapper behavior, window dimensions, seam borders, and all hotkey bindings.
- **`alacritty.toml`**: Governs terminal styling, font definitions, opacity, and Windows 11 acrylic blur.

### Configuration File (`config.ini`)
Located at `%APPDATA%\alacritty\config.ini` (or the repository root):

```ini
[General]
FirstRun=true
; Multi-monitor visor workspace mode (isolated | hopping)
MultiMonitorMode=isolated
; Help command hint on terminal launch (tip | banner | none)
ShowHelpOnStart=tip

[Appearance]
; Seam divider thickness in pixels (1-5px)
BorderGap=2

; Seam divider hex RGB color (without # prefix)
; Electric Cyan: 38bdf8 | One Dark Cyan: 56b6c2 | Purple: c678dd | Gray: 3e4452
BorderColor=38bdf8

; Visor height coverage percentage for the top visor row (20-90)
VisorHeightPercent=40

; 3-pane master orientation layout mode (bottom | top | left | right)
; bottom: Top row 2 panes (50%/50%), Bottom master pane (100% width)
; top:    Top master pane (100% width), Bottom row 2 panes (50%/50%)
; left:   Left master pane (100% height), Right column 2 stacked panes
; right:  Right master pane (100% height), Left column 2 stacked panes
TileLayout=bottom

; 2-pane split mode (side-by-side-visor | side-by-side-full | left-stacked | right-stacked)
; side-by-side-visor: 2 columns at VisorHeightPercent
; side-by-side-full:  2 columns at 100% work area height
; left-stacked:       2 stacked panes on Left half, desktop open on Right
; right-stacked:      2 stacked panes on Right half, desktop open on Left
TwoPaneLayout=side-by-side-visor

[Hotkeys]
; Global toggle hotkey (shows / hides visor on monitor under mouse cursor)
; #sc029 is Win + § (the key directly under Escape on Swedish/Nordic keyboards)
ToggleVisor=#sc029

; Window management shortcuts (active while inside Alacritty)
SplitWindow=!Enter
CloseWindow=!w
Retile=!r
CycleLayout=!l

; Focus navigation
FocusLeft=!Left
FocusRight=!Right
FocusUp=!Up
FocusDown=!Down

; Position swapping & rotation
SwapLeft=!+Left
SwapRight=!+Right
SwapUp=!+Up
SwapDown=!+Down
RotatePanes=!+Space

; Development in-process reload
ReloadScript=!^r
```

> [!TIP]
> After saving changes in `config.ini`, press **`Alt + Ctrl + R`** while inside Alacritty to instantly reload settings without restarting the terminal!

### Adjusting Opacity & Blur
Edit [`alacritty.toml`](alacritty.toml):
```toml
[window]
opacity = 0.70    # 0.0 is completely transparent, 1.0 is solid
blur = true       # Windows 11 Acrylic blur effect
decorations = "None"
```

---

## 📄 License
MIT License. Feel free to use, modify, and share!
