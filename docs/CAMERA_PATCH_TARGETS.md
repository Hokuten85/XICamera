# XICamera — Patch Targets

> Concrete signatures and patch sites used by XICamera. Pair this
> with `CLIENT_BEHAVIOR.md` (how FFXi's camera works) and the live
> code in:
>
> - `XICamera.Core/Camera.cpp` (Windower 4 DLL)
> - `Ashita3/addons/xicamera/xicamera.lua`
> - `Ashita4/addons/xicamera/xicamera.lua`
> - `Windower5/addons/xicamera/xicamera.lua`
>
> Every patch lands inside `FFXiMain.dll` and is reverted on unload.

## TL;DR

XICamera adjusts the camera by editing data, not code. There are two
classes of patch:

1. **Direct float overwrites** — for slots that are read every frame
   from a fixed address (`min/max camera distance`, `min/max battle
   distance`, `horizontal/vertical pan speed`). We `VirtualProtect`,
   write a new `float`, and restore on unload.
2. **Pointer-rewrite overrides** — for slots where the game reads
   `mov eax, [<float*>]`. We allocate our own `float` constant and
   rewrite the operand of that load to point at it. The four
   "min-distance follower" sites (zoom-on-zone, walk anim, NPC walk
   anim, battle sound) and the battle-camera-range slot all use this
   shape. The two FLD slots inside the jitter function use it too.

The single in-place code patch is at the battle-camera-range
"clamp" — a 2-byte clamp instruction we replace with NOPs (`90 90`)
when the user requests "battle camera unlocked."

## Signatures

Format: `<bytes>` with `??` wildcards. Offsets are bytes from the
start of the match. Type column is what XICamera does with the
matched site.

| # | Feature              | Signature                                                                | Op | Offset |
|:--|:---------------------|:-------------------------------------------------------------------------|:---|:-------|
| 1 | min camera distance  | `D8 C9 D9 C0 D8 C1 D9 C2 D8 0D ?? ?? ?? ?? D9 C3 DC C0 D8 EB`            | float overwrite via deref | +0x0A |
| 2 | max camera distance  | `D9 44 24 10 D8 25 ?? ?? ?? ?? 51 D8 0D`                                 | float overwrite via deref | +0x06 |
| 3 | min battle distance  | `51 52 D8 44 24 24 D9 05 ?? ?? ?? ?? D8 C1`                              | float overwrite via deref | +0x08 |
| 4 | max battle distance  | `D8 C1 D8 CA D9 5C 24 50 D8 05 ?? ?? ?? ?? D8 C9`                        | float overwrite via deref | +0x0A |
| 5 | h. pan speed         | `D8 4C 24 20 8B 06 8B CE D8 0D ?? ?? ?? ??`                              | float overwrite via deref | +0x0A |
| 6 | v. pan speed         | `D8 4C 24 24 8B 16 8B CE D8 0D ?? ?? ?? ??`                              | float overwrite via deref | +0x0A |
| 7 | zoom on zone-in      | `85 C0 74 1A D9 44 24 04 D8 0D ?? ?? ?? ?? D8 0D ?? ?? ?? ?? D8 7C`      | float* pointer-rewrite    | +0x10 |
| 8 | walk animation       | `0F 85 ?? ?? ?? ?? D8 0D ?? ?? ?? ?? D9 13 D8 1D`                        | float* pointer-rewrite    | +0x08 |
| 9 | NPC walk animation   | `75 14 D9 44 24 10 D8 0D ?? ?? ?? ?? D9 1B 8B 8E`                        | float* pointer-rewrite    | +0x08 |
|10 | battle sound calc    | `D9 5C 24 14 74 1B 48 74 10 D9 44 24 10 D8 0D`                           | float* pointer-rewrite    | +0x0F |
|11 | jitter (push #2, x/z arm) | `8D 54 24 2C 8D 44 24 2C D8 C9 52 55 50`                            | float* pointer-rewrite × 2 | +0x0F, +0x1F |
|12 | battle camera range  | `D8 C9 D9 9C 24 DC 00 00 00 DD D8 D9 44 24 50 D8 44 24 28 D8 3D`         | float* pointer-rewrite + 2-byte NOP patch | +0x15, +0x19 |
|13 | jitter (push #1, vertical arm) | `D8 64 24 10 51 8D 44 24 2C D8 0D ?? ?? ?? ?? D9 1C 24`         | float* pointer-rewrite | +0x0B |

### How the float* pointer-rewrites work

For signatures 7–10, the matched bytes contain a `D8 0D <addr32>`
(`fmul m32fp`) load. The 4-byte operand at the offset listed is the
absolute address the FPU dereferences. Replacing those 4 bytes with
the address of our own `float` constant makes the game read our
value instead.

The same shape (`D8 0D <addr32>`, also a multiply) appears in
signature 11 (jitter) at offsets `+0x0F` and `+0x1F`. Both slots are
inside `sub_1001ED90` (the camera-task per-frame method) and both
multiply by the **damping rate** of the camera-proximity push that
fires when the camera ends up within 3.0 units of the player. We
point both at our `1.0` constant so the lerp completes in one frame
instead of 12.5%-per-frame, eliminating the visible oscillation
when walls force the camera close to the player. See
[`JITTER_INVESTIGATION.md`](JITTER_INVESTIGATION.md) for the full
disassembly.

> Signatures 11 and 13 together cover both proximity-push damping
> arms (horizontal x/z and vertical/single-axis). The other two
> 0.125 readers in `sub_1001ED90` are unrelated math; see
> `JITTER_INVESTIGATION.md`.

### How the battle range lock patch works

Signature 12 lands on the `D8 C9 D9 9C 24 DC 00 00 00 ...` block.
At offset `+0x15` is a `D8 3D <addr32>` (`fdivr m32fp`) — that's
the float* slot we point at our `newBattleRange` constant.

At offset `+0x19` immediately follows a 2-byte FPU stack op
(`D9 E8` = `fld1`) that gets compared against the now-divided value
to clamp battle-camera rotation to the canonical range. Replacing
those 2 bytes with `90 90` (NOPs) bypasses the clamp and lets the
camera rotate the full 360 degrees around the locked target.

Restoration writes the original 2 bytes back.

## Default values (FFXi stock)

These were captured at runtime against the April 2026 retail build.
They're useful as ground truth for the `*_originalXxx` fields and
as a sanity check after a signature scan.

| Slot                        | Default     | Comment                                |
|:----------------------------|------------:|:---------------------------------------|
| min camera distance         |      `2.5` | scales with max via `(max - min)` delta |
| max camera distance         |      `6.0` | the "distance" the user actually sets   |
| min battle distance         |     `4.42` | enforced when in combat                 |
| max battle distance         |      `8.2` | the "battle distance" the user sets     |
| horizontal pan speed scalar |  `0.0294…` | shipped value × 100 ≈ 2.94              |
| vertical pan speed scalar   |   `0.107…` | shipped value × 100 ≈ 10.7              |
| jitter scalar               |    `0.125` | the multiplier we replace with `1.0`    |
| battle camera range         |      `4.0` | XICamera UX maps 0..100 to this slot    |

The 100× scaling on pan speeds matches the integer the user supplies
to the chat command (`hs 3` writes `0.03` to memory). Float division
in the hot path makes a literal `0.03` float fine even if the user
asks for a value like `7.5`.

## What about FOV / mouse sensitivity / cursor / smoothing?

Not currently patched. Open candidates:

- **Camera FOV**: SE's HUD camera and world camera use independent
  projection matrices. The world matrix's FOV constant is set
  during `D3DXMatrixPerspectiveFov` setup; locating its source
  literal is doable but not done.
- **Mouse cursor sensitivity**: separate from in-game pan speed —
  affects the OS pointer when the camera is unlocked. Likely a
  scaler in the input dispatcher; not investigated.
- **Lock-on (L1) zoom multiplier**: the L1-held narrowed view has
  its own distance multiplier; a third "lock-on distance" knob could
  expose it.
- **Smooth zoom transitions**: the inter-frame interpolation rate
  for camera-distance changes; bypassing it would make zoom changes
  instant (could feel jarring; not obviously useful as a default).

These would be additional signatures + a new chat-command surface.
None are blocking for the current feature set.

## Suggested order of attack for new patch targets

1. Identify the FFXi feature you want to alter and find a debug
   string or class name in `FFXiMain.dll.c` that anchors it (e.g.
   the camera task class is `CMoCameraTask`, line 18448 of the
   decomp).
2. Find the math you want to change. Float scalars are typically
   `D8 0D` / `D9 05` (FPU loads from absolute address) — easy to
   pattern-scan.
3. Make the signature long enough to be unique (XICamera's are
   12–21 bytes including 2–4 wildcard bytes for the operand).
4. Add a new `findpattern` site + restore logic in each of the
   three lua addons + Camera.cpp; keep the pattern strings byte-for-
   byte identical across all four.
5. Test: load the addon, run the new chat command, confirm the
   camera changed; unload, confirm the camera is back to stock.
