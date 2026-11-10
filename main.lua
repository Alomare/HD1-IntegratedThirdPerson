-- Integrated Third Person: an over-the-shoulder camera built on Obsidian hooks.
-- Based on Third Person Camera (HD2 Style) by yukiorsrs, used with permission.
--
-- The mod is split into parts (obsidian.json "parts"):
--   view             client: camera, aim, crosshair, view distance, sky, ship walls, enemy indicators
--   weapon_range     session: every weapon reaches as far as the farthest one
--   enemy_detection  session: enemies notice the squad from farther away
-- Every hook, frame function and key is registered with the options of its part ({ part = "..." }),
-- so a lobby that isn't cleared switches only the session parts off. A loader without parts ignores
-- the extra argument and gates everything, the safe fallback.

local api = obsidian.import("obsidian.api")
local config = obsidian.module("src/config")

local VIEW = { part = "view" }
local KEY_VIEW = { part = "view", always = true }

-- Shared between the modules. camera.lua and aim.lua write it, the others read it.
local state = {
	active = false,     -- third person is steering the view this frame
	vehicle = false,    -- the player sits in a vehicle or a turret
	aiming = false,     -- the aim button is held
	crosshair = nil,    -- { x, y } in pixels from the bottom left, where shots go
	claimed_by = nil,   -- id of a mod that draws the crosshair instead of this one
}

local env = {
	api = api,
	config = config,
	state = state,
	VIEW = VIEW,
	KEY_VIEW = KEY_VIEW,
	part = function(id) return { part = id } end,
	log = function(...) obsidian.log(...) end,
	parts = obsidian.capabilities and obsidian.capabilities.parts or false,
}

config.start(env)

local started = {}
for _, name in ipairs({ "src/camera", "src/aim", "src/crosshair", "src/view", "src/radar", "src/session" }) do
	local ok, err = pcall(function()
		local m = obsidian.module(name)
		if m and m.start then m.start(env) end
		started[name] = m
	end)
	if not ok then obsidian.log("Integrated Third Person: " .. name .. " did not start: " .. tostring(err)) end
end

-- What other mods get from obsidian.import("alomare.integratedthirdperson").
local export = { version = "0.1.0" }

-- Where shots go on screen while third person steers the view: { x, y, aiming }, in pixels from the
-- bottom left (the coordinates of obsidian.ui.canvas). nil while the top-down camera is on.
function export.crosshair()
	if not state.active or not state.crosshair then return nil end
	return { x = state.crosshair.x, y = state.crosshair.y, aiming = state.aiming, vehicle = state.vehicle }
end

-- Another mod draws the crosshair from now on (Custom Crosshair does this). Integrated Third Person
-- stops drawing its own. Answers true.
function export.claim_crosshair(mod_id)
	state.claimed_by = mod_id or obsidian.caller and obsidian.caller() or "unknown"
	return true
end

-- true while third person steers the view.
function export.active()
	return state.active
end

return export
