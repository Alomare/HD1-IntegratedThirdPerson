-- What the shoulder camera sees that the top-down one never did: the distance and a sky. Each applies
-- only while third person steers the view, and goes back with it.
--
--   far_view    the camera's far range, the planet's fog pushed out (Obsidian API's shading), and
--               distant models keeping their detail (API detail, the lod_object_multiplier setting)
--   fix_sky     a dome around the camera in the colour of the planet's fog: units the mod adds when
--               the option is on at launch (res/sky_*, tools/build_sky.py), with the render config
--               that clears the picture past the level (the same bytes as Photo Mode's)
local rig = obsidian.module("src/rig")

local M = {}

local function g(name) return rawget(_G, name) end

M.FAR = 2400          -- metres the camera sees with the long view
M.FOG_SCALE = 2.5     -- the planet's fog range times this
M.DETAIL = 2          -- distant models keep detail this many times further
M.SKY_RADIUS = 1800   -- metres
M.SKY_MADE = 500      -- the dome's own radius
-- The skies tools/build_sky.py draws, by planet type, and the fog colour each was drawn for.
M.SKIES = {
	desert = { 0.62, 0.60, 0.55 },
	forest = { 0.46, 0.58, 0.66 },
	snow = { 0.66, 0.72, 0.80 },
	lava = { 0.70, 0.34, 0.20 },
	city = { 0.52, 0.55, 0.58 },
	night = { 0.10, 0.13, 0.22 },
}
M.ENVIRONMENTS = { "desert", "forest", "snow", "lava", "city" } -- Obsidian API's order

-- The fog range pushed out: { start, end } times scale.
function M.fog_range(planet, scale)
	if type(planet) ~= "table" or type(planet[1]) ~= "number" or type(planet[2]) ~= "number" then return nil end
	return { planet[1] * scale, planet[2] * scale }
end

-- The sky for a mission: night at night, else the planet type's. environment is a name or an index
-- in ENVIRONMENTS.
function M.sky_name(environment, time)
	if time == "night" or time == 4 then return "night" end
	if type(environment) == "number" then environment = M.ENVIRONMENTS[environment] end
	if type(environment) == "string" then
		for name in pairs(M.SKIES) do
			if environment:lower():find(name, 1, true) then return name end
		end
	end
	return "desert"
end

-- The dome's brightness: how bright the planet's fog is next to the colour the sky was drawn in.
function M.sky_intensity(name, fog)
	local drawn = M.SKIES[name] or M.SKIES.desert
	local function lum(c) return 0.2126 * c[1] + 0.7152 * c[2] + 0.0722 * c[3] end
	if type(fog) ~= "table" or type(fog[1]) ~= "number" then return 2 end
	return rig.clamp(2 * lum(fog) / math.max(0.02, lum(drawn)), 0.5, 4)
end

-- Far view ------------------------------------------------------------------------------------------

-- range: the camera's far range is held at FAR (the long view, and the sky, which sits 1800 m out).
-- look: the fog and the detail of distant models, for the long view only.
local far = { range = false, saved = nil, look = false, fog = false }

local function look_apply(env)
	if far.look then return end
	far.look = true
	local api = env.api
	if not (api and api.world) then return end
	local planet = api.world.planet_shading and api.world.planet_shading("fog_depth_range")
	local range = M.fog_range(planet, M.FOG_SCALE)
	if range and api.world.shading then far.fog = api.world.shading("fog_depth_range", "vector2", range) == true end
	if api.world.detail then pcall(api.world.detail, M.DETAIL) end
end

local function look_release(env)
	if not far.look then return end
	far.look = false
	local api = env.api
	if api and api.world then
		if far.fog and api.world.shading then pcall(api.world.shading, "fog_depth_range", "vector2") end
		if api.world.detail then pcall(api.world.detail, nil) end
	end
	far.fog = false
end

local function range_apply(view)
	local C = g("Camera")
	if not far.range then
		far.range = true
		local ok, f = pcall(C.far_range, view.camera)
		far.saved = ok and f or nil
	end
	pcall(C.set_far_range, view.camera, math.max(far.saved or 0, M.FAR))
end

local function range_release(cm)
	if not far.range then return end
	far.range = false
	if far.saved and type(cm) == "table" and cm.viewport then
		pcall(function() g("Camera").set_far_range(cm.viewport:get_camera(), far.saved) end)
	end
	far.saved = nil
end

-- Sky -----------------------------------------------------------------------------------------------

local sky = { unit = nil, world = nil, name = nil }

-- The skies are in the game only when the option was on at launch: spawning a unit the game hasn't
-- loaded stops the game, past any pcall.
function M.sky_available()
	local ok, on = pcall(obsidian.settings.get, "fix_sky")
	return ok and on == true
end

local function sky_remove()
	if sky.unit and sky.world then
		pcall(function()
			if g("Unit").alive(sky.unit) then g("World").destroy_unit(sky.world, sky.unit) end
		end)
	end
	sky.unit, sky.world, sky.name = nil, nil, nil
end

local function sky_brightness(unit, value)
	local U, Mesh, Mat = g("Unit"), g("Mesh"), g("Material")
	pcall(function()
		for i = 0, U.num_meshes(unit) - 1 do
			local mesh = U.mesh(unit, i)
			for j = 0, Mesh.num_materials(mesh) - 1 do Mat.set_scalar(Mesh.material(mesh, j), "intensity", value) end
		end
	end)
end

-- The planet type (obsidian.ui.data.mission) and the time of day (the generated level's, as the game's
-- own flashlight code reads it).
local function mission_look()
	local environment, time = nil, nil
	local data = obsidian.ui and obsidian.ui.data
	local ok, m = pcall(function() return data and data.mission and data.mission() end)
	if ok and type(m) == "table" then environment = m.environment end
	local cm = g("CameraManager")
	local level = type(cm) == "table" and cm.generated_level
	if type(level) == "table" then
		environment = environment or level.environment
		time = level.time_of_day
	end
	return environment, time
end

local function sky_update(env, view)
	local U, V3 = g("Unit"), g("Vector3")
	if not (sky.unit and sky.world == view.world and U.alive(sky.unit)) then
		sky_remove()
		local api = env.api
		if not (api and api.game and api.game.in_mission and api.game.in_mission()) then return end
		local environment, time = mission_look()
		local name = M.sky_name(environment, time)
		local ok, unit = pcall(g("World").spawn_unit, view.world, "itp/sky/" .. name, V3(view.position.x, view.position.y, 0))
		if not ok or not unit then return end
		sky.unit, sky.world, sky.name = unit, view.world, name
		pcall(U.set_local_scale, unit, 0, V3(M.SKY_RADIUS / M.SKY_MADE, M.SKY_RADIUS / M.SKY_MADE, M.SKY_RADIUS / M.SKY_MADE))
		local fog = api.world and api.world.planet_shading and api.world.planet_shading("fog_color")
		sky_brightness(unit, M.sky_intensity(name, fog))
	end
	pcall(U.teleport_local_position, sky.unit, 0, V3(view.position.x, view.position.y, 0))
	pcall(g("World").update_unit, sky.world, sky.unit)
end

function M.start(env)
	local config = env.config
	table.insert(env.on_pose, function(view, cm)
		local long = config.get("far_view") and true or false
		if long then look_apply(env) else look_release(env) end
		if M.sky_available() then sky_update(env, view) else sky_remove() end
		if long or sky.unit then range_apply(view) else range_release(cm) end
	end)
	table.insert(env.on_release, function(cm)
		look_release(env)
		range_release(cm)
		sky_remove()
	end)
end

M._far, M._sky = far, sky -- for tests
return M
