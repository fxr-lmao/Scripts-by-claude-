--[[
	cinematic/Fonts.lua
	Pick a font; it re-skins the hub, every other UI under PlayerGui, and chat
	(window + bubbles via TextChatService's font config). One persistent
	DescendantAdded watcher catches UI spawned afterward — no polling, so it
	stays lag-free.

	Invalid font names are skipped via pcall, so the list can be generous.
--]]

local TextChatService = game:GetService("TextChatService")
local Workspace       = game:GetService("Workspace")

return function(ctx, Lib)
	local make = Lib.make
	local THEME = Lib.THEME
	local PlayerGui = Lib.PlayerGui
	local gui = ctx.gui

	local page = ctx.addTab("Fonts", 3)

	Lib.addLabel(page, 1,
		"Pick a font — applies to the hub, every other UI in the game, and chat "
		.. "(window + bubbles):", 34)

	local FONT_OPTIONS = {
		-- clean / UI
		"Gotham", "GothamBold", "GothamMedium", "SourceSans", "SourceSansBold",
		"Roboto", "RobotoCondensed", "RobotoMono", "Ubuntu", "Nunito",
		"Merriweather", "Jura", "TitilliumWeb", "Sarpanch", "Oswald",
		-- fun / display
		"Bangers", "Creepster", "IndieFlower", "PermanentMarker", "Fondamento",
		"Cartoon", "Antique", "Arcade", "Bodoni", "Garamond",
		"Michroma", "Orbitron", "FredokaOne", "GrenzeGotisch", "AmaticSC",
		"Kalam", "DenkOne", "Fantasy", "HighwayGothic", "Balthazar",
		"PatrickHand", "Grenze", "BuilderSans",
	}

	local scroll = make("ScrollingFrame", {
		Size = UDim2.new(1, 0, 0, 230),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 8,
		ScrollBarImageColor3 = THEME.Accent,
		LayoutOrder = 2,
	}, page)
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)

	local DEFAULT_FONT = Enum.Font.Gotham
	local selectedFont = DEFAULT_FONT
	local fontChosen = false -- don't touch game UI until the user actually picks

	local function applyToInstance(inst, fontEnum)
		-- Leave the font-list preview buttons alone: each one renders its own
		-- font as a live preview, so re-skinning them would make every option
		-- look identical and you couldn't compare/pick another.
		if inst:GetAttribute("CinematicFontPreview") then return end
		if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
			-- pcall per instance: some CoreGui text is locked and throws, and one
			-- locked element must not abort the rest of the sweep.
			pcall(function() inst.Font = fontEnum end)
		end
	end

	-- The game's own text: the player's UI (which includes our hub) and in-world
	-- Billboard/Surface GUIs under Workspace (nameplates, overhead labels, signs…).
	-- We deliberately do NOT touch CoreGui — that's Roblox's own system UI (the
	-- leave/settings menu, player list, chat frame), and re-fonting it breaks its
	-- layout. Chat is handled the supported way via TextChatService below.
	local function collectRoots()
		return { PlayerGui, Workspace }
	end

	local function applyAll(fontEnum)
		for _, root in ipairs(collectRoots()) do
			local ok, descendants = pcall(function() return root:GetDescendants() end)
			if ok then
				for _, d in ipairs(descendants) do
					applyToInstance(d, fontEnum)
				end
			end
		end
	end

	local function applyToChat(fontEnum)
		pcall(function()
			TextChatService.ChatWindowConfiguration.FontFace = Font.fromEnum(fontEnum)
		end)
		pcall(function()
			TextChatService.BubbleChatConfiguration.FontFace = Font.fromEnum(fontEnum)
		end)
	end

	-- Watchers are connected lazily on the first pick (zero overhead until the
	-- feature is actually used), then catch any text spawned afterward across
	-- every root. The per-instance IsA check makes the Workspace watcher cheap.
	local watchersConnected = false
	local function connectWatchers()
		if watchersConnected then return end
		watchersConnected = true
		for _, root in ipairs(collectRoots()) do
			pcall(function()
				root.DescendantAdded:Connect(function(d)
					if fontChosen then applyToInstance(d, selectedFont) end
				end)
			end)
		end
	end

	local function selectFont(fontEnum)
		fontChosen = true
		selectedFont = fontEnum
		Lib.hubFont, Lib.bodyFont = fontEnum, fontEnum
		connectWatchers()
		applyAll(fontEnum)
		applyToChat(fontEnum)
	end

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
			}, scroll)
			-- Tag so the font modifier never overwrites this preview's own font.
			btn:SetAttribute("CinematicFontPreview", true)
			Lib.corner(btn, 6)
			btn.Activated:Connect(function() selectFont(fontEnum) end)
		end
	end

	-- Only revert fonts if we actually changed them; don't stamp the default
	-- onto a game we never touched.
	ctx.onReset(function()
		if fontChosen then selectFont(DEFAULT_FONT) end
	end)
end
