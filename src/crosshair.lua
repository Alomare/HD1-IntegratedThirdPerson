-- A plain crosshair at the middle of the view while third person steers it. Another mod that draws
-- the crosshair (claim_crosshair in main.lua, as Custom Crosshair does) turns this one off. The game's
-- aiming cursor stays hidden meanwhile (src/camera.lua).
local M = {}

M.GAP, M.LENGTH, M.THICK = 5, 8, 2
M.AIM_GAP = 3
M.COLOR = { 255, 255, 255, 230 }   -- obsidian.ui.canvas takes 0 to 255
M.SHADOW = { 0, 0, 0, 140 }

-- Whether the crosshair shows now. env.api may be nil.
function M.visible(env)
	local state = env.state
	if not state.active or not state.crosshair or state.claimed_by then return false end
	local api = env.api
	if api then
		if api.capture and api.capture.busy then
			local ok, busy = pcall(api.capture.busy)
			if ok and busy then return false end
		end
		if api.map and api.map.is_open then
			local ok, open = pcall(api.map.is_open)
			if ok and open then return false end
		end
	end
	return true
end

-- The rectangles of the crosshair around (x, y): { x, y, w, h } each, four arms and a dot.
function M.shape(x, y, aiming)
	local gap, len, t = aiming and M.AIM_GAP or M.GAP, M.LENGTH, M.THICK
	local h = t / 2
	return {
		{ x - gap - len, y - h, len, t },
		{ x + gap, y - h, len, t },
		{ x - h, y + gap, t, len },
		{ x - h, y - gap - len, t, len },
		{ x - h, y - h, t, t },
	}
end

function M.draw(kit, env)
	local c = env.state.crosshair
	for _, r in ipairs(M.shape(c.x, c.y, env.state.aiming)) do
		kit:rect(r[1] - 1, r[2] - 1, r[3] + 2, r[4] + 2, M.SHADOW)
	end
	for _, r in ipairs(M.shape(c.x, c.y, env.state.aiming)) do
		kit:rect(r[1], r[2], r[3], r[4], M.COLOR)
	end
end

function M.start(env)
	local ui = obsidian.ui
	if type(ui) ~= "table" or type(ui.canvas) ~= "function" then return end
	local kit = ui.canvas("integratedthirdperson_crosshair", { layer = 500 })
	if not kit then return end
	local failed = false
	obsidian.on_frame(function()
		if failed or not M.visible(env) then return end
		local ok, err = pcall(M.draw, kit, env)
		if not ok then
			failed = true
			env.log("Integrated Third Person: crosshair stopped: " .. tostring(err))
		end
	end, env.VIEW)
end

return M
