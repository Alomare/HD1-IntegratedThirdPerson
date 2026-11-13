-- The shoulder camera: rig math, collision, look input, camera-relative movement, the top-down
-- frustum kept for the game's rules, and stepping aside.
local E = dofile("tests/engine.lua")

local function rig() return obsidian.module("src/rig") end

-- Starts src/camera.lua on the fake engine and runs one frame of input and camera for `masters`.
local function frame(e, env, masters, dt)
	local update_masters = E.hook("InputComponent", "update_masters")
	local seen = nil
	update_masters(function() seen = CameraManager.follow_spin end, {}, masters, dt or 0.016)
	E.hook("CameraManager", "update")(function() end, CameraManager, dt or 0.016)
	return seen
end

local function started(api)
	local e = E.install()
	local env = E.env(api)
	env.config.start(env)
	obsidian.module("src/camera").start(env)
	return e, env
end

return {
	{ "the game's screen effects on the camera widen with the view and go back after", function()
		local e, env = started()
		local links = {}
		_G.Matrix4x4 = { identity = function() return {} end, set_element = function(m, r, c, v) m[r .. "," .. c] = v end }
		World.link_particles = function(_, id, unit, node, m) links[#links + 1] = { id = id, x = m["1,1"], z = m["3,3"] } end
		CameraManager.camera_particles = {}
		local add = E.hook("CameraManager", "add_camera_particle")
		add(function(self, name) self.camera_particles[name] = "fx" .. name end, CameraManager, "alarm", "fx/alarm", true)
		frame(e, env, E.player(e, "me"))
		local want = math.tan(math.rad(70) / 2) / math.tan(math.rad(60) / 2)
		local last = links[#links]
		eq(last.id, "fxalarm")
		near(last.z, want, "as much wider as the view", 1e-6)
		near(last.x, want * (1920 / 1080) / 1.777778, "with the game's own stretch", 1e-4)
		local n = #links
		frame(e, env, E.player(e, "me"))
		eq(#links, n, "linked once while the view keeps its width")
		obsidian.module("src/camera").release(env, CameraManager)
		near(links[#links].z, 1, "back to the game's size", 1e-9)
		E.remove()
	end },

	{ "rig places the camera behind the pivot and to the shoulder", function()
		local at, dir, length = rig().place({ x = 0, y = 0, z = 1.5 }, 0, 0, 3, 0.65)
		near(at.x, 0.65, "x") near(at.y, -3, "y") near(at.z, 1.5, "z")
		near(length, math.sqrt(9 + 0.65 * 0.65), "length")
		near(rig().length(dir), 1, "unit dir")
		-- Yaw 90 looks along -x; the right side is then +y.
		local at2 = rig().place({ x = 0, y = 0, z = 0 }, 90, 0, 2, 1)
		near(at2.x, 2, "x at yaw 90", 1e-9) near(at2.y, 1, "y at yaw 90", 1e-9)
	end },

	{ "look turns with the mouse, inverts and stops at the pitch limits", function()
		local r = rig()
		local view = { yaw = 0, pitch = 0 }
		r.look(view, { x = 10, y = -5 }, nil, { speed = 1 })
		near(view.yaw, -10 * r.MOUSE_RATE, "yaw") near(view.pitch, 5 * r.MOUSE_RATE, "mouse up looks up")
		local inv = { yaw = 0, pitch = 0 }
		r.look(inv, { x = 0, y = -5 }, nil, { speed = 1, invert = true })
		near(inv.pitch, -5 * r.MOUSE_RATE, "inverted")
		r.look(view, { x = 0, y = -100000 }, nil, { speed = 1 })
		eq(view.pitch, r.PITCH_MAX, "pitch limit")
		-- The stick turns by time, past the dead zone only.
		local pad = { yaw = 0, pitch = 0 }
		r.look(pad, nil, { x = 0.1, y = 0 }, { speed = 1, dt = 1 })
		eq(pad.yaw, 0, "dead zone")
		r.look(pad, nil, { x = 1, y = 0 }, { speed = 1, dt = 0.5 })
		near(pad.yaw, -r.STICK_YAW * 0.5, "full stick")
	end },

	{ "aiming narrows the view and pulls the camera in", function()
		local r = rig()
		local d0, f0, s0 = r.lens({ distance = 4, fov = 70, side = 1, aim = 0 })
		local d1, f1, s1 = r.lens({ distance = 4, fov = 70, side = -1, aim = 1 })
		eq(d0, 4) eq(f0, 70) near(s0, r.SHOULDER)
		near(d1, 4 * r.AIM_DISTANCE) eq(f1, 70, "aiming doesn't zoom")
		assert(s1 < 0, "left shoulder")
		near(s1, -r.SHOULDER * r.AIM_SHOULDER, "aiming brings the camera in behind the head")
		assert(r.AIM_SHOULDER < 1)
		local dm, _, sm = r.lens({ distance = 7, fov = 70, side = 1, vehicle = "exosuit" })
		near(sm, r.MECH_SHOULDER, "a mech camera sits farther to the side")
		near(dm, 7 - r.MECH_SIDE_CLOSER, "and closer")
		local dc = r.lens({ distance = 7, fov = 70, side = 0, vehicle = "exosuit" })
		near(dc, 7, "in the middle the distance is the option's")
		local _, _, sv = r.lens({ distance = 7, fov = 70, side = 0, vehicle = "apc" })
		eq(sv, 0, "middle")
		assert(r.height("apc", 1) < r.height("apc", 0), "beside a vehicle the camera comes down")
		assert(r.height(nil, nil, 1) < r.height(), "a dive brings the pivot down")
	end },

	{ "in a vehicle the swap key goes left, middle, right", function()
		local r = rig()
		eq(r.next_vehicle_side(-1), 0) eq(r.next_vehicle_side(0), 1) eq(r.next_vehicle_side(1), -1)
		eq(r.vehicle_side("exosuit", -1), -1, "a mech starts on the on-foot shoulder")
		eq(r.vehicle_side("exosuit", 1), 1)
		eq(r.vehicle_side("apc", 1), 0, "other vehicles start in the middle")
	end },

	{ "collision pulls in at once and eases back out", function()
		local r = rig()
		eq(r.pull_in(3, nil), 3, "nothing hit")
		near(r.pull_in(3, 1.5), 1.5 - r.MARGIN, "pulled in")
		eq(r.pull_in(3, 0.1), r.MIN_LENGTH, "never inside the pivot")
		eq(r.follow_length(3, 1, 0.016), 1, "in at once")
		local out = r.follow_length(1, 3, 0.016)
		assert(out > 1 and out < 1.2, "out slowly: " .. out)
		-- The same time in small or large frames lands at the same place.
		local a, b = 1, 1
		for _ = 1, 10 do a = r.follow_length(a, 3, 0.01) end
		b = r.follow_length(b, 3, 0.1)
		near(a, b, "frame rate", 1e-9)
	end },

	{ "the pivot follows smoothly and snaps after a teleport", function()
		local r = rig()
		local p = r.follow_pivot({ x = 0, y = 0, z = 0 }, { x = 1, y = 0, z = 1 }, 0.016)
		assert(p.x > 0 and p.x < 1 and p.z > 0 and p.z < p.x, "eases, height slower")
		local s = r.follow_pivot({ x = 0, y = 0, z = 0 }, { x = 100, y = 0, z = 0 }, 0.016)
		eq(s.x, 100, "snap")
	end },

	{ "the camera frame sits behind the Helldiver and a wall pulls it in", function()
		OPTIONS.foot_distance, OPTIONS.foot_fov, OPTIONS.shoulder = 3, 70, "right"
		local e, env = started()
		local masters = E.player(e, "me", { position = { x = 10, y = 20, z = 0 } })
		frame(e, env, masters)
		assert(env.state.active, "active")
		local pos = e.calls.set_local_position[3]
		local want = rig().place({ x = 10, y = 20, z = rig().FOOT_HEIGHT }, 0, rig().START_PITCH, 3, rig().SHOULDER)
		near(pos.x, want.x, "shoulder", 1e-6) near(pos.y, want.y, "behind", 1e-6) near(pos.z, want.z, "height", 1e-6)
		assert(pos.y < 20 and pos.x > 10, "behind and to the right")
		near(e.calls.set_vertical_fov[2], math.rad(70), "fov")
		assert(e.calls.update_unit, "camera unit updated")
		e.hit = 1.5
		frame(e, env, masters)
		local pulled = e.calls.set_local_position[3]
		local d = math.sqrt((pulled.x - 10) ^ 2 + (pulled.y - 20) ^ 2 + (pulled.z - rig().FOOT_HEIGHT) ^ 2)
		near(d, 1.5 - rig().MARGIN, "pulled in", 1e-6)
		E.remove()
	end },

	{ "W moves where the camera looks, and other units keep the game's turn", function()
		local e, env = started()
		local masters = E.player(e, "me")
		frame(e, env, masters)
		e.mouse = { x = 100, y = 0 }
		frame(e, env, masters)
		e.mouse = { x = 0, y = 0 }
		local camera = obsidian.module("src/camera")
		local spin = CameraManager.follow_spin
		local queue = E.hook("InputComponent", "queue_command_master")
		local got, faced = {}, nil
		-- What the game's update_masters does: W turned by the top-down spin, for each master.
		local function game()
			for _, unit in ipairs({ "me", "bot" }) do
				local w = { x = -math.sin(spin), y = math.cos(spin), z = 0 }
				queue(function(_, u, _, _, d) got[u] = d end, {}, unit, "mover", "set_movement", w)
			end
			local input = { movement = { x = -math.sin(spin), y = math.cos(spin), z = 0 } }
			queue(function(_, _, _, _, d) faced = d.movement end, {}, "me", "character", "input", input)
		end
		E.hook("InputComponent", "update_masters")(game, {}, masters, 0.016)
		local f = rig().flat_forward(camera.view.yaw)
		near(got.me.x, f.x, "x", 1e-9) near(got.me.y, f.y, "y", 1e-9)
		near(faced.x, f.x, "character input", 1e-9)
		near(got.bot.x, -math.sin(spin), "a bot keeps the game's turn", 1e-9)
		eq(CameraManager.follow_spin, spin, "follow_spin never changes")
		near(camera.view.yaw, -100 * rig().MOUSE_RATE, "mouse turned the view", 1e-9)
		-- Outside update_masters nothing is turned.
		local later = { x = 0, y = 1, z = 0 }
		queue(function() end, {}, "me", "mover", "set_movement", later)
		eq(later.x, 0)
		E.remove()
	end },

	{ "options change the camera at once", function()
		OPTIONS.foot_distance, OPTIONS.shoulder = 3, "right"
		local e, env = started()
		local masters = E.player(e, "me")
		env.config.set("shoulder", "left")
		env.config.set("foot_distance", 6)
		frame(e, env, masters)
		local pos = e.calls.set_local_position[3]
		local want = rig().place({ x = 0, y = 0, z = rig().FOOT_HEIGHT }, 0, rig().START_PITCH, 6, -rig().SHOULDER)
		near(pos.x, want.x, "left shoulder", 1e-6) near(pos.y, want.y, "new distance", 1e-6)
		E.remove()
	end },

	{ "stays off with a toast while Third Person Camera is installed", function()
		local e, env = started()
		HD2CAM_OVERLAY = { done = true }
		frame(e, env, E.player(e, "me"))
		eq(env.state.active, false, "off")
		eq(e.calls.set_local_position, nil, "camera untouched")
		local toast = false
		for _, l in ipairs(LOGS) do toast = toast or l:find("toast: Integrated Third Person stays off", 1, true) ~= nil end
		assert(toast, "toast")
		E.remove()
	end },

	{ "steps aside while another mod has the camera, and comes back", function()
		local taken = true
		local e, env = started({ world = { camera = { taken = function() return taken end } } })
		local masters = E.player(e, "me")
		frame(e, env, masters)
		eq(env.state.active, false, "taken")
		taken = false
		frame(e, env, masters)
		eq(env.state.active, true, "back")
		E.remove()
	end },

	{ "the toggle key gives the view back to the top-down camera", function()
		local e, env = started()
		local masters = E.player(e, "me")
		frame(e, env, masters)
		eq(env.state.active, true)
		KEYS.toggle_view.fn()
		frame(e, env, masters)
		eq(env.state.active, false, "off")
		eq(STORED.third_person, false, "kept")
		eq(e.calls.set_vertical_fov[2], CameraManager.fov, "game's field of view back")
		E.remove()
	end },

	{ "the game places the drawn camera only while the top-down view is on", function()
		local e, env = started()
		local masters = E.player(e, "me")
		local input, update = E.hook("InputComponent", "update_masters"), E.hook("CameraManager", "update")
		local reached = {}
		local function game()
			e.calls.set_local_position = nil
			Camera.set_local_position("camera", "camera_unit", "top-down")
			reached[#reached + 1] = e.calls.set_local_position ~= nil
		end
		local function step()
			input(function() end, {}, masters, 0.016)
			update(game, CameraManager, 0.016)
		end
		step() step() step()
		eq(reached[1], true, "first frame: the game still places the camera")
		eq(reached[2], false, "then the game's pose stays out of the engine")
		eq(reached[3], false, "every frame after")
		eq(env.state.active, true, "shoulder camera on")
		eq(type(e.calls.set_local_position[3]), "table", "the shoulder pose is the one written")
		eq(rawget(Camera, "set_local_position"), nil, "Camera put back after the game's update")
		KEYS.toggle_view.fn()
		step()
		eq(reached[4], true, "toggled off: the game places the camera again")
		eq(env.state.active, false, "off")
		E.remove()
	end },

	{ "a failing frame puts the top-down pose back on the camera", function()
		local e, env = started()
		local masters = E.player(e, "me")
		frame(e, env, masters)
		frame(e, env, masters)
		eq(env.state.active, true)
		local cam = obsidian.module("src/camera")
		local drive = cam.drive
		cam.drive = function() error("broken frame") end
		e.calls.set_local_position = nil
		frame(e, env, masters)
		cam.drive = drive
		eq(env.state.active, false, "released")
		local pos = e.calls.set_local_position and e.calls.set_local_position[3]
		assert(pos, "a pose was written")
		eq(pos.x .. "," .. pos.y .. "," .. pos.z, "0,-10,17", "the game's top-down pose")
		E.remove()
	end },

	{ "two players on one computer keep the shared top-down view", function()
		local e, env = started()
		local masters = E.player(e, "me")
		e.units.friend = { position = { x = 0, y = 0, z = 0 }, forward = { x = 0, y = 1, z = 0 }, character = {} }
		masters.friend = { state = { pad_number = 1, input_data = { is_active = true } } }
		frame(e, env, masters)
		eq(env.state.active, false)
		E.remove()
	end },

	{ "a second player joining turns third person off with a message, and leaving brings it back", function()
		local e, env = started()
		local cam = obsidian.module("src/camera")
		local function said(text)
			local n = 0
			for _, l in ipairs(LOGS) do if l == "toast: " .. text then n = n + 1 end end
			return n
		end
		local masters = E.player(e, "me")
		frame(e, env, masters)
		eq(env.state.active, true, "one player")
		e.units.friend = { position = { x = 0, y = 0, z = 0 }, forward = { x = 0, y = 1, z = 0 }, character = {} }
		masters.friend = { state = { pad_number = 1, input_data = { is_active = true } } }
		frame(e, env, masters)
		frame(e, env, masters)
		eq(env.state.active, false, "two players share the screen")
		eq(said(cam.SHARED_TEXT), 1, "the reason, once")
		masters.friend = nil
		frame(e, env, masters)
		eq(env.state.active, true, "one player again")
		eq(said(cam.BACK_TEXT), 1, "back, said once")
		E.remove()
	end },

	{ "a dive brings the camera in fast, and eases it back out after", function()
		local e, env = started()
		local masters = E.player(e, "me")
		e.units.me.health = { is_dodging = false }
		local function back()
			local v = env.view
			return rig().dot(rig().sub(v.pivot, v.position), v.forward)
		end
		for _ = 1, 30 do frame(e, env, masters, 0.05) end
		local before = back()
		near(before, 5, "the on-foot distance", 1e-3)
		local high = env.view.pivot.z
		e.units.me.health.is_dodging = true
		frame(e, env, masters, 0.05)
		local first = back()
		assert(first < before and first > before * rig().DIVE_DISTANCE + 0.1, "on the way in, not there at once: " .. first)
		for _ = 1, 20 do frame(e, env, masters, 0.05) end
		near(back(), before * rig().DIVE_DISTANCE, "close in", 1e-2)
		near(env.view.pivot.z, high - rig().DIVE_DROP, "down toward the Helldiver", 1e-2)
		e.units.me.health.is_dodging = false
		frame(e, env, masters, 0.05)
		assert(back() < before * 0.8, "backs out more slowly than it came in: " .. back())
		for _ = 1, 80 do frame(e, env, masters, 0.05) end
		near(back(), before, "all the way out", 1e-2)
		OPTIONS.dive_camera = false
		e.units.me.health.is_dodging = true
		for _ = 1, 5 do frame(e, env, masters, 0.05) end
		near(back(), before, "option off: no close-up", 1e-2)
		E.remove()
	end },

	{ "the shoulder swap eases across instead of jumping", function()
		local e, env = started()
		local masters = E.player(e, "me")
		local function side()
			local v = env.view
			return rig().dot(rig().sub(v.position, v.pivot), rig().right(v.yaw))
		end
		for _ = 1, 5 do frame(e, env, masters, 0.05) end
		near(side(), rig().SHOULDER, "right shoulder", 1e-6)
		KEYS.swap_shoulder.fn()
		frame(e, env, masters, 0.05)
		local s = side()
		assert(s < rig().SHOULDER - 0.1 and s > -rig().SHOULDER + 0.1, "on the way across: " .. s)
		for _ = 1, 40 do frame(e, env, masters, 0.05) end
		near(side(), -rig().SHOULDER, "left shoulder", 1e-3)
		E.remove()
	end },

	{ "name cards go above heads in the shoulder view", function()
		local e, env = started()
		local masters = E.player(e, "me")
		frame(e, env, masters)
		local seen = {}
		local w2v, hud = E.hook("ViewportProxy", "world_to_viewport"), E.hook("Hud", "pre_update_and_draw_hud")
		local function project(_, p) seen[#seen + 1] = p.z return p end
		local function game()
			w2v(project, e.viewport, E.V3(0, 0, 0))
			w2v(project, e.viewport, E.V3(0, 0, 0))
		end
		hud(game, {})
		eq(seen[1], obsidian.module("src/frustum").NAME_HEIGHT, "the feet point goes above the head")
		eq(seen[2], 0, "only the first projection of each card")
		seen = {}
		OPTIONS.names_above = false
		hud(game, {})
		eq(seen[1], 0, "option off: at the feet")
		E.remove()
	end },

	{ "Obsidian API bots on this machine don't count as a second player", function()
		local bot = { unit = function() return "bot" end }
		local e, env = started({ bots = { all = function() return { bot } end } })
		local masters = E.player(e, "me")
		e.units.bot = { position = { x = 0, y = 0, z = 0 }, forward = { x = 0, y = 1, z = 0 }, character = {} }
		masters.bot = { state = { pad_number = 3, input_data = { is_active = true } } }
		frame(e, env, masters)
		eq(env.state.active, true)
		E.remove()
	end },

	{ "the game's rules see the top-down screen, the HUD sees the view", function()
		local e, env = started()
		local masters = E.player(e, "me")
		frame(e, env, masters)
		local fr = obsidian.module("src/frustum")
		-- The real viewport answers for the third-person view: everything is "behind" here.
		ViewportProxy = { world_to_viewport = function() return E.V3(-1, -1, -1) end }
		local w2v = E.hook("ViewportProxy", "world_to_viewport")
		local inside = function(self, p)
			local v = w2v(ViewportProxy.world_to_viewport, self.viewport, p)
			return v.x >= 0 and v.x <= 1920 and v.z >= 0 and v.z <= 1080
		end
		local rules = E.hook("CameraManager", "is_position_inside_frustum")
		-- A point straight ahead of the top-down camera, on the ground.
		local cam = fr.top_down(CameraManager)
		local ahead = rig().add(cam.position, cam.forward, 20)
		eq(rules(inside, CameraManager, ahead), true, "rules: inside the top-down screen")
		local draw = E.hook("Hud", "draw_plugins")
		local got = nil
		draw(function() got = rules(inside, CameraManager, ahead) end)
		eq(got, false, "HUD: the real view")
		ViewportProxy = nil
		E.remove()
	end },

	{ "top-down projection and the inverse agree", function()
		local fr = obsidian.module("src/frustum")
		local cam = fr.camera_from({ x = 0, y = -10, z = 17 }, { x = 0, y = 0.5, z = -0.866 }, math.rad(60))
		local x, depth, y = fr.project(cam, { x = 3, y = 2, z = 0 }, 1920, 1080)
		local p = fr.unproject(cam, x, y, depth, 1920, 1080)
		near(p.x, 3, "x", 1e-6) near(p.y, 2, "y", 1e-6) near(p.z, 0, "z", 1e-6)
		local cx, _, cy = fr.project(cam, rig().add(cam.position, cam.forward, 10), 1920, 1080)
		near(cx, 960, "centre x", 1e-6) near(cy, 540, "centre y", 1e-6)
	end },

	{ "points behind the view go off screen for drawing", function()
		local e, env = started()
		frame(e, env, E.player(e, "me"))
		local w2s = E.hook("CameraManager", "world_to_screen")
		local v = w2s(function() return E.V3(500, 500, -3) end, CameraManager, E.V3())
		eq(v.x, -100000) eq(v.z, -3, "depth kept")
		local front = w2s(function() return E.V3(500, 500, 3) end, CameraManager, E.V3())
		eq(front.x, 500)
		E.remove()
	end },

	{ "a vehicle uses the vehicle distance and field of view", function()
		OPTIONS.vehicle_distance, OPTIONS.vehicle_fov = 8, 80
		local e, env = started({ vehicles = { kind = function() return "exosuit" end } })
		local masters = E.player(e, "me", { seat = "mech" })
		e.units.mech = { position = { x = 0, y = 0, z = 0 }, forward = { x = 0, y = 1, z = 0 } }
		frame(e, env, masters)
		eq(env.state.vehicle, true)
		local pos = e.calls.set_local_position[3]
		local want = rig().place({ x = 0, y = 0, z = rig().height("exosuit", 1) }, 0, rig().START_PITCH, 8 - rig().MECH_SIDE_CLOSER, rig().MECH_SHOULDER)
		near(pos.x, want.x, "beside the right shoulder", 1e-6) near(pos.y, want.y, "vehicle distance", 1e-6)
		near(pos.z, want.z, "mech height", 1e-6)
		KEYS.swap_shoulder.fn()
		eq(obsidian.module("src/camera").ride.side, -1, "right to left")
		KEYS.swap_shoulder.fn()
		eq(obsidian.module("src/camera").ride.side, 0, "left to the middle")
		for _ = 1, 60 do frame(e, env, masters) end
		pos = e.calls.set_local_position[3]
		near(pos.x, 0, "middle", 1e-3)
		near(e.calls.set_vertical_fov[2], math.rad(80), "vehicle fov")
		-- Driving reads the movement back through the same yaw.
		local seen = nil
		E.hook("VehicleComponent", "update_masters")(function() seen = CameraManager.follow_spin end, {}, { mech = {} })
		near(seen, math.rad(obsidian.module("src/camera").view.yaw), "vehicle steering follows the view")
		E.remove()
	end },
}
