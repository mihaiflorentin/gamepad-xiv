local _, ns = ...

-- Crossbar themes. They only change how the slots look, never where they are.
--   classic: the game's standard action button art, as before themes existed.
--   forever: like Forever's own bar: square D-pad slots, round face button slots, Forever's borders,
--            and the D-pad arrow or face button glyph in an empty slot.
--   round:   every slot round, with Forever's round borders.
--   minimal: flat square icons on a thin dark edge, with no frames.
--   orb, hex, sigil, holo, ink: the addon's own art, see below.
-- Each theme also picks a background, a background border, a slot fill and a slot border. Those settings
-- can each be set to "From theme" (the default) or to a style of their own.
-- Only textures change, which addon code may do on these secure buttons even in combat.

ns.THEMES = {
	{ "classic", "Classic" },
	{ "forever", "Forever" },
	{ "round", "Round" },
	{ "hex", "Hex" },
	{ "sigil", "Sigil" },
	{ "holo", "Holo" },
	{ "ink", "Ink" },
	{ "orb", "Orb" },
	{ "minimal", "Minimal" },
}

-- What each theme uses for the settings left on "From theme".
local PRESETS = {
	classic = { background = "none", backgroundBorder = "none", slotFill = "none", slotBorder = "none" },
	forever = { background = "shadow", backgroundBorder = "none", slotFill = "none", slotBorder = "none" },
	round = { background = "shadow", backgroundBorder = "none", slotFill = "glass", slotBorder = "none" },
	orb = { background = "none", backgroundBorder = "none", slotFill = "dark", slotBorder = "none" },
	hex = { background = "hex", backgroundBorder = "hex", slotFill = "dark", slotBorder = "none" },
	sigil = { background = "vignette", backgroundBorder = "runes", slotFill = "dark", slotBorder = "none" },
	holo = { background = "holo", backgroundBorder = "holo", slotFill = "scan", slotBorder = "none" },
	ink = { background = "ink", backgroundBorder = "none", slotFill = "dark", slotBorder = "none" },
	minimal = { background = "none", backgroundBorder = "none", slotFill = "dark", slotBorder = "none" },
}

-- Themes that were removed, and what replaces them.
local RENAMED = { sleek = "round", rounded = "round", slate = "round", halo = "round", neon = "round", glass = "round" }

local function CurrentTheme()
	local theme = ns.db and ns.db.theme or "classic"
	theme = RENAMED[theme] or theme
	return PRESETS[theme] and theme or "classic"
end

-- A crossbar look setting: its own value, or the theme's when it is "theme".
local function Look(key)
	local value = ns.db and ns.db[key] or "theme"
	if value == "theme" then
		return PRESETS[CurrentTheme()][key]
	end
	return value
end
ns.ThemeLook = Look

local MEDIA = "Interface\\AddOns\\GamepadXIV\\Media\\"

local SQUARE = {
	normal = "gamepad-actionbar-squareslot-border-normal",
	pushed = "gamepad-actionbar-squareslot-border-pressed",
	highlight = "gamepad-actionbar-squareslot-border-hover",
	checked = "gamepad-actionbar-squareslot-border-selected",
	shadow = "gamepad-actionbar-squareslot-dropshadow",
	mask = "Interface\\Buttons\\WHITE8X8",
	inset = 0.08, -- fraction of the slot the icon stays inside the border on each side
}
local CIRCLE = {
	normal = "gamepad-actionbar-circleslot-border-normal",
	pushed = "gamepad-actionbar-circleslot-border-pressed",
	highlight = "gamepad-actionbar-circleslot-border-hover",
	checked = "gamepad-actionbar-circleslot-border-selected",
	shadow = "gamepad-actionbar-circleslot-dropshadow",
	mask = "Interface\\CharacterFrame\\TempPortraitAlphaMask",
	inset = 0.11,
}

-- Minimal: smaller square icons with room between them, on a thin dark border.
local MINIMAL = {
	mask = "Interface\\Buttons\\WHITE8X8",
	inset = 0.14,
	border = 0.045, -- border width, as a fraction of the slot
}

