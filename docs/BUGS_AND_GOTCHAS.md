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

### Visor Hide: Hidden Foreground Windows Keep Receiving Keystrokes

#### Symptom
- `Win + §` hides the visor, but typing still lands in the (now invisible) terminal. The previous app or desktop never regains keyboard focus.

#### Root Cause
`WinHide` maps to `ShowWindow(SW_HIDE)`, which sends `WM_SHOWWINDOW` but not `WM_ACTIVATE`/`WM_ACTIVATEAPP`. Windows is allowed to leave the hidden HWND as the foreground window, so keystrokes keep being delivered to it. Hiding the panes in a loop makes the OS's "activate another window" choice even less predictable, especially in isolated multi-monitor mode where other visors stay visible and topmost.

#### Established Solution ([`HideVisorAndReturnFocus()` in `quake_alacritty.ahk`](../quake_alacritty.ahk))
- `CaptureVisorReturnWindow()` records the last non-visor foreground window before the visor takes focus; it is refreshed on every toggle where the foreground is not a pane.
- `HideVisorAndReturnFocus()` activates that target **before** the `WinHide` loop, so the visor is never the foreground window when it disappears.
- Post-hide verification (`ActivateReturnWindow()`, with `SwitchToThisWindow` as a fallback for foreground-lock refusals) re-asserts the target, then clears the tracker.
- If the target was closed/minimized while the visor was open, the first usable window in Z-order (`WinGetList()` order, skipping hidden/minimized/cloaked/tool/owned/`WS_EX_NOACTIVATE` windows, shell surfaces and all `alacritty.exe` windows) becomes the fallback.
- Focus is only reclaimed when one of the panes being hidden owns it; hiding the visor must never steal focus from an app the user switched to while it was open.

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



---

## 11. Windows PowerShell 5.1 ANSI Encoding & Right Double Quote Syntax Breakage

### Symptom
- Spawning a terminal or running `welcome.ps1` fails with parser errors:
  ```
  Unexpected token 'Œ" + ("â”€"' in expression or statement.
  Missing closing ')' in expression.
  Missing closing '}' in statement block or type definition.
  ```

### Root Cause
By default, Windows PowerShell 5.1 (`powershell.exe`) opens `.ps1` script files that lack a byte-order mark (BOM) using the legacy system ANSI code page (typically Windows-1252), rather than UTF-8.
In UTF-8, the box-drawing character `┌` is encoded as the 3-byte sequence `0xE2 0x94 0x8C`. In Windows-1252:
- `0xE2` is `â`
- `0x94` is `”` (`U+201D` Right Double Quotation Mark)
- `0x8C` is `Œ`

Because PowerShell treats Unicode right double quotation marks (`”`) as matching double quote delimiters, it interprets byte `0x94` as closing the string literal early, leaving `Œ` as an unquoted token outside the string and immediately throwing fatal parser errors.

### Established Solution
1. **ASCII-Safe Unicode Codepoints**: Never use raw multibyte Unicode box literals inside `.ps1` string concatenation. Define glyphs programmatically using `[string][char]0x250C` (`┌`), `[string][char]0x2500` (`─`), `[string][char]0x00A7` (`§`), etc.
2. **UTF-8 with BOM (`EF BB BF`) Enforcement**: Always save `.ps1` files using `New-Object System.Text.UTF8Encoding($true)` so PowerShell 5.1 reliably recognizes the UTF-8 encoding.

---

## 12. Windows 11 DWM Interception of `Win + Shift + Left / Right`

### Symptom
- Pressing `Win + Shift + Left` or `Win + Shift + Right` shifts only the single currently focused terminal pane across monitors, dropping it on top of existing windows on the other screen.
- AutoHotkey's multi-window visor migration / swap handler never executes (or executes after the window has already been moved by the OS).

### Root Cause
In Windows 10 and 11, `Win + Shift + Left` and `Win + Shift + Right` are hardcoded shell hotkeys registered by Windows Explorer and the Desktop Window Manager (DWM) for moving the active window to an adjacent display.
Because AutoHotkey runs under standard user token integrity, Windows intercepts and processes these specific `Win + Shift + Arrow` combinations at the kernel/win32k input level *before* AHK's low-level keyboard hook (`WH_KEYBOARD_LL`) can suppress or redirect them.

### Established Solution
Avoid using `#+Left` / `#+Right` as default keybindings for application-level multi-window migration.
Use an `Alt`-family modifier combination that Windows DWM never intercepts: **`Alt + Ctrl + Left` / `Alt + Ctrl + Right`** (`!^Left` / `!^Right`).
This fits naturally into Quake Alacritty's navigation hierarchy:
- `Alt + Arrows`: Move focus between panes
- `Alt + Shift + Arrows`: Swap pane positions within the current monitor
- `Alt + Ctrl + Left / Right`: Swap entire visor workspace across physical monitors

