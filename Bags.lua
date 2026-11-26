local _, ns = ...

-- The bags window (alpha, docs/UI-REPLACEMENT-PLAN.md, "Replacements" row 1). Off by default
-- (bagWindow). It replaces the game's bag windows with one grid moved with the D-pad.
--
-- * Slots are the game's own item buttons (ContainerFrameItemButtonTemplate), one parent frame per bag
--   with the bag's ID, as ElvUI builds them. {PAD1} is bound straight to the slot's right click and
--   {PAD3} to its left click (Nav.lua "clicks"), so the game's secure click code runs: use or equip,
--   sell at a vendor, put in the bank, mail or trade; pick up and put down.
-- * The game's bag windows are moved under a hidden frame (SetParent, a widget method), so they stay
--   out of sight without writing anything into Blizzard's code. The game still opens and closes them;
--   post-hooks on its open, close and toggle functions show and hide this window instead.
-- * It needs Forever's gamepad UI off. With it on, Forever's focus manager takes the game's bag
--   window as focused whenever a bag opens (FrameControlsManager.lua, "ContainerFrame.OpenBag"), even
--   out of sight, and would fight this window for the controller.

local WHITE = "Interface\\Buttons\\WHITE8X8"
local PANEL = { 0.075, 0.075, 0.09, 0.97 }
local BORDER = { 0.25, 0.25, 0.3, 1 }
local GOLD = { 1, 0.82, 0 }
local SLOT, GAP, PAD, HEAD, FOOT = 37, 4, 12, 76, 26 -- HEAD: the title row and the bag slots row
local COLUMNS = 10

local Bags = { slots = {}, order = {}, parents = {}, cursor = 1, equip = {}, filter = 1 }

-- Quick filters, picked with L2 / R2 without a keyboard: the other items are dimmed.
-- classes: C_Item.GetItemInfoInstant's class IDs.
local FILTERS = {
	{ name = "All" },
	{ name = "Consumables", classes = { [0] = true } },
	{ name = "Equipment", classes = { [2] = true, [4] = true } },
	{ name = "Quest items", classes = { [12] = true }, quest = true },
	{ name = "Trade goods", classes = { [7] = true } },
	{ name = "Junk", quality = 0 },
}
Bags.FILTERS = FILTERS
ns.Bags = Bags

local hidden = CreateFrame("Frame")
hidden:Hide()

local window, highlight

local function Log(...)
	if ns.PlayLog then
		ns.PlayLog("bags:", ...)
	end
end

---------------------------------------------------------------------------------------------------
-- When this window is in use

local function AddOnLoaded(name)
	local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
	return loaded and loaded(name) and true or false
end

local function GamepadUI()
	return InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled() or false
end

-- Why the window stands aside, or nil when it is in use.
function ns.BagsStandAside()
	if not (ns.db and ns.db.bagWindow) then
		return "it is off in the settings"
	elseif GamepadUI() then
		return "it needs Forever's gamepad UI off (Options > Gameplay > Gamepad > Enable Gamepad UI, then /reload)"
	elseif AddOnLoaded("BagPad") then
		return "BagPad is loaded; turn BagPad off to use it"
	end
	return nil
end

local function InUse()
	return Bags.active == true
end

---------------------------------------------------------------------------------------------------
-- Which bags and slots

local function BagIDs()
	local ids = {}
	local last = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
	for bag = 0, last do
		if (C_Container.GetContainerNumSlots(bag) or 0) > 0 then
			table.insert(ids, bag)
		end
	end
	return ids
end

local function Parent(bag)
	local parent = Bags.parents[bag]
	if not parent then
		parent = CreateFrame("Frame", "GamepadXIVBagsBag" .. bag, window)
		parent:SetID(bag)
		parent:SetAllPoints(window)
		Bags.parents[bag] = parent
	end
	return parent
end

-- The slot button for a bag slot. New buttons are made out of combat only.
local function Slot(bag, slot)
	local key = bag * 1000 + slot
	local button = Bags.slots[key]
	if button or InCombatLockdown() then
		return button
	end
	button = CreateFrame("ItemButton", "GamepadXIVBagsB" .. bag .. "S" .. slot, Parent(bag), "ContainerFrameItemButtonTemplate")
	button:SetID(slot)
	button:SetSize(SLOT, SLOT)
	Bags.slots[key] = button
	return button
