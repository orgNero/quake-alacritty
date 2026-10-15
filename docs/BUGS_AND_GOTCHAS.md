# Bugs, Edge Cases & Technical Gotchas

This document records architectural quirks, Windows 11 OS friction, and hard-won fixes encountered during the development of **Quake Alacritty**. 

> [!IMPORTANT]
> **Always consult this file before refactoring or touching window enumeration, coordinate math, DPI scaling, or process launching.** Many non-obvious code blocks exist specifically to guard against the recurring bugs documented below.

---

## 1. Alacritty Ghost HWNDs & Child Window Filtering

### Symptom
- Spawning 2 terminals causes the layout to act as if 3 or 4 windows exist (blank space reserved, unexpected 3-way or 4-way splits).
- Closing a terminal fails to restore the 1-terminal 100% width layout because "ghost" windows are still detected.

### Root Cause
Alacritty on Windows does not create a single window per process. Under the hood (via `winit` and OpenGL/DirectX), it creates hidden utility/event windows:
- Nvidia OpenGL buffers: `NVOpenGLPbuffer`
- Event handler thread targets: `Winit Thread Event Target`
- Owned/tool helper windows

A naive query like `WinGetList("ahk_exe alacritty.exe")` grabs all of these auxiliary HWNDs, inflating the terminal count.

### Established Solution ([`GetAlacrittyWindows()` in `quake_alacritty.ahk`](../quake_alacritty.ahk))
Strictly filter enumerated windows using three criteria:
1. **Window Class**: Must equal `"Window Class"` (the actual terminal canvas).
2. **Extended Window Style**: Must NOT have `WS_EX_TOOLWINDOW` (`0x80`).
3. **Owner Window**: Must NOT have an owner window (`DllCall("GetWindow", "Ptr", hwnd, "UInt", 4, "Ptr") == 0`, where `GW_OWNER = 4`).

```autohotkey
cls      := WinGetClass("ahk_id " hwnd)
exStyle  := WinGetExStyle("ahk_id " hwnd)
hasOwner := DllCall("GetWindow", "Ptr", hwnd, "UInt", 4, "Ptr") ; GW_OWNER = 4

if (cls != "Window Class" || (exStyle & 0x80) || hasOwner)
    continue
```

---

## 2. Windows Z-Order Flip-Flop vs Spatial Order

### Symptom
- Clicking on a split pane causes windows to randomly switch positions on the next retile (`Alt + R`), when opening another split (`Alt + Enter`), or when closing a pane (`Alt + W`).

