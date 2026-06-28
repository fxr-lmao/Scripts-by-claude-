--[[
	cinematic/Fun.lua
	Time-wasters and public-safe toys: Pong against a simple AI (to pass the
	time while you wait in-game), a bouncing DVD logo, and an emote player
	(default Roblox emotes + a custom animation-id field).

	The emotes load real animations onto your own Animator, so other players
	see them too — nothing here touches the server or anyone else's state.
--]]

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

return function(ctx, Lib)
	local make  = Lib.make
	local THEME = Lib.THEME
	local LocalPlayer = Players.LocalPlayer

	local page = ctx.addTab("Fun", 7)

	local function header(order, text)
		local lbl = Lib.addLabel(page, order, text, 22)
		lbl.TextColor3 = THEME.Text
		lbl.Font = Lib.hubFont
		lbl.TextSize = 15
		return lbl
	end

	local function getHumanoid()
		local char = LocalPlayer.Character
		return char and char:FindFirstChildOfClass("Humanoid")
	end

	------------------------------------------------------------------
	-- Emotes
	------------------------------------------------------------------
	header(1, "Emotes")
	Lib.addLabel(page, 2, "Play a default emote, or paste any animation id.", 22)

	local DEFAULT_EMOTES = {
		{ name = "Wave",    id = 507770239 },
		{ name = "Point",   id = 507770453 },
		{ name = "Cheer",   id = 507770818 },
		{ name = "Laugh",   id = 507770904 },
		{ name = "Dance",   id = 507771019 },
		{ name = "Dance 2", id = 507776043 },
		{ name = "Dance 3", id = 507777268 },
	}

	local currentEmote
	local function stopEmote()
		if currentEmote then
			pcall(function() currentEmote:Stop(0.15) end)
			currentEmote = nil
		end
	end
	local function playEmote(animId)
		local humanoid = getHumanoid()
		local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		if not animator then return end
		stopEmote()
		local anim = Instance.new("Animation")
		anim.AnimationId = "rbxassetid://" .. tostring(animId)
		local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
		if ok and track then
			track.Priority = Enum.AnimationPriority.Action
			track.Looped = true
			pcall(function() track:Play(0.15) end)
			currentEmote = track
		end
	end

	local emoteGrid = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 3,
	}, page)
	make("UIGridLayout", {
		CellSize = UDim2.new(0, 110, 0, 30),
		CellPadding = UDim2.new(0, 6, 0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, emoteGrid)

	for i, emote in ipairs(DEFAULT_EMOTES) do
		local b = make("TextButton", {
			BackgroundColor3 = THEME.PanelAlt,
			TextColor3 = THEME.Text,
			Font = Lib.bodyFont,
			TextSize = 13,
			Text = emote.name,
			LayoutOrder = i,
			AutoButtonColor = true,
		}, emoteGrid)
		Lib.corner(b, 6)
		b.Activated:Connect(function() playEmote(emote.id) end)
	end

	Lib.addTextInput(page, 4, "Animation id…", "Play", function(text)
		local id = tonumber((text or ""):match("%d+"))
		if id then playEmote(id) end
	end)
	Lib.addButtonRow(page, 5, {
		{ text = "Stop Emote", width = 110, color = THEME.Danger,
			textColor = Color3.new(1, 1, 1), callback = stopEmote },
	})

	------------------------------------------------------------------
	-- DVD logo
	------------------------------------------------------------------
	header(6, "DVD Logo")
	Lib.addLabel(page, 7, "A bouncing logo that recolours on every wall hit.", 22)

	local dvdLayer, dvdLogo, dvdConn
	local function stopDVD()
		if dvdConn then dvdConn:Disconnect() dvdConn = nil end
		if dvdLayer then dvdLayer:Destroy() dvdLayer = nil dvdLogo = nil end
	end
	local function startDVD()
		stopDVD()
		dvdLayer = make("Frame", {
			Name = "DVDLayer",
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
		}, ctx.gui)
		dvdLogo = make("TextLabel", {
			Size = UDim2.new(0, 120, 0, 60),
			BackgroundColor3 = THEME.Accent,
			TextColor3 = Color3.new(1, 1, 1),
			Font = Enum.Font.GothamBold,
			TextSize = 26,
			Text = "DVD",
		}, dvdLayer)
		Lib.corner(dvdLogo, 8)

		local px, py = 40, 40
		local vx, vy = 160, 120
		dvdConn = RunService.RenderStepped:Connect(function(dt)
			if not dvdLayer then return end
			local area = dvdLayer.AbsoluteSize
			local size = dvdLogo.AbsoluteSize
			px = px + vx * dt
			py = py + vy * dt
			local bounced = false
			if px <= 0 then px = 0; vx = math.abs(vx); bounced = true end
			if px + size.X >= area.X then px = area.X - size.X; vx = -math.abs(vx); bounced = true end
			if py <= 0 then py = 0; vy = math.abs(vy); bounced = true end
			if py + size.Y >= area.Y then py = area.Y - size.Y; vy = -math.abs(vy); bounced = true end
			if bounced then
				dvdLogo.BackgroundColor3 = Color3.fromHSV(math.random(), 0.65, 1)
			end
			dvdLogo.Position = UDim2.new(0, px, 0, py)
		end)
	end

	local dvdToggle = Lib.addToggleRow(page, 8, "Bouncing DVD logo", false, function(state)
		if state then startDVD() else stopDVD() end
	end)

	------------------------------------------------------------------
	-- Pong vs robot
	------------------------------------------------------------------
	header(9, "Pong vs Robot")
	Lib.addLabel(page, 10, "Move your paddle by dragging in the court. First to pass wins the point.", 34)

	local COURT_W, COURT_H = 320, 200
	local PADDLE_H, PADDLE_W = 46, 8
	local BALL = 10

	local court = make("Frame", {
		Size = UDim2.new(0, COURT_W, 0, COURT_H),
		BackgroundColor3 = Color3.fromRGB(12, 12, 16),
		LayoutOrder = 11,
		Active = true, -- capture pointer so the page doesn't drag-scroll under us
	}, page)
	Lib.corner(court, 8)
	Lib.stroke(court, THEME.Accent, 1)

	make("Frame", { -- centre line
		Size = UDim2.new(0, 2, 1, -16),
		Position = UDim2.new(0.5, -1, 0, 8),
		BackgroundColor3 = Color3.fromRGB(60, 60, 70),
		BorderSizePixel = 0,
	}, court)

	local scoreLabel = make("TextLabel", {
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.new(0, 0, 0, 4),
		BackgroundTransparency = 1,
		Font = Lib.hubFont,
		TextSize = 16,
		TextColor3 = THEME.Text,
		Text = "0 : 0",
	}, court)

	local playerPaddle = make("Frame", {
		Size = UDim2.new(0, PADDLE_W, 0, PADDLE_H),
		Position = UDim2.new(0, 6, 0.5, -PADDLE_H / 2),
		BackgroundColor3 = THEME.Accent,
		BorderSizePixel = 0,
	}, court)
	Lib.corner(playerPaddle, 3)

	local aiPaddle = make("Frame", {
		Size = UDim2.new(0, PADDLE_W, 0, PADDLE_H),
		Position = UDim2.new(1, -6 - PADDLE_W, 0.5, -PADDLE_H / 2),
		BackgroundColor3 = THEME.Danger,
		BorderSizePixel = 0,
	}, court)
	Lib.corner(aiPaddle, 3)

	local ball = make("Frame", {
		Size = UDim2.new(0, BALL, 0, BALL),
		Position = UDim2.new(0.5, -BALL / 2, 0.5, -BALL / 2),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, court)
	Lib.corner(ball, 5)

	local playerY = COURT_H / 2
	local aiY = COURT_H / 2
	local bx, by = COURT_W / 2, COURT_H / 2
	local vx, vy = 170, 110
	local scoreP, scoreA = 0, 0

	local function clampPaddle(y) return math.clamp(y, PADDLE_H / 2, COURT_H - PADDLE_H / 2) end
	local function resetBall(dir)
		bx, by = COURT_W / 2, COURT_H / 2
		vx = 170 * dir
		vy = (math.random() * 2 - 1) * 120
	end

	-- Drag inside the court to set the player's paddle height.
	local function setPaddleFromInput(input)
		playerY = clampPaddle(input.Position.Y - court.AbsolutePosition.Y)
	end
	court.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			setPaddleFromInput(input)
		end
	end)
	court.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			setPaddleFromInput(input)
		end
	end)

	local pongActive = false
	local pongConn
	local function pongStep(dt)
		dt = math.min(dt, 1 / 30)

		-- AI tracks the ball with a capped speed (so it's beatable).
		local aiSpeed = 150 * dt
		if aiY < by - 4 then aiY = aiY + aiSpeed
		elseif aiY > by + 4 then aiY = aiY - aiSpeed end
		aiY = clampPaddle(aiY)

		bx = bx + vx * dt
		by = by + vy * dt

		if by <= 5 then by = 5; vy = math.abs(vy) end
		if by >= COURT_H - 5 then by = COURT_H - 5; vy = -math.abs(vy) end

		-- Player paddle (left).
		if vx < 0 and bx <= 6 + PADDLE_W and bx >= 6
			and math.abs(by - playerY) <= PADDLE_H / 2 + 5 then
			vx = math.abs(vx) * 1.04
			vy = vy + (by - playerY) * 2
		end
		-- AI paddle (right).
		if vx > 0 and bx >= COURT_W - 6 - PADDLE_W and bx <= COURT_W - 6
			and math.abs(by - aiY) <= PADDLE_H / 2 + 5 then
			vx = -math.abs(vx) * 1.04
			vy = vy + (by - aiY) * 2
		end

		if bx < 0 then scoreA = scoreA + 1; resetBall(1) end
		if bx > COURT_W then scoreP = scoreP + 1; resetBall(-1) end

		scoreLabel.Text = ("%d : %d"):format(scoreP, scoreA)
		ball.Position = UDim2.new(0, bx - BALL / 2, 0, by - BALL / 2)
		playerPaddle.Position = UDim2.new(0, 6, 0, playerY - PADDLE_H / 2)
		aiPaddle.Position = UDim2.new(0, COURT_W - 6 - PADDLE_W, 0, aiY - PADDLE_H / 2)
	end

	local pongToggle = Lib.addToggleRow(page, 12, "Play Pong", false, function(state)
		pongActive = state
		if state then
			if not pongConn then pongConn = RunService.RenderStepped:Connect(function(dt)
				if pongActive then pongStep(dt) end
			end) end
		else
			if pongConn then pongConn:Disconnect() pongConn = nil end
		end
	end)

	Lib.addButtonRow(page, 13, {
		{ text = "Reset Score", width = 110, callback = function()
			scoreP, scoreA = 0, 0
			resetBall(1)
			scoreLabel.Text = "0 : 0"
		end },
	})

	------------------------------------------------------------------
	-- Reset
	------------------------------------------------------------------
	ctx.onReset(function()
		stopEmote()
		if dvdToggle.get() then dvdToggle.set(false) end
		stopDVD()
		if pongToggle.get() then pongToggle.set(false) end
		scoreP, scoreA = 0, 0
		scoreLabel.Text = "0 : 0"
	end)
end
