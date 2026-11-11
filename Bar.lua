local _, ns = ...

local BUTTON_SIZE = 40
-- Half the width of one diamond of buttons: the side offset plus half a button.
local CLUSTER_HALF_WIDTH = BUTTON_SIZE * 0.8 + BUTTON_SIZE / 2

local movers = {}

-- Diamond offsets for the 1 left, 2 up, 3 right, 4 down cluster order, in button units.
local DIAMOND = { { -1, 0 }, { 0, 0.72 }, { 1, 0 }, { 0, -0.72 } }

local GOLD = { 1, 0.82, 0.25 }
-- The setting that colors the selected bar's highlight, for each layer.
local ACTIVE_COLOR_KEYS = {
	L = "activeColorBottom", R = "activeColorBottom",
	WL = "activeColorTopLeft", WR = "activeColorTopRight",
	LR = "activeColorCombo", RL = "activeColorCombo",
}
local LAYER_ROW = { L = "L", R = "R", WL = "WL", WR = "WR", LR = "L", RL = "R" }

local MEDIA = "Interface\\AddOns\\GamepadXIV\\Media\\"

-- How the selected bar is highlighted.
ns.ACTIVE_STYLES = {
	{ "glow", "Big glow" },
	{ "soft", "Soft glow per group" },
	{ "ring", "Ring per group" },
	{ "slots", "Glow per slot" },
	{ "none", "None" },
}

-- The selection animation: the highlight swells in and settles while the side stays selected.
local function AddSelectAnim(texture)
	local anim = texture:CreateAnimationGroup()
	local fade = anim:CreateAnimation("Alpha")
	fade:SetFromAlpha(0)
	fade:SetToAlpha(0.9)
	fade:SetDuration(0.14)
	fade:SetOrder(1)
	local swell = anim:CreateAnimation("Scale")
	swell:SetScaleFrom(0.72, 0.72)
	swell:SetScaleTo(1, 1)
	swell:SetDuration(0.14)
	swell:SetOrder(1)
	anim:SetToFinalAlpha(true)
	anim.fade = fade
	texture.anim = anim
	texture:SetBlendMode("ADD")
	texture:SetAlpha(0)
end

-- Small marks in the middle of each cluster of a selected side: a cross for the D-pad, four dots for the face buttons.
local function CreateClusterMarks(content)
	local marks = CreateFrame("Frame", nil, content)
	marks:SetAllPoints()
	marks:SetFrameLevel(content:GetFrameLevel() + 20)
	marks:Hide()

	marks.items = {}
	local function AddMark(clusterSign, x, y, width, height)
		local texture = marks:CreateTexture(nil, "OVERLAY")
		texture:SetColorTexture(1, 1, 1, 0.9)
		texture:SetSize(width, height)
		tinsert(marks.items, { texture = texture, clusterSign = clusterSign, x = x, y = y })
	end

	AddMark(-1, 0, 0, 16, 5)
	AddMark(-1, 0, 0, 5, 16)
	AddMark(1, -6, 0, 5, 5)
	AddMark(1, 6, 0, 5, 5)
	AddMark(1, 0, 6, 5, 5)
	AddMark(1, 0, -6, 5, 5)
	return marks
end

