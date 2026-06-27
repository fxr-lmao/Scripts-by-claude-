--[[
	FreeCam.lua
	A cross-platform free camera ("free cam") for Roblox, built for cinematic shots.

	Features
	  - Detaches the camera from your character so you can fly it anywhere.
	  - Desktop:  WASD / arrows to move, mouse to look, Q/E down/up,
	              Shift = boost, Ctrl = slow, scroll wheel = adjust speed.
	  - Mobile:   on-screen left thumbstick to move, drag the right side of
	              the screen to look, on-screen Up/Down buttons, and a
	              speed slider. Everything is touch-driven.
	  - Hides ALL UIs (your own ScreenGuis, the Roblox core/topbar, health
	              bar, backpack, chat, leaderboard, player list...) while the
	              free cam is active, then restores them when you exit — so
	              your shots are completely clean.
	  - One toggle button (and the keyboard key "P") to enter/exit.

	How to use
	  Put this as a LocalScript in StarterPlayer > StarterPlayerScripts
	  (or run it via your usual method). Tap/press the "Free Cam" button or
	  press P to toggle.

	Notes
	  - This only moves YOUR camera locally; it does not move your character
	    and is purely client-side.
	  - Toggling UI visibility uses StarterGui:SetCore and GuiService, which
	    is the supported, exploit-free way to hide core UI.
--]]

------------------------------------------------------------------------
-- Services
------------------------------------------------------------------------
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local StarterGui        = game:GetService("StarterGui")
local GuiService        = game:GetService("GuiService")
local Workspace         = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

------------------------------------------------------------------------
-- Configuration
------------------------------------------------------------------------
local CONFIG = {
	BaseSpeed      = 50,    -- studs per second at default speed
	MinSpeed       = 5,
	MaxSpeed       = 500,
	BoostMultiplier = 4,    -- hold Shift (desktop)
	SlowMultiplier  = 0.25, -- hold Ctrl  (desktop)
	LookSensitivity = 0.25, -- mouse / touch look sensitivity
	TouchLookSensitivity = 0.4,
	ToggleKey      = Enum.KeyCode.P,
	UpKey          = Enum.KeyCode.E,
	DownKey        = Enum.KeyCode.Q,
}

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
local enabled        = false
local camera         = Workspace.CurrentCamera
local moveSpeed      = CONFIG.BaseSpeed

-- camera orientation tracked as yaw / pitch so we never get roll
local yaw, pitch     = 0, 0
local camPosition    = Vector3.new()

-- desktop keyboard movement state
local keysDown = {}

-- mobile movement vector coming from the on-screen thumbstick (-1..1 each axis)
local stickVector = Vector2.new(0, 0)
local touchUp, touchDown = false, false

-- saved UI states so we can restore exactly what we hid
local hiddenScreenGuis = {}
local savedCoreGui = {}

local connections = {}

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local function isMobile()
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

local function track(conn)
	table.insert(connections, conn)
	return conn
end

local function clearConnections()
	for _, conn in ipairs(connections) do
		if conn.Connected then conn:Disconnect() end
	end
	table.clear(connections)
end

-- Safe wrapper because SetCore items may not be registered yet on join.
local function trySetCore(name, value)
	local ok = pcall(function()
		StarterGui:SetCore(name, value)
	end)
	return ok
end

local function trySetCoreGuiEnabled(coreGuiType, enabledFlag)
	pcall(function()
		StarterGui:SetCoreGuiEnabled(coreGuiType, enabledFlag)
	end)
end

