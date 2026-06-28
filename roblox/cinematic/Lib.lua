--[[
	cinematic/Lib.lua
	Shared theme, low-level instance helpers, and reusable UI widgets
	(sliders, toggles, button rows, labels) for the Cinematic Hub.

	Returns a single `Lib` table. Fonts (`Lib.hubFont` / `Lib.bodyFont`) are
	mutable so the Fonts tab can change what newly-built widgets use.
--]]

local UserInputService = game:GetService("UserInputService")
local Players           = game:GetService("Players")
local StarterGui        = game:GetService("StarterGui")
local GuiService        = game:GetService("GuiService")

-- Resolve LocalPlayer defensively so the hub is safe to auto-execute before the
-- player has fully loaded in.
local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
	LocalPlayer = Players:GetPropertyChangedSignal("LocalPlayer"):Wait() and Players.LocalPlayer
end
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

local Lib = {}

Lib.PlayerGui = PlayerGui

Lib.THEME = {
	Background = Color3.fromRGB(22, 22, 28),
	Panel      = Color3.fromRGB(30, 30, 38),
	PanelAlt   = Color3.fromRGB(38, 38, 48),
	Accent     = Color3.fromRGB(90, 170, 255),
	Text       = Color3.fromRGB(235, 235, 240),
	SubText    = Color3.fromRGB(160, 160, 170),
	Danger     = Color3.fromRGB(220, 80, 80),
}
local THEME = Lib.THEME

Lib.hubFont  = Enum.Font.GothamBold
Lib.bodyFont = Enum.Font.Gotham

-- Brand: change these two and the whole UI (launcher, title, prints) follows.
Lib.BRAND = "Mirage"
Lib.GLYPH = "✨"

-- Set true while a slider knob/track is being dragged, so a tab page's
-- drag-to-scroll yields instead of fighting the slider for the same press.
Lib.widgetDragging = false

