# Testing XICamera

How to verify each feature is live after loading. Every check
below can be done in-game; most take under a minute.

**One constraint up front:** chat commands only work once your
character is in-world. The title / lobby / character-select screens
don't accept chat input. Log in, then run the checks.

## Quick self-check

Run `/camera status` (Ashita) or `//camera status` (Windower). You
should see something like:

```
- status
-  cameraDistance:     6
-  battleDistance:     8.2
-  battleRange:        4
-  battleRangeLocked:  true
-  horizontalPanSpeed: 3
-  verticalPanSpeed:   10.7
-  autoCalcVertSpeed:  true
-  saveOnIncrement:    false
```

If the addon failed to load, you'll see an error in the chat log
with the name of the signature that didn't match. See "If a
signature fails" below.

## Camera distance (`/camera distance N` or `/camera d N`)

**Expect:** the third-person camera moves to N units behind the
character. Default `6`.

**Quick verify:**

1. Stand still in a town. Use mouse-wheel to confirm you can zoom
   between min and max. Note where "fully zoomed out" lands.
2. `/camera distance 12` — fully-zoomed-out should now be ~6 units
   farther back. Mouse-wheel should still let you zoom *in* by the
   same amount as before.
3. `/camera distance 6` — should snap back to stock.

**Subtle gotcha:** XICamera preserves the original *delta* between
min and max. So setting `distance 12` widens the zoom-out range
but doesn't change how close you can zoom in. If you set distance
below the stock min (`distance 1`), the math still holds but the
camera will clip into the player model.

## Battle distance (`/camera battle N` or `/camera b N`)

**Expect:** when locked on a target (R3 click / `/lockon`), the
combat camera moves to N units. Default `8.2`.

**Quick verify:**

1. Lock on to any harmless mob.
2. `/camera battle 12` — combat camera retreats; you should see
   more terrain around you and the target.
3. Unlock — you snap back to whatever camera distance is set.
4. `/camera battle 8.2` — back to stock.

## Pan speeds (`/camera hs N`, `/camera vs N`)

**Expect:** mouse / right-stick camera rotation speed changes.

**Quick verify:**

1. Right-click-drag to rotate the camera. Note the speed.
2. `/camera hs 6` — horizontal rotation should be roughly twice
   as fast.
3. `/camera vs 20` — vertical pitch should be roughly twice as
   fast. **This forces `autoCalcVertSpeed off`** — note the status
   line if you want it back on.
4. `/camera acv` to toggle `autoCalcVertSpeed` back on.

**Why "100×"?** The chat command takes a friendly integer; the
underlying scalar is `<value> / 100`. Stock values map to roughly
3 (h) and 10.7 (v).

## Vertical height snap (`/camera vheight N` or `/camera vh N`)

**Expect:** the camera height snaps once to the current
character/reference height plus N. This is not a lock; normal camera
updates continue after the snap.

**Quick verify:**

1. Stand somewhere with open space above the character.
2. `/camera status` and note `cameraY` / `referenceY`.
3. `/camera vh 20` — the camera should jump upward; status should
   report `cameraY` near `referenceY + 20`.
4. Bind the command in the launcher if desired, e.g. bind a key to
   run `/camera vh 20` or `//camera vh 20`.

## Battle range and lock (`/camera br N`, `/camera bl on|off`)

**Expect:** wider/narrower angular sweep around a locked target;
360° rotation when unlocked.

**Quick verify:**

1. Lock on to any mob.
2. Right-click-drag to rotate around the target. Stock allows
   roughly ±90° of sweep before the camera snaps back.
3. `/camera br 50` — the sweep should now reach roughly ±180°.
4. `/camera bl off` — full 360° rotation around the target.
5. `/camera bl on` — stock clamp restored.

**Subtle gotcha:** `br` forces `bl on`. To get the wide-sweep + 360°
combination, run `br N` first then `bl off`.

## Increment / decrement (`/camera in`, `/camera de`, `/camera bin`, `/camera bde`)

**Expect:** ±1 step on the corresponding distance value, no save
unless `saveOnIncrement` is on.

