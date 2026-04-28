# FFXi Camera Behavior — How the Stock Client Computes Camera State

> Phase-1 reference for XICamera. Maps every value XICamera adjusts
> back to the FFXiMain.dll code that reads it, so future patches
> have a coherent model to attach to rather than "this signature
> seems to work."
>
> Sources cited:
>
> - `C:\XI-decompiled\FFXiMain.dll_19042026004046.dll.c` — IDA
>   Hex-Rays output for the April 2026 retail client.
> - The four XICamera implementations in this repo (Ashita 3 / 4
>   lua addons, Windower 4 DLL, Windower 5 lua addon).

## TL;DR

| Question                                | Answer                                                              |
|:----------------------------------------|:--------------------------------------------------------------------|
| Where is the camera "logical state"?    | A `CMoCameraTask` instance scheduled with the rest of the per-frame task list (string ref at `FFXiMain.dll.c:18448`). |
| Where are the distance scalars?         | Floats in the data segment, loaded via `D8 0D <addr32>` from a few specific call sites. XICamera overwrites those four floats. |
| Why are there four "min distance" patch sites? | The min-distance float is *also* read by zoom-on-zone-in setup, walk-anim distance scaling, NPC walk-anim, and battle-sound positioning — four readers. Editing the float alone fixes distance but not the followers; we additionally re-point each of the four `D8 0D` operand slots at our own copy. |
| Is there a per-frame interpolation?     | Yes. The camera lerps between current and target distance frame-to-frame. We do **not** patch the lerp — we just move the target, and the lerp converges naturally. |
| What's "battle range"?                  | A separate float that controls the angular sweep of the camera around a locked target. Stock value 4.0; XICamera exposes 0..100. |
| What's "jitter"?                        | A `0.125` scalar applied to camera distance during quick movement, to give the impression of rapid camera adjustment. We replace with `1.0` (no shrink). |

## 1. The CMoCameraTask machinery

`FFXiMain.dll.c:18448` defines `off_10329B34 = "CMoCameraTask"` — the
debug name string for FFXi's camera task. A few hundred bytes earlier
in the same vtable area are similar entries (`CYyTexBase`,
`CMoAttachments`, `CMoCelestial`, …) — the per-frame task system.

Tasks are scheduled by name at startup; `off_103532B8[6]` is just the
string `"Camera"` in the worker-thread task list (`FFXiMain.dll.c:24725`).
The task system's per-frame tick wakes each registered task, the
camera's tick reads input + the current distance scalars + the
session's lock-on target and emits a view matrix.

We don't hook the task. We just edit the data the task reads each
frame.

## 2. Distance scalars

Camera distance lives in two pairs of floats:

```
+----------------------+    Min camera distance (data-seg float)
|  g_MinCameraAddress  | <- D8 0D xx xx xx xx  (FPU loads via addr32)
+----------------------+
+----------------------+    Max camera distance
|  g_MaxCameraAddress  | <- D8 25 xx xx xx xx
+----------------------+
+----------------------+    Min battle distance
|  g_MinBattleAddress  | <- D9 05 xx xx xx xx
+----------------------+
+----------------------+    Max battle distance
|  g_MaxBattleAddress  | <- D8 05 xx xx xx xx
+----------------------+
```

The shipped values (April 2026 retail):

- Min camera =  `2.5`
- Max camera =  `6.0`
- Min battle =  `4.42`
- Max battle =  `8.2`

The user-facing "distance" knob in XICamera writes the *max* slot to
the user's value and the *min* slot to `user - (max - min)` — i.e.
preserves the original min/max delta but slides both. This keeps the
camera-zoom-out range intact (zoom in via mouse wheel still has the
original ~3.5 unit travel between min and max).

## 3. The four "min distance follower" sites

`g_MinCameraAddress` is read from more than just the camera task.
Four separate functions also read it:

| Site                     | What reads it                                     |
|:-------------------------|:--------------------------------------------------|
| Zoom-on-zone-in setup    | Resets camera to "min" briefly when a zone loads. |
| Walk animation           | Scales walk-cycle FOV/distance heuristics.        |
| NPC walk animation       | Same logic, NPC variant.                          |
| Battle sound calculation | Emit-distance attenuation for combat sounds.      |

If you only patch `g_MinCameraAddress`, those four readers continue
to use the stock min and produce visual hitches — most notably,
the zone-in flash where the camera snaps to stock min for a frame
before lerp-ing to whatever max distance you set.

XICamera fixes this by re-pointing each of the four `D8 0D` operand
slots at its own `g_NewMinDistance` copy. After patching:

```
+----------------------+
|  g_NewMinDistance    | <-- our own float, equals g_OriginalMinDistance
+----------------------+
                            ^   ^   ^   ^
                            |   |   |   |
                  zoom_setup walk npc sound  (all four readers)
```

Editing `g_NewMinDistance` updates all four readers atomically.

## 4. Pan speeds

Two scalars live in the data segment:

- Horizontal pan speed (`D8 0D <addr32>` at sig `D8 4C 24 20 8B 06 8B CE D8 0D`)
- Vertical pan speed   (`D8 0D <addr32>` at sig `D8 4C 24 24 8B 16 8B CE D8 0D`)

Stock floats are `~0.0294` (h) and `~0.107` (v). The chat command
takes a friendly integer (the "3" in `/camera hs 3`) and writes
`<value> / 100.0` so the user-facing scale is comprehensible.

