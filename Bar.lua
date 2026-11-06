local _, ns = ...

local BUTTON_SIZE = 40
-- Half the width of one diamond of buttons: the side offset plus half a button.
local CLUSTER_HALF_WIDTH = BUTTON_SIZE * 0.8 + BUTTON_SIZE / 2

local movers = {}

-- Diamond offsets for the 1 left, 2 up, 3 right, 4 down cluster order, in button units.
local DIAMOND = { { -1, 0 }, { 0, 0.72 }, { 1, 0 }, { 0, -0.72 } }

local GOLD = { 1, 0.82, 0.25 }
local LAYER_COLORS = { L = GOLD, R = GOLD, WL = GOLD, WR = GOLD, LR = { 0.55, 1, 0.45 }, RL = { 0.55, 1, 0.45 } }
local LAYER_ROW = { L = "L", R = "R", WL = "WL", WR = "WR", LR = "L", RL = "R" }
local TRIGGER_LABELS = { L = "L2", R = "R2" }

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
	glow:SetBlendMode("ADD")
	glow:SetAlpha(0)
	side.glow = glow

	-- Selection animation: the glow swells in and settles while the side stays selected.
	local anim = glow:CreateAnimationGroup()
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
	side.selectAnim = anim

	side.label = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	side.label:SetPoint("TOP", content, "TOP", 0, 4)

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

		-- A separate multiply layer, because Blizzard's own usable state owns the icon's vertex color.
		local rangeTint = button:CreateTexture(nil, "BACKGROUND", nil, 7)
		rangeTint:SetAllPoints(button.icon)
		rangeTint:SetColorTexture(1, 0.2, 0.2)
		rangeTint:SetBlendMode("MOD")
		rangeTint:AddMaskTexture(button.IconMask)
		rangeTint:Hide()
		button.rangeTint = rangeTint

		-- Slots can be dragged out of combat regardless of the action bar lock.
		-- Blizzard's own handler already covers an unlocked bar or a modified drag.
		button:HookScript("OnDragStart", function(self)
			if not InCombatLockdown() and Settings.GetValue("lockActionBars") and not IsModifiedClick("PICKUPACTION") then
				PickupAction(self.action)
			end
		end)
		button:HookScript("OnClick", function(self, mouseButton, down)
			if ns.editing and not down and not InCombatLockdown() then
				ns.OnSlotClick(self, mouseButton)
			end
		end)

		side.buttons[i] = button
		button:Show()
	end

	-- Created after the buttons, so the marks sit on top of them.
	side.marks = CreateClusterMarks(content)
	return side
end

-- The R1 overlay: which button picks which set, laid out like the buttons themselves.
local function CreateSetPicker(root)
	local picker = CreateFrame("Frame", nil, root)
	picker:SetSize(190, 70)
	picker:SetPoint("BOTTOM", root, "CENTER", 0, 64) -- above the bottom row, between the top bars
	picker:Hide()

	local title = picker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	title:SetPoint("BOTTOM", 0, 0)
	title:SetText("CHANGE SET")

	-- Offsets around each cluster's centre: up, right, down, left.
	local AROUND = { { 0, 18 }, { 18, 0 }, { 0, -18 }, { -18, 0 } }
	picker.numbers = {}
	for set = 1, ns.NUM_SETS do
		local number = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		local around = AROUND[(set - 1) % 4 + 1]
		local clusterX = (set <= 4) and 55 or -55
		number:SetPoint("CENTER", picker, "CENTER", clusterX + around[1], 10 + around[2])
		number:SetText(set)
		picker.numbers[set] = number
	end
	root.setPicker = picker
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
end

function ns.ApplyLayout()
	local root = ns.root
	local db = ns.db
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

