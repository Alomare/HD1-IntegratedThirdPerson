-- Option values for the modules. Starts from what the player set in Obsidian, and follows the rows
-- of the in-game settings page (Obsidian API mod_settings, bound to the obsidian.json options), so a
-- change in the pause menu applies at once.
local M = {}

local values = {}
local listeners = {}

local function set(id, value)
	if values[id] == value then return end
	values[id] = value
	for _, fn in ipairs(listeners[id] or {}) do pcall(fn, value) end
end

function M.get(id)
	local v = values[id]
	if v == nil then v = obsidian.settings.get(id) end
	return v
end

-- Calls fn(value) whenever the option changes in game.
function M.on_change(id, fn)
	listeners[id] = listeners[id] or {}
	table.insert(listeners[id], fn)
end

M.set = set

-- Rows of the in-game page. Each one is the obsidian.json option with the same id.
local ROWS = {
	{ kind = "number", id = "foot_distance", min = 1, max = 10, step = 0.5, unit = " m",
		label = { en = "On-foot camera distance" },
		info = { en = "Meters between the camera and the Helldiver on foot in a mission." } },
	{ kind = "number", id = "ship_distance", min = 0.5, max = 10, step = 0.5, unit = " m",
		label = { en = "Ship camera distance" },
		info = { en = "Meters between the camera and the Helldiver on the Super Destroyer." } },
	{ kind = "number", id = "foot_fov", min = 40, max = 110, step = 1, unit = "",
		label = { en = "On-foot field of view" },
		info = { en = "Vertical field of view on foot." } },
	{ kind = "number", id = "vehicle_distance", min = 3, max = 20, step = 0.5, unit = " m",
		label = { en = "Vehicle camera distance" },
		info = { en = "Meters between the camera and the vehicle." } },
	{ kind = "number", id = "vehicle_fov", min = 40, max = 120, step = 1, unit = "",
		label = { en = "Vehicle field of view" },
		info = { en = "Vertical field of view in a vehicle." } },
}

function M.start(env)
	local api = env.api
	if not (api and api.mod_settings and api.mod_settings.BINDS) then return end
	local page = api.mod_settings.page("Integrated Third Person")
	for _, row in ipairs(ROWS) do
		local unit = row.unit
		local start = page[row.kind](page, row.id, {
			option = true,
			label = row.label,
			info = row.info,
			min = row.min, max = row.max, step = row.step,
			default = obsidian.settings.get(row.id),
			format = function(v) return tostring(v) .. unit end,
			on_change = function(v) set(row.id, v) end,
		})
		if start ~= nil then values[row.id] = start end
	end
end

return M