Vertical pan speed has an `autoCalcVertSpeed` mode (default ON):
when the user changes camera distance, vertical pan is rescaled by
`<defaultVert> * <newDistance> / 6.0` to keep the angular pan speed
similar across distance changes. Manually setting `vspeed N`
disables `autoCalcVertSpeed`.

## 5. Jitter (camera-proximity push)

The "jitter" the user sees against walls is **not** a movement-shake
effect — it's the **lerp damping of a camera-proximity push** that
fires every frame whenever the camera ends up closer than 3.0 units
to the player. The push tries to walk the camera back out to 3.0
units away, at a rate of 12.5% per frame (the `0.125` scalar).
When walls constrain the camera so it can never reach 3.0, the push
fires every frame and produces the visible oscillation as the
"near-wall" condition flickers with player movement.

The signature `8D 54 24 2C 8D 44 24 2C D8 C9 52 55 50` lands inside
`sub_1001ED90` (the camera task `Update` method) at the horizontal
two-axis arm of the push. The two `D8 0D <0.125>` slots at offsets
`+0x0F` and `+0x1F` are the per-component damping multiplications
for x and z. XICamera redirects both to a `1.0` constant, making
the push close the gap in one frame — visible as a hard snap to
"safe distance" instead of a soft lerp, which empirically
eliminates the oscillation.

The function actually contains a **second** proximity push (the
single-axis vertical arm at `VA 0x1001FCD5`) that uses `-0.125` and
is currently unpatched. See
[`JITTER_INVESTIGATION.md`](JITTER_INVESTIGATION.md) for the full
disassembly and a proposed signature to extend the patch.

There's no UX knob for jitter intensity today; it's binary (on by
default prior to XICamera, off when XICamera is loaded).

## 6. Battle camera range and lock

When the player is locked on a target, the camera sweeps around the
target rather than around the player. The angular range of that
sweep is governed by a single float (stock `4.0`) and a clamp.

The signature `D8 C9 D9 9C 24 DC 00 00 00 DD D8 D9 44 24 50 D8 44 24 28 D8 3D`
lands on a function whose tail is shaped like:

```asm
fmul    st(0), st(1)        ; D8 C9
fstp    [esp+0DCh]          ; D9 9C 24 DC 00 00 00
ffree   st(0)               ; DD D8
fld     [esp+50h]           ; D9 44 24 50
fadd    [esp+28h]            ; D8 44 24 28
fdivr   <range_float>       ; D8 3D <addr32>           ; <-- patch site at +0x15
fld1                          ; D9 E8                   ; <-- 2-byte clamp at +0x19
fcom    st(1)
...
```

The `fdivr <range_float>` operand at `+0x15` is the float* we
re-point. The `fld1` at `+0x19` is the clamp source — we replace
its 2 bytes with `90 90` (NOPs) to bypass the clamp when the user
asks for "battle range unlocked."

XICamera maps 0..100 to that float. Higher values widen the sweep;
above ~50 the camera can travel past 180° around the target. With
the clamp NOPed, full 360° rotation works.

## 7. What we deliberately don't touch

- **The camera task itself** — too much state, too many input
  paths, no obvious gain.
- **The view matrix construction** — derived from the scalars we
  already control; touching it would just recompute what the game
  already does.
- **Input dispatch / WM_MOUSEMOVE handling** — separate from camera
  pan speed (it's the OS pointer scaler, used when the camera is
  unlocked from the player). Adjusting it would be a separate
  feature.
- **FOV** — see CAMERA_PATCH_TARGETS.md §4 ("What about FOV...");
  candidate, not implemented.

## 8. Citations index

| Symbol / address                | Location              | Role                                  |
|:--------------------------------|:----------------------|:--------------------------------------|
| `"CMoCameraTask"` string        | `FFXiMain.dll.c:18448` | Camera task class debug name          |
| `"Camera"` task list entry      | `FFXiMain.dll.c:24725` | Worker-thread task name               |
| `D8 0D <min_distance_addr>`     | sig 1 (above)          | Min camera distance load              |
| `D8 25 <max_distance_addr>`     | sig 2                  | Max camera distance load              |
| `D9 05 <min_battle_addr>`       | sig 3                  | Min battle distance load              |
| `D8 05 <max_battle_addr>`       | sig 4                  | Max battle distance load              |
| `D8 0D <h_pan_speed_addr>`      | sig 5                  | Horizontal pan scalar load            |
| `D8 0D <v_pan_speed_addr>`      | sig 6                  | Vertical pan scalar load              |
| zoom-on-zone-in `D8 0D` operand | sig 7 +0x10            | Min-distance follower #1              |
| walk-anim `D8 0D` operand       | sig 8 +0x08            | Min-distance follower #2              |
| NPC walk-anim `D8 0D` operand   | sig 9 +0x08            | Min-distance follower #3              |
| battle-sound `D8 0D` operand    | sig 10 +0x0F           | Min-distance follower #4              |
| jitter `D9 05` slots            | sig 11 +0x0F, +0x1F    | 0.125 jitter scalar                   |
| battle-range `D8 3D` operand    | sig 12 +0x15           | Battle-camera range float             |
| battle-range `D9 E8` clamp      | sig 12 +0x19           | 2-byte FPU clamp (NOPed when unlocked) |
