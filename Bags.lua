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
-- * With Forever's gamepad UI on and BagPad installed, BagPad keeps the bags and this window stands
--   aside.

local WHITE = "Interface\\Buttons\\WHITE8X8"
local PANEL = { 0.075, 0.075, 0.09, 0.97 }
local BORDER = { 0.25, 0.25, 0.3, 1 }
local GOLD = { 1, 0.82, 0 }
local SLOT, GAP, PAD, HEAD, FOOT = 37, 4, 12, 30, 26
local COLUMNS = 10

local Bags = { slots = {}, order = {}, parents = {}, cursor = 1 }
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
		return "off in the settings"
	elseif GamepadUI() and AddOnLoaded("BagPad") then
		return "BagPad keeps the bags while Forever's gamepad UI is on"
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

local function Call(button, method, ...)
	local fn = button[method]
	if type(fn) == "function" then
		pcall(fn, button, ...)
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
	local rows = math.max(1, math.ceil(#order / COLUMNS))
	window:SetSize(PAD * 2 + COLUMNS * SLOT + (COLUMNS - 1) * GAP, HEAD + PAD + rows * SLOT + (rows - 1) * GAP + FOOT)
	for i, button in ipairs(order) do
		local col, row = (i - 1) % COLUMNS, math.floor((i - 1) / COLUMNS)
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", window, "TOPLEFT", PAD + col * (SLOT + GAP), -(HEAD + row * (SLOT + GAP)))
		button:Show()
		DrawSlot(button, button.gxivBag, button.gxivSlot)
	end
	window.free:SetText((total - used) .. " / " .. total .. " free")
	if GetMoney and GetCoinTextureString then
		window.money:SetText(GetCoinTextureString(GetMoney()))
	end
	if Bags.cursor > #order then
		Bags.cursor = math.max(1, #order)
	end
	Bags.DrawCursor()
end

function Bags.Current()
	return Bags.order[Bags.cursor]
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
	return "{PAD1} " .. UseLabel() .. "   {PAD3} " .. (holding and "Put down" or "Pick up")
		.. "   {PAD4} Sort   {PADLSHOULDER}{PADRSHOULDER} Bag   {PAD2} Close"
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
		if C_Container.GetContainerItemInfo(button.gxivBag, button.gxivSlot) then
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

-- L1 / R1: the first slot of the bag before or after the one the cursor is in.
local function StepBag(delta)
	local current = Bags.Current()
	if not current then
		return
	end
	local starts, at = {}, 1
	for i, button in ipairs(Bags.order) do
		if i == 1 or button.gxivBag ~= Bags.order[i - 1].gxivBag then
			table.insert(starts, i)
		end
		if button == current then
			at = #starts
		end
	end
	Bags.cursor = starts[ns.StepWrap(at, delta, #starts)] or 1
end

function Bags.Open()
	if not InUse() then
		return
	end
	Build()
	if not window:IsShown() then
		window:Show()
		Bags.Layout()
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

local function SlotClick(mouse)
	return function()
		local button = Bags.Current()
		return button and button:GetName(), mouse
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
		"UNIT_QUEST_LOG_CHANGED", "CURSOR_CHANGED", "PLAYER_REGEN_ENABLED" }) do
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
		ns.Print("The bags window is " .. reason .. ".")
	end
end