end

-- The game's slot methods, each in a pcall so one that fails doesn't stop the rest. A failure goes
-- to the play log once per method.
local failed = {}
local function Call(button, method, ...)
	local fn = button[method]
	if type(fn) == "function" then
		local ok, err = pcall(fn, button, ...)
		if not ok and not failed[method] then
			failed[method] = true
			Log("slot method failed:", method, tostring(err))
		end
	end
end

-- Draws a slot the way the game's bag window does (ContainerFrameMixin:UpdateItems).
local function DrawSlot(button, bag, slot)
	local info = C_Container.GetContainerItemInfo(bag, slot)
	local texture = info and info.iconFileID
	local quest = C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(bag, slot) or {}
	if ClearItemButtonOverlay then pcall(ClearItemButtonOverlay, button) end
	Call(button, "SetHasItem", texture)
	Call(button, "SetItemButtonTexture", texture)
	Call(button, "SyncAppearanceWithHasItem")
	if SetItemButtonQuality then pcall(SetItemButtonQuality, button, info and info.quality, info and info.hyperlink, false, info and info.isBound) end
	if SetItemButtonCount then pcall(SetItemButtonCount, button, info and info.stackCount) end
	if SetItemButtonDesaturated then pcall(SetItemButtonDesaturated, button, info and info.isLocked) end
	Call(button, "UpdateQuestItem", quest.isQuestItem, quest.questID, quest.isActive)
	Call(button, "UpdateNewItem", info and info.quality)
	Call(button, "UpdateJunkItem", info and info.quality, info and info.hasNoValue)
	Call(button, "UpdateCooldown", texture)
	Call(button, "SetReadable", info and info.isReadable)
	Call(button, "SetMatchesSearch", Bags.Matches(info, quest))
end

