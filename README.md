# Integrated Third Person

An over-the-shoulder camera for HELLDIVERS (2015), for the [Obsidian](https://github.com/Alomare/ObsidianLauncher) mod manager. Based on [Third Person Camera (HD2 Style)](https://github.com/yukiorsrs/third-person-camera-helldivers) by **yukiorsrs**, rebuilt with the permission of the author so that other mods keep working beside it.

The camera follows the Helldiver on foot, in vehicles and on the ship. Shots, grenades and stratagems go where the crosshair points. The view reaches farther, the sky over the level is filled in, a ring around the crosshair warns of enemies close by, and a bar shows where hits come from.

Third Person Camera replaces 28 game scripts, so mods that change the same parts of the game stop working with it. Integrated Third Person replaces no script: every change is a hook through Obsidian.

## How to use

**F8** switches between third person and the top-down camera, and **H** swaps the shoulder. Both keys can be changed in Obsidian.

## Playing with others

The camera and everything on screen work in any lobby. Three options change the game for the whole lobby: Max weapon range, Far enemy detection and Free movement. They run only when every player runs Obsidian with the same mods, and switch off when anyone else joins. With all three off, the mod counts as a client mod.

## Known issues

- Players on one computer share a screen, so third person turns off while a second local player is in, and comes back after.
- The mod stays off while Third Person Camera is installed.

Mod authors can read the camera state through `obsidian.import("alomare.integratedthirdperson")`: `active()`, `crosshair()` and `shoulder()`.