-- The addon's own themes. Sizes are fractions of the slot: icon is the icon's width, and each layer
-- has a size and an alpha. outline is the slot's shape for borders and the cooldown sweep.
-- frame is { file, size, r, g, b, a } (r = "accent" for the highlight color, then g is the alpha);
-- glow is { file, size, alpha, r, g, b }, in the highlight color when r is left out.
--   hex:   hexagon icons with a fine light edge, on a dark hexagon with a double outline per group.
--   sigil: round icons in a gold double ring with four studs, inside an engraved ring of runes.
--   holo:  rounded square icons in cyan corner brackets, scanlines in empty slots, a dashed ring per group.
--   ink:   round icons in rough brushed ink rings, on a splattered ink wash.
--   orb:   round icons in a thick metal bezel lit from the top, on a soft drop shadow.
local MODERN = {
	hex = {
		mask = MEDIA .. "hex_mask", icon = 0.92, outline = "hex",
		frame = { MEDIA .. "hex_ring", 0.92, 0.8, 0.88, 1, 0.9 },
		inner = { MEDIA .. "hex_inner", 0.92, 0.6 },
		shadow = { MEDIA .. "shadow_round", 1.35, 0.55 },
		hover = MEDIA .. "hex_glow",
	},
	sigil = {
		mask = MEDIA .. "circle_mask", icon = 0.8, outline = "round",
		frame = { MEDIA .. "sigil_ring", 1, 1, 0.84, 0.52, 0.95 },
		inner = { MEDIA .. "inner_shadow", 0.8, 0.6 },
		shadow = { MEDIA .. "shadow_round", 1.4, 0.6 },
		hover = MEDIA .. "ring_glow",
	},
	holo = {
		mask = MEDIA .. "rsquare_mask", icon = 0.8, outline = "rsquare",
		frame = { MEDIA .. "holo_brackets", 1, 0.35, 0.9, 1, 1 },
		inner = { MEDIA .. "rsquare_inner_shadow", 0.8, 0.45 },
		glow = { MEDIA .. "rsquare_glow", 0.92, 0.25, 0.35, 0.9, 1 },
		hover = MEDIA .. "rsquare_glow",
	},
	ink = {
		mask = MEDIA .. "circle_mask", icon = 0.8, outline = "round",
		frame = { MEDIA .. "ink_ring", 1.06, 1, 1, 1, 1 },
		inner = { MEDIA .. "inner_shadow", 0.8, 0.55 },
		hover = MEDIA .. "ring_glow",
	},
	orb = {
		mask = MEDIA .. "circle_mask", icon = 0.8, outline = "round",
		frame = { MEDIA .. "bezel_round", 1.0, 1, 1, 1, 1 },
		inner = { MEDIA .. "inner_shadow", 0.8, 0.5 },
		shadow = { MEDIA .. "shadow_round", 1.55, 0.75 },
		hover = MEDIA .. "ring_glow",
	},
}
for _, spec in pairs(MODERN) do
	spec.inset = (1 - spec.icon) / 2
end

-- Forever's empty slot art, used when its own lookup is not available.
local FALLBACK_EMPTY = {
	"gamepad-actionbar-squareslot-generic-dpadleft-normal",
	"gamepad-actionbar-squareslot-generic-dpadup-normal",
	"gamepad-actionbar-squareslot-generic-dpadright-normal",
	"gamepad-actionbar-squareslot-generic-dpaddown-normal",
	"gamepad-actionbar-circleslot-xbox-x-normal",
	"gamepad-actionbar-circleslot-xbox-y-normal",
	"gamepad-actionbar-circleslot-xbox-b-normal",
	"gamepad-actionbar-circleslot-xbox-a-normal",
}

-- The empty slot art for the controller in use, as Forever picks it. Slot indexes match Forever's:
-- 1-4 D-pad left, up, right, down; 5-8 face left, top, right, bottom.
local function EmptySlotAtlas(index, round)
	local sets, manager = INPUT_DEVICE_ACTION_BUTTON_TEXTURE_SETS, InputDeviceIconSetManager
	local set = sets and manager and manager.GetActiveInputDeviceIconSet and sets[manager:GetActiveInputDeviceIconSet()]
	if set then
		local ok, atlas
		if index > 4 then
			ok, atlas = pcall(set.GetEmptySlotCircleBackgroundTextureByIndex, set, index)
		elseif not round then
			ok, atlas = pcall(set.GetEmptySlotSquareBackgroundTextureByIndex, set, index)
		end
		if ok and atlas then
			return atlas
		end
	end
	if index <= 4 and round then
		return nil
	end
	return FALLBACK_EMPTY[index]
end

local REGIONS = { "NormalTexture", "PushedTexture", "HighlightTexture", "CheckedTexture", "SlotArt", "SlotBackground", "Border" }

local function GetRegion(button, key)
	if key == "NormalTexture" then
		return button:GetNormalTexture()
	elseif key == "PushedTexture" then
		return button:GetPushedTexture()
	elseif key == "HighlightTexture" then
		return button:GetHighlightTexture()
	elseif key == "CheckedTexture" then
		return button:GetCheckedTexture()
	end
	return button[key]
end

-- The standard art of each region, kept so the Classic theme can put it back.
local function SaveOriginal(button)
	if button.themeOriginal then
		return
	end
	local original = {}
	for _, key in ipairs(REGIONS) do
		local region = GetRegion(button, key)
		if region then
			local points = {}
			for i = 1, region:GetNumPoints() do
				points[i] = { region:GetPoint(i) }
			end
			original[key] = {
				atlas = region.GetAtlas and region:GetAtlas(),
				texture = region:GetTexture(),
				points = points,
				alpha = region:GetAlpha(),
				blend = region:GetBlendMode(),
			}
		end
	end
	button.themeOriginal = original
