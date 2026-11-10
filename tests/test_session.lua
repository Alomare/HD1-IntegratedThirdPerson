-- The session parts: weapon range raised only while the game call runs, aggro range seen through
-- shadow settings, and the far sight ray of patrols.

local function vec_engine()
	local mt = {}
	mt.__add = function(a, b) return setmetatable({ x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }, mt) end
	mt.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, mt) end
	Vector3 = setmetatable({
		distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end,
		normalize = function(a)
			local l = math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
			return setmetatable({ x = a.x / l, y = a.y / l, z = a.z / l }, mt)
		end,
	}, { __call = function(_, x, y, z) return setmetatable({ x = x, y = y, z = z }, mt) end })
	Vector3Aux = { unbox = function(b) return Vector3(b[1], b[2], b[3]) end }
	POSITIONS = {}
	Unit = {
		alive = function(u) return POSITIONS[u] ~= nil end,
		world_position = function(u) return POSITIONS[u] end,
	}
end

local function env_with(options)
	for k, v in pairs(options or {}) do OPTIONS[k] = v end
	return {
		config = { get = function(id) return OPTIONS[id] end },
		part = function(id) return { part = id } end,
	}
end

local function hooks_by_method()
	local by = {}
	for _, h in ipairs(HOOKS) do if h.method then by[h.target .. "." .. h.method] = h end end
	return by
end

local function session()
	package.loaded["src/session"] = nil
	return dofile("src/session.lua")
end

return {
	{ "every hook carries the options of the part it belongs to", function()
		local s = session()
		s.start(env_with({ max_weapon_range = true, far_detection = true }))
		local by = hooks_by_method()
		for _, name in ipairs({ "FirearmComponent.update_slaves", "BeamweaponComponent.update_slaves",
			"LaserSightComponent.update_slaves", "LauncherComponent.do_fire" }) do
			assert(by[name], name .. " hooked")
			eq(by[name].opts.part, "weapon_range", name .. " part")
		end
		eq(by["EnemyComponent.update_target"].opts.part, "enemy_detection", "update_target part")
		eq(by["EnemyUtility.wander"].opts.part, "enemy_detection", "wander part")
	end },

	{ "an option set off registers nothing for that part", function()
		local s = session()
		s.start(env_with({ max_weapon_range = false, far_detection = true }))
		local by = hooks_by_method()
		assert(not by["FirearmComponent.update_slaves"], "no firearm hook")
		assert(by["EnemyComponent.update_target"], "detection still hooked")
	end },

	{ "range is raised during the call and back after it", function()
		local s = session()
		local rifle, saber = { state = { range = 30 } }, { state = { range = 0.75 } }
		local railgun = { state = { range = 120 } }
		local entities = { a = rifle, b = saber, c = railgun }
		local seen = {}
		s.with_entities(entities, function()
			seen.rifle, seen.saber, seen.railgun = rifle.state.range, saber.state.range, railgun.state.range
		end)
		eq(seen.rifle, s.MAX_RANGE, "rifle during")
		eq(seen.saber, 0.75, "melee untouched")
		eq(seen.railgun, 120, "longer range untouched")
		eq(rifle.state.range, 30, "rifle after")
	end },

	{ "range comes back when the game call fails", function()
		local s = session()
		local rifle = { state = { range = 30 } }
		local ok = pcall(s.with_entities, { rifle }, function() error("boom") end)
		eq(ok, false, "error passed on")
		eq(rifle.state.range, 30, "range restored")
	end },

	{ "results of the game call pass through, nils included", function()
		local s = session()
		local a, b, c = s.with_state({ range = 30 }, function() return 1, nil, 3 end)
		eq(a, 1, "first") eq(b, nil, "second") eq(c, 3, "third")
	end },

	{ "shadow settings answer the raised aggro range and nothing else changes", function()
		local s = session()
		local info = { aggro_range = 80, attack_range_shoot_max = 10 }
		local settings = { enemy_info = info, unit_radius = 1 }
		local shadow = s.shadow(settings)
		eq(shadow.enemy_info.aggro_range, s.AGGRO_RANGE, "raised")
		eq(shadow.enemy_info.attack_range_shoot_max, 10, "other fields read through")
		eq(shadow.unit_radius, 1, "top fields read through")
		eq(info.aggro_range, 80, "the game table keeps 80")
		eq(s.shadow(settings), shadow, "one shadow per settings table")
		eq(s.shadow({ enemy_info = { aggro_range = 1 } }).enemy_info.aggro_range, 1, "tiny ranges untouched")
	end },

	{ "update_target sees the shadow only during the call", function()
		local s = session()
		local settings = { enemy_info = { aggro_range = 80 } }
		local context = { settings = settings }
		local during
		s.with_shadow(context, function() during = context.settings.enemy_info.aggro_range end)
		eq(during, s.AGGRO_RANGE, "during")
		eq(context.settings, settings, "after")
	end },

	{ "a patrol casts a long sight ray toward a player past the alarm range", function()
		vec_engine()
		local s = session()
		local casts = {}
		POSITIONS.player = Vector3(40, 0, 0)
		local state = { patroling = true, position = { 0, 0, 0 }, closest_target_unit = "player",
			can_see_closest_target_raycast = { cast = function(_, from, dir, len) casts[#casts + 1] = len end } }
		local settings = { enemy_info = { patrol_range = 12 } }
		eq(s.far_sight("enemy", state, settings, 1), true, "cast")
		eq(casts[1], s.SIGHT_RANGE, "ray length")
		eq(state.waiting_for_see_closest_target_raycast, true, "waits like the game")
		state.waiting_for_see_closest_target_raycast = false
		eq(s.far_sight("enemy", state, settings, 1.1), false, "rate limited")
		eq(s.far_sight("enemy", state, settings, 2), true, "casts again later")
	end },

	{ "no far sight inside the alarm range, beyond sight, or once alerted", function()
		vec_engine()
		local s = session()
		local ray = { cast = function() error("no cast expected") end }
		local settings = { enemy_info = { patrol_range = 12 } }
		POSITIONS.near, POSITIONS.far = Vector3(8, 0, 0), Vector3(200, 0, 0)
		local function state(target, extra)
			local t = { patroling = true, position = { 0, 0, 0 }, closest_target_unit = target, can_see_closest_target_raycast = ray }
			for k, v in pairs(extra or {}) do t[k] = v end
			return t
		end
		eq(s.far_sight("e", state("near"), settings, 5), false, "the game handles the alarm range")
		eq(s.far_sight("e", state("far"), settings, 5), false, "beyond sight")
		eq(s.far_sight("e", state("near", { alerted = true }), settings, 5), false, "alerted")
		eq(s.far_sight("e", state("gone"), settings, 5), false, "dead target")
		eq(s.far_sight("e", state("near", { patroling = false }), settings, 5), false, "not a patrol")
	end },
}