------------------------------------------------------------------------
-- UI hiding (for clean cinematic shots)
------------------------------------------------------------------------
local function setAllUIVisible(visible)
	if visible then
		-- ---- RESTORE ----
		-- Player-made ScreenGuis we hid
		for gui, wasEnabled in pairs(hiddenScreenGuis) do
			if gui and gui.Parent then
				gui.Enabled = wasEnabled
			end
		end
		table.clear(hiddenScreenGuis)

		-- Roblox core UI
		trySetCoreGuiEnabled(Enum.CoreGuiType.All, true)
		trySetCore("TopbarEnabled", true)
		GuiService.AutoSelectGuiEnabled = true

		-- Re-show the freecam's own controls (they live in our own ScreenGui
		-- which we keep visible while active, so nothing to do here).
	else
		-- ---- HIDE ----
		table.clear(hiddenScreenGuis)
		-- Every player ScreenGui except the one created by this script.
		for _, gui in ipairs(PlayerGui:GetChildren()) do
			if gui:IsA("ScreenGui") and gui.Name ~= "FreeCamGui" then
				hiddenScreenGuis[gui] = gui.Enabled
				gui.Enabled = false
			end
		end

		-- Roblox core UI: health, backpack, chat, player list, topbar...
		trySetCoreGuiEnabled(Enum.CoreGuiType.All, false)
		trySetCore("TopbarEnabled", false)
		GuiService.AutoSelectGuiEnabled = false
	end
end

------------------------------------------------------------------------
-- On-screen UI (toggle button + mobile controls + speed slider)
------------------------------------------------------------------------
local gui          -- ScreenGui
local toggleButton -- always-visible toggle
local mobileControls -- container shown only while active on touch devices
local speedLabel