------------------------------------------------------------------------
-- Instance helpers
------------------------------------------------------------------------
function Lib.make(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	if parent then inst.Parent = parent end
	return inst
end
local make = Lib.make

function Lib.corner(parent, radius)
	return Lib.make("UICorner", { CornerRadius = UDim.new(0, radius or 8) }, parent)
end

function Lib.stroke(parent, color, thickness)
	return Lib.make("UIStroke", {
		Color = color or Color3.fromRGB(60, 60, 70),
		Thickness = thickness or 1,
	}, parent)
end

function Lib.isMobile()
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

------------------------------------------------------------------------
-- Shared "hide the game UI for a clean shot" helper (used by Free Cam and
-- the Extras "Hide All UI" toggle). One source of truth so the saved/restore
-- state never gets clobbered by two callers fighting over it.
------------------------------------------------------------------------
do
	local hidden = false
	local saved  = {}

	local function setCore(name, value)
		pcall(function() StarterGui:SetCore(name, value) end)
	end
	local function setCoreGui(t, v)
		pcall(function() StarterGui:SetCoreGuiEnabled(t, v) end)
	end

	-- selfGui: our own ScreenGui, which is left visible so the hub/launcher
	-- stay reachable.
	function Lib.setGameUIHidden(state, selfGui)
		if state == hidden then return end
		hidden = state
		if state then
			table.clear(saved)
			for _, g in ipairs(PlayerGui:GetChildren()) do
				if g:IsA("ScreenGui") and g ~= selfGui then
					saved[g] = g.Enabled
					g.Enabled = false
				end
			end
			setCoreGui(Enum.CoreGuiType.All, false)
			setCore("TopbarEnabled", false)
			GuiService.AutoSelectGuiEnabled = false
		else
			for g, wasEnabled in pairs(saved) do
				if g and g.Parent then g.Enabled = wasEnabled end
			end
			table.clear(saved)
			setCoreGui(Enum.CoreGuiType.All, true)
			setCore("TopbarEnabled", true)
			GuiService.AutoSelectGuiEnabled = true
		end
	end

	function Lib.isGameUIHidden() return hidden end
end

------------------------------------------------------------------------
-- Widgets
------------------------------------------------------------------------
function Lib.addLabel(parent, order, text, height)
	return make("TextLabel", {
		Size = UDim2.new(1, 0, 0, height or 18),
		BackgroundTransparency = 1,
		Font = Lib.bodyFont,
		TextSize = 13,
		TextColor3 = THEME.SubText,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = text,
		LayoutOrder = order,
	}, parent)
end

-- Returns a handle with :set(value) so callers (e.g. Reset) can move the
-- slider programmatically and have onChange fire.
function Lib.addSlider(parent, order, labelText, min, max, default, onChange)
	local row = make("Frame", {
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, parent)

	local label = make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 18),
		BackgroundTransparency = 1,
		Font = Lib.bodyFont,
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
	Lib.corner(track, 3)

	local function alphaFor(v)
		return math.clamp((v - min) / (max - min), 0, 1)
	end

	local fill = make("Frame", {
		Size = UDim2.new(alphaFor(default), 0, 1, 0),
		BackgroundColor3 = THEME.Accent,
		BorderSizePixel = 0,
	}, track)
	Lib.corner(fill, 3)

	local knob = make("TextButton", {
		Size = UDim2.new(0, 16, 0, 16),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(alphaFor(default), 0, 0.5, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Text = "",
		AutoButtonColor = false,
	}, track)
	Lib.corner(knob, 8)

	local function setVisual(rel, value)
		fill.Size = UDim2.new(rel, 0, 1, 0)
		knob.Position = UDim2.new(rel, 0, 0.5, 0)
		label.Text = ("%s: %.2f"):format(labelText, value)
	end

	local dragging = false
	local function applyFromX(absX)
		local rel = math.clamp((absX - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		local value = min + rel * (max - min)
		setVisual(rel, value)
		onChange(value)
	end

	local function startDrag()
		dragging = true
		Lib.widgetDragging = true
	end
	knob.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			startDrag()
		end
	end)
	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			startDrag()
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
			if dragging then Lib.widgetDragging = false end
			dragging = false
		end
	end)

	return {
		row = row,
		set = function(value, fire)
			local rel = alphaFor(value)
			setVisual(rel, value)
			if fire ~= false then onChange(value) end
		end,
	}
end

function Lib.addToggleRow(parent, order, labelText, default, onChange)
	local row = make("Frame", {
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, parent)

	make("TextLabel", {
		Size = UDim2.new(1, -60, 1, 0),
		BackgroundTransparency = 1,
		Font = Lib.bodyFont,
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
		Font = Lib.hubFont,
		TextSize = 12,
		TextColor3 = state and Color3.new(0, 0, 0) or THEME.Text,
	}, row)
	Lib.corner(switch, 13)

	local function render()
		switch.BackgroundColor3 = state and THEME.Accent or THEME.PanelAlt
		switch.Text = state and "ON" or "OFF"
		switch.TextColor3 = state and Color3.new(0, 0, 0) or THEME.Text
	end

	switch.Activated:Connect(function()
		state = not state
		render()
		onChange(state)
	end)

	return {
		row = row,
		set = function(value, fire)
			if state == value then return end
			state = value
			render()
			if fire ~= false then onChange(state) end
		end,
		get = function() return state end,
	}
end

-- A text field + action button on one row. onSubmit(text) fires on the button
-- or when the box is committed with Enter. Returns { row, box, set(text) }.
function Lib.addTextInput(parent, order, placeholder, buttonText, onSubmit)
	local row = make("Frame", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, parent)

	local box = make("TextBox", {
		Size = UDim2.new(1, -84, 1, 0),
		BackgroundColor3 = THEME.PanelAlt,
		TextColor3 = THEME.Text,
		Font = Lib.bodyFont,
		TextSize = 13,
		Text = "",
		PlaceholderText = placeholder or "",
		PlaceholderColor3 = THEME.SubText,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, row)
	Lib.corner(box, 6)
	make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, box)

	local btn = make("TextButton", {
		Size = UDim2.new(0, 76, 1, 0),
		Position = UDim2.new(1, -76, 0, 0),
		BackgroundColor3 = THEME.Accent,
		TextColor3 = Color3.new(0, 0, 0),
		Font = Lib.hubFont,
		TextSize = 13,
		Text = buttonText or "Go",
		AutoButtonColor = true,
	}, row)
	Lib.corner(btn, 6)

	local function submit() onSubmit(box.Text) end
	btn.Activated:Connect(submit)
	box.FocusLost:Connect(function(enterPressed)
		if enterPressed then submit() end
	end)

	return {
		row = row,
		box = box,
		set = function(text) box.Text = text end,
	}
end

function Lib.addButtonRow(parent, order, buttons)
	local row = make("Frame", {
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, parent)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)

	for i, def in ipairs(buttons) do
		local b = make("TextButton", {
			Size = UDim2.new(0, def.width or 88, 1, 0),
			BackgroundColor3 = def.color or THEME.PanelAlt,
			TextColor3 = def.textColor or THEME.Text,
			Font = Lib.bodyFont,
			TextSize = 13,
			Text = def.text,
			LayoutOrder = i,
			AutoButtonColor = true,
		}, row)
		Lib.corner(b, 6)
		b.Activated:Connect(def.callback)
	end
	return row
end

return Lib
