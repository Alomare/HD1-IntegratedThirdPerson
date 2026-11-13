-- Enemy indicators: one ring round the crosshair in four segments, front, right, back and left, with a
-- gap between them. The front segment never shows: what is ahead is on screen. A side segment shows
-- while an enemy is within the indicator range in that direction (thin, 30%), and stronger within half
-- the range (thicker, 60%). The side with the closest enemy inside half the range also carries a warning
-- triangle in the middle of its segment. Each segment fades from 70% of its strength at the inner edge
-- to all of it at the outer edge.
--
-- HELLDIVERS was made for a view from above, where everything round the Helldiver is on screen, so
-- enemies make little sound; in third person most of them are out of view.
--
-- Every frame: the enemies this machine knows (the "enemy" slaves of the entity manager, through
-- Obsidian API), the living ones within range, and the bearing of each from the way the camera faces
-- over the ground. No rays and no tables a frame. Hidden while the game is paused (Helldivers Arcade's
-- upgrade screen stops time), on other screens, with the map open and during a screenshot.
local M = {}

M.RING = 0.11        -- ring radius, as a share of the screen height
M.GAP = 14           -- degrees between two segments
M.THIN, M.THICK = 2, 4 -- segment thickness in pixels at 1080 lines: an enemy in range, and within half of it
M.ALPHA_FAR, M.ALPHA_NEAR = 0.3, 0.6
M.INNER = 0.7        -- strength at the inner edge, as a share of the outer edge
M.BANDS = 3          -- rings each segment is drawn in, from the inner to the outer edge
M.PIECES = 14        -- pieces along each segment
M.ICON = 22          -- warning triangle, pixels at 1080 lines (the height)
M.ICON_LINE = 1.6    -- its outline
M.FADE = 14          -- how fast a segment changes (ease rate, per second)
M.LAYER = 480        -- under the crosshair of Integrated Third Person (500)
M.PAUSE = 300        -- frames without marks after an error
M.SIDES = { "right", "back", "left" }

local sqrt, atan2, deg, rad, cos, sin, exp = math.sqrt, math.atan2, math.deg, math.rad, math.cos, math.sin, math.exp

-- Pure parts ----------------------------------------------------------------------------------------

-- The way the camera faces over the ground, as a unit vector (x, y), from the forward and up vectors
-- of the camera. Looking nearly straight down, forward has no ground part to speak of and up points to
-- the top of the screen instead (to the bottom when looking up). nil when neither has one.
function M.heading(fx, fy, fz, ux, uy)
	local hx, hy = fx, fy
	local len = sqrt(hx * hx + hy * hy)
	if len < 0.2 and ux and uy then
		local sign = (fz or 0) <= 0 and 1 or -1
		hx, hy = ux * sign, uy * sign
		len = sqrt(hx * hx + hy * hy)
	end
	if len < 1e-6 then return nil end
	return hx / len, hy / len
end

-- Degrees from the facing (hx, hy) to the offset (dx, dy), from -180 to 180, positive to the right
-- (clockwise seen from above; the level is z up).
function M.bearing(dx, dy, hx, hy)
	local ahead = dx * hx + dy * hy
	local right = dx * hy - dy * hx
	return deg(atan2(right, ahead))
end

-- The segment of a bearing: "front", "right", "back" or "left", each a quarter of the circle.
function M.side_of(bearing)
	if bearing > -45 and bearing <= 45 then return "front" end
	if bearing > 45 and bearing <= 135 then return "right" end
	if bearing < -45 and bearing >= -135 then return "left" end
	return "back"
end

-- How strongly a side shows for the closest enemy there, `d` metres away: 0 nothing, 1 in range, 2
-- within half the range.
function M.level(d, range)
	if not d or d > range then return 0 end
	if d <= range / 2 then return 2 end
	return 1
end

-- The side the warning triangle goes on: the one with the closest enemy, if that one is within half the
-- range. near: side -> closest distance or nil.
function M.warned(near, range)
	local best, side = range / 2, nil
	for _, s in ipairs(M.SIDES) do
		local d = near[s]
		if d and d <= best then best, side = d, s end
	end
	return side
end

-- The angle on screen (radians, 0 to the right, counter-clockwise, y up) of a bearing: ahead is up.
-- src/hits.lua draws its bars with it.
function M.screen_angle(bearing)
	return rad(90 - bearing)
