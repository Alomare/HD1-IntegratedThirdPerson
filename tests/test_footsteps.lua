-- Louder footsteps: copies of each footstep the game played, for Helldivers and enemies, only in
-- third person.
local E = dofile("tests/engine.lua")

local function setup(active)
	E.install()
	local env = E.env()
	env.config.start(env)
	env.state.active = active
	obsidian.module("src/footsteps").start(env)
	local fired = {}
	rawset(_G, "TimpaniWorld", {
		has_event = function(_, sound) return sound ~= "missing" end,
		trigger_event = function(world, sound, position) fired[#fired + 1] = { world = world, sound = sound, position = position } end,
	})
	rawset(_G, "ENGINE_TIME", 12.5)
	local manager = {
		timpani_world = "tw",
		last_played = {},
		effect_settings = {
			footstep = { sand = { audio = "fs_sand_walk" } },
			footstep_bug = { sand = { audio = "footstep_light_gravel" } },
			footstep_mech = { sand = { audio = "missing" } },
			projectile = { sand = { audio = "bullet_sand" } },
		},
	}
	-- The game function: plays the sound unless it played too soon before.
	local function game(self, _, effect_type, _, _, _, surface)
		local sound = self.effect_settings[effect_type][surface].audio
		local last = self.last_played[sound]
		if last and ENGINE_TIME - last < 0.1 and last ~= ENGINE_TIME then return "skipped" end
		self.last_played[sound] = ENGINE_TIME
		return "played"
	end
	local hook = E.hook("SurfaceEffectManager", "do_sound_fx")
	local function step(effect_type)
		return hook(game, manager, "ground", effect_type, E.V3(4, 5, 0), E.V3(0, 0, 1), nil, "sand")
	end
	return manager, fired, step
end

local function finish()
	rawset(_G, "TimpaniWorld", nil)
	rawset(_G, "ENGINE_TIME", nil)
	E.remove()
end

return {
	{ "each footstep plays four times at Loudest, the default", function()
		local _, fired, step = setup(true)
		eq(step("footstep"), "played", "the game answer comes back")
		eq(#fired, 3, "three copies on top of the step")
		eq(fired[1].sound, "fs_sand_walk") eq(fired[1].world, "tw")
		eq(fired[1].position.x .. "," .. fired[1].position.y, "4,5", "at the step")
		finish()
	end },

	{ "enemy steps count too, other surface sounds don't", function()
		local _, fired, step = setup(true)
		step("footstep_bug")
		eq(#fired, 3, "a bug step")
		step("projectile")
		eq(#fired, 3, "a bullet hit is left alone")
		finish()
	end },

	{ "Louder plays a step twice and Normal once", function()
		OPTIONS.footsteps = "louder"
		local _, fired, step = setup(true)
		step("footstep")
		eq(#fired, 1, "one copy")
		OPTIONS.footsteps = "normal"
		step("footstep_bug")
		eq(#fired, 1, "no copy")
		finish()
	end },

	{ "no copies for a step the game skipped, a missing sound or the top-down view", function()
		local manager, fired, step = setup(true)
		manager.last_played.fs_sand_walk = 12.45
		eq(step("footstep"), "skipped")
		eq(#fired, 0, "skipped step")
		step("footstep_mech")
		eq(#fired, 0, "missing sound")
		finish()
		local _, fired2, step2 = setup(false)
		step2("footstep")
		eq(#fired2, 0, "top-down view")
		finish()
	end },
}
