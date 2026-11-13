-- src/hits.lua: the fade, where a hit came from, which bar it goes in, and frames against stand-ins for
-- the engine: health, shield and vehicle hits, a bar following an enemy, and the fade out.
local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local function hits() return obsidian.module("src/hits") end

-- Pure parts -------------------------------------------------------------------------------------

test("hits rise at once, hold, and fade out within two seconds", function()
	local h = hits()
	eq(h.strength(0), 0, "starts")
	eq(h.strength(h.POP), 1, "full after the pop")
	eq(h.strength(h.HOLD), 1, "held")
	assert(h.strength(1) < 1 and h.strength(1) > h.strength(1.5), "fading")
	eq(h.strength(h.LIFE), 0, "gone at the end")
	eq(h.LIFE <= 2, true, "within two seconds")
end)

test("hits come from the enemy that did it, else from the thing that hit", function()
	local h = hits()
	local alive = function(u) return u ~= "gone" end
	local enemy = function(u) return u == "bug" end
	eq(table.concat({ tostring(h.source("bug", "spit", "me", alive, enemy)) }), "bug", "an enemy")
	local u, follow = h.source("bug", "spit", "me", alive, enemy)
	eq(follow, true, "followed")
	u, follow = h.source("me", "grenade", "me", alive, enemy)
	eq(u .. "," .. tostring(follow), "grenade,false", "own grenade: where it went off")
	u, follow = h.source("mate", "bullet", "me", alive, enemy)
	eq(u .. "," .. tostring(follow), "bullet,false", "a teammate: the bullet")
	u, follow = h.source("mate", "gone", "me", alive, enemy)
	eq(u .. "," .. tostring(follow), "mate,false", "the bullet gone: the teammate")
	eq(h.source("me", nil, "me", alive, enemy), nil, "nothing but the Helldiver")
	eq(h.source(nil, "gone", "me", alive, enemy), nil, "nothing left")
end)

test("hits renew the bar of the same enemy or the same way, else take a free or the oldest", function()
	local h = hits()
	local slots = {}
	for i = 1, 3 do slots[i] = { on = false, age = 0 } end
	local s, renew = h.pick(slots, "bug", true, "health", 10)
	eq(s, slots[1]) eq(renew, false)
	s.on, s.unit, s.follow, s.kind, s.way, s.age = true, "bug", true, "health", 10, 1
	s, renew = h.pick(slots, "bug", true, "shield", 90)
	eq(s, slots[1], "same enemy, any kind") eq(renew, true)
	s, renew = h.pick(slots, "bullet", false, "health", 30)
	eq(s, slots[2], "a new way") eq(renew, false)
	s.on, s.follow, s.kind, s.way, s.age = true, false, "health", 30, 0.5
	eq((h.pick(slots, "bullet2", false, "health", 45)), slots[2], "within the merge angle")
	eq((h.pick(slots, "bullet2", false, "shield", 45)), slots[3], "another kind")
	slots[3].on, slots[3].age = true, 0.2
	eq((h.pick(slots, "x", false, "vehicle", -120)), slots[1], "full: the oldest")
end)

test("hits bars run outward in pieces", function()
	local h = hits()
	local out = {}
	h.bar_piece(out, 100, 100, math.rad(90), 50, 90, 5, 0, 4)
	near(out[1], 95, "inner corner x") near(out[2], 150, "inner end")
	near(out[4], 160, "first piece is a quarter long")
	h.bar_piece(out, 100, 100, math.rad(90), 50, 90, 5, 3, 4)
	near(out[4], 190, "last piece reaches the outer end")
	eq(h.piece_share(0, 4) > h.piece_share(3, 4), true, "fades outward")
end)

-- The game ---------------------------------------------------------------------------------------

local function hook(target, method)
	for i = #HOOKS, 1, -1 do
		local h = HOOKS[i]
		if h.target == target and h.method == method then return h.fn end
	end
end

