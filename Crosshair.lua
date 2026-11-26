local _, ns = ...

-- The crosshair: Forever's small reticle in the middle of the screen, or one drawn here in its place
-- with the style, color, size, thickness and opacity from the Appearance settings. It sits where
-- Forever's does, so it marks the same spot. Forever's own icons are only faded out (its swing timer
-- stays), never changed otherwise.

ns.CROSSHAIR_STYLES = {
	{ "forever", "Forever's" },
	{ "dot", "Dot" },
	{ "cross", "Cross" },
	{ "gap", "Cross with a gap" },
	{ "circle", "Circle" },
	{ "none", "None" },
}

local MEDIA = "Interface\\AddOns\\GamepadXIV\\Media\\Crosshair\\"
-- Ring textures and the share of the diameter their stroke takes.
local RINGS = { 0.04, 0.07, 0.10, 0.14, 0.19, 0.25 }

-- Everything is drawn on the screen's own pixel grid: each canvas is scaled so one unit is one
-- physical pixel, and every edge lands on a whole pixel, so lines stay sharp at any UI scale. The
-- crosshair has one canvas, the preview in the settings another.
local function PixelSize()
	local height = GetPhysicalScreenSize and select(2, GetPhysicalScreenSize())
	if height and height > 0 then
		return 768 / height
	end
	return UIParent:GetEffectiveScale()
end

-- A setting in UI units, as whole screen pixels.
local function Pixels(value)
	return math.max(1, math.floor(value * UIParent:GetEffectiveScale() / PixelSize() + 0.5))
end

local function NewCanvas(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame:EnableMouse(false)
	frame:SetSize(1, 1)
	return { frame = frame, pieces = {} }
end

-- Puts the canvas's middle on the screen pixel nearest to the middle of region.
local function Anchor(canvas, region)
	local pixel = PixelSize()
	local frame = canvas.frame
	local parent = frame:GetParent()
	frame:SetScale(pixel / parent:GetEffectiveScale())
	local x, y
	if region and region.GetCenter and region:GetCenter() then
		local scale = region:GetEffectiveScale()
		x, y = region:GetCenter()
		x, y = x * scale, y * scale
	else
		local scale = UIParent:GetEffectiveScale()
		x, y = UIParent:GetCenter()
		x, y = x * scale, y * scale
	end
	-- In the canvas's own units, from its parent's bottom left corner.
	local left, bottom = parent:GetLeft() or 0, parent:GetBottom() or 0
	local parentScale = parent:GetEffectiveScale()
	x = math.floor(x / pixel + 0.5) - math.floor(left * parentScale / pixel + 0.5)
	y = math.floor(y / pixel + 0.5) - math.floor(bottom * parentScale / pixel + 0.5)
	if x ~= canvas.x or y ~= canvas.y or parent ~= UIParent then
		canvas.x, canvas.y = x, y
		frame:ClearAllPoints()
		frame:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x, y)
	end
end

-- Each piece is a pair: a black outline behind and the colored part in front.
local function Piece(canvas, index)
	local piece = canvas.pieces[index]
	if not piece then
		piece = {
			outline = canvas.frame:CreateTexture(nil, "ARTWORK", nil, 1),
			fill = canvas.frame:CreateTexture(nil, "ARTWORK", nil, 2),
		}
		canvas.pieces[index] = piece
	end
	return piece
end

local function Paint(texture, file, r, g, b, a)
	if file then
		texture:SetTexture(file, "CLAMP", "CLAMP", "TRILINEAR")
		texture:SetVertexColor(r, g, b, a)
		if texture.SetSnapToPixelGrid then
			texture:SetSnapToPixelGrid(false)
			texture:SetTexelSnappingBias(0)
		end
	else
		texture:SetColorTexture(r, g, b, a)
		texture:SetVertexColor(1, 1, 1, 1)
	end
end

local look = {}

-- One piece: a box from its bottom left corner, in pixels from the middle. file is a texture for
-- round shapes, outlineFile the one its outline uses; plain boxes are solid color.
local function Place(canvas, index, left, bottom, width, height, file, outlineFile)
	local piece = Piece(canvas, index)
	local fill, back = piece.fill, piece.outline
	local frame = canvas.frame
	fill:ClearAllPoints()
	fill:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", left, bottom)
	fill:SetSize(width, height)
	Paint(fill, file, look.r, look.g, look.b, look.alpha)
	fill:Show()
	back:ClearAllPoints()
	back:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", left - 1, bottom - 1)
	back:SetSize(width + 2, height + 2)
	Paint(back, outlineFile or file, 0, 0, 0, look.alpha * 0.8)
	back:SetShown(look.outline)
