--[[
	cinematic/Extras.lua
	Letterbox bars (with size slider), hide nameplates/healthbars, a standalone
	"Hide game UI" toggle (keeps the hub reachable so you can toggle back), and
	a Reset All that runs every module's registered reset.
--]]

local Players = game:GetService("Players")

return function(ctx, Lib)
	local make = Lib.make
	local THEME = Lib.THEME
	local page = ctx.addTab("Extras", 8)

	------------------------------------------------------------------
	-- Letterbox
	------------------------------------------------------------------
	local letterboxLayer = make("Frame", {
		Name = "Letterbox",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Visible = false,
	}, ctx.gui)
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

	local thickness = 0.12
	local function applyLetterbox()
		topBar.Size = UDim2.new(1, 0, thickness, 0)
		bottomBar.Size = UDim2.new(1, 0, thickness, 0)
	end
	applyLetterbox()

	local letterboxToggle = Lib.addToggleRow(page, 1, "Letterbox Bars", false, function(state)
		letterboxLayer.Visible = state
	end)
	Lib.addSlider(page, 2, "Letterbox Size", 0.02, 0.25, thickness, function(v)
		thickness = v
		applyLetterbox()
	end)

	------------------------------------------------------------------
	-- Nameplates / healthbars
	------------------------------------------------------------------
	local nameplatesHidden = false
	local function setNameplate(humanoid, visible)
		pcall(function()
			humanoid.DisplayDistanceType = visible
				and Enum.HumanoidDisplayDistanceType.Viewer
				or Enum.HumanoidDisplayDistanceType.None
		end)
	end
	local function forEachHumanoid(cb)
		for _, plr in ipairs(Players:GetPlayers()) do
			local char = plr.Character
			local humanoid = char and char:FindFirstChildOfClass("Humanoid")
			if humanoid then cb(humanoid) end
		end
	end

	-- Catch respawns for everyone (not just players who join later) so the
	-- setting sticks across deaths while it's on.
	for _, plr in ipairs(Players:GetPlayers()) do
		plr.CharacterAdded:Connect(function(char)
			if nameplatesHidden then
				setNameplate(char:WaitForChild("Humanoid"), false)
			end
		end)
	end
	Players.PlayerAdded:Connect(function(plr)
		plr.CharacterAdded:Connect(function(char)
			if nameplatesHidden then
				setNameplate(char:WaitForChild("Humanoid"), false)
			end
		end)
	end)

	local nameplateToggle = Lib.addToggleRow(page, 3, "Hide Nameplates/Healthbars", false, function(state)
		nameplatesHidden = state
		forEachHumanoid(function(h) setNameplate(h, not state) end)
	end)

	------------------------------------------------------------------
	-- Hide other players' characters (local-only, clean restore)
	------------------------------------------------------------------
	local playersHidden = false
	-- LocalTransparencyModifier hides a part client-side without touching its
	-- real Transparency, so it restores cleanly; decals keep no LTM, so we stash
	-- and restore their Transparency via an attribute.
	local function setCharHidden(char, hidden)
		for _, d in ipairs(char:GetDescendants()) do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = hidden and 1 or 0
			elseif d:IsA("Decal") or d:IsA("Texture") then
				if hidden then
					if d:GetAttribute("_mtrans") == nil then d:SetAttribute("_mtrans", d.Transparency) end
					d.Transparency = 1
				else
					local orig = d:GetAttribute("_mtrans")
					if orig ~= nil then d.Transparency = orig; d:SetAttribute("_mtrans", nil) end
				end
			end
		end
	end
	local function forEachOther(cb)
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= Players.LocalPlayer and plr.Character then cb(plr.Character) end
		end
	end
	-- Keep hiding across respawns / late joiners while the toggle is on.
	local function hookHidePlayer(plr)
		plr.CharacterAdded:Connect(function(char)
			if playersHidden and plr ~= Players.LocalPlayer then
				task.wait(0.2) -- let the body/accessories stream in first
				setCharHidden(char, true)
			end
		end)
	end
	for _, plr in ipairs(Players:GetPlayers()) do hookHidePlayer(plr) end
	Players.PlayerAdded:Connect(hookHidePlayer)

	local hidePlayersToggle = Lib.addToggleRow(page, 4, "Hide Other Players", false, function(state)
		playersHidden = state
		forEachOther(function(char) setCharHidden(char, state) end)
	end)

	------------------------------------------------------------------
	-- Hide game UI (keeps the hub reachable)
	------------------------------------------------------------------
	local hideUIToggle = Lib.addToggleRow(page, 5, "Hide Game UI", false, function(state)
		Lib.setGameUIHidden(state, ctx.gui)
	end)

	------------------------------------------------------------------
	-- Reset All
	------------------------------------------------------------------
	Lib.addButtonRow(page, 6, {
		{ text = "Reset All", width = 110, color = THEME.Danger, textColor = Color3.new(1, 1, 1),
			callback = function()
				letterboxToggle.set(false, false)
				letterboxLayer.Visible = false
				nameplateToggle.set(false, false)
				nameplatesHidden = false
				forEachHumanoid(function(h) setNameplate(h, true) end)
				hidePlayersToggle.set(false, false)
				playersHidden = false
				forEachOther(function(char) setCharHidden(char, false) end)
				hideUIToggle.set(false, false)
				Lib.setGameUIHidden(false, ctx.gui)
				ctx.runReset()
			end },
	})
end