local function CreateSide(root, row)
	local side = CreateFrame("Frame", "GamepadXIVSide" .. row, root)

	-- Secure code scales this frame in combat, around the side's centre.
	local content = CreateFrame("Frame", "GamepadXIVContent" .. row, side, "SecureHandlerBaseTemplate")
	content:SetPoint("CENTER")
	side.content = content

	local glow = content:CreateTexture(nil, "BACKGROUND")
	glow:SetPoint("CENTER")
	glow:SetSize(BUTTON_SIZE * 8, BUTTON_SIZE * 4.5)
	glow:SetAtlas("AftLevelup-WhiteIconGlow")
	if not glow:GetAtlas() then
		glow:SetColorTexture(1, 1, 1, 0.3)
	end
	AddSelectAnim(glow)
	side.glow = glow

	-- The other highlight styles: one soft glow or ring per group of four, or a glow behind each slot.
	side.highlights = { glow = { glow }, soft = {}, ring = {}, slots = {} }
	for sign = -1, 1, 2 do
		local soft = content:CreateTexture(nil, "BACKGROUND")
		soft:SetTexture(MEDIA .. "cluster_glow")
		soft.sign = sign
		AddSelectAnim(soft)
		tinsert(side.highlights.soft, soft)
		local ring = content:CreateTexture(nil, "BACKGROUND", nil, 1)
		ring:SetTexture(MEDIA .. "cluster_ring_glow")
		ring.sign = sign
		AddSelectAnim(ring)
		tinsert(side.highlights.ring, ring)
	end

	-- A gold flash over the bar when its set changes (R1 + a button, quick set swap, Expanded Hold).
	-- On its own frame above the buttons; purely visual.
	local flashFrame = CreateFrame("Frame", nil, content)
	flashFrame:SetAllPoints()
	flashFrame:SetFrameLevel(content:GetFrameLevel() + 30)
	local flash = flashFrame:CreateTexture(nil, "OVERLAY")
	flash:SetPoint("CENTER")
	flash:SetSize(BUTTON_SIZE * 8, BUTTON_SIZE * 4.5)
	flash:SetAtlas("AftLevelup-WhiteIconGlow")
	if not flash:GetAtlas() then
		flash:SetColorTexture(1, 1, 1, 0.3)
	end
	flash:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
	flash:SetBlendMode("ADD")
	flash:SetAlpha(0)
	local flashAnim = flash:CreateAnimationGroup()
	local rise = flashAnim:CreateAnimation("Alpha")
	rise:SetFromAlpha(0)
	rise:SetToAlpha(0.85)
	rise:SetDuration(0.12)
	rise:SetOrder(1)
	local grow = flashAnim:CreateAnimation("Scale")
	grow:SetScaleFrom(0.85, 0.85)
	grow:SetScaleTo(1.1, 1.1)
	grow:SetDuration(0.47)
	grow:SetOrder(1)
	local fall = flashAnim:CreateAnimation("Alpha")
	fall:SetFromAlpha(0.85)
	fall:SetToAlpha(0)
	fall:SetDuration(0.35)
	fall:SetStartDelay(0.12)
	fall:SetOrder(1)
	flashAnim:SetToFinalAlpha(true)
	side.flash = flashAnim

	-- The bar's set, outside it so its buttons never cover it: above a top bar, below a bottom one.
	side.label = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	if row == "WL" or row == "WR" then
		side.label:SetPoint("BOTTOM", content, "TOP", 0, 4)
	else
		side.label:SetPoint("TOP", content, "BOTTOM", 0, -4)
	end
	-- The label pops when the set changes.
	local pop = side.label:CreateAnimationGroup()
	local shrink = pop:CreateAnimation("Scale")
	shrink:SetScaleFrom(1.35, 1.35)
	shrink:SetScaleTo(1, 1)
	shrink:SetDuration(0.25)
	side.labelPop = pop

	side.buttons = {}
	for i = 1, ns.NUM_SLOTS do
		local button = CreateFrame("CheckButton", "GamepadXIVBtn" .. row .. i, content, "ActionBarButtonTemplate, SecureActionButtonTemplate")
		button:SetAttribute("showgrid", 1)
		button:SetScale(BUTTON_SIZE / button:GetWidth())

		if button.HotKey then
			button.HotKey:SetAlpha(0)
		end

		-- The button's own art for the active controller, set by RefreshKeyIcons.
		local keyIcon = button:CreateTexture(nil, "OVERLAY", nil, 7)
		keyIcon:SetPoint("CENTER", button, "BOTTOMRIGHT", -9, 9)
		button.keyIcon = keyIcon

		-- A separate red layer, because Blizzard's own usable state owns the icon's vertex color.
		local rangeTint = button:CreateTexture(nil, "BACKGROUND", nil, 7)
		rangeTint:SetAllPoints(button.icon)
		-- A see-through red rather than a multiply: masks do not apply to multiply textures, so that one
		-- stayed square around round and hexagon slots.
		rangeTint:SetColorTexture(0.85, 0.08, 0.08, 0.55)
		rangeTint:SetBlendMode("BLEND")
		rangeTint:AddMaskTexture(button.IconMask)
		rangeTint:Hide()
		button.rangeTint = rangeTint

		local slotGlow = content:CreateTexture(nil, "BACKGROUND", nil, 2)
		slotGlow:SetTexture(MEDIA .. "ring_glow")
		slotGlow:SetPoint("CENTER", button, "CENTER")
		slotGlow:SetSize(BUTTON_SIZE * 1.3, BUTTON_SIZE * 1.3)
		AddSelectAnim(slotGlow)
		tinsert(side.highlights.slots, slotGlow)

		-- Slots can be dragged out of combat regardless of the action bar lock.
		-- Blizzard's own handler already covers an unlocked bar or a modified drag.
		button:HookScript("OnDragStart", function(self)
			if not InCombatLockdown() and Settings.GetValue("lockActionBars") and not IsModifiedClick("PICKUPACTION") then
				PickupAction(self.action)
			end
		end)

		side.buttons[i] = button
		button:Show()
	end

	-- Created after the buttons, so the marks sit on top of them.
	side.marks = CreateClusterMarks(content)
	return side
