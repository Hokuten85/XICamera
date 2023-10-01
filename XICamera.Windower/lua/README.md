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
	<horizontalPanSpeed>3</cameraDistance>
	<verticalPanSpeed>10.7</battleDistance>
    </global>
</settings>
```

## In-Game commands

XICamera makes the in-game command `//camera` or `//cam` available to adjust camera distance on the fly.
The following parameters are supported:

- d/distance #        -- will change the camera distance
- b/battle #          -- will change the battle camera distance
- hs/hspeed #         -- will change the horizontal panning speed
- vs/vspeed #         -- will change the vertical panning speed
- in/incr		      -- will increment camera distance by 1
- de/decr		      -- will decrement camera distance by 1
- bin/bincr		      -- will increment battle camera distance by 1
- bde/bdecr		      -- will decrement battle camera distance by 1
- saveOnIncrement/soi -- will toggle saving behavior on incr/decr. By default this is off
- h/help              -- print help text
- s/status            -- print status

These commands all support a short version (d/b/h/s/hs/vs).
Changes made with distance will be reflected in `settings.xml`.

## Disclaimer

I tested XICamera to the best of my capabilities but I can not guarantee that it works without bugs for 100% of the time.
Use at your own discretion, I take no responsibility for any client crashes or data loss.
