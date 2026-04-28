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

The addon logs the failing signature name on load, e.g.:

```
[xicamera] could not find max battle camera distance
```

That means the corresponding `findpattern` call returned 0. Causes,
in order of likelihood:

1. **The client was updated** and the function the signature targets
   was recompiled. Check `docs/CAMERA_PATCH_TARGETS.md` to find which
   pattern needs a new bytes string. The fix is to update the
   signature in:
   - `XICamera.Core/Camera.cpp` (Windower 4)
   - `Ashita3/addons/xicamera/xicamera.lua` (Ashita 3)
   - `Ashita4/addons/xicamera/xicamera.lua` (Ashita 4)
   - `Windower5/addons/xicamera/xicamera.lua` (Windower 5)
   ...all four. If you find a working pattern in one launcher, copy
   it byte-for-byte to the other three.
2. **You loaded XICamera before logging in** (Ashita addons only
   sometimes — see your launcher docs). Reload the addon after
   character select.
3. **Another camera plugin/addon also patches the same site** and
   ran first, and rewrote the bytes such that our pattern doesn't
   match anymore. Unload the conflicting addon, then load XICamera.

If multiple signatures fail simultaneously, the most likely cause
is (1) — a client update.

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
