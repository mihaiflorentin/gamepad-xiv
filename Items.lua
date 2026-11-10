local _, ns = ...

-- Square moves the item under the controller cursor between the bags and an open bank, guild bank,
-- mail being written, auction house or trade, out of combat: what a mouse right-click does there.
--
-- Forever's bags give Square a job only when the item can be sold, equipped, used, opened or read,
-- so with a bank or a mailbox open most items (cloth, reagents) had none, and the bank's own slots
-- none at all. None of Forever's code is called from here, since addon code running it taints it:
-- Square gets a priority override binding of the addon's own, on a secure button that right-clicks
-- the focused item, a click that comes from the hardware press like a mouse click. With a vendor
-- open, or no such window, Square stays Forever's (sell, equip, use).

local MOVE_COMMAND = "CLICK GamepadXIVItemMove:RightButton"
local TAKE_COMMAND = "CLICK GamepadXIVItemMove:LeftButton"

local owner = CreateFrame("Frame") -- holds the addon's override binding
local moveButton, hint
local boundCommand -- the command Square has from the addon, or nil
local lastRebind = 0
local takenBack = false

local function Log(...)
	if ns.LfgLog then
		ns.LfgLog("items:", ...)
	end
end

local function Visible(frame)
	return frame and frame.IsVisible and frame:IsVisible()
end

local function NameOf(frame)
	return frame and frame.GetName and frame:GetName() or nil
end

-- The open window that takes items from the bags, its hint for a bag item, and its hint for one
-- of its own items.
local function OpenService()
	if Visible(MerchantFrame) then
		return nil -- Forever's Sell
	end
	if Visible(BankFrame) then
		return BankFrame, "Move to the bank", "Move to your bags"
	end
	if Visible(GuildBankFrame) then
		return GuildBankFrame, "Move to the guild bank", "Move to your bags"
	end
	if Visible(SendMailFrame) then
		return MailFrame, "Attach to the mail", "Take it back"
	end
	if Visible(OpenMailFrame) then
		return OpenMailFrame, nil, "Take into your bags"
	end
	if Visible(AuctionHouseFrame) then
		return AuctionHouseFrame, "Put up for auction", nil
	end
	if Visible(TradeFrame) then
		return TradeFrame, "Add to the trade", nil
	end
	return nil
end

local function IsBagItem(button)
	return ContainerFrameItemButtonMixin and button.OnClick == ContainerFrameItemButtonMixin.OnClick
		and button.GetBagID ~= nil
end

-- The backpack, the worn bags, the reagent bag and the keyring; not the bank or its tabs.
local function IsPlayerBag(bagID)
	if bagID == nil then
		return false
	end
	local index = Enum.BagIndex
	if index and index.Backpack then
		local last = index.ReagentBag or index.Bag_4 or NUM_BAG_SLOTS or 4
		return bagID == index.Keyring or (bagID >= index.Backpack and bagID <= last)
	end
	return bagID >= 0 and bagID <= (NUM_BAG_SLOTS or 4) or bagID == KEYRING_CONTAINER
end

local function HasItem(bagID, slot)
	local info = C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bagID, slot)
	return info ~= nil
end

-- What Square does on the focused button: the command and its hint, or nil to leave it to Forever.
local function FocusedAction()
	local service, toService, fromService = OpenService()
	-- Forever's cursor is in use: it keeps its last button when control goes back to the player.
	local nav = SmartNavigation
	local button = service and nav and nav.activeInfo and nav.currentButton
	if not (button and button.IsVisible and button:IsVisible()) then
		return nil
	end
	if IsBagItem(button) then
		if not HasItem(button:GetBagID(), button:GetID()) then
			return nil
		end
		local bagID = button:GetBagID()
		if not IsPlayerBag(bagID) then
			return Visible(BankFrame) and MOVE_COMMAND, button, "Move to your bags"
		end
		if not toService then
			return nil
		end
		if service == AuctionHouseFrame then
			-- Not one that can be sold there: a right-click would use or equip it instead.
			local location = ItemLocation and ItemLocation:CreateFromBagAndSlot(bagID, button:GetID())
			local valid = location and C_AuctionHouse and C_AuctionHouse.IsSellItemValid
				and C_AuctionHouse.IsSellItemValid(location, false)
			if not valid then
				return nil
			end
		end
		return MOVE_COMMAND, button, toService
	end
	local name = NameOf(button)
	-- Forever's bank: a panel of tabs, each a container (a right-click takes the item out).
	if service == BankFrame and BankPanelItemButtonMixin and button.OnClick == BankPanelItemButtonMixin.OnClick
		and button.GetBankTabID and button.GetContainerSlotID then
		return HasItem(button:GetBankTabID(), button:GetContainerSlotID()) and MOVE_COMMAND, button, fromService
	end
	-- The older bank window's own slots.
	if service == BankFrame and BankSlotsFrame and button:GetParent() == BankSlotsFrame and not button.isBag then
		return HasItem(BANK_CONTAINER or -1, button:GetID()) and MOVE_COMMAND, button, fromService
	end
	if service == GuildBankFrame and GuildBankItemButtonMixin and button.OnClick == GuildBankItemButtonMixin.OnClick then
		local tab = GetCurrentGuildBankTab and GetCurrentGuildBankTab()
		local texture = tab and GetGuildBankItemInfo and GetGuildBankItemInfo(tab, button:GetID())
		return texture and MOVE_COMMAND, button, fromService
	end
	if service == MailFrame and name and name:match("^SendMailAttachment%d+$") then
		local hasItem = GetSendMailItem and GetSendMailItem(button:GetID())
		return hasItem and MOVE_COMMAND, button, fromService
	end
	if service == OpenMailFrame and name and name:match("^OpenMailAttachmentButton%d+$") then
		return TAKE_COMMAND, button, fromService
	end
	return nil
