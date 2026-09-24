## About

XICamera for **Windower 5** changes the third-person camera: distance, battle distance, pan speeds, battle camera range and lock, a one-shot height snap, and removal of the camera jitter against walls.

## Setup

1. Extract the zip into your Windower 5 `addons` folder. You should end up with `addons/xicamera/` containing `manifest.xml`, `xicamera.lua` and `xicamera_core.lua`; all three are needed.
2. In game: `//addon load xicamera`.

Settings save through Windower 5's settings library.

## In-Game commands

`//camera`, `//cam`, `//xicamera` and `//xicam` all work. Parameters:

- d/distance #           -- camera distance - default: 6
- b/battle #             -- battle camera distance - default: 8.2
- hs/hspeed #            -- horizontal panning speed - default: 3
- vs/vspeed #            -- vertical panning speed - default: 10.7; turns auto calc off
- vh/vheight #           -- snaps camera height to the reference height plus #
- in/incr                -- camera distance +1
- de/decr                -- camera distance -1
- bin/bincr              -- battle camera distance +1
- bde/bdecr              -- battle camera distance -1
- saveOnIncrement/soi    -- toggles saving on incr/decr - default: off
- autoCalcVertSpeed/acv  -- toggles vertical pan speed auto calc - default: on
- brange/br #            -- battle camera movement range around the target, 0..100 - default: 4; turns the lock on
- battlelock/bl <on/off> -- off lets the battle camera rotate 360 degrees around the target
- h/help                 -- print help text
- s/status               -- print status, including any patch site that is not in

## Running next to other tools

XICamera never overwrites the client's own constants; it points the camera code at floats it owns, and only while the bytes at each site are the ones it found. A site another tool already changed is left alone and listed by `//cam status` as `owned`, `neutral` or `foreign`.

On Windower 5 the re-check that the other ports run for a minute after loading is tied to `//cam status`: running it re-applies anything another tool undid and reports takeovers.

## What changed in 0.8

Earlier versions wrote the user's distance straight into the client's 3.0 and 6.0 constants. Those numbers are shared with unrelated code, including the clamp on the running-animation rate, which is where the "NPCs run strangely after logging in" reports came from. 0.8 leaves the constants untouched.

## Disclaimer

I tested XICamera to the best of my capabilities but I can not guarantee that it works without bugs for 100% of the time.
Use at your own discretion, I take no responsibility for any client crashes or data loss.
