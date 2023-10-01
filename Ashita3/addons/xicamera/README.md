## About

XICamera is an addon that allows to change the camera distance.

## Setup

- 1) Copy the xicamera folder into your ashita addons folder.

## In-Game commands

XICamera makes the in-game command /camera|/cam|/xicamera|/xicam available to adjust various behaviors of the camera on the fly.
The following parameters are supported:

- d/distance #          -- will change the camera distance - default: 6
- b/battle #            -- will change the battle camera distance - default: 8.2
- hs/hspeed #           -- will change the horizontal panning speed - default: 3
- vs/vspeed #           -- will change the vertical panning speed - default: 10.7, this forces auto calc off
- in/incr		        -- will increment camera distance by 1
- de/decr		        -- will decrement camera distance by 1
- bin/bincr		        -- will increment battle camera distance by 1
- bde/bdecr		        -- will decrement battle camera distance by 1
- saveOnIncrement/soi   -- will toggle saving behavior on incr/decr - default: off
- autoCalcVertSpeed/acv -- Toggles Vertical pan speed autocalc - default: on
- h/help                -- print help text
- s/status              -- print status

These commands all support a short version (d/b/hs/vs/h/s).
Changes made with distance will be saved in the ashita config directory.

## Disclaimer

I tested XICamera to the best of my capabilities but I can not guarantee that it works without bugs for 100% of the time.
Use at your own discretion, I take no responsibility for any client crashes or data loss.