end

-- The controller cursor is free: not in a menu or a popup.
local function CursorFree()
	local manager = Menu and Menu.GetManager and Menu.GetManager()
	if manager and manager:IsAnyMenuOpen() then
		return false
	end
	if GamepadPopupHandler and GamepadPopupHandler.IsStaticPopupShowing and GamepadPopupHandler:IsStaticPopupShowing() then
		return false
	end
	return not (CursorHasItem and CursorHasItem())
end

local function ClearBinding(reason)
	if boundCommand and not InCombatLockdown() then
		ClearOverrideBindings(owner)
		boundCommand = nil
		Log("binding cleared:", reason)
	end
end

-- The button prompts Forever shows under the window the cursor is in (Select, More, Close), if
-- shown: the footer of the button's window or of one it is in.
local function FooterLegend(button)
	local frame = button
	for _ = 1, 8 do
		if not frame then
			return nil
		end
		local footer = frame.gamepadFooter
		local legend = type(footer) == "table" and footer.inputLegend
		if legend and legend.IsVisible and legend:IsVisible() then
			return legend
		end
		frame = frame.GetParent and frame:GetParent()
	end
	return nil
end

-- The Square prompt: beside Forever's prompts, in its style, or under the window when there are none.
local function UpdateHint(text, service, button)
	if not hint then
		return
	end
	if not text then
		hint:Hide()
		hint.lastText, hint.lastService, hint.lastAnchor = nil, nil, nil
		return
	end
	local legend = FooterLegend(button)
	hint:ClearAllPoints()
	if legend then
		hint:SetParent(legend)
		hint:SetFrameStrata(legend:GetFrameStrata())
		hint:SetFrameLevel(legend:GetFrameLevel() + 5)
		hint:SetPoint("LEFT", legend, "RIGHT", 4, 0)
		hint.text:SetFontObject(GameFontNormal)
		hint.text:SetText(ns.ButtonMarkup("PAD3", ns.BUTTON_NAMES and ns.BUTTON_NAMES.PAD3 or "PAD3", 24) .. " " .. text)
		hint:SetBackdropColor(0.05, 0.04, 0.03, 0.9)
		hint:SetBackdropBorderColor(0.55, 0.45, 0.25, 0.9)
		hint:SetSize(hint.text:GetStringWidth() + 24, math.max(legend:GetHeight(), 34))
	else
		hint:SetParent(UIParent)
		hint:SetFrameStrata("DIALOG")
		hint:SetPoint("TOP", service, "BOTTOM", 0, -6)
		hint.text:SetFontObject(GameFontHighlight)
		hint.text:SetText(ns.ButtonText("{PAD3} " .. text, 20))
		hint:SetBackdropColor(0, 0, 0, 0.6)
		hint:SetBackdropBorderColor(0, 0, 0, 0)
		hint:SetSize(hint.text:GetStringWidth() + 24, 34)
	end
	hint.lastAnchor = legend or service
	hint:Show()
end

local function CreateMoveButton()
	moveButton = CreateFrame("Button", "GamepadXIVItemMove", UIParent, "SecureActionButtonTemplate")
	moveButton:RegisterForClicks("AnyDown", "AnyUp")
	moveButton:SetAttribute("useOnKeyDown", true)
	moveButton:SetAttribute("type", "click")
	moveButton:SetAttribute("type1", "click")
	moveButton:SetAttribute("type2", "click")
	moveButton:Hide()
	moveButton:HookScript("OnClick", function(self, mouse, down)
		if not down then
			return
		end
		Log("moved with", mouse, NameOf(self:GetAttribute("clickbutton")) or "an item")
	end)

	hint = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	hint:SetFrameStrata("DIALOG")
	hint:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	hint.text = hint:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	hint.text:SetPoint("CENTER")
	hint:Hide()
	if InputDeviceIconSetManager and InputDeviceIconSetManager.RegisterActiveInputDeviceIconSetUpdatedCallback then
		InputDeviceIconSetManager:RegisterActiveInputDeviceIconSetUpdatedCallback(function()
			hint.lastText = nil -- redrawn on the next check
		end, hint)
	end
end

