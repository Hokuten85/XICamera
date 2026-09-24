# XICamera

A camera-tweaks addon for **Final Fantasy XI**, shipped as builds
for **Ashita v3**, **Ashita v4**, **Windower 4**, and **Windower 5**.
XICamera moves a few floats around inside `FFXiMain.dll` so the
camera obeys you instead of stock SE defaults.

| Feature | What it does | Default |
|:--|:--|:--|
| **Camera distance** | Sets the third-person camera distance from the player. Preserves the original min/max delta so mouse-wheel zoom-in still has its full travel. | 6 |
| **Battle distance** | Camera distance while locked onto a target. | 8.2 |
| **Pan speeds (h / v)** | Mouse / right-stick rotation speed. Vertical can auto-rescale with distance. | 3 / 10.7 |
| **Battle camera range** | Angular sweep allowed when rotating around a locked target. 0–100; > ~50 reaches past 180°. | 4 |
| **Battle range lock** | When OFF, removes the 2-byte FPU clamp and the camera rotates a full 360° around the target. | ON |
| **Vertical height snap** | One-shot command that sets camera height to the current character/reference height plus an offset. Useful for binding to a key. | n/a |
| **Jitter cancel** | Replaces the 0.125 jitter scalar with 1.0 so rapid movement stops shrinking the camera. | always on |

## Quick start

