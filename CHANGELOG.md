# Changelog

New, changed, fixed or removed features, one line each, brief and direct. The section for a release becomes the release notes.

## 0.4.2

- Changed: the crosshair handed to other mods also says when fire or a throw is held, so Custom Crosshair shows the aiming look while firing.

## 0.4.1

- New: a soft camera rumble while a weapon fires, stronger for vehicle guns. It follows the Camera shake option.
- Changed: the camera on foot sits a little lower, between the heights of 0.3.0 and 0.4.0.
- Changed: the game's own shakes move the shoulder camera 12 cm at the most, so a run of explosions no longer shakes it all the time.
- Fixed: the Hellpod camera did not start, because the game drops a new Helldiver in before the Helldiver counts as the player's.
- Fixed: enemy and hit indicators stayed on screen with the third person view switched off.
- Fixed: the red screen of an alarm still stopped short of the screen edges.

## 0.4.0

- New: Hellpod camera. When the Helldiver drops in, the camera rides the pod down looking at the ground, shakes on the landing, then glides into the shoulder view.
- New: Camera shake option (Off, Weak, Medium, Strong). Explosions and impacts now shake the shoulder camera too.
- Changed: enemy indicators are one ring around the crosshair in four segments. The right, back and left segments show faintly while an enemy is within 15 m on that side and stronger within 7.5 m, and the side with the closest enemy within 7.5 m shows a warning triangle. The ring hides while the game is paused.
- Changed: aiming no longer narrows the field of view; the camera comes in closer and in behind the head instead.
- Changed: the camera is 1 m farther away on foot and on the Super Destroyer, and sits higher on foot.
- Changed: beside a mech the camera sits farther to the side and about 2 m closer.
- Changed: vehicle guns always fire level, the way they point, so a mech no longer has to look up to shoot ahead.
- Fixed: the red screen of an alarm covers the whole screen instead of the middle.
- Removed: the ship walls.

## 0.3.0

- New: free movement, a lobby-wide option. In third person the Helldiver is no longer held on the shared top-down screen with the squad.
- New: a separate camera distance for the Super Destroyer, 3 m closer than in a mission by default.
- New: in a mech the camera sits beside the shoulder, on the same side as on foot. In any vehicle the swap key moves the camera from left to the middle to right.
- Changed: vehicle guns fire the way they point, at the height of the crosshair, instead of straight at the crosshair point while the gun is still turning.
- Changed: the camera on foot sits higher, while walking and while aiming.
- Changed: the dive camera also comes down toward the Helldiver.
- Changed: the on-foot camera distance is 4 m by default, and the vehicle field of view 70 degrees.
- Fixed: with the shield generator pack, grenades and stratagem balls always flew the full distance.

## 0.2.1

- Changed: enemy indicators are bigger. They scale with the hitpoints of the enemy from normal size up to one and a half times, where before they went from 0.8 to 1.2 times.

## 0.2.0

- New: dive camera. A dive brings the camera in close, and the camera eases back out once the dive ends.
- Changed: the shoulder swap, on H, glides across.
- New: a wall across the open back of the ship bridge.
- New: louder footsteps for Helldivers and enemies, with a Footsteps option.
- New: player name cards above heads instead of at the feet.
- New: a message when a second player joins on the same computer. Third person turns off and comes back once one player is left.
- Changed: enemy indicators show only enemies in sight, as fading white arcs, larger for enemies with more health.
- New: hit direction bars near the crosshair, red for health, yellow for the shield and white for vehicle hits.
- New: `shoulder()` for other mods.

## 0.1.2

- New: Obsidian offers updates from the GitHub repository.

## 0.1.1

- Fixed: the view no longer flickers to top-down while the shoulder camera draws.

## 0.1.0

- New: a shoulder camera on foot, in vehicles and on the ship, turned with the mouse or the right stick, with distance and field of view options, a shoulder swap, aim zoom and collision with rocks and walls. F8 switches between third person and the top-down camera.
- New: shots, laser sights, grenades and stratagem balls go where the crosshair points, with a plain crosshair.
- New: movement and vehicle steering follow the view.
- New: a long view with distant models kept detailed, a sky in the color of the planet fog, and walls on the open side of the ship bridge.
- New: enemy indicators, marks around the crosshair that point toward enemies in range.
- New: Max weapon range and Far enemy detection, two lobby-wide parts that switch off when a player without them joins.
- New: spawns, alarms and the squad leash still follow the top-down view, as in the game. The mod stays off with Third Person Camera installed.
