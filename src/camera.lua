-- The over-the-shoulder camera, on foot, in vehicles and on the ship.
--
-- The game's CameraManager.update runs as usual and keeps the top-down pose (src/frustum.lua answers
-- the game's rules from it). After it, this module puts the drawn camera at the shoulder: the same
-- engine calls the game's update ends with (Camera.set_local_position and set_local_rotation, the field of
-- view, World.update_unit, the grass observer and the sound listener).
--
-- While the shoulder camera draws, the game's update still works out the top-down pose but never hands
-- it to the engine: Camera.set_local_position and set_local_rotation do nothing while it runs, so each
-- frame places the drawn camera once. With both poses written every frame, the first run in the game
-- (2026-11-11) flickered between the top-down and the shoulder view. The free camera of Obsidian API
-- and Third Person Camera both write one pose a frame.
--
-- Movement follows the view: the game turns the movement keys and the left stick by
-- CameraManager.follow_spin, the top-down camera's. CameraManager.follow_spin itself stays as the game
-- has it, because Obsidian API's bots (and the game's leash) turn their own movement by it in the same
-- update; only the local player's movement commands are turned on by the difference to the view's yaw.
local rig = obsidian.module("src/rig")
local scoped = obsidian.module("src/scoped")
local frustum = obsidian.module("src/frustum")

local M = {}

local function g(name) return rawget(_G, name) end

-- What stops the view, by reason, for tests and the log. Each is a function of (cm).
M.enabled = true      -- the toggle key
M.view = { yaw = nil, pitch = 0, side = 1 }
M.input = nil         -- the local player's input this frame (from InputComponent.update_masters)
M.frame = 0
M.warned = {}
M.dropped = 0         -- lines logged when the view went back to top-down, at most 20 a launch

local smooth = { pivot = nil, length = nil, aim = 0, target = nil }
local saved_near = nil