---

## 13. Spontaneous Window Termination & Orphan Divider Outlines (`Alt + F4`, `exit`)

### Symptom
- Closing split terminals via `Alt + F4`, typing `exit`, or killing a terminal process leaves cyan seam divider lines ("outlines") permanently visible and floating on the screen.
- Closing one split terminal via `Alt + F4` or `exit` leaves the remaining terminal stuck in its split dimensions (e.g. 50% width) with the seam divider frozen in place.

### Root Cause
Dividers are independent click-through GUI windows (`Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 -DPIScale")`) tracked in `g_MonitorDividers` and `g_Dividers`.
While `CloseSplit()` (bound to `Alt + W`) explicitly calls `ClearDividers()` and rebalances remaining terminals, native Windows operations—such as pressing `Alt + F4`, typing `exit`, or killing the process—terminate the window at the OS/win32 level completely bypassing AutoHotkey's script execution.
Because AutoHotkey was not receiving any window destruction notification, the GUI divider windows remained orphaned and rendered on top of the desktop.

### Established Solution
1. **Direct `!F4` Context Hook**:
   Map `!F4` directly to `CloseSplit()` under `HotIfWinActive("ahk_exe alacritty.exe")`:
   ```autohotkey
   RegisterKey("!F4", (*) => CloseSplit())
   ```
   This ensures that pressing `Alt + F4` while focused inside any Alacritty pane triggers instant (0ms) graceful closure, dynamic layout rebalancing, and divider cleanup identical to `Alt + W`.

2. **Background Watchdog Timer (`WatchdogCheck`, 250ms)**:
   A lightweight periodic timer checks tracked HWNDs against live OS window existence (`WinExist` / `GetAlacrittyWindows`):
   - If zero Alacritty windows exist across the system, all dividers are purged immediately.
   - If a window closed spontaneously (via `exit`, `Ctrl + D`, crash, or task manager) on an isolated monitor:
     - If zero windows remain on that monitor, `ClearDividers(monId)` destroys all orphan outlines.
     - If remaining windows exist and are visible, `TileAlacritty(monId)` smoothly re-tiles and expands the remaining panes into the vacated space.
   - If no tracked windows or dividers exist, the watchdog exits in nanoseconds with negligible CPU overhead.

3. **Reentrancy Guard (`g_LayoutLock`)**:
   A reference-counted lock (`g_LayoutLock++` / `g_LayoutLock--` wrapped in `try ... finally`) prevents the watchdog from executing concurrently during active user tiling, split spawning, or manual close operations.

---

## 14. AppData Deployment Copies vs Live Repo Development (`Alt + Ctrl + R` Reload Desync)

### Symptom
- Code changes in `quake_alacritty.ahk` inside the git repository are saved and committed, and `Alt + Ctrl + R` is pressed inside Alacritty, but the running script behaves identically to the old code.

### Root Cause
`install.ps1` by default copies repository files to `%APPDATA%\alacritty` and registers the startup shortcut to point to `%APPDATA%\alacritty\quake_alacritty.ahk`.
When developing in `repos\quake-alacritty`, editing the repository file does not touch the `%APPDATA%` copy. When AutoHotkey executes `Reload()` via `Alt + Ctrl + R`, it re-reads its own script path (`A_ScriptFullPath` = `%APPDATA%\alacritty\quake_alacritty.ahk`), loading the stale deployed copy instead of the repository file.

### Established Solution
Always link `%APPDATA%\alacritty` to the repository directory using symbolic links via `cmd /c mklink` (supported without admin rights when Windows Developer Mode is enabled):
```powershell
cmd /c "del `"%APPDATA%\alacritty\quake_alacritty.ahk`" && mklink `"%APPDATA%\alacritty\quake_alacritty.ahk`" `"C:\Users\maxve\repos\quake-alacritty\quake_alacritty.ahk`""
```
With symbolic links in place, `A_ScriptFullPath` resolves directly to the repository file, guaranteeing that in-process reload (`Alt + Ctrl + R`) immediately executes live code edits.

---

## 15. Installer Upgrade & Uninstall Teardown Gotchas

### Symptom
- Re-running `install.ps1` behaved like a fresh install (config overwritten, no upgrade notice).
- Running AutoHotkey instances were never stopped by the installer or uninstaller, or were force-killed leaving orphan click-through seam overlays.
- Uninstalling left `%APPDATA%\alacritty` and a stale "Installed Apps" entry behind.

