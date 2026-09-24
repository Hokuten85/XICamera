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
#     build\<cfg>\Windower\XICamera\      ->  xicamera_windower4_addon_v<ver>.zip  (XICamera/...)
#
#  Three bundles are pure Lua and pack straight from the working tree. The
#  Windower 4 bundle needs the DLL, so a Release|Win32 build of
#  XICamera.Windower must run first (its post-build assembles the folder).
#
#  Output: build\dist\<zips> plus SHA256SUMS.txt.
#
#  Usage:
#      powershell -ExecutionPolicy Bypass -File tools\package_release.ps1
#      powershell -ExecutionPolicy Bypass -File tools\package_release.ps1 -Version 0.8.0
#      powershell -ExecutionPolicy Bypass -File tools\package_release.ps1 -Version 0.8.0 -Strict
#
#  -Version defaults to addon.version in Ashita4/addons/xicamera/xicamera.lua.
#  -Strict fails instead of skipping when the Windower 4 build tree is missing
#  (CI uses it).
# =============================================================================

param(
    [string]$Configuration = 'Release',
    [string]$Version       = '',
    [string]$RepoRoot      = (Resolve-Path (Join-Path $PSScriptRoot '..')),
    [string]$OutDir        = '',
    [switch]$Strict
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

Write-Host "Packaging XICamera $Version ($Configuration) -> $OutDir" -ForegroundColor Cyan

# ---- the four bundles --------------------------------------------------------

$bundles = @(
    @{ Tag = 'ashita3';   Source = Join-Path $RepoRoot 'Ashita3\addons\xicamera';                       Required = @('xicamera.lua', 'xicamera_core.lua', 'README.md') },
    @{ Tag = 'ashita4';   Source = Join-Path $RepoRoot 'Ashita4\addons\xicamera';                       Required = @('xicamera.lua', 'xicamera_core.lua', 'README.md') },
    @{ Tag = 'windower5'; Source = Join-Path $RepoRoot 'Windower5\addons\xicamera';                     Required = @('xicamera.lua', 'xicamera_core.lua', 'manifest.xml', 'README.md') },
    @{ Tag = 'windower4'; Source = Join-Path $RepoRoot "build\$Configuration\Windower\XICamera";        Required = @('XICamera.lua', 'lib\xicamera_core.lua', 'lib\windower_native.lua', 'libs\_XICamera.dll', 'libs\_WindowerMemory.dll', 'README.md'); NeedsBuild = $true }
)

# The shared core must be byte-identical in every port; refuse to ship a drifted copy.
$master = Get-Content (Join-Path $RepoRoot 'Ashita4\addons\xicamera\xicamera_core.lua') -Raw
foreach ($copy in @('Ashita3\addons\xicamera\xicamera_core.lua', 'Windower5\addons\xicamera\xicamera_core.lua', 'XICamera.Windower\lua\lib\xicamera_core.lua')) {
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
        if ($b.NeedsBuild) { $why += " (run a $Configuration|Win32 build of XICamera.Windower first)" }
        if ($Strict) { throw "cannot package $($b.Tag): $why" }
        Write-Warning "  skip $($b.Tag): $why"
        continue
    }

    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

    # Stage a clean copy so stray files next to the addon (old zips, editor files) never ship.
    $stage = Join-Path ([System.IO.Path]::GetTempPath()) ("xicamera-pack-" + [guid]::NewGuid().ToString('N'))
    $folder = Join-Path $stage (Split-Path $b.Source -Leaf)
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    Copy-Item -Path (Join-Path $b.Source '*') -Destination $folder -Recurse -Force
    Get-ChildItem $folder -Recurse -Include '*.zip', '*.pdb', '*.ilk', '*.exp', '*.lib', 'Thumbs.db', '.DS_Store' | Remove-Item -Force

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