end

-- The angle on screen of a side's middle (radians, 0 to the right, counter-clockwise, y up).
M.ANGLE = { front = rad(90), right = 0, back = rad(-90), left = rad(180) }

-- A share of the way to the target this frame, the same at any frame rate.
function M.ease(current, target, rate, dt)
	return current + (target - current) * (1 - exp(-rate * dt))
end

-- One piece of a band: radii r0 to r1, angles a0 to a1. Written into `out` { x1, y1, ... x4, y4 }.
function M.quad(out, cx, cy, r0, r1, a0, a1)
	local c0, s0, c1, s1 = cos(a0), sin(a0), cos(a1), sin(a1)
	out[1], out[2] = cx + c0 * r0, cy + s0 * r0
	out[3], out[4] = cx + c0 * r1, cy + s0 * r1
	out[5], out[6] = cx + c1 * r1, cy + s1 * r1
	out[7], out[8] = cx + c1 * r0, cy + s1 * r0
	return out
end

-- The strength of band k (0 inner to bands - 1 outer) as a share of the segment's: INNER to 1.
function M.band_share(k, bands)
	if bands <= 1 then return 1 end
	return M.INNER + (1 - M.INNER) * k / (bands - 1)
end

-- Whether the game stands still: paused (the game's own PAUSED, which Obsidian API's time_scale sets
-- for a stop), time stopped through the API, or the players frozen through its freeze effect.
function M.paused(api)
	if rawget(_G, "PAUSED") == true then return true end
	local world = api and api.world
	if world and world.time_now then
		local ok, now = pcall(world.time_now)
		if ok and now == 0 then return true end
	end
	local effects = api and api.effects
	if effects and effects.is_on then
		local ok, frozen = pcall(effects.is_on, "freeze")
		if ok and frozen then return true end
	end
	return false
end

-- The game -----------------------------------------------------------------------------------------

local function g(name) return rawget(_G, name) end

