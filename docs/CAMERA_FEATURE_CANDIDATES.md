# Camera Feature Candidates — Investigation Notes

> **Status:** vertical lock was declined, but one-shot vertical
> snap-to-offset has been implemented. In-game testing of the
> Feature-1 lock candidate sites found that NOPing
> `FFXiMain.dll+0x1F07A` did lock vertical movement, but the resulting
> behavior (camera dropping and getting stuck at a lower height when
> moving) was not what was wanted; the other four FSTP sites had no
> observable effect. The shipped `vheight|vh` command avoids that
> lock behavior by writing camera Y once and then letting the normal
> camera update loop continue.
>
> Reproduce the analysis with `python tools/analyze_camera_features.py`.

## Camera-task struct layout (deduced)

`sub_1001ED90` operates on `this` via `edi`. The accesses we see suggest
this layout (offsets in bytes from the camera-task object):

| Offset    | Likely meaning                                         | Evidence |
|:----------|:-------------------------------------------------------|:---------|
| `+0x00`   | Yaw or rotation accumulator (FLD reads, MOV writes)    | 4 accesses |
| `+0x04`   | Pitch or rotation accumulator                          | `fsubr`/`fadd`/`fstp` pattern at 0x1001F4A0 / 0x10020E4C / 0x10020E56 |
| `+0x44`   | Camera position vec3 base (x at +0x44, y at +0x48, z at +0x4C) | 7 `lea` ops loading `[edi+0x44]` as a pointer arg |
| `+0x48`   | **Camera Y (vertical position)** — the user-facing "vertical position" knob | 16 accesses, 5 of which are `fstp` writes |
| `+0x4C`   | Camera Z                                               | 2 `mov` reads |
| `+0x50`   | Vec3 base for second position (target?)                | 1 `lea` |
| `+0x54`   | Likely target Y / vertical clamp anchor                | `fsub`/`fcomp` against camera Y |
| `+0xBC`   | State block (used as `lea` source)                     | 3 `lea` ops |
| `+0xF0`   | State byte (camera mode? see compares with `4`)        | `mov [edi+0xf0], 4` and `cmp [edi+0xf0], 4` |

## Feature 1 — vertical camera position lock

**Goal (per user):** freeze the vertical pitch of the camera so it
stops updating per-frame. Should work in both battle and normal
camera modes. User can still manually move camera up/down via input.

**Approach:** the camera Y position is stored at `[edi+0x48]`. There
are **5 FSTP write sites** that update it each frame:

| VA            | Bytes (3)    | Context                                          |
|:--------------|:-------------|:-------------------------------------------------|
| `0x1001F07A`  | `D9 5F 48`   | Follows `fadd [edi+0x48]` at 0x1001F077          |
| `0x1001F1CD`  | `D9 5F 48`   | Follows `fadd [edi+0x48]` at 0x1001F1CA          |
| `0x1001FE15`  | `D9 5F 48`   | End of the proximity-collision Y adjust block   |
| `0x1002071E`  | `D9 5F 48`   | (untraced — separate Y-adjustment code path)    |
| `0x10020767`  | `D9 5F 48`   | (untraced — separate Y-adjustment code path)    |

**Patch shape:** to "lock" vertical position, we'd replace each
FSTP `[edi+0x48]` with `FSTP ST(0)` followed by a NOP, both kept
to 3 bytes total to preserve subsequent instruction layout. Bytes:
`DD D8 90` (= `fstp st(0); nop`). FSTP-ST(0) discards the value
without writing memory, keeping FPU-stack discipline intact.

**Caveats:**
- Locking ALL five writes might over-constrain — the user's
  manual "move camera up/down" input may flow through one of
  these writes. Need to identify which write is the per-frame
  *automatic* update vs. the *user-input* update. Doing this
  reliably requires a runtime debugger session or annotated
  decompile reading.
- A simpler alternative: lock only the proximity-related write at
  `0x1001FE15` (which is in the same block as the jitter math)
  and observe. If that's the main "auto-pull-camera-down" site,
  this single patch may give the desired feel.
- Another simpler alternative: **don't do code-modification
  patches at all** for this feature. Instead, lock vertical via a
  per-frame lua hook that resets `[edi+0x48]` to the desired
  value after each frame. That's a different architectural
  pattern (would need a frame hook, which XICamera doesn't have
  today).

**Recommended next step:** in-game test of NOPing
`0x1001FE15` alone first (smallest possible change). Then expand
coverage if needed.

### Drafted signatures for the FSTP sites

Each FSTP is exactly `D9 5F 48`, which is too short / common to
sig-match alone. Sig out longer surrounding context for each site.
Bytes are taken straight from `tools/analyze_camera_features.py`'s
disassembly; verify uniqueness before patching:

| Site VA       | Surrounding signature (~16 bytes)                            | FSTP at offset |
|:--------------|:-------------------------------------------------------------|:---------------|
| `0x1001F07A`  | (need to dump bytes around 0x1001F070-0x1001F080)            | TBD            |
| `0x1001F1CD`  | (need to dump bytes around 0x1001F1C0-0x1001F1D0)            | TBD            |
| `0x1001FE15`  | `D9 05 70 5D 45 10 D8 E1 D8 6F 48 D9 5F 48`                  | `+0x0B`        |
| `0x1002071E`  | (need to dump bytes around 0x10020715-0x100207A0)            | TBD            |
| `0x10020767`  | (need to dump bytes around 0x10020760-0x100207B0)            | TBD            |

