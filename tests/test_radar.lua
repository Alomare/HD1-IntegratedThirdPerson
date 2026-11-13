-- src/radar.lua: bearings from the camera, the four segments, their strength and the warning
-- triangle, and frames against stand-ins for the engine.
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
	eq(r.heading(0, 0, -1, nil, nil), nil, "nothing to go by")
end)

test("radar bearings split the circle in four sides", function()
	local r = radar()
	near(r.bearing(0, 10, 0, 1), 0, "ahead")
	near(r.bearing(10, 0, 0, 1), 90, "east of a north facing is right")
	near(r.bearing(-10, 0, 0, 1), -90, "left")
	eq(r.side_of(0), "front") eq(r.side_of(44), "front")
	eq(r.side_of(90), "right") eq(r.side_of(-90), "left")
	eq(r.side_of(180), "back") eq(r.side_of(-170), "back") eq(r.side_of(136), "back")
end)

test("radar strength: in range, then within half of it", function()
	local r = radar()
	eq(r.level(nil, 15), 0)
	eq(r.level(16, 15), 0, "out of range")
	eq(r.level(15, 15), 1, "in range")
	eq(r.level(7.5, 15), 2, "within half the range")
	eq(r.level(2, 15), 2)
end)

test("radar warns on the side with the closest enemy, only within half the range", function()
	local r = radar()
	eq(r.warned({ right = 5, left = 3 }, 15), "left")
	eq(r.warned({ right = 5, back = 6 }, 15), "right")
	eq(r.warned({ right = 9, back = 12 }, 15), nil, "nobody within 7.5 m")
	eq(r.warned({}, 15), nil)
end)

test("radar segments fade from 70% inside to all of it outside", function()
	local r = radar()
	near(r.band_share(0, 3), 0.7) near(r.band_share(2, 3), 1) near(r.band_share(1, 3), 0.85)
	eq(r.band_share(0, 1), 1)
end)

test("radar is hidden while the game stands still", function()
	local r = radar()
	eq(r.paused({}), false)
	rawset(_G, "PAUSED", true)
	eq(r.paused({}), true, "the game's pause")
	rawset(_G, "PAUSED", nil)
	eq(r.paused({ world = { time_now = function() return 0 end } }), true, "time stopped")
	eq(r.paused({ world = { time_now = function() return 0.5 end } }), false, "slow motion still shows")
	eq(r.paused({ effects = { is_on = function(id) return id == "freeze" end } }), true, "frozen")
end)

-- The game ---------------------------------------------------------------------------------------