end

local function Restore(button)
	for key, saved in pairs(button.themeOriginal) do
		local region = GetRegion(button, key)
		if region then
			if saved.atlas then
				region:SetAtlas(saved.atlas)
			elseif saved.texture then
				region:SetTexture(saved.texture)
			end
			region:ClearAllPoints()
			for _, point in ipairs(saved.points) do
				region:SetPoint(unpack(point))
			end
			region:SetAlpha(saved.alpha)
			region:SetBlendMode(saved.blend)
			region:SetVertexColor(1, 1, 1, 1)
		end
	end
end

local function SetArt(button, key, atlas)
	local region = GetRegion(button, key)
	if not region then
		return
	end
	if atlas then
		region:SetAtlas(atlas)
		region:ClearAllPoints()
		region:SetAllPoints(button)
		region:SetAlpha(1)
	else
		region:SetAlpha(0)
	end
end

-- Moves the icon (and the range tint drawn over it) onto the given mask.
local function UseMask(button, mask)
	local icon = button.icon
	local masks = { button.IconMask }
	local shapes = { SQUARE, CIRCLE, MINIMAL }
	for _, spec in pairs(MODERN) do
		tinsert(shapes, spec)
	end
	for _, shape in ipairs(shapes) do
		if shape.maskKey and button[shape.maskKey] then
			tinsert(masks, button[shape.maskKey])
		end
	end
	local regions = { icon, button.rangeTint }
	for _, existing in ipairs(masks) do
		for _, region in pairs(regions) do
			region:RemoveMaskTexture(existing)
		end
	end
	if mask then
		for _, region in pairs(regions) do
			region:AddMaskTexture(mask)
		end
	end
end

-- The game snaps textures to whole screen pixels. On scaled buttons that resamples the icon a second
-- time and makes it look low resolution, so the icon, its masks and the theme art draw unsnapped.
local function NoSnap(region)
	if region and region.SetSnapToPixelGrid then
		region:SetSnapToPixelGrid(false)
		region:SetTexelSnappingBias(0)
	end
end

local function GetMask(button, shape)
	shape.maskKey = shape.maskKey or ("themeMask" .. tostring(shape):gsub("[^%w]", ""))
	local key = shape.maskKey
	if not button[key] then
		local mask = button:CreateMaskTexture()
		-- Full size mask files rather than the small mask atlases, which made icons look blurry.
		mask:SetTexture(shape.mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		NoSnap(mask)
		-- Forever's border is drawn a little inside the slot, so the icon is cut to fit within it.
		local inset = button:GetWidth() * shape.inset
		mask:SetPoint("TOPLEFT", button.icon, "TOPLEFT", inset, -inset)
		mask:SetPoint("BOTTOMRIGHT", button.icon, "BOTTOMRIGHT", -inset, inset)
		button[key] = mask
	end
	return button[key]
end

-- Icons carry a thin border of their own; cropping it keeps them sharp inside the themed slots.
local function CropIcon(button, crop)
	NoSnap(button.icon)
	if crop then
		button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	else
		button.icon:SetTexCoord(0, 1, 0, 1)
	end
end

-- Fills inside each slot, under the icon, so empty slots are not see-through.
ns.SLOT_FILLS = {
	{ "none", "None" },
	{ "dark", "Dark" },
	{ "smoke", "Smoke" },
	{ "gradient", "Gradient" },
	{ "glass", "Glass" },
	{ "tint", "Highlight color" },
	{ "deep", "Deep" },
	{ "frost", "Frost" },
	{ "scan", "Scanlines" },
}

local function ApplyFill(button, shape)
	local style = Look("slotFill")
	local fill = button.themeFill
	if not fill then
		fill = button:CreateTexture(nil, "BACKGROUND", nil, -1)
		button.themeFill = fill
	end
	fill:Hide()
	if fill.themeMask then
		fill:RemoveMaskTexture(fill.themeMask)
		fill.themeMask = nil
	end
	if style == "none" then
		return false
	end
	fill:ClearAllPoints()
	fill:SetAllPoints(button.icon)
	fill:SetBlendMode("BLEND")
	fill:SetGradient("VERTICAL", CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1))
	if style == "dark" then
		fill:SetColorTexture(0.04, 0.04, 0.06, 0.9)
	elseif style == "smoke" then
		fill:SetColorTexture(0.22, 0.22, 0.25, 0.75)
	elseif style == "gradient" then
		fill:SetColorTexture(1, 1, 1, 1)
		fill:SetGradient("VERTICAL", CreateColor(0.02, 0.02, 0.04, 0.95), CreateColor(0.2, 0.2, 0.26, 0.9))
	elseif style == "glass" then
		fill:SetColorTexture(0.55, 0.7, 1, 0.22)
	elseif style == "tint" then
		local color = ns.GetHighlightColor and { ns.GetHighlightColor() } or { 1, 0.82, 0.25 }
		fill:SetColorTexture(color[1], color[2], color[3], 0.35)
	elseif style == "deep" then
		fill:SetTexture(MEDIA .. "slot_deep")
		fill:SetVertexColor(1, 1, 1, 1)
	elseif style == "frost" then
		fill:SetTexture(MEDIA .. "slot_frost")
		fill:SetVertexColor(1, 1, 1, 1)
	elseif style == "scan" then
		fill:SetTexture(MEDIA .. "holo_scan")
		fill:SetVertexColor(1, 1, 1, 1)
	end
	local mask = shape and GetMask(button, shape) or button.IconMask
	if mask then
		fill:AddMaskTexture(mask)
		fill.themeMask = mask
	end
	fill:Show()
	return true