### Root Cause
- `Get-Process` exposes **no** `CommandLine` property in Windows PowerShell 5.1, so `Where-Object { $_.CommandLine -like '*quake_alacritty*' }` silently matched nothing. Process discovery must go through `Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64.exe'"` and validate the parsed `.ahk` path.
- Force-killing AutoHotkey skips `OnExit`, leaving the script's seam divider GUIs behind.
- `.install-state.json`, `VERSION`, `CONFIG_SCHEMA` and timestamped `.bak` files are intentionally left in the deploy folder, so "delete the folder only when empty" never fires.

### Established Solution
- `quake_common.ps1` is dot-sourced by both scripts and provides `Get-QuakeAhkProcesses`, `Stop-QuakeAhkProcess`, install-state and version helpers.
- Teardown posts `WM_CLOSE` to the process windows first; `quake_alacritty.ahk` handles `WM_CLOSE` by exiting through `OnExit` (`CleanupOnExit` destroys all dividers). A force-kill fallback runs only after the grace period.
- `uninstall.ps1` deletes every known artifact explicitly (including the `HKCU\...\Uninstall\QuakeAlacritty` key) instead of relying on folder emptiness.
- User `config.ini` is merged append-only (missing keys/sections only) and every rewrite is preceded by a timestamped `.bak`; `-ResetConfig` is the only path that replaces it.

---

## 16. Spontaneous Window Termination & `TargetError` (`WinShow`, `WinSetAlwaysOnTop`, `WinMove`)

### Symptom
- Spawning a terminal (`Win + §`) or retiling fails with a modal error dialog:
  ```
  Error: Target window not found.
  Specifically: ahk_id <hwnd>
  WinSetAlwaysOnTop(1, "ahk_id " hwnd)
  ```

### Root Cause
1. **Invalid Shell Binary in `alacritty.toml`**: If `alacritty.toml` specifies a shell binary path that does not exist on the machine (e.g. hardcoded `C:\Program Files\Git\bin\bash.exe` when Git is installed in a custom directory like `C:\Users\<user>\Program\Git` or a portable folder), Alacritty starts, creates its top-level window for a split second, and immediately crashes with OS error 5 (`PermissionDenied` / `Åtkomst nekad`).
2. **AutoHotkey v2 `TargetError`**: When AHK's window poll detects the transient window HWND and calls `TileAlacritty()`, Alacritty exits in the middle of the loop. In AHK v2, calling `WinShow`, `WinSetAlwaysOnTop`, `WinMove`, or `WinActivate` on an HWND that was destroyed mid-execution throws an unhandled `TargetError` exception, halting script execution.

### Established Solution
1. **Multi-Source Shell Path Discovery (`install.ps1`)**:
   Locate `bash.exe` robustly across:
   - Registry: `HKLM:\SOFTWARE\GitForWindows`, `HKCU:\SOFTWARE\GitForWindows` (`InstallPath`)
   - Active PATH derivation: `(Get-Command git.exe).Source` -> `..\bin\bash.exe`
   - Common install folders: `C:\Program Files\Git`, `C:\Program Files (x86)\Git`, `%LOCALAPPDATA%\Programs\Git`, `%ProgramW6432%\Git`
   - Safe Fallback: If `bash.exe` cannot be verified with `Test-Path`, never write a non-existent binary path to `alacritty.toml`; fall back to `powershell.exe` with a clear warning.
2. **Defensive Window Operations (`quake_alacritty.ahk`)**:
   - Wrap `WinShow`, `WinSetAlwaysOnTop`, `WinMove`, `WinHide`, and `WinActivate` in `try` blocks.
   - Verify `WinExist("ahk_id " hwnd)` before pushing new HWNDs to monitor tracking arrays (`g_MonitorWindows`).

---

## 17. Background Update Check: Console Flash, `A_NowUTC` and PS 5.1 JSON Nulls

### Symptom
- A short `powershell.exe` console flashes when the visor script starts or the visor is toggled.
- The cache's `lastError` is written as `""` instead of `null`, so consumers cannot distinguish "failed" from "no error".

### Root Cause
- AutoHotkey's `Run()` starts a console-subsystem process with a visible console unless the `"Hide"` option (or `SW_HIDE`) is supplied. `RunWait` is not required to get a hidden child, and waiting on the check would block the AHK thread.
- `A_NowUTC` is a fixed-width `yyyyMMddHHmmss` stamp. AHK compares digit-only strings numerically, so comparing it to a 14-digit `nextCheckAtUtc` is chronological **only** while both values keep that width; Nan/non-numeric values fall back to string comparison.
- Windows PowerShell 5.1 converts `$null` to `""` when binding to a typed `[string]` parameter. A cache writer that takes `[string]$LastError` therefore emits `""`, not JSON `null`.

