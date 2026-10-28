# ⚡ Quake Alacritty Terminal

A sleek, macOS/i3-style drop-down ("visor") terminal setup for **Windows 11** built with **Alacritty** and **AutoHotkey v2**.

Features mouse-aware multi-monitor detection, dynamic 2×2 quad grid tiling, acrylic background blur, and pixel-perfect DPI-aware click-through cyan seam dividers.

[![GitHub Issues](https://img.shields.io/github/issues/orgNero/quake-alacritty?color=38bdf8)](https://github.com/orgNero/quake-alacritty/issues)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## 🚀 Key Features

* **Independent Per-Monitor Terminal Workspaces (`Win + §`):**
  * **Isolated Workspaces (`MultiMonitorMode=isolated`, Default):** Each physical monitor maintains its own independent terminal workspace, layout orientation, and seam dividers. Summoning or dismissing the visor on one screen never disturbs or flickers terminals running on another display.
  * **Hopping Mode (`MultiMonitorMode=hopping`):** Prefer a single floating visor? Switch mode to `hopping` in `config.ini` to let a single terminal pool travel between displays to follow your mouse.
  * **Display Topology Safety:** Automatically detects monitor disconnects and resolution shifts (`WM_DISPLAYCHANGE`), safely migrating any orphaned terminals to your primary display without losing session states.
  * **Cross-Monitor Visor Migration (`Alt + Ctrl + Left / Right`):** Seamlessly relocate or swap your active visor workspace between physical monitors without killing running sessions. Automatically handles spatial left-to-right monitor sorting, work area dimensions, and click-through cyan seam overlays across mixed-DPI displays.
* **Focus-Aware Dismissal (`Win + §`):** Hiding the visor hands keyboard focus back to the window you were using before summoning it, so typing never stays bound to the now-hidden terminal.
* **Smart Dynamic Multi-Pane Tiling (`Alt + Enter`, `Alt + L`):**
  * **1 Terminal:** Top visor (100% width, 40% height) or side half-screen column (50% width, 100% height).
  * **2 Terminals:** 5 flexible modes cycled live via `Alt + L`:
    * `side-by-side-visor`: Top row side-by-side (50% / 50% width, 40% visor height).
    * `side-by-side-full`: 2 full-height columns (50% / 50% width, 100% height).
    * `top-bottom`: 2 full-width rows (100% width, 50% / 50% height horizontal split).
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
* **Auto-Rebalancing & Transitions (`Alt + W` / `Alt + F4`):** Closing any terminal automatically collapses and re-tiles the remaining ones (supported via `Alt + W`, `Alt + F4`, or shell `exit`). Closing a stacked split preserves the remaining terminal on its half-screen column without snapping to full-width visor.
* **Keyboard Pane Navigation (`Alt + Arrows`):** Hop typing focus between splits without touching the mouse, featuring deterministic tie-breaking across asymmetrical master layouts.
* **Window Swapping & Rotation (`Alt + Shift + Arrows`, `Alt + Shift + Space`):** Rearrange panes on the fly by swapping with adjacent windows or rotating all positions cyclically without losing keyboard focus.
* **In-Terminal Startup Help Hint & Cheat Sheet (`quake-help`, `quake-env`):** Displays a sleek 1-line reminder (`💡 Tip: Type 'quake-help' to view keyboard shortcuts`) on every terminal start. Configurable via `ShowHelpOnStart=tip` in `config.ini` (`tip` for sleek 1-line hint, `banner` for full 20-line table, `none` for silent startup). Running `quake-help` displays the full electric cyan quickstart cheat sheet on demand anytime, while `quake-env` inspects your setup (OS, AutoHotkey, Alacritty, displays) and copies formatted Markdown to the clipboard for rapid bug reporting.
* **One-Word Updates (`quake-update`):** `quake-update` checks for a newer release and upgrades a Git clone in place (fast-forward pull + installer), and re-deploys when the clone is already ahead of the installed copy. ZIP installs download the release archive, verify the SHA-256 published in the release notes, and run the extracted installer. `quake-update --check` (`-Check` in PowerShell) reports the version without changing anything.
* **Once-a-Day Update Notice:** When the cached background check has seen a newer published release, terminal startup prints a single line — `⬆ Update available: vX (you have vY). Type 'quake-update'.` — at most once per calendar day. The line comes from the local cache only (no network on launch), `quake-help` shows it while an update is pending, and `QUAKE_SHOW_HELP=none` suppresses startup messages.
* **Taskbar Awareness:** Respects custom work areas (such as left-docked taskbars) using `MonitorGetWorkArea`.

---

## ⌨️ Shortcuts Reference

| Shortcut | Context | Description |
| :--- | :--- | :--- |
| **`Win + §`** | **Global** | Toggle terminal visor (shows on the monitor under the mouse cursor; hiding returns focus to the previous window) |
| **`Alt + Enter`** | Inside Alacritty | Spawn a new split (auto-tiles into 1 → 2 → 3 → 4 layout) |
| **`Alt + W`** / **`Alt + F4`** | Inside Alacritty | Close focused split and smoothly rebalance remaining windows |
| **`Alt + R`** | Inside Alacritty | Force re-tile / balance windows |
| **`Alt + L`** | Inside Alacritty | Cycle pane layout mode / master orientation live |
| **`Alt + Left` / `Right`** | Inside Alacritty | Move active typing focus between left & right panes |
| **`Alt + Up` / `Down`** | Inside Alacritty | Move active typing focus between top & bottom panes |
| **`Alt + Shift + Left` / `Right`** | Inside Alacritty | Swap active pane position with left / right neighbor |
| **`Alt + Shift + Up` / `Down`** | Inside Alacritty | Swap active pane position with top / bottom neighbor |
| **`Alt + Shift + Space`** | Inside Alacritty | Rotate all terminal pane positions cyclically clockwise |
| **`Alt + Ctrl + Left` / `Right`** | Inside Alacritty | Move / swap entire visor workspace across monitors (spatial order) |
| **`Alt + Ctrl + R`** | Inside Alacritty | Instant in-process script reload (development & config refresh) |
| **`Ctrl + Insert`** / **`Ctrl + Shift + C`** | Inside Alacritty | Copy selected text to the clipboard |
| **`Shift + Insert`** / **`Ctrl + Shift + V`** | Inside Alacritty | Paste clipboard contents into the terminal |

---

## 📦 Prerequisites (Optional for Automated Install)

> [!TIP]
> **No dependencies required beforehand!**
> You do **not** need to install any prerequisites before running the automated installer. The setup script (`.\src\install.ps1`) automatically inspects your machine, detects if Alacritty, AutoHotkey v2, or JetBrainsMono Nerd Font are missing, and offers to install them for you via `winget`.
>
> Only run the manual commands below if you prefer installing dependencies yourself or are performing a manual setup (Option B).

If you prefer installing prerequisites manually, run the following in PowerShell:

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

### Option A: Download the Latest Release (Recommended)

No Git, no clone, no developer tools:

1. Open **[Releases](https://github.com/orgNero/quake-alacritty/releases/latest)** and download `quake-alacritty-vX.Y.Z.zip`.
2. Extract the **whole** archive to a folder of your choice (keep every file together).
3. Double-click **`Install.cmd`**. It forwards to `src\install.ps1` with `-ExecutionPolicy Bypass` (process-scoped only) and keeps the window open if something fails.

`Install.cmd` contains no install logic of its own; everything is still owned by `src\install.ps1`, so ZIP installs and clone installs behave identically. To pass flags, run it from a terminal:

```bat
Install.cmd -Shell wsl -KeyboardLayout us -InstallDependencies -CreateStartupShortcut
```

> [!NOTE]
> **Windows may warn about a downloaded ZIP.** Extracted files carry Mark-of-the-Web, so SmartScreen can show "Windows protected your PC" for the launcher. That is expected for an unsigned script; choose **More info → Run anyway**. If your organisation blocks `.cmd` files outright, run PowerShell manually with `-ExecutionPolicy Bypass` as shown below. Do not disable execution policy machine-wide. On a machine with managed endpoint security (SentinelOne, CrowdStrike Falcon, Defender for Endpoint), see the antivirus/EDR quarantine entry under [Troubleshooting](#-troubleshooting) before running the installer.

> [!NOTE]
> **Zero setup required beforehand:** Running the installer works immediately on a fresh Windows 11 machine without needing any pre-installed software—it will automatically detect, prompt for, and install all missing dependencies for you.

> [!NOTE]
> **First install that had to add Alacritty:** Windows only publishes new `PATH` entries to programs started afterwards. The installer refreshes its own environment and launches the visor with it, and the visor also checks the standard Alacritty folders, so the default `winget` install normally works right away. If `Win + §` still reports that Alacritty cannot be found, log out and back in (or restart) once. At sign-in the Startup shortcut relaunches Quake Alacritty automatically; if you skipped it, start `quake_alacritty.ahk` again, then press the shortcut. Re-running the installer after the reboot is **not** needed.

### Option B: From a Git Clone (Development)

```powershell
git clone https://github.com/orgNero/quake-alacritty.git
cd quake-alacritty
```

Run PowerShell from inside the repository folder:

```powershell
# Interactive setup wizard (prompts for shell, keyboard layout, dependencies & startup)
.\src\install.ps1

# If script execution is blocked in your session:
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\install.ps1

# Or run headless / unattended with explicit options:
.\src\install.ps1 -Shell wsl -KeyboardLayout us -InstallDependencies -CreateStartupShortcut
```

The runtime scripts, templates and version markers live in `src/`; only `Install.cmd`, `README.md` and repository metadata stay at the root. The release ZIP mirrors that layout, so the same relative paths work in both places.

The setup wizard guides you through:
1. **Prerequisite Check**: Automatically detects if Alacritty, AutoHotkey v2, or JetBrainsMono Nerd Font are missing and offers to install them via `winget`.
2. **Shell Selection**: Choose your default environment out of the box — **PowerShell**, **WSL (Ubuntu / Linux Bash)**, or **Git Bash**.
3. **Keyboard Layout**: Select **Nordic / Swedish (`Win + §`)** or **US / Standard ANSI (`` `Win + ` `` / `Win + ~`)**.
4. **Startup Integration**: Configures automatic startup with Windows.

#### Upgrading an Existing Install

Re-running `install.ps1` is a safe upgrade, not a reinstall. The script reads `%APPDATA%\alacritty\.install-state.json` (falling back to the deployed script for older installs) and reports `Existing install found (vX) -> upgrading to vY`.

- **Configuration is preserved by default.** `config.ini` is merged by appending only missing sections/keys; existing lines, ordering, comments and custom values are never rewritten. `alacritty.toml` is only patched when you explicitly choose a shell. Every modification is preceded by a timestamped `.bak` backup.
- **Running instances are stopped gracefully.** `install.ps1` and `uninstall.ps1` detect AutoHotkey processes through `Win32_Process.CommandLine`, validate the script path, send `WM_CLOSE` so `OnExit` can destroy seam overlays, and only force-kill after a grace period.
- **Windows "Installed Apps" is updated.** A per-user `HKCU` uninstall entry (version, install location, size, uninstall command) is refreshed on every upgrade and removed by the uninstaller.

| Flag | What it does |
| --- | --- |
| `-ResetConfig` | Deliberately restore factory `config.ini` / `alacritty.toml` (timestamped backups first) |
| `-Shell keep` | Keep the existing `[terminal.shell]` block in headless/CI runs |
| `-KeyboardLayout nordic\|us` | Rebind `ToggleVisor`; omit it to keep your current binding |
| `-UpgradeDependencies` | Print installed vs. winget-available versions, then run `winget upgrade` |
| `-CheckForUpdates` | Advisory check against the newest **published GitHub release** (never downloads or installs) |
| `-DryRun` | Print every planned file write, backup, shortcut, registry key and process action without applying it |
| `-VerifyVersion` | Fail when `VERSION`, the newest `CHANGELOG.md` heading and git tags disagree |
| `-NonInteractive` | Never prompt; use defaults for anything not supplied |
| `-PassThru` | With `-CheckForUpdates`, return a result object instead of relying on text output |

> [!NOTE]
> Re-running without `-Shell` or `-KeyboardLayout` no longer changes an existing shell block or rewrites a user-rebound `ToggleVisor` hotkey.

#### Updating

The installer registers a `quake-update` command in PowerShell and Git Bash:

```powershell
quake-update            # check, then update
quake-update -Check     # PowerShell: report only, change nothing
```

```bash
quake-update            # check, then update
quake-update --check    # Git Bash: report only, change nothing
```

- **Git clone installs** are fast-forwarded with `git pull --ff-only` and then re-deployed by the freshly pulled `install.ps1`. A dirty working tree, a detached HEAD, or a branch without an upstream stops the update with a plain message. Nothing is ever stashed, reset, or discarded automatically. A branch that lost its upstream is re-attached to `origin/<branch>` automatically when that remote-tracking branch exists.
- **"Already on the latest version" means the deployment is current, not just the clone.** If the pull brings no new commits but the clone's `src\VERSION` is newer than the deployed copy — or the deployed copy was installed from a different commit, which is the normal case between releases — `quake-update` re-runs the installer instead of stopping. Re-deploying never touches your `alacritty.toml` or `config.ini`.
- **ZIP installs update themselves.** `quake-update` reads the newest published release, downloads `quake-alacritty-vX.Y.Z.zip` over HTTPS, compares its SHA-256 with the digest in the release notes, extracts it to a temporary folder and runs the extracted `src\install.ps1` (configuration preserved). The temporary folder is removed afterwards, and nothing outside `%APPDATA%\alacritty` is touched.
- **Any failure falls back to the download link.** No connection, a missing asset, a digest mismatch, an archive whose `VERSION` disagrees with the release, or an installer that exits non-zero leaves your current install untouched and prints the manual download link instead of half-applying an update.
- **Watch for the notice:** the once-a-day line (`⬆ Update available: vX (you have vY). Type 'quake-update'.`) is rendered from the cached result of the background check, so it never slows down or blocks a new terminal. It appears at most once per calendar day; `QUAKE_SHOW_HELP=none` hides it along with the startup tip. Run `quake-update` to apply it.
- **The check reads published releases, not `main`.** A tag that has no GitHub release is never advertised, and the 60-requests-per-hour unauthenticated API limit is ample for a once-a-day check. If GitHub cannot be reached, the previous cached result is kept and the check retries later; failures never block terminal startup.
- **Your current shell keeps the old functions** until you open a new terminal pane. The update itself runs a child installer, so the running command is never replaced mid-flight.

Manual fallback: for a clone, `git pull` followed by `.\src\install.ps1`; for a ZIP, download the newer release and run its `Install.cmd`.

### Option C: Manual Setup
1. Copy the runtime files from `src\` (`alacritty.toml`, `quake_alacritty.ahk`, `config.ini`, `welcome.ps1`, `quake_common.ps1`, `update.ps1`, `update-check.ps1`, `uninstall.ps1`, `VERSION`, and `CONFIG_SCHEMA`) to your configuration folder:
   ```
   C:\Users\<YourUsername>\AppData\Roaming\alacritty\
   ```
2. Run `quake_alacritty.ahk` with AutoHotkey v2.
3. Press **`Win + §`** (or **`` `Win + ` ``** on US ANSI) anywhere to summon your terminal!

---

## 🎨 Customization

Quake Alacritty uses a clean separation of concerns:
- **`config.ini`**: Governs wrapper behavior, window dimensions, seam borders, and all hotkey bindings.
- **`alacritty.toml`**: Governs terminal styling, font definitions, opacity, and Windows 11 acrylic blur.

### Configuration File (`config.ini`)
Located at `%APPDATA%\alacritty\config.ini` (or `src\config.ini` in the repository):

```ini
[General]
FirstRun=true
; Multi-monitor visor workspace mode (isolated | hopping)
MultiMonitorMode=isolated
; Help command hint on terminal launch (tip | banner | none)
ShowHelpOnStart=tip
; Default starting directory for newly spawned terminal windows (~ or empty defaults to user profile directory)
StartingDirectory=~

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

; 2-pane split mode (side-by-side-visor | side-by-side-full | top-bottom | left-stacked | right-stacked)
; side-by-side-visor: 2 columns at VisorHeightPercent
; side-by-side-full:  2 columns at 100% work area height
; top-bottom:         2 full-width rows (50%/50% height horizontal split)
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

; Multi-monitor visor migration & swapping
MoveVisorLeft=!^Left
MoveVisorRight=!^Right

; Development in-process reload
ReloadScript=!^r
```

> [!TIP]
> After saving changes in `config.ini`, press **`Alt + Ctrl + R`** while inside Alacritty to instantly reload settings without restarting the terminal!

### Adjusting Opacity & Blur
Edit [`alacritty.toml`](src/alacritty.toml):
```toml
[window]
opacity = 0.70    # 0.0 is completely transparent, 1.0 is solid
blur = true       # Windows 11 Acrylic blur effect
decorations = "None"
```

### Configuring Your Shell (PowerShell, WSL Bash, Git Bash)
Quake Alacritty natively supports any Windows shell inside Alacritty without forcing PowerShell wrappers. You can change your shell anytime in [`alacritty.toml`](src/alacritty.toml):

**WSL Bash (Ubuntu / Linux):**
```toml
[terminal.shell]
program = "wsl.exe"
args = ["~"]
```

**Git Bash (MSYS2):**
```toml
[terminal.shell]
program = "C:\\Program Files\\Git\\bin\\bash.exe"
args = ["--login", "-i"]
```

**PowerShell:**
```toml
[terminal.shell]
program = "powershell.exe"
```

---

## 🗑️ Uninstallation

To cleanly remove Quake Alacritty, run the uninstaller:

```powershell
# From the repository:
.\src\uninstall.ps1

# Or from your AppData installation folder:
powershell -ExecutionPolicy Bypass -File "$env:APPDATA\alacritty\uninstall.ps1"
```

The uninstaller:
- Requests a graceful shutdown of running Quake Alacritty instances (force-kill only as a fallback) so seam overlays are cleaned up.
- Removes the Windows Startup shortcut.
- Removes the per-user "Installed Apps" registry entry (`HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\QuakeAlacritty`).
- Cleans up the `quake-help`, `quake-env` and `quake-update` commands from your PowerShell `$PROFILE` and Git Bash `~/.bashrc`.
- Removes deployed application files and installer artifacts (`.install-state.json`, `.update-check.json`, `.update-notice`, `VERSION`, `CONFIG_SCHEMA`, `quake_common.ps1`, `update.ps1`, `update-check.ps1`) while giving you the option to keep or delete your custom configuration files (`config.ini` and `alacritty.toml`). Choosing to delete the configuration also removes the timestamped `.bak` backups and the now-empty install folder.

---

## 🩺 Troubleshooting

**`Install.cmd` closes immediately or does nothing**
- Extract the **whole** ZIP first; `Install.cmd` refuses to run when `src\install.ps1` is missing.
- Run it from a terminal (or `cmd /k Install.cmd`) so the error stays visible.
- If `.cmd` files are blocked by policy, use PowerShell directly:
  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File .\src\install.ps1
  ```
  `-ExecutionPolicy Bypass` applies to that process only; it does not change machine or user policy.

**SmartScreen or "Windows protected your PC" on a downloaded ZIP**
- Downloaded files carry Mark-of-the-Web. Open **More info → Run anyway**, or right-click the ZIP → **Properties → Unblock** *before* extracting.
- This project ships unsigned scripts only. There is no compiled installer and no certificate to trust.
- On a machine with managed endpoint security (SentinelOne, CrowdStrike Falcon, Defender for Endpoint), also read the quarantine entry below before running anything.

**Antivirus or endpoint security quarantines the ZIP, `Install.cmd` or the visor**
- **The release contains no executable.** It is a `.cmd`, plain-text `.ps1`/`.ahk` files and the default configs. If the archive you downloaded contains an `.exe`, `.dll` or `.scr`, it is not an official release — stop, delete it, and re-download from **[Releases](https://github.com/orgNero/quake-alacritty/releases/latest)**.
- **Verify before you allow it:**
  ```powershell
  Get-FileHash .\quake-alacritty-vX.Y.Z.zip -Algorithm SHA256
  ```
  The expected hash is printed in the release notes of the tag you downloaded. Extract from that verified archive only.
- **`quake-update` performs that check automatically** for ZIP installs: it downloads the archive, compares it with the digest in the release notes, and refuses to extract on a mismatch. If endpoint security blocks the temporary download, the update stops and your current install stays untouched.
- **Heuristic detections are expected**, because everything the installer legitimately does is also what malware does: it runs an unsigned script with `-ExecutionPolicy Bypass`, creates a Startup shortcut and an `HKCU` uninstall entry, rewrites `$PROFILE` and `~/.bashrc`, calls `winget` (installing AutoHotkey, which many engines already flag on its own), and the visor installs a global keyboard hook (`InstallKeybdHook`) and enumerates windows through Win32 calls. Static AI and script engines react to that pattern, not to a specific bad file.
- **Preview instead of trusting:** `.\src\install.ps1 -DryRun` prints every planned file write, shortcut, registry key and profile edit and changes nothing.
- **After reviewing it**, add exclusions for the extracted folder and for `%APPDATA%\alacritty`, or submit a false-positive report to your vendor with the SHA-256 above.
- **On a managed machine**, enterprise EDR can respond to a detection by cutting the endpoint's network access (SentinelOne's "disconnect from network" / containment, leaving only the management console reachable). That is the security agent, not Quake Alacritty, and a local user usually cannot lift it — ask IT to reconnect the endpoint. Ask them for the detection name and the engine (static vs. behavioural) as well.
- **Recovering from a quarantine:** removing the files does not undo what the installer already did. Run `%APPDATA%\alacritty\uninstall.ps1` if it survived; otherwise remove `%APPDATA%\alacritty`, the `quake_alacritty.lnk` shortcut in `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup`, the `HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\QuakeAlacritty` key, and the `# >>> Quake Alacritty >>>` … `# <<< Quake Alacritty <<<` block in `$PROFILE` and `~/.bashrc`.

**`quake-update` says "Could not update from GitHub"**
- Check the connection and retry. Dirty trees, detached HEADs, missing upstreams and missing Git are intentionally stop states; nothing is stashed or reset for you.
- A branch without an upstream is re-attached to `origin/<branch>` automatically when that remote-tracking branch exists, so this error should not come back on its own.
- The current shell keeps its old functions until a new pane is opened.

**`quake-update` downloaded a release but did not install it**
- It prints the reason and leaves your current version deployed. A digest mismatch, a release without an archive, an archive whose `VERSION` disagrees with the release, and a non-zero installer exit all abort before anything is written.
- Antivirus or EDR can block the archive in `%TEMP%`; see the quarantine entry above. The manual download link is always printed as the fallback.

**`quake-update` cannot fast-forward after upgrading to v0.13.1**
- v0.13.1 rewrote the repository history to remove files that should never have been published, so clones made before it share no common commit with `main` and `git pull --ff-only` refuses to continue. Re-clone once, then redeploy:
  ```bash
  git clone https://github.com/orgNero/quake-alacritty.git
  cd quake-alacritty
  pwsh -File .\src\install.ps1
  ```
  Your `config.ini` and `alacritty.toml` in `%APPDATA%\alacritty` are preserved.

**`-CheckForUpdates` reports "No published release found yet."**
- That is expected before the first GitHub release exists. Tags alone are not advertised; only a published release is.

**The update notice does not appear**
- The check runs at most once a day after a success (once an hour after a failure) and is triggered when the visor starts or is toggled. Give it a moment, then open a new pane.
- `QUAKE_SHOW_HELP=none` suppresses the notice together with the startup tip. `quake-help` still shows a pending update without consuming the daily marker.

**The first `Win + §` says Alacritty cannot be found**
- This only affects the session in which the installer itself installed Alacritty: the already-running installer and its AutoHotkey child keep the `PATH` they inherited before Alacritty existed. The installer now refreshes `PATH` from the registry and the visor also checks `%LOCALAPPDATA%\Programs\Alacritty` and `%ProgramFiles%\Alacritty`, so a default `winget` install normally opens on the first press.
- If it still cannot find the executable, log out or restart Windows once so the updated `PATH` reaches every process. Start Quake Alacritty again at sign-in (the Startup shortcut does this automatically; otherwise launch `quake_alacritty.ahk`), then press the shortcut again. **Do not re-run the installer**; nothing else needs to change.
- Alacritty in a custom or portable folder? Add the optional override under `[General]` in `%APPDATA%\alacritty\config.ini`, then reload with `Alt + Ctrl + R`:
  ```ini
  [General]
  AlacrittyPath=C:\full\path\to\alacritty.exe
  ```
  This key is not part of the default template, so leaving it out keeps the normal resolution order (`PATH` → `%LOCALAPPDATA%\Programs\Alacritty` → `%ProgramFiles%\Alacritty`).

---

## 🔖 Version Metadata

- **`VERSION`** — one-line semantic version of the app, deployed to `%APPDATA%\alacritty\VERSION`. Published versions are listed on **[Releases](https://github.com/orgNero/quake-alacritty/releases)**.
- **`CONFIG_SCHEMA`** — one-line integer that is bumped when `config.ini` keys are renamed or removed.
- **`%APPDATA%\alacritty\.install-state.json`** — machine state written on every deploy (`version`, `configSchema`, `gitCommit`, `installedAt`, `updatedAt`, `shell`, `layout`, `targetDir`, `sourceType`, `sourceDir`). It is informational only; `VERSION`/`CONFIG_SCHEMA` remain the source of truth. `sourceType` records whether the install came from a `repo` clone or a `zip` archive, and `sourceDir` is the clone path used by `quake-update`.
- **`%APPDATA%\alacritty\.update-check.json`** — cached result of the throttled background update check (`installedVersion`, `latestVersion`, `checkedAtUtc`, `nextCheckAtUtc`, `lastError`). Read by the terminal notice; never used as a version source of truth.
- **`%APPDATA%\alacritty\.update-notice`** — the local date (`yyyyMMdd`) of the last automatic update notice, so it shows at most once per day. Written only by the startup path.
- The AutoHotkey tray tooltip/menu and the `quake-help` cheat sheet read `VERSION` at runtime instead of embedding constants.
- Run `.\src\install.ps1 -VerifyVersion` to assert that `VERSION` and the newest `CHANGELOG.md` heading agree (and the nearest git tag, once tags exist).

---

## 💬 Feedback & Issues

Have an idea for a new feature, workflow improvement, or encountered a bug?

- 🐛 **Report a Bug**: [Open Bug Report](https://github.com/orgNero/quake-alacritty/issues/new?template=bug_report.md)
  > 💡 *Quick Tip*: Run `quake-env` in your terminal to automatically capture your Windows build, monitor resolution, and software versions directly to your clipboard before filing!
- 💡 **Request a Feature**: [Open Feature Request](https://github.com/orgNero/quake-alacritty/issues/new?template=feature_request.md)
- 📋 **All Issues & Discussions**: [Browse GitHub Issues](https://github.com/orgNero/quake-alacritty/issues)

---

## 📄 License
MIT License. Feel free to use, modify, and share!
