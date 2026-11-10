-- src/radar.lua: bearings from the camera, closeness, merging, the marks, and a frame against
-- stand-ins for the engine.
local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local function radar() return obsidian.module("src/radar") end

-- Pure parts -------------------------------------------------------------------------------------

test("radar heading follows the camera over the ground", function()
	local r = radar()
	local x, y = r.heading(0, 1, 0)
	near(x, 0, "level x")
	near(y, 1, "level y")
	-- The top-down camera: 65 degrees down, facing north.
	x, y = r.heading(0, math.cos(math.rad(65)), -math.sin(math.rad(65)), 0, math.sin(math.rad(65)))
	near(y, 1, "top-down faces north")
	-- Straight down: up points to the top of the screen.
	x, y = r.heading(0, 0, -1, 1, 0)
	near(x, 1, "straight down takes up")
	-- Steeply up: up points backward, so it turns round.
	x, y = r.heading(0, 0.05, 0.998, 0, -0.998)
	near(y, 1, "steeply up")
	eq(r.heading(0, 0, -1, 0, 0), nil, "no ground direction at all")
end)

test("radar bearing is degrees to the right of the facing", function()
	local r = radar()
	near(r.bearing(0, 10, 0, 1), 0, "ahead")
	near(r.bearing(10, 0, 0, 1), 90, "right (east, facing north)")
	near(r.bearing(-10, 0, 0, 1), -90, "left")
	near(math.abs(r.bearing(0, -10, 0, 1)), 180, "behind")
	near(r.bearing(0, 10, 1, 0), -90, "north is left when facing east")
	near(r.bearing(5, 5, 0, 1), 45, "ahead right")
end)

test("radar angle gaps wrap round", function()
	local r = radar()
	near(r.angle_gap(170, -170), 20, "across the back")
	near(r.angle_gap(-170, 170), -20, "the other way")
	near(r.angle_gap(10, 30), 20, "plain")
end)

test("radar closeness runs from the player to the range", function()
	local r = radar()
	near(r.closeness(0, 35), 1, "at the player")
	near(r.closeness(17.5, 35), 0.5, "half way")
	near(r.closeness(35, 35), 0, "at the range")
	near(r.closeness(50, 35), 0, "past the range")
	near(r.closeness(5, 0), 0, "no range")
end)

test("radar behind is past the side", function()
	local r = radar()
	eq(r.behind(119), false, "side")
	eq(r.behind(121), true, "back right")
	eq(r.behind(-150), true, "back left")
end)

test("radar big enemies by the game marks, base and hitpoints", function()
	local r = radar()
	eq(r.is_big({ heavy = true }, 100), true, "heavy (Tank)")
	eq(r.is_big({ health_info = { large = true } }, 100), true, "large (Hulk to be killed)")
	eq(r.is_big({ unit_radius = 1 }, 300), true, "wide base (Strider)")
	eq(r.is_big({ unit_radius = 0.5 }, 2000), true, "many hitpoints (Hulk)")
	eq(r.is_big({ unit_radius = 0.5, health_info = { large = false } }, 120), false, "a warrior")
	eq(r.is_big(nil, nil), false, "nothing known")
end)

test("radar pool keeps the nearest first and reuses records", function()
	local r = radar()
	local pool, n = {}, 0
	for i, d in ipairs({ 30, 10, 20, 5, 25 }) do n = r.insert(pool, n, 3, d, i, false, false) end
	eq(n, 3, "capped")
	eq(pool[1].d .. "," .. pool[2].d .. "," .. pool[3].d, "5,10,20", "nearest three in order")
	local tables = {}
	for i = 1, 3 do tables[pool[i]] = true end
	n = 0
	for _, d in ipairs({ 8, 2, 40, 1 }) do n = r.insert(pool, n, 3, d, 0, false, false) end
	eq(pool[1].d .. "," .. pool[2].d .. "," .. pool[3].d, "1,2,8", "next frame")
	for i = 1, 3 do eq(tables[pool[i]], true, "record " .. i .. " reused") end
end)