local function RefreshKeyIcons()
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
	root.softHint:SetText("Next ability goes here. A: make target. B: cancel.")
	root.softHint:Hide()

	-- Border on the unit frame of the temporary target.
	local softBorder = CreateFrame("Frame", nil, UIParent)
	softBorder:SetFrameStrata("HIGH")
	softBorder:Hide()
	for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
		local line = softBorder:CreateTexture(nil, "OVERLAY")
		line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
		line:SetPoint(edge[1])
		line:SetPoint(edge[2])
		if edge[1]:sub(1, 3) == edge[2]:sub(1, 3) then
			line:SetHeight(2)
		else
			line:SetWidth(2)
		end
	end
	root.softBorder = softBorder

	root.editHint = CreateFrame("Frame", nil, root)
	root.editHint:SetFrameStrata("HIGH")
	root.editHint:SetSize(60, 30)
	root.editHint:SetPoint("CENTER", root, "CENTER", 0, 42)
	root.editHint:Hide()
	local hintText = root.editHint:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hintText:SetPoint("CENTER")
	hintText:SetText("BACK\nEdit")

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
	ns.currentSet = set
	ns.l1Held = layer == "L1"

	local activeRow = not ns.editing and LAYER_ROW[layer]
	for _, row in ipairs(ns.ROWS) do
		local side = root.sides[row]
		if row == activeRow then
			local color = LAYER_COLORS[layer]
			side.glow:SetVertexColor(color[1], color[2], color[3])
			if ns.lastLayer ~= layer then
				side.selectAnim:Stop()
				side.selectAnim:Play()
			end
		else
			side.selectAnim:Stop()
			side.glow:SetAlpha(0)
		end
		side.marks:SetShown(row == activeRow)
	end
	root.editHint:SetShown(activeRow and true or false)

	local sides = root.sides
	if ns.editing then
		sides.L.label:SetText(DescribeLabel(leftSide))
		sides.R.label:SetText(DescribeLabel(rightSide))
		sides.WL.label:SetText("Double tap L2: " .. DescribeLabel(ns.db.sideWL))
		sides.WR.label:SetText("Double tap R2: " .. DescribeLabel(ns.db.sideWR))
		root.setText:SetText("EDIT")
	else
		sides.L.label:SetText(TRIGGER_LABELS.L)
		sides.R.label:SetText(TRIGGER_LABELS.R)
		sides.WL.label:SetText("")
		sides.WR.label:SetText("")
		root.setText:SetText("SET " .. set .. "  [R1]")
	end

	root.setPicker:SetShown(layer == "SET")
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
	local compact = CompactPartyFrame and CompactPartyFrame.memberUnitFrames
	if compact then
		for _, frame in ipairs(compact) do
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
	end
	local index = unit:match("^party(%d)$")
	frame = index and PartyFrame and PartyFrame["MemberFrame" .. index]
	return frame and frame:IsVisible() and frame or nil
end

-- Called from the secure driver: unit is "" when no temporary target is set.
function ns.ShowSoftTarget(unit)
	local root = ns.root
	root.softBorder:Hide()
	root.softHint:SetShown(unit ~= "")
	if unit == "" then
		root.softText:SetText("")
		return
	end
	-- The name can be a secret value in combat: it may be displayed, not concatenated or tested.
	root.softText:SetText(UnitName(unit))
	local frame = FindUnitFrame(unit)
	if frame then
		root.softBorder:ClearAllPoints()
		root.softBorder:SetAllPoints(frame)
		root.softBorder:Show()
	end
end

function ns.SetBarShown(shown)
	if ns.root then
		ns.root:SetAlpha(shown and 1 or 0)
	end
end

-- Move mode: a handle over each side, and one in the middle that carries all of them.
-- Shift + drag on any handle also carries all of them.
local function GetWholePosition()
	return ns.db.x, ns.db.y
end

local function SetWholePosition(x, y)
	ns.db.x, ns.db.y = x, y
end

local function CreateMover(anchor, width, height, labelText, strata, getPosition, setPosition)
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
		local carryAll = IsShiftKeyDown()
		local get, set = carryAll and GetWholePosition or getPosition, carryAll and SetWholePosition or setPosition
		local startCursorX, startCursorY = GetCursorPosition()
		local startX, startY = get()
		mover:SetScript("OnUpdate", function()
			if InCombatLockdown() then
				StopDrag()
				return
			end
			local cursorX, cursorY = GetCursorPosition()
			local scale = ns.root:GetEffectiveScale()
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
	local NAMES = { L = "L2", R = "R2", WL = "L2 L2", WR = "R2 R2" }
	for _, row in ipairs(ns.ROWS) do
		local keyX, keyY = "pos" .. row .. "x", "pos" .. row .. "y"
		local side = ns.root.sides[row]
		movers[row] = CreateMover(side, side:GetWidth(), side:GetHeight(), NAMES[row], "DIALOG",
			function() return db[keyX], db[keyY] end,
			function(x, y) db[keyX], db[keyY] = x, y end)
	end
	if ns.interactHud then
		movers.prompt = CreateMover(ns.interactHud, 280, 46, "INTERACT PROMPT", "DIALOG",
			function() return db.promptX, db.promptY end,
			function(x, y) db.promptX, db.promptY = x, y end)
		-- Shown only in move mode; the prompt itself is hidden when there is nothing to interact with.
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
	for _, row in ipairs(ns.ROWS) do
		local keyX, keyY = "pos" .. row .. "x", "pos" .. row .. "y"
		db[keyX], db[keyY] = defaults[keyX], defaults[keyY]
	end
	ns.ApplyLayout()
end
