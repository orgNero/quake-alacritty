# Changelog

All notable changes to this project will be documented in this file.
Every merge from a development branch into `main` must add an entry describing what was included.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [0.10.0] - 2026-10-20

## Features
### Major
- **Cross-Monitor Visor Relocation & Workspace Swapping (`Win + Shift + Left / Right`)**: Added dynamic multi-monitor visor migration allowing users to shift or swap their active terminal cluster across physical monitors without closing or restarting shells.
  - Supports both empty display migration (moving all windows and seam dividers to the target screen) and occupied display swapping (atomic pairwise exchange of terminal pools between screens).
  - Automatically sorts displays by physical X-coordinate (`mL`) rather than arbitrary Windows monitor IDs, ensuring directional arrows always map accurately to physical left/right desktop layouts.
  - Safely clamps at outer monitor boundaries to prevent accidental wraparound disorientation.
  - Full compatibility with both `MultiMonitorMode=isolated` (per-monitor workspaces) and `MultiMonitorMode=hopping` (roaming single pool).
### Minor
- **In-Terminal Cheat Sheet Synchronization (`welcome.ps1`)**: Added `Win + Shift + Left/Right` to the quickstart cheat sheet table and patched the `config.ini` parser to strip inline comments.

## Fixes
### Minor
- **Inline Comment Sanitization in Help Banner**: Fixed an issue where inline comments in `config.ini` (e.g. `ToggleVisor=#sc029 ; Win + §`) were erroneously parsed as modifier tokens by `welcome.ps1`.

## Window Management & Multi-Monitor
- Implemented physical monitor spatial sorting (`MoveVisorDirection`) using `MonitorGet` coordinates.
- Preserves and swaps per-monitor layout states (`g_MonitorTileLayout`, `g_MonitorTwoPaneLayout`, `g_MonitorSinglePaneSide`) during cross-monitor relocation.
- Re-tiles destination windows with `MonitorGetWorkArea` and updates click-through seam divider GUIs (`-DPIScale`) on both source and destination monitors.

## Styling & Appearance
_None_

## Configuration & Tooling
- Added `[Hotkeys] MoveVisorLeft` (`#+Left`) and `MoveVisorRight` (`#+Right`) to `config.ini` and `README.md`.

---
## [0.9.0] - 2026-10-20

