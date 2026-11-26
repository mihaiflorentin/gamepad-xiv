local _, ns = ...

-- Square in the spellbook (spellbookAssign): the spell under the controller cursor goes to a slot
-- chosen on the crossbar, like moving an ability, instead of Forever's Bind to Action Bar, whose
-- page reaches only sets 1-3 and can't change the set. As with Square in the bags (Items.lua), none
-- of Forever's code is called: Square gets a priority override binding of the addon's own while the
-- cursor is on a spell, and the spell is read from the focused button's fields and the spellbook
-- API, never from its methods. The same press closes the spellbook through its close button, a
-- secure click from the hardware press, so the slot is chosen on the crossbar right away.

local owner = CreateFrame("Frame") -- holds the addon's override binding
local COMMAND = "CLICK GamepadXIVSpellbookPick:LeftButton"
local bound = false
local lastRebind = 0
local focusedSpell
local pick

local function Visible(frame)
	return frame and not (frame.IsForbidden and frame:IsForbidden()) and frame.IsVisible and frame:IsVisible()
end

local function SpellbookFrame()
	if Visible(PlayerSpellsFrame) then
		return PlayerSpellsFrame
	elseif Visible(SpellBookFrame) then
		return SpellBookFrame
	end
end

local function Inside(frame, parent)
	for _ = 1, 12 do
		if not frame then
			return false
		elseif frame == parent then
			return true
		end
		frame = frame.GetParent and frame:GetParent()
	end
	return false
end

local function Placeable(item)
	local kind = Enum.SpellBookItemType
	return type(item) == "table" and item.spellID and not item.isPassive and not item.isOffSpec
		and (item.itemType == nil or not kind or item.itemType == kind.Spell)
end

-- The spell of a spellbook button, from the button or its parents: the newer spellbook keeps it in
-- spellBookItemInfo or slotIndex / spellBank, the older one in the button's ID.
local function SpellOf(button)
	local book = C_SpellBook
	local frame = button
	for _ = 1, 3 do
		if not frame then
			break
		end
		if Placeable(frame.spellBookItemInfo) then
			return frame.spellBookItemInfo.spellID
		end
		if type(frame.slotIndex) == "number" and book and book.GetSpellBookItemInfo then
			local bank = frame.spellBank or (Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
			local item = book.GetSpellBookItemInfo(frame.slotIndex, bank)
			if Placeable(item) then
				return item.spellID
			end
		end
		if type(frame.spellID) == "number" and not (C_Spell.IsSpellPassive and C_Spell.IsSpellPassive(frame.spellID)) then
			return frame.spellID
		end
		frame = frame.GetParent and frame:GetParent()
	end
	return nil
end

local function ClearBinding()
	if bound and not InCombatLockdown() then
		ClearOverrideBindings(owner)
		bound = false
	end
end

local function CloseButtonOf(book)
	local name = book.GetName and book:GetName()
	local close = book.CloseButton or (name and _G[name .. "CloseButton"])
	return close and close.Click and close or nil
end

-- What was last seen, saved for reports (spellbookDebug): the button under the cursor, the spell
-- read from it and the close button, so a spellbook this misreads can be fixed from the file.
local function Note(book, button, spellID, close)
	local db = ns.db
	if not db then
		return
	end
	-- Some names come back as secret values, which can't even be compared; those are left out.
	local function Name(frame)
		if not frame then
			return "none"
		end
		local name = frame.GetName and frame:GetName() or frame.GetDebugName and frame:GetDebugName()
		if issecretvalue and issecretvalue(name) then
			return "secret"
		end
		return tostring(name)
	end
	local text = Name(book) .. " | " .. Name(button) .. " | spell " .. tostring(spellID) .. " | close " .. Name(close)
	if db.spellbookDebug ~= text then
		db.spellbookDebug = text
		ns.Trail("spellbook: " .. text)
	end
end

local function Update()
	focusedSpell = nil
	if InCombatLockdown() then
		return
	end
	local book = ns.db and ns.db.spellbookAssign and ns.IsActive and ns.IsActive() and SpellbookFrame()
	local nav = ns.Mode():Navigator()
	local button = book and nav and nav.activeInfo and nav.currentButton
	local close = book and CloseButtonOf(book)
	if button and Visible(button) and Inside(button, book) then
		focusedSpell = SpellOf(button)
	end
	if book then
		Note(book, button, focusedSpell, close)
	end
	if not focusedSpell then
		ClearBinding()
		return
	end
	if pick:GetAttribute("clickbutton") ~= close then
		pick:SetAttribute("clickbutton", close)
	end
	-- Forever binds again when its own bindings change, so Square is taken back now and then.
	local now = GetTime()
	if GetBindingAction("PAD3", true) ~= COMMAND and (not bound or now - lastRebind > 1) then
		SetOverrideBindingClick(owner, true, "PAD3", "GamepadXIVSpellbookPick", "LeftButton")
		bound = true
		lastRebind = now
	end
end

pick = CreateFrame("Button", "GamepadXIVSpellbookPick", UIParent, "SecureActionButtonTemplate")
pick:RegisterForClicks("AnyDown", "AnyUp")
pick:SetAttribute("useOnKeyDown", true)
pick:SetAttribute("type", "click")
pick:Hide()
-- After the secure click has closed the spellbook.
pick:HookScript("OnClick", function(_, _, down)
	local spellID = focusedSpell
	if down and spellID and not InCombatLockdown() then
		ns.StartPlaceSpell(spellID)
	end
end)

local watcher = CreateFrame("Frame")
local elapsedSince = 0
watcher:SetScript("OnUpdate", function(_, elapsed)
	elapsedSince = elapsedSince + elapsed
	if elapsedSince < 0.1 then
		return
	end
	elapsedSince = 0
	if not bound and not SpellbookFrame() and not (ns.db and ns.db.spellbookAssign) then
		focusedSpell = nil
		return
	end
	-- An error here would open the game's error window from this addon's code, and Forever's
	-- controls would carry this addon's taint from that window on, so none is let out.
	pcall(Update)
end)
-- Combat: bindings freeze, so Square is Forever's again until it ends.
watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
watcher:SetScript("OnEvent", function()
	ClearBinding()
	focusedSpell = nil
end)