**Quick verify:**

1. `/camera distance 6`
2. `/camera in` — distance becomes 7. `/camera s` confirms.
3. Reload the addon. Distance should be back to 6 (the saved value),
   not 7.
4. `/camera soi` to enable persistent step. Repeat steps 2–3 — now
   the saved value tracks.

## If a signature fails

The addon logs each site that is not patched on load, and the
patch group it takes down with it, e.g.:

```
[xicamera] min distance: eye follow C: signature not found on this client build
[xicamera] camera min patch group is off: min distance: eye follow C: signature not found on this client build
[xicamera] WARN: not every patch group is in (min); see /cam status
```

Every reader of one constant is a group and a group installs
all-or-none, so one missing min-distance site turns the whole
distance setting off rather than patching half of the camera's
math. `/camera status` lists every site that is not `patched`, with
its state; on Ashita 4 the settings window's "Patch status" shows
the same list.

| State | Meaning | What to do |
|:--|:--|:--|
| `missing` | the signature did not match | client update; see below |
| `owned` | another tool replaced the instruction (TrueFPS does this to the vertical jitter push) | expected; the other tool's version of the fix is in |
| `neutral` | another tool already points the operand at the value XICamera uses | nothing; XICamera leaves it to that tool |
| `foreign` | another tool points the operand somewhere else | load order or a conflicting camera tool; XICamera leaves it alone |
| `skipped` | in a group that is off | fix the group's failing site |
| `refused` | at unload, the site no longer held XICamera's pointer | another tool took it over; nothing was overwritten |

Causes of `missing`, in order of likelihood:

1. **The client was updated** and the function the signature targets
   was recompiled. Check `docs/CAMERA_PATCH_TARGETS.md` for the site,
   find the new bytes in an unpacked client image, and update the
   row in `Core.SITES` in `Ashita4/addons/xicamera/xicamera_core.lua`.
   Copy that file verbatim to the Ashita 3, Windower 4 (`Windower4/addons/XICamera/lib/`)
   and Windower 5 folders; `tools/test_core.lua <image>` checks the
   copies match and exercises every site against the image.
2. **Another tool rewrote the bytes the signature covers.** Signatures
   avoid every byte TrueFPS writes, so with TrueFPS this shows up as
   `owned` or `neutral`, never `missing`; with an unknown tool, unload
   it and reload XICamera to confirm.

If several signatures fail at once, the cause is (1).

## Restore on unload

**Expect:** unloading XICamera reverts every patch. Camera distance,
battle distance, pan speeds, jitter, and battle range all revert to
their stock values; the 2-byte battle-range clamp is restored.

**Quick verify:**

1. Set every value to non-stock: `/camera d 12`, `/camera b 12`,
   `/camera hs 6`, `/camera br 100`, `/camera bl off`.
2. Unload the addon (`/addon unload xicamera` on Ashita,
   `//lua unload xicamera` on Windower).
3. Mouse-wheel zoom should return to ~6 unit max. Locking onto a
   mob should snap to ~8.2 distance and the rotation clamp should
   stop the camera at ±90° again.

If you see any leftover patches after unload (e.g. battle camera
still rotates 360°), that's a bug — please file an issue with the
exact sequence that produced it.

## Settings window (Ashita 4 only)

**Expect:** `/camera` on its own, or `/camera ui`, toggles an ImGui
window with every setting above as a slider or checkbox, a height-snap
control, Save / Reset to defaults buttons, and a collapsible "Patch
status" list showing each signature as found or missing.

**Quick verify:**

1. `/camera ui` — the window opens. Drag "Distance" to 12: the camera
   moves while you drag; the settings file is written when you release.
2. `/camera d 8` in chat — the Distance slider follows the command.
3. Tick "Auto-calculate vertical pan speed" off and on — the vertical
   slider becomes editable, then shows the computed value again.
4. Expand "Patch status" — every row should read `found`. A `missing`
   row names the signature that did not match this client build.
5. Close the window with its title-bar X; `/camera` reopens it.
