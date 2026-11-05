[CmdletBinding()]
param(
    [string]$Destination = (Join-Path $env:LOCALAPPDATA 'quake-alacritty\psmodules')
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (-not (Test-Path $Destination)) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
}

$hasPester = $false
$pesterDir = Join-Path $Destination 'Pester'
if (Test-Path $pesterDir) {
    $subdirs = Get-ChildItem -Directory -Path $pesterDir -ErrorAction SilentlyContinue
    foreach ($d in $subdirs) {
        try {
            $ver = [version]$d.Name
            if ($ver.Major -ge 5 -and $ver.Major -lt 6) {
                $hasPester = $true
                break
            }
        } catch {
        }
    }
}

$pssaDir = Join-Path $Destination 'PSScriptAnalyzer'
$hasPssa = $false
if (Test-Path $pssaDir) {
    $subdirs = Get-ChildItem -Directory -Path $pssaDir -ErrorAction SilentlyContinue
    if ($subdirs.Count -gt 0) {
        $hasPssa = $true
    }
}

if (-not $hasPester -or -not $hasPssa) {
    $nuget = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
    if (-not $nuget) {
        Install-PackageProvider -Name NuGet -Force -Scope CurrentUser | Out-Null
    }

    if (-not $hasPester) {
        Save-Module -Name Pester -MinimumVersion 5.0 -MaximumVersion 5.99.99 -Path $Destination -Force -Repository PSGallery
    }

    if (-not $hasPssa) {
        Save-Module -Name PSScriptAnalyzer -Path $Destination -Force -Repository PSGallery
    }
}

if (-not (Test-Path $pesterDir) -or -not (Test-Path $pssaDir)) {
    Write-Error "Failed to install required test dependencies in $Destination"
    exit 1
}

Write-Output "TEST_DEPS=$Destination"
