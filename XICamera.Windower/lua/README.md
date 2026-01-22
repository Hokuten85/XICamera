## About

XICamera is an addon that allows to change the camera distance.

## Setup

- 1) Copy the XICamera folder into your Windower addons folder.
- 2) (Optional) Edit `data/settings.xml`:
   - change the default camera distance. Camera and Battle distance will be defaulted to 6 and 8.2 if no setting is specified.

settings.xml:

```xml
<?xml version="1.1" ?>
<settings>
    <global>
	<cameraDistance>6</cameraDistance>
	<battleDistance>8.2</battleDistance>
	<horizontalPanSpeed>3</horizontalPanSpeed>
	<verticalPanSpeed>10.7</verticalPanSpeed>
    </global>
</settings>
```

## In-Game commands

XICamera makes the in-game command `//camera` or `//cam` available to adjust camera distance on the fly.
The following parameters are supported:

- d/distance #           -- will change the camera distance - default: 6
- b/battle #             -- will change the battle camera distance - default: 8
- hs/hspeed #            -- will change the horizontal panning speed - default: 3
- vs/vspeed #            -- will change the vertical panning speed - default: 10, this forces auto calc off
- in/incr		         -- will increment camera distance by 1
- de/decr		         -- will decrement camera distance by 1
- bin/bincr		         -- will increment battle camera distance by 1
- bde/bdecr		         -- will decrement battle camera distance by 1
- saveOnIncrement/soi    -- will toggle saving behavior on incr/decr - default: off
- autoCalcVertSpeed/acv  -- Toggles Vertical pan speed autocalc - default: on
- brange/br #            -- changes the battle camera movement range up to about 180 degrees around mob. default: 4, min: 0, max: 100.
- battlelock/bl <on/off> -- allows battle camera to rotate 360 degrees around mob.
- h/help                 -- print help text
- s/status               -- print status

These commands all support a short version (d/b/h/s/hs/vs).
Changes made with distance will be reflected in `settings.xml`.

## Disclaimer

I tested XICamera to the best of my capabilities but I can not guarantee that it works without bugs for 100% of the time.
Use at your own discretion, I take no responsibility for any client crashes or data loss.