function M.start(env)
	local ui = obsidian.ui
	if type(ui) ~= "table" or type(ui.canvas) ~= "function" then return end
	local kit = ui.canvas("integratedthirdperson_radar", { layer = M.LAYER })
	if not kit then return end

	local config = env.config
	local on = config.get("radar") ~= false
	local range = tonumber(config.get("radar_range")) or 15
	if config.on_change then
		config.on_change("radar", function(v) on = v ~= false end)
		config.on_change("radar_range", function(v) range = tonumber(v) or range end)
	end

	-- Per side: the strength now (a), the thickness now (t), and the warning triangle's strength (w).
	local look = {}
	for _, s in ipairs(M.SIDES) do look[s] = { a = 0, t = M.THIN, w = 0 } end
	local near = {}
	local piece, tri = { 0, 0, 0, 0, 0, 0, 0, 0 }, { 0, 0, 0, 0, 0, 0 }
	local fill = { 255, 255, 255, 255 }

	local function shown(api)
		if M.paused(api) then return false end
		if ui.current then
			local cur = ui.current()
			if type(cur) == "table" and cur.screen ~= "hud" then return false end
		end
		if api.map and api.map.is_open then
			local ok, open = pcall(api.map.is_open)
			if ok and open then return false end
		end
		if api.capture and api.capture.busy then
			local ok, busy = pcall(api.capture.busy)
			if ok and busy then return false end
		end
		return true
	end

	local function rest()
		for _, s in ipairs(M.SIDES) do
			local l = look[s]
			l.a, l.t, l.w = 0, M.THIN, 0
		end
	end

	-- A segment, in BANDS rings fading outward, with a gap in the middle `hole` radians wide (the triangle).
	local function segment(cx, cy, theta, r, thick, alpha, hole)
		local half = rad(90 - M.GAP) / 2
		local band = thick / M.BANDS
		for k = 0, M.BANDS - 1 do
			fill[4] = alpha * M.band_share(k, M.BANDS) * 255
			local r0 = r + k * band
			for i = 0, M.PIECES - 1 do
				local a0 = theta - half + 2 * half * i / M.PIECES
				local a1 = theta - half + 2 * half * (i + 1) / M.PIECES
				if hole <= 0 or a1 <= theta - hole / 2 or a0 >= theta + hole / 2 then
					kit:poly(M.quad(piece, cx, cy, r0, r0 + band, a0, a1), fill)
				end
			end
		end
	end

	-- The warning triangle, upright, outlined, with an exclamation mark, centred at (x, y).
	local function warning(x, y, size, alpha, line)
		local h = size
		local w = size * 1.15
		tri[1], tri[2] = x - w / 2, y - h * 0.45
		tri[3], tri[4] = x + w / 2, y - h * 0.45
		tri[5], tri[6] = x, y + h * 0.55
		fill[4] = alpha * 255
		kit:outline(tri, fill, line)
		kit:rect(x - line / 2, y - h * 0.08, line, h * 0.32, fill)
		kit:rect(x - line / 2, y - h * 0.3, line, line, fill)
	end

	local function frame()
		local api = env.api
		if not (api and api.game and api.game.in_mission and api.game.in_mission()) then return rest() end
		if not shown(api) then return rest() end
		local me = api.game.my_unit()
		if not me then return rest() end
		local U, aux, cm = g("Unit"), g("EntityAux"), g("CameraManager")
		local C, Q = g("Camera"), g("Quaternion")
		if not (U and aux and cm and cm.viewport and C and Q) then return end
		local dt = g("ENGINE_DT")
		dt = type(dt) == "number" and dt > 0 and math.min(dt, 0.1) or 1 / 60

		-- The camera, as the engine has it this frame.
		local cam = cm.viewport:get_camera()
		local rot = C.world_rotation(cam)
		local f, up = Q.forward(rot), Q.up(rot)
		local hx, hy = M.heading(f.x, f.y, f.z, up.x, up.y)
		if not hx then return end
		local w, h, x0, y0 = cm.viewport:window()
		if not (w and h) then
			w, h = g("Application").resolution()
			x0, y0 = 0, 0
		end
		x0, y0 = x0 or 0, y0 or 0

		near.right, near.back, near.left = nil, nil, nil
		local p = U.world_position(me, 0)
		local px, py = p.x, p.y
		local r2 = range * range
		for unit in pairs(api.game.slaves("enemy")) do
			if U.alive(unit) then
				local q = U.world_position(unit, 0)
				local dx, dy = q.x - px, q.y - py
				local d2 = dx * dx + dy * dy
				if d2 <= r2 then
					local health = aux.state(unit, "health")
					if health and not health.is_dead then
						local side = M.side_of(M.bearing(dx, dy, hx, hy))
						if side ~= "front" then
							local d = sqrt(d2)
							if not near[side] or d < near[side] then near[side] = d end
						end
					end
				end
			end
		end
		local warn = M.warned(near, range)

		local scale = h / 1080
		local cx, cy
		local state = env.state
		if state.active and state.crosshair then
			cx, cy = state.crosshair.x, state.crosshair.y
		else
			cx, cy = x0 + w / 2, y0 + h / 2
		end
		local ring = M.RING * h
		local icon = M.ICON * scale
		for _, s in ipairs(M.SIDES) do
			local l = look[s]
			local level = M.level(near[s], range)
			l.a = M.ease(l.a, level == 2 and M.ALPHA_NEAR or level == 1 and M.ALPHA_FAR or 0, M.FADE, dt)
			l.t = M.ease(l.t, level == 2 and M.THICK or M.THIN, M.FADE, dt)
			l.w = M.ease(l.w, warn == s and 1 or 0, M.FADE, dt)
			if l.a >= 0.01 then
				local theta = M.ANGLE[s]
				local thick = l.t * scale
				local hole = l.w > 0.05 and (icon * 1.3 / ring) * l.w or 0
				segment(cx, cy, theta, ring, thick, l.a, hole)
				if l.w > 0.05 then
					local mid = ring + thick / 2
					warning(cx + cos(theta) * mid, cy + sin(theta) * mid, icon, l.w, M.ICON_LINE * scale)
				end
			end
		end
	end

	-- An error rests the marks for PAUSE frames (a level tearing down, say) and is logged once.
	local warned, wait = false, 0
	obsidian.on_frame(function()
		if not on then return rest() end
		if wait > 0 then
			wait = wait - 1
			return
		end
		local ok, err = pcall(frame)
		if not ok then
			wait = M.PAUSE
			rest()
			if not warned then
				warned = true
				env.log("Integrated Third Person: enemy indicators: " .. tostring(err))
			end
		end
	end, env.VIEW)
end

return M
