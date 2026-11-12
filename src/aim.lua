-- Aim under the shoulder camera: a ray from the camera through the middle of the screen finds the
-- crosshair point, and the game's aim, shots, grenades and stratagem balls go there.
--
-- Everything here is scoped to one call of the game (src/scoped.lua):
--   InputComponent.queue_command_master   the character's aim input points at the crosshair point
--   <weapon>.update_slaves, LauncherComponent.do_fire
--                                          Quaternion.forward answers the crosshair way for this
--                                          player's weapons, and WeaponUtility.get_random_spread
--                                          drops the dip that makes a level shot meet the ground
--   LauncherComponent.do_fire             the state's z_direction is the crosshair way's
--   LaserSightComponent.update_slaves     the laser line goes to the crosshair point
--   Character*Throw.update                 CameraManager.screen_to_world answers the crosshair point,
--                                          which sets how far a grenade or a stratagem ball flies
local rig = obsidian.module("src/rig")
local scoped = obsidian.module("src/scoped")

local M = {}

local function g(name) return rawget(_G, name) end

M.RANGE = 300 -- metres the crosshair ray reaches

-- Whether a unit hit by the crosshair ray belongs to this player: the body, the vehicle, or something the
-- Helldiver carries (a backpack such as the shield generator pack, whose shield surrounds the body).
local function own_hit(unit, view)
	if unit == nil then return false end
	if unit == view.avatar or unit == view.target then return true end
	local EA = g("EntityAux")
	local ok, wielder = pcall(function()
		if EA and EA.has_component(unit, "equipment") then return EA.state(unit, "equipment").wielder end
		return nil
	end)
	return ok and wielder ~= nil and (wielder == view.avatar or wielder == view.target)
end

-- The crosshair point: the first thing along the view past the pivot that isn't this player's own body,
-- vehicle or gear, or the far end of the ray. Every hit along the ray is asked for at once: the ray
-- starts inside a shield bubble when the Helldiver carries one, and a hit at the start (a shape the ray
-- starts in) doesn't count either.
function M.find_point(view)
	local PW, V3, W, Actor = g("PhysicsWorld"), g("Vector3"), g("World"), g("Actor")
	local f = view.forward
	local start = rig.add(view.position, f, rig.ray_start(view.position, f, view.pivot))
	local pw = W.physics_world(view.world)
	local hits = PW.immediate_raycast(pw, V3(start.x, start.y, start.z), V3(f.x, f.y, f.z), M.RANGE,
		"all", "collision_filter", "damage_ray")
	local best, best_distance = nil, math.huge
	if type(hits) == "table" then
		for _, h in ipairs(hits) do
			local pos, distance, actor = h[1], h[2], h[4]
			if pos and type(distance) == "number" and distance > 0.05 and distance < best_distance then
				local unit = actor and Actor and Actor.unit(actor)
				if not own_hit(unit, view) then best, best_distance = pos, distance end
			end
		end
	end
	if best then return { x = best.x, y = best.y, z = best.z }, true end
	return rig.add(start, f, M.RANGE), false
end

-- Where the crosshair is drawn: the middle of the view, in pixels from the bottom left of the window.
function M.centre(cm)
	local w, h, x0, y0 = cm.viewport:window()
	return { x = (x0 or 0) + w / 2, y = (y0 or 0) + h / 2 }
end

-- The character's aim input. The game sets it while the player aims, fires or throws; it now points
-- at the crosshair point. A pad's right stick turns the view, so it no longer turns the Helldiver.
function M.steer(data, input, view, point)
	if type(data) ~= "table" or type(data.aim) ~= "table" then return false end
	-- The map, a menu or the game's own input lock: the game's aim stands.
	if not input.look then return false end
	local a = data.aim
	-- With a mouse the game asks for aim only while aiming, firing or throwing; a pad's aim is the stick.
	local asked = input.aiming or input.fire or input.throw
	if input.kbm and ((a.x or 0) ~= 0 or (a.y or 0) ~= 0) then asked = true end
	if asked and point then
		local from = view.target_position or view.pivot
		local flat = rig.flat_dir(from, point)
		if flat then
			a.x, a.y, a.z = flat.x, flat.y, 0
			return true
		end
	end
	if not input.kbm then a.x, a.y, a.z = 0, 0, 0 end
	return false
end