end

local function Ring(diameter, stroke)
	local best, gap = 1, math.huge
	for i, share in ipairs(RINGS) do
		local off = math.abs(share - stroke / diameter)
		if off < gap then
			best, gap = i, off
		end
	end
	return MEDIA .. "ring" .. best
end

local function Layout(canvas)
	local db = ns.db
	for _, piece in pairs(canvas.pieces) do
		piece.fill:Hide()
		piece.outline:Hide()
	end
	look.r, look.g, look.b = ns.ColorByKey(db.crosshairColor or "white")
	look.alpha = db.crosshairAlpha or 1
	look.outline = db.crosshairOutline and true or false
	local style = db.crosshairStyle
	if style == "forever" and not ns.IsGamepadUI() then
		style = "cross" -- no Forever reticle without its gamepad UI
	end
	local size = Pixels(db.crosshairSize or 16)
	local thick = Pixels(db.crosshairThickness or 2)
	-- With an odd thickness the middle is a pixel's center, otherwise a pixel corner.
	local odd = thick % 2
	local base = -math.floor(thick / 2)
	if style == "dot" then
		local d = thick * 2 + 2
		Place(canvas, 1, -d / 2, -d / 2, d, d, MEDIA .. "dot")
	elseif style == "cross" then
		local length = size + (size - thick) % 2
		local from = base - (length - thick) / 2
		Place(canvas, 1, from, base, length, thick)
		Place(canvas, 2, base, from, thick, length)
	elseif style == "gap" then
		-- Four bars around an empty middle.
		local gap = math.max(2, math.floor(size * 0.15 + 0.5))
		local arm = math.max(2, math.floor(size / 2) - gap)
		Place(canvas, 1, -gap - arm, base, arm, thick)
		Place(canvas, 2, gap + odd, base, arm, thick)
		Place(canvas, 3, base, -gap - arm, thick, arm)
		Place(canvas, 4, base, gap + odd, thick, arm)
	elseif style == "circle" then
		local d = size + size % 2
		Place(canvas, 1, -d / 2, -d / 2, d, d, Ring(d, thick), Ring(d + 2, thick + 2))
	end
end

local main = NewCanvas(UIParent)
local frame = main.frame
frame:SetFrameStrata("LOW")
frame:Hide()

-- The preview in the settings: draws the crosshair in the middle of region, a frame of the
-- settings window. Returns its canvas, to pass back to ns.DrawCrosshairPreview.
function ns.CreateCrosshairPreview(region)
	local canvas = NewCanvas(region)
	canvas.region = region
	canvas.frame:SetFrameLevel(region:GetFrameLevel() + 5)
	return canvas
end

function ns.DrawCrosshairPreview(canvas)
	if not ns.db then
		return
	end
	Anchor(canvas, canvas.region)
	Layout(canvas)
end

local function ForeverIcons()
	return GamepadReticle and GamepadReticle.Icons
end

function ns.RefreshCrosshair()
	if not ns.db then
		return
	end
	Anchor(main, ns.IsGamepadUI() and GamepadReticle or nil)
	Layout(main)
	local icons = ForeverIcons()
	if icons and (ns.db.crosshairStyle or "forever") == "forever" then
		icons:SetAlpha(1)
	end
end

-- Shown with Forever's reticle (gamepad mode, no mouse cursor). Forever fades its icons back in on
-- its own, so they are faded out again each frame while another style is picked.
local watcher = CreateFrame("Frame")
watcher:SetScript("OnUpdate", function()
	local db = ns.db
	if not db then
		return
	end
	local style = db.crosshairStyle or "forever"
	local reticle = GamepadReticle
	local noUI = not ns.IsGamepadUI()
	local custom = style ~= "forever" or noUI
	-- Without Forever's gamepad UI there is no reticle: the addon's crosshair shows while it runs.
	local where = noUI and (db.enabled and db.withoutGamepadUI) or (reticle and reticle:IsVisible())
	local visible = custom and style ~= "none" and where and not IsCursorVisible()
	frame:SetShown(visible and true or false)
	if visible then
		Anchor(main, not noUI and GamepadReticle or nil)
	end
	local icons = ForeverIcons()
	if custom and icons and icons:GetAlpha() > 0 then
		icons:SetAlpha(0)
	end
end)
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
watcher:RegisterEvent("UI_SCALE_CHANGED")
watcher:SetScript("OnEvent", function()
	C_Timer.After(0, ns.RefreshCrosshair)
end)
