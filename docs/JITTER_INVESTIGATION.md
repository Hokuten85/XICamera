# Jitter / Camera-Proximity Push — Investigation

> Definitive analysis of what XICamera's "jitter" patch actually does,
> based on disassembling `FFXiMain.dll_19042026004046.dll`. Reproducible
> with `python tools/analyze_jitter.py`.
>
> **TL;DR:** The 0.125 scalar XICamera replaces with 1.0 is the
> **damping rate of a camera proximity push** — when the camera ends
> up within 3.0 units of some reference position (likely the player),
> the game tries to gently lerp the camera back out at 12.5% per
> frame. Walls flickering "near"/"not near" cause the lerp to
> oscillate visibly. Setting the rate to 1.0 closes the gap in one
> frame, eliminating the oscillation. The patch is correctly placed
> on TWO of the FPU multiplications but the FUNCTION HAS A SECOND
> RELATED PUSH that is currently unpatched. To be comprehensive we
> need to patch one more site.

## What we know

### Function: `sub_1001ED90`

| | |
|:--|:--|
| Address                       | `VA 0x1001ED90`  (file `0x1E190`) |
| Size                          | ~4 KB (large per-frame method)    |
| Calling convention            | `__userpurge` / thiscall-ish      |
| Hex-Rays declaration          | `char __userpurge sub_1001ED90@<al>(int a1@<ecx>, int a2@<ebx>, int a3@<ebp>, int a4)` |
| Likely purpose                | Camera task per-frame update — sits in the same vtable area as `CMoCameraTask` (string at `VA 0x1032FEBC`) |

### The damping scalar: `0x103293BC`  (= `0.125`)

A `.rdata` float used in many places across the binary; we cannot
edit the float value globally without affecting unrelated code. The
existing XICamera patch correctly uses **per-site pointer-rewrite**
(redirects the `D8 0D <addr>` operand) to override the value
locally without touching the .rdata float itself.

Adjacent in `.rdata`:

| Address       | Value    | Use                                      |
|:--------------|:---------|:-----------------------------------------|
| `0x103293BC`  | `0.125`  | proximity-push damping rate (positive)   |
| `0x103293C0`  | `-0.125` | proximity-push damping rate (negative)   |