### Established Solution
- `MaybeCheckForUpdates()` resolves the checker next to the script first, then in `%APPDATA%\alacritty`, and spawns it with `Run(..., , "Hide")` inside a `try` block. It never uses `RunWait` and keeps a 5-minute in-memory debounce (duplicate-spawn guard), while the cache's `nextCheckAtUtc` (+24 h success, +1 h failure) drives retries from long-running instances.
- The cache gate uses a targeted regex and compares the fixed-width UTC strings (`nextCheck > A_NowUTC`); a missing or malformed field is treated as due.
- `update-check.ps1` declares `[object]$LastError` so `null` survives `ConvertTo-Json`, and writes the cache atomically (temp file + `Move-Item -Force`) while preserving unknown JSON fields for forward compatibility.

---

## 18. Updater Process Handoff: `Start-Process -Wait` and PS 5.1 Native Stderr

### Symptom
- `quake-update` appears to hang forever after the child installer prints its success summary.
- A failing `git` probe (`rev-parse '@{u}'`, `pull --ff-only`) aborts the updater with a raw `NativeCommandError` instead of a plain message, even though stderr was redirected.

### Root Cause
- `Start-Process -Wait` waits for the started process **and its descendants**. The installer relaunches AutoHotkey and exits, but the AHK grandchild keeps the wait alive indefinitely.
- Windows PowerShell 5.1 converts native stderr into a terminating `NativeCommandError` while `$ErrorActionPreference = "Stop"`. Redirecting with `2>$null` or `2> file` does **not** prevent the termination; only `2>&1` combined with a relaxed preference (or a helper that relaxes it) lets the caller inspect `$LASTEXITCODE`.

### Established Solution
- `update.ps1` launches the installer with the call operator (`& $powerShellExe -File $installer ...`) and reads `$LASTEXITCODE`. That waits for the direct child only, so the detached AHK process cannot block the updater.
- All git calls go through `Invoke-QuakeGit`, which temporarily sets `$ErrorActionPreference = "Continue"`, redirects stderr to a temp file, restores the preference in `finally`, and returns `ExitCode`/`Lines`/`Text`. Every failure path then prints a plain-language sentence; theme detection and error extraction never see PowerShell's stderr decoration.
- Prefer probing capabilities (`rev-parse --show-toplevel`) and checking `$LASTEXITCODE` over assuming a clean stderr stream from `git`.

---

## 19. Cached Update Notice: Stale `installedVersion`, Once-a-Day Marker and Prompt Latency

### Symptom
- After `quake-update`, every new terminal still prints `Update available` even though `VERSION` already reports the new version.
- A handwritten notice prints on every pane instead of once per calendar day, or `quake-help` silently consumes the daily throttle.
- A naive implementation adds tens of milliseconds to every terminal startup.

### Root Cause
- The cache's `installedVersion` is only refreshed by the next background check, so comparing `latestVersion` against the cache keeps advertising the version that was just replaced.
- `Get-Command <name>` for a command that does **not** exist scans the whole command table (~25 ms per call), and dot-sourcing `quake_common.ps1` inside a function re-parses it on every invocation because the definitions land in that function's scope.
- MSYS2/Git Bash `fork()` is expensive (~10-25 ms per external command). A prompt hook built from `cygpath` + `sed` + `head` + `tr` + `sort -V` forks 7+ processes and adds ~200 ms to **every** new shell, even when no notice is due.
- Writing the `.update-notice` marker from the manual `quake-help` path would consume the once-a-day budget for a view the user requested explicitly. A failed marker write must not suppress the notice or throw.

### Established Solution
- `welcome.ps1` compares the cache's `latestVersion` with the deployed `VERSION` file next to the script and uses the cache's `installedVersion` only when `VERSION` is missing.
- The `.update-notice` marker (one line, local `yyyyMMdd`) is written **only** by the automatic startup path (`-Startup`, passed by AHK and by the Git Bash banner hook). Manual `quake-help` displays the notice without writing or consuming the marker; marker write failures are swallowed.
- The PowerShell helper returns before dot-sourcing `quake_common.ps1` unless a newer version is actually pending, so ordinary startup stays at baseline; the notice path costs ~12 ms once a day.
- The Git Bash hook uses bash builtins only — `$(<file)`, `[[ $raw =~ ... ]]`, an integer version compare and `printf '%(%Y%m%d)T'` — instead of `grep`/`sed`/`sort -V`, keeping an up-to-date prompt at ~3 ms and a pending notice at ~15 ms, without dropping the notice. It strips CR/whitespace from `VERSION`, because a Windows checkout can deploy that file with CRLF line endings.
- `install.ps1` deletes `.update-notice` on every deploy and `uninstall.ps1` removes it with the other artifacts.
