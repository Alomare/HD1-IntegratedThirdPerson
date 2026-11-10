-- View: the long view, the sky and the ship walls.
local E = dofile("tests/engine.lua")

local function view() return obsidian.module("src/view") end

local function started(api)
	local e = E.install()
	local env = E.env(api)
	env.config.start(env)
	obsidian.module("src/camera").start(env)
	view().start(env)
	return e, env
end

local function frame(e, env, masters)
	E.hook("InputComponent", "update_masters")(function() end, {}, masters, 0.016)
	E.hook("CameraManager", "update")(function() end, CameraManager, 0.016)
end

-- A fake API that records shading and detail calls.
local function api(calls, in_mission)
	return {
		game = { in_mission = function() return in_mission end },
		world = {
			planet_shading = function(name)
				if name == "fog_depth_range" then return { 20, 120 } end
				if name == "fog_color" then return { 0.31, 0.30, 0.275 } end
			end,
			shading = function(name, kind, value) calls[#calls + 1] = { name, kind, value } return true end,
			detail = function(v) calls.detail = v return true end,
		},
	}
end

return {
	{ "fog range, sky choice and sky brightness", function()
		local v = view()
		local r = v.fog_range({ 20, 120 }, 2.5)
		eq(r[1], 50) eq(r[2], 300)
		eq(v.fog_range(nil, 2), nil)
		eq(v.sky_name("desert", "day"), "desert")
		eq(v.sky_name(4, "dusk"), "lava", "index in the API's order")
		eq(v.sky_name("snow", "night"), "night")
		eq(v.sky_name(nil, nil), "desert", "a known sky when unsure")
		near(v.sky_intensity("desert", { 0.31, 0.30, 0.275 }), 1, "half as bright as drawn", 1e-3)
		eq(v.sky_intensity("desert", nil), 2, "the dome's own")
	end },

	{ "the wall goes across from the window, and fills the open side", function()
		local v = view()
		local bounds = { min = { x = 0, y = 0, z = 0 }, max = { x = 20, y = 10, z = 6 } }
		-- Panels along y-, x- and x+; none along y+ (the window).
		local panels = { { x = 5, y = 1, z = 2 }, { x = 15, y = 1, z = 2 }, { x = 1, y = 5, z = 2 }, { x = 19, y = 5, z = 2 } }
		local side, window = v.wall_side(bounds, panels)
		eq(window, "y+") eq(side, "y-")
		local slots = v.wall_layout(bounds, "y-", 4, 3)
		local wall = 0
		for _, s in ipairs(slots) do
			if s.facing.z == 0 then
				wall = wall + 1
				eq(s.position.y, 0, "on the edge") eq(s.facing.y, 1, "facing in")
				assert(s.position.z > 0 and s.position.z < 6, "floor to ceiling")
			else
				eq(s.position.z, 6, "ceiling") eq(s.facing.z, -1)
			end
		end
		eq(wall, 5 * 2, "columns by rows")
	end },

	{ "the long view pushes the fog and the far range out, and gives them back", function()
		OPTIONS.far_view = true
		local calls = {}
		local e, env = started(api(calls, true))
		local masters = E.player(e, "me")
		frame(e, env, masters)
		eq(calls[1][1], "fog_depth_range") eq(calls[1][3][2], 300)
		eq(calls.detail, view().DETAIL)
		eq(e.calls.set_far_range[2], view().FAR)
		KEYS.toggle_view.fn()
		frame(e, env, masters)
		eq(calls[2][1], "fog_depth_range") eq(calls[2][3], nil, "the planet's fog back")
		eq(calls.detail, nil, "the game's detail back")
		E.remove()
	end },

	{ "no sky is spawned when the skies were not deployed", function()
		OPTIONS.fix_sky = false
		local e, env = started(api({}, true))
		local spawned = 0
		World.spawn_unit = function() spawned = spawned + 1 return "dome" end
		frame(e, env, E.player(e, "me"))
		eq(spawned, 0)
		OPTIONS.fix_sky = true
		World.units = function() return {} end
		Unit.set_local_scale = function() end
		Unit.teleport_local_position = function() end
		e.units.dome = { position = { x = 0, y = 0, z = 0 } }
		local name = nil
		World.spawn_unit = function(_, n) name = n spawned = spawned + 1 return "dome" end
		frame(e, env, E.player(e, "me"))
		eq(spawned, 1) eq(name, "itp/sky/desert")
		frame(e, env, E.player(e, "me"))
		eq(spawned, 1, "one dome, moved with the camera")
		E.remove()
	end },
}
