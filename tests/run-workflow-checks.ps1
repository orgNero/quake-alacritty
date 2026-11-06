[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repo = Split-Path $PSScriptRoot -Parent
$workflowsDir = Join-Path $repo '.github\workflows'

if (-not (Test-Path -LiteralPath $workflowsDir)) {
    Write-Output "WORKFLOW_CHECK_FAIL: workflows directory missing: $workflowsDir"
    exit 1
}

$workflowFiles = @(Get-ChildItem -Path $workflowsDir -Filter '*.yml' -File | Sort-Object Name)
if ($workflowFiles.Count -eq 0) {
    Write-Output "WORKFLOW_CHECK_FAIL: no *.yml workflows found in $workflowsDir"
    exit 1
}

$failures = [System.Collections.Generic.List[string]]::new()

$pinRefRegex = '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@[0-9a-f]{40}$'
$commentRegex = '#\s*v\d+(\.\d+(\.\d+)?)?\b'

foreach ($file in $workflowFiles) {
    $lines = Get-Content -LiteralPath $file.FullName
    $lineNum = 0
    foreach ($line in $lines) {
        $lineNum++
        if ($line -match '^\s*(?:-\s*)?uses:\s*(\S+)') {
            $ref = $matches[1]
            $refMatches = $ref -match $pinRefRegex
            $hasComment = $line -match $commentRegex
            if (-not ($refMatches -and $hasComment)) {
                $failures.Add("WORKFLOW_PIN_FAIL $($file.Name):$lineNum $ref")
            }
        }
    }
}

$releasePath = Join-Path $workflowsDir 'release.yml'
if (-not (Test-Path -LiteralPath $releasePath)) {
    $failures.Add("WORKFLOW_CHECK_FAIL: release.yml not found")
} else {
    $releaseContent = Get-Content -LiteralPath $releasePath -Raw

    if ($releaseContent -notmatch 'actions/attest-build-provenance@4d101475d8b20a2381f78447822ac1eab6504dd8') {
        $failures.Add("WORKFLOW_CHECK_FAIL: release.yml missing actions/attest-build-provenance@4d101475d8b20a2381f78447822ac1eab6504dd8")
    }

    $sourceFilesMatch = [regex]::Match($releaseContent, '(?ms)\$sourceFiles\s*=\s*@\((.*?)\)')
    if (-not $sourceFilesMatch.Success -or $sourceFilesMatch.Groups[1].Value -notmatch "'quake_alacritty\.ahk'") {
        $failures.Add("WORKFLOW_CHECK_FAIL: release.yml `$sourceFiles must contain 'quake_alacritty.ahk'")
    }

    $rootFilesMatch = [regex]::Match($releaseContent, '(?ms)\$rootFiles\s*=\s*@\((.*?)\)')
    if ($rootFilesMatch.Success -and $rootFilesMatch.Groups[1].Value -match 'tests') {
        $failures.Add("WORKFLOW_CHECK_FAIL: release.yml `$rootFiles must not contain 'tests'")
    }
    if ($sourceFilesMatch.Success -and $sourceFilesMatch.Groups[1].Value -match 'tests') {
        $failures.Add("WORKFLOW_CHECK_FAIL: release.yml `$sourceFiles must not contain 'tests'")
    }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Output $failure
    }
    exit 1
}

Write-Output "WORKFLOW_CHECKS_OK"
exit 0