## Features
### Major
- **Interactive CLI Setup Wizard (`install.ps1`)**: Introduced a guided CLI setup wizard prompting users for prerequisite installations (Alacritty, AHK v2, Nerd Font via winget), default shell configuration (PowerShell, WSL Bash, Git Bash), keyboard layout mapping (Nordic `Win + §` vs. US ANSI `Win + ` `), and Windows startup integration.
- **Dedicated Uninstaller (`uninstall.ps1`)**: Added a clean uninstallation script that stops running Quake Alacritty processes, removes startup shortcuts, unregisters profile hooks from `$PROFILE`, and removes deployed application scripts while allowing users to keep or delete their custom configuration files.
### Minor
- **Shell-Agnostic Launch Execution (`LaunchTerminalProcess`)**: Patched `quake_alacritty.ahk` to resolve `GetConfiguredShell()` from `alacritty.toml`. Non-PowerShell shells (e.g. `wsl.exe`, `bash.exe`) bypass PowerShell-specific startup flags (`-NoLogo -NoExit ... welcome.ps1`), allowing custom shells to launch cleanly without getting overridden.
- **Headless / Scripted Installer Flags**: Added automated parameter support (`-Shell`, `-KeyboardLayout`, `-InstallDependencies`, `-CreateStartupShortcut`, `-NonInteractive`) to `install.ps1` for unattended and CI deployments.

## Fixes
### Major
- **Non-PowerShell Startup Hijack**: Fixed an issue where `ShowHelpOnStart=tip` (or `FirstRun=true`) would force Alacritty to launch with `powershell.exe -e welcome.ps1` even when a user explicitly configured Bash or WSL in `alacritty.toml`.
### Minor
- **Windows PowerShell 5.1 BOM & Parser Resiliency**: Ensured installer and uninstaller `.ps1` files maintain proper UTF-8 BOM encoding and safe expression handling, preventing Windows-1252 ANSI character corruption and token parsing exceptions.

## Window Management & Multi-Monitor
_None_

## Styling & Appearance
_None_

## Configuration & Tooling
- **Deploy Uninstaller**: `install.ps1` automatically deploys `uninstall.ps1` to `%APPDATA%\alacritty\uninstall.ps1`.
- **Automated Shell Injection**: Configures `[terminal.shell]` program and args dynamically in `alacritty.toml` during installation.
- **Keyboard Layout Localization**: Automatically annotates and configures `ToggleVisor` in `config.ini` for Nordic (`#sc029`) and US (`#sc029` / backtick) keyboard users.

---

## [0.8.0] - 2026-10-20

## Features
### Major
- **50/50 Full-Screen Horizontal Split (`TwoPaneLayout=top-bottom`)**: Added full-screen 50/50 horizontal dual-pane tiling with two 100% width panes stacked top and bottom with a pixel-perfect click-through horizontal divider seam.
### Minor
- **5-Mode 2-Pane Live Layout Cycling (`Alt + L`)**: Seamlessly integrated `top-bottom` into dynamic layout rotation (`side-by-side-visor` -> `side-by-side-full` -> `top-bottom` -> `left-stacked` -> `right-stacked`).
- **Smooth 2<->3 Pane Spawn and Despawn Transitions**: Spawning a 3rd pane (`Alt + Enter`) from `top-bottom` smoothly transitions into `top` master orientation without jarring window reordering; closing a pane from `top` or `bottom` 3-pane layouts automatically collapses into `top-bottom`.

## Fixes
_None_

## Window Management & Multi-Monitor
- Symmetrical horizontal work area division (`MonitorGetWorkArea`) maintaining exact DPI scale and click-through seam overlay alignment for horizontal splits.

## Styling & Appearance
_None_

## Configuration & Tooling
- **Configuration Option in `config.ini`**: Added `top-bottom` (with aliases `horizontal-full` and `horizontal`) to `[Appearance] TwoPaneLayout`.

## [0.7.0] - 2026-10-20

## Features
### Major
- **Sleek Startup Help Command Hint (`ShowHelpOnStart=tip`)**: Replaced full-table startup dumping with a clean, unobtrusive 1-line reminder (`💡 Tip: Type 'quake-help' to view keyboard shortcuts`) on every terminal launch (both visor cold starts and splits).
- **Interactive Quickstart Cheat Sheet on Demand (`quake-help`)**: Running `quake-help` anytime in any terminal session displays the complete 20-line ANSI quickstart cheat sheet box.
### Minor
- **Configurable Help Display Modes**: Added `[General] ShowHelpOnStart` supporting `tip` (sleek 1-line hint on start, default), `banner` (full table on start), and `none` (completely silent startup).
- **Centralized Terminal Launcher (`LaunchTerminalProcess`)**: Consolidated terminal invocation into a unified launcher across visor toggling and split creation.

## Fixes
### Major
- **PowerShell 5.1 ANSI Quote Parsing Fix (`welcome.ps1`)**: Resolved parser crash (`Unexpected token 'Œ'`) occurring in Windows PowerShell 5.1 when executing `welcome.ps1`. Replaced raw multibyte Unicode box characters with ASCII-safe `[string][char]0x...` definitions and ensured UTF-8 with BOM (`EF BB BF`) output encoding.
### Minor
_None_

## Window Management & Multi-Monitor
_None_

## Styling & Appearance
- **Cheat Sheet Label Polish**: Aligned visor shortcut description in `welcome.ps1` to reflect mouse-aware per-display toggling.

## Configuration & Tooling
- **Configuration Option in `config.ini`**: Added `[General] ShowHelpOnStart=tip` with documentation in `config.ini` and `README.md`.

---

## [0.6.0] - 2026-10-20

## Features
### Major
- **Independent Per-Monitor Terminal Workspaces (`MultiMonitorMode=isolated`)**: Each physical monitor now maintains its own isolated terminal workspace (`g_MonitorWindows := Map()`). Toggling the visor (`Win + §`) on one display strictly shows or hides only that display's terminals without disrupting terminals on other screens.
- **Display Topology Safety & Migration (`WM_DISPLAYCHANGE`)**: Added automatic event listener for Windows message `0x007E` (`WM_DISPLAYCHANGE`). If a secondary monitor is unplugged, disconnected, or enters sleep mode, any orphaned terminals belonging to it are automatically migrated to the primary display.
### Minor
- **Per-Monitor Divider Isolation**: Cyan seam dividers are now tracked independently per monitor (`g_MonitorDividers[targetMon] := []`). Tiling, showing, or hiding splits on one display never affects or flickers divider lines on other displays.
- **Per-Monitor Layout Memory**: Tile layouts (`TileLayout`), 2-pane modes (`TwoPaneLayout`), and half-screen states (`SinglePaneSide`) are tracked per display, allowing different layout presets (e.g. `left-stacked` on a secondary portrait display and `bottom` master on an ultrawide display).
- **Directional Navigation & Swapping Monitor Boundary Containment**: Confined `FocusDirection` (`Alt + Arrows`), `SwapDirection` (`Alt + Shift + Arrows`), and `RotateWindows` (`Alt + Shift + Space`) to the active display so split navigation never jumps unintentionally across physical screens.

## Fixes
### Major
_None_
### Minor
- **Display Drag Reassignment**: Added detection in `SyncMonitorWindows` for visible terminals dragged across monitors (or moved via `Win + Shift + Arrows`), seamlessly reassigning their tracking to the destination monitor.

## Window Management & Multi-Monitor
- **Partitioned Window Synchronization**: Implemented `SyncMonitorWindows(targetMon)` replacing the single-pool array with monitor-keyed partition lists while preserving backward compatibility for users configuring `MultiMonitorMode="hopping"`.
- **First-Run Banner per Monitor**: Ensured `LaunchNewTerminal(targetMon)` properly hooks first-run welcome banners on whichever monitor first summons the terminal.

## Styling & Appearance
- **Zero-Flicker Multi-Screen Seam Rendering**: Partitioned divider creation and destruction so redrawing dividers on one monitor does not destroy or blink dividers on other active monitors.

## Configuration & Tooling
- **Default Multi-Monitor Mode in `config.ini`**: Set `[General] MultiMonitorMode=isolated` as the default mode in `config.ini` with documentation for `isolated` and `hopping` options.

---

## [0.5.0] - 2026-10-18

## Features
### Major
- **Configurable Multi-Pane Terminal Layouts (`TileLayout` & `TwoPaneLayout`)**: Introduced 4-cardinal 3-pane master orientations (`bottom`, `top`, `left`, `right`) and configurable 2-pane modes (`side-by-side-visor`, `side-by-side-full`, `left-stacked`, `right-stacked`).
- **Live Layout Cycling (`Alt + L`)**: Added on-the-fly layout cycle shortcut (`CycleLayout=!l`) allowing live toggling between 2-pane modes and 3-pane master orientations without restarting or editing configuration files.
### Minor
- **Half-Screen Stacked Workspaces**: Added `left-stacked` and `right-stacked` 2-pane layouts that occupy 50% screen width while leaving the opposite half unobstructed for viewing browser documentation or IDEs.
- **Cheat Sheet & Banner Integration**: Updated `welcome.ps1` and `quake-help` to include the `Alt + L` layout cycle shortcut.

## Fixes
### Major
_None_
### Minor
- **Deterministic Directional Tie-Breaking**: Resolved equidistant centroid ambiguity in `FocusDirection` and `SwapDirection` across asymmetrical master layouts (preferring higher panes on horizontal navigation and leftmost panes on vertical navigation).

## Window Management & Multi-Monitor
- **Dynamic Spawning & Despawning Transitions**: Spawning a 3rd pane (`Alt + Enter`) from `left-stacked` or `right-stacked` expands into the opposite half as a full-height master (`right` or `left` layout). Closing a stacked pane (`Alt + W`) preserves the remaining terminal on its half-screen column (`50%` width, `100%` height) without snapping back to a full-width visor.
- **Cold-Start Slot Stability**: Aligned spatial `(Y, X)` coordinate reading order in `TileAlacritty()` across all 4 cardinal master orientations so script reloads (`Alt + Ctrl + R`) maintain pane slot stability.

## Styling & Appearance
- **Clean Half-Screen Boundary Seams**: Configured `CreateDivider` to render only internal divider seams between stacked panes in half-screen modes, avoiding intrusive outer borders against background desktop windows.

## Configuration & Tooling
- **Configuration Options in `config.ini`**: Added `[Appearance] TileLayout=bottom`, `[Appearance] TwoPaneLayout=side-by-side-visor`, and `[Hotkeys] CycleLayout=!l`.

---

## [0.4.0] - 2026-10-16

## Features
### Major
- **In-Terminal First-Run Welcome Banner (`welcome.ps1`)**: Renders a persistent ANSI quickstart cheat sheet directly inside the initial terminal buffer on cold start when `FirstRun=true` in `config.ini`, replacing transient OS notifications.
### Minor
- **Session & Profile Help Command (`quake-help`)**: Introduced `quake-help` command in PowerShell sessions allowing users to redisplay the quickstart cheat sheet anytime on demand.
- **Dynamic Hotkey Introspection**: The welcome cheat sheet dynamically parses `config.ini` to display custom user keybindings with clean human-readable labels.

## Fixes
### Major
_None_
### Minor
_None_

## Window Management & Multi-Monitor
- **First-Run Cold Start Launch Hook**: Integrated banner invocation into `ToggleVisor()` when `windows.Length == 0` and `g_FirstRun == true`, automatically writing `FirstRun=false` to `config.ini` so subsequent splits and future visor toggles spawn standard shells.
- **Shell Resolution (`GetDefaultShell`)**: Added automatic detection of configured shell in `alacritty.toml` to support `pwsh.exe` and `powershell.exe` with `-NoLogo -NoExit -ExecutionPolicy Bypass`.

## Styling & Appearance
- **Electric Cyan ANSI Theming**: Designed the cheat sheet using Unicode box-drawing borders and electric cyan (`#38bdf8`) ANSI color sequences aligned with Quake Alacritty's seam divider theme.

## Configuration & Tooling
- **Automated Deployment & Profile Integration (`install.ps1`)**: Updated `install.ps1` to deploy `welcome.ps1` to `%APPDATA%\alacritty\` and register the `quake-help` helper function in the user's PowerShell `$PROFILE`.

---

## [0.3.2] - 2026-10-15

## Features
### Major
_None_
### Minor
_None_

## Fixes
### Major
_None_
### Minor
- **Cold-Start Visor Focus (`Win + §`)**: Automatically shift keyboard typing focus via `WinActivate` to the newly launched Alacritty terminal on initial cold start, preventing focus from remaining on background desktop applications.

## Window Management & Multi-Monitor
- **Adaptive Cold-Start Polling**: Extended initial window appearance polling in `ToggleVisor()` to accommodate GPU context initialization during fresh process launch before asserting window focus.

## Styling & Appearance
_None_

## Configuration & Tooling
_None_

---

## [0.3.1] - 2026-10-15

## Features
### Major
_None_
### Minor
_None_

## Fixes
### Major
_None_
### Minor
- **Split Focus on Creation (`Alt + Enter`)**: Automatically shift keyboard typing focus to newly spawned Alacritty split terminals using `WinActivate` after dynamic grid retiling, preventing focus from remaining stuck in the parent pane.

## Window Management & Multi-Monitor
- **Live HWND Differential Tracking**: Enhanced `SpawnSplit()` to capture pre- and post-launch window sets, accurately isolating the new window ID and ensuring reliable focus transfer across multi-monitor setups.

## Styling & Appearance
_None_

## Configuration & Tooling
_None_

---

## [0.3.0] - 2026-10-15

## Features
### Major
- **Unified Configuration Engine (`config.ini`)**: Introduced centralized `.ini` configuration for Quake Alacritty wrapper behavior. Users can now customize hotkeys, seam borders, and visor height without modifying AutoHotkey scripts.
### Minor
- **Dynamic Hotkey Registration**: Replaced static AutoHotkey declarations with dynamic `Hotkey()` bindings, allowing any visor shortcut (including `ToggleVisor`, `SplitWindow`, `CloseWindow`, `Retile`, directional focus navigation, pane swapping, and cyclic rotation) to be rebound from `config.ini`.
- **Configurable Visor Coverage**: Added `VisorHeightPercent` setting in `config.ini` to let users adjust the top visor row coverage (from 10% to 100% of work area height).

## Fixes
### Major
_None_
### Minor
- **Configuration Preservation on Reinstall**: Updated `install.ps1` to prevent overwriting existing `%APPDATA%\alacritty\config.ini` during standard deployments, preserving user preferences across updates.

## Window Management & Multi-Monitor
- **Dynamic Layout Height**: `TileAlacritty()` dynamically calculates top row visor height based on `VisorHeightPercent` from `config.ini`.

## Styling & Appearance
- **Customizable Seam Borders**: Border gap thickness (`BorderGap`) and hex color (`BorderColor`) are now loaded directly from `config.ini` and applied dynamically to click-through divider GUIs.

## Configuration & Tooling
- **Deployment & Schema**: Added default `config.ini` template to repository and updated `install.ps1` to deploy `config.ini` alongside `alacritty.toml` and `quake_alacritty.ahk`.

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