-- The local player's master of InputComponent: the avatar, the context of that master, and whether another local
-- player (a second pad) shares the screen.
function M.local_master(masters, api)
	if type(masters) ~= "table" then return nil end
	local main = api and api.game and api.game.my_unit and api.game.my_unit() or nil
	local kbm = rawget(_G, "KEYBOARD_MOUSE_PAD_NUMBER")
	local settings = g("GameSettings")
	local main_pad = settings and settings.get_main_pad_number and settings.get_main_pad_number()
	local found, ctx, others = nil, nil, {}
	for unit, c in pairs(masters) do
		local st = type(c) == "table" and c.state
		if st and st.pad_number ~= nil then
			local mine = unit == main or (not main and (st.pad_number == main_pad or st.pad_number == kbm))
			if mine and not found then found, ctx = unit, c else others[#others + 1] = unit end
		end
	end
	-- Obsidian API's bots drive input masters of this machine too, with pads of their own: they don't
	-- share the screen the way a second player does.
	if #others > 0 then
		local bots = api and api.bots and api.bots.all
		local ok, list = pcall(function() return bots and bots() or {} end)
		local bot = {}
		for _, b in ipairs(ok and list or {}) do
			local got, u = pcall(b.unit, b)
			if got and u then bot[u] = true end
		end
		local people = 0
		for _, u in ipairs(others) do if not bot[u] then people = people + 1 end end
		return found, ctx, people > 0
	end
	return found, ctx, false
end

-- Reads what the local player asks of the view this frame, from the input the game is about to use.
-- Answers the snapshot kept in M.input.
function M.read_input(self, unit, ctx, shared, dt)
	local st = ctx.state
	local data = st.input_data
	local kbm = st.pad_number == rawget(_G, "KEYBOARD_MOUSE_PAD_NUMBER")
	local hud = nil
	if self and (self.current_state == "game" or self.current_state == "tutorial") then
		local cc = g("CharacterComponent")
		if cc and cc.get_hud_state then
			local ok, h = pcall(cc.get_hud_state, unit)
			if ok then hud = h end
		end
	end
	local window = g("Window")
	local focused = not (window and window.has_focus) or window.has_focus()
	local active = type(data) == "table" and data.is_active and st.has_focus
	local look = active and focused and not st.character_input_disabled and hud ~= "map" and not st.show_menu_cursor
		and not st.mouse_aim_disabled and true or false
	local fire = active and type(data.fire_button) == "number" and data.fire_button >= 0.5 or false
	local throw = active and type(data.throw) == "number" and data.throw > 0.1 or false
	local aiming = active and kbm and data.aiming_pressed and true or false
	local stick = nil
	if active and not kbm and data.aim then
		local ok, x, y = pcall(function() return data.aim.x, data.aim.y end)
		if ok then stick = { x = x or 0, y = y or 0 } end
	end
	M.input = { frame = M.frame, unit = unit, ctx = ctx, kbm = kbm, look = look, fire = fire, throw = throw,
		aiming = aiming, stick = look and stick or nil, shared = shared, dt = dt }
	return M.input
end

-- Why the view stays top-down now, or nil when the shoulder camera can steer it.
function M.blocked(env, cm)
	if not M.enabled then return "off" end
	if rawget(_G, "HD2CAM_OVERLAY") then return "tpc" end
	local api = env.api
	local cam = api and api.world and api.world.camera
	if cam and cam.taken then
		local ok, taken = pcall(cam.taken)
		if ok and taken then return "taken" end
	end
	if type(cm) ~= "table" or not cm.viewport then return "no_camera" end
	if cm.state ~= "follow" and cm.state ~= "follow_menu" then return "state" end
	local input = M.input
	if not input or M.frame - input.frame > 30 then return "no_input" end
	if input.shared then return "shared" end
	local units = g("Unit")
	if not (input.unit and units and units.alive(input.unit)) then return "no_avatar" end
	return nil
end

-- The unit the camera follows and the vehicle kind, nil on foot.
function M.target(env, avatar)
	local EA = g("EntityAux")
	local ok, cs = pcall(EA.state, avatar, "character")
	local seat = ok and type(cs) == "table" and cs.current_seat_unit or nil
	if seat and g("Unit").alive(seat) then
		local kind = nil
		local vehicles = env.api and env.api.vehicles
		if vehicles and vehicles.kind then
			local got, k = pcall(vehicles.kind, seat)
			if got then kind = k end
		end
		return seat, kind or "turret"
	end
	return avatar, nil
end

local function vec(v) return { x = v.x, y = v.y, z = v.z } end

-- The shortest free length along a line, from three rays: the line and two beside it, so the camera
-- doesn't slip through a gap narrower than the picture. Only static geometry stops it.
function M.clear_length(pw, from, dir, length)
	local PW, V3 = g("PhysicsWorld"), g("Vector3")
	local side = rig.normalize({ x = dir.y, y = -dir.x, z = 0 }) or { x = 1, y = 0, z = 0 }
	local best = nil
	for _, s in ipairs({ 0, 0.2, -0.2 }) do
		local start = rig.add(from, side, s)
		local hit, _, distance = PW.immediate_raycast(pw, V3(start.x, start.y, start.z), V3(dir.x, dir.y, dir.z),
			length + rig.MARGIN, "closest", "types", "statics", "collision_filter", "default")
		if hit and type(distance) == "number" and (not best or distance < best) then best = distance end
	end
	return best
end

local function world_of(cm)
	local proxy = cm.viewport:get_world_proxy()
	return proxy:get_world(), proxy
end

-- Gives the drawn camera back to the game's pose.
function M.release(env, cm)
	local state = env.state
	if not state.active then return end
	state.active, state.vehicle, state.aiming, state.crosshair = false, false, false, nil
	env.view = nil
	smooth.pivot, smooth.length, smooth.aim, smooth.target = nil, nil, 0, nil
	M.view.yaw = nil
	if type(cm) == "table" and cm.viewport then
		pcall(function()
			local C = g("Camera")
			local cam = cm.viewport:get_camera()
			-- The game sets the field of view only when cm.fov changes, so it goes back by hand.
			if cm.fov then C.set_vertical_fov(cam, cm.fov) end
			cm.prev_fov = cm.fov
			if saved_near then C.set_near_range(cam, saved_near) end
		end)
	end
	saved_near = nil
	for _, fn in ipairs(env.on_release) do pcall(fn, cm) end
end

local function quiet() end

-- The game's camera update with the two calls that place the drawn camera left out.
function M.quiet_update(original, self, dt, ...)
	local C = g("Camera")
	if type(C) ~= "table" then return original(self, dt, ...) end
	return scoped.swap(C, "set_local_position", quiet, scoped.swap, C, "set_local_rotation", quiet, original, self, dt, ...)
end

-- The top-down pose on the drawn camera, for a frame where the game's update was kept quiet and the
-- shoulder camera then stopped.
function M.game_pose(cm)
	local C, V3A, QA = g("Camera"), g("Vector3Aux"), g("QuaternionAux")
	local cam, cam_unit = cm.viewport:get_camera(), cm.viewport.camera_unit
	C.set_local_position(cam, cam_unit, V3A.unbox(cm.position))
	C.set_local_rotation(cam, cam_unit, QA.unbox(cm.rotation))
	local world, proxy = world_of(cm)
	if cm.viewport:is_active() and proxy:is_active() then g("World").update_unit(world, cam_unit) end
end

-- One frame of the shoulder camera, after the game's own update.
function M.drive(env, cm, dt)
	local state, config = env.state, env.config
	local why = M.blocked(env, cm)
	if why then
		if state.active and M.dropped < 20 then
			M.dropped = M.dropped + 1
			env.log("Integrated Third Person: top-down view (" .. why .. ")")
		end
		if why == "tpc" and not M.warned.tpc then
			M.warned.tpc = true
			obsidian.toast("Integrated Third Person stays off: Third Person Camera is installed.", 8)
			env.log("Third Person Camera found (HD2CAM_OVERLAY); staying off")
		elseif why == "shared" and not M.warned.shared then
			M.warned.shared = true
			obsidian.toast("Third person needs one player on this computer.", 6)
		end
		M.release(env, cm)
		return false
	end
	local input = M.input
	local avatar = input.unit
	local U, Q, V3, C = g("Unit"), g("Quaternion"), g("Vector3"), g("Camera")
	local target, kind = M.target(env, avatar)
	local view = M.view
	if view.yaw == nil or smooth.target ~= target then
		-- A new view looks the way the Helldiver or the vehicle faces.
		local f = Q.forward(U.world_rotation(target, 0))
		if view.yaw == nil then view.yaw, view.pitch = rig.yaw_of(f), rig.START_PITCH end
		smooth.target = target
		smooth.length = nil
	end
	dt = math.min(math.max(dt or 0.016, 0), 0.1)

	-- Look.
	local aim_t = smooth.aim
	local zoom = 1 + (rig.AIM_FOV - 1) * aim_t
	if input.look and M.frame - input.frame <= 4 then
		rig.look(view, M.mouse_delta(true), input.stick, { speed = config.get("look_speed") or 1, invert = config.get("invert_y"),
			zoom = zoom, dt = dt })
	else
		M.mouse_delta(false) -- drop what moved while the view didn't take it
	end
	smooth.aim = rig.ease(smooth.aim, (input.aiming and not kind) and 1 or 0, 12, dt)
	state.aiming = input.aiming and not kind and true or false

	-- Pivot and lens.
	local p = U.world_position(target, 0)
	local want = { x = p.x, y = p.y, z = p.z + rig.height(kind) }
	smooth.pivot = rig.follow_pivot(smooth.pivot, want, dt)
	local distance, fov, side = rig.lens({
		distance = kind and (config.get("vehicle_distance") or 7) or (config.get("foot_distance") or 3),
		fov = kind and (config.get("vehicle_fov") or 75) or (config.get("foot_fov") or 70),
		side = view.side, aim = smooth.aim, vehicle = kind ~= nil })
	local at, dir, full = rig.place(smooth.pivot, view.yaw, view.pitch, distance, side)

	-- Walls and rocks pull the camera in.
	local world, proxy = world_of(cm)
	local hit = M.clear_length(g("World").physics_world(world), smooth.pivot, dir, full)
	smooth.length = rig.follow_length(smooth.length, rig.pull_in(full, hit), dt)
	local position = rig.add(smooth.pivot, dir, smooth.length)

	-- Apply.
	local cam, cam_unit = cm.viewport:get_camera(), cm.viewport.camera_unit
	local rotation = Q.multiply(Q(V3(0, 0, 1), math.rad(view.yaw)), Q(V3(1, 0, 0), math.rad(view.pitch)))
	C.set_local_position(cam, cam_unit, V3(position.x, position.y, position.z))
	C.set_local_rotation(cam, cam_unit, rotation)
	C.set_vertical_fov(cam, math.rad(fov))
	if saved_near == nil then
		local ok, near = pcall(C.near_range, cam)
		saved_near = ok and near or 0.1
		pcall(C.set_near_range, cam, 0.05)
	end
	if cm.viewport:is_active() and proxy:is_active() then g("World").update_unit(world, cam_unit) end
	local forward = rig.forward(view.yaw, view.pitch)
	-- Grass and scattered detail gather around what the view looks at.
	local scatter = g("ScatterSystem")
	if scatter and cm.scatter_system and cm.observer_id then
		local f = rig.flat_forward(view.yaw)
		pcall(scatter.move_observer, cm.scatter_system, cm.observer_id, V3(smooth.pivot.x + f.x * 20, smooth.pivot.y + f.y * 20, p.z + 10))
	end
	local tw, M4 = g("TimpaniWorld"), g("Matrix4x4")
	if tw and M4 and cm.timpani_world then
		pcall(tw.set_listener, cm.timpani_world, 0, M4.from_quaternion_position(rotation, V3(position.x, position.y, position.z)))
	end

	env.view = { position = position, forward = forward, yaw = view.yaw, pitch = view.pitch, fov = fov, pivot = smooth.pivot,
		avatar = avatar, target = target, vehicle = kind, world = world, camera = cam }
	state.active = true
	state.vehicle = kind ~= nil
	for _, fn in ipairs(env.on_pose) do
		local ok, err = pcall(fn, env.view, cm, dt)
		if not ok and not M.warned[fn] then
			M.warned[fn] = true
			env.log("Integrated Third Person: " .. tostring(err))
		end
	end
	return true
end

-- Mouse movement since the last frame: { x right, y down the screen } in counts. The cursor is kept near
-- the middle of the window, so it never reaches the edge of a windowed game.
local mouse_ids, last_cursor, skip_cursor = nil, nil, false
function M.mouse_delta(recenter)
	local mouse = g("Mouse")
	if not mouse then return nil end
	local ok, out = pcall(function()
		if not mouse_ids then
			local found, delta = pcall(mouse.axis_index, "mouse")
			mouse_ids = { delta = found and delta or nil, cursor = mouse.axis_index("cursor") }
		end
		local cursor = mouse.axis(mouse_ids.cursor)
		local d = nil
		if mouse_ids.delta then
			local v = mouse.axis(mouse_ids.delta)
			d = { x = v.x, y = v.y }
		elseif last_cursor and not skip_cursor then
			-- The cursor's y grows up the screen.
			d = { x = cursor.x - last_cursor.x, y = -(cursor.y - last_cursor.y) }
		end
		skip_cursor = false
		last_cursor = { x = cursor.x, y = cursor.y }
		local w, h = g("Application").resolution()
		if recenter and (math.abs(cursor.x - w / 2) > w * 0.1 or math.abs(cursor.y - h / 2) > h * 0.1) then
			local cursors = g("CursorManager")
			if cursors and cursors.set_cursor_position then
				cursors:set_cursor_position(g("Vector3")(math.floor(w / 2), math.floor(h / 2), 0))
				skip_cursor, last_cursor = true, nil
			end
		end
		return d
	end)
	return ok and out or nil
end

function M.start(env)
	local state = env.state
	env.on_pose = env.on_pose or {}
	env.on_release = env.on_release or {}
	env.frame = function() return M.frame end
	env.camera = M
	M.enabled = obsidian.storage.get("third_person", true) ~= false
	M.view.side = env.config.get("shoulder") == "left" and -1 or 1
	env.config.on_change("shoulder", function(v) M.view.side = v == "left" and -1 or 1 end)

	frustum.install(env)

	-- The input this frame is kept for the camera, and the cursor stays hidden.
	local inside = false
	local function enter() inside = true end
	local function leave() inside = false end
	obsidian.hook("InputComponent", "update_masters", function(original, self, masters, dt, ...)
		local unit, ctx, shared = M.local_master(masters, env.api)
		if unit then M.read_input(self, unit, ctx, shared, dt) end
		if not (state.active and M.view.yaw) then return original(self, masters, dt, ...) end
		if M.input and M.input.look then
			local st = ctx and ctx.state
			-- The software cursor the game eases back to the Helldiver after aiming stays away.
			if st then st.software_cursor_position, st.software_cursor_start_distance = nil, nil end
			local cursors = g("CursorManager")
			if cursors and cursors.is_shown and cursors:is_shown() then cursors:set_show_cursor(false) end
		end
		return scoped.around(enter, leave, original, self, masters, dt, ...)
	end, env.VIEW)

	-- W moves where the camera looks: the local player's movement, which the game turned by the top-down
	-- spin, turns on by the difference to the view's yaw (the mover's set_movement, and the movement
	-- in the character's input, which the Helldiver faces while not aiming).
	obsidian.hook("InputComponent", "queue_command_master", function(original, self, unit, component, command, data, ...)
		local cm = g("CameraManager")
		if inside and state.active and M.view.yaw and M.input and unit == M.input.unit and type(cm) == "table"
			and type(cm.follow_spin) == "number" then
			local turn = rig.spin_of(M.view.yaw) - cm.follow_spin
			if component == "mover" and command == "set_movement" then
				rig.turn_flat(data, turn)
			elseif component == "character" and command == "input" and type(data) == "table" then
				rig.turn_flat(data.movement, turn)
			end
		end
		return original(self, unit, component, command, data, ...)
	end, env.VIEW)

	-- A tank's tracks and a vehicle's turn read the driver's movement back through follow_spin: with this
	-- player's vehicle the only one this machine drives, the view's yaw stands there for that update.
	obsidian.hook("VehicleComponent", "update_masters", function(original, self, masters, ...)
		local cm = g("CameraManager")
		local view = env.view
		if not (state.active and state.vehicle and view and type(cm) == "table" and M.view.yaw and type(masters) == "table"
			and masters[view.target] and next(masters, next(masters)) == nil) then
			return original(self, masters, ...)
		end
		return scoped.swap(cm, "follow_spin", rig.spin_of(M.view.yaw), original, self, masters, ...)
	end, env.VIEW)

	-- While the game reads input under the shoulder camera, the aiming cursor stays hidden and in place.
	obsidian.hook("CursorManager", "set_show_cursor", function(original, self, on, ...)
		if inside and on and state.active and M.input and M.input.look then return original(self, false, ...) end
		return original(self, on, ...)
	end, env.VIEW)
	obsidian.hook("CursorManager", "set_cursor_position", function(original, self, ...)
		if inside and state.active and M.input and M.input.look then return end
		return original(self, ...)
	end, env.VIEW)

	obsidian.hook("CameraManager", "update", function(original, self, dt, ...)
		-- The shoulder camera of the last frame goes on unless something stops it in this one.
		local asked, why = pcall(M.blocked, env, self)
		local still = state.active and asked and why == nil
		local r
		if still then
			r = scoped.pack(M.quiet_update(original, self, dt, ...))
		else
			r = scoped.pack(original(self, dt, ...))
		end
		M.frame = M.frame + 1
		local ok, drove = pcall(M.drive, env, self, dt)
		if not ok then
			if not M.warned.drive then
				M.warned.drive = true
				env.log("Integrated Third Person: camera stopped: " .. tostring(drove))
			end
			pcall(M.release, env, self)
		end
		if still and not (ok and drove) then pcall(M.game_pose, self) end
		return unpack(r, 1, r.n)
	end, env.VIEW)

	obsidian.keybind("toggle_view", function()
		M.enabled = not M.enabled
		obsidian.storage.set("third_person", M.enabled)
		obsidian.toast(M.enabled and "Third person" or "Top-down camera", 2)
	end, env.KEY_VIEW)

	obsidian.keybind("swap_shoulder", function()
		if not state.active or state.vehicle then return end
		M.view.side = -M.view.side
	end, env.KEY_VIEW)
end

return M
