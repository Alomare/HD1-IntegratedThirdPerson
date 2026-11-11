-- src/radar.lua: bearings from the camera, strength and size, the sight ray, the arc and arrow, and
-- frames against stand-ins for the engine.
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

test("radar closeness runs from the player to the range", function()
	local r = radar()
	near(r.closeness(0, 35), 1, "at the player")
	near(r.closeness(17.5, 35), 0.5, "half way")
	near(r.closeness(35, 35), 0, "at the range")
	near(r.closeness(50, 35), 0, "past the range")
	near(r.closeness(5, 0), 0, "no range")
end)

test("radar strength runs from 20 to 90 percent with closeness", function()
	local r = radar()
	near(r.alpha(0), 0.2, "at the range")
	near(r.alpha(1), 0.9, "at the player")
	near(r.alpha(0.5), 0.55, "half way")
end)

test("radar size grows with the hitpoints of the enemy, 1 to 1.5", function()
	local r = radar()
	eq(r.scale_of(10), 1, "small")
	eq(r.scale_of(r.HP_SMALL), 1, "at the small end")
	eq(r.scale_of(r.HP_BIG), 1.5, "at the big end")
	eq(r.scale_of(20000), 1.5, "past it")
	near(r.scale_of(math.sqrt(r.HP_SMALL * r.HP_BIG)), 1.25, "half way on the log scale", 1e-9)
	eq(r.scale_of(nil), 1, "nothing known")
	assert(r.scale_of(500) < r.scale_of(1500), "more hitpoints, larger")
end)

test("radar pool keeps the nearest first and reuses records", function()
	local r = radar()
	local pool, n = {}, 0
	for i, d in ipairs({ 30, 10, 20, 5, 25 }) do n = r.insert(pool, n, 3, d, i, "u" .. i) end
	eq(n, 3, "capped")
	eq(pool[1].d .. "," .. pool[2].d .. "," .. pool[3].d, "5,10,20", "nearest three in order")
	eq(pool[1].unit, "u4", "the unit kept")
	local tables = {}
	for i = 1, 3 do tables[pool[i]] = true end
	n = 0
	for _, d in ipairs({ 8, 2, 40, 1 }) do n = r.insert(pool, n, 3, d, 0, "x") end
	eq(pool[1].d .. "," .. pool[2].d .. "," .. pool[3].d, "1,2,8", "next frame")
	for i = 1, 3 do eq(tables[pool[i]], true, "record " .. i .. " reused") end
end)

test("radar sight is clear unless the level is hit well before the enemy", function()
	local r = radar()
	local function nothing() return nil end
	eq(r.in_sight(nothing, 0, 0, 1, 10, 0, 1), true, "nothing in the way")
	eq(r.in_sight(function() return 3 end, 0, 0, 1, 10, 0, 1), false, "a wall at 3 of 10 m")
	eq(r.in_sight(function() return 10 - r.SLACK / 2 end, 0, 0, 1, 10, 0, 1), true, "the ground at the enemy")
	local got = {}
	r.in_sight(function(...) got = { ... } return nil end, 0, 0, 1, 0, 8, 7)
	near(got[5], 0.8, "unit direction y") near(got[6], 0.6, "unit direction z") near(got[7], 10, "length")
end)

test("radar arcs are thin in the middle-thick shape and centred on the bearing", function()
	local r = radar()
	local out = {}
	local span = math.rad(20)
	-- Ahead (up): the middle of the arc is straight above the centre.
	r.arc_piece(out, 100, 100, r.screen_angle(0), 50, span, 2, 4, 3, 1)
	near(out[1], 100, "inner start x of the second half", 1e-9) near(out[2], 150, "inner start on the ring", 1e-9)
	near(out[4], 153, "3 px thick in the middle", 1e-9)
	r.arc_piece(out, 100, 100, r.screen_angle(0), 50, span, 0, 4, 3, 1)
	local a = math.rad(90) - span / 2
	near(out[1], 100 + math.cos(a) * 50, "first piece starts half the span round", 1e-9)
	near(math.sqrt((out[3] - 100) ^ 2 + (out[4] - 100) ^ 2), 51, "1 px thick at the end", 1e-9)
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
end)

-- The game ---------------------------------------------------------------------------------------

