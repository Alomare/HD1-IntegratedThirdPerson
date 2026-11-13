-- The Hellpod camera: while the Helldiver drops in at the start of a mission or a respawn, the camera
-- rides the pod down, looking down and ahead so the ground shows, shakes when the pod lands, waits a
-- moment and glides into the shoulder view.
--
-- The game drops a Helldiver through CharacterStateCutscene with the animation "intro_land" for
-- character_info.spawn_time (5.4 s, character_component.lua:178, with the flow event spawn_hellpod
-- that drops the pod itself). Lua never sees the pod, so the camera follows a fall of its own toward
-- the Helldiver's spot. The landing is the "hellpod" camera shake the game raises near the Helldiver
-- (CameraShakeSettings.hellpod); without one, the pod counts as landed after LAND_FALLBACK seconds.
-- Plain numbers only, so tests can run it.
local rig = obsidian.module("src/rig")

local M = {}

M.HEIGHT = 70          -- metres above the landing spot the ride starts
M.LOW = 4              -- metres above the spot the camera ends the fall
M.BACK = 3             -- metres the camera sits behind the pod, along the view
M.PITCH = -68          -- degrees the pod camera looks down
M.LAND_FALLBACK = 1.8  -- seconds after the drop starts that the pod counts as landed without a shake
M.HOLD = 0.5           -- seconds the camera stays on the landed pod
M.GLIDE = 1.3          -- seconds the glide into the shoulder view takes
M.NEAR = 6             -- metres from the Helldiver a hellpod shake counts as this pod's landing

-- A new drop: anchor is the landing spot { x, y, z }.
function M.new(anchor)
	return { t = 0, landed = nil, anchor = { x = anchor.x, y = anchor.y, z = anchor.z } }
end

-- Moves a drop on by dt seconds. Answers false once the glide is over.
function M.step(s, dt)
	s.t = s.t + math.max(0, dt or 0)
	if not s.landed and s.t >= M.LAND_FALLBACK then s.landed = M.LAND_FALLBACK end
	return not (s.landed and s.t >= s.landed + M.HOLD + M.GLIDE)
end

-- The pod has landed now (the game's hellpod shake). Answers true the first time.
function M.land(s)
	if s.landed then return false end
	s.landed = s.t
	return true
end

-- How far into the shoulder view the camera is: 0 on the pod, 1 in the shoulder view, eased.
function M.blend(s)
	if not s.landed then return 0 end
	local g = (s.t - s.landed - M.HOLD) / M.GLIDE
	if g <= 0 then return 0 end
	if g >= 1 then return 1 end
	return g * g * (3 - 2 * g)
end

-- The pod's height above the spot: falling fast, slowing at the end, LOW once landed.
function M.height(s)
	if s.landed then return M.LOW end
	local f = math.min(1, s.t / M.LAND_FALLBACK)
	local left = 1 - f
	return M.LOW + (M.HEIGHT - M.LOW) * left * left
end

-- The camera on the pod for a view turned to `yaw`: position and pitch.
function M.pose(s, yaw)
	local flat = rig.flat_forward(yaw)
	local h = M.height(s)
	local a = s.anchor
	return { x = a.x - flat.x * M.BACK, y = a.y - flat.y * M.BACK, z = a.z + h }, M.PITCH
end

-- Between the pod pose and the shoulder pose by the blend: position and pitch.
function M.mix(pod_at, pod_pitch, at, pitch, w)
	return {
		x = pod_at.x + (at.x - pod_at.x) * w,
		y = pod_at.y + (at.y - pod_at.y) * w,
		z = pod_at.z + (at.z - pod_at.z) * w,
	}, pod_pitch + (pitch - pod_pitch) * w
end

return M