1. **Download** the zip for your launcher from the
   [releases page](https://github.com/Hokuten85/XICamera/releases):
   - `xicamera_ashita4_addon_v<version>.zip` (Ashita v4)
   - `xicamera_ashita3_addon_v<version>.zip` (Ashita v3)
   - `xicamera_windower4_addon_v<version>.zip` (Windower 4, DLL + lua)
   - `xicamera_windower5_addon_v<version>.zip` (Windower 5)
2. **Extract** the zip into your launcher's `addons` folder. Each
   zip holds the addon folder at its root, so it lands as
   `addons/xicamera/` (`addons/XICamera/` on Windower 4).
3. **Launch the game**, log in, and load your character. Chat
   commands only work once you're in-world.
4. **Verify** with `/camera status` (Ashita) or `//camera status`
   (Windower). Expected output is a multi-line summary of every
   setting. See [TESTING.md](TESTING.md) for the per-feature checks.

> **Chat-command prefix**: Ashita uses `/`, Windower uses `//`.
> Every command in this README uses the generic `/` form; on
> Windower, double it.

## Chat commands

```
/camera status                      # multi-line dump of current values
/camera d|distance <n>              # set camera distance (default 6)
/camera b|battle <n>                # set battle camera distance (default 8.2)
/camera hs|hspeed <n>               # set horizontal pan speed (default 3)
/camera vs|vspeed <n>               # set vertical pan speed; forces autoCalc OFF
/camera vh|vheight <n>              # snap camera height to character/reference height + n
/camera br|brange <0-100>           # battle camera range; forces lock ON
/camera bl|battlelock <on|off>      # 360° rotation around locked target when OFF
/camera in|incr  /  /camera de|decr # ±1 on camera distance
/camera bin|bincr  /  /camera bde|bdecr  # ±1 on battle distance
/camera soi|saveOnIncrement         # toggle persisting incr/decr to settings
/camera acv|autoCalcVertSpeed       # toggle vertical pan auto-rescaling
/camera h|help                      # one-line hint per command
```

`/cam`, `/xicamera`, and `/xicam` are accepted as aliases of
`/camera` on every launcher. Settings persist via the launcher's
own settings facility (Ashita config dir, Windower data/settings.xml).

## Compatibility

XICamera does not detour any FFXi function and never writes the
client's own constants. It allocates its own floats and re-points
24 operands in the camera code at them, each only while the bytes
at that site are the ones it found at load, and it restores each
only while the site still holds its pointer. Everything is reverted
on unload.

Other tools that touch the same bytes are handled rather than raced.
A site another tool already changed is left alone and reported as
`owned`, `neutral` or `foreign` in `/camera status` (and in the
Ashita 4 settings window). TrueFPS shares the three jitter sites
with XICamera and works in either load order: whichever tool reaches
them first keeps them. See [`docs/TOOL_COMPAT_REVIEW.md`](docs/TOOL_COMPAT_REVIEW.md).

Works on retail and on private-server emulators (LSB / Topaz).
There is no server-visible signal — XICamera emits no packets.

## Repository layout

```
XICamera/
├── Ashita4/addons/xicamera/xicamera_core.lua
│                          the camera patch logic, shared verbatim by every port
├── Ashita3/               Ashita v3 lua addon (host + copy of the core)
├── Ashita4/               Ashita v4 lua addon (host + core + ImGui settings window)
├── Windower5/             Windower 5 lua addon (host + copy of the core)
├── XICamera.Windower/     Windower 4: memory-primitive DLL + lua addon (host + copy of the core)
├── XICamera.Core/         legacy C++ camera logic; no longer built by anything (safe to delete)
├── 3rdParty/SDKs/         Windower lua SDK
├── docs/                  Camera-internals reference + tool-compatibility review
├── tools/                 Release packaging, binary-analysis helpers, tools/test_core.lua
└── XICamera.sln           Visual Studio solution
```

Every port is lua: one shared `xicamera_core.lua` holds the site
table and all patching rules, and each host supplies a small memory
adapter plus settings and commands. On Windower 4 the adapter is
backed by a DLL (`_XICamera.dll`) that exposes memory read, write,
scan, allocation and an atomic compare-exchange to lua.
`tools/test_core.lua <unpacked FFXiMain image>` runs the core against
the real client bytes without the game.

## Building

**Prerequisites:** Visual Studio 2019 or 2022 with the
"Desktop C++ Development" workload (v143 toolset),
Windows 10 SDK. Only needed for the Windower 4 DLL; the lua
addons need no build step.

**Step 1 — drop the SDKs.** The Windower lua SDK headers are not
redistributed here. Copy them into:

```
3rdParty/SDKs/Windower/LUA/             <- from Windower's LuaCore package
3rdParty/SDKs/Windower/LuaCore_exports.lib
```

**Step 2 — build.** Open `XICamera.sln`, select `Release | Win32`,
Build Solution. The Windower 4 project's post-build copies the
DLL plus the lua addon into `build/Release/Windower/XICamera/`.

**Step 3 — release zips (optional).** After a successful build:

```
powershell -ExecutionPolicy Bypass -File tools\package_release.ps1
```

Writes `build/dist/xicamera_<launcher>_addon_v<version>.zip` for
each launcher plus `SHA256SUMS.txt` (the lua-only bundles don't
need the build step; they're packed straight from the working
tree). The version defaults to `addon.version` in the Ashita 4
lua and can be overridden with `-Version 0.8.0`.

**Releases are cut by GitHub Actions.** Pushing a tag `v<version>`
runs `.github/workflows/release.yml`, which builds the DLL, packages
the four zips and publishes the release; a version with a suffix
(`v0.8.0-pre1`) is published as a pre-release, and an annotated
tag's message becomes the release notes. The workflow can also be
run by hand from the Actions tab with a version and a pre-release
switch. Bump `addon.version` in the four lua hosts and the Windower 5
`manifest.xml` before tagging.

## Installing

### Ashita v3

1. Copy `Ashita3/addons/xicamera/` into `<Ashita3>/addons/xicamera/`.
2. In-game: `/addon load xicamera`.

### Ashita v4

1. Copy `Ashita4/addons/xicamera/` into `<Ashita4>/addons/xicamera/`.
2. In-game: `/addon load xicamera`. `/cam ui` opens the settings
   window; settings save per character under `config/addons/xicamera/`.

### Windower 4

1. Copy `build/Release/Windower/XICamera/` into
   `<Windower>/addons/`. The addon dir should end up at
   `<Windower>/addons/XICamera/` containing `XICamera.lua`,
   `lib/xicamera_core.lua`, `lib/windower_native.lua`,
   `libs/_XICamera.dll`, and a README.
2. In-game: `//lua load XICamera`.

### Windower 5

1. Copy `Windower5/addons/xicamera/` into
   `<Windower5>/addons/xicamera/`.
2. In-game: `//addon load xicamera`.

## Documentation

Camera internals and patch sites are documented under [`docs/`](docs/):

- [`ANALYSIS.md`](docs/ANALYSIS.md) — XICamera architecture overview;
  how the four launcher implementations relate; what we adopted from
  XIPivot and XIOverclock.
- [`CLIENT_BEHAVIOR.md`](docs/CLIENT_BEHAVIOR.md) — how stock FFXi
  computes camera state; what each value does.
- [`CAMERA_PATCH_TARGETS.md`](docs/CAMERA_PATCH_TARGETS.md) — the
  24 patch sites, their signatures and groups; required reading
  before updating any signature.
- [`TOOL_COMPAT_REVIEW.md`](docs/TOOL_COMPAT_REVIEW.md) — why the
  0.8 model exists: the pooled-constant problem and how XICamera
  coexists with TrueFPS and similar tools.

[`TESTING.md`](TESTING.md) covers the in-game verification
procedure for each feature.

## Special thanks

- **Renee Koecher ("Heals")** — author of
  [XIPivot](https://github.com/HealsCodes/XIPivot). The multi-launcher
  layout (shared `.Core` + per-launcher shim) is lifted from XIPivot,
  and a huge chunk of the original C++ scaffolding came directly
  from that project.
- **atom0s** — for much of the Ashita ecosystem the lua addons
  depend on.

## Disclaimer

I tested XICamera to the best of my capabilities but I can't
guarantee bug-free behaviour on every client version. Use at your
own discretion; I take no responsibility for client crashes or
data loss.

## Status

0.8 is a pre-release: the patch model changed from overwriting
constants to re-pointing operands, and it has been verified against
an unpacked client image (`tools/test_core.lua`) but needs time in
game across launchers. The mechanism is simple enough that it either
works or it reports which site is not in and stays out of the way.
Signature updates for new client versions are a one-row change in
the shared `xicamera_core.lua`, copied to the four ports; see
[`docs/CAMERA_PATCH_TARGETS.md`](docs/CAMERA_PATCH_TARGETS.md) for
the derivation process.

## Support

Feedback through GitHub issues or the FFXIAH forums is appreciated.