end

-- The R1 overlay: which button picks which set, laid out like the buttons themselves, each number
-- with its button's icon. It sits above the top row (placed in ShowLayer), on the DIALOG strata so
-- other windows and addons' frames don't cover it, compact and transparent.
local function CreateSetPicker(root)
	local picker = CreateFrame("Frame", nil, root)
	picker:SetSize(260, 92)
	picker:SetFrameStrata("DIALOG")
	picker:Hide()

	-- No background: the text's shadow keeps it readable over the world.
	local title = picker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	title:SetPoint("TOP", 0, -4)
	title:SetText("CHANGE SET")

	-- Offsets around each cluster's centre: up, right, down, left.
	local AROUND = { { 0, 21 }, { 32, 0 }, { 0, -21 }, { -32, 0 } }
	picker.numbers = {}
	for set = 1, ns.NUM_SETS do
		local number = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		local around = AROUND[(set - 1) % 4 + 1]
		local clusterX = (set <= 4) and 68 or -68
		number:SetPoint("CENTER", picker, "CENTER", clusterX + around[1], -7 + around[2])
		picker.numbers[set] = number
	end
	root.setPicker = picker
end

-- The button that picks each set, from the driver's key order.
local function SetPickerKeys()
	local keys = {}
	for index, key in ipairs(ns.KEYS) do
		keys[ns.SET_BY_KEY[index]] = key
	end
	return keys
end

local function DrawSetPicker()
	local keys = SetPickerKeys()
	for set, number in ipairs(ns.root.setPicker.numbers) do
		number:SetText(ns.ButtonText("{" .. (keys[set] or "") .. "}", 18) .. " " .. set)
	end
end

-- Places the two diamonds of a side with the chosen gap between them.
local function LayoutSide(side, row, padding)
	local clusterX = CLUSTER_HALF_WIDTH + padding / 2
	local width, height = (clusterX + CLUSTER_HALF_WIDTH) * 2, BUTTON_SIZE * 3
	side:SetSize(width, height)
	side.content:SetSize(width, height)
	if movers[row] then
		movers[row]:SetSize(width, height)
	end

	for i, button in ipairs(side.buttons) do
		local offset = DIAMOND[(i - 1) % 4 + 1]
		local x = (i <= 4) and -clusterX or clusterX
		local scale = button:GetScale()
		button:ClearAllPoints()
		button:SetPoint("CENTER", side.content, "CENTER",
			(x + offset[1] * BUTTON_SIZE * 0.8) / scale,
			(offset[2] * BUTTON_SIZE * 1.1) / scale)
	end

	for _, item in ipairs(side.marks.items) do
		item.texture:ClearAllPoints()
		item.texture:SetPoint("CENTER", side.marks, "CENTER", item.clusterSign * clusterX + item.x, item.y)
	end
	for _, key in ipairs({ "soft", "ring" }) do
		for _, texture in ipairs(side.highlights[key]) do
			local size = key == "soft" and 140 or 116
			texture:ClearAllPoints()
			texture:SetPoint("CENTER", side.content, "CENTER", texture.sign * clusterX, 0)
			texture:SetSize(size, size)
		end
	end
	side.clusterX = clusterX
	ns.ApplyBackground(side)
end

-- The loot roll window, where the player moved it. Its first anchors are kept so a reset can restore them.
function ns.PlaceLootFrame()
	local frame = ns.lootFrame
	local db = ns.db
	if not frame or not db or ns.placingLoot then
		return
	end
	if InCombatLockdown() and frame:IsProtected() then
		return
	end
	-- Forever's own anchors, read while the window is still where Forever put it.
	if not db.lootMoved and not frame.gxivMovedOnce then
		local points = {}
		for i = 1, frame:GetNumPoints() do
			points[i] = { frame:GetPoint(i) }
		end
		frame.gxivOriginalPoints = points
	end
	ns.placingLoot = true
	if db.lootMoved then
		frame:ClearAllPoints()
		frame:SetPoint("CENTER", UIParent, "CENTER", db.lootX, db.lootY)
	elseif frame.gxivMovedOnce then
		frame:ClearAllPoints()
		for _, point in ipairs(frame.gxivOriginalPoints) do
			frame:SetPoint(unpack(point))
		end
		frame.gxivMovedOnce = nil
	end
	if db.lootMoved then
		frame.gxivMovedOnce = true
	end
	ns.placingLoot = false
end

-- The loot roll window's position from the middle of the screen, in UIParent units.
local function GetLootPosition()
	local db = ns.db
	if db.lootMoved then
		return db.lootX, db.lootY
	end
	local frame = ns.lootFrame
	local x, y = frame:GetCenter()
	local parentX, parentY = UIParent:GetCenter()
	if not x then
		return 0, 0
	end
	local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
	return x * ratio - parentX, y * ratio - parentY
