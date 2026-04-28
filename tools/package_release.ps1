# =============================================================================
#  package_release.ps1
#
#  Bundles the per-launcher install trees into release zips. Two of the four
#  bundles are pure-Lua (Ashita 3, Ashita 4, Windower 5); the Windower 4
#  bundle is the only one that needs a built DLL, so a Release|Win32 build
#  of XICamera.sln must run before this script for that one to be present.
#
#  Sources packed (relative to the repo root):
#
#     Ashita3/                      ->  XICamera-Ashita3-<ver>.zip
#     Ashita4/                      ->  XICamera-Ashita4-<ver>.zip
#     Windower5/                    ->  XICamera-Windower5-<ver>.zip
#     build\Release\Windower\       ->  XICamera-Windower-<ver>.zip
#
#  Output goes to build\Release\dist\.
#
#  Usage:
#      powershell -ExecutionPolicy Bypass -File tools\package_release.ps1
#      powershell -ExecutionPolicy Bypass -File tools\package_release.ps1 -Version 0.8
#      powershell -ExecutionPolicy Bypass -File tools\package_release.ps1 -Version 0.8 -Configuration Release
# =============================================================================

param(
    [string]$Configuration = 'Release',
    [string]$Version       = '',       # if empty, derive from git describe
    [string]$RepoRoot      = (Resolve-Path (Join-Path $PSScriptRoot '..'))
)

$ErrorActionPreference = 'Stop'

# ---- version string ---------------------------------------------------------

if (-not $Version) {
    try {
        Push-Location $RepoRoot
        $desc = (& git describe --tags --dirty --always 2>$null)
        if ($LASTEXITCODE -ne 0 -or -not $desc) {
            $desc = (& git rev-parse --short HEAD 2>$null)
        }
        if ($LASTEXITCODE -ne 0 -or -not $desc) {
            $desc = 'dev'
        }
        $Version = $desc.Trim()
    } catch {
        $Version = 'dev'
    } finally {
        Pop-Location
    }
}

Write-Host "Packaging XICamera $Version ($Configuration)" -ForegroundColor Cyan

$buildRoot = Join-Path $RepoRoot "build\$Configuration"
$distDir   = Join-Path $buildRoot 'dist'
New-Item -ItemType Directory -Path $distDir -Force | Out-Null

# ---- bundle plan -----------------------------------------------------------
#
# Each bundle is { source-dir, archive-tag, requires-build }. The Lua-only
# launchers source from the working tree directly so they can be packaged
# without invoking MSBuild. The Windower 4 bundle reads the post-build
# tree the .vcxproj already assembles under build\<cfg>\Windower\.

$bundles = @(
    @{ Source = Join-Path $RepoRoot   'Ashita3';                    Tag = 'Ashita3';   NeedsBuild = $false },
    @{ Source = Join-Path $RepoRoot   'Ashita4';                    Tag = 'Ashita4';   NeedsBuild = $false },
    @{ Source = Join-Path $RepoRoot   'Windower5';                  Tag = 'Windower5'; NeedsBuild = $false },
    @{ Source = Join-Path $buildRoot  'Windower';                   Tag = 'Windower';  NeedsBuild = $true  }
)

$results = @()
foreach ($b in $bundles) {
    $src     = $b.Source
    $zipName = "XICamera-$($b.Tag)-$Version.zip"
    $zipPath = Join-Path $distDir $zipName

    if (-not (Test-Path $src)) {
        if ($b.NeedsBuild) {
            Write-Warning "  skip $($b.Tag): $src not found (run a $Configuration|Win32 build first)"
        } else {
            Write-Warning "  skip $($b.Tag): $src not found"
        }
        continue
    }

    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

    Write-Host ("  -> {0}" -f $zipName)
    Compress-Archive -Path (Join-Path $src '*') -DestinationPath $zipPath -CompressionLevel Optimal

    $size = (Get-Item $zipPath).Length
    $results += [PSCustomObject]@{
        Archive = $zipName
        Bytes   = $size
        KB      = [math]::Round($size / 1KB, 1)
    }
}

Write-Host ""
Write-Host "Wrote:" -ForegroundColor Green
$results | Format-Table -AutoSize
Write-Host "  ($distDir)"