end

local function GetExtras(button)
	if not button.themeShadow then
		button.themeShadow = button:CreateTexture(nil, "BACKGROUND", nil, -8)
		button.themeShadow:SetPoint("TOPLEFT", -6, 6)
		button.themeShadow:SetPoint("BOTTOMRIGHT", 6, -6)
		button.themeEdge = button:CreateTexture(nil, "BACKGROUND", nil, -7)
		button.themeEdge:SetPoint("TOPLEFT", -2, 2)
		button.themeEdge:SetPoint("BOTTOMRIGHT", 2, -2)
		button.themeEdge:SetColorTexture(0, 0, 0, 0.85)
		button.themeEmpty = button:CreateTexture(nil, "BACKGROUND", nil, -6)
		button.themeEmpty:SetAllPoints()
		button.themeEmpty:SetColorTexture(0.05, 0.05, 0.07, 0.55)
		button.themeInner = button:CreateTexture(nil, "ARTWORK", nil, 1)
		button.themeRing = button:CreateTexture(nil, "OVERLAY", nil, 1)
		button.themeGloss = button:CreateTexture(nil, "OVERLAY", nil, 2)
		button.themeGloss:SetBlendMode("ADD")
		button.themeSlotBorder = button:CreateTexture(nil, "OVERLAY", nil, 3)
		for _, key in ipairs({ "themeShadow", "themeInner", "themeRing", "themeGloss", "themeSlotBorder" }) do
			NoSnap(button[key])
		end
	end
	for _, key in ipairs({ "themeShadow", "themeEdge", "themeEmpty", "themeInner", "themeRing", "themeGloss", "themeSlotBorder" }) do
		button[key]:Hide()
	end
	button.themeShadow:SetVertexColor(1, 1, 1, 1)
	button.themeShadow:SetAlpha(1)
	button.themeShadow:SetBlendMode("BLEND")
	button.themeShadow:ClearAllPoints()
	button.themeShadow:SetPoint("TOPLEFT", -6, 6)
	button.themeShadow:SetPoint("BOTTOMRIGHT", 6, -6)
end

-- Places a texture over the icon's visible area, grown or shrunk by a scale around its centre.
local function FitToIcon(button, texture, inset, scale)
	local size = button:GetWidth()
	local half = size * (1 - 2 * inset) / 2 * (scale or 1)
	texture:ClearAllPoints()
	texture:SetPoint("CENTER", button.icon, "CENTER")
	texture:SetSize(half * 2, half * 2)
end

local function UseMaskOn(texture, button, shape)
	if texture.themeMask then
		texture:RemoveMaskTexture(texture.themeMask)
	end
	texture.themeMask = GetMask(button, shape)
	texture:AddMaskTexture(texture.themeMask)
end

local SWIPE_SQUARE = "Interface\\Buttons\\WHITE8X8"

-- The cooldown sweep follows the icon's size. It is a frame, so it only moves out of combat.
local function FitCooldown(button, inset)
	local cooldown = button.cooldown
	if InCombatLockdown() or cooldown.themeInset == inset then
		return
	end
	if not cooldown.themeOriginalPoints then
		local points = {}
		for i = 1, cooldown:GetNumPoints() do
			points[i] = { cooldown:GetPoint(i) }
		end
		cooldown.themeOriginalPoints = points
	end
	cooldown:ClearAllPoints()
	if inset == 0 then
		for _, point in ipairs(cooldown.themeOriginalPoints) do
			cooldown:SetPoint(unpack(point))
		end
	else
		local pixels = button:GetWidth() * inset
		cooldown:SetPoint("TOPLEFT", button.icon, "TOPLEFT", pixels, -pixels)
		cooldown:SetPoint("BOTTOMRIGHT", button.icon, "BOTTOMRIGHT", -pixels, pixels)
	end
	cooldown.themeInset = inset