local function game(options)
	options = options or {}
	local kit = { calls = {} }
	function kit:poly(pts, c) self.calls[#self.calls + 1] = { "poly", { unpack(pts) }, a = c[4] } end
	local current = { screen = "hud" }
	obsidian.ui = {
		canvas = function(id, opts) kit.id, kit.layer = id, opts.layer return kit end,
		current = function() return current end,
	}
	local me = "me"
	local pos = { me = { x = 0, y = 0, z = 0 } }
	local health = {}
	local enemies = {}
	local function enemy(name, x, y, opts)
		opts = opts or {}
		pos[name] = { x = x, y = y, z = 0 }
		health[name] = { is_dead = opts.dead or false, max_hitpoints = opts.hp or 150 }
		enemies[name] = { state = {} }
	end
	-- Vectors from a ring of four, so the two of a ray stay apart and nothing is made per frame.
	local vectors, next_vector = { {}, {}, {}, {} }, 0
	local world
	world = {
		map_open = false,
		rays = 0,
		wall_x = nil, -- a wall across the level at this x
		Unit = {
			alive = function(u) return pos[u] ~= nil end,
			world_position = function(u) if world.broken then error("level gone") end return pos[u] end,
		},
		EntityAux = { state = function(u, c) return c == "health" and health[u] or nil end },
		Vector3 = function(x, y, z)
			next_vector = next_vector % 4 + 1
			local v = vectors[next_vector]
			v.x, v.y, v.z = x, y, z
			return v
		end,
		Camera = { world_rotation = function() return "rot" end },
		Quaternion = {
			-- Facing north, 65 degrees down, as the top-down camera does.
			forward = function() return { x = 0, y = 0.42, z = -0.91 } end,
			up = function() return { x = 0, y = 0.91, z = 0.42 } end,
		},
		World = { physics_world = function(w) return w == "level" and "physics" or nil end },
		PhysicsWorld = {
			immediate_raycast = function(pw, from, dir, length, ...)
				world.rays = world.rays + 1
				assert(pw == "physics", "the level physics")
				assert(select(2, ...) == "types" and select(3, ...) == "statics", "the level only")
				local wx = world.wall_x
				if wx and dir.x ~= 0 then
					local t = (wx - from.x) / dir.x
					if t > 0 and t < length then return true, from, t end
				end
				return false
			end,
		},
		CameraManager = {
			viewport = {
				get_camera = function() return "cam" end,
				window = function() return 1920, 1080, 0, 0 end,
				get_world_proxy = function() return { get_world = function() return "level" end } end,
			},
		},
		ENGINE_DT = 1 / 60,
	}
	for _, name in ipairs({ "Unit", "EntityAux", "Vector3", "Camera", "Quaternion", "World", "PhysicsWorld", "CameraManager", "ENGINE_DT" }) do
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
	world.pos, world.health = pos, health
	world.frame = function()
		kit.calls = {}
		for _, f in ipairs(FRAMES) do f.fn() end
		return kit.calls
	end
	-- Frames until every fade has settled; answers the calls of the last.
	world.settle = function()
		local calls
		for _ = 1, 90 do calls = world.frame() end
		return calls
	end
	return world
end

local function cleanup()
	for _, name in ipairs({ "Unit", "EntityAux", "Vector3", "Camera", "Quaternion", "World", "PhysicsWorld", "CameraManager", "ENGINE_DT" }) do
		rawset(_G, name, nil)
	end
end

local PER_MARK = 0 -- set below: the arc pieces and the arrow
local function marks(calls)
	PER_MARK = radar().SEGMENTS + 1
	return #calls / PER_MARK
end

-- The arrow of the mark pointing at `angle` degrees on screen (0 right, 90 up) round (cx, cy).
local function arrow_at(calls, cx, cy, angle)
	for i = PER_MARK, #calls, PER_MARK do
		local tip = calls[i][2]
		local a = math.deg(math.atan2(tip[6] - cy, tip[5] - cx))
		if math.abs(((a - angle + 180) % 360) - 180) < 1 then return calls[i] end
	end
	return nil
end

test("radar registers one frame function in the view part", function()
	local w = game()
	eq(#FRAMES, 1, "frame functions")
	eq(FRAMES[1].opts, w.env.VIEW, "registered with env.VIEW")
	eq(w.kit.layer, radar().LAYER, "layer")
	cleanup()
end)

test("radar marks each enemy in sight with an arc and an arrow, fading in", function()
	local w = game()
	w.enemy("ahead", 0, 10)
	w.enemy("right", 20, 0)
	w.enemy("dead", -10, 0, { dead = true })
	w.enemy("far", 100, 0)
	local first = w.frame()
	eq(marks(first), 2, "ahead and right")
	local target = radar().alpha(radar().closeness(10, 35))
	assert(first[1].a > 0 and first[1].a < target * 255 * 0.5, "fading in: " .. first[1].a)
	local calls = w.settle()
	eq(marks(calls), 2, "still two")
	local ahead = arrow_at(calls, 960, 540, 90)
	assert(ahead, "an arrow pointing up")
	near(ahead.a, target * 255, "strength from the distance", 1e-3)
	local s = radar().scale_of(150)
	near(ahead[2][6], 540 + radar().RING * 1080 + radar().THICK * s + radar().ARROW_LENGTH * s, "arrow tip past the arc", 1e-6)
	local right = arrow_at(calls, 960, 540, 0)
	assert(right, "an arrow pointing right")
	near(right.a, radar().alpha(radar().closeness(20, 35)) * 255, "farther, fainter", 1e-3)
	eq(#LOGS, 0, "no errors")
	cleanup()
end)

test("radar leaves out enemies behind the level and fades a mark when sight is lost", function()
	local w = game()
	w.wall_x = 10
	w.enemy("behind_wall", 20, 0)
	w.enemy("near", 5, 0)
	local calls = w.settle()
	eq(marks(calls), 1, "only the enemy in sight")
	-- The near one walks behind the wall: the next sight ray sees it, then the mark fades.
	w.pos.near.x = 15
	for _ = 1, radar().RECHECK + 1 do w.frame() end
	local fading = w.frame()
	eq(marks(fading), 1, "fading, not gone at once")
	assert(fading[1].a < radar().alpha(radar().closeness(5, 35)) * 255, "weaker")
	eq(marks(w.settle()), 0, "gone")
	cleanup()
end)

test("radar fades the mark of an enemy that dies", function()
	local w = game()
	w.enemy("a", 5, 0)
	w.settle()
	w.health.a.is_dead = true
	eq(marks(w.frame()), 1, "still fading")
	eq(marks(w.settle()), 0, "gone")
	cleanup()
end)

test("radar marks of bigger enemies are larger", function()
	local w = game()
	w.enemy("small", 0, 10, { hp = 40 })
	w.enemy("tank", 0, -10, { hp = 5000 })
	local calls = w.settle()
	local small, tank = arrow_at(calls, 960, 540, 90), arrow_at(calls, 960, 540, -90)
	local function length(c) return math.abs(c[2][6] - c[2][2]) end
	near(length(tank) / length(small), 1.5, "1.5 against 1", 1e-6)
	cleanup()
end)

test("radar centres on the crosshair while third person steers", function()
	local w = game()
	w.enemy("ahead", 0, 10)
	w.env.state.active = true
	w.env.state.crosshair = { x = 1000, y = 500 }
	local calls = w.frame()
	assert(arrow_at(calls, 1000, 500, 90), "arrow above the crosshair")
	cleanup()
end)

test("radar keeps quiet when off, out of a mission, on the map or a menu", function()
	local w = game({ radar = false })
	w.enemy("near", 5, 0)
	eq(#w.frame(), 0, "option off")
	w.listeners.radar(true)
	eq(marks(w.frame()), 1, "switched on")
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
	eq(marks(w.frame()), 1, "inside 20 m")
	cleanup()
end)

test("radar casts a few sight rays a frame and tracks the nearest", function()
	local w = game()
	for i = 1, 30 do
		local a = math.rad(i * 12)
		w.enemy("e" .. i, math.cos(a) * 20, math.sin(a) * 20)
	end
	w.frame()
	eq(w.rays, radar().RAYS, "rays in the first frame")
	local calls = w.settle()
	eq(marks(calls), radar().MAX_SCAN, "the nearest tracked")
	w.rays = 0
	for _ = 1, radar().RECHECK do w.frame() end
	eq(w.rays, radar().MAX_SCAN, "each tracked enemy checked once every RECHECK frames")
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
	eq(marks(w.frame()), 1, "back after the pause")
	cleanup()
end)

test("radar frames make no tables per enemy", function()
	local w = game()
	for i = 1, 20 do w.enemy("e" .. i, i * 1.5 - 15, (i % 7) * 3 - 9) end
	w.wall_x = 6
	local kit = w.kit
	kit.poly = function() end
	local frame = FRAMES[1].fn
	-- The stand-in camera answers new tables; keep the same ones from here.
	local f, up = { x = 0, y = 0.42, z = -0.91 }, { x = 0, y = 0.91, z = 0.42 }
	Quaternion.forward, Quaternion.up = function() return f end, function() return up end
	local proxy = { get_world = function() return "level" end }
	CameraManager.viewport.get_world_proxy = function() return proxy end
	-- No compiled code from earlier tests or the warm-up: leaving a trace can build what it had sunk.
	jit.off()
	jit.flush()
	for _ = 1, 30 do frame() end
	collectgarbage("collect")
	collectgarbage("stop")
	-- The runtime sometimes grows once, by under 1 KB, early after a full collect; a table per enemy
	-- or per frame keeps growing, so the frames after the first 300 are the ones counted.
	for _ = 1, 300 do frame() end
	local before = collectgarbage("count")
	for _ = 1, 600 do frame() end
	local grew = collectgarbage("count") - before
	collectgarbage("restart")
	jit.on()
	eq(grew < 1, true, "KB over 600 frames: " .. grew)
	cleanup()
end)

test("radar does nothing without a canvas", function()
	obsidian.ui = {}
	radar().start({ config = { get = function() return true end }, state = {}, VIEW = {}, log = function() end })
	eq(#FRAMES, 0, "no frame function")
end)

return T
