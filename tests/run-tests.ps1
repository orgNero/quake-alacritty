[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$modulePath = if ($env:QUAKE_PSMODULES) {
    $env:QUAKE_PSMODULES
} else {
    Join-Path $env:LOCALAPPDATA 'quake-alacritty\psmodules'
}

$env:PSModulePath = "$modulePath;$env:PSModulePath"

Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop

$testFiles = @(Get-ChildItem -Path $PSScriptRoot -Filter '*.Tests.ps1' |
    Select-Object -ExpandProperty FullName)

$result = Invoke-Pester -Path $testFiles -Output Detailed -PassThru

$passed = if ($null -ne $result.PassedCount) { $result.PassedCount } else { 0 }
$failed = if ($null -ne $result.FailedCount) { $result.FailedCount } else { 0 }
$skipped = if ($null -ne $result.SkippedCount) { $result.SkippedCount } else { 0 }

Write-Output "PASSED=$passed FAILED=$failed SKIPPED=$skipped"

if ($failed -eq 0 -and $skipped -eq 0 -and $passed -ge 12) {
    exit 0
} else {
    exit 1
}
