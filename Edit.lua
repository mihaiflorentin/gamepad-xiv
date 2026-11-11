local _, ns = ...

-- Move bars: every row stays on screen with a blue handle, to drag it with the mouse. It runs in
-- the driver's edit state, which keeps the rows shown, stops the slots from casting and ends by
-- itself in combat. Slots are filled by dragging onto them at any time, and R1 + a button shows
-- any set on the bottom row, so there is no slot editor.

local panel

local function CreatePanelButton(text, width, onClick)
	local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	button:SetSize(width, 24)
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	return button
end

function ns.CreateEditor()
	panel = CreateFrame("Frame", "GamepadXIVEditor", UIParent, "BackdropTemplate")
	panel:SetSize(420, 84)
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

	local icon = panel:CreateTexture(nil, "ARTWORK")
	icon:SetSize(32, 32)
	icon:SetPoint("TOPLEFT", 10, -10)
	icon:SetTexture(ns.ICON)

	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -1)
	title:SetText("Move bars")

	local help = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	help:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
	help:SetPoint("RIGHT", -12, 0)
	help:SetJustifyH("LEFT")
	help:SetText("Drag a blue handle to move that bar. ALL, or Shift + drag, moves all of them.")

	local done = CreatePanelButton("Done", 70, function() panel:Hide() end)
	done:SetPoint("BOTTOMRIGHT", -12, 10)

	local reset = CreatePanelButton("Reset positions", 120, function() ns.ResetPositions() end)
	reset:SetPoint("RIGHT", done, "LEFT", -4, 0)

	panel:SetScript("OnHide", function()
		if ns.editing then
			ns.EndEdit()
		end
	end)
end

-- The combat state driver can end it on its own; this only tidies up the visible part.
function ns.OnEditEnded()
	ns.editing = false
	ns.SetMoveMode(false)
	if panel:IsShown() then
		panel:Hide()
	end
	ns.RefreshVisuals()
end

function ns.ToggleMove()
	if not panel then
		return
	end
	if ns.editing then
		panel:Hide()
		return
	end
	if InCombatLockdown() then
		ns.Print("Moving the bars is not available in combat.")
		return
	end
	if not ns.IsActive() then
		ns.Print("Moving the bars needs the layout to be active. See /gxiv status.")
		return
	end
	local set = ns.currentSet or ns.db.set
	ns.editing = true
	ns.BeginEdit(ns.SideOf(set, false), ns.SideOf(set, true))
	ns.SetMoveMode(true)
	panel:Show()
end

-- Older ways in (/gxiv edit, L2/R2 + Back) open Move bars now.
ns.ToggleEditor = ns.ToggleMove