end
local SWIPE_ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local function ApplyShape(button, index, shape, round)
	Restore(button)
	UseMask(button, GetMask(button, shape))
	SetArt(button, "NormalTexture", shape.normal)
	SetArt(button, "PushedTexture", shape.pushed)
	SetArt(button, "HighlightTexture", shape.highlight)
	SetArt(button, "CheckedTexture", shape.checked)
	SetArt(button, "Border", nil)
	SetArt(button, "SlotBackground", nil)
	local empty = EmptySlotAtlas(index, round)
	SetArt(button, "SlotArt", empty)
	button.themeShadow:SetAtlas(shape.shadow)
	button.themeShadow:Show()
	CropIcon(button, true)
	local filled = ApplyFill(button, shape)
	-- Without glyph art (round D-pad slots) an empty slot gets a plain dark disc instead.
	local hasAction = button.action and HasAction(button.action)
	if not empty and not hasAction and not filled then
		button.themeEmpty:SetShown(true)
		UseMaskOn(button.themeEmpty, button, shape)
	end
	if button.cooldown then
		button.cooldown:SetSwipeTexture(shape == CIRCLE and SWIPE_ROUND or SWIPE_SQUARE)
		button.cooldown:SetSwipeColor(0, 0, 0, 0.8)
		FitCooldown(button, shape.inset)
	end
end

local function AccentColor()
	if ns.GetHighlightColor then
		return ns.GetHighlightColor()
	end
	return 1, 0.82, 0.25
end

-- Places a texture centred on the slot at a size that is a fraction of the slot, a little lower if dy is given.
local function Place(button, texture, size, dy)
	local pixels = button:GetWidth() * size
	texture:ClearAllPoints()
	texture:SetPoint("CENTER", button.icon, "CENTER", 0, dy or 0)
	texture:SetSize(pixels, pixels)
end

local function ApplyModern(button, spec)
	Restore(button)
	UseMask(button, GetMask(button, spec))
	for _, key in ipairs({ "NormalTexture", "PushedTexture", "CheckedTexture", "Border", "SlotArt", "SlotBackground" }) do
		SetArt(button, key, nil)
	end
	CropIcon(button, true)
	local accentR, accentG, accentB = AccentColor()

	local frame = button.themeRing
	local file, size, r, g, b, a = unpack(spec.frame)
	frame:SetTexture(file)
	if r == "accent" then
		frame:SetVertexColor(accentR, accentG, accentB, g)
	else
		frame:SetVertexColor(r, g, b, a)
	end
	Place(button, frame, size)
	frame:Show()

	if spec.inner then
		local file, size, alpha = unpack(spec.inner)
		button.themeInner:SetTexture(file)
		button.themeInner:SetAlpha(alpha)
		Place(button, button.themeInner, size)
		button.themeInner:Show()
	end

	-- Behind the slot: a drop shadow or a glow.
	local shadow = button.themeShadow
	if spec.shadow then
		local file, size, alpha = unpack(spec.shadow)
		shadow:SetTexture(file)
		shadow:SetBlendMode("BLEND")
		shadow:SetAlpha(alpha)
		Place(button, shadow, size, -3)
		shadow:Show()
	elseif spec.glow then
		local file, size, alpha, r, g, b = unpack(spec.glow)
		shadow:SetTexture(file)
		shadow:SetBlendMode("ADD")
		shadow:SetVertexColor(r or accentR, g or accentG, b or accentB, 1)
		shadow:SetAlpha(alpha)
		Place(button, shadow, size)
		shadow:Show()
	end

	local highlight = button:GetHighlightTexture()
	if highlight then
		highlight:SetTexture(spec.hover)
		highlight:SetVertexColor(1, 1, 1, 0.5)
		highlight:SetBlendMode("ADD")
		highlight:SetAlpha(1)
		Place(button, highlight, spec.icon * 1.12)
	end

	local filled = ApplyFill(button, spec)
	if not filled and not (button.action and HasAction(button.action)) then
		button.themeEmpty:Show()
		UseMaskOn(button.themeEmpty, button, spec)
	end
	if button.cooldown then
		button.cooldown:SetSwipeTexture(spec.outline == "round" and SWIPE_ROUND or spec.mask)
		button.cooldown:SetSwipeColor(0, 0, 0, 0.75)
		FitCooldown(button, spec.inset)
	end
end

-- Borders drawn on each slot, on top of the theme, in the slot's own shape.
ns.SLOT_BORDERS = {
	{ "none", "None" },
	{ "thin", "Thin" },
	{ "thick", "Thick" },
	{ "double", "Double" },
	{ "glow", "Glow" },
	{ "accent", "Highlight color" },
}

