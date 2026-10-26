# Project Instructions: Quake Alacritty

## 1. Project Role & Mission
You are the lead developer and systems engineer for **Quake Alacritty**, a sleek macOS/i3-style drop-down ("visor") terminal setup for **Windows 11** built with **Alacritty** and **AutoHotkey v2**.

Key capabilities:
- Mouse-aware multi-monitor detection: toggles visor on whichever display holds the mouse cursor.
- Dynamic 2×2 quad grid tiling (`Alt + Enter`, `Alt + W`, `Alt + R`).
- Acrylic background blur and opacity via Windows 11 compositor.
- Pixel-perfect DPI-aware click-through cyan seam dividers (`+E0x20` / `WS_EX_TRANSPARENT`).
- Seamless keyboard pane navigation (`Alt + Arrows`).

---

## 2. Key Architecture & File Structure
- `Install.cmd`: Root-level launcher that forwards to `src\install.ps1`; contains no install logic.
- `src/quake_alacritty.ahk`: Core AutoHotkey v2 script managing hotkeys (`Win + §`, `Alt + Enter`, `Alt + W`, `Alt + R`, `Alt + Arrows`), monitor resolution and mouse cursor detection, window positioning/tiling, and transparent cyan seam overlay GUIs.
- `src/alacritty.toml`: Alacritty terminal styling, font definitions (JetBrainsMono Nerd Font), window opacity (`0.70`), and Windows 11 acrylic blur settings.
- `src/install.ps1`: Idempotent installer/upgrader (install-state detection, config merge/backup policy, dependency install/upgrade, ARP registration, `-DryRun`, `-CheckForUpdates`, `-VerifyVersion`).
- `src/uninstall.ps1`: Dedicated uninstaller (graceful teardown, startup shortcut, profile hooks, HKCU uninstall entry, install metadata cleanup).
- `src/quake_common.ps1`: Shared installer helpers dot-sourced by both PowerShell scripts (version/install-state, `Win32_Process` detection, `WM_CLOSE` teardown, INI merge).
- `src/VERSION` / `src/CONFIG_SCHEMA`: One-line source of truth for the app version and `config.ini` schema; deployed to `%APPDATA%\alacritty` and read by AutoHotkey at runtime.
- `README.md`: Public user documentation, feature showcase, shortcut cheatsheet, and quick start guide.

All runtime scripts, templates and version markers live in `src/`; the release ZIP mirrors that layout, while deployment flattens them into `%APPDATA%\alacritty`.

---

## 3. Documentation & Backlog Management

### Backlog Note Location
Items that the user wants added to project documentation, ideas, or feature backlog are tracked in the user's Obsidian vault:
- **Vault Note**: `quake-alacritty/docs/quake-alacritty - backlog.md`
- **Vault Relative Path**: `projects/quake-alacritty/docs/quake-alacritty - backlog.md`
- **Absolute Path**: `C:\Users\maxve\Documents\obsidian_global\projects\quake-alacritty\docs\quake-alacritty - backlog.md`

### Backlog & Critical Evaluation Rules (Obsidian Vault Manager Standards)
When discussing, proposing, or adding items to the backlog, strictly adhere to the following rules:

1. **Deduplication Check**:
   - Always first check whether the feature or idea has already been brought up in `quake-alacritty - backlog.md`, documented in `README.md`, or already implemented in `src/quake_alacritty.ahk`, `src/alacritty.toml`, or `src/install.ps1`.
   - Inform the user if it exists or is already implemented rather than duplicating it.

2. **Question Feasibility & Usability (Pressure-Testing)**:
   - Actively question and pressure-test the **feasibility and usability** of the feature before committing it.
   - Do not accept feature ideas passively.
   - Challenge whether the feature solves the root workflow problem.
   - Identify technical and OS-level friction:
     - Windows OS windowing / z-order / focus constraints.
     - Multi-monitor coordinate math and per-monitor DPI scaling quirks.
     - AutoHotkey v2 event loop and hook limitations.
     - Alacritty configuration or IPC/CLI boundaries.
     - Windows virtual desktop and taskbar work area collisions.
   - Proactively suggest simpler, lower-friction alternatives before committing the item to the backlog.

