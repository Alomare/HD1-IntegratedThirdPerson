-- Enemy indicators: marks on a ring around the crosshair, each pointing toward enemies within range.
-- HELLDIVERS was made for a view from above, where everything around the Helldiver is on screen, so
-- enemies make little sound. In third person most of them are out of view; the marks say where.
--
-- Every frame: the enemies this machine knows (the "enemy" slaves of the entity manager, through
-- Obsidian API), the living ones within range, and the bearing of each from the way the camera faces
-- over the ground, read from the engine camera, so the top-down view works too. The nearest MAX_SCAN
-- go into a pool, close bearings merge, and at most MAX_MARKS are drawn: larger and stronger as the
-- enemy comes closer, doubled for enemies behind, heavier for big enemies, faint for enemies already
-- in view. Nothing per enemy makes a table: the pools stay from frame to frame, and whether an enemy
-- is big is looked up once per enemy.
local M = {}

M.MAX_MARKS = 8      -- marks drawn at most
M.MAX_SCAN = 24      -- nearest enemies weighed for the marks
M.MERGE = 14         -- degrees: enemies closer together than this share one mark
M.BEHIND = 120       -- degrees from the facing past which an enemy counts as behind
M.BIG_HP = 900       -- most hitpoints from which an enemy counts as big (Obsidian API brain.lua BIG_HP)
M.BIG_RADIUS = 1     -- unit_radius from which an enemy counts as big: Hulks, Tripods and Striders, Tanks
M.RING = 0.085       -- ring radius, as a share of the screen height
M.SIZE_FAR, M.SIZE_NEAR = 8, 18 -- mark length in pixels at 1080 lines, at the range and at the player
M.BIG_SIZE = 1.45    -- big enemies: this much larger, with a dark edge
M.MERGED_SIZE = 0.15 -- each extra enemy in a mark adds this much, up to MERGED_MAX extra enemies
M.MERGED_MAX = 3
M.ALPHA_FAR, M.ALPHA_NEAR = 0.35, 1
M.IN_VIEW = 0.3      -- marks of enemies already on screen keep this much of their strength
M.LAYER = 480        -- under the crosshair of Integrated Third Person (500)
M.PAUSE = 300        -- frames without marks after an error
M.COLOR = { 255, 64, 40 }
M.EDGE = { 24, 6, 4 }

local sqrt, atan2, deg, rad, cos, sin, abs = math.sqrt, math.atan2, math.deg, math.rad, math.cos, math.sin, math.abs

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

-- The smallest turn from bearing a to bearing b, in degrees, from -180 to 180.
function M.angle_gap(a, b)
	local d = (b - a) % 360
	if d > 180 then d = d - 360 end
	return d
end

-- 1 at the player, 0 at the range and past it.
function M.closeness(d, range)
	if not range or range <= 0 then return 0 end
	local c = 1 - d / range
	if c < 0 then return 0 end
	if c > 1 then return 1 end
	return c
end

function M.behind(bearing)
	return abs(bearing) > M.BEHIND
end

-- Whether an enemy counts as big, from the settings of the unit (LuaSettingsManager) and the most
-- hitpoints it has: the game marks Tanks, Impalers and the IFV heavy or large, and Hulks, Tripods
-- and Striders stand on a wide base.
function M.is_big(settings, max_hp)
	if type(settings) == "table" then
		if settings.heavy == true then return true end
		local hi = settings.health_info
		if type(hi) == "table" and hi.large == true then return true end
		if (tonumber(settings.unit_radius) or 0) >= M.BIG_RADIUS then return true end
	end
	return (tonumber(max_hp) or 0) >= M.BIG_HP
end

