# Quake Alacritty Test Suite

Automated verification harness for Quake Alacritty PowerShell modules and tools.

## What is Covered

- **PSScriptAnalyzer Linting**: Validates `src/*.ps1` against syntax parse errors and script analyzer error rules defined in `tests/PSScriptAnalyzerSettings.psd1`.
- **QuakeCommon Pester Suite**: Tests shared helper logic in `src/quake_common.ps1` (`Merge-QuakeIniContent`, `Compare-QuakeVersion`, install state read/write, version/schema discovery, and executable probing).

## How to Run from Linux (WSL Interop)

Per DEC-03, tests run via Windows PowerShell 5.1 from Linux using WSL interop:

```bash
PS=/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe

# 1. Install or update dependencies (Pester 5, PSScriptAnalyzer)
"$PS" -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w tests/install-test-deps.ps1)" < /dev/null

# 2. Run static analysis / linting
"$PS" -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w tests/run-lint.ps1)" < /dev/null

# 3. Run Pester unit tests
"$PS" -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w tests/run-tests.ps1)" < /dev/null
```

## How to Run on Windows

Open Windows PowerShell 5.1 in the repository root:

```powershell
# 1. Install dependencies into %LOCALAPPDATA%\quake-alacritty\psmodules
.\tests\install-test-deps.ps1

# 2. Run linter
.\tests\run-lint.ps1

# 3. Run Pester test suite
.\tests\run-tests.ps1
```

## Manual Matrix Pointer

Interactive smoke checks and manual multi-monitor / UI verification procedures are tracked in the Obsidian vault note:
`projects/quake-alacritty/docs/quake-alacritty - pre-release verification 2026-10-28.md` (and the release smoke checklist in `quake-alacritty - backlog.md`). The repository ships no test docs folder.

## Packaging Boundary

The `tests/` directory is repository-only. Tests and test runners are never shipped in the release ZIP artifact.