end

local function SetLootPosition(x, y)
	local db = ns.db
	if not db.lootMoved then
		ns.PlaceLootFrame() -- keeps Forever's own anchors before the first move
	end
	db.lootMoved, db.lootX, db.lootY = true, x, y
end

function ns.ApplyLayout()
	local root = ns.root
	local db = ns.db
	ns.PlaceLootFrame()
	if ns.interactHud then
		ns.interactHud:ClearAllPoints()
		ns.interactHud:SetPoint("CENTER", UIParent, "CENTER", db.promptX, db.promptY)
	end
	root:SetScale(db.scale)
	root:ClearAllPoints()
	root:SetPoint("BOTTOM", UIParent, "BOTTOM", db.x, db.y)
	for _, row in ipairs(ns.ROWS) do
		local side = root.sides[row]
		LayoutSide(side, row, db.clusterPadding)
		side:ClearAllPoints()
		side:SetPoint("CENTER", root, "CENTER", db["pos" .. row .. "x"], db["pos" .. row .. "y"])
	end
end

-- The labels outside Move bars name buttons, so they are redrawn when another controller is plugged in.
local function SetPlayLabels()
	local root = ns.root
	if not root or ns.editing or not root.shownSet then
		return
	end
	-- Each bar names its set: the bottom ones with their trigger, the top ones with a double tap of it.
	local shown = root.shownSides or {}
	local function SetName(side)
		if not side then
			return ""
		end
		-- Past the eight sets are the stance bars of forms (set 0).
		return side > ns.NUM_SETS * 2 and "STANCE" or ("SET " .. (ns.DescribeSide(side)))
	end
	root.sides.L.label:SetText(ns.ButtonText("{PADLTRIGGER}", 24) .. "  " .. SetName(shown[1]))
	root.sides.R.label:SetText(SetName(shown[2]) .. "  " .. ns.ButtonText("{PADRTRIGGER}", 24))
	root.sides.WL.label:SetText(ns.ButtonText("{PADLTRIGGER}{PADLTRIGGER}", 20) .. "  " .. SetName(ns.db.sideWL))
	root.sides.WR.label:SetText(SetName(ns.db.sideWR) .. "  " .. ns.ButtonText("{PADRTRIGGER}{PADRTRIGGER}", 20))
	local name = root.shownSet == 0 and "STANCE" or ("SET " .. root.shownSet)
	root.setText:SetText(name .. "  " .. ns.ButtonText("{PADRSHOULDER}", 20))
end

local function RefreshKeyIcons()
	SetPlayLabels()
	local root = ns.root
	for _, row in ipairs(ns.ROWS) do
		for i, button in ipairs(root.sides[row].buttons) do
			local key = ns.KEYS[i]
			local textures = InputIconTextureSetUtility and InputIconTextureSetUtility.GetActiveInputIconButtonTextures(key)
			if ns.db.showKeyLabels and textures then
				button.keyIcon:SetAtlas(InputIconTextureSetUtility.GetNormalActiveInputIconButtonTexture(key))
				button.keyIcon:SetSize(ns.db.keyIconSize, ns.db.keyIconSize)
				button.keyIcon:Show()
			else
				button.keyIcon:Hide()
			end
		end
	end
end

-- Polled, because a slot can change page or target without a range event for its new action.
local RANGE_CHECK_SECONDS = 0.2

local function UpdateRangeTints()
	local active = ns.db.rangeIndicator and UnitExists("target")
	for _, row in ipairs(ns.ROWS) do
		for _, button in ipairs(ns.root.sides[row].buttons) do
			local action = button.action
			local outOfRange = active and action and button:IsVisible() and C_ActionBar.HasAction(action)
				and C_ActionBar.IsActionInRange(action) == false
			button.rangeTint:SetShown(outOfRange or false)
		end
	end
end

function ns.RefreshVisuals()
	local root = ns.root
	ns.ApplyTheme()
	for _, row in ipairs(ns.ROWS) do
		ns.ApplyBackground(root.sides[row])
	end
	for _, row in ipairs(ns.ROWS) do
		local side = root.sides[row]
		side.label:SetShown(ns.db.showSetLabels)
	end
	RefreshKeyIcons()
	root.setText:SetShown(ns.db.showSetLabels)
	if ns.lastShown then
		ns.ShowLayer(unpack(ns.lastShown))
	end
end

