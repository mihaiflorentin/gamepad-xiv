local _, ns = ...

-- Puts an ability, item or macro in a slot chosen on the crossbar, without the spellbook: in the move
-- or remove mode, an empty slot or Replace on a filled one opens this list. The D-pad chooses, left
-- and right jump a page, A selects and B goes back. Out of combat only, like moving abilities.
local ROWS = 8
local ROW_HEIGHT = 34

local SECTIONS = {
	{ label = "Abilities", icon = "Interface\\Icons\\INV_Misc_Book_09", detail = "abilities, at the highest rank you know", choices = function() return ns.RingSpellChoices() end },
	{ label = "Items", icon = "Interface\\Icons\\INV_Misc_Bag_08", detail = "items in your bags", choices = function() return ns.RingItemChoices() end },
	{ label = "Macros", icon = "Interface\\Icons\\INV_Misc_Note_01", detail = "account and character macros", choices = function() return ns.RingMacroChoices() end },
}

local panel, slot, onDone
local list, cursor, folder = {}, 1, nil

local function CreatePanel()
	panel = CreateFrame("Frame", "GamepadXIVAssignPanel", UIParent, "BackdropTemplate")
	panel:SetSize(440, 92 + ROWS * ROW_HEIGHT)
	panel:SetFrameStrata("HIGH")
	panel:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
	panel:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	panel:Hide()

	panel.slotIcon = panel:CreateTexture(nil, "ARTWORK")
	panel.slotIcon:SetSize(30, 30)
	panel.slotIcon:SetPoint("TOPLEFT", 16, -12)
	panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	panel.title:SetPoint("LEFT", panel.slotIcon, "RIGHT", 10, 0)
	panel.title:SetPoint("RIGHT", -16, 0)
	panel.title:SetJustifyH("LEFT")

	panel.rows = {}
	for i = 1, ROWS do
		local row = CreateFrame("Frame", nil, panel)
		row:SetSize(408, ROW_HEIGHT - 2)
		row:SetPoint("TOPLEFT", 16, -50 - (i - 1) * ROW_HEIGHT)
		row.highlight = row:CreateTexture(nil, "BACKGROUND")
		row.highlight:SetAllPoints()
		row.highlight:SetColorTexture(1, 0.82, 0.25, 0.25)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(26, 26)
		row.icon:SetPoint("LEFT", 4, 0)
		row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.label:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
		row.label:SetJustifyH("LEFT")
		row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		row.detail:SetPoint("RIGHT", -6, 0)
		row.detail:SetJustifyH("RIGHT")
		row.label:SetPoint("RIGHT", row.detail, "LEFT", -8, 0)
		panel.rows[i] = row
	end

	panel.hint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.hint:SetPoint("BOTTOM", 0, 14)
	panel.empty = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	panel.empty:SetPoint("TOP", 0, -70)
end

local function ShowList()
	local name = C_ActionBar and C_ActionBar.HasAction(slot) and ns.GetActionName(slot)
	panel.slotIcon:SetTexture(C_ActionBar and C_ActionBar.GetActionTexture(slot) or nil)
	panel.slotIcon:SetShown(name and true or false)
	local what = folder and folder.label:lower() or "something"
	panel.title:SetText(name and ("Replace " .. name .. " with " .. what) or ("Put " .. what .. " in this slot"))
	local first = math.floor((cursor - 1) / ROWS) * ROWS
	for i, row in ipairs(panel.rows) do
		local entry = list[first + i]
		row:SetShown(entry ~= nil)
		if entry then
			row.icon:SetTexture(entry.icon)
			row.label:SetText(entry.label)
			row.detail:SetText(entry.detail or "")
			row.highlight:SetShown(first + i == cursor)
		end
	end
	panel.empty:SetText(#list == 0 and "Nothing here." or "")
	panel.hint:SetText(ns.ButtonText("{PADDUP}{PADDDOWN} choose   {PADDLEFT}{PADDRIGHT} page   {PAD1} select   {PAD2} "
		.. (folder and "back" or "cancel"), 18))
end

local function OpenFolder(section)
	folder = section
	list = section and section.choices() or {}
	if not section then
		list = {}
		for _, entry in ipairs(SECTIONS) do
			tinsert(list, { label = entry.label, icon = entry.icon, detail = #entry.choices() .. " " .. entry.detail, section = entry })
		end
	end
	cursor = 1
	ShowList()
end

local function Finish()
	if onDone then
		onDone()
	end
end

-- Through the cursor, as dragging does. What was in the slot comes back on the cursor and is let go.
local function Place(data)
	if InCombatLockdown() then
		return
	end
	ClearCursor()
	if data.spell then
		(C_Spell and C_Spell.PickupSpell or PickupSpell)(data.spell)
	elseif data.item then
		(C_Item and C_Item.PickupItem or PickupItem)(data.item)
	elseif data.macro then
		PickupMacro(data.macro)
	end
	if GetCursorInfo() then
		PlaceAction(slot)
		ns.Trail("assign PlaceAction " .. tostring(slot))
	else
		ns.Print("That can't go on a bar.")
	end
	ClearCursor()
	Finish()
end

function ns.AssignNav(name)
	if not (panel and panel:IsShown()) then
		return
	end
	local count = #list
	if (name == "Up" or name == "Down") and count > 0 then
		cursor = (cursor - 1 + (name == "Up" and -1 or 1)) % count + 1
		ShowList()
	elseif (name == "Left" or name == "Right") and count > 0 then
		cursor = math.max(1, math.min(count, cursor + (name == "Left" and -ROWS or ROWS)))
		ShowList()
	elseif name == "Accept" then
		local entry = list[cursor]
		if entry and entry.section then
			OpenFolder(entry.section)
		elseif entry then
			Place(entry.data)
		end
	elseif name == "Back" then
		if folder then
			local from = folder
			OpenFolder(nil)
			for index, entry in ipairs(list) do
				if entry.section == from then
					cursor = index
				end
			end
			ShowList()
		else
			Finish()
		end
	end
end

-- done ends the move or remove mode; it is called once something was placed or on cancel.
function ns.OpenAssign(chosenSlot, done)
	if not panel then
		CreatePanel()
	end
	slot, onDone = chosenSlot, done
	OpenFolder(nil)
	panel:Show()
end

function ns.CloseAssign()
	if panel then
		panel:Hide()
	end
	slot, onDone, folder = nil, nil, nil
end