local SLOT_BORDER_ART = {
	round = { thin = "ring_thin", thick = "ring", double = "ring_double", glow = "ring_glow", accent = "ring_thin" },
	rsquare = { thin = "rsquare_ring_thin", thick = "rsquare_ring", double = "rsquare_ring_double", glow = "rsquare_glow", accent = "rsquare_ring_thin" },
	square = { thin = "square_ring_thin", thick = "square_ring", double = "square_ring_double", glow = "square_glow", accent = "square_ring_thin" },
	hex = { thin = "hex_ring", thick = "hex_ring", double = "hex_ring", glow = "hex_glow", accent = "hex_ring" },
}

-- outline: "round", "rsquare", "square" or "hex", the shape of the slot the border goes around.
local function ApplySlotBorder(button, outline, inset)
	local style = Look("slotBorder")
	local border = button.themeSlotBorder
	if style == "none" then
		border:Hide()
		return
	end
	border:SetTexture(MEDIA .. SLOT_BORDER_ART[outline][style])
	if style == "accent" then
		border:SetVertexColor(AccentColor())
	elseif style == "glow" then
		border:SetVertexColor(1, 1, 1, 0.6)
	else
		border:SetVertexColor(0.9, 0.92, 0.98, 0.75)
	end
	border:SetBlendMode(style == "glow" and "ADD" or "BLEND")
	FitToIcon(button, border, inset, style == "glow" and 1.12 or 1)
	border:Show()
end

-- The cast and channel fill drawn inside a slot is square art; on other slot shapes it gets a mask and
-- glow in that shape instead. The game picks the art at each cast, so this runs after it does.
local SQUARE_FILL_MASK = "UI-HUD-ActionBar-IconFrame-Mask"
local SQUARE_END_MASK = "UI-HUD-ActionBar-CastingChannel-Complete-Mask"

-- The cast fill's mask and inner glow for each slot shape. Square slots keep the game's own art; round
-- slots use Forever's round glow; the other shapes use the theme's own mask and glow in cast colors.
local CAST_SHAPES = {
	round = { mask = "circle_mask" },
	rsquare = { mask = "rsquare_mask", glow = "rsquare_glow" },
	hex = { mask = "hex_mask", glow = "hex_glow" },
}

-- The attack flash: Blizzard blinks a square frame while auto-attack or a pet attack is on. Shaped
-- slots blink a red glow in their own shape instead; Blizzard only shows and hides the texture.
local FLASH_GLOWS = { round = "ring_glow", rsquare = "rsquare_glow", hex = "hex_glow" }

local function ShapeFlash(button)
	local flash = button.Flash
	if not flash then
		return
	end
	if not flash.themeOriginal then
		flash.themeOriginal = { atlas = flash:GetAtlas(), width = flash:GetWidth(), height = flash:GetHeight() }
	end
	local glow = FLASH_GLOWS[button.themeOutline]
	flash:ClearAllPoints()
	if glow then
		local size = button:GetWidth() * (1 - 2 * (button.themeInset or 0))
		flash:SetTexture(MEDIA .. glow)
		flash:SetBlendMode("ADD")
		flash:SetVertexColor(1, 0.15, 0.1, 1)
		flash:SetPoint("CENTER", button.icon, "CENTER")
		flash:SetSize(size, size)
	else
		local original = flash.themeOriginal
		if original.atlas then
			flash:SetAtlas(original.atlas)
		end
		flash:SetBlendMode("BLEND")
		flash:SetVertexColor(1, 1, 1, 1)
		flash:SetPoint("TOPLEFT")
		flash:SetSize(original.width, original.height)
	end
end