-- Puts an enemy into `pool` (records reused from frame to frame), kept nearest first, at most `cap`
-- long; `n` is how many are in use. Answers the new count. A record is only made while the pool grows
-- past any earlier frame.
function M.insert(pool, n, cap, d, bearing, big, in_view)
	local rec
	if n < cap then
		n = n + 1
		rec = pool[n]
		if not rec then
			rec = {}
			pool[n] = rec
		end
	else
		if d >= pool[n].d then return n end
		rec = pool[n]
	end
	rec.d, rec.bearing, rec.big, rec.in_view = d, bearing, big, in_view
	local i = n
	while i > 1 and pool[i - 1].d > d do
		pool[i] = pool[i - 1]
		i = i - 1
	end
	pool[i] = rec
	return n
end

-- Marks from the `n` nearest records of `pool` (nearest first): a record within `spread` degrees of a
-- mark already made joins that mark (count, big, in view only if all are), else makes a new one while
-- fewer than `max` exist. A mark keeps the bearing and distance of the nearest enemy in it. Answers
-- the number of marks.
function M.merge(pool, n, marks, max, spread)
	local m = 0
	for i = 1, n do
		local e = pool[i]
		local into = nil
		for j = 1, m do
			if abs(M.angle_gap(marks[j].bearing, e.bearing)) < spread then
				into = marks[j]
				break
			end
		end
		if into then
			into.count = into.count + 1
			into.big = into.big or e.big
			into.in_view = into.in_view and e.in_view
		elseif m < max then
			m = m + 1
			local k = marks[m]
			if not k then
				k = {}
				marks[m] = k
			end
			k.bearing, k.d, k.big, k.in_view, k.count = e.bearing, e.d, e.big, e.in_view, 1
			k.behind = M.behind(e.bearing)
		end
	end
	return m
end

-- Mark length in pixels at 1080 lines, from how close (0 to 1), big, and how many enemies it holds.
function M.size(c, big, count)
	local s = M.SIZE_FAR + (M.SIZE_NEAR - M.SIZE_FAR) * c
	if big then s = s * M.BIG_SIZE end
	local extra = math.min((count or 1) - 1, M.MERGED_MAX)
	if extra > 0 then s = s * (1 + M.MERGED_SIZE * extra) end
	return s
end

-- Strength from 0 to 1.
function M.alpha(c, in_view)
	local a = M.ALPHA_FAR + (M.ALPHA_NEAR - M.ALPHA_FAR) * c
	if in_view then a = a * M.IN_VIEW end
	return a
end

-- The angle on screen (radians, 0 to the right, counter-clockwise, y up) of a bearing: ahead is up.
function M.screen_angle(bearing)
	return rad(90 - bearing)
end

