# XICamera — Patch Targets

> Concrete signatures and patch sites used by XICamera. Pair this
> with `CLIENT_BEHAVIOR.md` (how FFXi's camera works) and the live
> code, which is one shared file plus a thin host per platform:
>
> - `Ashita4/addons/xicamera/xicamera_core.lua` — the site table and
>   all patch logic (copied verbatim into the Ashita 3, Windower 4 and
>   Windower 5 folders; `tools/test_core.lua` checks the copies match)
> - `Ashita3/addons/xicamera/xicamera.lua`, `Ashita4/addons/xicamera/xicamera.lua`,
>   `XICamera.Windower/lua/XICamera.lua`, `Windower5/addons/xicamera/xicamera.lua`
>   — memory adapter, settings, commands, UI
>
> Every patch lands inside `FFXiMain.dll` code and is reverted on unload.

## TL;DR

XICamera never writes the client's own constants. Every value it
controls is a float XICamera allocates once per process ("slot") and
the camera code is re-pointed at it: each site is an x87 instruction
with a 4-byte absolute operand (`D8 0D <addr>` = `fmul`, `D9 05` =
`fld`, `D8 25` = `fsub`, `D8 1D` = `fcomp`, `D8 15` = `fcom`, `D8 05` =
`fadd`, `D8 3D` = `fdivr`), and the operand is swapped for the slot's
address.

Why not overwrite the constant in place, as XICamera did up to 0.7.x?
Because the client's constants are compiler-pooled literals. The "min
camera distance" is the same 3.0 that 36 instructions across the
client read, and the 6.0 max is shared with 12. Writing 22.0 over the
3.0 changed, among others, the clamp on the locomotion animation rate
(the "NPCs run funny" report). See `TOOL_COMPAT_REVIEW.md` §2.

The single in-place code patch is the battle-camera-range clamp: a
2-byte `fld1` replaced with NOPs (`90 90`) while the user has "battle
camera unlocked".

## Signatures

Format: compact hex with `??` wildcards, as the Lua table holds them.
`Op` is the byte offset of the 4-byte operand from the start of the
match. `Head` is the opcode pair in front of the operand, verified
before every write; where the signature does not cover it, the table
states it explicitly. Addresses are RVAs on the May 2026 retail client.

| Slot | Site | Signature | Op | RVA |
|:--|:--|:--|:--|:--|
| min | zoom calc | `D8C9D9C0D8C1D9C2D80D????????D9C3DCC0D8EB` | +0x0A | `0x01C7C4` |
| min | zoom setup | `85C0741AD9442404D80D????????D80D????????D87C` | +0x10 | `0x015373` |
| min | eye follow A | `D815????????DFE0F6C4057A62` | +0x02 | `0x01F8F3` |
| min | eye follow B | `D9442410D81D????????DFE0F6C4057A3E` | +0x06 | `0x01FCB9` |
| min | eye follow C | `D905????????D864241051` | +0x02 | `0x01FCC6` |
| min | eye follow D | `D9FA83C414D9542410D81D????????` | +0x0B | `0x01FD34` |
| min | eye follow E | `D905????????D8642414D944242C` | +0x02 | `0x01FD4B` |
| min | battle camera | `D9442424D80D????????EB1F` | +0x06 | `0x02036E` |
| max | orbit A | `D905????????D8F1D84C2410D95C2410DDD88B16` | +0x02 | `0x01EFC0` |
| max | orbit B | `D905????????D8F1D84C2410D95C2410DDD88B06` | +0x02 | `0x01F128` |
| max | zoom C | `743CE8????????D95C2410E8????????D80D????????` | +0x12 | `0x01F764` |
| max | zoom D | `7440E8????????D95C2410E8????????D80D????????` | +0x12 | `0x01F7B4` |
| max | zoom E | `7E3FE8????????D95C2410E8????????D80D????????` | +0x12 | `0x01F80A` |
| max | zoom F | `7D54E8????????D95C2410E8????????D80D????????` | +0x12 | `0x01F852` |
| max | eye follow G | `EB24D9442410D81D????????` | +0x08 | `0x01FC62` |
| max | eye follow H | `D9442410D825????????51D80D` | +0x06 | `0x01FC75` |
| minBattle | battle min distance | `5152D8442424D905????????D8C1` | +0x08 | `0x02031B` |
| maxBattle | battle max distance | `D8C1D8CAD95C2450D805????????D8C9` | +0x0A | `0x020329` |
| hPan | horizontal pan speed | `D84C24208B068BCED80D` (head `D8 0D`) | +0x0A | `0x01EF5C` |
| vPan | vertical pan speed | `D84C24248B168BCED80D` (head `D8 0D`) | +0x0A | `0x01F02F` |
| jitter | push x | `8D54242C8D44242CD8C9525550` (head `D8 0D`) | +0x0F | `0x01FD66` |
| jitter | push z | same match | +0x1F | `0x01FD76` |
| jitterNeg | push vertical | `D8642410518D44242C` (head `D8 0D`) | +0x0B | `0x01FCD5` |
| battleRange | battle camera range | `D8C9D99C24DC000000DDD8D9442450D8442428D83D` | +0x15 | `0x020342` |
| (lock) | battle range clamp | same match, 2 bytes `D9 E8` | +0x19 | `0x020346` |

Read-only: the camera manager global,
`A1????????0594020000C39090909090A1????????8B4050C3` +0x11, used by
the height snap command.

### Groups

Every reader of one constant is a group, and a group installs
all-or-none: if one min-distance reader is missing, no min-distance
reader is patched, the group is reported off, and the distance setting
has no effect until a signature update. Otherwise a raised distance
would reach some of the camera's math and not the rest.

The jitter sites are individually optional.

### The min-distance readers XICamera leaves alone

Of the 36 readers of the pooled 3.0, XICamera re-points the nine
inside camera code (zoom calc and setup, the eye-follow function,
the battle camera). The rest, including the walk-animation and
NPC-walk-animation multiplies that 0.7.x patched as "followers", and
the battle-sound attenuation, are not camera semantics and now read
the untouched literal. The zone-in flash the follower model was
meant to fix is covered by the zoom-setup site.

### Coexisting with other tools

Rules the core applies at every site (borrowed from TrueFPS):

- Patch only while the head bytes and the operand still hold what
  resolve found. Restore only while the operand still holds XICamera's
  slot. Anything else is left alone and reported (`owned`, `foreign`,
  `refused`).
- An operand already pointing outside the client image is another
  tool's. If the float there is what XICamera would write (1.0 at the
  jitter sites) the site is `neutral`: nothing written, nothing
  restored.
