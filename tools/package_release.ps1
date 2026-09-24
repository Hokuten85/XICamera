# =============================================================================
#  package_release.ps1
#
#  Bundles the per-launcher addon folders into the release zips GitHub ships.
#  Each zip holds the addon folder at its root, the way users have always
#  installed XICamera ("copy the xicamera folder into your addons folder"):
#
#     Ashita3/addons/xicamera/            ->  xicamera_ashita3_addon_v<ver>.zip    (xicamera/...)
#     Ashita4/addons/xicamera/            ->  xicamera_ashita4_addon_v<ver>.zip    (xicamera/...)
#     Windower5/addons/xicamera/          ->  xicamera_windower5_addon_v<ver>.zip  (xicamera/...)
#     Windower4/addons/XICamera/          ->  xicamera_windower4_addon_v<ver>.zip  (XICamera/...)
#
#  Every bundle packs straight from the working tree. The Windower 4 bundle
#  also gets libs/_WindowerMemory.dll (and its license) from the WindowerMemory
#  release pinned in windowermemory.json, downloaded and checked against the
#  pinned SHA-256 by tools/fetch_windowermemory.ps1.
#
#  Output: build\dist\<zips> plus SHA256SUMS.txt.
#
#  Usage:
#      pwsh -File tools\package_release.ps1
#      pwsh -File tools\package_release.ps1 -Version 0.8.0
#
#  -Version defaults to addon.version in Ashita4/addons/xicamera/xicamera.lua.
# =============================================================================

param(
    [string]$Version  = '',
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')),
    [string]$OutDir   = ''
)

$ErrorActionPreference = 'Stop'

# ---- version ----------------------------------------------------------------

if (-not $Version) {
    $lua = Get-Content (Join-Path $RepoRoot 'Ashita4\addons\xicamera\xicamera.lua') -Raw
    if ($lua -match "addon\.version\s*=\s*'([^']+)'") { $Version = $Matches[1] }
    else { throw 'could not read addon.version from Ashita4/addons/xicamera/xicamera.lua' }
}
$Version = $Version.TrimStart('v', 'V')

if (-not $OutDir) { $OutDir = Join-Path $RepoRoot 'build\dist' }
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

Write-Host "Packaging XICamera $Version -> $OutDir" -ForegroundColor Cyan

$wm = & (Join-Path $PSScriptRoot 'fetch_windowermemory.ps1') -RepoRoot $RepoRoot

# ---- the four bundles --------------------------------------------------------

$bundles = @(
    @{ Tag = 'ashita3';   Source = Join-Path $RepoRoot 'Ashita3\addons\xicamera';                       Required = @('xicamera.lua', 'xicamera_core.lua', 'README.md') },
    @{ Tag = 'ashita4';   Source = Join-Path $RepoRoot 'Ashita4\addons\xicamera';                       Required = @('xicamera.lua', 'xicamera_core.lua', 'README.md') },
    @{ Tag = 'windower5'; Source = Join-Path $RepoRoot 'Windower5\addons\xicamera';                     Required = @('xicamera.lua', 'xicamera_core.lua', 'manifest.xml', 'README.md') },
    @{ Tag = 'windower4'; Source = Join-Path $RepoRoot 'Windower4\addons\XICamera';                     Required = @('XICamera.lua', 'lib\xicamera_core.lua', 'lib\windower_native.lua', 'README.md')
       Extra = @{ 'libs\_WindowerMemory.dll' = Join-Path $wm '_WindowerMemory.dll'; 'libs\WindowerMemory-LICENSE.txt' = Join-Path $wm 'LICENSE.txt' } }
)

# The shared core must be byte-identical in every port; refuse to ship a drifted copy.
$master = Get-Content (Join-Path $RepoRoot 'Ashita4\addons\xicamera\xicamera_core.lua') -Raw
foreach ($copy in @('Ashita3\addons\xicamera\xicamera_core.lua', 'Windower5\addons\xicamera\xicamera_core.lua', 'Windower4\addons\XICamera\lib\xicamera_core.lua')) {
    if ((Get-Content (Join-Path $RepoRoot $copy) -Raw) -ne $master) {
        throw "xicamera_core.lua differs from the Ashita 4 copy: $copy"
    }
}

$written = @()
foreach ($b in $bundles) {
    $zipName = "xicamera_$($b.Tag)_addon_v$Version.zip"
    $zipPath = Join-Path $OutDir $zipName

    $missing = @($b.Required | Where-Object { -not (Test-Path (Join-Path $b.Source $_)) })
    if (-not (Test-Path $b.Source) -or $missing.Count -gt 0) {
        $why = if (-not (Test-Path $b.Source)) { "$($b.Source) not found" } else { "missing: $($missing -join ', ')" }
        throw "cannot package $($b.Tag): $why"
    }

    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

    # Stage a clean copy so stray files next to the addon (old zips, editor files) never ship.
    $stage = Join-Path ([System.IO.Path]::GetTempPath()) ("xicamera-pack-" + [guid]::NewGuid().ToString('N'))
    $folder = Join-Path $stage (Split-Path $b.Source -Leaf)
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    Copy-Item -Path (Join-Path $b.Source '*') -Destination $folder -Recurse -Force
    Get-ChildItem $folder -Recurse -Include '*.zip', '*.pdb', '*.ilk', '*.exp', '*.lib', 'Thumbs.db', '.DS_Store' | Remove-Item -Force
    if ($b.Extra) {
        foreach ($to in $b.Extra.Keys) {
            $dest = Join-Path $folder $to
            New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null
            Copy-Item $b.Extra[$to] $dest -Force
        }
    }

    Write-Host ("  -> {0}" -f $zipName)
    Compress-Archive -Path $folder -DestinationPath $zipPath -CompressionLevel Optimal
    Remove-Item $stage -Recurse -Force

    $written += Get-Item $zipPath
}

if ($written.Count -eq 0) { throw 'nothing was packaged' }

# ---- checksums ---------------------------------------------------------------

$sums = $written | ForEach-Object { "{0}  {1}" -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower(), $_.Name }
Set-Content -Path (Join-Path $OutDir 'SHA256SUMS.txt') -Value $sums -Encoding ascii

Write-Host ""
Write-Host "Wrote:" -ForegroundColor Green
$written | Select-Object Name, @{ n = 'KB'; e = { [math]::Round($_.Length / 1KB, 1) } } | Format-Table -AutoSize
Write-Host "  $OutDir"
