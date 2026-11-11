-- Enemy indicators: a thin white arc with a small arrow on a ring around the crosshair, one for each
-- enemy within range that the Helldiver has a clear line to. HELLDIVERS was made for a view from above,
-- where everything around the Helldiver is on screen, so enemies make little sound. In third person
-- most of them are out of view; the marks say where.
--
-- Every frame: the enemies this machine knows (the "enemy" slaves of the entity manager, through
-- Obsidian API), the living ones within range, and the bearing of each from the way the camera faces
-- over the ground, read from the engine camera, so the top-down view works too. The nearest MAX_SCAN
-- are tracked. A ray from the chest of the Helldiver to each tracked enemy, against the level only,
-- says whether the enemy is in sight; each enemy is checked again every RECHECK frames, at most RAYS a
-- frame. A mark grows stronger as the enemy comes closer, from ALPHA_FAR at the range to ALPHA_NEAR at
-- the player, and is larger for enemies with more hitpoints (SCALE_SMALL to SCALE_BIG). Every change
-- fades: a mark coming into sight, leaving it, or an enemy dying.
--
-- No tables per frame: the pool of nearest enemies stays from frame to frame, and each tracked enemy
-- keeps one record until the mark has faded out.
local M = {}

M.MAX_SCAN = 16      -- nearest enemies tracked
M.RAYS = 6           -- sight rays cast a frame at most
M.RECHECK = 8        -- frames before an enemy is checked again
M.EYE = 1.4          -- metres above the feet of the Helldiver the sight ray starts
M.CHEST = 1          -- metres above the feet of the enemy it ends
M.SLACK = 0.4        -- metres short of the enemy a hit still leaves it in sight
M.RING = 0.11        -- ring radius, as a share of the screen height
M.ARC = 18           -- degrees the arc spans, at size 1
M.THICK, M.THICK_END = 2.4, 0.8 -- arc thickness in pixels at 1080 lines, in the middle and at the ends
M.ARROW_LENGTH, M.ARROW_HALF = 5.5, 4.5 -- the arrow on the arc, pixels at 1080 lines
M.SEGMENTS = 6       -- pieces each arc is drawn in
M.ALPHA_FAR, M.ALPHA_NEAR = 0.2, 0.9
M.FADE = 18          -- how fast a mark fades in and out (ease rate, per second)
M.HP_SMALL, M.HP_BIG = 60, 3000 -- hitpoints at size SCALE_SMALL and SCALE_BIG, log scale between
M.SCALE_SMALL, M.SCALE_BIG = 1, 1.5
M.LAYER = 480        -- under the crosshair of Integrated Third Person (500)
M.PAUSE = 300        -- frames without marks after an error
M.COLOR = { 255, 255, 255 }

local sqrt, atan2, deg, rad, cos, sin, log, exp = math.sqrt, math.atan2, math.deg, math.rad, math.cos, math.sin, math.log, math.exp

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

-- 1 at the player, 0 at the range and past it.
function M.closeness(d, range)
	if not range or range <= 0 then return 0 end
	local c = 1 - d / range
	if c < 0 then return 0 end
	if c > 1 then return 1 end
	return c
end

-- Strength from ALPHA_FAR at the range to ALPHA_NEAR at the player.
function M.alpha(c)
	return M.ALPHA_FAR + (M.ALPHA_NEAR - M.ALPHA_FAR) * c
end

-- Size of a mark from the most hitpoints of the enemy: SCALE_SMALL at HP_SMALL and below, SCALE_BIG at
-- HP_BIG and above, on a log scale between.
function M.scale_of(max_hp)
	local hp = tonumber(max_hp)
	if not hp or hp <= M.HP_SMALL then return M.SCALE_SMALL end
	if hp >= M.HP_BIG then return M.SCALE_BIG end
	local t = (log(hp) - log(M.HP_SMALL)) / (log(M.HP_BIG) - log(M.HP_SMALL))
	return M.SCALE_SMALL + (M.SCALE_BIG - M.SCALE_SMALL) * t
