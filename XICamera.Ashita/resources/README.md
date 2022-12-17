## About

XICamera is a plugin that allows to change the camera distance.

## Setup

- 1) Copy the `XICamera.dll` into Ashita's `plugins/` directory.
- 2) Copy `XICamera.sample.xml` to Ashita's `config/` directory and rename it to `XICamera.xml`
- 3) Add `/load xicamera` to your setup script

XICamera.xml:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<settings>
    <setting name="cameraDistance">6</setting>
	<setting name="battleDistance">8.2</setting>
</settings>
```
## In-Game commands

XICamera makes the in-game command `/camera` available to change the camera distance at runtime.

The following parameters are supported:

- d/distance # -- will change the camera distance
- b/battle #   -- will change the camera distance
- h/help       -- print this text

These commands all support a short first letter version (d/b/h).

## Disclaimer

I tested XICamera to the best of my capabilities but I can not guarantee that it works without bugs for 100% of the time.
Use at your own discretion, I take no responsibility for any client crashes or data loss.