test("radar close bearings merge into the nearest", function()
	local r = radar()
	local pool, n = {}, 0
	n = r.insert(pool, n, 10, 5, 10, false, true)
	n = r.insert(pool, n, 10, 9, 18, true, false)    -- 8 degrees off: joins
	n = r.insert(pool, n, 10, 12, 60, false, false)  -- own mark
	n = r.insert(pool, n, 10, 7, 175, false, false)
	n = r.insert(pool, n, 10, 8, -178, false, false) -- across the back: joins
	local marks = {}
	local m = r.merge(pool, n, marks, 8, 14)
	eq(m, 3, "marks")
	eq(marks[1].bearing, 10, "nearest bearing kept")
	eq(marks[1].count, 2, "two in the first")
	eq(marks[1].big, true, "big carries over")
	eq(marks[1].in_view, false, "in view only if every one is")
	eq(marks[2].bearing, 175, "behind")
	eq(marks[2].behind, true, "behind flag")
	eq(marks[2].count, 2, "merged across 180")
	eq(r.merge(pool, n, marks, 1, 14), 1, "capped")
end)

test("radar marks grow and strengthen as enemies close in", function()
	local r = radar()
	eq(r.size(1, false, 1) > r.size(0, false, 1), true, "near is larger")
	eq(r.size(0.5, true, 1) > r.size(0.5, false, 1), true, "big is larger")
	eq(r.size(0.5, false, 3) > r.size(0.5, false, 1), true, "merged is larger")
	eq(r.size(0.5, false, 50), r.size(0.5, false, 1 + r.MERGED_MAX), "merging stops growing")
	eq(r.alpha(1, false) > r.alpha(0, false), true, "near is stronger")
	near(r.alpha(1, true), r.alpha(1, false) * r.IN_VIEW, "in view fades")
end)

test("radar triangles point outward from the ring", function()
	local r = radar()
	local out = {}
	r.triangle(out, 100, 100, r.screen_angle(0), 50, 10, 4)
	near(out[5], 100, "ahead: tip above the centre x")
	near(out[6], 160, "tip 50 + 10 up")
	near(out[2], 150, "base 50 up")
	near(math.abs(out[1] - out[3]), 8, "base width")
	r.triangle(out, 100, 100, r.screen_angle(90), 50, 10, 4)
	near(out[5], 160, "right: tip to the right")
	near(out[6], 100, "right: level")
	r.triangle(out, 100, 100, r.screen_angle(180), 50, 10, 4)
	near(out[6], 40, "behind: tip below")
end)

-- The game ---------------------------------------------------------------------------------------

