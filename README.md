# ⚡ Quake Alacritty Terminal

A sleek, macOS/i3-style drop-down ("visor") terminal setup for **Windows 11** built with **Alacritty** and **AutoHotkey v2**.

Features mouse-aware multi-monitor detection, dynamic 2×2 quad grid tiling, acrylic background blur, and pixel-perfect DPI-aware click-through cyan seam dividers.

---

## 📸 Preview

![Quake Alacritty Demo](assets/quake_alacritty_preview.gif)

---

## 🚀 Key Features

* **Drop-Down Visor (`Win + §`):** Smoothly toggles from the top on whichever monitor currently holds your **mouse cursor**. If already open on another display, pressing `Win + §` immediately hops the visor over to your current screen.
* **Smart Dynamic 2×2 Tiling (`Alt + Enter`):**
  * **1 Terminal:** Top visor (100% width, 40% screen height, borderless).
  * **2 Terminals:** Top row side-by-side (50% / 50% width, vertical cyan seam).
  * **3 Terminals:** 2 on top (50% each), 1 across the bottom (T-split cyan seams).
  * **4 Terminals:** Clean 2×2 quad grid (50% width & 50% height each, cyan cross seams).
* **Adjacent Cyan Dividers:** 
  * Only borders between neighboring terminals are colored (outer screen edges remain completely clean and borderless).
  * Rendered as click-through overlay bars (`+E0x20` / `WS_EX_TRANSPARENT`), so mouse selections pass directly into the terminal without interference.
  * `-DPIScale` enforcement ensures pixel-perfect coordinates on high-DPI displays (125%, 150%, etc.) with zero bleed across monitors.
* **Auto-Rebalancing (`Alt + W`):** Closing any terminal automatically collapses and re-tiles the remaining ones.
* **Keyboard Pane Navigation (`Alt + Arrows`):** Hop typing focus between splits without touching the mouse.
* **Window Swapping & Rotation (`Alt + Shift + Arrows`, `Alt + Shift + Space`):** Rearrange panes on the fly by swapping with adjacent windows or rotating all positions cyclically without losing keyboard focus.
* **First-Run Welcome Banner & Cheat Sheet (`quake-help`):** On the first toggle cold-start, greets you with an in-buffer ANSI quickstart cheat sheet formatted in theme-matching electric cyan. The cheat sheet remains in scrollback for easy reference while learning shortcuts and can be redisplayed anytime by running `quake-help`.
* **Taskbar Awareness:** Respects custom work areas (such as left-docked taskbars) using `MonitorGetWorkArea`.

---

## ⌨️ Shortcuts Reference

| Shortcut | Context | Description |
| :--- | :--- | :--- |
| **`Win + §`** | **Global** | Toggle terminal visor (shows / hides on monitor under mouse cursor) |
| **`Alt + Enter`** | Inside Alacritty | Spawn a new split (auto-tiles into 1 → 2 → 3 → 4 layout) |
| **`Alt + W`** | Inside Alacritty | Close focused split and smoothly rebalance remaining windows |
| **`Alt + R`** | Inside Alacritty | Force re-tile / balance windows |
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
MultiMonitorMode=hopping

[Appearance]
; Seam divider thickness in pixels (1-5px)
BorderGap=2

; Seam divider hex RGB color (without # prefix)
; Electric Cyan: 38bdf8 | One Dark Cyan: 56b6c2 | Purple: c678dd | Gray: 3e4452
BorderColor=38bdf8

; Visor height coverage percentage for the top visor row (20-90)
VisorHeightPercent=40

[Hotkeys]
; Global toggle hotkey (shows / hides visor on monitor under mouse cursor)
; #sc029 is Win + § (the key directly under Escape on Swedish/Nordic keyboards)
ToggleVisor=#sc029

; Window management shortcuts (active while inside Alacritty)
SplitWindow=!Enter
CloseWindow=!w
Retile=!r

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