function ns.CreateBar()
	local root = CreateFrame("Frame", "GamepadXIVFrame", UIParent)
	root:SetFrameStrata("MEDIUM")
	root:SetSize(120, 40)
	ns.root = root

	root.sides = {}
	for _, row in ipairs(ns.ROWS) do
		root.sides[row] = CreateSide(root, row)
	end

	root.setText = root:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	root.setText:SetPoint("CENTER", root, "CENTER", 0, -68)

	root.softText = root:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	root.softText:SetPoint("BOTTOM", root, "CENTER", 0, 84)
	root.softHint = root:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	root.softHint:SetPoint("TOP", root.softText, "BOTTOM", 0, -2)
	root.softHint:Hide()

	root.softBorder = ns.CreateSelectionHighlight()
	root.targetHighlight = ns.CreateSelectionHighlight()
	local targetWatcher = CreateFrame("Frame", nil, root)
	targetWatcher:RegisterEvent("PLAYER_TARGET_CHANGED")
	targetWatcher:RegisterEvent("GROUP_ROSTER_UPDATE")
	targetWatcher:RegisterEvent("UNIT_PET")
	-- Frames can move or appear after these events, so the frame is looked up a moment later.
	targetWatcher:SetScript("OnEvent", function()
		C_Timer.After(0.1, ns.UpdateTargetHighlight)
	end)

	-- Plugging in another controller changes the art.
	if InputDeviceIconSetManager then
		InputDeviceIconSetManager:RegisterActiveInputDeviceIconSetUpdatedCallback(RefreshKeyIcons, ns)
	end

	CreateSetPicker(root)
	ns.ApplyLayout()
	ns.RefreshVisuals()
	C_Timer.NewTicker(RANGE_CHECK_SECONDS, UpdateRangeTints)
end

local function DescribeLabel(side)
	local set, letter = ns.DescribeSide(side)
	return "Set " .. set .. " " .. letter
end

-- Purely visual; called from the secure driver through CallMethod whenever the layer changes.
function ns.ShowLayer(layer, leftSide, rightSide, set, form)
	local root = ns.root
	if not root then
		return
	end
	ns.lastShown = { layer, leftSide, rightSide, set, form }
	ns.currentSet = set > 0 and set or nil -- 0 is the game's stance bar, which the editor doesn't show
	ns.l1Held = layer == "L1"

	local activeRow = not ns.editing and LAYER_ROW[layer]
	local style = ns.db.activeHighlight or "glow"
	local r, g, b = ns.ColorByKey(ns.db[ACTIVE_COLOR_KEYS[layer] or "activeColorBottom"])
	for _, row in ipairs(ns.ROWS) do
		local side = root.sides[row]
		for key, textures in pairs(side.highlights) do
			for _, texture in ipairs(textures) do
				if row == activeRow and key == style then
					texture:SetVertexColor(r, g, b)
					texture.anim.fade:SetToAlpha(ns.db.activeStrength or 0.9)
					if ns.lastLayer ~= layer then
						texture.anim:Stop()
						texture.anim:Play()
					end
				else
					texture.anim:Stop()
					texture:SetAlpha(0)
				end
			end
		end
		side.marks:SetShown(row == activeRow and ns.db.activeMarks ~= false)
	end

	local sides = root.sides
	if ns.editing then
		sides.L.label:SetText(DescribeLabel(leftSide))
		sides.R.label:SetText(DescribeLabel(rightSide))
		sides.WL.label:SetText(ns.ButtonText("Double tap {PADLTRIGGER}: ", 18) .. DescribeLabel(ns.db.sideWL))
		sides.WR.label:SetText(ns.ButtonText("Double tap {PADRTRIGGER}: ", 18) .. DescribeLabel(ns.db.sideWR))
		root.setText:SetText("MOVE")
		root.barSides = nil
	else
		root.shownSet = set
		root.shownSides = { leftSide, rightSide }
		-- A bar whose set changed flashes; nothing on the first show or after Move bars.
		local now = { L = leftSide, R = rightSide, WL = ns.db.sideWL, WR = ns.db.sideWR }
		local before = root.barSides
		for row, sideIndex in pairs(now) do
			if before and before[row] and before[row] ~= sideIndex then
				sides[row].flash:Stop()
				sides[row].flash:Play()
				sides[row].labelPop:Stop()
				sides[row].labelPop:Play()
			end
		end
		root.barSides = now
		SetPlayLabels()
	end

	local picker = root.setPicker
	if layer == "SET" then
		-- Above whichever top bar is higher, so nothing covers it.
		local top = math.max(sides.WL:GetTop() or 0, sides.WR:GetTop() or 0)
		local scale = sides.WL:GetEffectiveScale() / root:GetEffectiveScale()
		local center = select(2, root:GetCenter()) or 0
		picker:ClearAllPoints()
		picker:SetPoint("BOTTOM", root, "CENTER", 0, top * scale - center + 16)
		DrawSetPicker()
	end
	picker:SetShown(layer == "SET" and ns.db.showSetPicker)
	for index, number in ipairs(root.setPicker.numbers) do
		if index == set then
			number:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
		else
			number:SetTextColor(0.7, 0.7, 0.7)
		end
	end
	-- Editing shows no glow, so leaving it must play the animation again.
	ns.lastLayer = not ns.editing and layer or nil

	if form and form > 0 then
		ns.db["formSet" .. form] = set
	else
		ns.db.set = set
	end