end

-- A share of the way to the target this frame, the same at any frame rate.
function M.ease(current, target, rate, dt)
	return current + (target - current) * (1 - exp(-rate * dt))
end

-- Puts an enemy into `pool` (records reused from frame to frame), kept nearest first, at most `cap`
-- long; `n` is how many are in use. Answers the new count. A record is only made while the pool grows
-- past any earlier frame.
function M.insert(pool, n, cap, d, bearing, unit)
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
	rec.d, rec.bearing, rec.unit = d, bearing, unit
	local i = n
	while i > 1 and pool[i - 1].d > d do
		pool[i] = pool[i - 1]
		i = i - 1
	end
	pool[i] = rec
	return n
end

-- Whether the line from (fx, fy, fz) to (tx, ty, tz) is clear: cast(sx, sy, sz, dx, dy, dz, length)
-- answers the distance to the first piece of level along the way, or nil.
function M.in_sight(cast, fx, fy, fz, tx, ty, tz)
	local dx, dy, dz = tx - fx, ty - fy, tz - fz
	local length = sqrt(dx * dx + dy * dy + dz * dz)
	if length < 1e-3 then return true end
	local hit = cast(fx, fy, fz, dx / length, dy / length, dz / length, length)
	return not hit or hit >= length - M.SLACK
end

-- The angle on screen (radians, 0 to the right, counter-clockwise, y up) of a bearing: ahead is up.
function M.screen_angle(bearing)
	return rad(90 - bearing)
end

