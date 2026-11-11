# Integrated Third Person

An over-the-shoulder camera for HELLDIVERS (2015), for the [Obsidian](https://github.com/Alomare/ObsidianLauncher) mod manager. Based on [Third Person Camera (HD2 Style)](https://github.com/yukiorsrs/third-person-camera-helldivers) by **yukiorsrs**, rebuilt with the permission of the author so that other mods keep working beside it.

Third Person Camera replaces 28 game scripts, so mods that change the same parts of the game stop working with it. Integrated Third Person replaces no script: every change is a hook through Obsidian, and the hooks of other mods on the same functions still run.

## What it does

- A shoulder camera on foot, in vehicles (mech, APC, bike, turrets and seats) and on the ship, turned with the mouse or the right stick. W moves where the camera looks.
- Shots, laser sights, grenades and stratagem balls go where the crosshair points, up and down included. Vehicle weapons follow the crosshair too.
- The camera keeps out of rocks and walls, and the aim button brings it closer. A dive brings it in close, quickly but smoothly, and it eases back out once the dive ends. The shoulder swap glides across.
- A longer view: the fog, the far edge of the view and the detail of distant models are pushed out, so far enemies and landmarks show.
- A sky over the level in the color of the planet fog, in place of the smears past the level.
- Walls across the open back of the Super Destroyer bridge, which the top-down camera never showed, made from copies of the bridge wall panels.
- Marks around the crosshair that point toward nearby enemies, larger and stronger as they come closer, since the game was made for a view from above and enemies make little sound.
- Louder footsteps for Helldivers and enemies: each step plays up to four times, so steps out of view are easier to hear. The sound files stay as they are.
- Player name cards above heads instead of at the feet.
- The rules of the game keep the top-down screen: enemies spawn, patrols raise the alarm and the squad stays together as in the game.

## Options

Every option is in Obsidian. The four camera distances and fields of view are also in game, under Mods in the pause menu, and apply at once.

| Group | Option | Default |
|---|---|---|
| Camera on foot | On-foot camera distance (m) | 3 |
| | On-foot field of view (degrees) | 70 |
| | Shoulder | Right |
| | Look sensitivity | 1 |
| | Invert vertical look | Off |
| | Dive camera | On |
| Camera in vehicles | Vehicle camera distance (m) | 7 |
| | Vehicle field of view (degrees) | 75 |
| Indicators and names | Enemy indicators | On |
| | Indicator range (m) | 35 |
| | Names above heads | On |
| View distance, sky and ship | Long view distance | On |
| | Sky | On (needs a deploy) |
| | Ship walls | On |
| Sound | Footsteps | Loudest |
| Lobby-wide changes | Max weapon range | On |
| | Far enemy detection | On |

Keys: **F8** switches between third person and the top-down camera, **H** swaps the shoulder. Both can be changed in the Keys tab in Obsidian.

## Playing with others

Players on one computer share one screen, which only the top-down camera can show. When a second player joins on the same computer, third person turns off with a message, and it comes back once one player is left.

The mod comes in parts. The camera, aim, view, sky, ship walls, enemy indicators, name cards and footsteps only change what this player sees and hears, and work in any lobby. Two parts change the game the whole lobby shares:

- **Max weapon range**: every gun, laser and launcher reaches 100 m, the length of the bullet ray in the game. Flamethrowers, arc weapons and melee keep their reach.
- **Far enemy detection**: enemies keep chasing a player up to 150 m away instead of 80 m, and patrols spot players up to 80 m away and close in. The alarm still needs a player as close as in the game.

These two run only in a lobby where every player runs Obsidian and allows the same mods. When a player without them joins, both switch off at once and the camera keeps working. With both options off, the mod counts as a client mod: Galactic War results are sent as usual.

Parts need Obsidian 2.0.0 or later. An older Obsidian treats the whole mod as a session mod, so the camera also stops in lobbies with players who don't run it.

## Working with other mods

- **Custom Crosshair** draws the crosshair in place of the plain one built in here.
- **Enhanced Visuals** loads after this mod and brings the same sky fix.
- **Photo Mode** takes the camera while open; third person steps aside until it closes.
- **Better HUD** hides enemy bars out of view while third person is on, instead of pinning them to the edge of the screen, sets them a little lower, and moves the ammo circle to a fixed spot on the side away from the camera shoulder.
- **Third Person Camera**: the two mods can't run together. With Third Person Camera installed, this mod stays off and says so.

Mods built on Obsidian API keep working: other mods can ask `obsidian.import("alomare.integratedthirdperson")` for `active()`, `crosshair()` and `shoulder()` (1 for the right shoulder, -1 for the left, nil in the top-down view).

## Building the skies

`python tools/build_sky.py` writes the sky textures, materials and units in `res/` from the game install. `res/render_config.bin` is the render config of Photo Mode, byte for byte, so the two mods never conflict.

## Tests

`luajit tests/run.lua` runs the offline tests.

## Credits

- **yukiorsrs**, author of Third Person Camera (HD2 Style), which this mod is based on and studied from, with permission.
- Arrowhead Game Studios for HELLDIVERS.

## License

MIT. See [LICENSE](LICENSE).
