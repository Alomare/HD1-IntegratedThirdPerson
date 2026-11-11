-- Hit direction indicators: when the Helldiver, the personal shield or the vehicle the Helldiver sits
-- in takes damage, a bar near the crosshair points toward where the hit came from and fades out within
-- LIFE seconds. Red for health, yellow for the shield, white for a vehicle. A hit from an enemy keeps
-- pointing at that enemy while the bar shows.
--
-- HealthComponent.command_master runs every damage command on the machine that runs the unit:
-- "do_damage", "request_do_damage" (a hit another machine saw first) and "set_hitpoints", each with
-- owner_unit (who did it) and attacker_unit (the weapon, projectile or grenade). A hit counts when
-- hitpoints_real drops. A working personal shield takes the hit instead, in
-- ShieldComponent.on_damage_taken. A vehicle counts on the machine that runs it, usually the machine
-- of the player who called it in.
local scoped = obsidian.module("src/scoped")
local radar = obsidian.module("src/radar")

local M = {}

M.LIFE = 2           -- seconds a bar shows
M.POP = 0.06         -- seconds to full strength
M.HOLD = 0.3         -- seconds at full strength before the fade
M.ALPHA = 0.85       -- full strength
M.SLOTS = 8          -- bars at once
M.MERGE = 25         -- degrees: a hit this close to a bar of the same kind renews that bar
M.RADIUS = 0.15      -- from the crosshair to the inner end of a bar, as a share of the screen height
M.LENGTH = 0.075     -- bar length, same share
M.WIDTH = 0.022      -- bar width, same share
M.STEPS = 4          -- pieces each bar fades outward in
M.LAYER = 470        -- under the enemy indicators (480)
M.COLORS = { health = { 230, 40, 30 }, shield = { 255, 210, 40 }, vehicle = { 255, 255, 255 } }
M.DAMAGE = { do_damage = true, request_do_damage = true, set_hitpoints = true }

local atan2, deg, abs, min = math.atan2, math.deg, math.abs, math.min

-- Pure parts ----------------------------------------------------------------------------------------

-- Strength from 0 to 1 at `age` seconds: up within POP, held until HOLD, then down to 0 at LIFE.
function M.strength(age)
	if age < 0 or age >= M.LIFE then return 0 end
	local s = min(1, age / M.POP)
	if age > M.HOLD then
		local t = (age - M.HOLD) / (M.LIFE - M.HOLD)
		s = s * (1 - t) * (1 - t)
	end
	return s
end

-- Where a hit came from: the unit and whether to follow it while it lives. An enemy that did it is
-- followed. Otherwise the thing that hit (a projectile, a grenade, a barrel) or the one who did it
-- (a teammate) gives the place at the moment of the hit. nil for a hit with no source but the
-- Helldiver.
function M.source(owner, attacker, me, alive, is_enemy)
	if owner and owner ~= me and alive(owner) and is_enemy(owner) then return owner, true end
	if attacker and attacker ~= me and alive(attacker) then return attacker, false end
	if owner and owner ~= me and alive(owner) then return owner, false end
	return nil, false
end

-- The slot a new hit goes in: the bar already following that unit, else a bar of the same kind
-- pointing within MERGE degrees (`way`, degrees over the ground from the player), else a free slot,
-- else the oldest bar. Answers the slot and whether it renews a bar.
function M.pick(slots, unit, follow, kind, way)
	local free, oldest = nil, nil
	for _, s in ipairs(slots) do
		if s.on then
			if follow and s.follow and s.unit == unit then return s, true end
			if not follow and not s.follow and s.kind == kind and abs(radar.angle_gap and radar.angle_gap(s.way, way) or (s.way - way)) < M.MERGE then
				return s, true
			end
			if not oldest or s.age > oldest.age then oldest = s end
		elseif not free then
			free = s
		end
	end
	return free or oldest, false
end

-- Degrees over the ground from (px, py) toward (x, y), north 0, east 90.
function M.way(px, py, x, y)
	return deg(atan2(x - px, y - py))
end

-- Piece k (0 to n - 1) of a bar pointing outward from (cx, cy) at angle theta: the bar runs from r0 to
-- r1 pixels out and is `half` wide each side. Written into `out` { x1, y1, ... x4, y4 }.
function M.bar_piece(out, cx, cy, theta, r0, r1, half, k, n)
	local ux, uy = math.cos(theta), math.sin(theta)
	local px, py = -uy, ux
	local a = r0 + (r1 - r0) * k / n
	local b = r0 + (r1 - r0) * (k + 1) / n
	out[1], out[2] = cx + ux * a + px * half, cy + uy * a + py * half
	out[3], out[4] = cx + ux * b + px * half, cy + uy * b + py * half
	out[5], out[6] = cx + ux * b - px * half, cy + uy * b - py * half
	out[7], out[8] = cx + ux * a - px * half, cy + uy * a - py * half
	return out
end

-- How strong piece k of n is next to the inner end: the bar fades outward.
function M.piece_share(k, n)
	return 1 - 0.8 * k / n
end

-- The game -----------------------------------------------------------------------------------------

local function g(name) return rawget(_G, name) end