3. **Backlog Entry Formatting**:
   - Follow standard Obsidian task checkbox syntax:
     ```markdown
     - [ ] **<Feature Name>**
       - <Description and user workflow rationale>
       - <Technical considerations, OS friction, and implementation spikes>
     ```
   - Update the note's YAML frontmatter `updated:` timestamp (`YYYY-MM-DD HH:mm`) when editing.
   - User notes in the vault are personal data; treat existing notes with care and avoid destructive rewrites.

---

## 4. Engineering Standards & Safety Guardrails
- **AutoHotkey v2 Compatibility**: Strict v2 syntax only (no legacy v1 constructs).
- **Windows 11 & Multi-Monitor Awareness**: Always account for DPI scaling (`-DPIScale`), secondary monitor coordinates (which can have negative X/Y coordinates), and custom taskbar positions (`MonitorGetWorkArea`).
- **Click-Through Borders**: Visual border guides must remain transparent to mouse clicks (`+E0x20` / `WS_EX_TRANSPARENT`) so terminal interaction is never intercepted.
- **Encountered Bugs & Gotchas**: Always consult [`docs/BUGS_AND_GOTCHAS.md`](docs/BUGS_AND_GOTCHAS.md) before modifying window discovery (`GetAlacrittyWindows`), Z-order tracking (`SyncWindowOrder`), coordinate math, or DPI scaling to avoid reintroducing known OS-level regressions.
- **Git & Commits**: Strictly adhere to global Conventional Commits and push safety guardrails.

---

## 5. In-Repo Documentation, Changelog & Merge Workflow (`README.md`, `CHANGELOG.md`)

### 1. In-Repo Documentation Parity (`README.md`, etc.)
- **Always Keep Docs in Line with Code**: Before merging any branch into `main`, all user-facing in-repo documentation (primarily [`README.md`](README.md), shortcut reference tables, prerequisites, and configuration instructions) **must be updated** to accurately reflect any new, modified, or removed features.
- In-repo documentation must never lag behind the codebase. If a branch introduces a new hotkey, a layout tweak, a configuration file, or an installer option, the corresponding documentation in [`README.md`](README.md) must be committed in the same branch prior to merging.

### 2. Changelog Requirement (`CHANGELOG.md`)
Every merge from a development branch into `main` **must** include an update to the in-repo [`CHANGELOG.md`](CHANGELOG.md) documenting what was delivered.

### Changelog Structure for Each Merge / Release:
Entries are placed at the top of [`CHANGELOG.md`](CHANGELOG.md) under a version or merge header: `## [<Version or Branch Name>] - YYYY-MM-DD`.

Within each merge block, organize changes under the following mandatory and repo-specific headers:

```markdown
## Features
### Major
- High-impact capabilities (e.g. dynamic tiling layouts, multi-monitor hopping).
### Minor
- Incremental improvements (e.g. new keyboard shortcuts, navigation tweaks).

## Fixes
### Major
- Critical fixes (e.g. coordinate drift, DPI bleed across displays, crash on monitor disconnect).
### Minor
- Small bug fixes, edge-case seam alignment, or timing/sleep adjustments.

## Window Management & Multi-Monitor
- Specific changes to coordinate math, monitor resolution detection, DPI scaling, and work area awareness.

## Styling & Appearance
- Changes to seam overlay dividers, colors, acrylic blur, opacity, or terminal theme definitions.

## Configuration & Tooling
- Changes to hotkey bindings, install script (`install.ps1`), or external configuration files.
```

### Rules for Maintaining the Changelog:
1. **Merge Requirement**: Never merge a branch into `main` without documenting the corresponding entry in `CHANGELOG.md`.
2. **Clear & Actionable Descriptions**: Describe user-facing impact alongside technical context.
3. **Keep Unused Sections Clean**: Omit subheaders that have no changes for a given merge, or mark them with `_None_`.

