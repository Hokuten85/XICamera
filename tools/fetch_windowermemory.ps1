# =============================================================================
#  fetch_windowermemory.ps1
#
#  Downloads the WindowerMemory release pinned in windowermemory.json and checks
#  the DLL against the pinned SHA-256. Files are cached in
#  build\windowermemory\<version>\ and reused while the hash still matches:
#
#     _WindowerMemory.dll   the DLL the Windower 4 bundle ships in libs\
#     LICENSE.txt           WindowerMemory's license, shipped next to it
#
#  Prints the cache folder. To move to a new WindowerMemory release, change the
#  version and the sha256 (from that release's SHA256SUMS.txt) together.
#
#  Usage:
#      pwsh -File tools\fetch_windowermemory.ps1
# =============================================================================

param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..'))
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$pin = Get-Content (Join-Path $RepoRoot 'windowermemory.json') -Raw | ConvertFrom-Json
$cache = Join-Path $RepoRoot "build\windowermemory\$($pin.version)"
$dll = Join-Path $cache '_WindowerMemory.dll'
$license = Join-Path $cache 'LICENSE.txt'
New-Item -ItemType Directory -Path $cache -Force | Out-Null

function Get-Sha256($path) { (Get-FileHash $path -Algorithm SHA256).Hash.ToLower() }

if (-not (Test-Path $dll) -or (Get-Sha256 $dll) -ne $pin.sha256.ToLower()) {
    $url = "https://github.com/$($pin.repository)/releases/download/v$($pin.version)/_WindowerMemory.dll"
    Write-Host "Downloading $url" -ForegroundColor Cyan
    Invoke-WebRequest -Uri $url -OutFile $dll
    $actual = Get-Sha256 $dll
    if ($actual -ne $pin.sha256.ToLower()) {
        Remove-Item $dll -Force
        throw "_WindowerMemory.dll v$($pin.version) has SHA-256 $actual, but windowermemory.json pins $($pin.sha256)"
    }
}

if (-not (Test-Path $license)) {
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/$($pin.repository)/v$($pin.version)/LICENSE.txt" -OutFile $license
}

Write-Output $cache
