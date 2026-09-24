# Coexisting with other memory-patching tools (TrueFPS review)

> **Status (2026-09-24):** implemented in 0.8.0. The shared
> `xicamera_core.lua` inverts the constant model (item 1), guards
> every write and restore (2), never frees slots (3), recognises
> foreign and owned sites (4), keeps per-site state with reasons (5),
> reports on request what other tools changed after load without
> re-applying anything (6, deliberately reduced: XICamera lets other
> tools win after load),
> and no longer touches `.rdata` (8) or
> assumes one original per group (9). The Windower 4 DLL writes with
> locked exchanges and offers `compare_exchange_uint32` (7); the
> Ashita and Windower 5 hosts have no atomic primitive and use
> read-write-verify. `tools/test_core.lua` exercises all of it
> against an unpacked client image. The analysis below is kept as
> the record of why.

Date: 2026-09-24. Client: retail FFXiMain.dll, May 2026 build (unpacked
memory image). Reproduce every table here with:

```
python tools/analyze_tool_overlap.py <unpacked FFXiMain image> --raw
```

Context: a user reported XICamera misbehaving alongside
[TrueFPS](https://github.com/SQLCommit/TrueFPS) (an Ashita 4 plugin that
re-times ~58 client routines, many of them in the camera code), and a
separate report (ffxiah thread, 2026-08-26) of NPCs "running around
really funny" after logging in with a large distance set. This document
records what the two tools actually collide on, what TrueFPS does that
XICamera should copy, and the root cause candidate for the NPC report.

## 1. Where the two tools touch the same bytes

TrueFPS locates every site by its own patterns; all 58 resolve on this
build, as do all 16 XICamera signatures. Intersecting the write ranges:

| XICamera site | RVA written | TrueFPS site | Kind of TrueFPS write |
|:--|:--|:--|:--|
| jitter push #2, x operand | `0x01FD68`+4 | "eye horizontal push x" | swaps the same 4-byte operand |
| jitter push #2, z operand | `0x01FD78`+4 | "eye horizontal push z" | swaps the same 4-byte operand |
| jitter push #1 operand    | `0x01FCD7`+4 | "eye push-out"          | replaces the whole 6-byte `fmul` at `0x01FCD5` with `call stub; nop` |

Nothing else overlaps. In particular, no TrueFPS site writes the six
float constants XICamera edits in place, and TrueFPS deliberately keeps
the pan-speed sites read-only because they overlap XICamera's
signatures.

What happens per load order today:

- **TrueFPS first, then XICamera, push #2.** XICamera's "original
  pointer" is really TrueFPS's slot. XICamera overwrites both operands
  with its 1.0 slot; TrueFPS notices, recognises 1.0 outside the client
  image as "another tool's, no decay to pace", and leaves it. On XICamera
  unload the TrueFPS slot pointer is written back; TrueFPS reclaims it,
  or, if TrueFPS already unloaded, the slot still exists because TrueFPS
  never frees that page. Works, but only because TrueFPS anticipated
  XICamera's exact behaviour.
- **TrueFPS first, then XICamera, push #1.** XICamera's signature
  requires `D8 0D` at `0x01FCD5`; TrueFPS has put `E8` there. The scan
  fails, XICamera logs "jittersPush1Sig not found; vertical-axis jitter
  still active" and continues. Silent feature loss, and the log blames a
  client update.