-- A triangle pointing outward from (cx, cy) at angle `theta`: the base `from` pixels out and `half`
-- wide each side, the tip `length` past the base. Written into `out` { x1, y1, x2, y2, x3, y3 }.
function M.triangle(out, cx, cy, theta, from, length, half)
	local ux, uy = cos(theta), sin(theta)
	local px, py = -uy, ux
	local bx, by = cx + ux * from, cy + uy * from
	out[1], out[2] = bx + px * half, by + py * half
	out[3], out[4] = bx - px * half, by - py * half
	out[5], out[6] = bx + ux * length, by + uy * length
	return out
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
	local range = tonumber(config.get("radar_range")) or 35
	if config.on_change then
		config.on_change("radar", function(v) on = v ~= false end)
		config.on_change("radar_range", function(v) range = tonumber(v) or range end)
	end

	local pool, marks = {}, {}
	local tri, tri2 = { 0, 0, 0, 0, 0, 0 }, { 0, 0, 0, 0, 0, 0 }
	local fill, edge = { M.COLOR[1], M.COLOR[2], M.COLOR[3], 255 }, { M.EDGE[1], M.EDGE[2], M.EDGE[3], 255 }

	-- Whether each enemy is big, looked up once; dropped with a new mission or when it grows long.
	local big, big_count, big_of_map = {}, 0, nil
	local function big_of(unit, health, enemies)
		if enemies ~= big_of_map or big_count > 512 then
			big, big_count, big_of_map = {}, 0, enemies
		end
		local b = big[unit]
		if b == nil then
			local lsm = g("LuaSettingsManager")
			local ok, settings = false, nil
			if type(lsm) == "table" and lsm.get_settings_by_unit then ok, settings = pcall(lsm.get_settings_by_unit, lsm, unit) end
			b = M.is_big(ok and settings or nil, health.max_hitpoints)
			big[unit] = b
			big_count = big_count + 1
		end
		return b
	end

	local function shown(api)
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

	local function frame()
		local api = env.api
		if not (api and api.game and api.game.in_mission and api.game.in_mission()) then return end
		if not shown(api) then return end
		local me = api.game.my_unit()
		if not me then return end
		local U, aux, cm = g("Unit"), g("EntityAux"), g("CameraManager")
		local C, Q, V3 = g("Camera"), g("Quaternion"), g("Vector3")
		if not (U and aux and cm and cm.viewport and C and Q and V3) then return end

		-- The camera, as the engine has it this frame.
		local cam = cm.viewport:get_camera()
		local rot = C.world_rotation(cam)
		local f, up = Q.forward(rot), Q.up(rot)
		local hx, hy = M.heading(f.x, f.y, f.z, up.x, up.y)
		if not hx then return end
		local w, h, x0, y0 = cm.viewport:window()
		if not (w and h) then
			local app = g("Application")
			w, h = app.resolution()
			x0, y0 = 0, 0
		end
		x0, y0 = x0 or 0, y0 or 0

		local p = U.world_position(me, 0)
		local px, py = p.x, p.y
		local enemies = api.game.slaves("enemy")
		local n = 0
		for unit in pairs(enemies) do
			if U.alive(unit) then
				local health = aux.state(unit, "health")
				if health and not health.is_dead then
					local q = U.world_position(unit, 0)
					local dx, dy = q.x - px, q.y - py
					local d = sqrt(dx * dx + dy * dy)
					if d <= range and (n < M.MAX_SCAN or d < pool[n].d) then
						local s = cm:world_to_screen(V3(q.x, q.y, q.z + 1))
						local in_view = s.z > 0 and s.x >= x0 and s.x <= x0 + w and s.y >= y0 and s.y <= y0 + h
						n = M.insert(pool, n, M.MAX_SCAN, d, M.bearing(dx, dy, hx, hy), big_of(unit, health, enemies), in_view)
					end
				end
			end
		end
		if n == 0 then return end
		local m = M.merge(pool, n, marks, M.MAX_MARKS, M.MERGE)

		local scale = h / 1080
		local cx, cy
		local state = env.state
		if state.active and state.crosshair then
			cx, cy = state.crosshair.x, state.crosshair.y
		else
			cx, cy = x0 + w / 2, y0 + h / 2
		end
		local ring = M.RING * h
		for i = 1, m do
			local mk = marks[i]
			local c = M.closeness(mk.d, range)
			local size = M.size(c, mk.big, mk.count) * scale
			local a = M.alpha(c, mk.in_view)
			local theta = M.screen_angle(mk.bearing)
			fill[4] = a * 255
			edge[4] = a * 255
			local half = size * 0.55
			M.triangle(tri, cx, cy, theta, ring, size, half)
			kit:poly(tri, fill)
			if mk.big then kit:outline(tri, edge, math.max(1.5, size * 0.12)) end
			if mk.behind then
				-- A second, smaller arrow past the first: enemies the view turns away from.
				M.triangle(tri2, cx, cy, theta, ring + size + 2 * scale, size * 0.75, half * 0.75)
				kit:poly(tri2, fill)
				if mk.big then kit:outline(tri2, edge, math.max(1.5, size * 0.1)) end
			end
		end
	end

	-- An error rests the marks for PAUSE frames (a level tearing down, say) and is logged once.
	local warned, wait = false, 0
	obsidian.on_frame(function()
		if not on then return end
		if wait > 0 then
			wait = wait - 1
			return
		end
		local ok, err = pcall(frame)
		if not ok then
			wait = M.PAUSE
			if not warned then
				warned = true
				env.log("Integrated Third Person: enemy indicators: " .. tostring(err))
			end
		end
	end, env.VIEW)
end

return M
