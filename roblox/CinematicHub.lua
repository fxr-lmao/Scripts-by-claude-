--[[
	CinematicHub.lua  —  loader

	All-in-one, client-side "cinematic tools" hub for Roblox. One floating
	button opens a tabbed panel: Free Cam, Shaders, Fonts, World, Extras.
	Every feature is visual/camera only — no exploits, no gameplay edits.

	This file is a thin loader: the actual code lives in small modules under
	roblox/cinematic/ so it's easy to read and maintain. Run it with an
	executor via:

	    loadstring(game:HttpGet("<raw url to this file>"))()

	or, in Studio, place the cinematic/ ModuleScripts and require them.

	IMPORTANT (loadstring usage): SOURCE.ref below must point at the branch /
	commit that actually contains the cinematic/ folder. It's set to the
	development branch; flip it to "refs/heads/main" once this is merged.
--]]

-- Auto-execute safe: when dropped in an executor's autoexec folder this can run
-- before the place or the local player exist. Wait for both so nothing downstream
-- (LocalPlayer, PlayerGui, PlayerModule) is nil.
local Players = game:GetService("Players")
if not game:IsLoaded() then game.Loaded:Wait() end
if not Players.LocalPlayer then Players:GetPropertyChangedSignal("LocalPlayer"):Wait() end

local SOURCE = {
	repo = "fxr-lmao/Scripts-by-claude-",
	ref  = "refs/heads/claude/hub-freecam-qol-0jgtb0",
	dir  = "roblox/cinematic",
}

local BASE = ("https://raw.githubusercontent.com/%s/%s/%s/"):format(SOURCE.repo, SOURCE.ref, SOURCE.dir)

-- If this hub is required as a ModuleScript (Studio), resolve siblings locally;
-- otherwise fetch each module over HTTP (executor).
local localModules = script and script:FindFirstChild("cinematic")

local cache = {}
local function loadModule(name)
	if cache[name] then return cache[name] end
	local result
	if localModules then
		result = require(localModules:FindFirstChild(name))
	else
		local url = BASE .. name .. ".lua"
		local ok, body = pcall(function() return game:HttpGet(url) end)
		if not ok then
			error(("[CinematicHub] couldn't fetch %s (%s). Is the repo public?")
				:format(name, tostring(body)))
		end
		local chunk, compileErr = loadstring(body)
		if not chunk then
			error(("[CinematicHub] couldn't compile %s: %s"):format(name, tostring(compileErr)))
		end
		result = chunk()
	end
	cache[name] = result
	return result
end

local Lib   = loadModule("Lib")
local Shell = loadModule("Shell")
local ctx   = Shell(Lib)

-- Tab modules (each is `function(ctx, Lib) ... end`).
loadModule("FreeCam")(ctx, Lib)
loadModule("Shaders")(ctx, Lib)
loadModule("Fonts")(ctx, Lib)
loadModule("World")(ctx, Lib)
loadModule("Client")(ctx, Lib)
loadModule("Fun")(ctx, Lib)
loadModule("Extras")(ctx, Lib)

ctx.selectTab("Free Cam")

print("[CinematicHub] Loaded. Tap '🎬 Cinematic' or press ` to open. Press P for Free Cam.")
return ctx