-- Whether an item passes the search box (the game's own search, info.isFiltered) and the filter.
function Bags.Matches(info, quest)
	local filter = FILTERS[Bags.filter] or FILTERS[1]
	if not info then
		return filter.classes == nil and filter.quality == nil
	end
	if info.isFiltered then
		return false
	end
	if filter.quality and info.quality ~= filter.quality then
		return false
	end
	if filter.classes then
		local classID = info.itemID and C_Item and C_Item.GetItemInfoInstant and select(6, C_Item.GetItemInfoInstant(info.itemID))
		if not (classID and filter.classes[classID]) and not (filter.quest and quest and (quest.isQuestItem or quest.questID)) then
			return false
		end
	end
	return true
end

---------------------------------------------------------------------------------------------------
-- The window

local function Fill(frame, color)
	local texture = frame:CreateTexture(nil, "BACKGROUND")
	texture:SetTexture(WHITE)
	texture:SetVertexColor(unpack(color))
	texture:SetAllPoints()
	return texture
end

local function Build()
	if window then
		return window
	end
	window = CreateFrame("Frame", "GamepadXIVBags", UIParent)
	window:SetFrameStrata("HIGH")
	window:SetClampedToScreen(true)
	window:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -80, 180)
	window:EnableMouse(true)
	window:Hide()
	local border = window:CreateTexture(nil, "BACKGROUND", nil, -1)
	border:SetTexture(WHITE)
	border:SetVertexColor(unpack(BORDER))
	border:SetPoint("TOPLEFT", -1, 1)
	border:SetPoint("BOTTOMRIGHT", 1, -1)
	Fill(window, PANEL)

	window.title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	window.title:SetPoint("TOPLEFT", PAD, -8)
	window.title:SetText("Bags")
	window.title:SetTextColor(unpack(GOLD))
	window.free = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	window.free:SetPoint("LEFT", window.title, "RIGHT", 10, -1)
	window.money = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	window.money:SetPoint("TOPRIGHT", -PAD, -10)
	window.filter = window:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	window.filter:SetPoint("TOPRIGHT", -PAD, -32)

	-- The search box (a keyboard types in it; {PADRSTICK} puts the cursor in it). The game's own item
	-- search does the matching, so it is the same search as its bag windows.
	local search = CreateFrame("EditBox", "GamepadXIVBagsSearch", window, "SearchBoxTemplate")
	search:SetSize(150, 20)
	search:SetPoint("RIGHT", window.filter, "LEFT", -12, 0)
	search:SetAutoFocus(false)
	search:HookScript("OnTextChanged", function(box)
		if C_Container.SetItemSearch then
			C_Container.SetItemSearch(box:GetText() or "")
		end
	end)
	window.search = search

	-- The equipped bags: the backpack, then the four bag slots. {PAD3} picks a bag up or puts the
	-- one held there, so a bigger bag replaces a smaller one.
	local bagSlots = NUM_BAG_SLOTS or 4
	for i = 0, bagSlots do
		local equip = CreateFrame("Button", "GamepadXIVBagsEquip" .. i, window)
		equip:SetSize(SLOT - 4, SLOT - 4)
		equip:SetPoint("TOPLEFT", PAD + i * (SLOT + GAP), -32)
		equip.icon = equip:CreateTexture(nil, "ARTWORK")
		equip.icon:SetAllPoints()
		equip.gxivEquip = i
		Bags.equip[i] = equip
	end

	window.hint = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	window.hint:SetPoint("BOTTOMLEFT", PAD, 8)
	window.hint:SetPoint("BOTTOMRIGHT", -PAD, 8)
	window.hint:SetJustifyH("LEFT")

	-- The cursor: a gold frame over the slot it is on.
	highlight = CreateFrame("Frame", nil, window)
	highlight:SetFrameLevel(window:GetFrameLevel() + 30)
	for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", 0, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 0, 2 },
			{ "TOPLEFT", "BOTTOMLEFT", 2, 0 }, { "TOPRIGHT", "BOTTOMRIGHT", 2, 0 } }) do
		local line = highlight:CreateTexture(nil, "OVERLAY")
		line:SetTexture(WHITE)
		line:SetVertexColor(unpack(GOLD))
		line:SetPoint(side[1], -2, 2)
		line:SetPoint(side[2], 2, -2)
		if side[3] > 0 then line:SetWidth(side[3]) else line:SetHeight(side[4]) end
	end
	highlight:Hide()

	window:SetScript("OnHide", function()
		GameTooltip:Hide()
		if ns.NavClosed then ns.NavClosed("Bags") end
	end)
	return window
end

