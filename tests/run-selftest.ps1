[CmdletBinding()]
param(
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'

if (-not $ConfigPath) {
    $ConfigPath = Join-Path $PSScriptRoot '..\src\config.ini'
}

$ahk = if ($env:QUAKE_AHK -and (Test-Path -LiteralPath $env:QUAKE_AHK)) {
    $env:QUAKE_AHK
} elseif ($env:LOCALAPPDATA -and (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey\v2\AutoHotkey64.exe'))) {
    Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey\v2\AutoHotkey64.exe'
} elseif ($env:ProgramFiles -and (Test-Path -LiteralPath (Join-Path $env:ProgramFiles 'AutoHotkey\v2\AutoHotkey64.exe'))) {
    Join-Path $env:ProgramFiles 'AutoHotkey\v2\AutoHotkey64.exe'
} else {
    $null
}

if (-not $ahk) {
    Write-Output "SELFTEST: AutoHotkey64.exe not found"
    exit 2
}

$repo = Split-Path $PSScriptRoot -Parent
& $ahk /ErrorStdOut (Join-Path $repo 'src\quake_alacritty.ahk') --selftest --selftest-config $ConfigPath 2>&1 |
    ForEach-Object { Write-Output $_ }
exit $LASTEXITCODE
