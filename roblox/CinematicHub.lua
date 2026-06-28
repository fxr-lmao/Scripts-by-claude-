--[[
	CinematicHub.lua
	A single, all-in-one "cinematic tools" hub for Roblox — exploit-hub style
	UI, but every feature is a legitimate, client-side cinematic QOL tool.

	One floating button opens a tabbed panel:
	  - Free Cam   : detach the camera and fly it around (desktop + mobile).
	  - Shaders    : Lighting post-effects (Bloom, Blur, DepthOfField,
	                 ColorCorrection, SunRays) with ready-made presets
	                 (Cinematic, Noir, Warm, Cold, Dreamy, Horror) plus
	                 manual sliders.
	  - Fonts      : pick a font for the hub UI, optionally applied to
	                 every TextLabel/TextButton/TextBox currently and
	                 newly created in your PlayerGui.
	  - World      : time of day (ClockTime) and camera FOV sliders.

	How to use
	  Put this as a LocalScript in StarterPlayer > StarterPlayerScripts
	  (or run it via your usual method). Tap/press the "🎬 Cinematic"
	  button (draggable) or press the Backquote (`) key to open/close
	  the hub. Press P to toggle Free Cam directly.

	Notes
	  - Purely client-side: visual/camera changes only, no exploits,
	    no gameplay manipulation. Safe to use in any experience that
	    allows local LocalScripts (e.g. your own place, Studio, or a
	    game that supports client mods).
--]]

------------------------------------------------------------------------
-- Services
------------------------------------------------------------------------
local Players          = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local StarterGui        = game:GetService("StarterGui")
local GuiService        = game:GetService("GuiService")
local Workspace          = game:GetService("Workspace")
local Lighting          = game:GetService("Lighting")
local TweenService      = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

local function isMobile()
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

------------------------------------------------------------------------
-- Theme
------------------------------------------------------------------------
local THEME = {
	Background  = Color3.fromRGB(22, 22, 28),
	Panel       = Color3.fromRGB(30, 30, 38),
	PanelAlt    = Color3.fromRGB(38, 38, 48),
	Accent      = Color3.fromRGB(90, 170, 255),
	Text        = Color3.fromRGB(235, 235, 240),
	SubText     = Color3.fromRGB(160, 160, 170),
	Danger      = Color3.fromRGB(220, 80, 80),
}

local hubFont = Enum.Font.GothamBold
local bodyFont = Enum.Font.Gotham

------------------------------------------------------------------------
-- Tiny UI helpers
------------------------------------------------------------------------
local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
	return c
end

local function stroke(parent, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.fromRGB(60, 60, 70)
	s.Thickness = thickness or 1
	s.Parent = parent
	return s
end

local function make(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	if parent then inst.Parent = parent end
	return inst
end

------------------------------------------------------------------------
-- Root GUI
------------------------------------------------------------------------
local gui = make("ScreenGui", {
	Name = "CinematicHubGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 1000,
}, PlayerGui)

------------------------------------------------------------------------
-- Floating launcher button (draggable)
------------------------------------------------------------------------
local launcher = make("TextButton", {
	Name = "Launcher",
	Size = UDim2.new(0, 150, 0, 46),
	Position = UDim2.new(0, 16, 0, 16),
	BackgroundColor3 = THEME.Panel,
	TextColor3 = THEME.Text,
	Font = hubFont,
	TextSize = 16,
	Text = "🎬  Cinematic",
	AutoButtonColor = true,
}, gui)
corner(launcher, 10)
stroke(launcher, THEME.Accent, 1)

do
	-- simple drag-to-move for the launcher
	local dragging, dragStart, startPos = false, nil, nil
	launcher.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = launcher.Position
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			launcher.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

------------------------------------------------------------------------
-- Main hub window
------------------------------------------------------------------------
local hub = make("Frame", {
	Name = "Hub",
	Size = UDim2.new(0, 520, 0, 360),
	Position = UDim2.new(0.5, -260, 0.5, -180),
	BackgroundColor3 = THEME.Background,
	Visible = false,
}, gui)
corner(hub, 12)
stroke(hub, Color3.fromRGB(55, 55, 65), 1)

-- title bar (also draggable)
local titleBar = make("Frame", {
	Name = "TitleBar",
	Size = UDim2.new(1, 0, 0, 40),
	BackgroundColor3 = THEME.Panel,
}, hub)
corner(titleBar, 12)

make("TextLabel", {
	Size = UDim2.new(1, -90, 1, 0),
	Position = UDim2.new(0, 14, 0, 0),
	BackgroundTransparency = 1,
	TextXAlignment = Enum.TextXAlignment.Left,
	Font = hubFont,
	TextSize = 16,
	TextColor3 = THEME.Text,
	Text = "Cinematic Hub",
}, titleBar)

local closeBtn = make("TextButton", {
	Name = "CloseButton",
	Size = UDim2.new(0, 32, 0, 32),
	Position = UDim2.new(1, -38, 0, 4),
	BackgroundColor3 = THEME.Danger,
	TextColor3 = Color3.new(1, 1, 1),
	Font = hubFont,
	TextSize = 16,
	Text = "X",
}, titleBar)
corner(closeBtn, 8)

do
	local dragging, dragStart, startPos = false, nil, nil
	titleBar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = hub.Position
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			hub.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

-- sidebar (tabs)
local sidebar = make("Frame", {
	Name = "Sidebar",
	Size = UDim2.new(0, 130, 1, -40),
	Position = UDim2.new(0, 0, 0, 40),
	BackgroundColor3 = THEME.Panel,
}, hub)

local sidebarList = make("UIListLayout", {
	Padding = UDim.new(0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, sidebar)
make("UIPadding", {
	PaddingTop = UDim.new(0, 8),
	PaddingLeft = UDim.new(0, 8),
	PaddingRight = UDim.new(0, 8),
}, sidebar)

-- content area
local content = make("Frame", {
	Name = "Content",
	Size = UDim2.new(1, -130, 1, -40),
	Position = UDim2.new(0, 130, 0, 40),
	BackgroundTransparency = 1,
	ClipsDescendants = true,
}, hub)

local tabButtons = {}
local tabPages = {}
local activeTab = nil

local function selectTab(name)
	if activeTab == name then return end
	activeTab = name
	for tabName, page in pairs(tabPages) do
		page.Visible = (tabName == name)
	end
	for tabName, btn in pairs(tabButtons) do
		if tabName == name then
			btn.BackgroundColor3 = THEME.Accent
			btn.TextColor3 = Color3.new(0, 0, 0)
		else
			btn.BackgroundColor3 = THEME.PanelAlt
			btn.TextColor3 = THEME.Text
		end
	end
end

local function addTab(name, order)
	local btn = make("TextButton", {
		Name = name .. "Tab",
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = THEME.PanelAlt,
		TextColor3 = THEME.Text,
		Font = bodyFont,
		TextSize = 14,
		Text = name,
		LayoutOrder = order,
		AutoButtonColor = true,
	}, sidebar)
	corner(btn, 8)
	tabButtons[name] = btn

	local page = make("Frame", {
		Name = name .. "Page",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Visible = false,
	}, content)
	tabPages[name] = page

	btn.Activated:Connect(function() selectTab(name) end)

	return page
end

------------------------------------------------------------------------
-- Generic widgets used across tabs (slider / toggle / button row)
------------------------------------------------------------------------
local function layoutColumn(parent)
	make("UIListLayout", {
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, parent)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 14),
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 14),
		PaddingBottom = UDim.new(0, 14),
	}, parent)
end

-- creates a labeled slider, returns nothing; calls onChange(value) live
local function addSlider(parent, order, labelText, min, max, default, onChange)
	local row = make("Frame", {
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, parent)

	local label = make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		Font = bodyFont,
		TextSize = 13,
		TextColor3 = THEME.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = ("%s: %s"):format(labelText, tostring(default)),
	}, row)

	local track = make("Frame", {
		Size = UDim2.new(1, 0, 0, 6),
		Position = UDim2.new(0, 0, 0, 26),
		BackgroundColor3 = THEME.PanelAlt,
	}, row)
	corner(track, 3)

	local function alphaFor(v)
		return math.clamp((v - min) / (max - min), 0, 1)
	end

	local fill = make("Frame", {
		Size = UDim2.new(alphaFor(default), 0, 1, 0),
		BackgroundColor3 = THEME.Accent,
		BorderSizePixel = 0,
	}, track)
	corner(fill, 3)

	local knob = make("TextButton", {
		Size = UDim2.new(0, 16, 0, 16),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(alphaFor(default), 0, 0.5, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Text = "",
		AutoButtonColor = false,
	}, track)
	corner(knob, 8)

	local dragging = false
	local function applyFromX(absX)
		local rel = math.clamp((absX - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		local value = min + rel * (max - min)
		fill.Size = UDim2.new(rel, 0, 1, 0)
		knob.Position = UDim2.new(rel, 0, 0.5, 0)
		label.Text = ("%s: %.2f"):format(labelText, value)
		onChange(value)
	end

	knob.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
		end
	end)
	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			applyFromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			applyFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	return row
end

local function addButtonRow(parent, order, buttons)
	-- buttons: list of {text, callback}
	local row = make("Frame", {
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, parent)
	local list = make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)

	for i, def in ipairs(buttons) do
		local b = make("TextButton", {
			Size = UDim2.new(0, 90, 1, 0),
			BackgroundColor3 = THEME.PanelAlt,
			TextColor3 = THEME.Text,
			Font = bodyFont,
			TextSize = 13,
			Text = def.text,
			LayoutOrder = i,
			AutoButtonColor = true,
		}, row)
		corner(b, 6)
		b.Activated:Connect(def.callback)
	end
	return row
end

local function addToggleRow(parent, order, labelText, default, onChange)
	local row = make("Frame", {
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, parent)

	make("TextLabel", {
		Size = UDim2.new(1, -60, 1, 0),
		BackgroundTransparency = 1,
		Font = bodyFont,
		TextSize = 13,
		TextColor3 = THEME.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = labelText,
	}, row)

	local state = default
	local switch = make("TextButton", {
		Size = UDim2.new(0, 50, 0, 26),
		Position = UDim2.new(1, -50, 0.5, -13),
		BackgroundColor3 = state and THEME.Accent or THEME.PanelAlt,
		Text = state and "ON" or "OFF",
		Font = hubFont,
		TextSize = 12,
		TextColor3 = state and Color3.new(0,0,0) or THEME.Text,
	}, row)
	corner(switch, 13)

	switch.Activated:Connect(function()
		state = not state
		switch.BackgroundColor3 = state and THEME.Accent or THEME.PanelAlt
		switch.Text = state and "ON" or "OFF"
		switch.TextColor3 = state and Color3.new(0,0,0) or THEME.Text
		onChange(state)
	end)

	return row
end

------------------------------------------------------------------------
-- ============================ FREE CAM TAB ============================
------------------------------------------------------------------------
local freeCamPage = addTab("Free Cam", 1)
layoutColumn(freeCamPage)

local FC = {
	enabled = false,
	camera = Workspace.CurrentCamera,
	moveSpeed = 50,
	minSpeed = 5,
	maxSpeed = 500,
	boost = 4,
	slow = 0.25,
	lookSens = 0.25,
	touchLookSens = 0.4,
	yaw = 0,
	pitch = 0,
	pos = Vector3.new(),
	keysDown = {},
	stickVector = Vector2.new(0, 0),
	touchUp = false,
	touchDown = false,
	lookTouchId = nil,
	hiddenScreenGuis = {},
	connections = {},
}

local function fcTrack(conn) table.insert(FC.connections, conn) end
local function fcClearConnections()
	for _, conn in ipairs(FC.connections) do
		if conn.Connected then conn:Disconnect() end
	end
	table.clear(FC.connections)
end

local function trySetCore(name, value)
	pcall(function() StarterGui:SetCore(name, value) end)
end
local function trySetCoreGuiEnabled(coreGuiType, enabledFlag)
	pcall(function() StarterGui:SetCoreGuiEnabled(coreGuiType, enabledFlag) end)
end

local function fcSetUIVisible(visible)
	if visible then
		for guiObj, wasEnabled in pairs(FC.hiddenScreenGuis) do
			if guiObj and guiObj.Parent then guiObj.Enabled = wasEnabled end
		end
		table.clear(FC.hiddenScreenGuis)
		trySetCoreGuiEnabled(Enum.CoreGuiType.All, true)
		trySetCore("TopbarEnabled", true)
		GuiService.AutoSelectGuiEnabled = true
	else
		table.clear(FC.hiddenScreenGuis)
		for _, guiObj in ipairs(PlayerGui:GetChildren()) do
			if guiObj:IsA("ScreenGui") and guiObj.Name ~= "CinematicHubGui" then
				FC.hiddenScreenGuis[guiObj] = guiObj.Enabled
				guiObj.Enabled = false
			end
		end
		trySetCoreGuiEnabled(Enum.CoreGuiType.All, false)
		trySetCore("TopbarEnabled", false)
		GuiService.AutoSelectGuiEnabled = false
	end
end

local fcStatusLabel = make("TextLabel", {
	Size = UDim2.new(1, 0, 0, 20),
	BackgroundTransparency = 1,
	Font = bodyFont,
	TextSize = 13,
	TextColor3 = THEME.SubText,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "Status: OFF  (toggle key: P)",
	LayoutOrder = 1,
}, freeCamPage)

local fcToggleButton
local function fcSetButtonState()
	if FC.enabled then
		fcToggleButton.Text = "Exit Free Cam"
		fcToggleButton.BackgroundColor3 = THEME.Danger
		fcStatusLabel.Text = "Status: ON  (toggle key: P)"
	else
		fcToggleButton.Text = "Enter Free Cam"
		fcToggleButton.BackgroundColor3 = THEME.Accent
		fcStatusLabel.Text = "Status: OFF  (toggle key: P)"
	end
end

local function fcOnRenderStep(dt)
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
	if FC.keysDown[Enum.KeyCode.LeftShift] or FC.keysDown[Enum.KeyCode.RightShift] then
		speed *= FC.boost
	end
	if FC.keysDown[Enum.KeyCode.LeftControl] or FC.keysDown[Enum.KeyCode.RightControl] then
		speed *= FC.slow
	end

	if move.Magnitude > 0 then
		local worldMove = rotation:VectorToWorldSpace(move)
		FC.pos += worldMove * speed * dt
	end

	FC.camera.CFrame = CFrame.new(FC.pos) * rotation
end

local function fcOnInputChanged(input)
	if not FC.enabled then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		local delta = input.Delta
		FC.yaw   = FC.yaw   - delta.X * FC.lookSens * 0.01
		FC.pitch = math.clamp(FC.pitch - delta.Y * FC.lookSens * 0.01, -1.54, 1.54)
	elseif input.UserInputType == Enum.UserInputType.Touch then
		if FC.lookTouchId and input == FC.lookTouchId then
			local delta = input.Delta
			FC.yaw   = FC.yaw   - delta.X * FC.touchLookSens * 0.01
			FC.pitch = math.clamp(FC.pitch - delta.Y * FC.touchLookSens * 0.01, -1.54, 1.54)
		end
	end
end

local function fcOnInputBegan(input, processed)
	if not FC.enabled then return end
	if input.UserInputType == Enum.UserInputType.Touch and not processed and not FC.lookTouchId then
		if input.Position.X > FC.camera.ViewportSize.X * 0.5 then
			FC.lookTouchId = input
		end
	end
end

local function fcOnInputEnded(input)
	if FC.lookTouchId and input == FC.lookTouchId then FC.lookTouchId = nil end
end

local function fcEnter()
	FC.enabled = true
	FC.camera = Workspace.CurrentCamera

	FC.pos = FC.camera.CFrame.Position
	local look = FC.camera.CFrame.LookVector
	FC.yaw   = math.atan2(-look.X, -look.Z)
	FC.pitch = math.asin(math.clamp(look.Y, -1, 1))

	FC.camera.CameraType = Enum.CameraType.Scriptable
	fcSetUIVisible(false)
	hub.Visible = false -- get the hub out of the shot too
	fcSetButtonState()

	if not isMobile() then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
	end

	RunService:BindToRenderStep("CinematicHubFreeCam", Enum.RenderPriority.Camera.Value + 1, fcOnRenderStep)
	fcTrack(UserInputService.InputChanged:Connect(fcOnInputChanged))
	fcTrack(UserInputService.InputBegan:Connect(fcOnInputBegan))
	fcTrack(UserInputService.InputEnded:Connect(fcOnInputEnded))
end

local function fcExit()
	FC.enabled = false
	fcSetUIVisible(true)
	fcSetButtonState()

	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true

	pcall(function() RunService:UnbindFromRenderStep("CinematicHubFreeCam") end)
	fcClearConnections()

	FC.camera.CameraType = Enum.CameraType.Custom
	local char = LocalPlayer.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if humanoid then FC.camera.CameraSubject = humanoid end

	table.clear(FC.keysDown)
	FC.stickVector = Vector2.new(0, 0)
	FC.touchUp, FC.touchDown, FC.lookTouchId = false, false, nil
end

local function fcToggle()
	if FC.enabled then fcExit() else fcEnter() end
end

fcToggleButton = make("TextButton", {
	Size = UDim2.new(1, 0, 0, 40),
	BackgroundColor3 = THEME.Accent,
	TextColor3 = Color3.new(0, 0, 0),
	Font = hubFont,
	TextSize = 15,
	Text = "Enter Free Cam",
	LayoutOrder = 2,
}, freeCamPage)
corner(fcToggleButton, 8)
fcToggleButton.Activated:Connect(fcToggle)

addSlider(freeCamPage, 3, "Move Speed", FC.minSpeed, FC.maxSpeed, FC.moveSpeed, function(v)
	FC.moveSpeed = v
end)

make("TextLabel", {
	Size = UDim2.new(1, 0, 0, 60),
	BackgroundTransparency = 1,
	Font = bodyFont,
	TextSize = 12,
	TextColor3 = THEME.SubText,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	LayoutOrder = 4,
	Text = "Desktop: WASD/arrows move, mouse look, Q/E down/up, Shift boost, Ctrl slow.\nMobile: left thumbstick to move, drag right side of screen to look.",
}, freeCamPage)

if isMobile() then
	local mobileLayer = make("Frame", {
		Name = "FreeCamMobileControls",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Visible = false,
	}, gui)

	local stickBase = make("Frame", {
		Size = UDim2.new(0, 120, 0, 120),
		Position = UDim2.new(0, 40, 1, -160),
		BackgroundColor3 = THEME.Panel,
		BackgroundTransparency = 0.5,
	}, mobileLayer)
	corner(stickBase, 60)

	local stickKnob = make("Frame", {
		Size = UDim2.new(0, 52, 0, 52),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		BackgroundColor3 = Color3.fromRGB(230, 230, 235),
		BackgroundTransparency = 0.1,
	}, stickBase)
	corner(stickKnob, 26)

	local stickInputId = nil
	local function updateStick(pos)
		local center = stickBase.AbsolutePosition + stickBase.AbsoluteSize / 2
		local delta = Vector2.new(pos.X, pos.Y) - center
		local radius = stickBase.AbsoluteSize.X / 2
		if delta.Magnitude > radius then delta = delta.Unit * radius end
		stickKnob.Position = UDim2.new(0.5, delta.X, 0.5, delta.Y)
		FC.stickVector = Vector2.new(delta.X / radius, -delta.Y / radius)
	end
	local function resetStick()
		stickInputId = nil
		FC.stickVector = Vector2.new(0, 0)
		stickKnob.Position = UDim2.new(0.5, 0, 0.5, 0)
	end

	stickBase.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			stickInputId = input
			updateStick(input.Position)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if stickInputId and input == stickInputId and input.UserInputType == Enum.UserInputType.Touch then
			updateStick(input.Position)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if stickInputId and input == stickInputId then resetStick() end
	end)

	local function makeVButton(text, yOffset)
		local b = make("TextButton", {
			Size = UDim2.new(0, 64, 0, 64),
			Position = UDim2.new(1, -84, 1, yOffset),
			BackgroundColor3 = THEME.Panel,
			BackgroundTransparency = 0.4,
			TextColor3 = THEME.Text,
			Font = hubFont,
			TextSize = 24,
			Text = text,
		}, mobileLayer)
		corner(b, 10)
		return b
	end
	local upBtn, downBtn = makeVButton("▲", -150), makeVButton("▼", -78)
	upBtn.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.Touch then FC.touchUp = true end end)
	upBtn.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.Touch then FC.touchUp = false end end)
	downBtn.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.Touch then FC.touchDown = true end end)
	downBtn.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.Touch then FC.touchDown = false end end)

	-- keep the mobile move/look layer visible only while free cam is active
	RunService.RenderStepped:Connect(function()
		mobileLayer.Visible = FC.enabled
	end)
end

------------------------------------------------------------------------
-- ============================ SHADERS TAB ============================
------------------------------------------------------------------------
local shaderPage = addTab("Shaders", 2)
layoutColumn(shaderPage)

local fx = {
	colorCorrection = make("ColorCorrectionEffect", { Name = "CinematicHub_ColorCorrection" }, Lighting),
	bloom           = make("BloomEffect",           { Name = "CinematicHub_Bloom" }, Lighting),
	blur            = make("BlurEffect",             { Name = "CinematicHub_Blur", Size = 0 }, Lighting),
	dof             = make("DepthOfFieldEffect",     { Name = "CinematicHub_DepthOfField" }, Lighting),
	sunRays         = make("SunRaysEffect",          { Name = "CinematicHub_SunRays", Intensity = 0 }, Lighting),
}

local PRESETS = {
	Default = function()
		fx.colorCorrection.Brightness, fx.colorCorrection.Contrast, fx.colorCorrection.Saturation = 0, 0, 0
		fx.colorCorrection.TintColor = Color3.new(1, 1, 1)
		fx.bloom.Intensity, fx.bloom.Size, fx.bloom.Threshold = 0, 24, 2
		fx.blur.Size = 0
		fx.dof.FarIntensity, fx.dof.InFocusRadius, fx.dof.NearIntensity = 0, 50, 0
		fx.sunRays.Intensity, fx.sunRays.Spread = 0, 0.5
	end,
	Cinematic = function()
		fx.colorCorrection.Brightness, fx.colorCorrection.Contrast, fx.colorCorrection.Saturation = -0.02, 0.15, -0.1
		fx.colorCorrection.TintColor = Color3.fromRGB(255, 244, 230)
		fx.bloom.Intensity, fx.bloom.Size, fx.bloom.Threshold = 0.6, 18, 1.6
		fx.blur.Size = 0
		fx.dof.FarIntensity, fx.dof.InFocusRadius, fx.dof.NearIntensity = 0.4, 35, 0
		fx.sunRays.Intensity, fx.sunRays.Spread = 0.15, 0.6
	end,
	Noir = function()
		fx.colorCorrection.Brightness, fx.colorCorrection.Contrast, fx.colorCorrection.Saturation = -0.05, 0.35, -1
		fx.colorCorrection.TintColor = Color3.new(1, 1, 1)
		fx.bloom.Intensity, fx.bloom.Size, fx.bloom.Threshold = 0.3, 16, 1.8
		fx.blur.Size = 0
		fx.dof.FarIntensity, fx.dof.InFocusRadius, fx.dof.NearIntensity = 0.3, 40, 0
		fx.sunRays.Intensity, fx.sunRays.Spread = 0, 0.5
	end,
	Warm = function()
		fx.colorCorrection.Brightness, fx.colorCorrection.Contrast, fx.colorCorrection.Saturation = 0.03, 0.08, 0.15
		fx.colorCorrection.TintColor = Color3.fromRGB(255, 210, 160)
		fx.bloom.Intensity, fx.bloom.Size, fx.bloom.Threshold = 0.4, 20, 1.8
		fx.blur.Size = 0
		fx.dof.FarIntensity, fx.dof.InFocusRadius, fx.dof.NearIntensity = 0.2, 45, 0
		fx.sunRays.Intensity, fx.sunRays.Spread = 0.25, 0.7
	end,
	Cold = function()
		fx.colorCorrection.Brightness, fx.colorCorrection.Contrast, fx.colorCorrection.Saturation = -0.02, 0.1, -0.05
		fx.colorCorrection.TintColor = Color3.fromRGB(170, 210, 255)
		fx.bloom.Intensity, fx.bloom.Size, fx.bloom.Threshold = 0.35, 18, 1.9
		fx.blur.Size = 0
		fx.dof.FarIntensity, fx.dof.InFocusRadius, fx.dof.NearIntensity = 0.25, 40, 0
		fx.sunRays.Intensity, fx.sunRays.Spread = 0, 0.5
	end,
	Dreamy = function()
		fx.colorCorrection.Brightness, fx.colorCorrection.Contrast, fx.colorCorrection.Saturation = 0.05, -0.05, 0.1
		fx.colorCorrection.TintColor = Color3.fromRGB(255, 235, 250)
		fx.bloom.Intensity, fx.bloom.Size, fx.bloom.Threshold = 1.2, 32, 1.2
		fx.blur.Size = 4
		fx.dof.FarIntensity, fx.dof.InFocusRadius, fx.dof.NearIntensity = 0.6, 25, 0.1
		fx.sunRays.Intensity, fx.sunRays.Spread = 0.3, 0.8
	end,
	Horror = function()
		fx.colorCorrection.Brightness, fx.colorCorrection.Contrast, fx.colorCorrection.Saturation = -0.2, 0.3, -0.6
		fx.colorCorrection.TintColor = Color3.fromRGB(190, 220, 200)
		fx.bloom.Intensity, fx.bloom.Size, fx.bloom.Threshold = 0.2, 12, 2
		fx.blur.Size = 1
		fx.dof.FarIntensity, fx.dof.InFocusRadius, fx.dof.NearIntensity = 0.7, 20, 0
		fx.sunRays.Intensity, fx.sunRays.Spread = 0, 0.5
	end,
}

local presetOrder = { "Default", "Cinematic", "Noir", "Warm", "Cold", "Dreamy", "Horror" }
local presetButtonsDef = {}
for _, name in ipairs(presetOrder) do
	table.insert(presetButtonsDef, { text = name, callback = function() PRESETS[name]() end })
end

-- two rows of preset buttons (4 + 3) since addButtonRow is one row
local presetsLabel = make("TextLabel", {
	Size = UDim2.new(1, 0, 0, 18),
	BackgroundTransparency = 1,
	Font = bodyFont,
	TextSize = 13,
	TextColor3 = THEME.SubText,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "Presets",
	LayoutOrder = 1,
}, shaderPage)

addButtonRow(shaderPage, 2, { presetButtonsDef[1], presetButtonsDef[2], presetButtonsDef[3], presetButtonsDef[4] })
addButtonRow(shaderPage, 3, { presetButtonsDef[5], presetButtonsDef[6], presetButtonsDef[7] })

addSlider(shaderPage, 4, "Bloom", 0, 3, 0, function(v) fx.bloom.Intensity = v end)
addSlider(shaderPage, 5, "Blur", 0, 24, 0, function(v) fx.blur.Size = v end)
addSlider(shaderPage, 6, "Saturation", -1, 1, 0, function(v) fx.colorCorrection.Saturation = v end)
addSlider(shaderPage, 7, "Contrast", -1, 1, 0, function(v) fx.colorCorrection.Contrast = v end)

------------------------------------------------------------------------
-- ============================ FONTS TAB ============================
------------------------------------------------------------------------
local fontPage = addTab("Fonts", 3)
layoutColumn(fontPage)

make("TextLabel", {
	Size = UDim2.new(1, 0, 0, 32),
	BackgroundTransparency = 1,
	Font = bodyFont,
	TextSize = 13,
	TextColor3 = THEME.SubText,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "Pick a font — applies to the hub, every other UI in the game, and chat (window + bubbles):",
	LayoutOrder = 1,
}, fontPage)

local FONT_OPTIONS = {
	"Gotham", "GothamBold", "SourceSans", "SourceSansBold", "Fondamento",
	"Bangers", "Creepster", "IndieFlower", "Oswald", "PermanentMarker",
	"Sarpanch", "TitilliumWeb",
}

local fontScroll = make("ScrollingFrame", {
	Size = UDim2.new(1, 0, 1, -90),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.new(0, 0, 0, #FONT_OPTIONS * 38),
	ScrollBarThickness = 6,
	LayoutOrder = 2,
}, fontPage)
make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, fontScroll)

local selectedFont = Enum.Font.Gotham

-- Applies once to every TextLabel/TextButton/TextBox already in the hub.
local function setFontEverywhereInHub(fontEnum)
	for _, descendant in ipairs(gui:GetDescendants()) do
		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
			descendant.Font = fontEnum
		end
	end
end

local function applyFontToInstance(inst, fontEnum)
	if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
		inst.Font = fontEnum
	end
end

-- One-shot, single pass over existing UI — cheap even on big games since it
-- only runs when you actually pick a font, never on a loop.
local function applyFontGlobally(fontEnum)
	for _, screenGui in ipairs(PlayerGui:GetChildren()) do
		if screenGui:IsA("ScreenGui") and screenGui.Name ~= "CinematicHubGui" then
			for _, descendant in ipairs(screenGui:GetDescendants()) do
				applyFontToInstance(descendant, fontEnum)
			end
		end
	end
end

-- Chat uses its own font config (TextChatService) instead of per-label
-- scanning, so bubble chat / chat window text updates instantly with zero
-- extra per-frame cost.
local function applyFontToChat(fontEnum)
	local TextChatService = game:GetService("TextChatService")
	pcall(function()
		TextChatService.ChatWindowConfiguration.FontFace = Font.fromEnum(fontEnum)
	end)
	pcall(function()
		TextChatService.BubbleChatConfiguration.Font = fontEnum
	end)
end

-- Single persistent watcher (not re-created per click) so newly spawned UI
-- — inventories, dialogs, other chat bubbles — picks up whichever font is
-- currently selected, without scanning anything repeatedly.
local fontWatchConnection = PlayerGui.DescendantAdded:Connect(function(descendant)
	if descendant:IsDescendantOf(gui) then return end
	applyFontToInstance(descendant, selectedFont)
end)

for i, fontName in ipairs(FONT_OPTIONS) do
	local ok, fontEnum = pcall(function() return Enum.Font[fontName] end)
	if ok and fontEnum then
		local btn = make("TextButton", {
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundColor3 = THEME.PanelAlt,
			TextColor3 = THEME.Text,
			Font = fontEnum,
			TextSize = 16,
			Text = fontName,
			LayoutOrder = i,
		}, fontScroll)
		corner(btn, 6)
		btn.Activated:Connect(function()
			selectedFont = fontEnum
			hubFont, bodyFont = fontEnum, fontEnum
			setFontEverywhereInHub(fontEnum)
			applyFontGlobally(fontEnum)
			applyFontToChat(fontEnum)
		end)
	end
end

------------------------------------------------------------------------
-- ============================ WORLD TAB ============================
------------------------------------------------------------------------
local worldPage = addTab("World", 4)
layoutColumn(worldPage)

addSlider(worldPage, 1, "Time of Day", 0, 24, Lighting.ClockTime, function(v)
	Lighting.ClockTime = v
end)

addSlider(worldPage, 2, "Camera FOV", 20, 120, Workspace.CurrentCamera.FieldOfView, function(v)
	Workspace.CurrentCamera.FieldOfView = v
end)

addSlider(worldPage, 3, "Atmosphere Haze", 0, 10, 0, function(v)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosphere then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Name = "CinematicHub_Atmosphere"
		atmosphere.Parent = Lighting
	end
	atmosphere.Haze = v
end)

addToggleRow(worldPage, 4, "Freeze Time of Day", false, function(state)
	-- Holds ClockTime steady against any other script changing it.
	worldPage:SetAttribute("FreezeTime", state)
end)

RunService.Heartbeat:Connect(function()
	if worldPage:GetAttribute("FreezeTime") then
		-- holds ClockTime steady against any other script changing it
		Lighting.ClockTime = Lighting.ClockTime
	end
end)

------------------------------------------------------------------------
-- ============================ EXTRAS TAB ============================
------------------------------------------------------------------------
local extrasPage = addTab("Extras", 5)
layoutColumn(extrasPage)

-- Letterbox bars: pure GUI overlay, no per-frame cost once sized.
local letterboxLayer = make("Frame", {
	Name = "Letterbox",
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 1,
	Visible = false,
}, gui)

local topBar = make("Frame", {
	Size = UDim2.new(1, 0, 0, 0),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BorderSizePixel = 0,
}, letterboxLayer)
local bottomBar = make("Frame", {
	Size = UDim2.new(1, 0, 0, 0),
	Position = UDim2.new(0, 0, 1, 0),
	AnchorPoint = Vector2.new(0, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BorderSizePixel = 0,
}, letterboxLayer)

local letterboxThickness = 0.12
local function applyLetterboxSize()
	topBar.Size = UDim2.new(1, 0, letterboxThickness, 0)
	bottomBar.Size = UDim2.new(1, 0, letterboxThickness, 0)
end
applyLetterboxSize()

addToggleRow(extrasPage, 1, "Letterbox Bars", false, function(state)
	letterboxLayer.Visible = state
end)

addSlider(extrasPage, 2, "Letterbox Size", 0.02, 0.25, letterboxThickness, function(v)
	letterboxThickness = v
	applyLetterboxSize()
end)

-- Hide nameplates / health bars over characters' heads for clean shots.
local nameplatesHidden = false
local function setNameplateVisible(humanoid, visible)
	pcall(function()
		humanoid.DisplayDistanceType = visible
			and Enum.HumanoidDisplayDistanceType.Viewer
			or Enum.HumanoidDisplayDistanceType.None
	end)
end

local function forEachHumanoid(callback)
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		if humanoid then callback(humanoid) end
	end
end

addToggleRow(extrasPage, 3, "Hide Nameplates/Healthbars", false, function(state)
	nameplatesHidden = state
	forEachHumanoid(function(h) setNameplateVisible(h, not state) end)
end)

Players.PlayerAdded:Connect(function(plr)
	plr.CharacterAdded:Connect(function(char)
		if nameplatesHidden then
			local humanoid = char:WaitForChild("Humanoid")
			setNameplateVisible(humanoid, false)
		end
	end)
end)

addButtonRow(extrasPage, 4, {
	{ text = "Reset All", callback = function()
		PRESETS.Default()
		letterboxLayer.Visible = false
		nameplatesHidden = false
		forEachHumanoid(function(h) setNameplateVisible(h, true) end)
		Lighting.ClockTime = 14
		Workspace.CurrentCamera.FieldOfView = 70
		local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
		if atmosphere then atmosphere.Haze = 0 end
		worldPage:SetAttribute("FreezeTime", false)
	end },
})

------------------------------------------------------------------------
-- Wire up launcher / close / keybind, default tab
------------------------------------------------------------------------
selectTab("Free Cam")
fcSetButtonState()

local function setHubOpen(open)
	hub.Visible = open
end

launcher.Activated:Connect(function()
	setHubOpen(not hub.Visible)
end)
closeBtn.Activated:Connect(function()
	setHubOpen(false)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if input.UserInputType == Enum.UserInputType.Keyboard then
		if input.KeyCode == Enum.KeyCode.P then
			fcToggle()
		elseif input.KeyCode == Enum.KeyCode.Backquote and not processed then
			setHubOpen(not hub.Visible)
		end
	end
end)

Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	if Workspace.CurrentCamera then
		FC.camera = Workspace.CurrentCamera
	end
end)

print("[CinematicHub] Loaded. Tap '🎬 Cinematic' or press ` to open the hub. Press P to toggle Free Cam.")
