-- Scoped overrides: a value or a function swapped only while one call of the game runs, and put back
-- even when that call fails. The error goes on to the loader, which never runs the game's function a
-- second time once a hook has run it.
local M = {}

function M.pack(...) return { n = select("#", ...), ... } end

local function finish(r)
	if not r[1] then error(r[2], 0) end
	return unpack(r, 2, r.n)
end

-- Calls fn(...) with enter() run before and leave() after.
function M.around(enter, leave, fn, ...)
	enter()
	local r = M.pack(pcall(fn, ...))
	leave()
	return finish(r)
end

-- Calls fn(...) with t[key] set to value, then gives t[key] back. A field another mod changed while
-- fn ran is left as that mod set it.
function M.swap(t, key, value, fn, ...)
	local before = rawget(t, key)
	rawset(t, key, value)
	local r = M.pack(pcall(fn, ...))
	if rawget(t, key) == value then rawset(t, key, before) end
	return finish(r)
end

return M
