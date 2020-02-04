## About

XICamera is an addon that allows to change the camera distance.

## Setup

- 1) Copy the XICamera folder into your Windower addons folder.
- 2) (Optional) Edit `data/settings.xml`:
   - change the default camera distance. Distance will be defaulted to 5 if no setting is specified.

settings.xml:

```xml
<?xml version="1.1" ?>
<settings>
    <global>
	<cameraDistance>5</cameraDistance>
    </global>
</settings>
```

## In-Game commands

XICamera makes the in-game command `//camera` or `//cam` available to adjust camera distance on the fly.
The following parameters are supported:

- d/distance #     -- will change the camera distance
- s/status               -- dumps XICamera's global status
- h/help                 -- print this text

These commands all support a short first letter version (d/s/h).
Changes made with distance will be reflected in `settings.xml`.

## Limitations

There are some small differences in how the camera will behave.

Normal camera behavior will very slightly depending on character movement. For instance, you can notice a subtle increase in camera when beginning to run, and a subtle decrease in distance when stopping.

While the addon is on, the camera will always remain at the specified distance. As you move the camera distance further out, the rate that you can pan the camera up and down decreases. The camera's ability to automatically trail behind you also diminishes. You will stay in frame, but the camera doesn't swing behind you in the direction that you are running.

## Disclaimer

I tested XICamera to the best of my capabilities but I can not guarantee that it works without bugs for 100% of the time.
Use at your own discretion, I take no responsibility for any client crashes or data loss.