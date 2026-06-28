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
	LookSensitivity = 0.25, -- mouse look sensitivity (per pixel of mouse delta)
	-- Touch look is normalised by viewport height, so this is roughly the
	-- radians of yaw/pitch produced by a full screen-height swipe. This keeps
	-- the feel identical across phones of different resolutions / DPI.
	TouchLookSensitivity = 4.0,
	ScrollSpeedStep = 10,  -- studs added/removed per mouse-wheel notch (desktop)
	StickDeadzone   = 0.08, -- ignore tiny thumbstick wobble, then ease in smoothly
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
local savedCoreGui = {}      -- [CoreGuiType] = wasEnabled
local savedTopbar = nil      -- bool, or nil if it couldn't be read
local savedAutoSelect = nil  -- bool, or nil if not captured

-- cached reference to the PlayerModule controls so we can stop the character
-- from walking while the free cam is active (and re-enable it on exit).
local playerControls = nil
-- whether the game already had character controls enabled when we entered, so
-- we don't re-enable movement the game had intentionally locked (e.g. cutscene).
local controlsWereEnabled = nil

-- guards re-entrancy if the toggle is spammed (enter/exit are synchronous).
local transitioning = false

-- assigned by buildUI on touch devices: resets all on-screen touch input
-- (thumbstick, up/down) to neutral. nil on desktop.
local resetMobileInput = nil

local connections = {}

-- Forward declarations so these stay local (they reference each other and are
-- used by handlers defined before their bodies).
local toggleFreeCam, enterFreeCam, exitFreeCam

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local function isMobile()
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

-- Fetch (and cache) the default character controls object. This is the
-- supported way to suspend movement input: while disabled, neither WASD nor
-- the default mobile thumbstick will move the avatar, and the default touch
-- controls are hidden so they can't fight our custom on-screen stick.
local function getPlayerControls()
	if playerControls then return playerControls end
	local ok, controls = pcall(function()
		local playerScripts = LocalPlayer:WaitForChild("PlayerScripts", 5)
		if not playerScripts then return nil end
		local playerModule = playerScripts:WaitForChild("PlayerModule", 5)
		if not playerModule then return nil end
		return require(playerModule):GetControls()
	end)
	if ok and controls then
		playerControls = controls
	end
	return playerControls
end

local function setCharacterMovementEnabled(allowMovement)
	local controls = getPlayerControls()
	if not controls then return end
	pcall(function()
		if allowMovement then
			controls:Enable()
		else
			controls:Disable()
		end
	end)
end

-- Best-effort read of whether character controls are currently enabled. The
-- ControlModule keeps this on its `enabled` field; if a future version renames
-- it we simply fall back to nil (treated as "was enabled") below.
local function readControlsEnabled()
	local controls = getPlayerControls()
	if not controls then return nil end
	local ok, value = pcall(function()
		return controls.enabled
	end)
	if ok and type(value) == "boolean" then
		return value
	end
	return nil
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

-- Returns (value) or nil if the core item can't be read on this client.
local function tryGetCore(name)
	local ok, value = pcall(function()
		return StarterGui:GetCore(name)
	end)
	if ok then return value end
	return nil
end

-- Every individual CoreGuiType (i.e. all of them except the catch-all `All`),
-- gathered dynamically so future additions are covered automatically.
local CORE_GUI_TYPES = {}
for _, item in ipairs(Enum.CoreGuiType:GetEnumItems()) do
	if item ~= Enum.CoreGuiType.All then
		table.insert(CORE_GUI_TYPES, item)
	end
end

------------------------------------------------------------------------
-- UI hiding (for clean cinematic shots)
------------------------------------------------------------------------
local function setAllUIVisible(visible)
	if visible then
		-- ---- RESTORE (put everything back exactly as it was) ----
		-- Player-made ScreenGuis we hid
		for gui, wasEnabled in pairs(hiddenScreenGuis) do
			if gui and gui.Parent then
				gui.Enabled = wasEnabled
			end
		end
		table.clear(hiddenScreenGuis)

		-- Roblox core UI: restore each type to the state captured at hide-time,
		-- so we never re-enable UI the game had intentionally turned off.
		for coreType, wasEnabled in pairs(savedCoreGui) do
			trySetCoreGuiEnabled(coreType, wasEnabled)
		end
		table.clear(savedCoreGui)

		-- Topbar: restore the captured value if we managed to read it, else
		-- fall back to enabled (its default) rather than guessing wrong.
		if savedTopbar ~= nil then
			trySetCore("TopbarEnabled", savedTopbar)
		else
			trySetCore("TopbarEnabled", true)
		end

		-- AutoSelect: restore the exact captured bool (avoid the and/or trap).
		if savedAutoSelect ~= nil then
			GuiService.AutoSelectGuiEnabled = savedAutoSelect
		else
			GuiService.AutoSelectGuiEnabled = true
		end

		savedTopbar, savedAutoSelect = nil, nil

		-- The freecam's own controls live in our own ScreenGui which stays
		-- visible while active, so there is nothing to re-show here.
	else
		-- ---- HIDE (snapshot first, then turn off) ----
		table.clear(hiddenScreenGuis)
		-- Every player ScreenGui except the one created by this script.
		for _, gui in ipairs(PlayerGui:GetChildren()) do
			if gui:IsA("ScreenGui") and gui.Name ~= "FreeCamGui" then
				hiddenScreenGuis[gui] = gui.Enabled
				gui.Enabled = false
			end
		end

		-- Snapshot the current core-UI state so the restore is exact.
		table.clear(savedCoreGui)
		for _, coreType in ipairs(CORE_GUI_TYPES) do
			local ok, wasEnabled = pcall(function()
				return StarterGui:GetCoreGuiEnabled(coreType)
			end)
			if ok then
				savedCoreGui[coreType] = wasEnabled
			end
		end
		savedTopbar = tryGetCore("TopbarEnabled")
		savedAutoSelect = GuiService.AutoSelectGuiEnabled

		-- Now hide everything: health, backpack, chat, player list, topbar...
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
local sliderFill, sliderKnob -- promoted so the scroll-wheel handler can sync them