-- This player's units that fire: the avatar and, in a vehicle, the seat and the guns of that seat.
local function own_units(view)
	local set = { [view.avatar] = true }
	if view.vehicle and view.target then
		set[view.target] = true
		local EA = g("EntityAux")
		pcall(function()
			local seat = EA.state(view.target, "seat")
			local cs = EA.state(view.avatar, "character")
			for i, unit in ipairs(seat.seat_weapon_units or {}) do
				local index = seat.weapon_index_to_seat and seat.weapon_index_to_seat[i]
				if index == nil or index == cs.current_seat_index then set[unit] = true end
			end
		end)
	end
	return set
end

local function wielder_of(unit)
	local EA = g("EntityAux")
	local ok, w = pcall(function()
		if EA.has_component(unit, "equipment") then return EA.state(unit, "equipment").wielder end
		return nil
	end)
	return ok and w or unit
end

-- For each weapon of this player in `slaves` (unit to context), the forward the game will compute and
-- the way to the crosshair point. Answers a list of { f, dir }.
function M.collect(slaves, view, point, quaternion_forward)
	local list = {}
	local U, Q, V3A = g("Unit"), g("Quaternion"), g("Vector3Aux")
	local mine = own_units(view)
	for unit, ctx in pairs(slaves) do
		local wielder = wielder_of(unit)
		if wielder and (mine[wielder] or mine[unit]) and U.alive(wielder) then
			local st = type(ctx) == "table" and (ctx.state or ctx) or {}
			for _, node in ipairs({ type(st.attach_node) == "number" and st.attach_node or 0, 0 }) do
				local rot = U.world_rotation(wielder, node)
				local f = quaternion_forward(rot)
				local p = U.world_position(wielder, 0)
				local origin = { x = p.x, y = p.y, z = p.z + 1 }
				if node ~= 0 and st.ray_source_offset then
					local o = Q.rotate(rot, V3A.unbox(st.ray_source_offset))
					origin = { x = p.x + o.x, y = p.y + o.y, z = p.z + o.z }
				end
				-- A vehicle gun turns slower than the view: it fires the way it points, at the height of the
				-- crosshair point. On foot the shot goes straight to the crosshair point.
				local dir
				if view.vehicle then dir = rig.gun_dir(origin, point, f)
				else dir = rig.shot_dir(origin, point, { x = f.x, y = f.y, z = 0 }) end
				if dir then list[#list + 1] = { f = { x = f.x, y = f.y, z = f.z }, dir = dir } end
			end
		end
	end
	return list
end

-- Laser sights draw from the weapon's own node, and lower the line by 1.5 / range after asking for
-- the forward: the answer is raised by as much (lift), so the line lands on the crosshair point.
function M.collect_lasers(slaves, view, point, quaternion_forward)
	local list = {}
	local U = g("Unit")
	local mine = own_units(view)
	for unit, ctx in pairs(slaves) do
		local st = type(ctx) == "table" and ctx.state or nil
		local wielder = wielder_of(unit)
		if st and st.laser_enabled and wielder and (mine[wielder] or mine[unit]) and U.alive(unit) then
			local node = type(st.attach_node) == "number" and st.attach_node or 0
			local f = quaternion_forward(U.world_rotation(unit, node))
			local p = U.world_position(unit, node)
			local dir = rig.shot_dir({ x = p.x, y = p.y, z = p.z }, point, { x = f.x, y = f.y, z = 0 })
			if dir then
				local lift = type(st.range) == "number" and st.range > 0 and 1.5 / st.range or 0
				list[#list + 1] = { f = { x = f.x, y = f.y, z = f.z }, dir = dir, lift = lift }
			end
		end
	end
	return list
end

local function same(a, b)
	return math.abs(a.x - b.x) < 1e-5 and math.abs(a.y - b.y) < 1e-5 and math.abs(a.z - b.z) < 1e-5
end

-- Runs fn(...) with this player's shots going to the crosshair point.
function M.redirect(list, fn, ...)
	local Q, WU, V3 = g("Quaternion"), g("WeaponUtility"), g("Vector3")
	if #list == 0 or type(Q) ~= "table" or type(WU) ~= "table" then return fn(...) end
	local forward, spread = Q.forward, WU.get_random_spread
	local function aimed_forward(q, ...)
		local f = forward(q, ...)
		for _, o in ipairs(list) do
			if same(f, o.f) then return V3(o.dir.x, o.dir.y, o.dir.z + (o.lift or 0)) end
		end
		return f
	end
	local function level_spread(offset, f, ...)
		for _, o in ipairs(list) do
			if f and same(f, o.dir) then return spread(V3(offset.x, offset.y, 0), f, ...) end
		end
		return spread(offset, f, ...)
	end
	return scoped.swap(Q, "forward", aimed_forward, scoped.swap, WU, "get_random_spread", level_spread, fn, ...)
end

function M.start(env)
	local state = env.state
	local camera = env.camera
	if not camera then return end
	state.aim_point = nil

	table.insert(env.on_pose, function(view, cm)
		local U = g("Unit")
		local tp = U.world_position(view.target, 0)
		view.target_position = { x = tp.x, y = tp.y, z = tp.z }
		local point, hit = M.find_point(view)
		state.aim_point, state.aim_hit = point, hit
		state.crosshair = M.centre(cm)
	end)
	table.insert(env.on_release, function()
		state.aim_point, state.aim_hit = nil, nil
	end)

	local function live()
		return state.active and env.view and state.aim_point and camera.input
	end

	obsidian.hook("InputComponent", "queue_command_master", function(original, self, unit, component, command, data, ...)
		if component == "character" and command == "input" and live() and unit == camera.input.unit then
			pcall(M.steer, data, camera.input, env.view, state.aim_point)
		end
		return original(self, unit, component, command, data, ...)
	end, env.VIEW)

	-- Firearms, beams, flamers and arc throwers: every machine runs update_slaves for every weapon; on
	-- this machine, this player's own weapons fire along the crosshair.
	for _, class in ipairs({ "FirearmComponent", "BeamweaponComponent", "FlameweaponComponent", "ArcweaponComponent" }) do
		obsidian.hook(class, "update_slaves", function(original, self, slaves, dt, ...)
			if not live() or type(slaves) ~= "table" then return original(self, slaves, dt, ...) end
			local ok, list = pcall(M.collect, slaves, env.view, state.aim_point, g("Quaternion").forward)
			if not ok or #list == 0 then return original(self, slaves, dt, ...) end
			return M.redirect(list, original, self, slaves, dt, ...)
		end, env.VIEW)
	end

	obsidian.hook("LaserSightComponent", "update_slaves", function(original, self, slaves, dt, ...)
		if not live() or type(slaves) ~= "table" then return original(self, slaves, dt, ...) end
		local ok, list = pcall(M.collect_lasers, slaves, env.view, state.aim_point, g("Quaternion").forward)
		if not ok or #list == 0 then return original(self, slaves, dt, ...) end
		return M.redirect(list, original, self, slaves, dt, ...)
	end, env.VIEW)

	-- Launchers fire once per call, and set the height of the shot from z_direction.
	obsidian.hook("LauncherComponent", "do_fire", function(original, self, unit, st, ...)
		if not live() or type(st) ~= "table" then return original(self, unit, st, ...) end
		local ok, list = pcall(M.collect, { [unit] = { state = st } }, env.view, state.aim_point, g("Quaternion").forward)
		if not ok or #list == 0 then return original(self, unit, st, ...) end
		local z = list[1].dir.z
		if type(st.z_direction) ~= "number" then return M.redirect(list, original, self, unit, st, ...) end
		return scoped.swap(st, "z_direction", z, M.redirect, list, original, self, unit, st, ...)
	end, env.VIEW)

	-- Grenades and stratagem balls: the game measures the throw from the ground point under the
	-- cursor, through CameraManager:screen_to_world.
	local throwing = false
	local function on() throwing = true end
	local function off() throwing = false end
	for _, class in ipairs({ "CharacterStateThrow", "CharacterStateStratagemsThrow", "CharacterStateDownedThrow",
		"CharacterStateDownedStratagemsThrow" }) do
		obsidian.hook(class, "update", function(original, unit, ...)
			if not live() or unit ~= camera.input.unit then return original(unit, ...) end
			return scoped.around(on, off, original, unit, ...)
		end, env.VIEW)
	end
	obsidian.hook("CameraManager", "screen_to_world", function(original, self, ...)
		local p = state.aim_point
		if throwing and p then return g("Vector3")(p.x, p.y, p.z) end
		return original(self, ...)
	end, env.VIEW)
end

return M