end

local function FindCompactFrame(unit)
	for _, key in ipairs({ "memberUnitFrames", "petUnitFrames" }) do
		for _, frame in ipairs(CompactPartyFrame and CompactPartyFrame[key] or {}) do
			if frame.unit == unit and frame:IsVisible() then
				return frame
			end
		end
	end
	for i = 1, 40 do
		local frame = _G["CompactRaidFrame" .. i]
		if frame and frame.unit == unit and frame:IsVisible() then
			return frame
		end
	end
	for group = 1, 8 do
		for member = 1, 5 do
			local frame = _G["CompactRaidGroup" .. group .. "Member" .. member]
			if frame and frame.unit == unit and frame:IsVisible() then
				return frame
			end
		end
	end
end

-- The frame showing a unit, whichever party or raid style is in use.
local function FindUnitFrame(unit)
	local frame = FindCompactFrame(unit)
	if frame then
		return frame
	end
	if unit == "player" then
		return PlayerFrame
	elseif unit == "pet" then
		return PetFrame and PetFrame:IsVisible() and PetFrame or nil
	end
	local index = unit:match("^party(%d)$")
	frame = index and PartyFrame and PartyFrame["MemberFrame" .. index]
	local petIndex = unit:match("^partypet(%d)$")
	local owner = petIndex and PartyFrame and PartyFrame["MemberFrame" .. petIndex]
	if owner then
		frame = owner.PetFrame
	end
	return frame and frame:IsVisible() and frame or nil
end

-- Highlight on the selected party or raid member's frame. Styles: "outline" (thin gold border), "thick"
-- (wide border), "fill" (gold tint with a border), "pulse" (a border that fades in and out) and "none".
-- Party frames can also get a bobbing arrow outside them, on the left or the right.
function ns.CreateSelectionHighlight()
	local highlight = CreateFrame("Frame", nil, UIParent)
	highlight:SetFrameStrata("HIGH")
	highlight:Hide()

	highlight.edges = {}
	for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
		local line = highlight:CreateTexture(nil, "OVERLAY")
		line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
		line:SetPoint(edge[1])
		line:SetPoint(edge[2])
		line.horizontal = edge[1]:sub(1, 3) == edge[2]:sub(1, 3)
		tinsert(highlight.edges, line)
	end

	highlight.fill = highlight:CreateTexture(nil, "ARTWORK")
	highlight.fill:SetAllPoints()
	highlight.fill:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.35)
	highlight.fill:SetBlendMode("ADD")

	highlight.pulse = highlight:CreateAnimationGroup()
	highlight.pulse:SetLooping("BOUNCE")
	local fade = highlight.pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.25)
	fade:SetDuration(0.6)

	local marker = CreateFrame("Frame", nil, highlight)
	marker:SetSize(28, 28)
	marker.arrow = marker:CreateTexture(nil, "OVERLAY")
	marker.arrow:SetAllPoints()
	marker.arrow:SetTexture("Interface\\Buttons\\Arrow-Up-Up")
	marker.bob = marker:CreateAnimationGroup()
	marker.bob:SetLooping("BOUNCE")
	marker.move = marker.bob:CreateAnimation("Translation")
	marker.move:SetDuration(0.45)
	highlight.marker = marker
	return highlight
end

-- Colors offered for the highlight; a list rather than a color picker so the controller can cycle it.
ns.HIGHLIGHT_COLORS = {
	{ "gold", "Gold", 1, 0.82, 0.25 },
	{ "white", "White", 1, 1, 1 },
	{ "green", "Green", 0.3, 1, 0.3 },
	{ "cyan", "Cyan", 0.2, 0.95, 1 },
	{ "blue", "Blue", 0.3, 0.55, 1 },
	{ "purple", "Purple", 0.75, 0.4, 1 },
	{ "pink", "Pink", 1, 0.45, 0.8 },
	{ "red", "Red", 1, 0.25, 0.25 },
	{ "orange", "Orange", 1, 0.55, 0.1 },
}

function ns.ColorByKey(key)
	for _, color in ipairs(ns.HIGHLIGHT_COLORS) do
		if color[1] == key then
			return color[3], color[4], color[5]
		end
	end
	return GOLD[1], GOLD[2], GOLD[3]