local function game(options)
	options = options or {}
	local kit = { calls = {} }
	function kit:poly(pts, c) self.calls[#self.calls + 1] = { "poly", { unpack(pts) }, a = c[4] } end
	function kit:outline(pts, c) self.calls[#self.calls + 1] = { "outline", { unpack(pts) }, a = c[4] } end
	function kit:rect(x, y, w, h, c) self.calls[#self.calls + 1] = { "rect", { x, y }, a = c[4] } end
	local current = { screen = "hud" }
	obsidian.ui = {
		canvas = function(id, opts) kit.id, kit.layer = id, opts.layer return kit end,
		current = function() return current end,
	}
	local pos = { me = { x = 0, y = 0, z = 0 } }
	local health = {}
	local enemies = {}
	local function enemy(name, x, y, opts)
		opts = opts or {}
		pos[name] = { x = x, y = y, z = 0 }
		health[name] = { is_dead = opts.dead or false }
		enemies[name] = { state = {} }
	end
	local world = {
		map_open = false,
		Unit = {
			alive = function(u) return pos[u] ~= nil end,
			world_position = function(u) if pos.broken then error("level gone") end return pos[u] end,
		},
		EntityAux = { state = function(u, c) return c == "health" and health[u] or nil end },
		Camera = { world_rotation = function() return "rot" end },
		Quaternion = {
			-- Facing north, 65 degrees down, as the top-down camera does.
			forward = function() return { x = 0, y = 0.42, z = -0.91 } end,
			up = function() return { x = 0, y = 0.91, z = 0.42 } end,
		},
		CameraManager = {
			viewport = {
				get_camera = function() return "cam" end,
				window = function() return 1920, 1080, 0, 0 end,
			},
		},
		ENGINE_DT = 1 / 60,
	}
	for _, name in ipairs({ "Unit", "EntityAux", "Camera", "Quaternion", "CameraManager", "ENGINE_DT" }) do
		rawset(_G, name, world[name])
	end
	local values = { radar = options.radar ~= false, radar_range = options.range or 15 }
	local listeners = {}
	local env = {
		api = {
			game = {
				in_mission = function() return world.in_mission ~= false end,
				my_unit = function() return "me" end,
				slaves = function(name) return name == "enemy" and enemies or {} end,
			},
			map = { is_open = function() return world.map_open end },
			world = { time_now = function() return world.time or 1 end },
		},
		config = {
			get = function(id) return values[id] end,
			on_change = function(id, fn) listeners[id] = fn end,
		},
		state = { active = true, crosshair = nil },
		VIEW = { part = "view" },
		log = function(...) LOGS[#LOGS + 1] = table.concat({ ... }, " ") end,
	}
	radar().start(env)
	world.kit, world.env, world.enemy, world.current, world.listeners, world.pos = kit, env, enemy, current, listeners, pos
	world.frame = function()
		kit.calls = {}
		for _, f in ipairs(FRAMES) do f.fn() end
		return kit.calls
	end
	world.settle = function()
		local calls
		for _ = 1, 120 do calls = world.frame() end
		return calls
	end
	return world
end

local function cleanup()
	for _, name in ipairs({ "Unit", "EntityAux", "Camera", "Quaternion", "CameraManager", "ENGINE_DT" }) do
		rawset(_G, name, nil)
	end
end

-- The sides drawn: from the angle of each piece's middle round the centre (960, 540).
local function sides(calls)
	local out, alpha = {}, {}
	for _, c in ipairs(calls) do
		if c[1] == "poly" then
			local p = c[2]
			local mx, my = (p[1] + p[5]) / 2 - 960, (p[2] + p[6]) / 2 - 540
			local s
			if math.abs(mx) > math.abs(my) then s = mx > 0 and "right" or "left" else s = my > 0 and "front" or "back" end
			out[s] = (out[s] or 0) + 1
			alpha[s] = math.max(alpha[s] or 0, c.a)
		end
	end
	return out, alpha
end

local function count(calls, kind)
	local n = 0
	for _, c in ipairs(calls) do if c[1] == kind then n = n + 1 end end
	return n
end

test("radar draws nothing with no enemy near", function()
	local w = game()
	w.enemy("far", 0, -40)
	eq(#w.settle(), 0)
	cleanup()
end)

test("radar shows a thin faint segment for an enemy in range, never the front", function()
	local w = game()
	w.enemy("east", 12, 0)
	w.enemy("north", 0, 5)
	local calls = w.settle()
	local s, a = sides(calls)
	assert(s.right and s.right > 0, "right segment")
	eq(s.front, nil, "the front never shows")
	eq(s.left, nil) eq(s.back, nil)
	near(a.right, 0.3 * 255, "30% at the outer edge", 1)
	eq(count(calls, "outline"), 0, "no warning at 12 m")
	cleanup()
end)

test("radar shows a stronger segment and one warning triangle for the closest side", function()
	local w = game()
	w.enemy("east", 6, 0)
	w.enemy("south", 0, -4)
	w.enemy("west", -14, 0)
	local calls = w.settle()
	local s, a = sides(calls)
	assert(s.right and s.back and s.left, "three sides")
	near(a.right, 0.6 * 255, "60% within half the range", 1)
	near(a.back, 0.6 * 255, "", 1)
	near(a.left, 0.3 * 255, "", 1)
	eq(count(calls, "outline"), 1, "one triangle")
	local tri
	for _, c in ipairs(calls) do if c[1] == "outline" then tri = c[2] end end
	local tx, ty = (tri[1] + tri[3] + tri[5]) / 3, (tri[2] + tri[4] + tri[6]) / 3
	near(tx, 960, "on the back segment", 2)
	assert(ty < 540 - 100, "below the crosshair: " .. ty)
	cleanup()
end)

test("radar hides while paused, on other screens and with the map open", function()
	local w = game()
	w.enemy("east", 6, 0)
	assert(#w.settle() > 0)
	w.time = 0
	eq(#w.settle(), 0, "time stopped")
	w.time = 1
	assert(#w.settle() > 0)
	w.current.screen = "upgrades"
	eq(#w.frame(), 0, "another screen")
	w.current.screen = "hud"
	w.map_open = true
	eq(#w.frame(), 0, "the map")
	w.map_open = false
	w.env.state.active = false
	eq(#w.frame(), 0, "the shoulder view off")
	w.env.state.active = true
	cleanup()
end)

test("radar follows the range option and the switch", function()
	local w = game({ range = 10 })
	w.enemy("east", 12, 0)
	eq(#w.settle(), 0, "out of a 10 m range")
	w.listeners.radar_range(20)
	assert(#w.settle() > 0, "in a 20 m range")
	w.listeners.radar(false)
	eq(#w.frame(), 0, "switched off")
	cleanup()
end)

test("radar rests after an error and says so once", function()
	local w = game()
	w.enemy("east", 6, 0)
	w.pos.broken = true
	LOGS = {}
	w.frame()
	w.frame()
	local said = 0
	for _, l in ipairs(LOGS) do if l:find("enemy indicators", 1, true) then said = said + 1 end end
	eq(said, 1)
	cleanup()
end)

return T
