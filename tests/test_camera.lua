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
		near(d1, 4 * r.AIM_DISTANCE) near(f1, 70 * r.AIM_FOV)
		assert(s1 < 0, "left shoulder")
		local _, _, sv = r.lens({ distance = 7, fov = 75, side = 1, vehicle = true })
		eq(sv, 0, "no shoulder in a vehicle")
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

	{ "movement follows the view only while the game reads input", function()
		local e, env = started()
		local masters = E.player(e, "me")
		frame(e, env, masters)
		local before = CameraManager.follow_spin
		e.mouse = { x = 100, y = 0 }
		frame(e, env, masters)
		e.mouse = { x = 0, y = 0 }
		local seen = frame(e, env, masters)
		local camera = obsidian.module("src/camera")
		near(seen, math.rad(camera.view.yaw), "W moves along the view")
		eq(CameraManager.follow_spin, before, "given back after")
		near(camera.view.yaw, -100 * rig().MOUSE_RATE, "mouse turned the view", 1e-9)
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

	{ "two players on one computer keep the shared top-down view", function()
		local e, env = started()
		local masters = E.player(e, "me")
		e.units.friend = { position = { x = 0, y = 0, z = 0 }, forward = { x = 0, y = 1, z = 0 }, character = {} }
		masters.friend = { state = { pad_number = 1, input_data = { is_active = true } } }
		frame(e, env, masters)
		eq(env.state.active, false)
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
		local want = rig().place({ x = 0, y = 0, z = rig().height("exosuit") }, 0, rig().START_PITCH, 8, 0)
		near(pos.x, 0, "centred", 1e-9) near(pos.y, want.y, "vehicle distance", 1e-6) near(pos.z, want.z, "mech height", 1e-6)
		near(e.calls.set_vertical_fov[2], math.rad(80), "vehicle fov")
		-- Driving reads the movement back through the same yaw.
		local seen = nil
		E.hook("VehicleComponent", "update_masters")(function() seen = CameraManager.follow_spin end, {})
		near(seen, math.rad(obsidian.module("src/camera").view.yaw), "vehicle steering follows the view")
		E.remove()
	end },
}
