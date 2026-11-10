-- The camera rig in plain numbers, with no engine calls, so tests can run it.
--
-- Angles are degrees, as Obsidian API's camera takes them: yaw turns about the up axis, 0 looks along
-- +y (the level's north) and grows turning left seen from above; pitch looks up when positive.
-- Positions and vectors are { x, y, z } tables in metres.
local M = {}

M.PITCH_MIN, M.PITCH_MAX = -65, 55
M.START_PITCH = -8        -- a new view looks a little down
M.FOOT_HEIGHT = 1.5        -- the point the camera turns about, above the feet
M.SHOULDER = 0.65          -- metres the camera sits to the side on foot
M.AIM_DISTANCE = 0.5       -- share of the distance kept while the aim button is held
M.AIM_FOV = 0.7            -- share of the field of view kept while aiming
M.MOUSE_RATE = 0.12        -- degrees per count of the mouse, at look speed 1
M.STICK_YAW, M.STICK_PITCH = 160, 110 -- degrees a second at full stick, at look speed 1
M.STICK_DEADZONE = 0.15
M.MARGIN = 0.25            -- metres kept between the camera and a wall
M.MIN_LENGTH = 0.35        -- the closest the camera comes to the pivot
-- Pivot heights in a vehicle, by Obsidian API's vehicle kinds.
M.VEHICLE_HEIGHT = { exosuit = 3.2, apc = 2.6, tank = 2.8, bike = 1.7, turret = 1.9 }
M.VEHICLE_HEIGHT_DEFAULT = 2.4

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
M.clamp = clamp

function M.wrap(a)
	a = a % 360
	if a > 180 then a = a - 360 end
	return a
end

function M.forward(yaw, pitch)
	local y, p = math.rad(yaw), math.rad(pitch or 0)
	return { x = -math.sin(y) * math.cos(p), y = math.cos(y) * math.cos(p), z = math.sin(p) }
end

function M.right(yaw)
	local y = math.rad(yaw)
	return { x = math.cos(y), y = math.sin(y), z = 0 }
end

function M.flat_forward(yaw)
	local y = math.rad(yaw)
	return { x = -math.sin(y), y = math.cos(y), z = 0 }
end

function M.add(p, v, s)
	s = s or 1
	return { x = p.x + v.x * s, y = p.y + v.y * s, z = p.z + v.z * s }
end

function M.sub(a, b) return { x = a.x - b.x, y = a.y - b.y, z = a.z - b.z } end

function M.dot(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end

function M.length(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end

function M.normalize(v)
	local l = M.length(v)
	if l < 1e-9 then return nil end
	return { x = v.x / l, y = v.y / l, z = v.z / l }
end

-- The yaw and pitch that look along a direction.
function M.yaw_of(dir) return math.deg(math.atan2(-dir.x, dir.y)) end

function M.pitch_of(dir)
	local d = M.normalize(dir)
	if not d then return 0 end
	return math.deg(math.asin(clamp(d.z, -1, 1)))
end

-- The game turns the movement keys and the stick by CameraManager.follow_spin (radians, about the
-- up axis), and W moves along the yaw this gives.
function M.spin_of(yaw) return math.rad(yaw) end

-- A share of the way from current to target this frame, the same at any frame rate: rate is how
-- many times e it closes per second.
function M.ease_share(rate, dt) return 1 - math.exp(-rate * math.max(0, dt)) end

function M.ease(current, target, rate, dt)
	return current + (target - current) * M.ease_share(rate, dt)
end

function M.ease_angle(current, target, rate, dt)
	return M.wrap(current + M.wrap(target - current) * M.ease_share(rate, dt))
end

-- The stick past the dead zone, from 0 to 1, keeping the sign, squared for fine aim near the middle.
function M.stick_curve(v)
	local a = math.abs(v)
	if a < M.STICK_DEADZONE then return 0 end
	local t = math.min((a - M.STICK_DEADZONE) / (1 - M.STICK_DEADZONE), 1)
	return (v < 0 and -1 or 1) * t * t
end

-- Turns a view by this frame's look input. mouse: counts moved { x right, y down the screen }.
-- stick: the right stick { x right, y up }. opts: speed (look speed), invert, zoom (share of the field
-- of view kept, so aiming turns slower), dt.
function M.look(view, mouse, stick, opts)
	local speed = (opts.speed or 1) * (opts.zoom or 1)
	local flip = opts.invert and -1 or 1
	local yaw, pitch = view.yaw, view.pitch
	if mouse then
		yaw = yaw - (mouse.x or 0) * M.MOUSE_RATE * speed
		pitch = pitch - (mouse.y or 0) * M.MOUSE_RATE * speed * flip
	end
	if stick then
		local dt = opts.dt or 0
		yaw = yaw - M.stick_curve(stick.x or 0) * M.STICK_YAW * speed * dt
		pitch = pitch + M.stick_curve(stick.y or 0) * M.STICK_PITCH * speed * dt * flip
	end
	view.yaw = M.wrap(yaw)
	view.pitch = clamp(pitch, M.PITCH_MIN, M.PITCH_MAX)
	return view
end

-- Where the camera wants to be: behind the pivot along the view, and to the side by `side` metres
-- (positive to the right). Answers the position and the unit vector from the pivot to it, with the
-- full length.
function M.place(pivot, yaw, pitch, distance, side)
	local f, r = M.forward(yaw, pitch), M.right(yaw)
	local at = M.add(M.add(pivot, r, side or 0), f, -distance)
	local off = M.sub(at, pivot)
	local length = M.length(off)
	local dir = M.normalize(off) or { x = -f.x, y = -f.y, z = -f.z }
	return at, dir, length
end

-- The length the camera may have from the pivot when something is hit `hit` metres along the way
-- (nil for nothing), keeping MARGIN from the wall.
function M.pull_in(full, hit)
	if not hit then return full end
	return clamp(hit - M.MARGIN, math.min(M.MIN_LENGTH, full), full)
end

-- Eases the camera's length: in at once toward a wall, out slowly once it clears, so it never shows
-- the inside of a rock and doesn't pump in and out.
function M.follow_length(current, wanted, dt)
	if not current or wanted <= current then return wanted end
	return M.ease(current, wanted, 4, dt)
end

-- The pivot eased toward the target: quick across the ground, slower up and down so steps and
-- landings don't jolt the view. A jump of more than 15 m (a teleport, a respawn) snaps.
function M.follow_pivot(current, target, dt)
	if not current then return { x = target.x, y = target.y, z = target.z } end
	local dx, dy, dz = target.x - current.x, target.y - current.y, target.z - current.z
	if dx * dx + dy * dy + dz * dz > 225 then return { x = target.x, y = target.y, z = target.z } end
	local s, sz = M.ease_share(22, dt), M.ease_share(12, dt)
	return { x = current.x + dx * s, y = current.y + dy * s, z = current.z + dz * sz }
end

-- The camera's distance, field of view and side offset for this frame. opts: distance, fov (degrees),
-- side (1 right, -1 left), aim (0 to 1, how far into the aim zoom), vehicle (no shoulder offset).
function M.lens(opts)
	local aim = clamp(opts.aim or 0, 0, 1)
	local distance = opts.distance * (1 + (M.AIM_DISTANCE - 1) * aim)
	local fov = opts.fov * (1 + (M.AIM_FOV - 1) * aim)
	local side = 0
	if not opts.vehicle then side = (opts.side or 1) * M.SHOULDER * (1 + 0.15 * aim) end
	return distance, fov, side
end

-- The pivot's height above the unit it follows.
function M.height(kind)
	if not kind then return M.FOOT_HEIGHT end
	return M.VEHICLE_HEIGHT[kind] or M.VEHICLE_HEIGHT_DEFAULT
end

-- How far along the camera's line the crosshair ray starts: past the pivot, so the Helldiver's own body
-- is never what the crosshair hits.
function M.ray_start(camera, forward, pivot)
	local past = M.dot(M.sub(pivot, camera), forward)
	return math.max(0, past) + 0.5
end

-- The way a shot goes from `origin` to the crosshair point. Answers nil when the point is closer than
-- 1.5 m or behind the shot's own forward, where the game's own aim is safer.
function M.shot_dir(origin, point, forward)
	local d = M.sub(point, origin)
	if M.length(d) < 1.5 then return nil end
	local n = M.normalize(d)
	if forward and M.dot(n, forward) < 0 then return nil end
	return n
end

-- The flat way from a unit to the crosshair point, for the game's aim input, or nil when the point is
-- right above or below.
function M.flat_dir(from, point)
	local d = { x = point.x - from.x, y = point.y - from.y, z = 0 }
	if d.x * d.x + d.y * d.y < 0.01 then return nil end
	return M.normalize(d)
end

return M
