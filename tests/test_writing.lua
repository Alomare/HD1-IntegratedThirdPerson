-- Player-facing text in obsidian.json keeps the writing rules: no "its", no "it's", no dashes
-- used as punctuation, no first person.
local function read(path)
	local f = assert(io.open(path, "rb"))
	local s = f:read("*a")
	f:close()
	return s
end

return {
	{ "manifest text has no its, dashes or first person", function()
		local s = read("obsidian.json")
		for text in s:gmatch('"en"%s*:%s*"(.-)"') do
			local lower = " " .. text:lower() .. " "
			assert(not lower:find("[^%w]its[^%w]"), "its in: " .. text)
			assert(not lower:find("it's", 1, true), "it's in: " .. text)
			assert(not text:find("\226\128\148", 1, true) and not text:find("\226\128\147", 1, true), "dash in: " .. text)
			assert(not lower:find("[^%w]my[^%w]") and not lower:find("[^%w]i[^%w]"), "first person in: " .. text)
		end
	end },
}
