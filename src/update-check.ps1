[CmdletBinding()]
param(
    [int]$TimeoutSeconds = 3,
    [switch]$Force,
    [string]$Url = "https://api.github.com/repos/orgNero/quake-alacritty/releases/latest"
)

<#
.SYNOPSIS
    Advisory-only background update check that writes a local cache file.

.DESCRIPTION
    Compares the installed version in %APPDATA%\alacritty\VERSION with the
    published version and records the result in
    %APPDATA%\alacritty\.update-check.json. Never downloads, extracts, installs
    or executes anything, never shows a dialog, and stays silent unless stderr
    is observed. Normal runs are throttled by nextCheckAtUtc: +24 h after a
    successful check, +1 h after a failure.

.PARAMETER TimeoutSeconds
    HTTP timeout for the version request (default 3).

.PARAMETER Force
    Ignore the cache throttle and perform a fresh check.

.PARAMETER Url
    Version endpoint (override for testing).
#>

$ErrorActionPreference = "Stop"

$commonPath = Join-Path $PSScriptRoot "quake_common.ps1"
if (Test-Path $commonPath) {
    . $commonPath
} else {
    [Console]::Error.WriteLine("quake_common.ps1 was not found next to update-check.ps1. Reinstall Quake Alacritty.")
    exit 1
}

$targetDir = Get-QuakeTargetDir
$cachePath = Join-Path $targetDir ".update-check.json"

function Read-QuakeUpdateCache {
    param([string]$Path)

    if (-not (Test-Path $Path)) { return $null }
    try {
        $raw = Get-Content -Path $Path -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ($raw | ConvertFrom-Json -ErrorAction Stop)
    } catch {
        return $null
    }
}

function Write-QuakeUpdateCache {
    param(
        [object]$Existing,
        [string]$InstalledVersion,
        [string]$LatestVersion,
        [string]$CheckedAtUtc,
        [string]$NextCheckAtUtc,
        [object]$LastError
    )

    $known = @('schema', 'installedVersion', 'latestVersion', 'checkedAtUtc', 'nextCheckAtUtc', 'lastError')
    $state = [ordered]@{
        schema           = 1
        installedVersion = $InstalledVersion
        latestVersion    = $LatestVersion
        checkedAtUtc     = $CheckedAtUtc
        nextCheckAtUtc   = $NextCheckAtUtc
        lastError        = $LastError
    }

    # Preserve fields added by later versions instead of clobbering them.
    if ($null -ne $Existing) {
        foreach ($property in @($Existing.PSObject.Properties)) {
            if ($known -notcontains $property.Name) {
                $state[$property.Name] = $property.Value
            }
        }
    }

    if (-not (Test-Path $targetDir)) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    $json = $state | ConvertTo-Json -Depth 4
    $tempPath = Join-Path $targetDir (".update-check." + [guid]::NewGuid().ToString("N") + ".tmp")
    [System.IO.File]::WriteAllText($tempPath, $json, (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -Path $tempPath -Destination $cachePath -Force
}

$nowUtc = (Get-Date).ToUniversalTime()
$nowStamp = $nowUtc.ToString("yyyyMMddHHmmss")
$existing = Read-QuakeUpdateCache -Path $cachePath

if (-not $Force -and $null -ne $existing) {
    $cachedNextCheck = [string]$existing.nextCheckAtUtc
    if ($cachedNextCheck -match '^\d{14}$' -and $cachedNextCheck -gt $nowStamp) {
        exit 0
    }
}

$installedVersion = Get-QuakeVersionFromDir -Directory $targetDir
$check = Invoke-QuakeUpdateCheck -InstalledVersion $installedVersion -TimeoutSeconds $TimeoutSeconds -Url $Url

if ($check.Error) {
    $lastError = [string]$check.Error
    if ($lastError.Length -gt 500) { $lastError = $lastError.Substring(0, 500) }

    $previousLatest = $null
    if ($null -ne $existing -and -not [string]::IsNullOrWhiteSpace([string]$existing.latestVersion)) {
        $previousLatest = [string]$existing.latestVersion
    }

    try {
        Write-QuakeUpdateCache -Existing $existing -InstalledVersion $installedVersion -LatestVersion $previousLatest `
            -CheckedAtUtc $nowStamp -NextCheckAtUtc $nowUtc.AddHours(1).ToString("yyyyMMddHHmmss") -LastError $lastError
    } catch {
        [Console]::Error.WriteLine("Could not write update check cache: $($_.Exception.Message)")
    }

    [Console]::Error.WriteLine("Update check failed: $lastError")
    exit 1
}

try {
    Write-QuakeUpdateCache -Existing $existing -InstalledVersion $installedVersion -LatestVersion $check.AvailableVersion `
        -CheckedAtUtc $nowStamp -NextCheckAtUtc $nowUtc.AddHours(24).ToString("yyyyMMddHHmmss") -LastError $null
} catch {
    [Console]::Error.WriteLine("Could not write update check cache: $($_.Exception.Message)")
    exit 1
}

exit 0