local function ShapeCastAnim(button)
	local anim = button.SpellCastAnimFrame
	local fill = anim and anim.Fill
	if not (fill and fill.FillMask and fill.InnerGlowTexture and anim.EndBurst and anim.EndBurst.EndMask) then
		return
	end
	local endMask = anim.EndBurst.EndMask
	local glow = fill.InnerGlowTexture
	if not anim.themeSizes then
		anim.themeSizes = { fill = { fill.FillMask:GetSize() }, finish = { endMask:GetSize() } }
	end
	-- Read before changing the art: the game has just set the cast or channel glow.
	local channel = glow:GetAtlas() == "UI-HUD-ActionBar-Channel-InnerGlow"
	glow:SetVertexColor(1, 1, 1, 1)
	glow:SetBlendMode("BLEND")
	local shape = CAST_SHAPES[button.themeOutline]
	if not shape then
		fill.FillMask:SetAtlas(SQUARE_FILL_MASK)
		fill.FillMask:SetSize(unpack(anim.themeSizes.fill))
		endMask:SetAtlas(SQUARE_END_MASK)
		endMask:SetSize(unpack(anim.themeSizes.finish))
		return
	end
	local size = button:GetWidth() * (1 - 2 * (button.themeInset or 0))
	if shape.glow then
		glow:SetTexture(MEDIA .. shape.glow)
		glow:SetBlendMode("ADD")
		if channel then
			glow:SetVertexColor(0.55, 0.85, 1, 1)
		else
			glow:SetVertexColor(1, 0.85, 0.45, 1)
		end
	else
		glow:SetAtlas(channel and "gamepad-actionbar-circleslot-channel" or "gamepad-actionbar-circleslot-casting")
	end
	glow:SetSize(size, size)
	fill.FillMask:SetTexture(MEDIA .. shape.mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	fill.FillMask:SetSize(size, size)
	endMask:SetTexture(MEDIA .. shape.mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	endMask:SetSize(size * 1.3, size * 1.3)
end

local function HookCastAnim(button)
	local anim = button.SpellCastAnimFrame
	if anim and not anim.themeHooked and anim.SetupAnimAtlases then
		anim.themeHooked = true
		hooksecurefunc(anim, "SetupAnimAtlases", function()
			ShapeCastAnim(button)
		end)
	end
end

local function ApplyToButton(button, index, theme)
	SaveOriginal(button)
	GetExtras(button)
	local outline, inset = "square", 0.05
	if MODERN[theme] then
		ApplyModern(button, MODERN[theme])
		outline, inset = MODERN[theme].outline, MODERN[theme].inset
	elseif theme == "forever" then
		ApplyShape(button, index, index > 4 and CIRCLE or SQUARE, false)
		outline, inset = index > 4 and "round" or "square", index > 4 and CIRCLE.inset or SQUARE.inset
	elseif theme == "round" then
		outline, inset = "round", CIRCLE.inset
		ApplyShape(button, index, CIRCLE, true)
	elseif theme == "minimal" then
		inset = MINIMAL.inset
		Restore(button)
		UseMask(button, GetMask(button, MINIMAL))
		for _, key in ipairs({ "NormalTexture", "PushedTexture", "CheckedTexture", "Border", "SlotArt", "SlotBackground" }) do
			SetArt(button, key, nil)
		end
		-- The border: a dark square a little larger than the icon, drawn under it.
		local size = button:GetWidth()
		local edge = (MINIMAL.inset - MINIMAL.border) * size
		button.themeEdge:ClearAllPoints()
		button.themeEdge:SetPoint("TOPLEFT", button.icon, "TOPLEFT", edge, -edge)
		button.themeEdge:SetPoint("BOTTOMRIGHT", button.icon, "BOTTOMRIGHT", -edge, edge)
		button.themeEdge:SetColorTexture(0, 0, 0, 0.9)
		button.themeEdge:Show()
		local highlight = button:GetHighlightTexture()
		if highlight then
			highlight:SetColorTexture(1, 1, 1, 0.15)
			highlight:ClearAllPoints()
			highlight:SetPoint("TOPLEFT", button.icon, "TOPLEFT", MINIMAL.inset * size, -MINIMAL.inset * size)
			highlight:SetPoint("BOTTOMRIGHT", button.icon, "BOTTOMRIGHT", -MINIMAL.inset * size, MINIMAL.inset * size)
			highlight:SetBlendMode("ADD")
		end
		CropIcon(button, true)
		local filled = ApplyFill(button, MINIMAL)
		local empty = not (button.action and HasAction(button.action))
		if empty and not filled then
			button.themeEmpty:Show()
			UseMaskOn(button.themeEmpty, button, MINIMAL)
		end
		if button.cooldown then
			button.cooldown:SetSwipeTexture(SWIPE_SQUARE)
			button.cooldown:SetSwipeColor(0, 0, 0, 0.8)
			FitCooldown(button, MINIMAL.inset)
		end
	else
		Restore(button)
		UseMask(button, button.IconMask)
		CropIcon(button, false)
		if ApplyFill(button, nil) then
			SetArt(button, "SlotBackground", nil)
		end
		if button.cooldown then
			button.cooldown:SetSwipeTexture(SWIPE_SQUARE)
			button.cooldown:SetSwipeColor(0, 0, 0, 0.8)
			FitCooldown(button, 0)
		end
	end
	ApplySlotBorder(button, outline, inset)
	button.themeOutline, button.themeInset = outline, inset
	HookCastAnim(button)
	ShapeCastAnim(button)
	ShapeFlash(button)
	button.appliedTheme = theme
end

-- Blizzard's own button code can put its art back when a slot changes, so the theme follows it.
local function Reapply(button)
	if button.appliedTheme then
		ApplyToButton(button, button.themeIndex, CurrentTheme())
	end
end

function ns.ApplyTheme()
	local root = ns.root
	if not root then
		return
	end
	local theme = CurrentTheme()
	for _, row in ipairs(ns.ROWS) do
		for index, button in ipairs(root.sides[row].buttons) do
			button.themeIndex = index
			if not button.themeHooked then
				button.themeHooked = true
				for _, method in ipairs({ "UpdateButtonArt", "Update" }) do
					if button[method] then
						hooksecurefunc(button, method, Reapply)
					end
				end
			end
			ApplyToButton(button, index, theme)
		end
	end
end

-- Backgrounds behind each group of four slots, and an optional border around them.
ns.BACKGROUNDS = {
	{ "none", "None" },
	{ "disc", "Dark circle" },
	{ "shadow", "Soft shadow" },
	{ "vignette", "Vignette" },
	{ "glass", "Glass" },
	{ "glow", "Highlight glow" },
	{ "hex", "Hexagon" },
	{ "holo", "Holo glass" },
	{ "ink", "Ink wash" },
}

ns.BACKGROUND_BORDERS = {
	{ "none", "None" },
	{ "thin", "Thin" },
	{ "double", "Double" },
	{ "glow", "Glow" },
	{ "accent", "Highlight color" },
	{ "hex", "Hexagon" },
	{ "runes", "Runes" },
	{ "holo", "Holo ring" },
}

-- Art for each style: file, size (of the group's circle), color ("accent" for the highlight color) and blend.
local BACKGROUND_ART = {
	disc = { "cluster_disc", 1 },
	vignette = { "vignette", 1.3 },
	glass = { "circle_mask", 0.955, { 0.32, 0.4, 0.55, 0.45 } },
	glow = { "cluster_glow", 1.15, "accent", "ADD" },
	hex = { "hex_cluster_fill", 1.08 },
	holo = { "circle_mask", 0.86, { 0.02, 0.06, 0.09, 0.6 } },
	ink = { "ink_wash", 1.12 },
}
local BORDER_ART = {
	thin = { "cluster_ring", 1, { 0.85, 0.88, 0.95, 0.6 } },
	double = { "cluster_double", 1, { 0.85, 0.88, 0.95, 0.6 } },
	glow = { "cluster_ring_glow", 1, { 0.8, 0.88, 1, 0.7 }, "ADD" },
	accent = { "cluster_ring_glow", 1, "accent", "ADD" },
	hex = { "hex_cluster_edge", 1.08, { 0.75, 0.85, 1, 0.55 } },
	runes = { "sigil_cluster", 1, { 1, 0.84, 0.52, 0.75 } },
	holo = { "holo_cluster", 1, { 0.35, 0.9, 1, 0.8 }, "ADD" },
}

local CLUSTER_SIZE = 112

local function GetBackgroundTextures(side)
	if side.backgrounds then
		return side.backgrounds
	end
	local content = side.content
	local textures = { clusters = {}, borders = {} }
	for sign = -1, 1, 2 do
		local texture = content:CreateTexture(nil, "BACKGROUND", nil, -8)
		texture.sign = sign
		tinsert(textures.clusters, texture)
		local border = content:CreateTexture(nil, "BACKGROUND", nil, -7)
		border.sign = sign
		tinsert(textures.borders, border)
	end
	side.backgrounds = textures
	return textures
end

local function PlaceCluster(texture, side, scale)
	texture:ClearAllPoints()
	texture:SetPoint("CENTER", side.content, "CENTER", texture.sign * side.clusterX, 0)
	texture:SetSize(CLUSTER_SIZE * scale, CLUSTER_SIZE * scale)
end

local function PaintCluster(texture, side, art, alpha)
	texture:SetShown(art ~= nil)
	if not art then
		return
	end
	local file, size, color, blend = art[1], art[2], art[3], art[4]
	texture:SetTexture(MEDIA .. file)
	texture:SetBlendMode(blend or "BLEND")
	if color == "accent" then
		local r, g, b = AccentColor()
		texture:SetVertexColor(r, g, b, 0.9)
	elseif color then
		texture:SetVertexColor(unpack(color))
	else
		texture:SetVertexColor(1, 1, 1, 1)
	end
	texture:SetAlpha(alpha)
	PlaceCluster(texture, side, size)
end

function ns.ApplyBackground(side)
	if not side.clusterX then
		return
	end
	local style = Look("background")
	local alpha = ns.db and ns.db.backgroundAlpha or 0.7
	local textures = GetBackgroundTextures(side)
	for _, texture in ipairs(textures.clusters) do
		if style == "shadow" then
			-- Forever's own soft shadow art.
			texture:SetAtlas("gamepad-actionbar-circleslot-dropshadow")
			texture:SetBlendMode("BLEND")
			texture:SetVertexColor(1, 1, 1, 1)
			texture:SetAlpha(alpha)
			PlaceCluster(texture, side, 1.35)
			texture:Show()
		else
			PaintCluster(texture, side, BACKGROUND_ART[style], alpha)
		end
	end
	local borderStyle = Look("backgroundBorder")
	for _, border in ipairs(textures.borders) do
		PaintCluster(border, side, BORDER_ART[borderStyle], 1)
	end
end
