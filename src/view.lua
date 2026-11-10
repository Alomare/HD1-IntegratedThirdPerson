-- What the shoulder camera sees that the top-down one never did: the distance, a sky, and the back
-- of the Super Destroyer bridge. Each applies only while third person steers the view, and goes back
-- with it.
--
--   far_view    the camera's far range, the planet's fog pushed out (Obsidian API's shading), and
--               distant models keeping their detail (API detail, the lod_object_multiplier setting)
--   fix_sky     a dome around the camera in the colour of the planet's fog: units the mod adds when
--               the option is on at launch (res/sky_*, tools/build_sky.py), with the render config
--               that clears the picture past the level (the same bytes as Photo Mode's)
--   ship_walls  copies of the game's own menu/menu_wallpanel_02 close the open side of the bridge and
--               the ceiling, as Third Person Camera does (CameraManager.mod_build_ship_interior there)
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
M.PANEL = "menu/menu_wallpanel_02"
M.SHIP_PARTS = { "menu/menu_ship_01", "menu/menu_wallpanel_01", "menu/menu_wallpanel_02" }
M.MAX_PANELS = 40

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

-- The open side of the bridge: of the four sides of the bounds, the one with the fewest panels near
-- the edge is the window, and the wall goes on the side across from it. positions: the game's panels.
function M.wall_side(bounds, positions)
	local counts = { ["y-"] = 0, ["y+"] = 0, ["x-"] = 0, ["x+"] = 0 }
	for _, p in ipairs(positions) do
		if p.y < bounds.min.y + 3 then counts["y-"] = counts["y-"] + 1 end
		if p.y > bounds.max.y - 3 then counts["y+"] = counts["y+"] + 1 end
		if p.x < bounds.min.x + 3 then counts["x-"] = counts["x-"] + 1 end
		if p.x > bounds.max.x - 3 then counts["x+"] = counts["x+"] + 1 end
	end
	local window = "y-"
	for _, side in ipairs({ "y+", "x-", "x+" }) do
		if counts[side] < counts[window] then window = side end
	end
	local across = { ["y-"] = "y+", ["y+"] = "y-", ["x-"] = "x+", ["x+"] = "x-" }
	return across[window], window
end

-- Where the panels go: a wall of width w by height h panels along `side`, facing in, from the floor
-- to the ceiling, and a ceiling of panels facing down. Answers { position, facing, up } each.
function M.wall_layout(bounds, side, w, h)
	local out = {}
	local lo, hi = bounds.min, bounds.max
	local rows = math.max(1, math.min(M.MAX_PANELS, math.ceil((hi.z - lo.z) / h)))
	local along_x = side == "y-" or side == "y+"
	local from, to = along_x and lo.x or lo.y, along_x and hi.x or hi.y
	local columns = math.max(1, math.min(M.MAX_PANELS, math.ceil((to - from) / w)))
	local edge, facing
	if side == "y-" then edge, facing = lo.y, { x = 0, y = 1, z = 0 }
	elseif side == "y+" then edge, facing = hi.y, { x = 0, y = -1, z = 0 }
	elseif side == "x-" then edge, facing = lo.x, { x = 1, y = 0, z = 0 }
	else edge, facing = hi.x, { x = -1, y = 0, z = 0 } end
	for c = 0, columns - 1 do
		for r = 0, rows - 1 do
			local a, z = from + w * (c + 0.5), lo.z + h * (r + 0.5)
			local p = along_x and { x = a, y = edge, z = z } or { x = edge, y = a, z = z }
			out[#out + 1] = { position = p, facing = facing, up = { x = 0, y = 0, z = 1 } }
		end
	end
	local cw, ch = w * 0.8, h * 0.8
	local nx = math.min(M.MAX_PANELS, math.ceil((hi.x - lo.x) / cw) + 3)
	local ny = math.min(M.MAX_PANELS, math.ceil((hi.y - lo.y) / ch) + 3)
	for i = 0, nx - 1 do
		for j = 0, ny - 1 do
			out[#out + 1] = { position = { x = lo.x - cw + cw * i, y = lo.y - ch + ch * j, z = hi.z },
				facing = { x = 0, y = 0, z = -1 }, up = { x = 0, y = 1, z = 0 } }
		end
	end
	return out
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

-- Ship walls ----------------------------------------------------------------------------------------

local walls = { world = nil, units = {}, failed = nil }

local function walls_remove()
	for _, u in ipairs(walls.units) do
		pcall(function() if g("Unit").alive(u) then g("World").destroy_unit(walls.world, u) end end)
	end
	walls.units, walls.world = {}, nil
end

local function is_a(unit, name)
	local ok, yes = pcall(g("Unit").is_a, unit, name)
	return ok and yes
end

-- The bridge's bounds, the game's panels and one panel to copy, from the units of the ship's world.
local function survey(world)
	local U, M4 = g("Unit"), g("Matrix4x4")
	local lo, hi, panels, model = nil, nil, {}, nil
	for _, u in ipairs(g("World").units(world)) do
		if U.alive(u) then
			for _, part in ipairs(M.SHIP_PARTS) do
				if is_a(u, part) then
					local ok, pose, half = pcall(U.box, u)
					if ok and pose and half then
						local c = M4.translation(pose)
						local a = { x = c.x - half.x, y = c.y - half.y, z = c.z - half.z }
						local b = { x = c.x + half.x, y = c.y + half.y, z = c.z + half.z }
						lo = lo and { x = math.min(lo.x, a.x), y = math.min(lo.y, a.y), z = math.min(lo.z, a.z) } or a
						hi = hi and { x = math.max(hi.x, b.x), y = math.max(hi.y, b.y), z = math.max(hi.z, b.z) } or b
					end
					if part == M.PANEL then
						model = model or u
						local p = U.world_position(u, 0)
						panels[#panels + 1] = { x = p.x, y = p.y, z = p.z }
					end
				end
			end
		end
	end
	if not (lo and model) then return nil end
	return { min = lo, max = hi }, panels, model
end

local function walls_build(env, world)
	walls_remove()
	walls.world = world
	local U, Q, V3, M4 = g("Unit"), g("Quaternion"), g("Vector3"), g("Matrix4x4")
	local bounds, panels, model = survey(world)
	if not bounds then
		walls.failed = "no bridge found"
		return
	end
	-- The model panel's size: the shortest axis of the box is the thickness; of the other two, the one
	-- nearest up is the height.
	local pose, half = U.box(model)
	local axes = { M4.right(pose), M4.forward(pose), M4.up(pose) }
	local ext = { half.x, half.y, half.z }
	local thick = 1
	for i = 2, 3 do if ext[i] < ext[thick] then thick = i end end
	local tall, best = nil, -1
	for i = 1, 3 do
		if i ~= thick then
			local n = rig.normalize({ x = axes[i].x, y = axes[i].y, z = axes[i].z })
			local d = n and math.abs(n.z) or 0
			if d > best then tall, best = i, d end
		end
	end
	local wide = 6 - thick - tall
	local w, h = ext[wide] * 2, ext[tall] * 2
	if w < 0.5 or h < 0.5 then
		walls.failed = "panel too small"
		return
	end
	-- The model's face and up, to turn each copy from.
	local centre = M4.translation(pose)
	local face = rig.normalize({ x = axes[thick].x, y = axes[thick].y, z = axes[thick].z })
	local mid = { x = (bounds.min.x + bounds.max.x) / 2, y = (bounds.min.y + bounds.max.y) / 2, z = centre.z }
	if rig.dot(face, rig.sub(mid, centre)) < 0 then face = { x = -face.x, y = -face.y, z = -face.z } end
	local up = rig.normalize({ x = axes[tall].x, y = axes[tall].y, z = axes[tall].z })
	if up.z < 0 then up = { x = -up.x, y = -up.y, z = -up.z } end
	local model_look = Q.look(V3(face.x, face.y, face.z), V3(up.x, up.y, up.z))
	local model_rot = U.world_rotation(model, 0)
	local origin = U.world_position(model, 0)
	local offset = V3(centre.x - origin.x, centre.y - origin.y, centre.z - origin.z)
	local scale = U.local_scale(model, 0)
	local side = M.wall_side(bounds, panels)
	for _, slot in ipairs(M.wall_layout(bounds, side, w, h)) do
		local turn = Q.multiply(Q.look(V3(slot.facing.x, slot.facing.y, slot.facing.z), V3(slot.up.x, slot.up.y, slot.up.z)),
			Q.inverse(model_look))
		local rot = Q.multiply(turn, model_rot)
		local shift = Q.rotate(turn, offset)
		local at = V3(slot.position.x - shift.x, slot.position.y - shift.y, slot.position.z - shift.z)
		local ok, unit = pcall(g("World").spawn_unit, world, M.PANEL, at, rot)
		if ok and unit then
			pcall(U.set_local_scale, unit, 0, scale)
			-- No physics: the copies only close the view, and must not block anyone walking.
			pcall(function() for i = U.num_actors(unit) - 1, 0, -1 do U.destroy_actor(unit, i) end end)
			walls.units[#walls.units + 1] = unit
		end
	end
	env.log("Integrated Third Person: ship walls on side " .. side .. ", " .. #walls.units .. " panels")
end

local function walls_update(env, view, cm)
	if cm.state ~= "follow_menu" then return end
	if walls.world == view.world and (#walls.units > 0 or walls.failed) then return end
	walls.failed = nil
	local ok, err = pcall(walls_build, env, view.world)
	if not ok then
		walls.failed = tostring(err)
		env.log("Integrated Third Person: ship walls: " .. walls.failed)
	end
end

function M.start(env)
	local config = env.config
	table.insert(env.on_pose, function(view, cm)
		local long = config.get("far_view") and true or false
		if long then look_apply(env) else look_release(env) end
		if M.sky_available() then sky_update(env, view) else sky_remove() end
		if long or sky.unit then range_apply(view) else range_release(cm) end
		if config.get("ship_walls") then walls_update(env, view, cm) elseif #walls.units > 0 then walls_remove() end
	end)
	table.insert(env.on_release, function(cm)
		look_release(env)
		range_release(cm)
		sky_remove()
		walls_remove()
		walls.failed = nil
	end)
end

M._far, M._sky, M._walls = far, sky, walls -- for tests
return M
