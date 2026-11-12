-- Fake engine tables for the offline tests: just enough of Vector3, Quaternion, Unit, Camera, World,
-- PhysicsWorld, the viewport and CameraManager for the modules to run a frame. Not a test file itself
-- (tests/run.lua only runs test_*.lua). E.install() sets the globals and answers a table to steer them.
local E = {}

local vmt = {}
vmt.__index = vmt
function E.V3(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, vmt) end
vmt.__add = function(a, b) return E.V3(a.x + b.x, a.y + b.y, a.z + b.z) end
vmt.__sub = function(a, b) return E.V3(a.x - b.x, a.y - b.y, a.z - b.z) end

function E.install()
	local e = {
		calls = {},                 -- Camera.* calls, by name: the last arguments
		units = {},                 -- unit: { position = {x,y,z}, forward = {x,y,z}, alive = true }
		hit = nil,                  -- distance the next static raycast hits at, or nil
		aim_hit = nil,              -- { pos = {x,y,z}, unit = u } for damage_ray casts
		mouse = { x = 0, y = 0 },   -- the "mouse" axis this frame
		resolution = { 1920, 1080 },
		cursor_position = nil,
		shown = true,
	}
	_G.Vector3 = setmetatable({ zero = function() return E.V3() end }, { __call = function(_, x, y, z) return E.V3(x, y, z) end })
	_G.Vector3Aux = {
		unbox = function(t) return E.V3(t.x, t.y, t.z) end,
		box = function(t, v) t = t or {} t.x, t.y, t.z = v.x, v.y, v.z return t end,
	}
	-- A quaternion here carries the forward it stands for.
	_G.Quaternion = setmetatable({
		multiply = function(a, b) return { parts = { a, b } } end,
		forward = function(q) local f = q.fwd or { x = 0, y = 1, z = 0 } return E.V3(f.x, f.y, f.z) end,
		rotate = function(_, v) return E.V3(v.x, v.y, v.z) end,
	}, { __call = function(_, axis, angle) return { axis = axis, angle = angle } end })
	_G.QuaternionAux = { unbox = function(t) return t end }
	_G.Unit = {
		alive = function(u) return u ~= nil and e.units[u] ~= nil and e.units[u].alive ~= false end,
		world_position = function(u) local p = e.units[u].position return E.V3(p.x, p.y, p.z) end,
		world_rotation = function(u, node) return { fwd = e.units[u].forward, node = node } end,
	}
	_G.EntityAux = {
		state = function(u, name) local s = e.units[u] and e.units[u][name] if s then return s end error("no " .. name) end,
		has_component = function(u, name) return e.units[u] and e.units[u][name] ~= nil end,
	}
	_G.Camera = setmetatable({}, { __index = function(_, name)
		return function(...) e.calls[name] = { ... } if name == "near_range" then return 0.1 end end
	end })
	_G.World = {
		physics_world = function() return "pw" end,
		update_unit = function() e.calls.update_unit = true end,
	}
	_G.Actor = { unit = function(a) return a end }
	_G.PhysicsWorld = {
		immediate_raycast = function(_, from, dir, length, mode, ...)
			local args = { ... }
			local statics = args[1] == "types"
			if statics then
				if e.hit and e.hit <= length then return true, E.V3(), e.hit end
				return false
			end
			if mode == "all" then
				-- Hits as the game answers them: { position, distance, normal, actor }, in any order.
				local list = {}
				for _, h in ipairs(e.aim_hits or (e.aim_hit and { e.aim_hit }) or {}) do
					list[#list + 1] = { E.V3(h.pos.x, h.pos.y, h.pos.z), h.distance or 10, E.V3(), h.unit }
				end
				return #list > 0 and list or nil
			end
			if e.aim_hit then return true, E.V3(e.aim_hit.pos.x, e.aim_hit.pos.y, e.aim_hit.pos.z), 10, nil, e.aim_hit.unit end
			return false
		end,
	}
	_G.Mouse = {
		axis_index = function(name) return name end,
		axis = function(i) if i == "mouse" then return E.V3(e.mouse.x, e.mouse.y, 0) end return E.V3(960, 540, 0) end,
	}
	_G.Application = { resolution = function() return e.resolution[1], e.resolution[2] end }
	_G.Window = { has_focus = function() return true end }
	_G.KEYBOARD_MOUSE_PAD_NUMBER = 99
	_G.CursorManager = {
		is_shown = function() return e.shown end,
		set_show_cursor = function(_, on) e.shown = on end,
		set_cursor_position = function(_, p) e.cursor_position = p end,
	}
	local proxy = { get_world = function() return "world" end, is_active = function() return true end }
	e.viewport = {
		camera_unit = "camera_unit",
		get_camera = function() return "camera" end,
		get_world_proxy = function() return proxy end,
		is_active = function() return true end,
		window = function() return e.resolution[1], e.resolution[2], 0, 0 end,
	}
	_G.CameraManager = {
		state = "follow", viewport = e.viewport, fov = math.rad(60), follow_spin = math.rad(-45),
		position = { x = 0, y = -10, z = 17 }, rotation = { fwd = { x = 0, y = 0.5, z = -0.866 } },
		update = function() end,
	}
	_G.InputComponent = { update_masters = function() end, queue_command_master = function() end }
	_G.HD2CAM_OVERLAY = nil
	return e
end

-- Clears the globals install() set, so other tests start clean.
function E.remove()
	for _, k in ipairs({ "Vector3", "Vector3Aux", "Quaternion", "QuaternionAux", "Unit", "EntityAux", "Camera", "World", "Actor",
		"PhysicsWorld", "Mouse", "Application", "Window", "KEYBOARD_MOUSE_PAD_NUMBER", "CursorManager", "CameraManager",
		"InputComponent", "HD2CAM_OVERLAY" }) do
		_G[k] = nil
	end
end

-- An env as main.lua builds it, with a config read from OPTIONS.
function E.env(api)
	local config = obsidian.module("src/config")
	return {
		api = api, config = config, log = function(...) LOGS[#LOGS + 1] = table.concat({ ... }, " ") end,
		state = { active = false, vehicle = false, aiming = false, crosshair = nil, claimed_by = nil },
		VIEW = { part = "view" }, KEY_VIEW = { part = "view", always = true },
		part = function(id) return { part = id } end, parts = true,
		on_pose = {}, on_release = {},
	}
end

-- The hook a test registered on target.method, or nil.
function E.hook(target, method)
	for i = #HOOKS, 1, -1 do
		local h = HOOKS[i]
		if h.target == target and h.method == method then return h.fn end
	end
	return nil
end

-- A player on keyboard and mouse: the master context InputComponent.update_masters gets.
function E.player(e, unit, opts)
	opts = opts or {}
	e.units[unit] = { position = opts.position or { x = 0, y = 0, z = 0 }, forward = opts.forward or { x = 0, y = 1, z = 0 },
		character = { current_seat_unit = opts.seat } }
	local data = { is_active = true, fire_button = opts.fire or 0, throw = 0, aiming_pressed = opts.aiming or false, aim = opts.stick }
	return { [unit] = { state = { pad_number = opts.pad or 99, input_data = data, has_focus = true } } }
end

return E