-- Puts Square on the addon's button while the cursor is on an item it can move. Forever re-binds
-- when its own bindings change, so the binding is checked again and taken back.
local function Update()
	if InCombatLockdown() then
		return
	end
	local command, button, text
	if ns.IsGamepadUI and ns.IsGamepadUI() and CursorFree() then
		command, button, text = FocusedAction()
	end
	local service = command and OpenService()
	if not command then
		ClearBinding("nothing to move")
		UpdateHint(nil)
		return
	end
	if not moveButton then
		CreateMoveButton()
	end
	if moveButton:GetAttribute("clickbutton") ~= button then
		moveButton:SetAttribute("clickbutton", button)
		moveButton:SetAttribute("clickbutton1", button)
		moveButton:SetAttribute("clickbutton2", button)
	end
	local now = GetTime()
	if GetBindingAction("PAD3", true) ~= command and (boundCommand ~= command or now - lastRebind > 1) then
		if boundCommand ~= command or not takenBack then
			Log(boundCommand == command and "binding taken back:" or "binding set:", command, "was", GetBindingAction("PAD3", true))
			takenBack = boundCommand == command
		end
		local target, mouse = command:match("^CLICK ([^:]+):(.+)$")
		SetOverrideBindingClick(owner, true, "PAD3", target, mouse)
		boundCommand = command
		lastRebind = now
	end
	-- Forever shows its prompts once the cursor settles, so where the prompt goes is checked again.
	if hint.lastText ~= text or hint.lastService ~= service or hint.lastAnchor ~= (FooterLegend(button) or service) then
		hint.lastText, hint.lastService = text, service
		UpdateHint(text, service, button)
	end
end

local watcher = CreateFrame("Frame")
local elapsedSince = 0
watcher:SetScript("OnUpdate", function(_, elapsed)
	elapsedSince = elapsedSince + elapsed
	if elapsedSince < 0.1 then
		return
	end
	elapsedSince = 0
	if not boundCommand and not OpenService() then
		UpdateHint(nil)
		takenBack = false
		return
	end
	Update()
end)

-- Combat: bindings freeze, so the addon's is taken off now (it can still change while this event
-- runs), and Square is Forever's again until it ends.
watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
watcher:SetScript("OnEvent", function()
	ClearBinding("combat")
	UpdateHint(nil)
end)

-- Experimental (openBagsWhenNeeded): the bags open when a spell waits for an item to be picked, and
-- at the mailbox. Forever opens them itself in both cases, but a player found them closed for a
-- scroll and at the mailbox; its check for spells looks only at SpellCanTargetItem. So a moment
-- later, if they are still closed, the addon opens them, and closes them when the spell is done if
-- it opened them. What it sees is logged with /gxiv lfglog.
local BAG_WAIT = 0.25
local openedForSpell = false

local function BagsOpen()
	return (IsBagOpen and IsBagOpen(0)) or Visible(ContainerFrameCombinedBags) or false
end

local function TargetingItem()
	local canItem = SpellCanTargetItem and SpellCanTargetItem() or false
	local canItemID = SpellCanTargetItemID and SpellCanTargetItemID() or false
	return canItem or canItemID, canItem, canItemID
end

local function BagsWanted()
	return ns.db and ns.db.openBagsWhenNeeded and ns.IsGamepadUI and ns.IsGamepadUI()
end

local function CheckSpell()
	local targeting, canItem, canItemID = TargetingItem()
	if targeting then
		local open = BagsOpen()
		Log("bags: spell waits for an item; SpellCanTargetItem", tostring(canItem), "SpellCanTargetItemID",
			tostring(canItemID), "bags open:", tostring(open))
		if not open and OpenAllBags then
			OpenAllBags()
			openedForSpell = BagsOpen()
			Log("bags: opened for the spell:", tostring(openedForSpell))
		end
	elseif openedForSpell then
		openedForSpell = false
		-- Left open when a window that uses the bags is open too.
		if not (Visible(MailFrame) or Visible(BankFrame) or Visible(MerchantFrame) or Visible(GuildBankFrame)
			or Visible(AuctionHouseFrame) or Visible(TradeFrame)) and CloseAllBags then
			CloseAllBags()
			Log("bags: closed after the spell")
		end
	end
end

local function CheckMail()
	if not Visible(MailFrame) then
		return
	end
	local open = BagsOpen()
	Log("bags: mailbox open, bags open:", tostring(open))
	if not open and OpenAllBags then
		OpenAllBags(MailFrame)
		Log("bags: opened for the mailbox:", tostring(BagsOpen()))
	end
end

local bagEvents = CreateFrame("Frame")
bagEvents:RegisterEvent("CURRENT_SPELL_CAST_CHANGED")
bagEvents:RegisterEvent("MAIL_SHOW")
bagEvents:SetScript("OnEvent", function(_, event)
	if not (BagsWanted() or openedForSpell) then
		return
	end
	-- After Forever's own handlers, which open the bags themselves when they can.
	C_Timer.After(BAG_WAIT, event == "MAIL_SHOW" and CheckMail or CheckSpell)
end)