local function buildUI()
	gui = Instance.new("ScreenGui")
	gui.Name = "FreeCamGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 1000
	gui.Parent = PlayerGui

	-- ---- Toggle button (always visible) ----
	toggleButton = Instance.new("TextButton")
	toggleButton.Name = "ToggleButton"
	toggleButton.Size = UDim2.new(0, 130, 0, 44)
	toggleButton.Position = UDim2.new(1, -140, 0, 10)
	toggleButton.AnchorPoint = Vector2.new(0, 0)
	toggleButton.BackgroundColor3 = Color3.fromRGB(30, 30, 38)
	toggleButton.BackgroundTransparency = 0.2
	toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	toggleButton.Font = Enum.Font.GothamBold
	toggleButton.TextSize = 16
	toggleButton.Text = "Free Cam"
	toggleButton.AutoButtonColor = true
	toggleButton.Parent = gui
	local tbCorner = Instance.new("UICorner")
	tbCorner.CornerRadius = UDim.new(0, 8)
	tbCorner.Parent = toggleButton

	-- ---- Mobile / active controls container ----
	mobileControls = Instance.new("Frame")
	mobileControls.Name = "MobileControls"
	mobileControls.Size = UDim2.new(1, 0, 1, 0)
	mobileControls.BackgroundTransparency = 1
	mobileControls.Visible = false
	mobileControls.Parent = gui

	-- Speed readout + slider (works on every platform)
	local speedFrame = Instance.new("Frame")
	speedFrame.Name = "SpeedFrame"
	speedFrame.Size = UDim2.new(0, 200, 0, 54)
	speedFrame.Position = UDim2.new(0.5, -100, 0, 10)
	speedFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
	speedFrame.BackgroundTransparency = 0.35
	speedFrame.Parent = mobileControls
	local sfCorner = Instance.new("UICorner")
	sfCorner.CornerRadius = UDim.new(0, 8)
	sfCorner.Parent = speedFrame

	speedLabel = Instance.new("TextLabel")
	speedLabel.Size = UDim2.new(1, 0, 0, 22)
	speedLabel.Position = UDim2.new(0, 0, 0, 4)
	speedLabel.BackgroundTransparency = 1
	speedLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	speedLabel.Font = Enum.Font.Gotham
	speedLabel.TextSize = 14
	speedLabel.Text = ("Speed: %d"):format(moveSpeed)
	speedLabel.Parent = speedFrame

	local sliderTrack = Instance.new("Frame")
	sliderTrack.Name = "SliderTrack"
	sliderTrack.Size = UDim2.new(1, -20, 0, 6)
	sliderTrack.Position = UDim2.new(0, 10, 0, 36)
	sliderTrack.BackgroundColor3 = Color3.fromRGB(80, 80, 90)
	sliderTrack.Parent = speedFrame
	local stCorner = Instance.new("UICorner")
	stCorner.CornerRadius = UDim.new(1, 0)
	stCorner.Parent = sliderTrack

	local sliderFill = Instance.new("Frame")
	sliderFill.Name = "SliderFill"
	sliderFill.BackgroundColor3 = Color3.fromRGB(90, 170, 255)
	sliderFill.BorderSizePixel = 0
	local function speedAlpha()
		return (moveSpeed - CONFIG.MinSpeed) / (CONFIG.MaxSpeed - CONFIG.MinSpeed)
	end
	sliderFill.Size = UDim2.new(speedAlpha(), 0, 1, 0)
	sliderFill.Parent = sliderTrack
	local sfillCorner = Instance.new("UICorner")
	sfillCorner.CornerRadius = UDim.new(1, 0)
	sfillCorner.Parent = sliderFill

	local sliderKnob = Instance.new("TextButton")
	sliderKnob.Name = "SliderKnob"
	sliderKnob.Size = UDim2.new(0, 18, 0, 18)
	sliderKnob.AnchorPoint = Vector2.new(0.5, 0.5)
	sliderKnob.Position = UDim2.new(speedAlpha(), 0, 0.5, 0)
	sliderKnob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	sliderKnob.Text = ""
	sliderKnob.AutoButtonColor = false
	sliderKnob.Parent = sliderTrack
	local knobCorner = Instance.new("UICorner")
	knobCorner.CornerRadius = UDim.new(1, 0)
	knobCorner.Parent = sliderKnob

	local function applySliderFromX(absX)
		local rel = math.clamp((absX - sliderTrack.AbsolutePosition.X) / sliderTrack.AbsoluteSize.X, 0, 1)
		moveSpeed = math.floor(CONFIG.MinSpeed + rel * (CONFIG.MaxSpeed - CONFIG.MinSpeed))
		speedLabel.Text = ("Speed: %d"):format(moveSpeed)
		sliderFill.Size = UDim2.new(rel, 0, 1, 0)
		sliderKnob.Position = UDim2.new(rel, 0, 0.5, 0)
	end

	local draggingSlider = false
	sliderKnob.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			draggingSlider = true
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if draggingSlider and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			applySliderFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			draggingSlider = false
		end
	end)
	sliderTrack.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			draggingSlider = true
			applySliderFromX(input.Position.X)
		end
	end)

	---------------------------------------------------------------
	-- Mobile-only: thumbstick + up/down buttons
	---------------------------------------------------------------
	if isMobile() then
		-- Left thumbstick for planar movement
		local stickBase = Instance.new("Frame")
		stickBase.Name = "StickBase"
		stickBase.Size = UDim2.new(0, 120, 0, 120)
		stickBase.Position = UDim2.new(0, 40, 1, -160)
		stickBase.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
		stickBase.BackgroundTransparency = 0.5
		stickBase.Parent = mobileControls
		local sbCorner = Instance.new("UICorner")
		sbCorner.CornerRadius = UDim.new(1, 0)
		sbCorner.Parent = stickBase

		local stickKnob = Instance.new("Frame")
		stickKnob.Name = "StickKnob"
		stickKnob.Size = UDim2.new(0, 52, 0, 52)
		stickKnob.AnchorPoint = Vector2.new(0.5, 0.5)
		stickKnob.Position = UDim2.new(0.5, 0, 0.5, 0)
		stickKnob.BackgroundColor3 = Color3.fromRGB(230, 230, 235)
		stickKnob.BackgroundTransparency = 0.1
		stickKnob.Parent = stickBase
		local skCorner = Instance.new("UICorner")
		skCorner.CornerRadius = UDim.new(1, 0)
		skCorner.Parent = stickKnob

		local stickInputId = nil
		local function updateStick(pos)
			local center = stickBase.AbsolutePosition + stickBase.AbsoluteSize / 2
			local delta = Vector2.new(pos.X, pos.Y) - center
			local radius = stickBase.AbsoluteSize.X / 2
			if delta.Magnitude > radius then
				delta = delta.Unit * radius
			end
			stickKnob.Position = UDim2.new(0.5, delta.X, 0.5, delta.Y)
			-- X = strafe (right positive), Y = forward (up on screen = forward)
			stickVector = Vector2.new(delta.X / radius, -delta.Y / radius)
		end
		local function resetStick()
			stickInputId = nil
			stickVector = Vector2.new(0, 0)
			stickKnob.Position = UDim2.new(0.5, 0, 0.5, 0)
		end

		stickBase.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				stickInputId = input
				updateStick(input.Position)
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if stickInputId and input == stickInputId
				and input.UserInputType == Enum.UserInputType.Touch then
				updateStick(input.Position)
			end
		end)
		UserInputService.InputEnded:Connect(function(input)
			if stickInputId and input == stickInputId then
				resetStick()
			end
		end)

		-- Up / Down buttons (vertical movement)
		local function makeVButton(name, text, yOffset)
			local b = Instance.new("TextButton")
			b.Name = name
			b.Size = UDim2.new(0, 64, 0, 64)
			b.Position = UDim2.new(1, -84, 1, yOffset)
			b.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
			b.BackgroundTransparency = 0.4
			b.TextColor3 = Color3.fromRGB(255, 255, 255)
			b.Font = Enum.Font.GothamBold
			b.TextSize = 24
			b.Text = text
			b.AutoButtonColor = true
			b.Parent = mobileControls
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, 10)
			c.Parent = b
			return b
		end

		local upBtn   = makeVButton("UpButton",   "▲", -150)
		local downBtn = makeVButton("DownButton", "▼", -78)

		upBtn.InputBegan:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.Touch then touchUp = true end
		end)
		upBtn.InputEnded:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.Touch then touchUp = false end
		end)
		downBtn.InputBegan:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.Touch then touchDown = true end
		end)
		downBtn.InputEnded:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.Touch then touchDown = false end
		end)
	end