end

-- Shows the selected bar's highlight again, after its settings change.
function ns.RefreshActiveHighlight()
	ns.lastLayer = nil
	if ns.lastShown then
		ns.ShowLayer(unpack(ns.lastShown))
	end
end

local function GetHighlightColor()
	for _, color in ipairs(ns.HIGHLIGHT_COLORS) do
		if color[1] == ns.db.highlightColor then
			return color[3], color[4], color[5]
		end
	end
	return GOLD[1], GOLD[2], GOLD[3]
end

ns.GetHighlightColor = GetHighlightColor

local function ApplyHighlight(highlight, frame, style, side)
	local red, green, blue = GetHighlightColor()
	for _, line in ipairs(highlight.edges) do
		line:SetColorTexture(red, green, blue, 1)
	end
	highlight.fill:SetColorTexture(red, green, blue, 0.35)
	highlight.marker.arrow:SetDesaturated(true)
	highlight.marker.arrow:SetVertexColor(red, green, blue)
	local thickness = (style == "thick") and 4 or (style == "pulse") and 3 or 2
	for _, line in ipairs(highlight.edges) do
		line:SetShown(style ~= "none")
		if line.horizontal then
			line:SetHeight(thickness)
		else
			line:SetWidth(thickness)
		end
	end
	highlight.fill:SetShown(style == "fill")
	highlight:SetAlpha(1)
	if style == "pulse" then
		highlight.pulse:Play()
	else
		highlight.pulse:Stop()
	end

	local marker = highlight.marker
	marker.bob:Stop()
	marker:ClearAllPoints()
	if side == "left" or side == "right" then
		local pointsRight = side == "left"
		-- The arrow art points up; it is turned to point at the frame.
		marker.arrow:SetRotation(pointsRight and -math.pi / 2 or math.pi / 2)
		marker:SetPoint(pointsRight and "RIGHT" or "LEFT", frame, pointsRight and "LEFT" or "RIGHT", pointsRight and -2 or 2, 0)
		marker.move:SetOffset(pointsRight and 6 or -6, 0)
		marker:Show()
		marker.bob:Play()
	else
		marker:Hide()
	end

	highlight:ClearAllPoints()
	highlight:SetAllPoints(frame)
	highlight:Show()
end

-- Called from the secure driver: unit is "" when no temporary target is set.
function ns.ShowSoftTarget(unit)
	if ns.PlayLog then
		ns.PlayLog("soft target:", unit == "" and "cleared" or unit)
	end
	local root = ns.root
	ns.softUnit = unit
	root.softBorder:Hide()
	root.softBorder.pulse:Stop()
	root.softBorder.marker.bob:Stop()
	root.softHint:SetShown(unit ~= "")
	root.softHint:SetText(format("Next ability goes here. %s make target. %s cancel.",
		ns.ButtonText("{PAD1}", 18), ns.ButtonText("{PAD2}", 18)))
	if unit == "" then
		root.softText:SetText("")
		return
	end
	-- The name can be a secret value in combat: it may be displayed, not concatenated or tested.
	root.softText:SetText(UnitName(unit))
	local frame = FindUnitFrame(unit)
	if frame then
		local db = ns.db
		if IsInRaid() then
			ApplyHighlight(root.softBorder, frame, db.raidHighlight, "off")
		else
			ApplyHighlight(root.softBorder, frame, db.partyHighlight, db.partyMarker)
		end
	end
end

-- With Party targeting on Hard there is no temporary target, so the highlight follows the real target
-- while it is a party or raid member or one of their pets.
local function FindGroupTargetUnit()
	if not UnitExists("target") then
		return nil
	end
	local units = { "player", "pet" }
	if IsInRaid() then
		for i = 1, 40 do
			tinsert(units, "raid" .. i)
			tinsert(units, "raidpet" .. i)
		end
	else
		for i = 1, 4 do
			tinsert(units, "party" .. i)
			tinsert(units, "partypet" .. i)
		end
	end
	for _, unit in ipairs(units) do
		if UnitExists(unit) and UnitIsUnit(unit, "target") then
			return unit
		end
	end
end

function ns.UpdateTargetHighlight()
	local root = ns.root
	if not (root and root.targetHighlight) then
		return
	end
	local highlight = root.targetHighlight
	highlight:Hide()
	highlight.pulse:Stop()
	highlight.marker.bob:Stop()
	if ns.db.partyTargeting ~= "hard" or not ns.IsActive() then
		return
	end
	local unit = FindGroupTargetUnit()
	local frame = unit and FindUnitFrame(unit)
	if not frame then
		return
	end
	if IsInRaid() then
		ApplyHighlight(highlight, frame, ns.db.raidHighlight, "off")
	else
		ApplyHighlight(highlight, frame, ns.db.partyHighlight, ns.db.partyMarker)
	end
