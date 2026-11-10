-- Aim: the crosshair ray, the character's aim input, shots along the crosshair, throws, the crosshair.
local E = dofile("tests/engine.lua")

local function rig() return obsidian.module("src/rig") end

local function started(api)
	local e = E.install()
	local env = E.env(api)
	env.config.start(env)
	obsidian.module("src/camera").start(env)
	obsidian.module("src/aim").start(env)
	return e, env
end

local function frame(e, env, masters)
	E.hook("InputComponent", "update_masters")(function() end, {}, masters, 0.016)
	E.hook("CameraManager", "update")(function() end, CameraManager, 0.016)
end

return {
	{ "the crosshair ray starts past the Helldiver and skips the own body", function()
		local e, env = started()
		local masters = E.player(e, "me")
		e.aim_hit = { pos = { x = 0, y = 30, z = 1 }, unit = "rock" }
		frame(e, env, masters)
		local p = env.state.aim_point
		eq(p.y, 30, "hit point") eq(env.state.aim_hit, true)
		eq(env.state.crosshair.x, 960) eq(env.state.crosshair.y, 540)
		-- Only the own body on the line: the point is the far end of the ray.
		e.aim_hit = { pos = { x = 0, y = 2, z = 1 }, unit = "me" }
		local calls = 0
		local cast = PhysicsWorld.immediate_raycast
		PhysicsWorld.immediate_raycast = function(...)
			local args = { ... }
			if args[6] == "collision_filter" then calls = calls + 1 if calls > 1 then return false end end
			return cast(...)
		end
		frame(e, env, masters)
		eq(env.state.aim_hit, false, "own body skipped")
		assert(env.state.aim_point.y > 200, "far end")
		E.remove()
	end },

	{ "ray start sits past the pivot", function()
		local r = rig()
		local s = r.ray_start({ x = 0, y = -3, z = 1.5 }, { x = 0, y = 1, z = 0 }, { x = 0, y = 0, z = 1.5 })
		near(s, 3.5, "past the pivot")
		eq(r.ray_start({ x = 0, y = 0, z = 0 }, { x = 0, y = 1, z = 0 }, { x = 0, y = -5, z = 0 }), 0.5, "pivot behind")
	end },

	{ "the aim input points at the crosshair while aiming, and a pad stick stops turning the body", function()
		local aim = obsidian.module("src/aim")
		local view = { pivot = { x = 0, y = 0, z = 1.5 }, target_position = { x = 0, y = 0, z = 0 } }
		local data = { aim = { x = 0, y = 0, z = 0 } }
		eq(aim.steer(data, { look = true, kbm = true, aiming = true }, view, { x = 10, y = 10, z = 5 }), true)
		near(data.aim.x, math.sqrt(0.5)) near(data.aim.y, math.sqrt(0.5)) eq(data.aim.z, 0, "flat")
		local idle = { aim = { x = 0, y = 0, z = 0 } }
		eq(aim.steer(idle, { look = true, kbm = true }, view, { x = 10, y = 0, z = 0 }), false, "not aiming: the game's own")
		eq(idle.aim.x, 0)
		local pad = { aim = { x = 1, y = 0, z = 0 } }
		aim.steer(pad, { look = true, kbm = false }, view, { x = 0, y = 10, z = 0 })
		eq(pad.aim.x, 0, "stick looks, not turns") eq(pad.aim.y, 0)
		local firing = { aim = { x = 0, y = 0, z = 0 } }
		aim.steer(firing, { look = true, kbm = false, fire = true }, view, { x = 0, y = 10, z = 0 })
		near(firing.aim.y, 1, "pad fires at the crosshair")
	end },

	{ "the queued aim command of this player is steered", function()
		local e, env = started()
		local masters = E.player(e, "me", { aiming = true })
		e.aim_hit = { pos = { x = 5, y = 5, z = 0 }, unit = "rock" }
		frame(e, env, masters)
		local queue = E.hook("InputComponent", "queue_command_master")
		local data = { aim = { x = 0, y = 1, z = 0 } }
		local got = nil
		queue(function(_, _, _, _, d) got = d end, {}, "me", "character", "input", data)
		near(got.aim.x, math.sqrt(0.5)) near(got.aim.y, math.sqrt(0.5))
		local other = { aim = { x = 0, y = 1, z = 0 } }
		queue(function() end, {}, "bot", "character", "input", other)
		eq(other.aim.y, 1, "other units untouched")
		E.remove()
	end },

	{ "shot directions: to the point, nil when too close or behind", function()
		local r = rig()
		local d = r.shot_dir({ x = 0, y = 0, z = 1.4 }, { x = 0, y = 30, z = 11.4 }, { x = 0, y = 1, z = 0 })
		near(d.z, 10 / math.sqrt(900 + 100), "pitch included")
		eq(r.shot_dir({ x = 0, y = 0, z = 0 }, { x = 0, y = 1, z = 0 }), nil, "too close")
		eq(r.shot_dir({ x = 0, y = 0, z = 0 }, { x = 0, y = -10, z = 0 }, { x = 0, y = 1, z = 0 }), nil, "behind")
	end },

	{ "this player's weapon fires along the crosshair with no dip, only during the call", function()
		local e = E.install()
		local aim = obsidian.module("src/aim")
		e.units.me = { position = { x = 0, y = 0, z = 0 }, forward = { x = 0, y = 1, z = 0 } }
		e.units.gun = { position = { x = 0, y = 0, z = 0 }, forward = { x = 0, y = 1, z = 0 }, equipment = { wielder = "me" } }
		e.units.their_gun = { position = { x = 5, y = 0, z = 0 }, forward = { x = 1, y = 0, z = 0 }, equipment = { wielder = "them" } }
		e.units.them = { position = { x = 5, y = 0, z = 0 }, forward = { x = 1, y = 0, z = 0 } }
		local view = { avatar = "me", target = "me" }
		local point = { x = 0, y = 30, z = 11 }
		local slaves = { gun = { state = { attach_node = 3 } }, their_gun = { state = { attach_node = 3 } } }
		local list = aim.collect(slaves, view, point, Quaternion.forward)
		assert(#list >= 1, "own gun found")
		for _, o in ipairs(list) do eq(o.f.x, 0, "only the own forward") end
		local spread_calls = {}
		WeaponUtility = { get_random_spread = function(offset, f) spread_calls[#spread_calls + 1] = offset.z return f end }
		local mine, theirs, offset_z
		aim.redirect(list, function()
			mine = Quaternion.forward(Unit.world_rotation("me", 3))
			theirs = Quaternion.forward(Unit.world_rotation("them", 3))
			WeaponUtility.get_random_spread(E.V3(0.2, 0.5, 1.4), mine, 0.01, 30)
			WeaponUtility.get_random_spread(E.V3(0.2, 0.5, 1.4), theirs, 0.01, 30)
		end)
		assert(mine.z > 0.3, "pitched up at the point: " .. mine.z)
		eq(theirs.x, 1, "another player's gun untouched")
		eq(spread_calls[1], 0, "no dip for the own shot") eq(spread_calls[2], 1.4, "dip kept for others")
		eq(Quaternion.forward(Unit.world_rotation("me", 3)).z, 0, "given back after the call")
		WeaponUtility = nil
		E.remove()
	end },

	{ "a laser sight on this player's weapon lands on the crosshair point", function()
		local e = E.install()
		local aim = obsidian.module("src/aim")
		e.units.me = { position = { x = 0, y = 0, z = 0 }, forward = { x = 0, y = 1, z = 0 } }
		e.units.gun = { position = { x = 0, y = 0, z = 1.4 }, forward = { x = 0, y = 1, z = 0 }, equipment = { wielder = "me" } }
		local slaves = { gun = { state = { laser_enabled = true, attach_node = 2, range = 30 } } }
		local list = aim.collect_lasers(slaves, { avatar = "me", target = "me" }, { x = 0, y = 30, z = 1.4 }, Quaternion.forward)
		eq(#list, 1)
		WeaponUtility = { get_random_spread = function() end }
		local got = nil
		aim.redirect(list, function()
			local f = Quaternion.forward(Unit.world_rotation("gun", 2))
			f.z = f.z - 1.5 / 30 -- what the game does next
			got = f
		end)
		near(got.z, 0, "level after the game's own lowering", 1e-9)
		WeaponUtility = nil
		E.remove()
	end },

	{ "a grenade throw measures to the crosshair point", function()
		local e, env = started()
		local masters = E.player(e, "me")
		e.aim_hit = { pos = { x = 0, y = 12, z = 0 }, unit = "ground" }
		frame(e, env, masters)
		local throw = E.hook("CharacterStateThrow", "update")
		local s2w = E.hook("CameraManager", "screen_to_world")
		local got = nil
		throw(function(unit) got = s2w(function() return "cursor" end, CameraManager, E.V3()) end, "me")
		eq(got.y, 12, "crosshair point")
		eq(s2w(function() return "cursor" end, CameraManager, E.V3()), "cursor", "outside a throw")
		E.remove()
	end },

	{ "the crosshair hides when claimed, for a picture, or on the map", function()
		local cross = obsidian.module("src/crosshair")
		local busy = false
		local env = { state = { active = true, crosshair = { x = 1, y = 1 } },
			api = { capture = { busy = function() return busy end }, map = { is_open = function() return false end } } }
		eq(cross.visible(env), true)
		busy = true
		eq(cross.visible(env), false, "picture")
		busy = false
		env.state.claimed_by = "alomare.customcrosshair"
		eq(cross.visible(env), false, "claimed")
		env.state.claimed_by, env.state.active = nil, false
		eq(cross.visible(env), false, "top-down")
		eq(#cross.shape(100, 100, false), 5)
	end },
}