end

------------------------------------------------------------------------
-- Look handling
------------------------------------------------------------------------
-- Right-side drag rotates the camera on mobile; mouse delta does it on desktop.
local lookTouchId = nil

local function onInputChanged(input, processed)
	if not enabled then return end

	if input.UserInputType == Enum.UserInputType.MouseMovement then
		-- Desktop look (mouse is locked to centre while active)
		local delta = input.Delta
		yaw   = yaw   - delta.X * CONFIG.LookSensitivity * 0.01
		pitch = math.clamp(pitch - delta.Y * CONFIG.LookSensitivity * 0.01, -1.54, 1.54)

	elseif input.UserInputType == Enum.UserInputType.Touch then
		-- Mobile look: only the touch we claimed as the "look" finger
		if lookTouchId and input == lookTouchId then
			local delta = input.Delta
			yaw   = yaw   - delta.X * CONFIG.TouchLookSensitivity * 0.01
			pitch = math.clamp(pitch - delta.Y * CONFIG.TouchLookSensitivity * 0.01, -1.54, 1.54)
		end
	end
end

local function onInputBegan(input, processed)
	if not enabled then return end
	-- Claim a right-side touch (not over UI) as the look finger.
	if input.UserInputType == Enum.UserInputType.Touch and not processed and not lookTouchId then
		if input.Position.X > camera.ViewportSize.X * 0.5 then
			lookTouchId = input
		end
	end
end

local function onInputEnded(input)
	if lookTouchId and input == lookTouchId then
		lookTouchId = nil
	end
end

------------------------------------------------------------------------
-- Keyboard (desktop)
------------------------------------------------------------------------
local function onKeyDown(input, processed)
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

	if input.KeyCode == CONFIG.ToggleKey then
		toggleFreeCam()
		return
	end
	if processed then return end
	keysDown[input.KeyCode] = true
end

local function onKeyUp(input)
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	keysDown[input.KeyCode] = nil
end