- Slots are never freed. Another tool may have saved a slot address as
  the "original" and will write it back after XICamera unloads.
- Inside a re-check window, once a second, `recheck()` re-applies a
  patch another tool reverted, retakes a neutral site whose owner
  unloaded, and reports a takeover once. Windows open for a minute at
  install and again the first time the character enters the world
  after that (packet 0x000A; later zones open nothing), and for 15
  seconds when the host sees another addon or plugin load or unload (`/load`,
  `/unload`, `/addon load|unload|reload` on Ashita; the console
  commands on Windower 4). Outside a window nothing runs; XICamera
  keeps itself clean at load and unload and otherwise lives with what
  other tools do.
- The Windower 4 DLL swaps operands with a locked compare-exchange;
  the other hosts read, write and read back.

TrueFPS specifically: its "eye push-out" replaces the whole vertical
push instruction with a call, so XICamera's vertical-push signature
stops before that instruction and reports `owned` when TrueFPS got
there first. Its two horizontal-push swaps and XICamera's are the
same operands; whichever loads second sees the other's 1.0 and goes
neutral.

### How the battle range lock patch works

The range signature lands on a function tail shaped like:

```asm
fmul    st(0), st(1)        ; D8 C9
fstp    [esp+0DCh]          ; D9 9C 24 DC 00 00 00
ffree   st(0)               ; DD D8
fld     [esp+50h]           ; D9 44 24 50
fadd    [esp+28h]           ; D8 44 24 28
fdivr   <range_float>       ; D8 3D <addr32>           ; <-- slot operand at +0x15
fld1                        ; D9 E8                   ; <-- 2-byte clamp at +0x19
```

The `fld1` is the clamp source; NOPing it lets the camera travel the
full 360 degrees around a locked target. The lock is written only
while the site holds the other of its two states (`D9 E8` or
`90 90`); anything else is reported and left.

## Default values (FFXi stock)

Read at runtime from the client's literals on the May 2026 retail
build (`tools/analyze_tool_overlap.py`). The April 2026 notes in
`CLIENT_BEHAVIOR.md` listed 2.5 / 4.42 / 8.2 for min, min battle and
max battle; re-read before relying on either.

| Slot | Stock | Comment |
|:--|--:|:--|
| min camera distance | `3.0` | slides with max: `user - (max - min)` |
| max camera distance | `6.0` | the "distance" the user sets |
| min battle distance | `7.2` | slides with battle max the same way |
| max battle distance | `8.6` | the "battle distance" the user sets |
| horizontal pan speed | `0.0279` | user value / 100 |
| vertical pan speed | `0.1067` | user value / 100 |
| jitter | `0.125` / `-0.125` | replaced by `1.0` / `-1.0` |
| battle camera range | `4.0` | user 0..100 |

## Adding a patch target

1. Find the instruction in an unpacked client image and confirm what
   it reads; `tools/analyze_tool_overlap.py --raw` lists every reader
   of a constant so pooled literals are caught before they bite.
2. Generate a signature that is unique, wildcards every imm32 and
   rel32, and avoids fixed bytes other tools write:
   `tools/gen_signatures.py` does this for a list of RVAs, using
   TrueFPS's site table in `smooth.h` as the reference for what it
   writes.
3. Add one row to `Core.SITES` in `xicamera_core.lua`, copy the file
   to the other three ports, and run `tools/test_core.lua` against the
   image.
4. Test in game: load, change the setting, unload, confirm stock.
