-- Offline tests for the parts of Integrated Third Person that don't need the game. From the
-- repository root:
--   luajit tests/run.lua
-- Every tests/test_*.lua file returns a list of { name, fn }. Each test starts with a fresh fake
-- `obsidian` global; a test file builds the engine fakes it needs itself.
local passed, failed = 0, 0

function fresh_obsidian()
	local loaded = {}
	LOGS, OPTIONS, STORED, HOOKS, FRAMES, KEYS = {}, {}, {}, {}, {}, {}
	obsidian = {
		capabilities = { parts = true },
		module = function(name)
			if loaded[name] == nil then loaded[name] = dofile(name .. ".lua") end
			return loaded[name]
		end,
		import = function() return nil end,
		log = function(...) LOGS[#LOGS + 1] = table.concat({ ... }, " ") end,
		caller = function() return "alomare.integratedthirdperson" end,
		settings = { get = function(id) return OPTIONS[id] end },
		storage = { get = function(k, d) if STORED[k] == nil then return d end return STORED[k] end,
			set = function(k, v) STORED[k] = v end },
		hook = function(target, method, fn, opts) HOOKS[#HOOKS + 1] = { target = target, method = method, fn = fn, opts = opts } end,
		on_require = function(name, fn) HOOKS[#HOOKS + 1] = { require = name, fn = fn } end,
		on_frame = function(fn, opts) FRAMES[#FRAMES + 1] = { fn = fn, opts = opts } end,
		on_session = function(fn, opts) HOOKS[#HOOKS + 1] = { session = fn, opts = opts } end,
		keybind = function(id, fn, opts) KEYS[id] = { fn = fn, opts = opts } end,
		after_startup = function(fn) fn() end,
		session = { cleared = function() return true end },
		toast = function(s) LOGS[#LOGS + 1] = "toast: " .. tostring(s) end,
		ui = {},
	}
end

function eq(got, want, what)
	if got ~= want then error((what or "value") .. ": expected " .. tostring(want) .. ", got " .. tostring(got), 2) end
end

function near(got, want, what, tolerance)
	if type(got) ~= "number" or math.abs(got - want) > (tolerance or 1e-6) then
		error((what or "value") .. ": expected " .. tostring(want) .. ", got " .. tostring(got), 2)
	end
end

local function test(name, fn)
	fresh_obsidian()
	local ok, err = xpcall(fn, debug.traceback)
	if ok then passed = passed + 1 else failed = failed + 1 print("FAIL " .. name .. "\n" .. err) end
end

local files = {}
local p = io.popen('ls tests 2>nul || dir /b tests')
if p then
	for line in p:lines() do
		local f = line:match("^(test_[%w_]+%.lua)$")
		if f then files[#files + 1] = "tests/" .. f end
	end
	p:close()
end
table.sort(files)

for _, file in ipairs(files) do
	local tests = dofile(file)
	for _, t in ipairs(tests) do test(file .. " " .. t[1], t[2]) end
end
print(passed .. " passed, " .. failed .. " failed")
os.exit(failed == 0 and 0 or 1)