- **XICamera first, then TrueFPS, push #1.** TrueFPS reads the operand
  (now XICamera's slot outside the image) and refuses the site, taking
  its whole "camera eye follow" routine down to whole ticks. If a future
  TrueFPS accepts the external operand and installs its call, XICamera's
  unload writes 4 bytes into the middle of that `call` (its rel32) and the
  client crashes on the next frame. XICamera never checks that the
  instruction still holds what it patched before restoring.

## 2. The in-place constant edits hit pooled literals

XICamera writes the user's values straight into the client's float
constants. Those constants are compiler-pooled `.rdata` literals, shared
by every function that uses the same number:

| Constant | RVA | Value on this build | Readers in `.text` | Redirected by XICamera |
|:--|:--|:--|:--|:--|
| min camera distance | `0x328D38` | 3.0 | **36** | 4 (zoom setup, walk anim, NPC walk anim, battle sound) |
| max camera distance | `0x3293E8` | 6.0 | **12** | 0 |
| min battle distance | `0x3293A8` | 7.2 | 1 | n/a |
| max battle distance | `0x3293A4` | 8.6 | 1 | n/a |
| horizontal pan speed | `0x3293EC` | 0.0279 | 1 | n/a |
| vertical pan speed | `0x3293E4` | 0.1067 | 1 | n/a |

At the default distance of 6 the min slot is rewritten to 6 - (6 - 3) = 3,
i.e. unchanged, which is why the defaults never show a problem. At any
other distance every `3.0f` in the client changes. With `/cam d 25` the
literal becomes 22.0 and the literal 6.0 becomes 25.0.

**The NPC animation report.** The walk-rate function (`0x0C8A00` area,
the same function TrueFPS patches for "locomotion animation rate" and
"movement deadband fine") clamps a per-entity locomotion value with the
pooled 3.0 literal, and XICamera does not redirect that read:

```
0x0C8A40  fcom  dword ptr [3.0]      ; if value > 3.0
0x0C8A4D  jne   0x0C8A57
0x0C8A51  fld   dword ptr [3.0]      ;     value = 3.0
0x0C8A57  fst   dword ptr [esi+0x824]
```

The two `fmul [3.0]` XICamera *does* redirect (`0x0C8AC8`, `0x0C8BE2`)
sit a hundred bytes further down in the same function. So with a raised
camera distance, the clamp moves from 3.0 to (distance - 3) while the
multipliers stay at 3.0. The value at `+0x824` feeds an exponential
moving average (TrueFPS's "animation rate old/new" at `0x0C8B36`), which
explains the login-only symptom: at login or zone-in entities are placed
with large one-frame position jumps, the clamp normally caps the spike,
and with the clamp at 22 the EMA takes a long time to settle. Loading
after login skips the spike. The reporter mentioned *battle* distance;
on this build the battle constants have no other readers, so either
their camera distance was raised too or the `/cam status` output is
needed to say more.

Other readers of the 3.0 literal outside the camera code, all currently
affected by any non-default distance: `0x1254DE`, `0x1259F6`, `0x162D34`,
`0x174CDA`-`0x174D32` (four in one function), `0x1EEE6F`, `0x1EEE80`,
`0x2AC04F`-`0x2AC07D`, `0x2B48EA`, `0x2CFAE0`, `0x2D5C5D`-`0x2D65A0` (six),
`0x2E261B`-`0x2E2A06` (three). Readers of the 6.0 literal outside the
camera code: `0x03BA89`, `0x04F776`, `0x12C5EE`, `0x2CFAFA`.

Camera-code readers of 3.0 that must keep following the user's distance
if the model is inverted: `0x015373` (zoom setup), `0x01C7C4`
(minDistance site), `0x01F8F3`, `0x01FCB9`, `0x01FCC6`, `0x01FD34`,
`0x01FD4B` (eye follow; the push-out rest point TrueFPS calls "a
camera-distance constant other tools rewrite"), `0x02036E`, `0x036C6A`
(battle sound). Camera-code readers of 6.0: `0x01EFC0`, `0x01F128`,
`0x01F764`, `0x01F7B4`, `0x01F80A`, `0x01F852`, `0x01FC62`, `0x01FC75`.

Note: docs/CLIENT_BEHAVIOR.md lists April 2026 values (min 2.5, min
battle 4.42, max battle 8.2); this May 2026 image holds 3.0, 7.2 and
8.6. Re-check before relying on either.

## 3. What TrueFPS does that XICamera should copy

Ordered by how much they matter for the reports above.

1. **Invert the constant model.** Leave pooled literals untouched.
   Allocate XICamera's own min and max floats and re-point only the
   camera code's reads at them (the lists in section 2), the same
   operand-rewrite XICamera already uses for the four followers. This
   removes the whole collateral class, and the four follower slots
   become unnecessary because the literal is no longer changed.
2. **Write only over what you expect; restore only what is still
   yours.** TrueFPS's `swapCode32` is a compare-exchange: it replaces
   the operand only while it still holds the saved bytes, and removal
   only while it still holds TrueFPS's bytes. If neither, the site is
   left alone and logged as another tool's. XICamera should read back
   the 4 bytes (and the opcode in front of them) before every write and
   before every restore. This is what prevents the push #1 crash
   scenario.
3. **Never free the override slots.** TrueFPS keeps the page holding its
   float cells for the life of the process because "other tools may
   restore saved pointers after unload", which is exactly what XICamera
   does with TrueFPS's slot today. XICamera's Lua deallocs its slots on
   unload; a tool that saved one of those pointers as "original" will
   write it back into client code and the next read faults. The Ashita
   Lua also deallocs `newMinDistanceConstant` four times (once per
   follower); that is a bug on its own.
4. **Recognise a foreign operand instead of failing.** Before patching,
   look at where the operand already points. Inside the client image:
   original, patch it. Outside, holding the value we would write (1.0
   for the jitter sites): another tool did our job, leave it and report
   "left as another tool set it". Outside with any other value: adopt or
   skip, but log which. For push #1, `E8` at the site means TrueFPS owns
   the instruction; log that rather than "signature not found".
5. **Per-site status with reasons, kept for the session.** TrueFPS
   tracks found / patched / neutral / kept / stuck per site and prints
   one line per state change. The new settings window's "Patch status"
   list is the first step; the next is recording *why* (not found,
   ambiguous, owned by another tool, restore refused).
6. **Re-check about once a second and self-recover.** TrueFPS re-reads
   its sites every 60 frames: if a neutral site's operand points back at
   the client's own value (the other tool unloaded) it retakes the site;
   if its own patch was overwritten it logs once. XICamera could do the
   same from `d3d_present`, cheaply, and would then survive either unload
   order.
7. **Atomic code writes.** The battle-range unlock replaces the 2-byte
   `fld1` with `90 90`. The C++ core does that as a plain store; use a
   16-bit interlocked exchange (any alignment works on x86 with a lock
   prefix). The 4-byte operand writes are atomic in practice unless they
   straddle a cache line; check `(addr & 63) <= 60` or use
   `InterlockedCompareExchange`. Lua has no atomic primitive, which is
   one more argument for doing the writes in the C++ core.
8. **Restore page protection.** The Lua `unprotect` leaves the `.rdata`
   page writable for the process lifetime. The C++ core already restores
   the old protection after each write; the Lua path should too (or stop
   writing `.rdata` at all, per item 1).
9. **Save each site's own original bytes.** The Lua restores
   `originalMinDistancePtr` (read at the zoom-setup site) into all four
   followers. Read and keep the original operand per site.

## 4. Suggested order of work

1. Item 1 (invert the constant model). Fixes the NPC report class and
   ends the dependence on TrueFPS following XICamera's constant edits.
2. Items 2, 3 and 9 together (guarded write, guarded restore, no
   dealloc, per-site originals). Small, mechanical, and they close the
   crash path.
3. Item 4 for the three jitter sites, with the log lines from item 5.
4. Item 6 if the once-a-second re-check proves cheap enough in Lua.

For the ffxiah reporter: ask for the full `/cam status` output and
whether TrueFPS or another FPS tool is loaded, and whether the symptom
persists with `/cam d 6`.
