# Quake Alacritty - Agent Guidelines & Project Context

Please see [GEMINI.md](file:///C:/Users/maxve/repos/quake-alacritty/GEMINI.md) for full project context, architecture, backlog location in the Obsidian vault, and critical evaluation rules.

## Quick Summary
- **Backlog Note**: `C:\Users\maxve\Documents\obsidian_global\projects\quake-alacritty\docs\quake-alacritty - backlog.md`
- **Backlog Rules**:
  1. Deduplicate against existing backlog items, docs, and codebase before adding.
  2. Question and pressure-test feasibility, Windows/AHK OS friction, and usability before accepting features.
  3. Format entries with `- [ ] **<Feature Name>**` and update note metadata.
- **In-Repo Changelog (`CHANGELOG.md`)**:
  - Update `CHANGELOG.md` upon every merge from a branch into `main` using standard headers (`## Features` [Major/Minor], `## Fixes` [Major/Minor], plus repo-specific headers like `## Window Management & Multi-Monitor`, `## Styling & Appearance`, `## Configuration & Tooling`).
- **In-Repo Documentation Parity (`README.md`)**:
  - Always keep in-repo documentation (primarily `README.md`, shortcut cheat sheets, setup guides) strictly up to date with newly added, modified, or removed features before merging any branch into `main`.
- **Known Bugs & Gotchas (`docs/BUGS_AND_GOTCHAS.md`)**:
  - Always consult `docs/BUGS_AND_GOTCHAS.md` before refactoring window enumeration (`GetAlacrittyWindows`), Z-order tracking, coordinate math, or DPI scaling.