------------------------------------------------------------------------
-- Per-frame camera update
------------------------------------------------------------------------
local function onRenderStep(dt)
	if not enabled then return end

	-- Build orientation
	local rotation = CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)

	-- Gather movement input
	local move = Vector3.new()

	-- Desktop keys
	if keysDown[Enum.KeyCode.W] or keysDown[Enum.KeyCode.Up]    then move += Vector3.new(0, 0, -1) end
	if keysDown[Enum.KeyCode.S] or keysDown[Enum.KeyCode.Down]  then move += Vector3.new(0, 0,  1) end
	if keysDown[Enum.KeyCode.A] or keysDown[Enum.KeyCode.Left]  then move += Vector3.new(-1, 0, 0) end
	if keysDown[Enum.KeyCode.D] or keysDown[Enum.KeyCode.Right] then move += Vector3.new( 1, 0, 0) end
	if keysDown[CONFIG.UpKey]   then move += Vector3.new(0,  1, 0) end
	if keysDown[CONFIG.DownKey] then move += Vector3.new(0, -1, 0) end

	-- Mobile thumbstick (planar) + up/down buttons
	if stickVector.Magnitude > 0.05 then
		move += Vector3.new(stickVector.X, 0, -stickVector.Y)
	end
	if touchUp   then move += Vector3.new(0,  1, 0) end
	if touchDown then move += Vector3.new(0, -1, 0) end

	-- Speed modifiers (desktop)
	local speed = moveSpeed
	if keysDown[Enum.KeyCode.LeftShift] or keysDown[Enum.KeyCode.RightShift] then
		speed *= CONFIG.BoostMultiplier
	end
	if keysDown[Enum.KeyCode.LeftControl] or keysDown[Enum.KeyCode.RightControl] then
		speed *= CONFIG.SlowMultiplier
	end

	if move.Magnitude > 0 then
		-- Move relative to where the camera looks, so W flies toward the crosshair.
		local worldMove = rotation:VectorToWorldSpace(move)
		camPosition += worldMove * speed * dt
	end

	camera.CFrame = CFrame.new(camPosition) * rotation
end

------------------------------------------------------------------------
-- Enter / exit free cam
------------------------------------------------------------------------
function toggleFreeCam()
	if enabled then
		exitFreeCam()
	else
		enterFreeCam()
	end
end

function enterFreeCam()
	enabled = true
	camera = Workspace.CurrentCamera

	-- Seed position/orientation from current camera so it doesn't jump.
	camPosition = camera.CFrame.Position
	local look = camera.CFrame.LookVector
	yaw   = math.atan2(-look.X, -look.Z)
	pitch = math.asin(math.clamp(look.Y, -1, 1))

	camera.CameraType = Enum.CameraType.Scriptable

	-- Hide everything for the clean shot.
	setAllUIVisible(false)
	mobileControls.Visible = true
	toggleButton.Text = "Exit Cam"
	toggleButton.BackgroundColor3 = Color3.fromRGB(120, 40, 40)

	-- Lock & hide the mouse on desktop for free-look.
	if not isMobile() then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
	end

	-- Connect runtime handlers. (BindToRenderStep returns nil, so it is not tracked.)
	RunService:BindToRenderStep("FreeCamUpdate", Enum.RenderPriority.Camera.Value + 1, onRenderStep)
	track(UserInputService.InputChanged:Connect(onInputChanged))
	track(UserInputService.InputBegan:Connect(onInputBegan))
	track(UserInputService.InputEnded:Connect(onInputEnded))
end

function exitFreeCam()
	enabled = false

	-- Restore UI.
	setAllUIVisible(true)
	mobileControls.Visible = false
	toggleButton.Text = "Free Cam"
	toggleButton.BackgroundColor3 = Color3.fromRGB(30, 30, 38)

	-- Restore mouse.
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true

	-- Disconnect runtime handlers.
	pcall(function() RunService:UnbindFromRenderStep("FreeCamUpdate") end)
	clearConnections()

	-- Hand the camera back to the character.
	camera.CameraType = Enum.CameraType.Custom
	local char = LocalPlayer.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end

	-- Reset input state.
	table.clear(keysDown)
	stickVector = Vector2.new(0, 0)
	touchUp, touchDown, lookTouchId = false, false, nil
end

------------------------------------------------------------------------
-- Bootstrap
------------------------------------------------------------------------
buildUI()

-- Toggle via the on-screen button.
toggleButton.Activated:Connect(toggleFreeCam)

-- Toggle via keyboard (always listening, even when not active).
UserInputService.InputBegan:Connect(onKeyDown)
UserInputService.InputEnded:Connect(onKeyUp)

-- Keep CurrentCamera reference fresh if it changes.
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	if Workspace.CurrentCamera then
		camera = Workspace.CurrentCamera
	end
end)

print("[FreeCam] Loaded. Press P or tap 'Free Cam' to toggle. Mobile controls included.")