## Feature 2 — snap vertical position to a specific offset

**Goal (per user):** instead of locking, *snap* the vertical to a
specific value the user picks (e.g., always sit at Y = +2.5 above
target).

**Implemented approach:** avoid patching the FSTP sites entirely.
The camera manager global stores the live camera-task pointer at
`cameraManager + 0x50`. The command reads that pointer, reads the
current reference/target Y at `[cameraTask + 0x54]`, and writes
`referenceY + offset` to `[cameraTask + 0x48]`.

The signature for resolving the camera manager global is:

`A1 ?? ?? ?? ?? 05 94 02 00 00 C3 90 90 90 90 90 A1 ?? ?? ?? ?? 8B 40 50 C3`

The second `A1` operand is the absolute address of the camera-manager
global; dereference it, then dereference `+0x50` to get the camera
task.

This is intentionally a one-shot snap. It does not fight the normal
per-frame camera update, which is what made the earlier vertical-lock
experiment feel bad.

## Feature 3 — battle camera pitch

**Goal (per user):** adjust the downward tilt angle when the
battle camera is locked on. User can still manually move camera
up/down.

**Candidate constants.** The camera task references these
angle-related floats:

| Address       | Value     | Likely role                                  |
|:--------------|:----------|:---------------------------------------------|
| `0x103293F4`  | `1.8849`  | ≈ 0.6π. Possibly max pitch angle (108°).    |
| `0x103293F8`  | `1.41367` | ≈ π/4 × 1.8 ≈ 81°. Possibly min pitch.       |
| `0x10328A30`  | `0.6`     | Pitch damping / scale factor                 |
| `0x103293E4`  | `0.106667`| Possibly per-frame pitch step                |

The angle wraparound constants (`0x103293B0..0x103293B8` = 2π/-π/π)
are clearly modular-arithmetic helpers and probably shouldn't be
patched.

**Patching strategy** (per-site pointer-rewrite, same shape as
existing patches):
1. Find each FMUL/FADD/FSUB referencing one of the candidates.
2. Verify by in-game test (e.g., change `0x10328A30` from 0.6 to
   1.2 and see if pitch behaviour changes).
3. Once confirmed, redirect the operand to a configurable XICamera
   constant.

**Recommended next step:** the user changes the candidate
constants one at a time *temporarily* (manually patch with a
debugger or a quick lua override) and reports which one
corresponds to "pitch tilt." That single experiment narrows
this down to the right knob.

## Feature 4 — battle camera vertical offset

**Goal (per user):** shift the height the battle camera floats
above the locked target. User can still manually move camera
up/down.

**Hypothesis:** `[edi+0x54]` is the lockon-target Y reference. The
camera math at `0x1001FDDE` (`fsub [edi+0x54]`) computes
`cam_y - target_y` — used downstream for clamping. If we add a
**static offset** to the value loaded from `[edi+0x54]`, the
camera's effective vertical relationship with the target shifts.

`[edi+0x54]` is a per-instance member, not a global, so we can't
patch its initial value without scoping per camera task. Better
candidate: find the math that *populates* `[edi+0x54]` (a
write — not visible in the current xref since we only see 3
*read* accesses at 0x1001FDDE / 0x1001FE00 / 0x10020A9F). The
write could be in another function (perhaps when lock-on engages).

**Recommended next step:** spawn a focused decompile read for the
write site to `[edi+0x54]`. Could come from a constant or from
target-position math. If from a constant, we have a clean patch
target.

## Quick reference — for the user

Stuff that's quick to test in-game:

1. **Vertical lock (single-site)**: NOP `0x1001FE15` (3 bytes
   `D9 5F 48` → `DD D8 90`). Smallest change. Reload addon and
   walk into walls to verify camera Y stays put.
2. **Pitch experiment**: in `cheat engine` or x64dbg, change
   `0x10328A30` from `0.6` to `1.2` (double the value). Lock on
   to a mob and look for any pitch behavior change. Report what
   shifts.
3. **Pitch experiment 2**: change `0x103293F4` from `1.8849` to
   `2.5` and observe.
4. **Vertical offset experiment**: while locked on, set a
   debugger watchpoint on `[edi+0x54]` and observe what value
   it takes. Then write a different value while standing still
   and see if camera vertical behavior changes.

Each of these is non-destructive (revert by changing back) and
gives concrete signal for what each constant does. Once we
know, the XICamera-side patch is mechanical.

## What this investigation deliberately *did not* find

- **First-person view distance** — the L1 / Tab-toggled FPS view
  uses a separate code path entirely (probably outside
  `sub_1001ED90`). Not investigated here.
- **The +0x44 base address writes** — we only see `lea` reads,
  not stores. The vec3 is updated through helper functions
  (`sub_10027050`, `sub_10026E50`, `sub_10026ED0`, `sub_1001E690`),
  not direct memory writes. The 5 `[edi+0x48]` writes ARE
  individual stores; they're the leverage point.
- **Free-camera default distance** — same as first-person, likely
  separate code path.
