-- Camera shake for the shoulder view. The game shakes only its top-down camera (CameraManager.update
-- adds CameraShaker:update's offset to the top-down pose, camera_manager.lua:476-479), and that pose
-- never reaches the screen under the shoulder view. The offset the game works out each frame is kept
-- (game) and added to the shoulder pose, scaled by the Camera shake option, with shakes of this mod's
-- own on top (the Hellpod landing). Plain numbers only, so tests can run it.
local M = {}

-- The option's levels, as a factor on every shake.
M.LEVEL = { off = 0, weak = 0.5, medium = 1, strong = 1.8 }

M.list = {}               -- own shakes: { amp, freq, left, total }
-- A soft rumble while this player's weapon fires (src/aim.lua sees it): metres, a second, and the
-- seconds it takes to die out after the last shot. A vehicle's guns rumble more.
M.FIRE = { amp = 0.02, vehicle_amp = 0.045, freq = 16, fade = 0.15 }
M.fire = { level = 0, phase = 0, vehicle = false }
-- The most the game's own shake moves the shoulder view in a frame, in metres: a run of explosions
-- (a mod with blasts on every kill) shook it all the time.
M.GAME_MOST = 0.12
M.game = { x = 0, y = 0 } -- the game's offset this frame, in metres right and up of the view

function M.factor(level)
	return M.LEVEL[level] or M.LEVEL.medium
end

-- A shake of amp metres at freq a second for dur seconds, dying out.
function M.add(amp, freq, dur)
	M.list[#M.list + 1] = { amp = amp, freq = freq, left = dur, total = dur, phase = 0 }
end

-- A weapon of this player fired this frame. vehicle: a vehicle's gun.
function M.fired(vehicle)
	M.fire.level = 1
	M.fire.vehicle = vehicle and true or false
end

local function clamp_length(x, y, most)
	local len = math.sqrt(x * x + y * y)
	if len <= most or len == 0 then return x, y end
	return x / len * most, y / len * most
end

-- The offset of this frame, metres right and up, and moves the own shakes on by dt.
function M.offset(dt, factor)
	local x, y = clamp_length(M.game.x or 0, M.game.y or 0, M.GAME_MOST)
	local f = M.fire
	if f.level > 0 then
		f.phase = f.phase + dt
		local a = (f.vehicle and M.FIRE.vehicle_amp or M.FIRE.amp) * f.level
		local w = f.phase * M.FIRE.freq * 2 * math.pi
		x = x + a * math.sin(w * 1.7)
		y = y + a * math.cos(w)
		f.level = math.max(0, f.level - dt / M.FIRE.fade)
	end
	for i = #M.list, 1, -1 do
		local s = M.list[i]
		s.phase = s.phase + dt
		s.left = s.left - dt
		if s.left <= 0 then
			table.remove(M.list, i)
		else
			local fade = s.left / s.total
			local a = s.amp * fade * fade
			local w = s.phase * s.freq * 2 * math.pi
			x = x + a * math.sin(w * 1.3)
			y = y + a * math.cos(w)
		end
	end
	return x * factor, y * factor
end

function M.clear()
	M.list = {}
	M.fire.level, M.fire.phase = 0, 0
	M.game.x, M.game.y = 0, 0
end

return M
