--[[
	cinematic/FreeCam.lua
	Detach-and-fly camera. Desktop: WASD/arrows + mouse look, Q/E down/up,
	Shift boost, Ctrl slow. Mobile: left thumbstick to move, drag right side
	to look, on-screen ▲/▼ and an Exit button. Toggle with P.
--]]

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace        = game:GetService("Workspace")

return function(ctx, Lib)
	local make, corner = Lib.make, Lib.corner
	local THEME = Lib.THEME
	local LocalPlayer = Players.LocalPlayer

	local page = ctx.addTab("Free Cam", 1)

	local FC = {
		enabled = false,
		camera = Workspace.CurrentCamera,
		moveSpeed = 50, minSpeed = 5, maxSpeed = 500,
		boost = 4, slow = 0.25,
		lookSens = 0.25, touchLookSens = 0.4,
		yaw = 0, pitch = 0, pos = Vector3.new(),
		keysDown = {},
		stickVector = Vector2.new(0, 0),
		touchUp = false, touchDown = false, lookTouchId = nil,
		connections = {},
	}

	local fcMobileLayer = nil
	local exitButton = nil
	local anchoredPart, wasAnchored = nil, false
	local disabledControls = nil

	-- Disable the default character controls (PlayerModule) so movement input —
	-- WASD, the mobile thumbstick, gamepad — never walks/turns your avatar while
	-- you fly. Anchoring (below) handles residual physics; this handles input.
	-- Wrapped in pcall: a few games strip or replace PlayerModule.
	local function disableCharacterControls()
		pcall(function()
			local scripts = LocalPlayer:FindFirstChild("PlayerScripts")
			local moduleScript = scripts and scripts:FindFirstChild("PlayerModule")
			if not moduleScript then return end
			local controls = require(moduleScript):GetControls()
			controls:Disable()
			disabledControls = controls
		end)
	end
	local function restoreCharacterControls()
		if disabledControls then
			pcall(function() disabledControls:Enable() end)
			disabledControls = nil
		end
	end

	local function track(conn) table.insert(FC.connections, conn) end
	local function clearConnections()
		for _, conn in ipairs(FC.connections) do
			if conn.Connected then conn:Disconnect() end
		end
		table.clear(FC.connections)
	end

	local statusLabel = Lib.addLabel(page, 1, "Status: OFF  (toggle key: P)")
	local toggleButton

	local function setButtonState()
		if FC.enabled then
			toggleButton.Text = "Exit Free Cam"
			toggleButton.BackgroundColor3 = THEME.Danger
			statusLabel.Text = "Status: ON  (toggle key: P)"
		else
			toggleButton.Text = "Enter Free Cam"
			toggleButton.BackgroundColor3 = THEME.Accent
			statusLabel.Text = "Status: OFF  (toggle key: P)"
		end
	end

	local function onRenderStep(dt)
		if not FC.enabled then return end
		local rotation = CFrame.fromEulerAnglesYXZ(FC.pitch, FC.yaw, 0)
		local move = Vector3.new()

		if FC.keysDown[Enum.KeyCode.W] or FC.keysDown[Enum.KeyCode.Up]    then move += Vector3.new(0, 0, -1) end
		if FC.keysDown[Enum.KeyCode.S] or FC.keysDown[Enum.KeyCode.Down]  then move += Vector3.new(0, 0,  1) end
		if FC.keysDown[Enum.KeyCode.A] or FC.keysDown[Enum.KeyCode.Left]  then move += Vector3.new(-1, 0, 0) end
		if FC.keysDown[Enum.KeyCode.D] or FC.keysDown[Enum.KeyCode.Right] then move += Vector3.new( 1, 0, 0) end
		if FC.keysDown[Enum.KeyCode.E] then move += Vector3.new(0,  1, 0) end
		if FC.keysDown[Enum.KeyCode.Q] then move += Vector3.new(0, -1, 0) end

		if FC.stickVector.Magnitude > 0.05 then
			move += Vector3.new(FC.stickVector.X, 0, -FC.stickVector.Y)
		end
		if FC.touchUp   then move += Vector3.new(0,  1, 0) end
		if FC.touchDown then move += Vector3.new(0, -1, 0) end

		local speed = FC.moveSpeed
		if FC.keysDown[Enum.KeyCode.LeftShift] or FC.keysDown[Enum.KeyCode.RightShift] then speed *= FC.boost end
		if FC.keysDown[Enum.KeyCode.LeftControl] or FC.keysDown[Enum.KeyCode.RightControl] then speed *= FC.slow end

		if move.Magnitude > 0 then
			FC.pos += rotation:VectorToWorldSpace(move) * speed * dt
		end
		FC.camera.CFrame = CFrame.new(FC.pos) * rotation
	end

	local function onInputChanged(input)
		if not FC.enabled then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			local d = input.Delta
			FC.yaw   = FC.yaw - d.X * FC.lookSens * 0.01
			FC.pitch = math.clamp(FC.pitch - d.Y * FC.lookSens * 0.01, -1.54, 1.54)
		elseif input.UserInputType == Enum.UserInputType.Touch
			and FC.lookTouchId and input == FC.lookTouchId then
			local d = input.Delta
			FC.yaw   = FC.yaw - d.X * FC.touchLookSens * 0.01
			FC.pitch = math.clamp(FC.pitch - d.Y * FC.touchLookSens * 0.01, -1.54, 1.54)
		end
	end

	local function onInputBegan(input, processed)
		if not FC.enabled then return end
		if input.UserInputType == Enum.UserInputType.Touch and not processed and not FC.lookTouchId then
			if input.Position.X > FC.camera.ViewportSize.X * 0.5 then
				FC.lookTouchId = input
			end
		end
	end

	local function onInputEnded(input)
		if FC.lookTouchId and input == FC.lookTouchId then FC.lookTouchId = nil end
	end

	local enterFreeCam, exitFreeCam

	function enterFreeCam()
		FC.enabled = true
		FC.camera = Workspace.CurrentCamera
		FC.pos = FC.camera.CFrame.Position
		local look = FC.camera.CFrame.LookVector
		FC.yaw   = math.atan2(-look.X, -look.Z)
		FC.pitch = math.asin(math.clamp(look.Y, -1, 1))

		FC.camera.CameraType = Enum.CameraType.Scriptable

		-- Freeze the character so WASD/physics don't walk it off while you fly.
		-- Disable input-driven movement first, then anchor against stray physics.
		disableCharacterControls()
		local char = LocalPlayer.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root then
			anchoredPart = root
			wasAnchored = root.Anchored
			root.Anchored = true
		end

		Lib.setGameUIHidden(true, ctx.gui)
		ctx.hub.Visible = false
		ctx.launcher.Visible = false
		if exitButton then exitButton.Visible = true end
		if fcMobileLayer then fcMobileLayer.Visible = true end
		setButtonState()

		if not Lib.isMobile() then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
			UserInputService.MouseIconEnabled = false
		end

		RunService:BindToRenderStep("CinematicHubFreeCam", Enum.RenderPriority.Camera.Value + 1, onRenderStep)
		track(UserInputService.InputChanged:Connect(onInputChanged))
		track(UserInputService.InputBegan:Connect(onInputBegan))
		track(UserInputService.InputEnded:Connect(onInputEnded))
	end

	function exitFreeCam()
		FC.enabled = false
		Lib.setGameUIHidden(false, ctx.gui)
		ctx.launcher.Visible = true
		if exitButton then exitButton.Visible = false end
		if fcMobileLayer then fcMobileLayer.Visible = false end
		setButtonState()

		-- Unfreeze the character (restore its previous anchored state) and hand
		-- movement back to the default controls.
		if anchoredPart then
			if anchoredPart.Parent then anchoredPart.Anchored = wasAnchored end
			anchoredPart = nil
		end
		restoreCharacterControls()

		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true

		pcall(function() RunService:UnbindFromRenderStep("CinematicHubFreeCam") end)
		clearConnections()

		FC.camera.CameraType = Enum.CameraType.Custom
		local char = LocalPlayer.Character
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		if humanoid then FC.camera.CameraSubject = humanoid end

		table.clear(FC.keysDown)
		FC.stickVector = Vector2.new(0, 0)
		FC.touchUp, FC.touchDown, FC.lookTouchId = false, false, nil
	end

	local function toggle()
		if FC.enabled then exitFreeCam() else enterFreeCam() end
	end

	-- Floating exit button shown on every platform while flying (the launcher
	-- is hidden for a clean shot, so this is the always-there way back out).
	exitButton = make("TextButton", {
		Name = "FreeCamExitButton",
		Size = UDim2.new(0, 150, 0, 40),
		Position = UDim2.new(0.5, -75, 0, 12),
		BackgroundColor3 = THEME.Danger,
		TextColor3 = Color3.new(1, 1, 1),
		Font = Lib.hubFont,
		TextSize = 15,
		Text = "Exit Free Cam",
		Visible = false,
	}, ctx.gui)
	corner(exitButton, 8)
	exitButton.Activated:Connect(toggle)

	toggleButton = make("TextButton", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = THEME.Accent,
		TextColor3 = Color3.new(0, 0, 0),
		Font = Lib.hubFont,
		TextSize = 15,
		Text = "Enter Free Cam",
		LayoutOrder = 2,
	}, page)
	corner(toggleButton, 8)
	toggleButton.Activated:Connect(toggle)
	setButtonState()

	Lib.addSlider(page, 3, "Move Speed", FC.minSpeed, FC.maxSpeed, FC.moveSpeed, function(v)
		FC.moveSpeed = v
	end)

	Lib.addLabel(page, 4,
		"Desktop: WASD/arrows move, mouse look, Q/E down/up, Shift boost, Ctrl slow.\n"
		.. "Mobile: left thumbstick to move, drag right side of screen to look.", 60)

	------------------------------------------------------------------
	-- Mobile controls
	------------------------------------------------------------------
	if Lib.isMobile() then
		local layer = make("Frame", {
			Name = "FreeCamMobileControls",
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Visible = false,
		}, ctx.gui)
		fcMobileLayer = layer

		-- Dynamic thumbstick: hidden until you touch the left half of the screen,
		-- then it spawns centred under your thumb and the knob trails it (like
		-- Roblox's own DynamicThumbstick). Lift off and it disappears again.
		local STICK_RADIUS = 60
		local stickBase = make("Frame", {
			Size = UDim2.new(0, STICK_RADIUS * 2, 0, STICK_RADIUS * 2),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, 0, 0, 0),
			BackgroundColor3 = THEME.Panel,
			BackgroundTransparency = 0.5,
			Visible = false,
		}, layer)
		corner(stickBase, STICK_RADIUS)

		local stickKnob = make("Frame", {
			Size = UDim2.new(0, 52, 0, 52),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			BackgroundColor3 = Color3.fromRGB(230, 230, 235),
			BackgroundTransparency = 0.1,
		}, stickBase)
		corner(stickKnob, 26)

		local moveTouch, stickOrigin = nil, Vector2.new()
		local function beginStick(pos)
			stickOrigin = Vector2.new(pos.X, pos.Y)
			stickBase.Position = UDim2.new(0, pos.X, 0, pos.Y)
			stickKnob.Position = UDim2.new(0.5, 0, 0.5, 0)
			stickBase.Visible = true
			FC.stickVector = Vector2.new(0, 0)
		end
		local function moveStick(pos)
			local delta = Vector2.new(pos.X, pos.Y) - stickOrigin
			if delta.Magnitude > STICK_RADIUS then delta = delta.Unit * STICK_RADIUS end
			stickKnob.Position = UDim2.new(0.5, delta.X, 0.5, delta.Y)
			FC.stickVector = Vector2.new(delta.X / STICK_RADIUS, -delta.Y / STICK_RADIUS)
		end
		local function resetStick()
			moveTouch = nil
			stickBase.Visible = false
			FC.stickVector = Vector2.new(0, 0)
		end

		-- Left half = movement (right half is claimed for look in onInputBegan).
		UserInputService.InputBegan:Connect(function(input, processed)
			if not FC.enabled or processed or moveTouch then return end
			if input.UserInputType ~= Enum.UserInputType.Touch then return end
			if input.Position.X <= FC.camera.ViewportSize.X * 0.5 then
				moveTouch = input
				beginStick(input.Position)
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if moveTouch and input == moveTouch and input.UserInputType == Enum.UserInputType.Touch then
				moveStick(input.Position)
			end
		end)
		UserInputService.InputEnded:Connect(function(input)
			if moveTouch and input == moveTouch then resetStick() end
		end)

		local function makeVButton(text, yOffset)
			local b = make("TextButton", {
				Size = UDim2.new(0, 64, 0, 64),
				Position = UDim2.new(1, -84, 1, yOffset),
				BackgroundColor3 = THEME.Panel,
				BackgroundTransparency = 0.4,
				TextColor3 = THEME.Text,
				Font = Lib.hubFont,
				TextSize = 24,
				Text = text,
			}, layer)
			corner(b, 10)
			return b
		end
		local upBtn, downBtn = makeVButton("▲", -150), makeVButton("▼", -78)
		upBtn.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.Touch then FC.touchUp = true end end)
		upBtn.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.Touch then FC.touchUp = false end end)
		downBtn.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.Touch then FC.touchDown = true end end)
		downBtn.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.Touch then FC.touchDown = false end end)

		-- (Exit button is the universal one created above, shown on all platforms.)
	end

	------------------------------------------------------------------
	-- P keybind + keyboard movement state
	------------------------------------------------------------------
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		if input.KeyCode == Enum.KeyCode.P and not processed then
			toggle()
			return
		end
		if not processed then FC.keysDown[input.KeyCode] = true end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Keyboard then
			FC.keysDown[input.KeyCode] = nil
		end
	end)

	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		if Workspace.CurrentCamera then FC.camera = Workspace.CurrentCamera end
	end)

	ctx.onReset(function()
		if FC.enabled then exitFreeCam() end
	end)
end