-- Set the move speed (clamped) and keep the on-screen slider in sync. Used by
-- both the slider drag and the desktop scroll-wheel handler.
local function setMoveSpeed(value)
	moveSpeed = math.clamp(math.floor(value + 0.5), CONFIG.MinSpeed, CONFIG.MaxSpeed)
	local rel = (moveSpeed - CONFIG.MinSpeed) / (CONFIG.MaxSpeed - CONFIG.MinSpeed)
	if speedLabel then speedLabel.Text = ("Speed: %d"):format(moveSpeed) end
	if sliderFill then sliderFill.Size = UDim2.new(rel, 0, 1, 0) end
	if sliderKnob then sliderKnob.Position = UDim2.new(rel, 0, 0.5, 0) end
end

local function buildUI()
	gui = Instance.new("ScreenGui")
	gui.Name = "FreeCamGui"
	gui.ResetOnSpawn = false
	-- NOTE: IgnoreGuiInset = true keeps GuiObject AbsolutePosition in raw screen
	-- space, which is what lets the thumbstick / slider hit-math line up with
	-- UserInputService touch positions (which also exclude the inset). If you
	-- ever flip this, revisit updateStick() and applySliderFromX().
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

	sliderFill = Instance.new("Frame")
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

	sliderKnob = Instance.new("TextButton")
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
		local trackWidth = sliderTrack.AbsoluteSize.X
		if trackWidth <= 0 then return end -- not laid out yet; avoid divide-by-zero
		local rel = math.clamp((absX - sliderTrack.AbsolutePosition.X) / trackWidth, 0, 1)
		setMoveSpeed(CONFIG.MinSpeed + rel * (CONFIG.MaxSpeed - CONFIG.MinSpeed))
	end

	-- Drag tracking. Mouse and touch are tracked separately: the mouse drag is a
	-- simple flag (no multi-touch), while the touch drag is bound to the exact
	-- finger that grabbed the slider so a second finger (e.g. the look finger)
	-- can't hijack or prematurely release it.
	local sliderMouseDown = false
	local sliderTouchId = nil
	local function beginSliderDrag(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			sliderMouseDown = true
			applySliderFromX(input.Position.X)
		elseif input.UserInputType == Enum.UserInputType.Touch then
			sliderTouchId = input
			applySliderFromX(input.Position.X)
		end
	end
	sliderKnob.InputBegan:Connect(beginSliderDrag)
	sliderTrack.InputBegan:Connect(beginSliderDrag)
	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			if sliderMouseDown then applySliderFromX(input.Position.X) end
		elseif input.UserInputType == Enum.UserInputType.Touch then
			if sliderTouchId and input == sliderTouchId then
				applySliderFromX(input.Position.X)
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			sliderMouseDown = false
		elseif sliderTouchId and input == sliderTouchId then
			sliderTouchId = nil
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
			local radius = stickBase.AbsoluteSize.X / 2
			if radius <= 0 then return end -- not laid out yet; avoid divide-by-zero / NaN
			local center = stickBase.AbsolutePosition + stickBase.AbsoluteSize / 2
			local delta = Vector2.new(pos.X, pos.Y) - center
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

		-- Track the holding finger by id so sliding it slightly off the button
		-- doesn't drop the hold; only an actual release (global InputEnded) stops
		-- vertical movement.
		local upInputId, downInputId = nil, nil
		upBtn.InputBegan:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.Touch then
				touchUp, upInputId = true, i
			end
		end)
		downBtn.InputBegan:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.Touch then
				touchDown, downInputId = true, i
			end
		end)
		UserInputService.InputEnded:Connect(function(i)
			if upInputId and i == upInputId then
				touchUp, upInputId = false, nil
			end
			if downInputId and i == downInputId then
				touchDown, downInputId = false, nil
			end
		end)

		-- Exposed so focus-loss / exit can force every touch control back to
		-- neutral even if an InputEnded was never delivered (app backgrounded,
		-- interrupted gesture, etc.).
		resetMobileInput = function()
			resetStick()
			touchUp, touchDown = false, false
			upInputId, downInputId = nil, nil
		end
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

	elseif input.UserInputType == Enum.UserInputType.MouseWheel then
		-- Desktop speed control (the mouse is locked, so the slider isn't usable
		-- while active). input.Position.Z is +1 / -1 per notch.
		setMoveSpeed(moveSpeed + input.Position.Z * CONFIG.ScrollSpeedStep)

	elseif input.UserInputType == Enum.UserInputType.Touch then
		-- Mobile look: only the touch we claimed as the "look" finger. Delta is
		-- normalised by viewport height so the rotation a given swipe produces is
		-- the same on every screen regardless of resolution / DPI.
		if lookTouchId and input == lookTouchId and camera then
			local height = camera.ViewportSize.Y
			if height > 0 then
				local delta = input.Delta
				local scale = CONFIG.TouchLookSensitivity / height
				yaw   = yaw   - delta.X * scale
				pitch = math.clamp(pitch - delta.Y * scale, -1.54, 1.54)
			end
		end
	end
