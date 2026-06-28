--[[
	cinematic/World.lua
	Time of day, camera FOV, atmosphere haze. Quick time-of-day presets, a
	freeze-time toggle that actually holds the clock (snapshots the chosen
	value instead of echoing it back), and a timelapse toggle that sweeps the
	sun for moving-shadow shots.
--]]

local Lighting   = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")

return function(ctx, Lib)
	local page = ctx.addTab("World", 4)

	local timeFrozen = false
	local frozenClockTime = Lighting.ClockTime
	local timelapse = false
	local timelapseSpeed = 1.0 -- hours of ClockTime per real second

	-- Published so other tabs (e.g. Client's "sync animation speed to timelapse")
	-- can read the live timelapse state without reaching into this module.
	ctx.timelapse = { enabled = false, speed = timelapseSpeed }

	local timeSlider
	timeSlider = Lib.addSlider(page, 1, "Time of Day", 0, 24, Lighting.ClockTime, function(v)
		Lighting.ClockTime = v
		frozenClockTime = v
	end)

	Lib.addButtonRow(page, 2, {
		{ text = "Dawn",   width = 70, callback = function() timeSlider.set(6.5) end },
		{ text = "Noon",   width = 70, callback = function() timeSlider.set(12) end },
		{ text = "Sunset", width = 70, callback = function() timeSlider.set(18) end },
		{ text = "Night",  width = 70, callback = function() timeSlider.set(0) end },
	})

	Lib.addSlider(page, 3, "Camera FOV", 20, 120, Workspace.CurrentCamera.FieldOfView, function(v)
		Workspace.CurrentCamera.FieldOfView = v
	end)

	Lib.addSlider(page, 4, "Atmosphere Haze", 0, 10, 0, function(v)
		local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
		if not atmosphere then
			atmosphere = Instance.new("Atmosphere")
			atmosphere.Name = "CinematicHub_Atmosphere"
			atmosphere.Parent = Lighting
		end
		atmosphere.Haze = v
	end)

	local freezeToggle = Lib.addToggleRow(page, 5, "Freeze Time of Day", false, function(state)
		timeFrozen = state
		if state then frozenClockTime = Lighting.ClockTime end
	end)

	local timelapseToggle = Lib.addToggleRow(page, 6, "Timelapse (moving sun)", false, function(state)
		timelapse = state
		ctx.timelapse.enabled = state
	end)

	Lib.addSlider(page, 7, "Timelapse Speed", 0.1, 6, timelapseSpeed, function(v)
		timelapseSpeed = v
		ctx.timelapse.speed = v
	end)

	-- One Heartbeat handles both freeze (hold) and timelapse (advance). Both
	-- branches are skipped by a boolean when idle, so there's no cost when off.
	RunService.Heartbeat:Connect(function(dt)
		if timelapse then
			frozenClockTime = (frozenClockTime + timelapseSpeed * dt) % 24
			Lighting.ClockTime = frozenClockTime
		elseif timeFrozen then
			Lighting.ClockTime = frozenClockTime
		end
	end)

	ctx.onReset(function()
		timeFrozen = false
		timelapse = false
		ctx.timelapse.enabled = false
		freezeToggle.set(false, false)
		timelapseToggle.set(false, false)
		Lighting.ClockTime = 14
		frozenClockTime = 14
		Workspace.CurrentCamera.FieldOfView = 70
		local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
		if atmosphere then atmosphere.Haze = 0 end
	end)
end