### Root Cause
The Windows API (`EnumWindows` / AHK's `WinGetList`) returns windows in **Z-order** (most recently active window at index 1). If window positions are calculated directly from `WinGetList`, focusing pane 2 promotes it to index 1, immediately swapping its slot with pane 1.

### Established Solution ([`SyncWindowOrder()` in `quake_alacritty.ahk`](../quake_alacritty.ahk))
- A global persistent array (`g_AlacrittyOrder`) preserves the assigned slot of each window across operations.
- `SyncWindowOrder()` compares live windows against `g_AlacrittyOrder`:
  - Retains existing windows in their previous order.
  - Appends new windows to the end.
  - Removes dead windows.
  - On cold start with multiple windows, sorts spatially (top-to-bottom, left-to-right) once before populating `g_AlacrittyOrder`.

---

## 3. Per-Monitor DPI Virtualization & Seam Alignment Drift

### Symptom
- Cyan seam divider lines are misaligned, drift by several pixels, or bleed onto secondary displays.
- Dividers look correct on a 100% DPI monitor, but scale up to 4–6 pixels wide on a 150% or 200% 4K monitor.

### Root Cause
AutoHotkey v2 GUIs enable automatic DPI scaling by default. When an AHK script calculates raw screen pixel coordinates (e.g., width 1920) and shows a GUI, Windows/AHK scales the dimensions a second time, multiplying pixel values by the monitor's DPI ratio (e.g., $1920 \times 1.25 = 2400$).

### Established Solution
Always disable DPI scaling on overlay divider GUIs using `-DPIScale`:
```autohotkey
div := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 -DPIScale")
```
This guarantees that 1 pixel in code equals exactly 1 physical screen pixel regardless of the display's scale factor.

---

## 4. Click Hijacking on Divider Overlays

### Symptom
- Users cannot click, highlight, or drag text near the edges of adjacent terminals.
- Mouse clicks near split borders feel "dead" or unresponsive.

### Root Cause
The cyan divider is an independent Windows GUI window placed between panes. If created as a standard window, it intercepts Windows mouse messages (`WM_LBUTTONDOWN`, `WM_MOUSEMOVE`), preventing mouse events from reaching the Alacritty window underneath.

### Established Solution
Apply the extended window style `+E0x20` (`WS_EX_TRANSPARENT`):
```autohotkey
div := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 -DPIScale")
```
Windows treats the divider as completely transparent to mouse clicks; all clicks fall through directly into the terminal buffer.

---

## 5. Negative Coordinates in Multi-Monitor Setups

### Symptom
- Tiling on a secondary monitor fails, tiles partially off-screen, or spawns with a zero/negative width.

### Root Cause
In Windows multi-monitor virtual screen space:
- The primary monitor has `(X=0, Y=0)` at its top-left.
- Any secondary monitor placed to the **left** or **above** the primary display has **negative X and/or Y coordinates** (e.g. `wLeft = -1920`, `wTop = -1080`).
- Naive coordinate logic assuming `X >= 0` or dividing coordinates incorrectly without accounting for negative offsets breaks window positioning.

### Established Solution
Always retrieve explicit work area bounds using `MonitorGetWorkArea(targetMon, &wLeft, &wTop, &wRight, &wBottom)`:
- Compute width as `totalWidth := wRight - wLeft`
- Compute height as `totalHeight := wBottom - wTop`
- Offset all window positions relative to `wLeft` and `wTop`:
  ```autohotkey
  currentX := wLeft
  WinMove(currentX, wTop, thisW, topHeight, "ahk_id " hwnd)
  ```

---

## 6. Work Area vs Full Monitor Bounds (Taskbar Collisions)

### Symptom
- Visor or 4-way tiling overlaps the Windows taskbar, gets clipped behind the taskbar, or leaves an ugly gap.
- Users with left-docked or top-docked custom taskbars experience distorted terminal heights.

### Root Cause
Using `MonitorGet` returns the physical resolution of the screen (e.g. $1920 \times 1080$) ignoring taskbars and app bars.

### Established Solution
Always use `MonitorGetWorkArea` instead of `MonitorGet`. `MonitorGetWorkArea` automatically subtracts the taskbar bounds regardless of whether the taskbar is at the bottom, top, left, or right.

---

## 7. Race Conditions During Split Spawning (`Alt + Enter`)

### Symptom
- Pressing `Alt + Enter` spawns a new terminal, but the layout only tiles the *old* terminals, leaving the newly spawned terminal floating in a default window size in the center of the screen.

### Root Cause
`Run("alacritty.exe")` is non-blocking. Alacritty takes 150–350ms to initialize its GPU context and create its top-level window. If `TileAlacritty()` executes immediately after `Run()`, the new window does not yet exist in `GetAlacrittyWindows()`.

### Established Solution
Insert a brief sleep before retiling:
```autohotkey
Run("alacritty.exe")
Sleep 350  ; Allow new window time to spawn
TileAlacritty()
```
Or for initial toggle cold start:
```autohotkey
Run("alacritty.exe")
if WinWait("ahk_exe alacritty.exe",, 3)
{
    Sleep 250
    TileAlacritty(targetMon)
}
```

---

## 8. Focus Loss on Move / Swap / Retile

### Symptom
- After moving or closing a window, typing does nothing until the user clicks on a terminal with the mouse.

### Root Cause
When AutoHotkey issues `WinMove`, `WinHide`, or recreates divider GUIs, the Windows OS window manager can shift active focus to the desktop, the taskbar, or a background application.

### Established Solution
Always explicitly re-assert focus on the active terminal window using `WinActivate("ahk_id " targetHwnd)` after layout operations.

---

## 9. Process Reaping from Transient Job Objects

### Symptom
- When an agent or automated script runner reloads AutoHotkey, the script seems to disappear from the system tray and never restarts.

### Root Cause
Terminal processes in automated runner environments run inside Windows Job Objects with `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`. When the subshell command finishes, Windows terminates all child processes in the job tree, killing the newly started AutoHotkey instance.

---

## 10. Windows Desktop Isolation (`exebox-...` vs `Default` Interactive Desktop)

### Symptom
- An AutoHotkey process appears alive in `Get-Process`, but the green "H" icon is nowhere to be found in the user's system tray / hidden icons menu, and hotkeys (`Win + §`) do nothing.

### Root Cause
Automated agents (e.g. Antigravity) run PowerShell commands inside an isolated virtual desktop (e.g. `exebox-V6P2PAEPO2SSFNP233JKLLSLCI`) within `WinSta0`.
When `Start-Process` or `AutoHotkey64.exe` is launched from this shell, Windows places the process on that hidden runner desktop instead of the user's interactive `Default` desktop:
1. `Shell_NotifyIcon` cannot communicate with `Shell_TrayWnd` on `Default` (no tray icon appears in the user's taskbar).
2. Low-level keyboard hooks (`WH_KEYBOARD_LL`) registered on the hidden desktop do not intercept keystrokes typed on the user's `Default` desktop.

### Established Solution
To launch into the true interactive user desktop from an agent shell:
1. **Interactive Task Scheduler Dispatch**:
   Register a temporary task using `New-ScheduledTaskPrincipal -LogonType Interactive -UserId $env:USERNAME`, trigger it immediately with `Start-ScheduledTask`, and clean it up. Task Scheduler forces the execution onto the user's interactive `Default` desktop.
2. **User Startup Shortcut**:
   Keep a persistent shortcut at `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\quake_alacritty.lnk` that the user or Windows login can execute directly on the `Default` desktop.
3. **In-Script `Reload()` Hotkey**:
   Use `!^r::Reload()` so the script reloads from within the interactive desktop, never going through external shell runners.


