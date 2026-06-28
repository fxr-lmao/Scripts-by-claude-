--[[
	cinematic/Shell.lua
	Builds the hub window: floating launcher, draggable title bar, sidebar
	tabs, and the content area. Each tab page is a ScrollingFrame that you can
	scroll by dragging anywhere on it (no scroll wheel required) as well as via
	the scrollbar — and its canvas auto-sizes to its contents.

	Usage:  local ctx = require(Shell)(Lib)
--]]

local UserInputService = game:GetService("UserInputService")

return function(Lib)
	local make, corner, stroke = Lib.make, Lib.corner, Lib.stroke
	local THEME = Lib.THEME
	local PlayerGui = Lib.PlayerGui

	local ctx = {}
	local resetCallbacks = {}
	function ctx.onReset(fn) table.insert(resetCallbacks, fn) end
	function ctx.runReset()
		for _, fn in ipairs(resetCallbacks) do
			pcall(fn)
		end
	end

	------------------------------------------------------------------
	-- Root
	------------------------------------------------------------------
	local gui = make("ScreenGui", {
		Name = "CinematicHubGui",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 1000,
	}, PlayerGui)
	ctx.gui = gui

	------------------------------------------------------------------
	-- Launcher (draggable, with drag-vs-click guard)
	------------------------------------------------------------------
	local launcher = make("TextButton", {
		Name = "Launcher",
		Size = UDim2.new(0, 150, 0, 46),
		Position = UDim2.new(0.5, -75, 0, 12), -- middle-top
		BackgroundColor3 = THEME.Panel,
		TextColor3 = THEME.Text,
		Font = Lib.hubFont,
		TextSize = 16,
		Text = "🎬  Cinematic",
		AutoButtonColor = true,
	}, gui)
	corner(launcher, 10)
	stroke(launcher, THEME.Accent, 1)
	ctx.launcher = launcher

	local launcherDragged = false
	do
		local dragging, dragStart, startPos = false, nil, nil
		launcher.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				dragging, launcherDragged = true, false
				dragStart, startPos = input.Position, launcher.Position
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch) then
				local delta = input.Position - dragStart
				if delta.Magnitude > 6 then launcherDragged = true end
				launcher.Position = UDim2.new(
					startPos.X.Scale, startPos.X.Offset + delta.X,
					startPos.Y.Scale, startPos.Y.Offset + delta.Y)
			end
		end)
		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				dragging = false
			end
		end)
	end

	------------------------------------------------------------------
	-- Window
	------------------------------------------------------------------
	local hub = make("Frame", {
		Name = "Hub",
		Size = UDim2.new(0, 540, 0, 420),
		Position = UDim2.new(0.5, -270, 0.5, -210),
		BackgroundColor3 = THEME.Background,
		Visible = false,
	}, gui)
	corner(hub, 12)
	stroke(hub, Color3.fromRGB(55, 55, 65), 1)
	ctx.hub = hub

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
		Font = Lib.hubFont,
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
		Font = Lib.hubFont,
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
				dragStart, startPos = input.Position, hub.Position
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch) then
				local delta = input.Position - dragStart
				hub.Position = UDim2.new(
					startPos.X.Scale, startPos.X.Offset + delta.X,
					startPos.Y.Scale, startPos.Y.Offset + delta.Y)
			end
		end)
		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				dragging = false
			end
		end)
	end

	local sidebar = make("Frame", {
		Name = "Sidebar",
		Size = UDim2.new(0, 130, 1, -40),
		Position = UDim2.new(0, 0, 0, 40),
		BackgroundColor3 = THEME.Panel,
	}, hub)
	make("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, sidebar)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
	}, sidebar)

	local content = make("Frame", {
		Name = "Content",
		Size = UDim2.new(1, -130, 1, -40),
		Position = UDim2.new(0, 130, 0, 40),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
	}, hub)
	ctx.content = content

	------------------------------------------------------------------
	-- Tabs
	------------------------------------------------------------------
	local tabButtons, tabPages = {}, {}
	local activeTab = nil

	local function selectTab(name)
		if activeTab == name then return end
		activeTab = name
		for tabName, page in pairs(tabPages) do
			page.Visible = (tabName == name)
		end
		for tabName, btn in pairs(tabButtons) do
			btn.BackgroundColor3 = (tabName == name) and THEME.Accent or THEME.PanelAlt
			btn.TextColor3 = (tabName == name) and Color3.new(0, 0, 0) or THEME.Text
		end
	end
	ctx.selectTab = selectTab

	-- Drag-to-scroll: pan the canvas when a press starts on the page's empty
	-- background (presses that start on a slider/button hit that control's own
	-- handler instead, so this never fights the widgets).
	local function attachDragScroll(page)
		local panning, startY, startCanvas = false, 0, 0
		page.InputBegan:Connect(function(input)
			-- Yield if a slider (or other widget) claimed this same press.
			if Lib.widgetDragging then return end
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				panning = true
				startY = input.Position.Y
				startCanvas = page.CanvasPosition.Y
			end
		end)
		UserInputService.InputChanged:Connect(function(input)
			if panning and not Lib.widgetDragging
				and (input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch) then
				local maxY = math.max(0, page.AbsoluteCanvasSize.Y - page.AbsoluteWindowSize.Y)
				local target = math.clamp(startCanvas - (input.Position.Y - startY), 0, maxY)
				page.CanvasPosition = Vector2.new(0, target)
			end
		end)
		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				panning = false
			end
		end)
	end

	function ctx.addTab(name, order)
		local btn = make("TextButton", {
			Name = name .. "Tab",
			Size = UDim2.new(1, 0, 0, 34),
			BackgroundColor3 = THEME.PanelAlt,
			TextColor3 = THEME.Text,
			Font = Lib.bodyFont,
			TextSize = 14,
			Text = name,
			LayoutOrder = order,
			AutoButtonColor = true,
		}, sidebar)
		corner(btn, 8)
		tabButtons[name] = btn

		local page = make("ScrollingFrame", {
			Name = name .. "Page",
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Visible = false,
			CanvasSize = UDim2.new(0, 0, 0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = 8,
			ScrollBarImageColor3 = THEME.Accent,
			ScrollBarImageTransparency = 0.2,
			ElasticBehavior = Enum.ElasticBehavior.Never,
		}, content)
		make("UIListLayout", {
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, page)
		make("UIPadding", {
			PaddingTop = UDim.new(0, 14),
			PaddingLeft = UDim.new(0, 14),
			PaddingRight = UDim.new(0, 14),
			PaddingBottom = UDim.new(0, 14),
		}, page)
		tabPages[name] = page
		attachDragScroll(page)

		btn.Activated:Connect(function() selectTab(name) end)
		return page
	end

	------------------------------------------------------------------
	-- Open / close
	------------------------------------------------------------------
	local function setHubOpen(open) hub.Visible = open end
	ctx.setHubOpen = setHubOpen

	launcher.Activated:Connect(function()
		if launcherDragged then
			launcherDragged = false
			return
		end
		setHubOpen(not hub.Visible)
	end)
	closeBtn.Activated:Connect(function() setHubOpen(false) end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType == Enum.UserInputType.Keyboard
			and input.KeyCode == Enum.KeyCode.Backquote then
			setHubOpen(not hub.Visible)
		end
	end)

	return ctx
end
