-- Louder footsteps while the shoulder view is on. Each footstep sound the game plays, for Helldivers
-- and enemies alike (SurfaceEffectManager effect types that start with "footstep"), plays again at the
-- same spot, so the copies add up. The sound files stay as they are: a bigger change would need new
-- sound banks.
--
-- SurfaceEffectManager.do_sound_fx looks up the sound for the effect type and the ground, and
-- play_sound_fx_effect skips a sound played again too soon, marking each one it plays with
-- ENGINE_TIME in last_played. Copies follow only a step that played this frame.
local scoped = obsidian.module("src/scoped")

local M = {}

M.COPIES = { normal = 0, louder = 1, loudest = 3 }

local function g(name) return rawget(_G, name) end

function M.copies(level) return M.COPIES[level] or 0 end

function M.is_footstep(effect_type)
	return type(effect_type) == "string" and effect_type:sub(1, 8) == "footstep"
end

-- The extra copies of one step, if the game played it this frame.
function M.echo(manager, effect_type, position, surface, copies)
	if copies <= 0 or not position then return 0 end
	local by_type = type(manager.effect_settings) == "table" and manager.effect_settings[effect_type]
	local entry = type(by_type) == "table" and by_type[surface]
	local sound = type(entry) == "table" and entry.audio
	if type(sound) ~= "string" then return 0 end
	local played = type(manager.last_played) == "table" and manager.last_played[sound]
	if played == nil or played ~= g("ENGINE_TIME") then return 0 end
	local TW, world = g("TimpaniWorld"), manager.timpani_world
	if not (TW and world) or not TW.has_event(world, sound) then return 0 end
	for _ = 1, copies do TW.trigger_event(world, sound, position) end
	return copies
end

function M.start(env)
	local state, config = env.state, env.config
	obsidian.hook("SurfaceEffectManager", "do_sound_fx", function(original, self, unit, effect_type, position, normal, forward, surface, ...)
		local r = scoped.pack(original(self, unit, effect_type, position, normal, forward, surface, ...))
		if state.active and M.is_footstep(effect_type) then
			local copies = M.copies(config.get("footsteps") or "loudest")
			if copies > 0 then pcall(M.echo, self, effect_type, position, surface, copies) end
		end
		return unpack(r, 1, r.n)
	end, env.VIEW)
end

return M
