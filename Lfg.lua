local _, ns = ...

-- Looking For Group (Forever's group finder, Blizzard_GroupFinder_VanillaStyle), out of combat:
-- Triangle refreshes the list, A on a group whispers its leader (after asking, by default) and
-- Square opens a group's menu, which then shows beside the window instead of in a screen corner.
--
-- Forever's menu navigation keeps A and B, and its bindings for an open window take the other face
-- buttons too. None of its code is called from here, since addon code running it taints it:
-- - Triangle and Square get priority override bindings of the addon's own, on clicks of secure
--   buttons that click the window's refresh button and right-click the entry under the controller
--   cursor. Those clicks come from the hardware press, like a mouse click.
-- - A stays Forever's (it selects the entry); the addon reads the controller to see it was pressed.

local REPEAT_WAIT = 10 -- seconds before the same leader can be whispered again
local LOG_MAX = 80

function ns.LfgLog(...)
	if not (ns.db and ns.db.lfgLogOn) then
		return
	end
	local parts = { date("%H:%M:%S") }
	for i = 1, select("#", ...) do
		parts[#parts + 1] = tostring((select(i, ...)))
	end
	ns.db.lfgLog = ns.db.lfgLog or {}
	tinsert(ns.db.lfgLog, table.concat(parts, " "))
	while #ns.db.lfgLog > LOG_MAX do
		tremove(ns.db.lfgLog, 1)
	end
end

function ns.ToggleLfgLog()
	ns.db.lfgLogOn = not ns.db.lfgLogOn
	if ns.db.lfgLogOn then
		ns.db.lfgLog = {}
		ns.Print("Group finder log on. Use the Looking For Group window, then /gxiv lfglog again to stop; it is saved on /reload or logout.")
	else
		ns.Print("Group finder log off,", #(ns.db.lfgLog or {}), "lines saved.")
	end
end

local owner = CreateFrame("Frame") -- holds the addon's override bindings for the window
local refreshButton, menuButton, cancelButton
local confirm, hint
local boundKeys = {} -- key -> the binding command the addon set
local takenBack = {} -- keys logged as taken back since the window opened
local lastSent = {}
local lastRebind = 0

local REFRESH_COMMAND = "CLICK GamepadXIVLfgRefresh:LeftButton"
local MENU_COMMAND = "CLICK GamepadXIVLfgMenu:RightButton"
local CANCEL_COMMAND = "CLICK GamepadXIVLfgCancel:LeftButton"

local function WindowShown()
	return LFGParentFrame and LFGParentFrame:IsVisible() and LFGBrowseFrame and LFGBrowseFrame:IsVisible()
end

-- Forever's controller cursor is in the window (and not in a menu or a popup over it).
local function CursorInWindow()
	local nav = SmartNavigation
	local frame = nav and nav.activeInfo and nav.activeInfo.frame
	if frame ~= LFGParentFrame and frame ~= LFGBrowseFrame then
		return false
	end
	local manager = Menu and Menu.GetManager and Menu.GetManager()
	if manager and manager:IsAnyMenuOpen() then
		return false
	end
	if GamepadPopupHandler and GamepadPopupHandler.IsStaticPopupShowing and GamepadPopupHandler:IsStaticPopupShowing() then
		return false
	end
	return true
end

local function FrameName(frame)
	if not frame then
		return "none"
	end
	return (frame.GetName and frame:GetName()) or (frame.GetObjectType and frame:GetObjectType()) or tostring(frame)
end

-- The list entry under the controller cursor, or nil.
local function FocusedEntry()
	local frame = SmartNavigation and SmartNavigation.currentButton
	local scrollBox = LFGBrowseFrame and LFGBrowseFrame.ScrollBox
	for _ = 1, 4 do
		if not frame then
			return nil
		end
		if frame.resultID then
			local parent = frame:GetParent()
			while parent and parent ~= scrollBox do
				parent = parent:GetParent()
			end
			return parent and frame or nil
		end
		frame = frame:GetParent()
	end
	return nil
end

-- A group that can be whispered, or nil and why not.
local function GroupInfo(entry)
	local info = entry and C_LFGList.GetSearchResultInfo(entry.resultID)
	if not info then
		return nil, "no entry"
	elseif info.isDelisted then
		return nil, "delisted"
	elseif info.hasSelf then
		return nil, "your own group"
	elseif (info.numMembers or 0) <= 1 then
		return nil, "a single player, not a group"
	elseif not info.leaderName then
		return nil, "no leader name yet"
	end
	return info
end

local function ActivityName(info)
	local id = (info.activityIDs and info.activityIDs[1]) or info.activityID
	local activity = id and C_LFGList.GetActivityInfoTable and C_LFGList.GetActivityInfoTable(id)
	if not activity then
		return ""
	end
	return (activity.shortName and activity.shortName ~= "" and activity.shortName) or activity.fullName or ""
end

-- The saved message with <level>, <class>, <name>, <leader> and <activity> filled in. Other <words>
-- stay as typed.
function ns.LfgMessage(info)
	local values = {
		level = UnitLevel("player"),
		class = UnitClass("player"),
		name = UnitName("player"),
		leader = info and info.leaderName and Ambiguate(info.leaderName, "short") or "",
		activity = info and ActivityName(info) or "",
	}
	local text = (ns.db.lfgMessage or ""):gsub("<(%a+)>", function(token)
		local value = values[token:lower()]
		return value ~= nil and tostring(value) or nil
	end)
	return strtrim(text):sub(1, 255)
end

local function Send(info)
	local leader = info.leaderName
	local now = GetTime()
	if lastSent[leader] and now - lastSent[leader] < REPEAT_WAIT then
		ns.Print("You whispered", Ambiguate(leader, "short"), "a moment ago.")
		ns.LfgLog("not sent, repeat", leader)
		return
	end
	local text = ns.LfgMessage(info)
	if text == "" then
		ns.Print("The group finder message is empty. Set it in /gxiv, General tab.")
		return
	end
	lastSent[leader] = now
	local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
	local ok, err = pcall(send, text, "WHISPER", nil, leader)
	ns.LfgLog(ok and "sent" or "send failed", leader, ok and text or tostring(err))
end

local function UpdateHint()
	if not hint then
		return
	end
	local shown = WindowShown() and ns.IsGamepadUI and ns.IsGamepadUI() and not InCombatLockdown()
	hint:SetShown(shown and true or false)
	if shown then
		hint.text:SetText(ns.ButtonText("{PAD4} Refresh     {PAD1} Request invite     {PAD3} Group menu", 20))
		hint:SetSize(hint.text:GetStringWidth() + 24, 34)
	end
end

local function HideConfirm(reason)
	if confirm and confirm:IsShown() then
		confirm:Hide()
		ns.LfgLog("confirm closed:", reason)
	end
end

local function ShowConfirm(info)
	if not confirm then
		confirm = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
		confirm:SetSize(420, 118)
		confirm:SetFrameStrata("DIALOG")
		confirm:EnableMouse(true)
		confirm:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		confirm:SetBackdropColor(0.06, 0.06, 0.08, 0.96)
		confirm:SetBackdropBorderColor(1, 0.82, 0, 0.6)
		confirm.title = confirm:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		confirm.title:SetPoint("TOP", 0, -14)
		confirm.title:SetPoint("LEFT", 16, 0)
		confirm.title:SetPoint("RIGHT", -16, 0)
		confirm.message = confirm:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		confirm.message:SetPoint("TOP", confirm.title, "BOTTOM", 0, -10)
		confirm.message:SetPoint("LEFT", 16, 0)
		confirm.message:SetPoint("RIGHT", -16, 0)
		confirm.message:SetWordWrap(true)
		confirm.keys = confirm:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		confirm.keys:SetPoint("BOTTOM", 0, 14)
		-- Mouse buttons, for a click instead of the controller.
		confirm.send = CreateFrame("Button", nil, confirm, "UIPanelButtonTemplate")
		confirm.send:SetSize(80, 22)
		confirm.send:SetPoint("BOTTOMRIGHT", -12, 10)
		confirm.send:SetText("Send")
		confirm.send:SetScript("OnClick", function()
			local pending = confirm.info
			HideConfirm("sent with the mouse")
			if pending then
				Send(pending)
			end
		end)
		confirm.cancel = CreateFrame("Button", nil, confirm, "UIPanelButtonTemplate")
		confirm.cancel:SetSize(80, 22)
		confirm.cancel:SetPoint("BOTTOMLEFT", 12, 10)
		confirm.cancel:SetText("Cancel")
		confirm.cancel:SetScript("OnClick", function() HideConfirm("cancelled with the mouse") end)
	end
	confirm.info = info
	confirm.navButton = SmartNavigation and SmartNavigation.currentButton
	confirm.title:SetText("Whisper " .. Ambiguate(info.leaderName, "short") .. "?")
	confirm.message:SetText("\"" .. ns.LfgMessage(info) .. "\"")
	confirm.keys:SetText(ns.ButtonText("{PAD1} Send     {PAD4} Cancel", 20))
	confirm:SetHeight(96 + confirm.message:GetStringHeight())
	confirm:ClearAllPoints()
	confirm:SetPoint("TOP", LFGParentFrame, "BOTTOM", 0, -44)
	confirm:Show()
	ns.LfgLog("confirm shown for", info.leaderName)
end

-- A on a list entry, read from the controller (Forever's navigation keeps the button).
local function OnConfirmPress()
	if confirm and confirm:IsShown() then
		local pending = confirm.info
		HideConfirm("sent")
		if pending then
			Send(pending)
		end
		return
	end
	if not CursorInWindow() then
		ns.LfgLog("A: cursor not in the window; its frame:", FrameName(SmartNavigation and SmartNavigation.activeInfo and SmartNavigation.activeInfo.frame))
		return
	end
	local entry = FocusedEntry()
	local info, why = GroupInfo(entry)
	if not info then
		ns.LfgLog("A: nothing to whisper,", why, "cursor on:", FrameName(SmartNavigation and SmartNavigation.currentButton))
		return
	end
	if ns.db.lfgConfirm then
		ShowConfirm(info)
	else
		Send(info)
	end
end

local function ClearBindings(reason)
	if next(boundKeys) and not InCombatLockdown() then
		ClearOverrideBindings(owner)
		wipe(boundKeys)
		ns.LfgLog("bindings cleared:", reason)
	end
end

-- Puts Triangle and Square on the addon's buttons while the controller cursor is in the window.
-- Forever re-binds when its own bindings change, so they are checked again and taken back.
local function UpdateBindings()
	if InCombatLockdown() then
		return
	end
	if not (WindowShown() and ns.IsGamepadUI and ns.IsGamepadUI() and CursorInWindow()) then
		ClearBindings("cursor left the window")
		return
	end
	local entry = FocusedEntry()
	if menuButton:GetAttribute("clickbutton") ~= entry then
		menuButton:SetAttribute("clickbutton", entry)
		menuButton:SetAttribute("clickbutton2", entry)
	end
	local wanted = {
		PAD4 = (confirm and confirm:IsShown()) and CANCEL_COMMAND or REFRESH_COMMAND,
		PAD3 = MENU_COMMAND,
	}
	local now = GetTime()
	for key, command in pairs(wanted) do
		if GetBindingAction(key, true) ~= command and (boundKeys[key] ~= command or now - lastRebind > 1) then
			if boundKeys[key] ~= command or not takenBack[key] then
				ns.LfgLog(boundKeys[key] == command and "binding taken back:" or "binding set:", key, command,
					"was", GetBindingAction(key, true))
				takenBack[key] = boundKeys[key] == command or nil
			end
			local button, mouse = command:match("^CLICK ([^:]+):(.+)$")
			SetOverrideBindingClick(owner, true, key, button, mouse)
			boundKeys[key] = command
			lastRebind = now
		end
	end
end

local function CreateSecureClick(name, mouse)
	local button = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
	button:RegisterForClicks("AnyDown", "AnyUp")
	button:SetAttribute("useOnKeyDown", true)
	button:SetAttribute("type", "click")
	button:SetAttribute(mouse == "RightButton" and "type2" or "type1", "click")
	button:Hide()
	return button
end

-- The group's menu shows beside the window, level with the entry, rather than where Forever's
-- navigation puts it.
local function PlaceEntryMenu(entry)
	local manager = Menu and Menu.GetManager and Menu.GetManager()
	local menu = manager and manager:GetOpenMenu()
	if not (menu and menu.ClearAllPoints and LFGParentFrame:IsVisible()) then
		ns.LfgLog("menu: none to place")
		return
	end
	local top = LFGParentFrame:GetTop()
	local entryTop = entry and entry.GetTop and entry:GetTop()
	local y = (entryTop and top) and math.min(0, entryTop - top) or -60
	local ok, err = pcall(function()
		menu:ClearAllPoints()
		menu:SetPoint("TOPLEFT", LFGParentFrame, "TOPRIGHT", 4, y)
		if menu.SetClampedToScreen then
			menu:SetClampedToScreen(true)
		end
	end)
	ns.LfgLog("menu placed beside the window:", ok and "yes" or tostring(err))
end

local function PlaceEntryMenuTwice(entry)
	PlaceEntryMenu(entry)
	-- Forever's navigation may anchor it again once it is laid out.
	C_Timer.After(0, function()
		PlaceEntryMenu(entry)
		local manager = Menu.GetManager()
		local menu = manager and manager:GetOpenMenu()
		if menu and menu.GetPoint then
			local point, relative, relativePoint = menu:GetPoint(1)
			ns.LfgLog("menu anchor now:", point, FrameName(relative), relativePoint)
		end
	end)
end

local watcher = CreateFrame("Frame")
local padIndex -- binding name -> button index in the controller state
local wasDown = false
local elapsedSince = 0
local windowWasShown = false

local function ConfirmButtonDown()
	local state = C_GamePad and C_GamePad.GetDeviceMappedState and
		(C_GamePad.GetDeviceMappedState() or C_GamePad.GetDeviceMappedState(C_GamePad.GetActiveDeviceID()))
	if not state then
		return false
	end
	if not padIndex or padIndex.count ~= state.buttonCount then
		padIndex = { count = state.buttonCount }
		for i = 1, state.buttonCount do
			padIndex[C_GamePad.ButtonIndexToBinding(i - 1) or ""] = i
		end
	end
	local index = padIndex.PAD1
	return index and state.buttons[index] and true or false
end

watcher:SetScript("OnUpdate", function(_, elapsed)
	if not WindowShown() then
		windowWasShown = false
		if wasDown or (confirm and confirm:IsShown()) or next(boundKeys) or (hint and hint:IsShown()) then
			wasDown = false
			HideConfirm("window closed")
			ClearBindings("window closed")
			UpdateHint()
		end
		return
	end
	if InCombatLockdown() or not (ns.IsGamepadUI and ns.IsGamepadUI()) then
		wasDown = false
		return
	end
	local down = ConfirmButtonDown()
	-- A press that opened the window (from the ring, say) is still down when it shows: not a new one.
	if not windowWasShown then
		windowWasShown = true
		wasDown = down
		ns.LfgLog("window open, cursor frame:", FrameName(SmartNavigation and SmartNavigation.activeInfo and SmartNavigation.activeInfo.frame))
		wipe(takenBack)
	end
	if down and not wasDown then
		OnConfirmPress()
	end
	wasDown = down
	-- Moving off the entry cancels the question.
	if confirm and confirm:IsShown() and SmartNavigation and SmartNavigation.currentButton ~= confirm.navButton then
		HideConfirm("cursor moved")
	end
	elapsedSince = elapsedSince + elapsed
	if elapsedSince >= 0.1 then
		elapsedSince = 0
		UpdateBindings()
		if hint and not hint:IsShown() then
			UpdateHint()
		end
	end
end)

-- Combat: bindings freeze, so the addon's are taken off now (they can still change while this
-- event runs), and the window's buttons are Forever's again until it ends.
watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:RegisterEvent("ADDON_LOADED")
watcher:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
watcher:SetScript("OnEvent", function(_, event, ...)
	local name = ...
	if event == "CHAT_MSG_WHISPER_INFORM" then
		ns.LfgLog("whisper went out to", select(2, ...))
	elseif event == "PLAYER_REGEN_DISABLED" then
		HideConfirm("combat")
		ClearBindings("combat")
		UpdateHint()
	elseif event == "PLAYER_REGEN_ENABLED" then
		if ns.lfgSetupPending then
			ns.lfgSetupPending = nil
			ns.SetupLfg()
		end
		UpdateHint()
	elseif event == "ADDON_LOADED" and name == "Blizzard_GroupFinder_VanillaStyle" then
		ns.SetupLfg()
	end
end)

function ns.SetupLfg()
	if InCombatLockdown() then
		ns.lfgSetupPending = true -- secure buttons can't be set up in combat
		return
	end
	if ns.lfgReady or not (LFGParentFrame and LFGBrowseFrame and LFGBrowseFrameRefreshButton) then
		return
	end
	ns.lfgReady = true
	refreshButton = CreateSecureClick("GamepadXIVLfgRefresh", "LeftButton")
	refreshButton:SetAttribute("clickbutton", LFGBrowseFrameRefreshButton)
	menuButton = CreateSecureClick("GamepadXIVLfgMenu", "RightButton")
	cancelButton = CreateFrame("Button", "GamepadXIVLfgCancel", UIParent)
	cancelButton:RegisterForClicks("AnyDown")
	cancelButton:SetScript("OnClick", function() HideConfirm("cancelled") end)
	cancelButton:Hide()
	refreshButton:HookScript("OnClick", function(_, _, down)
		if down then
			ns.LfgLog("refresh pressed")
		end
	end)
	menuButton:HookScript("OnClick", function(self, _, down)
		if down then
			ns.LfgLog("menu pressed on", self:GetAttribute("clickbutton") and "an entry" or "nothing")
		end
	end)
	if LFGBrowseFrame.CreateSearchEntryMenu then
		hooksecurefunc(LFGBrowseFrame, "CreateSearchEntryMenu", function(_, entry)
			PlaceEntryMenuTwice(entry)
		end)
	end

	hint = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	hint:SetFrameStrata("DIALOG")
	hint:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
	hint:SetBackdropColor(0, 0, 0, 0.6)
	hint:SetPoint("TOP", LFGParentFrame, "BOTTOM", 0, -6)
	hint.text = hint:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	hint.text:SetPoint("CENTER")
	hint:Hide()
	if InputDeviceIconSetManager and InputDeviceIconSetManager.RegisterActiveInputDeviceIconSetUpdatedCallback then
		InputDeviceIconSetManager:RegisterActiveInputDeviceIconSetUpdatedCallback(function()
			UpdateHint()
			if confirm and confirm:IsShown() then
				confirm.keys:SetText(ns.ButtonText("{PAD1} Send     {PAD4} Cancel", 20))
			end
		end, hint)
	end
	ns.LfgLog("set up")
end

-- The group finder loads when it is first opened; after a /reload it may be loaded already.
local function IsLoaded(name)
	local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
	return isLoaded and isLoaded(name)
end
if IsLoaded("Blizzard_GroupFinder_VanillaStyle") then
	ns.SetupLfg()
end
