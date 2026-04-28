# Camera Feature Candidates — Investigation Notes

> **Status:** research notes, no code changes yet. This document
> identifies candidate patch sites for proposed XICamera features
> based on a static analysis of `sub_1001ED90` (the camera-task
> per-frame method) **plus** historical pre-v0.7 work (commit
> [`e3b2a98b`](https://github.com/Hokuten85/XICamera/tree/e3b2a98b25b8b9465d566c370ae36e4c90bf3251))
> that already had working signatures and a per-frame override
> mechanism for camera position.
>
> Reproduce with `python tools/analyze_camera_features.py`.

## TL;DR — much of the work is already done

The pre-v0.7 codebase enforced a fixed camera distance by writing
the camera-position vector each frame (`prerender` lua event). It
needed three signatures to do that:

| Signature | What it gives | Verified in current April-2026 build? |
|:--|:--|:--|
| `83 C4 04 85 C9 74 11 8B 11 6A 01 FF 52 18 C7 05` (operand at +0x10) | `pointerToCamera` — pointer to a slot that holds the live camera-task instance pointer | **Yes** (VA `0x1001E50C`, operand `0x10455D64`) |
| `80 A0 B2 00 00 00 FB C6 05 ?? ?? ?? ?? 00` (operand at +0x09) | `cameraConnectPtr` — byte = 1 when camera is attached to a player (0 in cutscenes / loading) | **Yes** (VA `0x10084221`, operand `0x10350230`) |
| `8B CF E8 ?? ?? ?? ?? 8B 0D ?? ?? ?? ?? E8 ?? ?? ?? ?? 8B E8 85 ED 75 0C B9` (operand at +0x19) | `firstPersonPtr` — pointer; `firstPersonPtr[0x28]` = nonzero in first-person view | **Yes** (VA `0x1001F183`, operand `0x10486F50`) |

Plus the FSTP detour anchor:
| `D8 47 48 D9 5F 48 E8` | `fadd/fstp [edi+0x48]; CALL` — the per-frame camera-position update site | **Yes** (VA `0x1001F077`) |

This unlocks a much cleaner implementation than code-cave injection.
**The pattern is:** resolve the camera-task root once at load, then
each frame check (connected && not-first-person) and write whatever
fields we want directly. The game's own camera math runs as usual;
we override the result before render.

## Camera-task struct layout (verified)

Per the historical lua code at `e3b2a98b`:

```
rootCameraAddress = *(uint32_t*)(*pointerToCamera)

  +0x44   cam.X   (world X coordinate)
  +0x48   cam.Z   (world Z coordinate, NOT vertical)
  +0x4C   cam.Y   (vertical / world Y / "up" axis)
  +0x50   focal.X
  +0x54   focal.Z
  +0x58   focal.Y (vertical of focal point)
```

This is FFXi's standard (X, Z, Y) ordering — world up is the third
component. Important correction to my earlier reading: `[edi+0x48]`
is the Z axis (one of the horizontal components), not vertical.
The actual vertical the user wants to lock/snap is `[edi+0x4C]`.

## Feature 1 — vertical camera position lock

**Goal:** freeze the camera's vertical position so it stops tracking
the focal point's vertical changes. Manual camera input (right-stick
up/down) should still work.

**Implementation pattern** (lua per-frame hook):

```lua
-- At addon load:
ptrToCameraSlot = ashita.memory.findpattern(...) + 0x10
ptrToCamera     = ashita.memory.read_uint32(ptrToCameraSlot)
cameraConnectPtr = ... (resolved via signature)
firstPersonPtr   = ... (resolved via signature)

local lockedY = nil  -- nil = not locking

ashita.events.register('prerender', 'camera_vlock', function()
    if not options.verticalLock then return end
    local cam = ashita.memory.read_uint32(ptrToCamera)
    if cam == 0 then return end
    local connected = ashita.memory.read_uint8(cameraConnectPtr) == 1
    local fps       = ashita.memory.read_uint8(firstPersonPtr + 0x28) ~= 0
    if not connected or fps then return end

    if not lockedY then
        lockedY = ashita.memory.read_float(cam + 0x4C)
    end
    ashita.memory.write_float(cam + 0x4C, lockedY)
end)

-- /camera vlock on|off  -- toggles options.verticalLock + clears lockedY on off
```

**Manual input still works:** the user's right-stick input feeds
into the game's per-frame camera math BEFORE prerender. By the time
prerender fires, the game has already moved the camera. We then
overwrite the vertical with our locked value. Net: horizontal input
flows through (we don't touch +0x44 / +0x48), vertical input is
clobbered by the lock. To allow manual override of the lock, the
user would issue `/camera vlock off` to clear the lock and use the
new vertical position as the new lock anchor.

If the user wants manual vertical input to *update the locked Y*
while held, that's also doable: detect input via input deltas
(`isFirstPerson`'s neighbors include input flags) and refresh
`lockedY` while input is non-zero.

## Feature 2 — snap vertical to offset

**Goal:** force vertical to a specific value relative to the focal
point. E.g., "always sit 2.5 units above focal."

**Implementation:** trivial extension of Feature 1:

```lua
ashita.events.register('prerender', 'camera_vsnap', function()
    if not options.verticalSnap then return end
    local cam = ashita.memory.read_uint32(ptrToCamera)
    if cam == 0 then return end
    local focal_y = ashita.memory.read_float(cam + 0x58)
    ashita.memory.write_float(cam + 0x4C, focal_y + options.verticalSnapOffset)
end)

-- /camera vsnap <offset>   -- sets options.verticalSnapOffset, enables snap
-- /camera vsnap off        -- disables snap
```

`/camera vsnap 0` means "match focal Y exactly." Positive numbers
sit above focal, negative below.

## Feature 3 — battle camera pitch

**Goal:** adjust the downward tilt angle when locked on. User can
still manually move camera up/down.

**Pitch is geometric** — the camera-to-focal vector projected onto
the vertical axis. Computing it:

```
dx = cam.X - focal.X
dz = cam.Z - focal.Z
dy = cam.Y - focal.Y
horiz = sqrt(dx² + dz²)
pitch = atan2(dy, horiz)   -- positive = looking down
```

To set a target pitch each frame:

```lua
ashita.events.register('prerender', 'camera_pitch', function()
    if not options.battlePitchEnabled then return end
    local cam = ashita.memory.read_uint32(ptrToCamera)
    if cam == 0 then return end

    local cx = ashita.memory.read_float(cam + 0x44)
    local cz = ashita.memory.read_float(cam + 0x48)
    local cy = ashita.memory.read_float(cam + 0x4C)
    local fx = ashita.memory.read_float(cam + 0x50)
    local fz = ashita.memory.read_float(cam + 0x54)
    local fy = ashita.memory.read_float(cam + 0x58)

    local dx, dz = cx - fx, cz - fz
    local horiz_dist = math.sqrt(dx*dx + dz*dz)
    if horiz_dist < 0.01 then return end

    -- Compute desired vertical so that atan2(dy, horiz_dist) = target_pitch.
    -- Total camera-to-focal distance stays whatever the game decided.
    local target_pitch = options.battlePitchRadians
    local total = math.sqrt(dx*dx + dz*dz + (cy - fy)^2)
    local new_horiz = total * math.cos(target_pitch)
    local new_vert  = total * math.sin(target_pitch)

    -- Scale x/z components to the new horizontal length, write new vertical.
    local scale = new_horiz / horiz_dist
    ashita.memory.write_float(cam + 0x44, fx + dx * scale)
    ashita.memory.write_float(cam + 0x48, fz + dz * scale)
    ashita.memory.write_float(cam + 0x4C, fy + new_vert)
end)

-- /camera pitch <degrees>   -- 0 = horizontal, positive = looking down
-- /camera pitch off
```

**Note:** writing all three components each frame works but might
fight the game's collision response. Watch for the proximity-buffer
push #1 / #2 patches from `JITTER_INVESTIGATION.md` interacting
with this. Probably want pitch + jitter patches to coexist; the
prerender hook runs after the per-frame camera math (which includes
the jitter math), so we get the last word.

**Manual override:** if the user moves the camera vertically, do we
absorb that as the new pitch? Easiest answer: yes, recompute
`battlePitchRadians` from the post-input camera position whenever
the user moves the camera, then re-apply on subsequent frames.
Detecting "user moved" requires watching the input state byte
(neighbors of `firstPersonPtr + 0x28` likely include input deltas;
worth poking).

## Feature 4 — battle camera vertical offset

**Goal:** shift how high the battle camera floats above the focal
point.

**Implementation:** identical to Feature 2 but only when locked on.
`/camera vofs <offset>` sets `options.verticalOffset`; the prerender
hook applies it whenever the lockon flag is set.

The "is locked on?" flag is somewhere on the camera task; the
historical code didn't expose it because the per-frame distance fix
ran in both cases. Need to identify by reading flags around
`+0xF0`-area in the camera struct (which has a state byte the
function compares with `4`). Quick test: enter battle, check what
value `cam[0xF0]` takes vs. out-of-battle. Likely `4` is the
"locked on" mode.

## Implementation pattern recap

For all four features, the lua-side architecture is:

1. **At load:** resolve `pointerToCamera`, `cameraConnectPtr`,
   `firstPersonPtr` via the three historical signatures (verified
   to still work in April 2026 build).
2. **Per-frame prerender:** dereference `pointerToCamera` to get
   the active camera-task root. Bail if the root is null, the
   camera is disconnected, or the user is in first-person. Read /
   write whatever struct fields the active feature(s) need.
3. **Chat commands:** standard absolute + multiplier subcommand
   pattern from the existing 12 features.

The C++ Windower 4 DLL needs a similar mechanism. XIPivot has a
Direct3D Present hook the existing Camera class could borrow; the
XIOverclock `Detour` machinery would also work. Or — since the lua
side already has a per-frame hook that's per-launcher, we can
implement these features in lua only and have Camera.cpp expose
just the static-data setters (current pattern). That keeps the
C++ code simple.

**Recommendation:** implement Features 1, 2, 4 in pure lua across
all three lua addons (Ashita 3 / Ashita 4 / Windower 5), with
matching `/camera vlock`, `/camera vsnap`, `/camera vofs` commands.
Feature 3 (pitch) is geometric and works in lua too, but watch out
for interaction with the per-frame jitter patches.

## What this investigation deliberately *did not* find

- **Code-cave injection paths.** XICamera doesn't need them for
  Features 1-4; per-frame prerender override is sufficient.
- **First-person view distance.** Separate code path; not relevant
  here.
- **Free-camera default distance.** Also a separate path.
- **Lock-on engage/disengage triggers.** Probably visible at
  `+0xF0` in the camera struct; needs in-game probing to confirm.