end

function ns.SetBarShown(shown)
	if ns.root then
		ns.root:SetAlpha(shown and 1 or 0)
	end
end

-- Move mode: a handle over each side, and one in the middle that carries all of them. The bars move
-- together unless "Move bars separately" is on; Shift + drag on a bar's handle carries all of them too.
local function GetWholePosition()
	return ns.db.x, ns.db.y
end

local function SetWholePosition(x, y)
	ns.db.x, ns.db.y = x, y
end

local function CreateMover(anchor, width, height, labelText, strata, getPosition, setPosition, scaleFrame, isBar)
	local mover = CreateFrame("Frame", nil, UIParent)
	mover:SetFrameStrata(strata)
	mover:SetSize(width, height)
	mover:SetPoint("CENTER", anchor, "CENTER")
	mover:EnableMouse(true)
	mover:RegisterForDrag("LeftButton")
	mover:Hide()

	local background = mover:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(0.2, 0.6, 1, 0.35)

	local label = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("CENTER")
	label:SetText(labelText)

	local function StopDrag()
		mover:SetScript("OnUpdate", nil)
	end

	mover:SetScript("OnDragStart", function()
		if InCombatLockdown() then
			return
		end
		local carryAll = IsShiftKeyDown() or (isBar and not ns.db.moveBarsSeparately)
		local get, set = carryAll and GetWholePosition or getPosition, carryAll and SetWholePosition or setPosition
		local startCursorX, startCursorY = GetCursorPosition()
		local startX, startY = get()
		mover:SetScript("OnUpdate", function()
			if InCombatLockdown() then
				StopDrag()
				return
			end
			local cursorX, cursorY = GetCursorPosition()
			local scale = (scaleFrame or ns.root):GetEffectiveScale()
			set(startX + (cursorX - startCursorX) / scale, startY + (cursorY - startCursorY) / scale)
			ns.ApplyLayout()
		end)
	end)
	mover:SetScript("OnDragStop", StopDrag)
	mover:SetScript("OnHide", StopDrag)
	return mover
end

local function CreateMovers()
	local db = ns.db
	local NAMES = {
		L = ns.ButtonText("{PADLTRIGGER}", 20), R = ns.ButtonText("{PADRTRIGGER}", 20),
		WL = ns.ButtonText("{PADLTRIGGER} {PADLTRIGGER}", 20), WR = ns.ButtonText("{PADRTRIGGER} {PADRTRIGGER}", 20),
	}
	for _, row in ipairs(ns.ROWS) do
		local keyX, keyY = "pos" .. row .. "x", "pos" .. row .. "y"
		local side = ns.root.sides[row]
		movers[row] = CreateMover(side, side:GetWidth(), side:GetHeight(), NAMES[row], "DIALOG",
			function() return db[keyX], db[keyY] end,
			function(x, y) db[keyX], db[keyY] = x, y end, nil, true)
	end
	if ns.interactHud then
		movers.prompt = CreateMover(ns.interactHud, 280, 46, "INTERACT PROMPT", "DIALOG",
			function() return db.promptX, db.promptY end,
			function(x, y) db.promptX, db.promptY = x, y end)
		-- Shown only in move mode; the prompt itself is hidden when there is nothing to interact with.
	end
	if ns.lootFrame then
		movers.loot = CreateMover(ns.lootFrame, 300, 80, "LOOT ROLL", "DIALOG", GetLootPosition, SetLootPosition, UIParent)
	end
	-- Above every other handle, which can cover the middle of the screen.
	movers.all = CreateMover(ns.root, 90, 30, "ALL", "FULLSCREEN_DIALOG", GetWholePosition, SetWholePosition)
end

function ns.SetMoveMode(on)
	if on and not movers.all then
		CreateMovers()
	end
	ns.moving = on
	for _, mover in pairs(movers) do
		mover:SetShown(on)
	end
end

function ns.ResetPositions()
	if InCombatLockdown() then
		ns.Print("The bars cannot be moved in combat.")
		return
	end
	local defaults = ns.DEFAULTS
	local db = ns.db
	db.x, db.y = defaults.x, defaults.y
	db.promptX, db.promptY = defaults.promptX, defaults.promptY
	db.lootMoved = false
	for _, row in ipairs(ns.ROWS) do
		local keyX, keyY = "pos" .. row .. "x", "pos" .. row .. "y"
		db[keyX], db[keyY] = defaults[keyX], defaults[keyY]
	end
	ns.ApplyLayout()
end