end

local function onInputBegan(input, processed)
	if not enabled or not camera then return end
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
	-- The camera can briefly be nil/destroyed during a respawn; bail this frame.
	if not camera or not camera.Parent then return end

	-- Keep yaw bounded so it never accumulates into float-precision loss.
	yaw = yaw % (2 * math.pi)

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

	-- Mobile thumbstick (planar): apply a radial deadzone, then rescale so motion
	-- eases in from zero at the deadzone edge instead of snapping to a minimum.
	local stickMag = stickVector.Magnitude
	if stickMag > CONFIG.StickDeadzone then
		local scaled = (stickMag - CONFIG.StickDeadzone) / (1 - CONFIG.StickDeadzone)
		local dir = stickVector / stickMag
		move += Vector3.new(dir.X * scaled, 0, -dir.Y * scaled)
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
		-- Clamp the magnitude to 1 so diagonal / combined input isn't faster than
		-- a single axis, while still allowing analog (partial) stick speeds < 1.
		if move.Magnitude > 1 then
			move = move.Unit
		end
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
	-- Debounce: enter/exit are synchronous, so this just guards against a double
	-- activation in the same frame leaving handlers half-connected.
	if transitioning then return end
	transitioning = true
	if enabled then
		exitFreeCam()
	else
		enterFreeCam()
	end
	transitioning = false
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

	-- Freeze the character: stop WASD / the default mobile stick from walking
	-- the avatar around while we fly the camera. Remember the prior state so we
	-- don't re-enable movement the game had intentionally locked.
	controlsWereEnabled = readControlsEnabled()
	setCharacterMovementEnabled(false)

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

	-- Give character movement back -- unless the game had it disabled before we
	-- entered (e.g. a cutscene), in which case we leave it as we found it.
	if controlsWereEnabled ~= false then
		setCharacterMovementEnabled(true)
	end
	controlsWereEnabled = nil

	-- Disconnect runtime handlers.
	pcall(function() RunService:UnbindFromRenderStep("FreeCamUpdate") end)
	clearConnections()

	-- Hand the camera back to the character. Wrapped because this can run mid
	-- respawn (e.g. auto-exit on CharacterAdded) when the camera is in flux.
	pcall(function()
		local cam = Workspace.CurrentCamera or camera
		if not cam then return end
		cam.CameraType = Enum.CameraType.Custom
		local char = LocalPlayer.Character
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		if humanoid then
			cam.CameraSubject = humanoid
		end
	end)

	-- Reset input state.
	table.clear(keysDown)
	stickVector = Vector2.new(0, 0)
	touchUp, touchDown, lookTouchId = false, false, nil
	if resetMobileInput then resetMobileInput() end
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

-- #2/#13: If focus is lost or a touch is interrupted (alt-tab, app backgrounded,
-- system gesture), InputEnded may never fire and the camera would keep drifting.
-- Force all held movement input back to neutral.
UserInputService.WindowFocusReleased:Connect(function()
	table.clear(keysDown)
	stickVector = Vector2.new(0, 0)
	touchUp, touchDown, lookTouchId = false, false, nil
	if resetMobileInput then resetMobileInput() end
end)

-- #1: If the character respawns while free cam is active, the engine swaps in a
-- fresh (Custom) camera and re-enables the default controls. Rather than fight
-- that, exit free cam cleanly so we never end up in a half-detached state.
LocalPlayer.CharacterAdded:Connect(function()
	if enabled then
		exitFreeCam()
	end
end)

print("[FreeCam] Loaded. Press P or tap 'Free Cam' to toggle. Mobile controls included.")