-- Lays out every slot of every bag in one grid, bag after bag.
function Bags.Layout()
	if not window then
		return
	end
	local order, used, total = {}, 0, 0
	local seen = {}
	for i = 0, #Bags.equip do
		local equip = Bags.equip[i]
		Bags.DrawEquip(equip)
		table.insert(order, equip)
	end
	for _, bag in ipairs(BagIDs()) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local button = Slot(bag, slot)
			if button then
				table.insert(order, button)
				seen[button] = true
				total = total + 1
				if C_Container.GetContainerItemInfo(bag, slot) then
					used = used + 1
				end
				button.gxivBag, button.gxivSlot = bag, slot -- this addon's own fields, read only by it
			end
		end
	end
	for _, button in pairs(Bags.slots) do
		if not seen[button] then
			button:Hide()
		end
	end
	Bags.order = order
	local slotCount = #order - (#Bags.equip + 1)
	local rows = math.max(1, math.ceil(slotCount / COLUMNS))
	window:SetSize(PAD * 2 + COLUMNS * SLOT + (COLUMNS - 1) * GAP, HEAD + PAD + rows * SLOT + (rows - 1) * GAP + FOOT)
	local first = #Bags.equip + 2
	for i = first, #order do
		local button = order[i]
		local n = i - first
		local col, row = n % COLUMNS, math.floor(n / COLUMNS)
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", window, "TOPLEFT", PAD + col * (SLOT + GAP), -(HEAD + row * (SLOT + GAP)))
		button:Show()
		DrawSlot(button, button.gxivBag, button.gxivSlot)
	end
	window.filter:SetText(ns.ButtonText("{PADLTRIGGER}{PADRTRIGGER} ", 12) .. (FILTERS[Bags.filter] or FILTERS[1]).name)
	window.free:SetText((total - used) .. " / " .. total .. " free")
	if GetMoney and GetCoinTextureString then
		window.money:SetText(GetCoinTextureString(GetMoney()))
	end
	if Bags.cursor > #order then
		Bags.cursor = math.max(1, #order)
	end
	Bags.DrawCursor()
end

-- The inventory slot an equipped bag button stands for (nil for the backpack).
local function EquipInventoryID(equip)
	local i = equip and equip.gxivEquip
	if not i or i == 0 then
		return nil
	end
	return C_Container.ContainerIDToInventoryID and C_Container.ContainerIDToInventoryID(i) or nil
end

function Bags.DrawEquip(equip)
	local inv = EquipInventoryID(equip)
	local texture
	if equip.gxivEquip == 0 then
		texture = "Interface\\Buttons\\Button-Backpack-Up"
	else
		texture = inv and GetInventoryItemTexture("player", inv) or "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"
	end
	equip.icon:SetTexture(texture)
	equip:Show()
end

function Bags.Current()
	return Bags.order[Bags.cursor]
end

local function OnEquip()
	local current = Bags.Current()
	return current and current.gxivEquip ~= nil and current or nil
end

-- What {PAD1} does to the slot right now, the way the game's right click decides.
local function UseLabel()
	if MerchantFrame and MerchantFrame:IsShown() then
		return "Sell"
	elseif BankFrame and BankFrame:IsShown() then
		return "To the bank"
	elseif SendMailFrame and SendMailFrame:IsVisible() then
		return "Attach"
	elseif TradeFrame and TradeFrame:IsShown() then
		return "Trade"
	end
	return "Use"
end

function Bags.Hint()
	local holding = GetCursorInfo and GetCursorInfo() == "item"
	local equip = OnEquip()
	if equip then
		if equip.gxivEquip == 0 then
			return "{PAD1} Its slots   {PADRSTICK} Search   {PAD2} Close"
		end
		return "{PAD1} Its slots   {PAD3} " .. (holding and "Put the bag here" or "Pick up the bag")
			.. "   {PADRSTICK} Search   {PAD2} Close"
	end
	return "{PAD1} " .. UseLabel() .. "   {PAD3} " .. (holding and "Put down" or "Pick up")
		.. "   {PAD4} Sort   {PADLSHOULDER}{PADRSHOULDER} Bag   {PADRSTICK} Search   {PAD2} Close"
end

-- Moves the gold frame and the tooltip to the slot the cursor is on.
function Bags.DrawCursor()
	if not window or not window:IsShown() then
		return
	end
	local button = Bags.Current()
	local focused = ns.NavFocused and ns.NavFocused() == "Bags"
	if button and focused then
		highlight:ClearAllPoints()
		highlight:SetAllPoints(button)
		highlight:Show()
		GameTooltip:SetOwner(window, "ANCHOR_NONE")
		GameTooltip:SetPoint("BOTTOMRIGHT", window, "BOTTOMLEFT", -8, 0)
		local inv = button.gxivEquip and EquipInventoryID(button)
		if button.gxivEquip then
			if inv and GetInventoryItemTexture("player", inv) then
				GameTooltip:SetInventoryItem("player", inv)
				GameTooltip:Show()
			elseif button.gxivEquip == 0 then
				GameTooltip:SetText(BACKPACK_TOOLTIP or "Backpack")
				GameTooltip:Show()
			else
				GameTooltip:SetText(ns.ButtonText("Empty bag slot: {PAD3} puts a bag held here", 14))
				GameTooltip:Show()
			end
		elseif C_Container.GetContainerItemInfo(button.gxivBag, button.gxivSlot) then
			GameTooltip:SetBagItem(button.gxivBag, button.gxivSlot)
			GameTooltip:Show()
		else
			GameTooltip:Hide()
		end
	else
		highlight:Hide()
		if GameTooltip:GetOwner() == window then
			GameTooltip:Hide()
		end
	end
	window.hint:SetText(focused and ns.NavHint(ns.NavWindow("Bags"), 14) or ns.ButtonText("{PADBACK} Bags", 14))
end

local function Move(direction)
	local nodes = Bags.order
	if #nodes == 0 then
		return
	end
	Bags.cursor = ns.NavPick(nodes, Bags.cursor, direction)
end

-- The first item slot of a bag, or nil when it has none on show.
local function FirstSlotOf(bag)
	for i, button in ipairs(Bags.order) do
		if button.gxivBag == bag then
			return i
		end
	end
end

-- L1 / R1: the first slot of the bag before or after the one the cursor is in.
local function StepBag(delta)
	local current = Bags.Current()
	if not current then
		return
	end
	local starts, at = {}, 1
	local previous
	for i, button in ipairs(Bags.order) do
		if button.gxivBag and button.gxivBag ~= previous then
			table.insert(starts, i)
			previous = button.gxivBag
		end
		if button == current then
			at = #starts
		end
	end
	if current.gxivEquip then
		at = delta > 0 and 0 or #starts + 1
	end
	Bags.cursor = starts[ns.StepWrap(at, delta, #starts)] or 1
end

-- L2 / R2: the next quick filter.
local function StepFilter(delta)
	Bags.filter = ns.StepWrap(Bags.filter, delta, #FILTERS)
	Bags.Layout()
end

-- {PAD1} on an equipped bag: to its first slot.
local function EquipUse()
	local equip = OnEquip()
	local first = equip and FirstSlotOf(equip.gxivEquip)
	if first then
		Bags.cursor = first
	end
end

-- {PAD3} on an equipped bag: pick it up, or put the held bag there.
local function EquipPickUp()
	local equip = OnEquip()
	local inv = EquipInventoryID(equip)
	if not inv then
		return
	end
	if GetCursorInfo and GetCursorInfo() == "item" then
		if PutItemInBag then PutItemInBag(inv) end
	elseif PickupBagFromSlot then
		PickupBagFromSlot(inv)
	end
end

function Bags.Open()
	if not InUse() then
		return
	end
	Build()
	if not window:IsShown() then
		window:Show()
		Bags.Layout()
		-- Opening starts on the items, not on the equipped bags row.
		if Bags.Current() and Bags.Current().gxivEquip and #Bags.order > #Bags.equip + 1 then
			Bags.cursor = #Bags.equip + 2
		end
		Log("open")
	end
	if ns.NavOpened then
		ns.NavOpened("Bags")
	end
	Bags.DrawCursor()
end

function Bags.Close()
	if window and window:IsShown() then
		window:Hide()
		Log("close")
	end
end

function Bags.Toggle()
	if window and window:IsShown() then
		Bags.Close()
	else
		Bags.Open()
	end
end

---------------------------------------------------------------------------------------------------
-- Navigation (Nav.lua)

-- Item slots press the game's own button; the equipped bags row uses the keys below instead.
local function SlotClick(mouse)
	return function()
		local button = Bags.Current()
		if button and button.gxivBag then
			return button:GetName(), mouse
		end
		return nil
	end
end

ns.NavRegister({
	name = "Bags", group = "player", order = 10,
	IsOpen = function() return window ~= nil and window:IsShown() end,
	keys = {
		PADDUP = function() Move("UP") end,
		PADDDOWN = function() Move("DOWN") end,
		PADDLEFT = function() Move("LEFT") end,
		PADDRIGHT = function() Move("RIGHT") end,
		PADLSHOULDER = function() StepBag(-1) end,
		PADRSHOULDER = function() StepBag(1) end,
		PAD4 = function()
			if C_Container.SortBags then
				C_Container.SortBags()
			end
		end,
		PAD2 = function() Bags.Close() end,
		PAD1 = EquipUse,
		PAD3 = EquipPickUp,
		PADLTRIGGER = function() StepFilter(-1) end,
		PADRTRIGGER = function() StepFilter(1) end,
		PADRSTICK = function()
			if window and window.search then
				window.search:SetFocus()
			end
		end,
	},
	clicks = {
		PAD1 = SlotClick("RightButton"),
		PAD3 = SlotClick("LeftButton"),
	},
	Hint = Bags.Hint,
	Redraw = function() Bags.DrawCursor() end,
	OnFocus = function() Bags.DrawCursor() end,
	OnBlur = function() Bags.DrawCursor() end,
})

---------------------------------------------------------------------------------------------------
-- Taking over from the game's bag windows

-- Out of sight: under a frame that never shows. Out of combat only.
local function HideGameBags()
	if InCombatLockdown() then
		Bags.hidePending = true
		return
	end
	Bags.hidePending = nil
	local frames = { _G.ContainerFrameCombinedBags }
	local i = 1
	while _G["ContainerFrame" .. i] do
		table.insert(frames, _G["ContainerFrame" .. i])
		i = i + 1
	end
	for _, frame in ipairs(frames) do
		if frame:GetParent() ~= hidden then
			frame:SetParent(hidden)
		end
	end
	Log("game bag windows hidden:", #frames)
end

-- The game opened, closed or toggled its bags. Several of its functions call each other (a toggle
-- closes the backpack, which closes every bag), so what happened in one frame is settled once, a
-- frame later: a toggle flips this window, else an open shows it, else a close hides it.
local pending
local function Settle()
	local what = pending
	pending = nil
	if not InUse() or not what then
		return
	end
	if what.toggle then
		Bags.Toggle()
	elseif what.open then
		Bags.Open()
	elseif what.close and not (IsAnyBagOpen and IsAnyBagOpen()) then
		Bags.Close()
	end
end

local function Note(kind)
	return function()
		if not InUse() then
			return
		end
		if not pending then
			pending = {}
			C_Timer.After(0, Settle)
		end
		pending[kind] = true
	end
end

local hooked = false
local function Hook()
	if hooked then
		return
	end
	hooked = true
	for _, name in ipairs({ "ToggleAllBags", "ToggleBackpack", "ToggleBag" }) do
		if _G[name] then hooksecurefunc(name, Note("toggle")) end
	end
	for _, name in ipairs({ "OpenAllBags", "OpenBackpack", "OpenBag" }) do
		if _G[name] then hooksecurefunc(name, Note("open")) end
	end
	for _, name in ipairs({ "CloseAllBags", "CloseBackpack" }) do
		if _G[name] then hooksecurefunc(name, Note("close")) end
	end
end

function Bags.Start()
	local reason = ns.BagsStandAside()
	if reason then
		Bags.active = false
		Log("not in use:", reason)
		return
	end
	Bags.active = true
	Build()
	Hook()
	HideGameBags()
	Log("in use")
end

---------------------------------------------------------------------------------------------------
-- Events

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED", "BAG_UPDATE_COOLDOWN",
		"PLAYER_MONEY", "MERCHANT_SHOW", "MERCHANT_CLOSED", "BAG_CONTAINER_UPDATE", "QUEST_ACCEPTED",
		"UNIT_QUEST_LOG_CHANGED", "CURSOR_CHANGED", "PLAYER_REGEN_ENABLED", "INVENTORY_SEARCH_UPDATE",
		"PLAYER_EQUIPMENT_CHANGED" }) do
	events:RegisterEvent(event)
end
local drawQueued = false
local function QueueLayout()
	if drawQueued then
		return
	end
	drawQueued = true
	C_Timer.After(0.05, function()
		drawQueued = false
		if window and window:IsShown() then
			Bags.Layout()
		end
	end)
end
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		Bags.Start()
	elseif event == "PLAYER_REGEN_ENABLED" then
		if Bags.hidePending and InUse() then
			HideGameBags()
		end
		QueueLayout()
	elseif event == "CURSOR_CHANGED" then
		Bags.DrawCursor()
	elseif InUse() then
		QueueLayout()
	end
end)

-- The settings changed: the window takes over at once, but giving the bags back needs a reload.
function ns.ApplyBagWindow()
	local reason = ns.BagsStandAside()
	if not reason and not Bags.active then
		Bags.Start()
		ns.Print("The bags window is on. Your bags open in it now.")
	elseif reason and Bags.active then
		Bags.Close()
		Bags.active = false
		ns.Print("The bags window is off. /reload to get the game's bags back.")
	elseif reason then
		ns.Print("The bags window is not in use: " .. reason .. ".")
	end
end
