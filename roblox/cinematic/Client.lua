--[[
	cinematic/Client.lua
	Client-side tools tab: skin changer (copy a user's avatar or a preset),
	animation speed (with optional sync to the World timelapse), animation
	FastFlags, a performance / FPS booster, and an anti-idle (no AFK kick).

	Everything here is local-only. The skin changer, FFlags, FPS cap and
	anti-idle lean on executor / client APIs (ApplyDescription, setfflag,
	setfpscap, VirtualUser) — each is pcall-guarded so anything the runtime
	doesn't support quietly no-ops instead of erroring.
--]]

local Players     = game:GetService("Players")
local RunService  = game:GetService("RunService")
local Lighting    = game:GetService("Lighting")
local Workspace   = game:GetService("Workspace")

return function(ctx, Lib)
	local make  = Lib.make
	local THEME = Lib.THEME
	local LocalPlayer = Players.LocalPlayer

	local page = ctx.addTab("Client", 6)

	local function getCharacter() return LocalPlayer.Character end
	local function getHumanoid()
		local char = getCharacter()
		return char and char:FindFirstChildOfClass("Humanoid"), char
	end

	------------------------------------------------------------------
	-- Section header helper (a slightly bolder label)
	------------------------------------------------------------------
	local function header(order, text)
		local lbl = Lib.addLabel(page, order, text, 22)
		lbl.TextColor3 = THEME.Text
		lbl.Font = Lib.hubFont
		lbl.TextSize = 15
		return lbl
	end

	------------------------------------------------------------------
	-- Skin changer
	------------------------------------------------------------------
	header(1, "Skin Changer")
	Lib.addLabel(page, 2,
		"Copy a player's avatar by username/ID, or pick a preset. Client-side "
		.. "only — others still see your real avatar.", 34)

	local skinStatus = Lib.addLabel(page, 3, "", 18)

	-- The avatar we want held on this character; re-applied on respawn.
	local desiredUserId = nil

	-- Fully client-side avatar copy. ApplyDescription is blocked on the client in
	-- many games ("can only be called by the backend server"), so instead we pull
	-- the target's appearance instances (clothing, accessories, body colours,
	-- meshes) and parent them onto the local character ourselves. Visible only to
	-- you — the server never sees it.
	local function copyAppearance(userId)
		local char = getCharacter()
		local humanoid = getHumanoid()
		if not char or not humanoid then return false, "no character yet" end
		local ok, appearance = pcall(function()
			return Players:GetCharacterAppearanceAsync(userId)
		end)
		if not ok then return false, appearance end

		-- Strip current cosmetics so the copy doesn't stack on top.
		for _, c in ipairs(char:GetChildren()) do
			if c:IsA("Accessory") or c:IsA("Shirt") or c:IsA("Pants")
				or c:IsA("ShirtGraphic") or c:IsA("BodyColors") or c:IsA("CharacterMesh") then
				c:Destroy()
			end
		end

		-- GetCharacterAppearanceAsync returns a Model of instances (older builds
		-- may hand back a plain array) — support both.
		local items = {}
		if typeof(appearance) == "Instance" then
			items = appearance:GetChildren()
		elseif type(appearance) == "table" then
			items = appearance
		end
		for _, item in ipairs(items) do
			if item:IsA("Accessory") then
				pcall(function() humanoid:AddAccessory(item) end)
			else
				pcall(function() item.Parent = char end)
			end
		end
		return true
	end

	Lib.addTextInput(page, 4, "Username or UserId…", "Apply", function(text)
		text = (text or ""):gsub("%s+", "")
		if text == "" then return end
		skinStatus.Text = "Loading " .. text .. "…"
		task.spawn(function()
			local ok, userId = pcall(function()
				return tonumber(text) or Players:GetUserIdFromNameAsync(text)
			end)
			if not ok or not userId then
				skinStatus.Text = "User lookup failed: " .. tostring(userId)
				warn("[Mirage] skin lookup failed: " .. tostring(userId))
				return
			end
			desiredUserId = userId
			local applied, err = copyAppearance(userId)
			if applied then
				skinStatus.Text = "Applied avatar: " .. text
				print("[Mirage] skin (appearance) applied: " .. text)
			else
				skinStatus.Text = "Apply failed: " .. tostring(err)
				warn("[Mirage] skin apply failed: " .. tostring(err))
			end
		end)
	end)

	-- Re-apply the copied avatar after a respawn so it persists.
	LocalPlayer.CharacterAdded:Connect(function(char)
		if not desiredUserId then return end
		char:WaitForChild("Humanoid", 5)
		task.wait(1) -- let the default body stream in first, then overwrite
		copyAppearance(desiredUserId)
	end)

	-- Presets color the local character's parts directly. Purely client-side and
	-- immediate — unlike ApplyDescription, the game can't quietly revert it, and
	-- it works on both R6 and R15 rigs via the part-name heuristic.
	local function colorChar(scheme)
		local char = getCharacter()
		if not char then return false end
		for _, p in ipairs(char:GetDescendants()) do
			if p:IsA("BasePart") then
				local nm = p.Name:lower()
				local col = scheme.torso
				if nm:find("head") then col = scheme.head
				elseif nm:find("arm") or nm:find("hand") then col = scheme.arm
				elseif nm:find("leg") or nm:find("foot") then col = scheme.leg end
				pcall(function() p.Color = col end)
			end
		end
		return true
	end
	local function preset(name, scheme)
		return {
			text = name, width = 92,
			callback = function()
				local ok = colorChar(scheme)
				skinStatus.Text = ok and ("Preset: " .. name) or "Preset: no character"
				print("[Mirage] preset " .. name .. (ok and " applied" or " (no character)"))
			end,
		}
	end

	Lib.addButtonRow(page, 5, {
		preset("Stealth", {
			head = Color3.new(0, 0, 0), torso = Color3.new(0, 0, 0),
			arm = Color3.new(0, 0, 0), leg = Color3.new(0, 0, 0),
		}),
		preset("Noob", {
			head = Color3.fromRGB(245, 205, 48), torso = Color3.fromRGB(13, 105, 172),
			arm = Color3.fromRGB(245, 205, 48), leg = Color3.fromRGB(40, 127, 71),
		}),
	})

	-- Ghost: keep the local character's parts invisible. The engine rewrites
	-- LocalTransparencyModifier each frame, so hold it on with a Heartbeat.
	local ghostOn = false
	local ghostConn
	local function paintGhost()
		local char = getCharacter()
		if not char then return end
		for _, p in ipairs(char:GetDescendants()) do
			if p:IsA("BasePart") or p:IsA("Decal") then
				p.LocalTransparencyModifier = 1
			end
		end
	end
	local ghostToggle = Lib.addToggleRow(page, 6, "Invisible (ghost, local-only)", false, function(state)
		ghostOn = state
		if state then
			if not ghostConn then ghostConn = RunService.RenderStepped:Connect(paintGhost) end
		else
			if ghostConn then ghostConn:Disconnect() ghostConn = nil end
			local char = getCharacter()
			if char then
				for _, p in ipairs(char:GetDescendants()) do
					if p:IsA("BasePart") or p:IsA("Decal") then p.LocalTransparencyModifier = 0 end
				end
			end
		end
	end)

	------------------------------------------------------------------
	-- Animation speed (with optional sync to World timelapse)
	------------------------------------------------------------------
	header(7, "Animation Speed")
	Lib.addLabel(page, 8,
		"Speeds up / slows your character's animations. Sync ties the speed to "
		.. "the World tab's timelapse.", 34)

	local animSpeed = 1
	local animSync = false

	local function effectiveAnimSpeed()
		if animSync and ctx.timelapse and ctx.timelapse.enabled then
			-- Map the live (ramping) timelapse speed so anims sit at ~1x normally
			-- and accelerate from there as the timelapse ramps up.
			return math.clamp(1 + ctx.timelapse.speed, 1, 8)
		end
		return animSpeed
	end

	-- Modern games play animations through the Animator, so tracks must be read
	-- from it — Humanoid:GetPlayingAnimationTracks() is deprecated and comes back
	-- empty here, which is why the speed change appeared to do nothing.
	local function getAnimator()
		local humanoid = getHumanoid()
		if not humanoid then return nil end
		return humanoid:FindFirstChildOfClass("Animator")
	end

	local function applyAnimSpeed()
		local animator = getAnimator()
		if not animator then return 0 end
		local speed = effectiveAnimSpeed()
		local tracks = animator:GetPlayingAnimationTracks()
		for _, track in ipairs(tracks) do
			pcall(function() track:AdjustSpeed(speed) end)
		end
		return #tracks
	end

	-- New tracks should inherit the current speed too; rebind on respawn.
	local animPlayedConn
	local function bindAnimator()
		if animPlayedConn then animPlayedConn:Disconnect() animPlayedConn = nil end
		local animator = getAnimator()
		if not animator then return end
		animPlayedConn = animator.AnimationPlayed:Connect(function(track)
			pcall(function() track:AdjustSpeed(effectiveAnimSpeed()) end)
		end)
	end
	bindAnimator()
	LocalPlayer.CharacterAdded:Connect(function()
		task.wait(0.5)
		bindAnimator()
		applyAnimSpeed()
	end)

	local animSlider = Lib.addSlider(page, 9, "Animation Speed", 0.25, 4, 1, function(v)
		animSpeed = v
		local n = applyAnimSpeed()
		print(("[Mirage] animation speed %.2fx → %d playing track(s)"):format(v, n))
	end)
	local animSyncToggle = Lib.addToggleRow(page, 10, "Sync to World timelapse", false, function(state)
		animSync = state
		applyAnimSpeed()
	end)

	-- Re-assert the speed every frame. A game's default Animate script calls
	-- AdjustSpeed itself each frame (to scale walk/run by WalkSpeed), so a
	-- one-shot set is immediately clobbered — we only "stick" by winning every
	-- frame while a non-1x speed (or an active timelapse sync) is in effect.
	RunService.Heartbeat:Connect(function()
		if animSync then
			if ctx.timelapse and ctx.timelapse.enabled then applyAnimSpeed() end
		elseif animSpeed ~= 1 then
			applyAnimSpeed()
		end
	end)

	------------------------------------------------------------------
	-- Animation FastFlags
	------------------------------------------------------------------
	header(11, "Animation FFlags")
	Lib.addLabel(page, 12,
		"Applies smoothing / full-quality animation FastFlags via your executor. "
		.. "Most take effect after a rejoin. No-ops if unsupported.", 46)

	local fflagStatus = Lib.addLabel(page, 13, "", 18)

	-- Community animation FastFlags: keep characters animating at full quality
	-- regardless of distance and smooth interpolation. Unknown names just fail
	-- the per-flag pcall, so the list is safe to be generous.
	local ANIM_FFLAGS = {
		DFIntInterpolationNumFramesDelayed       = "2",
		FIntAnimationLodFacsDistanceMin          = "1000",
		FIntAnimationLodFacsDistanceMax          = "5000",
		FIntAnimationLodRenderDistanceMin        = "1000",
		FIntAnimationLodRenderDistanceMax        = "5000",
		FIntPlayerCharacterDistanceToAnimateFully = "10000",
		FFlagAnimationWeightedBlendFix           = "true",
		DFFlagSimNoRotationDriftWithoutThrottling = "true",
	}

	Lib.addButtonRow(page, 14, {
		{ text = "Apply FFlags", width = 120, callback = function()
			local applied = 0
			for name, value in pairs(ANIM_FFLAGS) do
				-- setfflag is an executor global; the pcall both calls it and
				-- guards the case where it doesn't exist at all.
				if pcall(function() setfflag(name, value) end) then
					applied += 1
				end
			end
			fflagStatus.Text = applied > 0
				and ("Applied " .. applied .. " FFlags (rejoin to take full effect)")
				or "FastFlags not supported by this executor"
		end },
	})

	------------------------------------------------------------------
	-- Performance / FPS booster
	------------------------------------------------------------------
	header(15, "Performance")
	Lib.addLabel(page, 16,
		"Strip visual effects to boost FPS. Stays on for newly-spawned parts too. "
		.. "Rejoin to fully restore visuals.", 46)

	local boosting = false
	local boostConn

	local function stripOne(obj)
		pcall(function()
			if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Smoke")
				or obj:IsA("Fire") or obj:IsA("Sparkles") or obj:IsA("Beam") then
				obj.Enabled = false
			elseif obj:IsA("Decal") or obj:IsA("Texture") then
				obj.Transparency = 1
			elseif obj:IsA("MeshPart") then
				obj.TextureID = ""
				obj.Material = Enum.Material.Plastic
				obj.Reflectance = 0
			elseif obj:IsA("BasePart") then
				obj.Material = Enum.Material.Plastic
				obj.Reflectance = 0
			end
		end)
	end

	local function applyBoost()
		pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
		pcall(function() Lighting.GlobalShadows = false end)
		pcall(function() Lighting.FogEnd = 1e9 end)
		pcall(function()
			local terrain = Workspace:FindFirstChildOfClass("Terrain")
			if terrain then
				terrain.WaterWaveSize = 0
				terrain.WaterWaveSpeed = 0
				terrain.WaterReflectance = 0
				terrain.WaterTransparency = 1
			end
		end)
		for _, e in ipairs(Lighting:GetChildren()) do
			if e:IsA("PostEffect") then pcall(function() e.Enabled = false end) end
		end
		for _, obj in ipairs(Workspace:GetDescendants()) do
			stripOne(obj)
		end
	end

	Lib.addToggleRow(page, 17, "FPS Boost (strip effects)", false, function(state)
		boosting = state
		if state then
			applyBoost()
			if not boostConn then
				boostConn = Workspace.DescendantAdded:Connect(function(obj)
					if boosting then stripOne(obj) end
				end)
			end
		else
			if boostConn then boostConn:Disconnect() boostConn = nil end
		end
	end)

	Lib.addSlider(page, 18, "FPS Cap", 30, 360, 60, function(v)
		pcall(function() setfpscap(math.floor(v)) end)
	end)

	------------------------------------------------------------------
	-- Anti-idle
	------------------------------------------------------------------
	header(19, "Anti-Idle")
	Lib.addLabel(page, 20,
		"Stops the ~20-minute AFK kick by nudging the controller when you go idle.", 34)

	local VirtualUser = game:GetService("VirtualUser")
	local idledConn
	Lib.addToggleRow(page, 21, "Anti-Idle (no AFK kick)", false, function(state)
		if state then
			if not idledConn then
				idledConn = LocalPlayer.Idled:Connect(function()
					pcall(function()
						VirtualUser:CaptureController()
						VirtualUser:ClickButton2(Vector2.new())
					end)
				end)
			end
		else
			if idledConn then idledConn:Disconnect() idledConn = nil end
		end
	end)

	------------------------------------------------------------------
	-- Reset
	------------------------------------------------------------------
	ctx.onReset(function()
		animSpeed = 1
		animSync = false
		animSlider.set(1, false)
		animSyncToggle.set(false, false)
		applyAnimSpeed()
		if ghostOn then ghostToggle.set(false) end
	end)
end