function M.start(env)
	local ui = obsidian.ui
	if type(ui) ~= "table" or type(ui.canvas) ~= "function" then return end
	local kit = ui.canvas("integratedthirdperson_hits", { layer = M.LAYER })
	if not kit then return end

	local config = env.config
	local on = config.get("hit_indicators") ~= false
	if config.on_change then config.on_change("hit_indicators", function(v) on = v ~= false end) end

	local slots = {}
	for i = 1, M.SLOTS do slots[i] = { on = false, age = 0, way = 0, x = 0, y = 0 } end
	local mine = { avatar = nil, seat = nil }
	local piece = { 0, 0, 0, 0, 0, 0, 0, 0 }
	local fill = { 255, 255, 255, 255 }

	local function alive(u)
		local U = g("Unit")
		local ok, yes = pcall(U.alive, u)
		return ok and yes
	end
	local function is_enemy(u)
		local aux = g("EntityAux")
		local ok, yes = pcall(aux.has_component, u, "enemy")
		return ok and yes
	end

	-- A hit on `kind` from owner/attacker: a new bar, or a renewed one.
	local function hit(kind, owner, attacker)
		local me = mine.avatar
		if not me then return end
		local unit, follow = M.source(owner, attacker, me, alive, is_enemy)
		if not unit then return end
		local U = g("Unit")
		local p, q = U.world_position(me, 0), U.world_position(unit, 0)
		local way = M.way(p.x, p.y, q.x, q.y)
		local s, renew = M.pick(slots, unit, follow, kind, way)
		s.on, s.unit, s.follow, s.kind, s.x, s.y, s.way = true, unit, follow, kind, q.x, q.y, way
		s.age = renew and min(s.age, M.POP) or 0
	end

	local function kind_of(unit)
		if unit == nil then return nil end
		if unit == mine.avatar then return "health" end
		if unit == mine.seat then return "vehicle" end
		return nil
	end

	obsidian.hook("HealthComponent", "command_master", function(original, self, unit, ctx, command, data, ...)
		local kind = on and M.DAMAGE[command] and kind_of(unit)
		if not kind then return original(self, unit, ctx, command, data, ...) end
		local st = type(ctx) == "table" and ctx.state
		local before = type(st) == "table" and st.hitpoints_real or nil
		local r = scoped.pack(original(self, unit, ctx, command, data, ...))
		if type(before) == "number" and type(data) == "table" then
			local after = st.hitpoints_real
			if type(after) == "number" and after < before then pcall(hit, kind, data.owner_unit, data.attacker_unit) end
		end
		return unpack(r, 1, r.n)
	end, env.VIEW)

	obsidian.hook("ShieldComponent", "on_damage_taken", function(original, self, unit, ctx, damage, data, ...)
		if on and unit ~= nil and unit == mine.avatar and type(damage) == "number" and damage > 0 and type(data) == "table" then
			pcall(hit, "shield", data.owner_unit, data.attacker_unit)
		end
		return original(self, unit, ctx, damage, data, ...)
	end, env.VIEW)

	local function clear()
		for _, s in ipairs(slots) do
			s.on, s.unit = false, nil
		end
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
		return true
	end

	local function frame()
		local api = env.api
		mine.avatar, mine.seat = nil, nil
		if not (api and api.game and api.game.in_mission and api.game.in_mission()) then return clear() end
		local me = api.game.my_unit()
		if not me then return clear() end
		mine.avatar = me
		local aux = g("EntityAux")
		local ok, cs = pcall(aux.state, me, "character")
		if ok and type(cs) == "table" then mine.seat = cs.current_seat_unit end

		local dt = g("ENGINE_DT")
		dt = type(dt) == "number" and dt > 0 and min(dt, 0.1) or 1 / 60
		local any = false
		for _, s in ipairs(slots) do
			if s.on then
				s.age = s.age + dt
				if s.age >= M.LIFE then s.on, s.unit = false, nil else any = true end
			end
		end
		if not any or not shown(api) then return end

		local U, cm, C, Q = g("Unit"), g("CameraManager"), g("Camera"), g("Quaternion")
		if not (U and cm and cm.viewport and C and Q) then return end
		local rot = C.world_rotation(cm.viewport:get_camera())
		local f, up = Q.forward(rot), Q.up(rot)
		local hx, hy = radar.heading(f.x, f.y, f.z, up.x, up.y)
		if not hx then return end
		local w, h, x0, y0 = cm.viewport:window()
		x0, y0 = x0 or 0, y0 or 0
		local p = U.world_position(me, 0)
		local px, py = p.x, p.y
		local cx, cy
		local state = env.state
		if state.active and state.crosshair then
			cx, cy = state.crosshair.x, state.crosshair.y
		else
			cx, cy = x0 + w / 2, y0 + h / 2
		end
		local r0, r1, half = M.RADIUS * h, (M.RADIUS + M.LENGTH) * h, M.WIDTH * h / 2
		for _, s in ipairs(slots) do
			if s.on then
				if s.follow and alive(s.unit) then
					local q = U.world_position(s.unit, 0)
					s.x, s.y = q.x, q.y
				end
				local dx, dy = s.x - px, s.y - py
				if dx * dx + dy * dy > 0.25 then
					local strength = M.strength(s.age) * M.ALPHA
					local color = M.COLORS[s.kind] or M.COLORS.health
					fill[1], fill[2], fill[3] = color[1], color[2], color[3]
					local theta = radar.screen_angle(radar.bearing(dx, dy, hx, hy))
					for k = 0, M.STEPS - 1 do
						fill[4] = strength * M.piece_share(k, M.STEPS) * 255
						kit:poly(M.bar_piece(piece, cx, cy, theta, r0, r1, half, k, M.STEPS), fill)
					end
				end
			end
		end
	end

	local warned = false
	obsidian.on_frame(function()
		if not on then return clear() end
		local ok, err = pcall(frame)
		if not ok then
			clear()
			if not warned then
				warned = true
				env.log("Integrated Third Person: hit indicators: " .. tostring(err))
			end
		end
	end, env.VIEW)
end

return M