-- Piece i (0 to n - 1) of an arc centred on the angle theta round (cx, cy): the inner edge at radius r,
-- `span` radians long, thick `mid` pixels in the middle and `edge` at the ends. Written into `out`
-- { x1, y1, ... x4, y4 }, inner start, outer start, outer end, inner end.
function M.arc_piece(out, cx, cy, theta, r, span, i, n, mid, edge)
	local u0, u1 = -1 + 2 * i / n, -1 + 2 * (i + 1) / n
	local a0, a1 = theta + u0 * span / 2, theta + u1 * span / 2
	local t0 = edge + (mid - edge) * (1 - u0 * u0)
	local t1 = edge + (mid - edge) * (1 - u1 * u1)
	local c0, s0, c1, s1 = cos(a0), sin(a0), cos(a1), sin(a1)
	out[1], out[2] = cx + c0 * r, cy + s0 * r
	out[3], out[4] = cx + c0 * (r + t0), cy + s0 * (r + t0)
	out[5], out[6] = cx + c1 * (r + t1), cy + s1 * (r + t1)
	out[7], out[8] = cx + c1 * r, cy + s1 * r
	return out
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

	local pool = {}
	local tracks = {}     -- unit: { a (strength now), seen, check (frame of the next ray), scale, bearing, d, on, near }
	local tracked = 0
	local frame_no = 0
	local piece, tri = { 0, 0, 0, 0, 0, 0, 0, 0 }, { 0, 0, 0, 0, 0, 0 }
	local fill = { M.COLOR[1], M.COLOR[2], M.COLOR[3], 255 }

	-- The sight ray, against the level only. pw is the physics world of this frame.
	local pw, PW, V3 = nil, nil, nil
	local function cast(sx, sy, sz, dx, dy, dz, length)
		local hit, _, distance = PW.immediate_raycast(pw, V3(sx, sy, sz), V3(dx, dy, dz), length,
			"closest", "types", "statics", "collision_filter", "default")
		if hit and type(distance) == "number" then return distance end
		return nil
	end

	local function physics_of(cm)
		return g("World").physics_world(cm.viewport:get_world_proxy():get_world())
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

	local function forget()
		if tracked > 0 then
			for unit in pairs(tracks) do tracks[unit] = nil end
			tracked = 0
		end
	end

	local function frame()
		local api = env.api
		if not (api and api.game and api.game.in_mission and api.game.in_mission()) then return forget() end
		if not shown(api) then return end
		local me = api.game.my_unit()
		if not me then return end
		local U, aux, cm = g("Unit"), g("EntityAux"), g("CameraManager")
		local C, Q = g("Camera"), g("Quaternion")
		PW, V3 = g("PhysicsWorld"), g("Vector3")
		if not (U and aux and cm and cm.viewport and C and Q and V3) then return end
		local dt = g("ENGINE_DT")
		dt = type(dt) == "number" and dt > 0 and math.min(dt, 0.1) or 1 / 60
		frame_no = frame_no + 1

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
		pw = nil
		if PW then
			local ok, found = pcall(physics_of, cm)
			if ok then pw = found end
		end

		local p = U.world_position(me, 0)
		local px, py, pz = p.x, p.y, p.z
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
						n = M.insert(pool, n, M.MAX_SCAN, d, M.bearing(dx, dy, hx, hy), unit)
					end
				end
			end
		end

		for _, t in pairs(tracks) do t.on, t.near = false, false end
		local rays = 0
		for i = 1, n do
			local e = pool[i]
			local t = tracks[e.unit]
			if not t then
				local health = aux.state(e.unit, "health")
				t = { a = 0, seen = false, check = 0, scale = M.scale_of(health and health.max_hitpoints) }
				tracks[e.unit] = t
				tracked = tracked + 1
			end
			t.bearing, t.d, t.near = e.bearing, e.d, true
			if t.check <= frame_no and rays < M.RAYS then
				rays = rays + 1
				t.check = frame_no + M.RECHECK
				if pw then
					local q = U.world_position(e.unit, 0)
					t.seen = M.in_sight(cast, px, py, pz + M.EYE, q.x, q.y, q.z + M.CHEST)
				else
					t.seen = true
				end
			end
			t.on = t.seen
		end
		if tracked == 0 then return end

		local scale = h / 1080
		local cx, cy
		local state = env.state
		if state.active and state.crosshair then
			cx, cy = state.crosshair.x, state.crosshair.y
		else
			cx, cy = x0 + w / 2, y0 + h / 2
		end
		local ring = M.RING * h
		for unit, t in pairs(tracks) do
			local want = t.on and M.alpha(M.closeness(t.d, range)) or 0
			t.a = M.ease(t.a, want, M.FADE, dt)
			if not t.near and t.a < 0.01 then
				-- Out of the nearest and faded: forgotten. An enemy still near but out of sight stays,
				-- with the sight ray schedule it has.
				tracks[unit] = nil
				tracked = tracked - 1
			elseif t.a >= 0.01 then
				local s = t.scale
				local theta = M.screen_angle(t.bearing)
				local mid, edge = M.THICK * s * scale, M.THICK_END * s * scale
				local span = rad(M.ARC) * s
				fill[4] = t.a * 255
				for i = 0, M.SEGMENTS - 1 do
					kit:poly(M.arc_piece(piece, cx, cy, theta, ring, span, i, M.SEGMENTS, mid, edge), fill)
				end
				kit:poly(M.triangle(tri, cx, cy, theta, ring + mid, M.ARROW_LENGTH * s * scale, M.ARROW_HALF * s * scale), fill)
			end
		end
	end

	-- An error rests the marks for PAUSE frames (a level tearing down, say) and is logged once.
	local warned, wait = false, 0
	obsidian.on_frame(function()
		if not on then return forget() end
		if wait > 0 then
			wait = wait - 1
			return
		end
		local ok, err = pcall(frame)
		if not ok then
			wait = M.PAUSE
			forget()
			if not warned then
				warned = true
				env.log("Integrated Third Person: enemy indicators: " .. tostring(err))
			end
		end
	end, env.VIEW)
end

return M
