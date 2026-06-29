--[[
	cinematic/Client.lua
	Client-side tools tab: skin changer (copy a user's avatar or a preset),
	animation speed (with optional sync to the World timelapse), an animation
	pack / gait swap, a performance / FPS booster, and an anti-idle (no AFK kick).

	Everything here is local-only. The FPS cap and anti-idle lean on executor /
	client APIs (setfpscap, VirtualUser) — each is pcall-guarded so anything the
	runtime doesn't support quietly no-ops instead of erroring.
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
		-- This game neither honours AddAccessory nor auto-welds on parent, so we
		-- weld each accessory ourselves: match its Handle's attachment to the
		-- same-named attachment on the character and create the weld by hand
		-- (exactly what the engine does internally).
		local function weldAccessory(accessory)
			local handle = accessory:FindFirstChild("Handle")
			if not handle then accessory.Parent = char return end
			for _, w in ipairs(handle:GetChildren()) do
				if w:IsA("Weld") or w:IsA("Motor6D") or w:IsA("ManualWeld") then w:Destroy() end
			end
			local accAtt = handle:FindFirstChildWhichIsA("Attachment")
			local charAtt
			if accAtt then
				for _, d in ipairs(char:GetDescendants()) do
					if d:IsA("Attachment") and d.Name == accAtt.Name and d.Parent ~= handle then
						charAtt = d
						break
					end
				end
			end
			accessory.Parent = char
			if accAtt and charAtt and charAtt.Parent then
				local weld = Instance.new("Weld")
				weld.Name = "MirageAccessoryWeld"
				weld.Part0 = handle
				weld.Part1 = charAtt.Parent
				weld.C0 = accAtt.CFrame
				weld.C1 = charAtt.CFrame
				weld.Parent = handle
				pcall(function() handle.Massless = true end)
				pcall(function() handle.CanCollide = false end)
			end
		end

		local counts = {}
		for _, item in ipairs(items) do
			counts[item.ClassName] = (counts[item.ClassName] or 0) + 1
			if item:IsA("Accessory") then
				pcall(weldAccessory, item)
			else
				pcall(function() item.Parent = char end)
			end
		end
		local summary = {}
		for cls, n in pairs(counts) do table.insert(summary, n .. "x " .. cls) end
		print("[Mirage] appearance items: "
			.. (#summary > 0 and table.concat(summary, ", ") or "none returned"))
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
	-- Animation Pack (swap your gait — client-side, no FastFlags)
	------------------------------------------------------------------
	header(11, "Animation Pack")
	Lib.addLabel(page, 12,
		"Swaps your walk / run / idle / jump animations via the Animate script — "
		.. "purely client-side, no FastFlags. Default restores yours. (Some "
		.. "executors sanitise custom animation ids; check the console if a pack "
		.. "doesn't take.)", 64)

	local animPackStatus = Lib.addLabel(page, 13, "", 18)

	-- folder.child → asset id, matching the default R15 Animate script's nodes.
	-- We set each AnimationId then restart Animate so it reloads from them.
	local function pack(idle1, idle2, walk, run, jump, fall, climb)
		return {
			["idle.Animation1"] = idle1, ["idle.Animation2"] = idle2,
			["walk.WalkAnim"] = walk, ["run.RunAnim"] = run,
			["jump.JumpAnim"] = jump, ["fall.FallAnim"] = fall,
			["climb.ClimbAnim"] = climb,
		}
	end
	-- Official Roblox animation-package ids (R15). Best-effort; a wrong id just
	-- leaves that motion on default, and the Default button restores everything.
	local PACKS = {
		Ninja      = pack(656117400, 656118341, 656121766, 656118852, 656117878, 656115606, 656114359),
		Zombie     = pack(616158929, 616160636, 616168032, 616163682, 616161997, 616157476, 616156119),
		Werewolf   = pack(1083445855, 1083450166, 1083473930, 1083462077, 1083455352, 1083443587, 1083439238),
		Robot      = pack(616088211, 616089559, 616095330, 616091570, 616090535, 616087271, 616086904),
		Astronaut  = pack(891621366, 891633237, 891667138, 891636393, 891627522, 891617961, 891609353),
		Mage       = pack(707742142, 707855907, 707897309, 707861613, 707853694, 707844760, 707826056),
		Levitation = pack(616006778, 616008087, 616013216, 616010382, 616008936, 616005863, 616003713),
		Pirate     = pack(750781874, 750782770, 750785693, 750783738, 750782230, 750780242, 750779492),
		Stylish    = pack(1069977950, 1069987858, 1070017263, 1070001516, 1069984528, 1069973677, 1069946257),
		Superhero  = pack(1510925809, 1510923170, 1510936671, 1510929263, 1510920302, 1510914848, 1510938553),
		Toy        = pack(782841498, 782845736, 782843345, 782842708, 782847596, 782846268, 782843869),
		Bubbly     = pack(910004836, 910009958, 910034870, 910025107, 910016857, 910001910, 909997997),
		Oldschool  = pack(845397899, 845400520, 845403764, 845398858, 845398624, 845396048, 845392650),
	}

	-- Snapshot the current (default) ids so "Default" can restore them; recapture
	-- on respawn since the Animate script is rebuilt with a fresh set.
	local defaultIds = {}
	local function captureDefault()
		local char = getCharacter()
		local animate = char and char:FindFirstChild("Animate")
		if not animate then return end
		defaultIds = {}
		for _, folder in ipairs({ "idle", "walk", "run", "jump", "fall", "climb" }) do
			local f = animate:FindFirstChild(folder)
			if f then
				for _, a in ipairs(f:GetChildren()) do
					if a:IsA("Animation") then defaultIds[folder .. "." .. a.Name] = a.AnimationId end
				end
			end
		end
	end
	captureDefault()
	LocalPlayer.CharacterAdded:Connect(function()
		task.wait(1)
		captureDefault()
	end)

	local function applyPack(map, isDefault)
		local char = getCharacter()
		local animate = char and char:FindFirstChild("Animate")
		if not animate then return false, "no Animate script (R6 / custom rig)" end
		for path, id in pairs(map) do
			local folder, child = path:match("^(%w+)%.(%w+)$")
			local f = folder and animate:FindFirstChild(folder)
			local a = f and f:FindFirstChild(child)
			if a and a:IsA("Animation") then
				local assetId = isDefault and id or ("rbxassetid://" .. id)
				pcall(function() a.AnimationId = assetId end)
			end
		end
		-- restart Animate so the new ids are reloaded
		pcall(function()
			animate.Disabled = true
			task.wait(0.05)
			animate.Disabled = false
		end)
		return true
	end

	local function pickPack(name)
		task.spawn(function()
			local ok, err
			if name == "Default" then
				ok, err = applyPack(defaultIds, true)
			else
				ok, err = applyPack(PACKS[name], false)
			end
			animPackStatus.Text = ok and ("Pack: " .. name) or ("Pack failed: " .. tostring(err))
			print("[Mirage] anim pack " .. name .. (ok and " applied" or (" failed: " .. tostring(err))))
		end)
	end

	local packGrid = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 14,
	}, page)
	make("UIGridLayout", {
		CellSize = UDim2.new(0, 84, 0, 28),
		CellPadding = UDim2.new(0, 6, 0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, packGrid)

	local packOrder = { "Default", "Ninja", "Zombie", "Werewolf", "Robot",
		"Astronaut", "Mage", "Levitation", "Pirate", "Stylish", "Superhero",
		"Toy", "Bubbly", "Oldschool" }
	for i, name in ipairs(packOrder) do
		local b = make("TextButton", {
			BackgroundColor3 = THEME.PanelAlt,
			TextColor3 = THEME.Text,
			Font = Lib.bodyFont,
			TextSize = 12,
			Text = name,
			LayoutOrder = i,
			AutoButtonColor = true,
		}, packGrid)
		Lib.corner(b, 6)
		b.Activated:Connect(function() pickPack(name) end)
	end

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
