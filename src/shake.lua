-- Camera shake for the shoulder view. The game shakes only its top-down camera (CameraManager.update
-- adds CameraShaker:update's offset to the top-down pose, camera_manager.lua:476-479), and that pose
-- never reaches the screen under the shoulder view. The offset the game works out each frame is kept
-- (game) and added to the shoulder pose, scaled by the Camera shake option, with shakes of this mod's
-- own on top (the Hellpod landing). Plain numbers only, so tests can run it.
local M = {}

-- The option's levels, as a factor on every shake.
M.LEVEL = { off = 0, weak = 0.5, medium = 1, strong = 1.8 }

M.list = {}               -- own shakes: { amp, freq, left, total }
M.game = { x = 0, y = 0 } -- the game's offset this frame, in metres right and up of the view

function M.factor(level)
	return M.LEVEL[level] or M.LEVEL.medium
end

-- A shake of amp metres at freq a second for dur seconds, dying out.
function M.add(amp, freq, dur)
	M.list[#M.list + 1] = { amp = amp, freq = freq, left = dur, total = dur, phase = 0 }
end

-- The offset of this frame, metres right and up, and moves the own shakes on by dt.
function M.offset(dt, factor)
	local x, y = M.game.x or 0, M.game.y or 0
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
	M.game.x, M.game.y = 0, 0
end

return M