local function game(options)
	options = options or {}
	local kit = { calls = {} }
	function kit:poly(pts, c) self.calls[#self.calls + 1] = { "poly", { unpack(pts) }, a = c[4] } end
	function kit:outline(pts, c, w) self.calls[#self.calls + 1] = { "outline", { unpack(pts) }, a = c[4], w = w } end
	local current = { screen = "hud" }
	obsidian.ui = {
		canvas = function(id, opts) kit.id, kit.layer = id, opts.layer return kit end,
		current = function() return current end,
	}
	local me = "me"
	local pos = { me = { x = 0, y = 0, z = 0 } }
	local health = {}
	local settings = {}
	local enemies = {}
	local function enemy(name, x, y, opts)
		opts = opts or {}
		pos[name] = { x = x, y = y, z = 0 }
		health[name] = { is_dead = opts.dead or false, max_hitpoints = opts.hp or 150 }
		settings[name] = opts.settings or { unit_radius = 0.5 }
		enemies[name] = { state = {} }
	end
	local screen = { x = 0, y = 0, z = 1 }
	local probe = { x = 0, y = 0, z = 0 }
	local world
	world = {
		map_open = false,
		Unit = {
			alive = function(u) return pos[u] ~= nil end,
			world_position = function(u) if world.broken then error("level gone") end return pos[u] end,
		},
		EntityAux = { state = function(u, c) return c == "health" and health[u] or nil end },
		LuaSettingsManager = { get_settings_by_unit = function(_, u) world.lookups = world.lookups + 1 return settings[u] end },
		Vector3 = function(x, y, z) probe.x, probe.y, probe.z = x, y, z return probe end,
		Camera = { world_rotation = function() return "rot" end },
		Quaternion = {
			-- Facing north, 65 degrees down, as the top-down camera does.
			forward = function() return { x = 0, y = 0.42, z = -0.91 } end,
			up = function() return { x = 0, y = 0.91, z = 0.42 } end,
		},
		CameraManager = {
			viewport = { get_camera = function() return "cam" end, window = function() return 1920, 1080, 0, 0 end },
			-- On screen: anything 5 m or more north of the player.
			world_to_screen = function(_, v)
				screen.x = v.y >= 5 and 900 or -50
				screen.y = 600
				return screen
			end,
		},
		lookups = 0,
	}
	for _, name in ipairs({ "Unit", "EntityAux", "LuaSettingsManager", "Vector3", "Camera", "Quaternion", "CameraManager" }) do
		rawset(_G, name, world[name])
	end
	local values = { radar = options.radar ~= false, radar_range = options.range or 35 }
	local listeners = {}
	local env = {
		api = {
			game = {
				in_mission = function() return world.in_mission ~= false end,
				my_unit = function()
					if world.no_unit then return nil end
					return me
				end,
				slaves = function(name) return name == "enemy" and enemies or {} end,
			},
			map = { is_open = function() return world.map_open end },
		},
		config = {
			get = function(id) return values[id] end,
			on_change = function(id, fn) listeners[id] = fn end,
		},
		state = { active = false, crosshair = nil },
		VIEW = { part = "view" },
		log = function(...) LOGS[#LOGS + 1] = table.concat({ ... }, " ") end,
	}
	radar().start(env)
	world.kit, world.env, world.enemy, world.current, world.listeners = kit, env, enemy, current, listeners
	world.frame = function()
		kit.calls = {}
		for _, f in ipairs(FRAMES) do f.fn() end
		return kit.calls
	end
	return world
end

local function cleanup()
	for _, name in ipairs({ "Unit", "EntityAux", "LuaSettingsManager", "Vector3", "Camera", "Quaternion", "CameraManager" }) do
		rawset(_G, name, nil)
	end
end

local function count(calls, kind)
	local n = 0
	for _, c in ipairs(calls) do
		if c[1] == kind then n = n + 1 end
	end
	return n
end

test("radar registers one frame function in the view part", function()
	local w = game()
	eq(#FRAMES, 1, "frame functions")
	eq(FRAMES[1].opts, w.env.VIEW, "registered with env.VIEW")
	eq(w.kit.layer, radar().LAYER, "layer")
	cleanup()
end)

test("radar marks enemies in range around the screen centre", function()
	local w = game()
	w.enemy("ahead", 0, 10)                                    -- on screen
	w.enemy("behind", 0, -10)
	w.enemy("tank", 20, 0, { settings = { heavy = true } })
	w.enemy("beside_tank", 21, 1)                              -- joins the tank
	w.enemy("far", 100, 0)
	w.enemy("dead", -10, 0, { dead = true })
	local calls = w.frame()
	eq(count(calls, "poly"), 4, "ahead, tank, and two arrows behind")
	eq(count(calls, "outline"), 1, "the tank is heavier")
	local ring = radar().RING * 1080
	-- Nearest first: ahead (10 m) and behind (10 m), then the tank.
	local ahead, tank
	for _, c in ipairs(calls) do
		if c[1] == "poly" and math.abs(c[2][5] - 960) < 1e-6 and c[2][6] > 540 then ahead = c end
		if c[1] == "poly" and c[2][5] > 960 + ring then tank = c end
	end
	assert(ahead, "a mark pointing up from the centre")
	near(ahead[2][2], 540 + ring, "base on the ring")
	local c = 1 - 10 / 35
	near(ahead.a, (radar().ALPHA_FAR + (1 - radar().ALPHA_FAR) * c) * radar().IN_VIEW * 255, "faint while in view", 1e-6)
	assert(tank, "a mark pointing right")
	local tank_len = tank[2][5] - (960 + ring)
	near(tank_len, radar().size(1 - 20 / 35, true, 2), "big and two enemies", 1e-6)
	local below = 0
	for _, p in ipairs(calls) do
		if p[1] == "poly" and p[2][6] < 540 - ring then below = below + 1 end
	end
	eq(below, 2, "a double arrow below for the enemy behind")
	eq(#LOGS, 0, "no errors")
	cleanup()
end)

test("radar centres on the crosshair while third person steers", function()
	local w = game()
	w.enemy("ahead", 0, 10)
	w.env.state.active = true
	w.env.state.crosshair = { x = 1000, y = 500 }
	local calls = w.frame()
	near(calls[1][2][5], 1000, "tip above the crosshair")
	near(calls[1][2][2], 500 + radar().RING * 1080, "base on the ring round the crosshair")
	cleanup()
end)

test("radar keeps quiet when off, out of a mission, on the map or a menu", function()
	local w = game({ radar = false })
	w.enemy("near", 5, 0)
	eq(#w.frame(), 0, "option off")
	w.listeners.radar(true)
	eq(#w.frame(), 1, "switched on")
	w.map_open = true
	eq(#w.frame(), 0, "map open")
	w.map_open = false
	w.current.screen = "main"
	eq(#w.frame(), 0, "pause menu")
	w.current.screen = "hud"
	w.no_unit = true
	eq(#w.frame(), 0, "no Helldiver")
	w.no_unit = false
	w.in_mission = false
	eq(#w.frame(), 0, "not in a mission")
	cleanup()
end)

test("radar range follows the option", function()
	local w = game({ range = 10 })
	w.enemy("mid", 15, 0)
	eq(#w.frame(), 0, "outside 10 m")
	w.listeners.radar_range(20)
	eq(#w.frame(), 1, "inside 20 m")
	cleanup()
end)

test("radar caps the marks drawn", function()
	local w = game()
	for i = 1, 30 do
		local a = math.rad(i * 12)
		w.enemy("e" .. i, math.cos(a) * 20, math.sin(a) * 20)
	end
	local calls = w.frame()
	local marks = count(calls, "poly")
	eq(marks <= radar().MAX_MARKS * 2, true, "arrows: " .. marks)
	cleanup()
end)

test("radar looks up the size of each enemy once", function()
	local w = game()
	w.enemy("a", 5, 0)
	w.enemy("b", -5, 0)
	w.frame()
	w.frame()
	w.frame()
	eq(w.lookups, 2, "one lookup per enemy")
	cleanup()
end)

test("radar rests after an error and logs it once", function()
	local w = game()
	w.enemy("a", 5, 0)
	w.broken = true
	w.frame()
	w.frame()
	eq(#LOGS, 1, "logged once")
	w.broken = false
	eq(#w.frame(), 0, "resting")
	for _ = 1, radar().PAUSE do w.frame() end
	eq(#w.frame(), 1, "back after the pause")
	cleanup()
end)

test("radar frames make no tables per enemy", function()
	local w = game()
	for i = 1, 20 do w.enemy("e" .. i, i * 1.5 - 15, (i % 7) * 3 - 9) end
	local kit = w.kit
	kit.poly, kit.outline = function() end, function() end
	local frame = FRAMES[1].fn
	frame()
	-- The stand-in camera answers new tables; keep the same ones from here.
	local f, up = { x = 0, y = 0.42, z = -0.91 }, { x = 0, y = 0.91, z = 0.42 }
	Quaternion.forward, Quaternion.up = function() return f end, function() return up end
	jit.off()
	collectgarbage("collect")
	collectgarbage("stop")
	local before = collectgarbage("count")
	for _ = 1, 300 do frame() end
	local grew = collectgarbage("count") - before
	collectgarbage("restart")
	jit.on()
	eq(grew < 1, true, "KB over 300 frames: " .. grew)
	cleanup()
end)

test("radar does nothing without a canvas", function()
	obsidian.ui = {}
	radar().start({ config = { get = function() return true end }, state = {}, VIEW = {}, log = function() end })
	eq(#FRAMES, 0, "no frame function")
end)

return T
