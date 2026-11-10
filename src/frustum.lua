-- The game's top-down screen, kept for the game's rules while the third-person view is drawn.
--
-- CameraManager:is_position_inside_frustum decides gameplay, not only drawing: enemies and patrols
-- spawn and despawn outside it, a patrol raises the alarm only inside it, escort NPCs die after time off
-- it, the squad leash keeps players on one screen, a downed Helldiver gets up only inside it, and a
-- respawn waits for it. The game's own CameraManager.update keeps running under the third-person view
-- and keeps the top-down pose in CameraManager.position and .rotation, so these questions are answered
-- against that pose, as if the top-down camera were still drawn. Only the HUD's markers (Hud.draw_plugins)
-- ask about the view on screen.
--
-- The answer comes from the game's own two functions, which ask the viewport: while one of them runs,
-- ViewportProxy.world_to_viewport and ViewportProxy.screen_to_world answer for the top-down pose.
local rig = obsidian.module("src/rig")
local scoped = obsidian.module("src/scoped")

local M = {}

local function g(name) return rawget(_G, name) end

-- A camera in plain numbers: position, forward, right and up unit vectors, fov (vertical, radians).
-- The top-down camera never rolls, so right and up follow from forward.
function M.camera_from(position, forward, fov)
	local f = rig.normalize(forward) or { x = 0, y = 1, z = 0 }
	local r = rig.normalize({ x = f.y, y = -f.x, z = 0 }) or { x = 1, y = 0, z = 0 }
	-- up = right x forward
	local u = { x = r.y * f.z - r.z * f.y, y = r.z * f.x - r.x * f.z, z = r.x * f.y - r.y * f.x }
	return { position = position, forward = f, right = r, up = u, fov = fov }
end

-- What Camera.world_to_screen answers for this camera: x and y in pixels of a w by h viewport (y up
-- from the bottom), and the depth along forward. A point behind gets the mirrored place, as the
-- engine's does.
function M.project(cam, p, w, h)
	local d = rig.sub(p, cam.position)
	local depth = rig.dot(d, cam.forward)
	local ty = math.tan(cam.fov / 2)
	local tx = ty * w / h
	local z = depth
	if math.abs(z) < 1e-6 then z = 1e-6 end
	local sx = w / 2 * (1 + rig.dot(d, cam.right) / (z * tx))
	local sy = h / 2 * (1 + rig.dot(d, cam.up) / (z * ty))
	return sx, depth, sy
end

-- The point of the level at a place of the viewport (pixels) and a depth along forward.
function M.unproject(cam, x, y, depth, w, h)
	local ty = math.tan(cam.fov / 2)
	local tx = ty * w / h
	local nx, ny = x / (w / 2) - 1, y / (h / 2) - 1
	local p = rig.add(cam.position, cam.forward, depth)
	p = rig.add(p, cam.right, nx * depth * tx)
	return rig.add(p, cam.up, ny * depth * ty)
end

-- The top-down pose the game's CameraManager keeps, as a camera.
function M.top_down(cm)
	local V3A, QA, Q = g("Vector3Aux"), g("QuaternionAux"), g("Quaternion")
	local p = V3A.unbox(cm.position)
	local f = Q.forward(QA.unbox(cm.rotation))
	return M.camera_from({ x = p.x, y = p.y, z = p.z }, { x = f.x, y = f.y, z = f.z }, cm.fov or math.rad(60))
end

function M.install(env)
	local state = env.state
	local asking = 0      -- inside the game's frustum functions, for the game's rules
	local drawing = false -- inside the HUD's markers, which follow the view on screen
	local cached, cached_frame = nil, nil

	local function top_down(cm)
		local frame = env.frame and env.frame() or 0
		if cached and cached_frame == frame then return cached end
		cached, cached_frame = M.top_down(cm), frame
		return cached
	end

	local function enter() asking = asking + 1 end
	local function leave() asking = asking - 1 end
	local function rules(original, self, ...)
		if not state.active or drawing then return original(self, ...) end
		return scoped.around(enter, leave, original, self, ...)
	end
	obsidian.hook("CameraManager", "is_position_inside_frustum", rules, env.VIEW)
	obsidian.hook("CameraManager", "get_closest_position_outside_frustum", rules, env.VIEW)

	local function draw_on() drawing = true end
	local function draw_off() drawing = false end
	obsidian.hook("Hud", "draw_plugins", function(original, ...)
		return scoped.around(draw_on, draw_off, original, ...)
	end, env.VIEW)

	local function ours(viewport)
		local cm = g("CameraManager")
		return asking > 0 and type(cm) == "table" and cm.viewport == viewport and cm.position and cm.rotation, cm
	end

	obsidian.hook("ViewportProxy", "world_to_viewport", function(original, self, p, ...)
		local yes, cm = ours(self)
		if not yes then return original(self, p, ...) end
		local w, h = self:window()
		local sx, depth, sy = M.project(top_down(cm), { x = p.x, y = p.y, z = p.z }, w, h)
		return g("Vector3")(sx, depth, sy)
	end, env.VIEW)

	obsidian.hook("ViewportProxy", "screen_to_world", function(original, self, a, b, c, ...)
		local yes, cm = ours(self)
		if not yes or (b == nil and c == nil) then return original(self, a, b, c, ...) end
		local w, h, x0, y0 = self:window()
		local p = M.unproject(top_down(cm), a - (x0 or 0), b - (y0 or 0), c, w, h)
		return g("Vector3")(p.x, p.y, p.z)
	end, env.VIEW)

	-- Points behind the third-person camera project mirrored in front of it. Callers that draw at
	-- world_to_screen (names, markers) get them far off screen instead, with the depth kept.
	-- Both answer the depth in z.
	local function off_screen(original, self, p, ...)
		local v = original(self, p, ...)
		if state.active and asking == 0 and v and type(v.z) == "number" and v.z <= 0 then
			return g("Vector3")(-100000, -100000, v.z)
		end
		return v
	end
	obsidian.hook("CameraManager", "world_to_screen", off_screen, env.VIEW)
	obsidian.hook("CameraManager", "world_to_viewport", off_screen, env.VIEW)

	M.asking = function() return asking > 0 end
end

return M
