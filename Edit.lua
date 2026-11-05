local _, ns = ...

-- Edit mode: both rows stay on screen, so every slot on them can be filled by drag and drop.
-- The bottom row can also show any other set or the Expanded Hold sides.
local TAB_SET, TAB_EXPANDED = 1, 2
local TAB_LABELS = { "Set", "Expanded" }

local panel
local shownTab = TAB_SET
local shownSet = 1
local cursorWasOn = false

local function GetTabSides()
	local db = ns.db
	if shownTab == TAB_EXPANDED then
		return db.sideLR, db.sideRL
	end
	return ns.SideOf(shownSet, false), ns.SideOf(shownSet, true)
end

local function DescribeTab()
	if shownTab == TAB_EXPANDED then
		return "Bottom row: Expanded Hold, L2 then R2 (left), R2 then L2 (right)"
	end
	return "Bottom row: set " .. shownSet .. ". Top row: double tap"
end

local function RefreshPanel()
	panel.title:SetText(DescribeTab())
	for index, tab in ipairs(panel.tabs) do
		tab:SetEnabled(index ~= shownTab)
	end
	panel.prevSet:SetEnabled(shownTab == TAB_SET)
	panel.nextSet:SetEnabled(shownTab == TAB_SET)
	panel.move:SetText(ns.moving and "Stop moving" or "Move bars")
	panel.help:SetText(ns.moving and "Drag a blue handle to move that bar. ALL or Shift + drag moves all of them."
		or "Drag spells onto the slots. Click: pick up or place. Right click: clear.")
	ns.SetEditSides(GetTabSides())
end

local function CreatePanelButton(text, width, onClick)
	local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	button:SetSize(width, 24)
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	return button
end

function ns.CreateEditor()
	panel = CreateFrame("Frame", "GamepadXIVEditor", UIParent, "BackdropTemplate")
	panel:SetSize(590, 92)
	-- Fixed to the screen, so a moved bar never carries it away.
	panel:SetPoint("TOP", UIParent, "TOP", 0, -90)
	panel:SetFrameStrata("DIALOG")
	panel:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	panel:EnableMouse(true)
	panel:Hide()

	panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	panel.title:SetPoint("TOP", 0, -10)

	local icon = panel:CreateTexture(nil, "ARTWORK")
	icon:SetSize(32, 32)
	icon:SetPoint("TOPLEFT", 8, -8)
	icon:SetTexture(ns.ICON)

	panel.help = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	panel.help:SetPoint("TOP", panel.title, "BOTTOM", 0, -3)

	panel.tabs = {}
	for index, label in ipairs(TAB_LABELS) do
		local tab = CreatePanelButton(label, 76, function()
			shownTab = index
			RefreshPanel()
		end)
		tab:SetPoint("BOTTOMLEFT", 10 + (index - 1) * 78, 10)
		panel.tabs[index] = tab
	end

	panel.prevSet = CreatePanelButton("<", 28, function()
		shownSet = (shownSet - 2) % ns.NUM_SETS + 1
		RefreshPanel()
	end)
	panel.prevSet:SetPoint("BOTTOMLEFT", 170, 10)

	panel.nextSet = CreatePanelButton(">", 28, function()
		shownSet = shownSet % ns.NUM_SETS + 1
		RefreshPanel()
	end)
	panel.nextSet:SetPoint("LEFT", panel.prevSet, "RIGHT", 2, 0)

	panel.move = CreatePanelButton("Move bars", 90, function()
		ns.SetMoveMode(not ns.moving)
		RefreshPanel()
	end)
	panel.move:SetPoint("LEFT", panel.nextSet, "RIGHT", 6, 0)

	local reset = CreatePanelButton("Reset", 54, function() ns.ResetPositions() end)
	reset:SetPoint("LEFT", panel.move, "RIGHT", 2, 0)

	local settings = CreatePanelButton("Settings", 70, function() ns.OpenConfig() end)
	settings:SetPoint("LEFT", reset, "RIGHT", 6, 0)

	local done = CreatePanelButton("Done", 60, function() panel:Hide() end)
	done:SetPoint("LEFT", settings, "RIGHT", 2, 0)

	panel:SetScript("OnHide", function()
		if ns.editing then
			ns.EndEdit()
		end
	end)
end

-- The combat state driver can end editing on its own; this only tidies up the visible part.
function ns.OnEditEnded()
	ns.editing = false
	ns.SetMoveMode(false)
	if panel:IsShown() then
		panel:Hide()
	end
	ns.RefreshVisuals()
	if ns.IsGamepadUI() and not cursorWasOn then
		SetGamePadCursorControl(false)
	end
end

function ns.ToggleEditor()
	if not panel then
		return
	end
	if ns.editing then
		panel:Hide()
		return
	end
	if InCombatLockdown() then
		ns.Print("Editing is not available in combat.")
		return
	end
	if not ns.IsActive() then
		ns.Print("Editing needs the layout to be active. See /fc status.")
		return
	end

	shownTab = TAB_SET
	shownSet = ns.currentSet or ns.db.set
	ns.editing = true
	ns.BeginEdit(GetTabSides())
	panel:Show()
	RefreshPanel()

	-- A controller has no pointer otherwise.
	if ns.IsGamepadUI() then
		cursorWasOn = IsGamePadCursorControlEnabled()
		SetGamePadCursorControl(true)
	end
end

-- Move mode lives inside the editor, which already brings the cursor and leaves on combat.
function ns.ToggleMove()
	if not panel then
		return
	end
	if not ns.editing then
		ns.ToggleEditor()
		if not ns.editing then
			return
		end
		ns.SetMoveMode(true)
	else
		ns.SetMoveMode(not ns.moving)
	end
	RefreshPanel()
end

function ns.OnSlotClick(button, mouseButton)
	if mouseButton == "RightButton" then
		PickupAction(button.action)
		ClearCursor()
	elseif GetCursorInfo() then
		PlaceAction(button.action)
	elseif C_ActionBar.HasAction(button.action) then
		PickupAction(button.action)
	end
end
