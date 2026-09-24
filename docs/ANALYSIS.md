# XICamera — Analysis

> Architecture notes for XICamera. Maps the four launcher
> implementations to a single mental model and points at the
> XIPivot / XIOverclock patterns we adopt where they help.

## What XICamera is

XICamera is a **stateless data patcher.** It does not detour any
function in `FFXiMain.dll`. At load time, it scans the image for
specific instruction sequences, captures the operand addresses
those instructions read from, and either:

1. Overwrites the float at that address with the user's value, or
2. Allocates a new float, and rewrites the operand to point at the
   new float instead of the original.

On unload, it restores the originals (option 1) or restores the
original operand pointer (option 2).

There is exactly one in-place code patch — the 2-byte FPU clamp at
the battle-range site we replace with NOPs to enable 360° rotation.
It's also restored on unload.

This is deliberately the simplest possible kind of patch. There are
no detours, no trampolines, no shadow copies of game state, no
thread synchronization. The only reason XICamera could break the
client is if a future client update changes one of the 12
signatures. Each scan independently fails-soft (logs an error,
leaves the rest of the camera alone).

## How the four launcher implementations differ

The same 12-signature plan is implemented four times because each
launcher exposes memory through a different API:

| Launcher    | Implementation                              | API used                      |
|:------------|:--------------------------------------------|:------------------------------|
| Ashita 3    | `Ashita3/addons/xicamera/xicamera.lua`      | `ashita.memory.findpattern`   |
| Ashita 4    | `Ashita4/addons/xicamera/xicamera.lua`      | `ashita.memory.find`          |
| Windower 4  | `XICamera.Core` + `XICamera.Windower` DLL   | C++ `FindPattern` in `functions.cpp`, exposed via Lua C bindings to `XICamera.Windower\lua\XICamera.lua` |
| Windower 5  | `Windower5/addons/xicamera/xicamera.lua`    | `core.scanner` + `memory.struct` + LuaJIT FFI |

The Windower 4 split — native DLL plus Lua addon — predates the
LuaJIT FFI being practical for this kind of work. It's still the
canonical implementation to read because the Camera C++ class
mirrors the math and order-of-operations directly.

The Ashita 3, Ashita 4, and Windower 5 lua addons should track each
other byte-for-byte on the signatures themselves and feature-for-
feature on the chat-command surface. Where they intentionally
diverge (e.g. Ashita 4 uses the new `settings` library;
Windower 5 uses `core.command` instead of a global `command`
event), the divergence is forced by the launcher API.

## Inspirations

### From XIPivot

The multi-launcher folder layout is XIPivot's, originally:

```
XICamera/
├── XICamera.Core/        shared C++ logic
├── XICamera.Windower/    Windower 4 DLL + lua glue
├── Ashita3/              pure-lua addon, vendored at the launcher's path shape
├── Ashita4/              pure-lua addon, vendored at the launcher's path shape
└── Windower5/            pure-lua addon, vendored at the launcher's path shape
```

Each top-level launcher folder mirrors what the user is meant to
copy into their launcher install. The release zips just compress
the folder verbatim.

### From XIOverclock

XIOverclock is structurally similar (same launcher layout, same
multi-pattern signatures-with-labels concept) but goes further on
robustness:

| Feature                         | XIOverclock                              | XICamera today                    |
|:--------------------------------|:-----------------------------------------|:----------------------------------|
| Logger abstraction              | `ILogger` + per-launcher impl            | `ILogProvider` + `DummyLogProvider` (Windower 4 only) |
| INI-driven config               | `Config::LoadFromFile()` parses sections | Per-launcher hardcoded defaults   |
| Multi-version signature support | `[signatures]` section with labels       | Single hardcoded sig per feature  |
| `/<plugin> status` command      | Single line, prefix=`<plugin>`           | Multi-line "status" enumerating fields |
| Pattern scanner                 | Standalone `PatternScanner` module       | Inline in `functions.cpp` / each lua |
| FFXi image lookup               | `FFXiClient` module                      | Inline `GetModuleHandleA` per scan |
| Detour helper                   | `Detour` class with mini disassembler    | Not needed — XICamera doesn't detour |
| Release packaging               | `tools/package_release.ps1`              | (newly added) `tools/package_release.ps1` |

XICamera does not need detours, so the `Detour` module is irrelevant.
Everything else is on the table. The multi-version signature
support in particular is appealing — once a client update shifts
one of the 12 signatures, having an INI override means a new
pattern can be supplied without rebuilding the DLL or pushing
addon updates to four launcher trees.

A future refactor that adopts XIOverclock's INI/Logger/PatternScanner
would push the lua side from "implementation" to "thin presentation
layer over the Core" — the addons would be small and the math
would live in C++ (linked statically into the Windower DLL,
re-bound to lua via a tiny `_XICamera.dll`). The Ashita lua addons
would stay pure-lua, but they'd read the same INI for signature
overrides.

## Things deliberately not done

- **No detours / no trampolines.** Static data patches are sufficient.
- **No memory monitoring.** We don't keep watching memory after load —
  the game owns it; we just changed initial conditions.
- **No telemetry.** Status output is current values, not counters.
- **No GUI / overlay.** The chat-command surface is the entire UI.
- **No cross-character profiles.** One ini per install; if a user
  wants different settings per character they can use the
  Ashita/Windower per-character settings facilities.

## Risks

The whole plugin's correctness depends on the 12 signatures
matching unique sites in `FFXiMain.dll`. Two specific failure modes:

1. **Client update shifts a signature.** Detected by signature scan
   returning `0`; we log the field name and leave the rest of the
   camera alone (Camera.cpp path) or `error()` out the addon (lua
   paths — would be improved by graceful degradation matching the
   C++ behaviour).
2. **Pattern matches the wrong place.** The signatures are all
   12+ bytes and most include both the load opcode (`D8 0D` /
   `D9 05` etc.) and surrounding context, so collision is unlikely
   in practice. Worth re-verifying after each major client update
   that the scanned address still falls inside the expected
   function and the post-match bytes look like the expected FPU
   sequence.

The "scanned address looks reasonable" check is currently informal
("does the camera still feel right after I change distance?"). A
TESTING.md-level check that prints the resolved addresses + the
bytes at each address would make this verifiable. (See TESTING.md
for the current quick-check procedure.)

## Cross-reference

- `CAMERA_PATCH_TARGETS.md` — the 12 signatures + per-feature notes
- `CLIENT_BEHAVIOR.md` — how stock FFXi computes camera state
- `TESTING.md` — how to verify each feature is live in-game
- `XICamera.Core/Camera.cpp` — the canonical implementation order
