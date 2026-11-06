# Security Policy

## Supported versions

Only the latest published release receives bug fixes and security updates. Older releases are supported only when a published regression in an active release is being hotfixed.

## Trust model

The SHA-256 digest published in GitHub release notes verifies transport integrity and protects against tampering between the release build and archive download. It does not protect against a compromised GitHub repository or maintainer account, which would control both the release archive and the release notes.

The project ships unsigned scripts only (`.ps1`, `.ahk`, `.cmd`, `.toml`, `.ini`). It does not use compiled binaries or code signing certificates, and there are currently no plans for code signing.

## What the installer touches

The installer (`install.ps1`) and runtime modify only user-scope files and configurations:
- `%APPDATA%\alacritty\` — the deployment directory holding configuration, AutoHotkey runtime scripts, helper scripts, and state.
- `.install-state.json` — recorded inside `%APPDATA%\alacritty\` to track the deployed version, schema, and source.
- `HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\QuakeAlacritty` — user-level registry entry for Windows Add/Remove Programs.
- The Windows Startup shortcut (`quake_alacritty.lnk` in `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup`).
- User shell profile hooks in `$PROFILE` (PowerShell) and `~/.bashrc` (Git Bash).
- `winget` — invoked during install to satisfy missing runtime dependencies (such as AutoHotkey or Alacritty).
- Global keyboard hook — the AutoHotkey visor runtime installs a low-level keyboard hook (`InstallKeybdHook`) to handle visor toggle and navigation shortcuts.

## Install lifecycle

`quake-update` validates release integrity before installing:
- Downloads the release archive to a temporary directory.
- Reads the SHA-256 digest published in the GitHub release notes.
- If the release notes carry no SHA-256 digest (`missing`) or a malformed digest (`malformed`), `quake-update` refuses to extract or install and exits non-zero.
- If the digest matches, it extracts the archive and runs the installer to complete the update.

Releases must always carry a valid SHA-256 digest in their release notes. A hand-run or automated release published without a valid SHA-256 digest is considered a maintainer error.

## Reporting a vulnerability

To report a security vulnerability, please submit a GitHub Private Security Advisory at:
https://github.com/orgNero/quake-alacritty/security/advisories/new

This project is maintained on a best-effort basis without a guaranteed response-time service-level agreement (SLA).

## Build provenance

The release workflow publishes a build provenance attestation for the ZIP. Verify it with:

```bash
gh attestation verify quake-alacritty-vX.Y.Z.zip --repo orgNero/quake-alacritty
```

It proves which workflow and commit built the artifact, not that the source is safe.