local function game()
	local kit = { calls = {} }
	function kit:poly(pts, c) self.calls[#self.calls + 1] = { "poly", { unpack(pts) }, c = { c[1], c[2], c[3], c[4] } } end
	obsidian.ui = { canvas = function(_, opts) kit.layer = opts.layer return kit end, current = function() return { screen = "hud" } end }
	local pos = { me = { x = 0, y = 0, z = 0 }, bug = { x = 0, y = 10, z = 0 }, mech = { x = 0, y = 0, z = 0 }, spit = { x = 10, y = 0, z = 0 } }
	local w
	w = {
		seat = nil,
		Unit = {
			alive = function(u) return pos[u] ~= nil end,
			world_position = function(u) return pos[u] end,
		},
		EntityAux = {
			state = function(u, c) if u == "me" and c == "character" then return { current_seat_unit = w.seat } end error("no " .. c) end,
			has_component = function(u, c) return c == "enemy" and u == "bug" end,
		},
		Camera = { world_rotation = function() return "rot" end },
		Quaternion = { forward = function() return { x = 0, y = 1, z = 0 } end, up = function() return { x = 0, y = 0, z = 1 } end },
		CameraManager = { viewport = { get_camera = function() return "cam" end, window = function() return 1920, 1080, 0, 0 end } },
		ENGINE_DT = 1 / 60,
		HealthComponent = { command_master = function() end },
		ShieldComponent = { on_damage_taken = function() end },
	}
	for _, name in ipairs({ "Unit", "EntityAux", "Camera", "Quaternion", "CameraManager", "ENGINE_DT", "HealthComponent", "ShieldComponent" }) do
		rawset(_G, name, w[name])
	end
	local values = { hit_indicators = true }
	local listeners = {}
	local env = {
		api = { game = { in_mission = function() return true end, my_unit = function() return "me" end } },
		config = { get = function(id) return values[id] end, on_change = function(id, fn) listeners[id] = fn end },
		state = { active = true },
		VIEW = { part = "view" },
		log = function(...) LOGS[#LOGS + 1] = table.concat({ ... }, " ") end,
	}
	hits().start(env)
	w.kit, w.env, w.pos, w.listeners = kit, env, pos, listeners
	w.frame = function()
		kit.calls = {}
		for _, f in ipairs(FRAMES) do f.fn() end
		return kit.calls
	end
	-- A damage command on `unit` from owner/attacker: hp drops by `loss`.
	w.damage = function(unit, owner, attacker, loss, command)
		local ctx = { state = { hitpoints_real = 100 } }
		local function game_fn(_, _, c) c.state.hitpoints_real = c.state.hitpoints_real - (loss or 10) return "done" end
		return hook("HealthComponent", "command_master")(game_fn, {}, unit, ctx, command or "do_damage",
			{ owner_unit = owner, attacker_unit = attacker })
	end
	w.shield = function(owner, attacker, damage)
		local seen = false
		hook("ShieldComponent", "on_damage_taken")(function() seen = true end, {}, "me", {}, damage or 20, { owner_unit = owner, attacker_unit = attacker })
		return seen
	end
	return w
end

local function cleanup()
	for _, name in ipairs({ "Unit", "EntityAux", "Camera", "Quaternion", "CameraManager", "ENGINE_DT", "HealthComponent", "ShieldComponent" }) do
		rawset(_G, name, nil)
	end
end

-- The angle on screen (degrees, 0 right, 90 up) a bar points at, from the first piece.
local function angle_of(call)
	local p = call[2]
	local mx, my = (p[1] + p[7]) / 2, (p[2] + p[8]) / 2
	return math.deg(math.atan2(my - 540, mx - 960))
end

test("hits on health draw a red bar toward the enemy, following it", function()
	local w = game()
	w.frame()
	eq(w.damage("me", "bug", "bug"), "done", "the game answer comes back")
	local calls = w.frame()
	eq(#calls, hits().STEPS, "one bar in pieces")
	eq(calls[1].c[1] .. "," .. calls[1].c[2] .. "," .. calls[1].c[3], "230,40,30", "red")
	near(angle_of(calls[1]), 90, "the bug is ahead: up", 1e-6)
	w.pos.bug.x, w.pos.bug.y = 10, 0
	near(angle_of(w.frame()[1]), 0, "the bug moved right: the bar follows", 1e-6)
	cleanup()
end)

test("hits on the shield are yellow and on the vehicle white", function()
	local w = game()
	w.frame()
	eq(w.shield("bug", "bug"), true, "the game function still runs")
	local calls = w.frame()
	eq(calls[1].c[2], 210, "yellow")
	cleanup()
	w = game()
	w.seat = "mech"
	w.frame()
	w.damage("mech", nil, "spit")
	calls = w.frame()
	eq(calls[1].c[1] .. "," .. calls[1].c[2] .. "," .. calls[1].c[3], "255,255,255", "white")
	near(angle_of(calls[1]), 0, "the spit hit from the right, and stays there", 1e-6)
	cleanup()
end)

test("hits that cost nothing, on other units or with no source show nothing", function()
	local w = game()
	w.frame()
	w.damage("me", "bug", "bug", 0)
	w.damage("bug", "me", "rifle")
	w.damage("me", "me", nil)
	w.damage("me", "bug", "bug", 10, "do_heal")
	eq(#w.frame(), 0, "no bars")
	cleanup()
end)

test("hits fade out within two seconds and the option turns them off", function()
	local w = game()
	w.frame()
	w.damage("me", "bug", "bug")
	local first = w.frame()
	eq(#first, hits().STEPS)
	for _ = 1, 30 do w.frame() end
	local held = w.frame()
	assert(held[1].c[4] < 255 * hits().ALPHA and held[1].c[4] > 0, "fading")
	for _ = 1, 100 do w.frame() end
	eq(#w.frame(), 0, "gone by two seconds")
	w.listeners.hit_indicators(false)
	w.damage("me", "bug", "bug")
	eq(#w.frame(), 0, "off")
	cleanup()
end)

return T
