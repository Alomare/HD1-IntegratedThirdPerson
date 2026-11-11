-- main.lua: every registration names a part, the export, and the in-game settings rows.
local E = dofile("tests/engine.lua")

local function boot()
	local e = E.install()
	obsidian.ui = { canvas = function() return { rect = function() end } end }
	local export = dofile("main.lua")
	return e, export
end

return {
	{ "every hook, frame function, key and session listener names a part", function()
		boot()
		local count = 0
		for _, h in ipairs(HOOKS) do
			if not h.require then
				assert(type(h.opts) == "table" and type(h.opts.part) == "string",
					"no part on " .. tostring(h.target or "session") .. "." .. tostring(h.method))
				count = count + 1
			end
		end
		for i, f in ipairs(FRAMES) do
			assert(type(f.opts) == "table" and type(f.opts.part) == "string", "no part on frame function " .. i)
		end
		for id, k in pairs(KEYS) do
			assert(type(k.opts) == "table" and k.opts.part == "view" and k.opts.always == true, "key " .. id)
		end
		assert(count > 10, "hooks registered: " .. count)
		assert(KEYS.toggle_view and KEYS.swap_shoulder, "both keys")
		E.remove()
	end },

	{ "the view's own registrations use the view part", function()
		boot()
		for _, h in ipairs(HOOKS) do
			local t = h.target
			if t == "CameraManager" or t == "InputComponent" or t == "ViewportProxy" or t == "CursorManager" or t == "Hud"
				or t == "CharacterStateThrow" then
				eq(h.opts.part, "view", tostring(t) .. "." .. tostring(h.method))
			end
		end
		E.remove()
	end },

	{ "the export answers nothing in the top-down view and hands the crosshair over", function()
		local e, export = boot()
		eq(export.crosshair(), nil, "top-down")
		eq(export.active(), false)
		eq(export.shoulder(), nil, "no shoulder in the top-down view")
		-- One frame of third person.
		local masters = E.player(e, "me")
		local um = E.hook("InputComponent", "update_masters")
		um(function() end, {}, masters, 0.016)
		E.hook("CameraManager", "update")(function() end, CameraManager, 0.016)
		eq(export.active(), true)
		eq(export.shoulder(), 1, "right shoulder")
		KEYS.swap_shoulder.fn()
		eq(export.shoulder(), -1, "the shoulder being moved to")
		KEYS.swap_shoulder.fn()
		local c = export.crosshair()
		eq(c.x, 960) eq(c.y, 540) eq(c.aiming, false) eq(c.vehicle, false)
		eq(export.claim_crosshair("alomare.customcrosshair"), true)
		local cross = obsidian.module("src/crosshair")
		eq(cross.visible({ state = { active = true, crosshair = c, claimed_by = "alomare.customcrosshair" } }), false)
		E.remove()
	end },

	{ "the in-game page binds the four camera options and follows changes", function()
		local rows = {}
		local page = setmetatable({}, { __index = function(_, kind)
			return function(_, id, opts) rows[#rows + 1] = { kind = kind, id = id, opts = opts } return opts.default end
		end })
		local api = { mod_settings = { BINDS = true, page = function() return page end } }
		OPTIONS.foot_distance = 4
		local config = obsidian.module("src/config")
		config.start({ api = api })
		eq(#rows, 4)
		for _, r in ipairs(rows) do eq(r.opts.option, true, r.id) end
		eq(config.get("foot_distance"), 4, "starts from the option")
		local heard = nil
		config.on_change("foot_distance", function(v) heard = v end)
		rows[1].opts.on_change(6)
		eq(heard, 6) eq(config.get("foot_distance"), 6)
	end },
}
