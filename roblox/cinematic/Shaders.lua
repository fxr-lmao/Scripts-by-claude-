--[[
	cinematic/Shaders.lua
	Lighting post-effects: ColorCorrection, Bloom, Blur, DepthOfField, SunRays.
	One-click presets plus manual sliders.

	Bloom note: BloomEffect only glows pixels brighter than its Threshold.
	The engine default (2.0) is so high that in most games nothing is bright
	enough to bloom — which is why it can look like "bloom does nothing". We
	keep the threshold low (~0.9) so the glow is actually visible, and the
	Bloom slider drives Intensity on top of that.
--]]

local Lighting = game:GetService("Lighting")

return function(ctx, Lib)
	local page = ctx.addTab("Shaders", 2)

	local fx = {
		colorCorrection = Lib.make("ColorCorrectionEffect", { Name = "CinematicHub_ColorCorrection" }, Lighting),
		bloom           = Lib.make("BloomEffect",           { Name = "CinematicHub_Bloom" }, Lighting),
		blur            = Lib.make("BlurEffect",            { Name = "CinematicHub_Blur", Size = 0 }, Lighting),
		dof             = Lib.make("DepthOfFieldEffect",    { Name = "CinematicHub_DepthOfField" }, Lighting),
		sunRays         = Lib.make("SunRaysEffect",         { Name = "CinematicHub_SunRays", Intensity = 0 }, Lighting),
	}

	-- A low, fixed bloom threshold so the Bloom slider always produces a
	-- visible glow regardless of the game's brightness.
	local BLOOM_THRESHOLD = 0.9

	local function cc(b, c, s, tint)
		fx.colorCorrection.Brightness = b
		fx.colorCorrection.Contrast   = c
		fx.colorCorrection.Saturation = s
		fx.colorCorrection.TintColor  = tint or Color3.new(1, 1, 1)
	end
	local function bloom(intensity, size)
		fx.bloom.Intensity = intensity
		fx.bloom.Size      = size or 24
		fx.bloom.Threshold = BLOOM_THRESHOLD
	end
	local function dof(far, focusRadius, near)
		fx.dof.FarIntensity, fx.dof.InFocusRadius, fx.dof.NearIntensity = far, focusRadius, near
	end

	local PRESETS = {
		Default = function()
			cc(0, 0, 0); bloom(0); fx.blur.Size = 0; dof(0, 50, 0)
			fx.sunRays.Intensity, fx.sunRays.Spread = 0, 0.5
		end,
		Cinematic = function()
			cc(-0.02, 0.15, -0.1, Color3.fromRGB(255, 244, 230)); bloom(0.7, 18)
			fx.blur.Size = 0; dof(0.4, 35, 0); fx.sunRays.Intensity, fx.sunRays.Spread = 0.15, 0.6
		end,
		Noir = function()
			cc(-0.05, 0.35, -1); bloom(0.4, 16); fx.blur.Size = 0; dof(0.3, 40, 0)
			fx.sunRays.Intensity, fx.sunRays.Spread = 0, 0.5
		end,
		Warm = function()
			cc(0.03, 0.08, 0.15, Color3.fromRGB(255, 210, 160)); bloom(0.5, 20)
			fx.blur.Size = 0; dof(0.2, 45, 0); fx.sunRays.Intensity, fx.sunRays.Spread = 0.25, 0.7
		end,
		Cold = function()
			cc(-0.02, 0.1, -0.05, Color3.fromRGB(170, 210, 255)); bloom(0.45, 18)
			fx.blur.Size = 0; dof(0.25, 40, 0); fx.sunRays.Intensity, fx.sunRays.Spread = 0, 0.5
		end,
		Dreamy = function()
			cc(0.05, -0.05, 0.1, Color3.fromRGB(255, 235, 250)); bloom(1.3, 32)
			fx.blur.Size = 4; dof(0.6, 25, 0.1); fx.sunRays.Intensity, fx.sunRays.Spread = 0.3, 0.8
		end,
		Horror = function()
			cc(-0.2, 0.3, -0.6, Color3.fromRGB(190, 220, 200)); bloom(0.3, 12)
			fx.blur.Size = 1; dof(0.7, 20, 0); fx.sunRays.Intensity, fx.sunRays.Spread = 0, 0.5
		end,
		Vintage = function()
			cc(0.02, 0.12, -0.35, Color3.fromRGB(255, 225, 190)); bloom(0.5, 22)
			fx.blur.Size = 0; dof(0.3, 40, 0); fx.sunRays.Intensity, fx.sunRays.Spread = 0.2, 0.65
		end,
		Vaporwave = function()
			cc(0.04, 0.1, 0.45, Color3.fromRGB(255, 190, 245)); bloom(1.0, 28)
			fx.blur.Size = 0; dof(0.4, 35, 0); fx.sunRays.Intensity, fx.sunRays.Spread = 0.25, 0.75
		end,
	}

	-- Neutralize on load (Bloom/DepthOfField ship with non-zero defaults that
	-- would otherwise glow/blur the screen the instant they're parented).
	PRESETS.Default()

	local presetOrder = {
		"Default", "Cinematic", "Noir", "Warm",
		"Cold", "Dreamy", "Horror", "Vintage", "Vaporwave",
	}
	local defs = {}
	for _, name in ipairs(presetOrder) do
		defs[#defs + 1] = { text = name, width = 84, callback = function() PRESETS[name]() end }
	end

	Lib.addLabel(page, 1, "Presets")
	-- chunk into rows of 3
	local order = 2
	for i = 1, #defs, 3 do
		local rowDefs = {}
		for j = i, math.min(i + 2, #defs) do rowDefs[#rowDefs + 1] = defs[j] end
		Lib.addButtonRow(page, order, rowDefs)
		order += 1
	end

	Lib.addLabel(page, order, "Manual"); order += 1
	Lib.addSlider(page, order, "Bloom (glow)", 0, 3, 0, function(v)
		fx.bloom.Intensity = v
		fx.bloom.Threshold = BLOOM_THRESHOLD
	end); order += 1
	Lib.addSlider(page, order, "Blur", 0, 24, 0, function(v) fx.blur.Size = v end); order += 1
	Lib.addSlider(page, order, "Brightness", -0.5, 0.5, 0, function(v) fx.colorCorrection.Brightness = v end); order += 1
	Lib.addSlider(page, order, "Contrast", -1, 1, 0, function(v) fx.colorCorrection.Contrast = v end); order += 1
	Lib.addSlider(page, order, "Saturation", -1, 1, 0, function(v) fx.colorCorrection.Saturation = v end); order += 1
	Lib.addSlider(page, order, "Sun Rays", 0, 1, 0, function(v) fx.sunRays.Intensity = v end); order += 1

	-- expose for Extras' Reset All
	ctx.shaderReset = PRESETS.Default
	ctx.onReset(PRESETS.Default)
end
