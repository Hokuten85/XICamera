## About

XICamera for **Ashita v4** changes the third-person camera: distance, battle distance, pan speeds, battle camera range and lock, a one-shot height snap, and removal of the camera jitter against walls.

## Setup

1. Extract the zip into your Ashita 4 `addons` folder. You should end up with `addons/xicamera/xicamera.lua` and `addons/xicamera/xicamera_core.lua` next to each other; both files are needed.
2. In game: `/addon load xicamera`.

Settings save per character under `config/addons/xicamera/`. To load it every time, add `/addon load xicamera` to your startup script.

## Settings window

`/cam` on its own, or `/cam ui`, opens a window with a slider or checkbox for every setting, a height-snap control, Save and Reset to defaults buttons, and a **Patch status** list that shows each patch site as `patched`, or why it is not. Its Refresh button re-reads the sites without changing anything.

## In-Game commands

`/camera`, `/cam`, `/xicamera` and `/xicam` all work. Parameters:

- ui                     -- toggles the settings window (the prefix on its own does the same)
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

XICamera never overwrites the client's own constants; it points the camera code at floats it owns, and only while the bytes at each site are the ones it found. A site another tool already changed is left alone and shown in Patch status as `owned`, `neutral` or `foreign`. TrueFPS in particular is fine in either load order: whichever tool reaches the jitter sites first keeps them.

## What changed in 0.8

Earlier versions wrote the user's distance straight into the client's 3.0 and 6.0 constants. Those numbers are shared with unrelated code, including the clamp on the running-animation rate, which is where the "NPCs run strangely after logging in" reports came from. 0.8 leaves the constants untouched. If you saw that, it is fixed here.

## Disclaimer

I tested XICamera to the best of my capabilities but I can not guarantee that it works without bugs for 100% of the time.
Use at your own discretion, I take no responsibility for any client crashes or data loss.
