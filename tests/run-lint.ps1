[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$modulePath = if ($env:QUAKE_PSMODULES) {
    $env:QUAKE_PSMODULES
} else {
    Join-Path $env:LOCALAPPDATA 'quake-alacritty\psmodules'
}

$env:PSModulePath = "$modulePath;$env:PSModulePath"

Import-Module PSScriptAnalyzer -ErrorAction Stop

$repoRoot = Split-Path $PSScriptRoot -Parent
$srcPath = Join-Path $repoRoot 'src'
$settingsPath = Join-Path $PSScriptRoot 'PSScriptAnalyzerSettings.psd1'

$findings = @(Invoke-ScriptAnalyzer -Path $srcPath -Recurse -Settings $settingsPath)

foreach ($finding in $findings) {
    Write-Output "$($finding.Severity)|$($finding.RuleName)|$($finding.ScriptName):$($finding.Line)|$($finding.Message)"
}

Write-Output "LINT_FINDINGS=$($findings.Count)"

if ($findings.Count -gt 0) {
    exit 1
}
exit 0
