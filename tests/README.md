# Quake Alacritty Test Suite

Automated verification harness for Quake Alacritty PowerShell modules and tools.

## What is Covered

- **PSScriptAnalyzer Linting**: Validates `src/*.ps1` against syntax parse errors and script analyzer error rules defined in `tests/PSScriptAnalyzerSettings.psd1`.
- **Pester Unit Tests**:
  - `tests/QuakeCommon.Tests.ps1`: Tests shared helper logic in `src/quake_common.ps1` (`Merge-QuakeIniContent`, `Compare-QuakeVersion`, install state read/write, version/schema discovery, and executable probing).
  - `tests/Digest.Tests.ps1`: Tests release notes SHA-256 digest parsing in `Get-QuakeArchiveDigestFromNotes` (`ok`, `missing`, `malformed` states).
- **AutoHotkey v2 Self-Test (`--selftest`)**: Validates `src/quake_alacritty.ahk` startup, configuration parsing (`--selftest-config <path>`), hotkey bindings, shell resolution, monitor detection, and `WSLENV` merging non-interactively without side effects.
- **Workflow & Packaging Checks**: Validates GitHub Actions SHA pins and packaging boundaries (`tests/run-workflow-checks.ps1`).

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

# 4. Run AutoHotkey v2 self-test
"$PS" -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w tests/run-selftest.ps1)" -ConfigPath "$(wslpath -w src/config.ini)" < /dev/null

# 5. Run workflow checks
"$PS" -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w tests/run-workflow-checks.ps1)" < /dev/null
```

You can also run the AutoHotkey self-test directly:

```bash
AHK="/mnt/c/Users/maxve/AppData/Local/Programs/AutoHotkey/v2/AutoHotkey64.exe"
"$AHK" /ErrorStdOut "$(wslpath -w src/quake_alacritty.ahk)" --selftest --selftest-config "$(wslpath -w src/config.ini)"
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

# 4. Run AutoHotkey v2 self-test
.\tests\run-selftest.ps1 -ConfigPath .\src\config.ini

# 5. Run workflow checks
.\tests\run-workflow-checks.ps1
```

Or run AutoHotkey directly with `--selftest`:

```powershell
& 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe' /ErrorStdOut src\quake_alacritty.ahk --selftest --selftest-config src\config.ini
```

## Manual Matrix Pointer

Interactive smoke checks and manual multi-monitor / UI verification procedures are tracked in the Obsidian vault note:
`projects/quake-alacritty/docs/quake-alacritty - pre-release verification 2026-10-28.md` (and the release smoke checklist in `quake-alacritty - backlog.md`). The repository ships no test docs folder.

## Packaging Boundary

The `tests/` directory is repository-only. Tests and test runners are never shipped in the release ZIP artifact.