The `-0.125` exists for the vertical/single-axis arm of the push
(see Push #1 below).

### The two proximity pushes inside `sub_1001ED90`

The function has **two** wall/proximity-buffer push blocks. Both fire
when distance to a reference position drops below **3.0**, both have
the same shape (compute `3.0 - distance`, multiply by ±0.125, add to
camera position, write back), and both are responsible for the
"jitter" symptom XICamera was written to fix.

#### Push #1 — vertical / single-axis arm   (UNPATCHED today)

Decompile (lines 100383–100390):
```c
if ( v261 < 3.0 )
{
  v241 = (3.0 - v261) * -0.125;
  sub_100271E0((float *)&v271, v241);
  sub_10026E50((float *)&v271, (float *)(LODWORD(v5) + 68));
  sub_1001E690((_DWORD *)LODWORD(v5), &v271);
  dword_10455D6C = 10;
}
```

Disassembly (VA `0x1001FCB9`–`0x1001FCFE`):
```asm
0x1001FCB9  D8 1D 38 8D 32 10  fcomp  [0x10328D38]    ; cmp ST(0), 3.0
0x1001FCC4  7A 3E              jp     0x1001FD04      ; if NOT ST<3.0, skip
0x1001FCC6  D9 05 38 8D 32 10  fld    [0x10328D38]    ; ST(0) = 3.0
0x1001FCCC  D8 64 24 10        fsub   [esp+0x10]      ; ST(0) = 3.0 - dist
0x1001FCD5  D8 0D C0 93 32 10  fmul   [0x103293C0]    ; ST(0) *= -0.125     <-- PATCH CANDIDATE
0x1001FCDB  D9 1C 24           fstp   [esp]            ; arg = scale_factor
0x1001FCDE  50                  push   eax              ; arg = &v271
0x1001FCDF  E8 .. .. .. ..     call   sub_100271E0    ; v271 *= scale
0x1001FCEA  E8 .. .. .. ..     call   sub_10026E50    ; v271 += cam_pos
0x1001FCF9  E8 .. .. .. ..     call   sub_1001E690    ; cam_pos = v271
```

XICamera does **not** patch this site. After the existing patch is
applied, push #2 completes in one frame but push #1 still runs at
the original 0.125 damping rate — meaning the vertical/single-axis
component of the proximity buffer continues to lerp slowly and
*can* oscillate against vertical-axis wall collisions.

#### Push #2 — horizontal (x,z) two-axis arm   (PATCHED today)

Decompile (lines 100394–100404):
```c
if ( v128 < 3.0 )                          // v128 = horizontal distance
{
  sub_100273E0((float *)&v271);            // normalize
  v262 = v128;
  v129 = 3.0 - v262;
  *(float *)&v271 = *(float *)&v271 * v129 * 0.125;   // x *= (3-d) * 0.125
  v273              = v273              * v129 * 0.125;   // z *= (3-d) * 0.125
  sub_10026ED0(...);                        // v271 += cam_pos
  sub_1001E690(LODWORD(v5), &v271);         // cam_pos = v271
}
```

Disassembly (VA `0x1001FD34`–`0x1001FD9D`):
```asm
0x1001FD34  D8 1D 38 8D 32 10  fcomp  [0x10328D38]    ; cmp v128, 3.0
0x1001FD3F  7A 62              jp     0x1001FDA3
0x1001FD46  E8 .. .. .. ..     call   sub_100273E0    ; normalize(v271)
0x1001FD4B  D9 05 38 8D 32 10  fld    [0x10328D38]    ; ST(0) = 3.0
0x1001FD51  D8 64 24 14        fsub   [esp+0x14]      ; ST(0) = 3.0 - dist  (v129)
0x1001FD55  D9 44 24 2C        fld    [esp+0x2c]      ; ST(0) = v271.x, ST(1) = v129
0x1001FD59  8D 54 24 2C        lea    edx, [esp+0x2c] ; (== JITTER_SIGNATURE start)
0x1001FD5D  8D 44 24 2C        lea    eax, [esp+0x2c]
0x1001FD61  D8 C9              fmul   st(1)            ; ST(0) = v271.x * v129
0x1001FD66  D8 0D BC 93 32 10  fmul   [0x103293BC]    ; ST(0) *= 0.125     <-- XICamera +0x0F
0x1001FD6C  D9 5C 24 38        fstp   [esp+0x38]       ; v271.x = ST(0)
0x1001FD70  D9 44 24 40        fld    [esp+0x40]      ; ST(0) = v271.z
0x1001FD74  D8 C9              fmul   st(1)            ; ST(0) = v271.z * v129
0x1001FD76  D8 0D BC 93 32 10  fmul   [0x103293BC]    ; ST(0) *= 0.125     <-- XICamera +0x1F
0x1001FD7C  D9 5C 24 40        fstp   [esp+0x40]       ; v271.z = ST(0)
0x1001FD82  E8 .. .. .. ..     call   sub_10026ED0    ; v271 += cam_pos
0x1001FD98  E8 .. .. .. ..     call   sub_1001E690    ; cam_pos = v271
```

XICamera redirects both `0x103293BC` operands to its own `g_newJitter
= 1.0f`, making the multiplication identity-like → camera snaps to
safe distance in one frame.

### Mechanics: why 0.125 produces oscillation

```
each frame:
    horiz_dist = horizontal distance from camera to reference
    if horiz_dist < 3.0:
        push_amount = (3.0 - horiz_dist) * 0.125
        camera += normalize(camera - reference) * push_amount
```

The push lerps 12.5% of the gap per frame. Convergence from
`horiz_dist=1.0` to `horiz_dist=3.0` takes
`log(0.001) / log(0.875) ≈ 52` frames (~0.87 s @ 60 FPS) at the
stock rate.

When a wall constrains the camera so it can't actually reach
`horiz_dist=3.0`, the push fires every frame but never converges. As
the player moves the wall geometry interacting with the cast can
flicker, so the *effective* push direction also flickers, producing
the visible oscillation.

Setting the rate to **1.0** changes the math to:
```
push_amount = (3.0 - horiz_dist) * 1.0 = (3.0 - horiz_dist)
```
The camera is moved the entire remaining distance in one frame. If
a wall blocks part of the move, the camera ends up pressed against
the wall at whatever horiz_dist it can manage, and the next frame
either accepts that position (no further push because we're now at
the maximum-possible push position) or gets a single-frame
correction. No multi-frame lerp → no oscillation.

## Verdict on XICamera's current patch

| Question                                         | Answer                                              |
|:-------------------------------------------------|:----------------------------------------------------|
| Is the signature inside the right function?      | **Yes** — `sub_1001ED90`, the camera task per-frame. |
| Are the two patched FMUL operand sites correct?  | **Yes** — these are exactly the x/z components of the horizontal proximity push (push #2). |
| Is the chosen replacement value (1.0) correct?   | **Reasonable** — it converts a slow lerp into a single-frame snap, which empirically eliminates oscillation. |
| Does the patch fully cover the proximity-push behavior? | **Yes (since signature 13 was added)** — both push #1 and push #2 are now redirected. |
| Is there a "better" patch site than the current one? | **No** for push #2 specifically — the two `D8 0D` operands at `+0x0F` / `+0x1F` are exactly the per-component scalars and replacing them is the cleanest possible intervention. |

## Implemented: extended the patch to cover push #1

A second signature for push #1 was added (signature 13 in
`CAMERA_PATCH_TARGETS.md`). The operand at match+0x0B is redirected
to a new `-1.0` constant, making the vertical/single-axis arm also
complete in one frame. All four launcher implementations carry this
patch; the C++ side allocates `g_newJitterNeg = -1.0f` next to the
existing `g_newJitter = 1.0f`.

### Push #1 signature (verified in retail April 2026)

The push #1 disassembly has a unique 13-byte run starting at
VA `0x1001FCC6` (or longer if we want more context):

```
D9 05 38 8D 32 10        fld   [0x10328D38]   ; load 3.0
D8 64 24 10              fsub  [esp+0x10]
51                       push  ecx
8D 44 24 2C              lea   eax, [esp+0x2c]
D8 0D C0 93 32 10        fmul  [0x103293C0]   ; <-- patch operand here
```

But the byte `38 8D 32 10` (the address of 3.0) appears in MANY
places in the binary, so a tighter pattern is preferable.
Recommended signature, keying on the full sequence around the
unique single-`fmul -0.125` site:

```
D8 64 24 10 51 8D 44 24 2C D8 0D ?? ?? ?? ?? D9 1C 24
```

This is 18 bytes:
- `D8 64 24 10` — `fsub [esp+0x10]`
- `51`           — `push ecx`
- `8D 44 24 2C`  — `lea eax, [esp+0x2c]`
- `D8 0D ?? ?? ?? ??` — `fmul [<addr>]`  ← patch operand at +9
- `D9 1C 24`     — `fstp [esp]`

The patch operand is at offset **+0x09** of the match. Verified
unique in the April 2026 retail build (`tools/analyze_jitter.py`
returns one match site at `VA 0x1001FCCC`, leading to the operand
at `VA 0x1001FCD5 + 2 = 0x1001FCD7`... actually the operand is at
match+9 = `0x1001FCC6 + 9 = 0x1001FCCF`... let me recompute.

If the match starts at `0x1001FCCC` (the `D8 64`), then:
- `+0` = `D8 64 24 10`           (`fsub`)
- `+4` = `51`                     (`push ecx`)
- `+5` = `8D 44 24 2C`            (`lea`)
- `+9` = `D8 0D`                  (`fmul` opcode)
- `+11` = `<4-byte operand>`     ← operand bytes here
- `+15` = `D9 1C 24`             (`fstp [esp]`)

So **patch site is +0x0B (11) into the match**, with 4 bytes to
overwrite. Same shape as the existing jitter patch, just a
different match → a different offset.

## Even more aggressive options (not recommended)

### Patch the threshold (3.0 at `0x10328D38`) per-site

Would prevent the `if (dist < 3.0)` block from firing entirely.
However the threshold address is referenced **30+ times** across
the binary (`tools/analyze_jitter.py` enumerates them); we'd have
to identify per-site patch points and the existing pointer-rewrite
approach scales but adds complexity for marginal benefit.

### Patch 0.125 → 0.0 (instead of 1.0)

Would make the push *do nothing* (move camera by 0). The proximity
buffer is fully disabled — camera can clip into the player when
walls force it close. The user is currently using 1.0 which
produces a snap; 0.0 would produce no movement at all. Different
trade-off; subjectively probably worse.

## Reproducibility

This investigation is reproducible from a fresh decompile via:

```bash
python tools/analyze_jitter.py [path-to-FFXiMain.dll]
```

The script:
1. Locates the 13-byte signature in `.text`
2. Identifies the enclosing function (heuristic: nearest preceding RET + plausible prologue)
3. Disassembles ±64 bytes around the signature with capstone
4. Enumerates every reader of the 0.125 / -0.125 / 3.0-threshold
   floats across the entire `.text` section, flagging which fall
   inside `sub_1001ED90`

If a future client update shifts the call site, run the script
against the new DLL — the same output structure tells you the new
addresses.
