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
	local timelapseSpeed = 1.0 -- target: hours of ClockTime per real second
	local curTLSpeed = 0       -- live speed, ramped toward the target
	local TL_ACCEL = 2.0       -- ramp rate (units/sec) → the "accelerate" feel

	-- Published so other tabs (e.g. Client's "sync animation speed to timelapse")
	-- can read the LIVE (ramped) timelapse state without reaching into this module.
	ctx.timelapse = { enabled = false, speed = 0 }

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
		timelapse = state -- the ramp below eases curTLSpeed toward the target
	end)

	Lib.addSlider(page, 7, "Timelapse Speed", 0.1, 6, timelapseSpeed, function(v)
		timelapseSpeed = v
	end)

	-- Fullbright: flatten lighting so nothing is in shadow (great for dark games
	-- and clean shots). Snapshots the originals so it restores exactly.
	local fbSaved
	local function setFullbright(on)
		if on then
			if not fbSaved then
				fbSaved = {
					Ambient = Lighting.Ambient,
					OutdoorAmbient = Lighting.OutdoorAmbient,
					Brightness = Lighting.Brightness,
					GlobalShadows = Lighting.GlobalShadows,
					FogEnd = Lighting.FogEnd,
					ExposureCompensation = Lighting.ExposureCompensation,
				}
			end
			Lighting.Ambient = Color3.fromRGB(178, 178, 178)
			Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
			Lighting.Brightness = 2
			Lighting.GlobalShadows = false
			Lighting.FogEnd = 1e9
			Lighting.ExposureCompensation = 0
		elseif fbSaved then
			for k, v in pairs(fbSaved) do pcall(function() Lighting[k] = v end) end
			fbSaved = nil
		end
	end
	local fullbrightToggle = Lib.addToggleRow(page, 8, "Fullbright", false, setFullbright)

	-- One Heartbeat handles freeze (hold) and timelapse (advance). The timelapse
	-- speed ramps toward its target instead of snapping, so enabling it makes the
	-- sun (and any synced animations) visibly accelerate up to speed and coast
	-- back down when disabled. The live speed is published for the anim-sync.
	RunService.Heartbeat:Connect(function(dt)
		local target = timelapse and timelapseSpeed or 0
		if curTLSpeed < target then
			curTLSpeed = math.min(curTLSpeed + TL_ACCEL * dt, target)
		elseif curTLSpeed > target then
			curTLSpeed = math.max(curTLSpeed - TL_ACCEL * dt, target)
		end
		ctx.timelapse.enabled = curTLSpeed > 0.01
		ctx.timelapse.speed = curTLSpeed

		if curTLSpeed > 0.0001 then
			frozenClockTime = (frozenClockTime + curTLSpeed * dt) % 24
			Lighting.ClockTime = frozenClockTime
		elseif timeFrozen then
			Lighting.ClockTime = frozenClockTime
		end
	end)

	ctx.onReset(function()
		timeFrozen = false
		timelapse = false
		curTLSpeed = 0
		ctx.timelapse.enabled = false
		ctx.timelapse.speed = 0
		freezeToggle.set(false, false)
		timelapseToggle.set(false, false)
		if fbSaved then setFullbright(false) end
		fullbrightToggle.set(false, false)
		Lighting.ClockTime = 14
		frozenClockTime = 14
		Workspace.CurrentCamera.FieldOfView = 70
		local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
		if atmosphere then atmosphere.Haze = 0 end
	end)
end
