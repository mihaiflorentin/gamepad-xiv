local _, ns = ...
local S = ns.Snippets

local driver
local SyncCycleToTarget

-- Temp CVars disappear with the session and never touch the player's saved settings.
local TEMP_CVARS = {
	GamepadShowPersistentInputLegend = "0",
	SoftTargetIconInteract = "0", -- the client's prompt shows Forever's button; see HookInteractPrompt
}

-- Input settings the client may only honour as real values, so they are also saved.
-- The player's own values are kept in the saved variables and survive a crash, so they can be put back.
local INPUT_CVARS = {
	GamePadEmulateShift = "none", -- L2 is a trigger, not a modifier
	GamePadEmulateCtrl = "none", -- L1 is a layer of its own
	GamePadEmulateAlt = "none",
	GamePadStickAxisButtons = "1", -- makes PADLSTICKUP a key, for L1 + left stick forward
}

-- Not every CVar is guaranteed on this beta client, and one missing must not stop the others.
local function SetTemp(name, value)
	ns.Trail("temp CVar " .. name .. " = " .. tostring(value))
	if not pcall(C_CVar.SetTempCVar, name, value) then
		ns.Print("Could not set", name)
	end
end

local function RemoveTemp(name)
	ns.Trail("remove temp CVar " .. name)
	pcall(C_CVar.RemoveTempCVar, name)
end

-- WoW has no way to turn the character on demand. A camera locked on the enemy, plus the character
-- turning with the camera while casting, comes closest. Only changes are written: each write of the
-- experimental CVar makes the client ask for confirmation again.
local cameraLocked = false
local experimentalOn = false
local turnWithCameraOn = false

local function UpdateCameraCVars()
	local db = ns.db
	local autoFace = db.autoFace and ns.cvarsApplied and true or false
	local useExperimental = (cameraLocked or autoFace) and not db.experimentalDeclined
	if useExperimental ~= experimentalOn then
		experimentalOn = useExperimental
		if useExperimental then
			SetTemp("test_cameraTargetFocusEnemyEnable", "1")
		else
			RemoveTemp("test_cameraTargetFocusEnemyEnable")
		end
	end
	if autoFace ~= turnWithCameraOn then
		turnWithCameraOn = autoFace
		if autoFace then
			SetTemp("GamePadTurnWithCamera", "3")
		else
			RemoveTemp("GamePadTurnWithCamera")
		end
	end
end

-- Called when the player asks for a feature that needs the experimental camera again.
function ns.AllowExperimentalCamera()
	ns.db.experimentalDeclined = false
end

-- Remembers the answer to the client's confirmation: Accept is not asked again, and Disable turns the features off.
function ns.HookExperimentalWarning()
	local WARNING = "EXPERIMENTAL_CVAR_WARNING"
	local WARNING_EVENT = "EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED"
	local dialog = StaticPopupDialogs and StaticPopupDialogs[WARNING]
	if not dialog or not dialog.OnCancel then
		return
	end

	hooksecurefunc(dialog, "OnCancel", function()
		local db = ns.db
		db.experimentalAccepted = false
		db.experimentalDeclined = true
		db.autoFace = false
		cameraLocked = false
		experimentalOn = false
		ns.Print("Experimental camera turned off. Face target or lock-on will turn it on again.")
	end)

	-- The dialog must never be closed from here: StaticPopup_Hide from addon code taints Forever's
	-- binding stack, and every later menu change then fails on a protected call. After an Accept,
	-- the client's event simply stops reaching the dialog. A dialog already open waits for a click.
	local function StopAsking()
		for _, frame in ipairs({ GetFramesRegisteredForEvent(WARNING_EVENT) }) do
			pcall(frame.UnregisterEvent, frame, WARNING_EVENT)
		end
	end

	local ticker
	local function WatchAnswer()
		if ticker then
			return
		end
		ticker = C_Timer.NewTicker(0.5, function()
			if not StaticPopup_Visible(WARNING) then
				ticker:Cancel()
				ticker = nil
				ns.db.experimentalAccepted = not ns.db.experimentalDeclined
				if ns.db.experimentalAccepted then
					StopAsking()
				end
			end
		end)
	end

	if ns.db.experimentalAccepted then
		StopAsking()
	end
	hooksecurefunc("StaticPopup_Show", function(which)
		if which == WARNING then
			WatchAnswer()
		end
	end)
	-- After a /reload the client can ask while the UI loads, before this addon does.
	if StaticPopup_Visible(WARNING) then
		WatchAnswer()
	end
end

local function ApplyInputCVars(apply)
	local saved = ns.db.savedCVars
	for name, value in pairs(INPUT_CVARS) do
		if apply then
			RemoveTemp(name)
			if saved[name] == nil then
				saved[name] = GetCVar(name) or false
			end
			ns.Trail("CVar " .. name .. " = " .. tostring(value))
			if not pcall(C_CVar.SetCVar, name, value) then
				ns.Print("Could not set", name)
			end
			SetTemp(name, value)
		else
			RemoveTemp(name)
			if saved[name] then
				ns.Trail("CVar " .. name .. " back to the player's")
				pcall(C_CVar.SetCVar, name, saved[name])
			end
			saved[name] = nil
		end
	end
	-- Makes the client read the changed input settings now, instead of at the next start.
	ns.Trail("C_GamePad.ApplyConfigs")
	pcall(C_GamePad.ApplyConfigs)
end

-- These CVars are account-wide and saved by the client, so the player's own values go back at
-- logout (a /reload included): a character without the addon must not keep them, or its stick
-- tilts close Forever's pet and stance menus. The next login applies them again.
do
	local logout = CreateFrame("Frame")
	logout:RegisterEvent("PLAYER_LOGOUT")
	logout:SetScript("OnEvent", function()
		if ns.db and ns.db.savedCVars then
			ApplyInputCVars(false)
		end
	end)
end

-- Forever's class menus close on any button press. With stick axis buttons on, every tilt of the
-- right stick is a button press too, so the menu closed the moment the stick moved. They are
-- turned off while one is open. The client blocks C_GamePad.ApplyConfigs in combat (the game's
-- "action blocked" popup), so a change in combat waits for the end of combat.
local pendingStickButtons
local function SetStickButtons(on)
	if ns.db.savedCVars.GamePadStickAxisButtons == nil then
		return -- the addon is not running its input settings
	end
	if InCombatLockdown() then
		pendingStickButtons = on
		return
	end
	pendingStickButtons = nil
	local value = on and INPUT_CVARS.GamePadStickAxisButtons or "0"
	ns.Trail("CVar GamePadStickAxisButtons = " .. value .. ", C_GamePad.ApplyConfigs")
	pcall(C_CVar.SetCVar, "GamePadStickAxisButtons", value)
	SetTemp("GamePadStickAxisButtons", value)
	pcall(C_GamePad.ApplyConfigs)
end

do
	local afterCombat = CreateFrame("Frame")
	afterCombat:RegisterEvent("PLAYER_REGEN_ENABLED")
	afterCombat:SetScript("OnEvent", function()
		if pendingStickButtons ~= nil then
			SetStickButtons(pendingStickButtons)
		end
	end)
end

local function ApplyTempCVars(apply)
	ApplyInputCVars(apply)
	for name, value in pairs(TEMP_CVARS) do
		if apply then
			SetTemp(name, value)
		else
			RemoveTemp(name)
		end
	end
	if not apply and ns.IsGamepadUI() then
		SetTemp("SoftTargetIconInteract", "1") -- Forever's own value, for its prompt
	end
	UpdateCameraCVars()
end

local function SetCameraLock(locked)
	if cameraLocked == locked then
		return
	end
	if locked then
		ns.AllowExperimentalCamera()
	end
	cameraLocked = locked
	UpdateCameraCVars()
	ns.Print(locked and "Camera lock on" or "Camera lock off")
end

-- Forever's reserved buttons do the context-sensitive work (loot, talk, attack, cancel...).
local function ForeverButtonBinding(index, fallback)
	local topBar = GamepadMainActionBarFrame and GamepadMainActionBarFrame.PageUnit
		and GamepadMainActionBarFrame.PageUnit.actionBars and GamepadMainActionBarFrame.PageUnit.actionBars.topBar
	local button = topBar and topBar.Right and topBar.Right["ActionButton" .. index]
	local name = button and button:GetName()
	if name then
		return "CLICK " .. name .. ":LeftButton", button
	end
	return fallback
end

-- Walking ends when Cancel is let go. Forever's button only hears the release if the key is still
-- bound to it; after a trigger or a soft target changed the binding, the release went elsewhere and
-- the character kept walking until a /reload. So while walking, the controller itself is asked
-- whether the button is still held.
local walkWatcher
local walkCheck -- how this client reports the button: "key", or the button index offset (0 or 1)

local function StopWalking()
	RemoveTemp("GamePadRunThreshold")
	if walkWatcher then
		walkWatcher:Hide()
	end
end

local function CancelHeld(check)
	if check == "key" then
		local ok, held = pcall(IsKeyDown, "PAD2")
		return ok and held
	end
	local ok, state = pcall(C_GamePad.GetDeviceMappedState)
	if not ok or type(state) ~= "table" or type(state.buttons) ~= "table" then
		return false
	end
	for i, pressed in ipairs(state.buttons) do
		if pressed then
			local okName, name = pcall(C_GamePad.ButtonIndexToBinding, i - check)
			if okName and name == "PAD2" then
				return true
			end
		end
	end
	return false
end

-- Called while Cancel is pressed, so whichever way reports it held now can be trusted later.
-- If none does, walking ends on the release only, as before.
local function WatchWalkRelease()
	walkCheck = nil
	for _, check in ipairs({ "key", 0, 1 }) do
		if (check == "key" and IsKeyDown or check ~= "key" and C_GamePad and C_GamePad.GetDeviceMappedState
				and C_GamePad.ButtonIndexToBinding) and CancelHeld(check) then
			walkCheck = check
			break
		end
	end
	if not walkCheck then
		return
	end
	if not walkWatcher then
		walkWatcher = CreateFrame("Frame")
		local elapsed = 0
		walkWatcher:SetScript("OnUpdate", function(self, delta)
			elapsed = elapsed + delta
			if elapsed < 0.1 then
				return
			end
			elapsed = 0
			if not CancelHeld(walkCheck) then
				StopWalking()
			end
		end)
	end
	walkWatcher:Show()
end

-- Cross is Forever's interact button, whose attack toggles: a second press on the enemy being
-- attacked stopped the attack. crossEnemy picks what Cross does on a living enemy target instead:
-- "attack" is /startattack, which never stops it, like FFXIV; "nothing" keeps the target without
-- attacking. The driver swaps the binding (UpdateTargetBindings), so anything else (no target, a
-- friend, a corpse or other thing to interact with) is Forever's own button, bound directly: reached
-- through a macro's /click, loot opened without auto loot.
-- "shoot" is the wand's Shoot (its ! form never stops it) while a wand is equipped, else /startattack.
local CROSS_ENEMY = { attack = "CLICK GamepadXIVCrossAttack:LeftButton", shoot = "CLICK GamepadXIVCrossShoot:LeftButton",
	nothing = "NONE" }

-- The wand's Shoot and the Wands item type, in the game's language.
local function ShootMacro()
	local function Name(get, ...)
		local ok, name = pcall(get, ...)
		return ok and type(name) == "string" and name ~= "" and name or nil
	end
	local shoot = (C_Spell and C_Spell.GetSpellName and Name(C_Spell.GetSpellName, 5019))
		or (GetSpellInfo and Name(GetSpellInfo, 5019)) or "Shoot"
	local wands = (C_Item and C_Item.GetItemSubClassInfo and Name(C_Item.GetItemSubClassInfo, 2, 19))
		or (GetItemSubClassInfo and Name(GetItemSubClassInfo, 2, 19)) or "Wands"
	return "/cast [@target,harm,nodead,equipped:" .. wands .. "] !" .. shoot
		.. "\n/startattack [@target,harm,nodead,noequipped:" .. wands .. "]"
end

local function SetupBaseBindings()
	local interact = ForeverButtonBinding(1, "INTERACTTARGET")
	driver:SetAttribute("ctx-PAD1", interact)
	local cross = CreateFrame("Button", "GamepadXIVCrossAttack", UIParent, "SecureActionButtonTemplate")
	cross:RegisterForClicks("AnyDown", "AnyUp")
	cross:SetAttribute("useOnKeyDown", true)
	cross:SetAttribute("type", "macro")
	cross:SetAttribute("macrotext", "/startattack [@target,harm,nodead]")
	cross:Hide()
	local shoot = CreateFrame("Button", "GamepadXIVCrossShoot", UIParent, "SecureActionButtonTemplate")
	shoot:RegisterForClicks("AnyDown", "AnyUp")
	shoot:SetAttribute("useOnKeyDown", true)
	shoot:SetAttribute("type", "macro")
	shoot:SetAttribute("macrotext", ShootMacro())
	shoot:Hide()
	local inspect = ForeverButtonBinding(2, "TOGGLEWORLDMAP")
	local back, backButton = ForeverButtonBinding(3, "TOGGLEGAMEMENU")

	driver:SetAttribute("ctx-PADDLEFT-target", "CLICK GamepadXIVTargetPrev:LeftButton")
	driver:SetAttribute("ctx-PADDRIGHT-target", "CLICK GamepadXIVTargetNext:LeftButton")
	driver:SetAttribute("ctx-PADDLEFT-party", "CLICK GamepadXIVFrameLeft:LeftButton")
	driver:SetAttribute("ctx-PADDRIGHT-party", "CLICK GamepadXIVFrameRight:LeftButton")
	driver:SetAttribute("ctx-PADDUP-target", "CLICK GamepadXIVPartyPrev:LeftButton")
	driver:SetAttribute("ctx-PADDDOWN-target", "CLICK GamepadXIVPartyNext:LeftButton")
	driver:SetAttribute("ctx-PADDUP-party", "CLICK GamepadXIVFrameUp:LeftButton")
	driver:SetAttribute("ctx-PADDDOWN-party", "CLICK GamepadXIVFrameDown:LeftButton")
		driver:SetAttribute("ctx-PAD2-ground", back)
	driver:SetAttribute("soft-PAD1", "CLICK GamepadXIVSoftConfirm:LeftButton")
	driver:SetAttribute("soft-PAD2", "CLICK GamepadXIVSoftCancel:LeftButton")
	driver:SetAttribute("base-PAD4", "JUMP")

	driver:SetAttribute("ctx-PAD3-target", inspect)
	driver:SetAttribute("ctx-PAD3-notarget", "TOGGLEWORLDMAP")
	driver:SetAttribute("ctx-PADLSTICK-target", "CLICK GamepadXIVLockOn:LeftButton")
	driver:SetAttribute("ctx-PADLSTICK-notarget", "TOGGLESHEATH")

	-- Holding Cancel walks, like FFXIV. Forever's button keeps doing the cancel itself.
	if backButton then
		backButton:HookScript("OnClick", function(_, _, down)
			if down and ns.IsActive() and ns.db.holdToWalk then
				SetTemp("GamePadRunThreshold", "1.1")
				WatchWalkRelease()
			elseif not down then
				StopWalking()
			end
		end)
	end
end

-- What each action key does while L1 is held.
local L1_BINDINGS = {
	PADDUP = "TARGETPREVIOUSENEMY",
	PADDDOWN = "TARGETNEARESTENEMY",
	PADDLEFT = "CLICK GamepadXIVRaidPrev:LeftButton",
	PADDRIGHT = "CLICK GamepadXIVRaidNext:LeftButton",
	PAD1 = "TOGGLECHARACTER0",
	PAD2 = "TOGGLESPELLBOOK",
	PAD3 = "TOGGLEWORLDMAP",
	PAD4 = "OPENALLBAGS",
}

local function CreateSecureButton(name, snippet, scriptType)
	local button = CreateFrame("Button", name, driver, "SecureActionButtonTemplate, SecureHandlerAttributeTemplate")
	button:RegisterForClicks("AnyDown", "AnyUp")
	button:SetAttribute("useOnKeyDown", true)
	button:Hide()
	SecureHandlerSetFrameRef(button, "driver", driver)
	if snippet then
		SecureHandlerWrapScript(button, scriptType or "OnClick", button, snippet)
	end
	return button
end

local function CreateTrigger(name, side)
	local button = CreateSecureButton(name, S.TriggerClick)
	button:SetAttribute("fc-side", side)
	button:SetAttribute("fc-ready", 1)
	button:SetAttribute("fc-ticks", 0)
	button:SetAttribute("_onattributechanged", S.TriggerAttribute)
	RegisterAttributeDriver(button, "fc-ready", 1)
end

local function CreateL1()
	local button = CreateSecureButton("GamepadXIVL1", S.L1Click)
	button:SetAttribute("fc-ready", 1)
	button:SetAttribute("fc-ticks", 0)
	button:SetAttribute("_onattributechanged", S.TriggerAttribute)
	RegisterAttributeDriver(button, "fc-ready", 1)
end

-- The popups Forever does not focus by itself that need a quick answer from the controller.
-- Going through Forever's focus for them left its bindings blocking the controller after answering.
local ANSWERED_POPUPS = {
	DEATH = true, RESURRECT = true, RESURRECT_NO_SICKNESS = true, RESURRECT_NO_TIMER = true,
	SKINNED_REPOP = true, RECOVER_CORPSE = true, RECOVER_CORPSE_INSTANCE = true, AREA_SPIRIT_HEAL = true,
	PARTY_INVITE = true,
}
local POPUP_KEYS = { PAD1 = "GetButton1", PAD2 = "GetButton2", PAD3 = "GetButton3", PAD4 = "GetButton4" }
local POPUP_KEY_ORDER = { "PAD1", "PAD2", "PAD3", "PAD4", "PADDLEFT", "PADDUP", "PADDRIGHT" }

-- The group finder's invite (a group from Looking For Group invites you) is a window of its own,
-- not one of the four popups; it is number 5 here.
local INVITE_POPUP = 5
local INVITE_BUTTONS = { PAD1 = "LFGInvitePopupAcceptButton", PAD2 = "LFGInvitePopupDeclineButton" }
-- The invite's role boxes have no names of their own, and no gamepad focus reaches them (Back says
-- "No interface frame to focus"). Secure "click" buttons of ours press them: the D-pad left, up and
-- right tick tank, healer and DPS, laid out as the boxes are.
local INVITE_ROLES = { PADDLEFT = "Tank", PADDUP = "Healer", PADDRIGHT = "DPS" }
local INVITE_ROLE_NAMES = { Tank = "Tank", Healer = "Healer", DPS = "DPS" }

local function InviteRoleButton(key)
	local role = INVITE_ROLES[key]
	local roleButton = role and _G["LFGInvitePopupRoleButton" .. role]
	local check = roleButton and roleButton.checkButton
	if not (check and roleButton:IsShown() and check:IsShown() and check:IsEnabled()) then
		return nil
	end
	local proxy = _G["GamepadXIVInviteRole" .. role]
	if not proxy then
		if InCombatLockdown() then
			return nil
		end
		proxy = CreateFrame("Button", "GamepadXIVInviteRole" .. role, UIParent, "SecureActionButtonTemplate")
		proxy:RegisterForClicks("AnyDown")
		proxy:SetAttribute("useOnKeyDown", true)
		proxy:SetAttribute("type", "click")
		proxy:Hide()
		proxy.label = INVITE_ROLE_NAMES[role]
	end
	if proxy:GetAttribute("clickbutton") ~= check then
		if InCombatLockdown() then
			return nil
		end
		proxy:SetAttribute("clickbutton", check)
	end
	return proxy
end

local function PopupByIndex(index)
	if index == INVITE_POPUP then
		return LFGInvitePopup
	end
	return index > 0 and _G["StaticPopup" .. index] or nil
end

local function GetAnsweredPopup()
	for index = 1, 4 do
		local popup = _G["StaticPopup" .. index]
		if popup and popup:IsShown() and ANSWERED_POPUPS[popup.which] then
			return popup, index
		end
	end
	if LFGInvitePopup and LFGInvitePopup:IsShown() then
		return LFGInvitePopup, INVITE_POPUP
	end
end

local function GetPopupButton(popup, key)
	if popup and popup == LFGInvitePopup then
		if INVITE_ROLES[key] then
			return InviteRoleButton(key)
		end
		local button = INVITE_BUTTONS[key] and _G[INVITE_BUTTONS[key]]
		return button and button:IsShown() and button or nil
	end
	local getter = popup and popup[POPUP_KEYS[key]]
	local button = getter and getter(popup)
	if button and button:IsShown() then
		return button
	end
end

local popupHint

-- Stays on what the bindings really do: in combat they only change when combat ends.
-- A party invite (not a group finder one) on screen: its window, or nil.
local function PartyInvitePopup()
	for index = 1, 4 do
		local popup = _G["StaticPopup" .. index]
		if popup and popup:IsShown() and (popup.which == "PARTY_INVITE" or popup.which == "PARTY_INVITE_XREALM") then
			return popup
		end
	end
end

-- What can wait for an answer mid-fight, when the bindings can't change: a party invite or a trade
-- window. Back (LfgFilter.lua's chat key button) opens the answer picker for it (ns.OpenCombatAnswer).
local COMBAT_ANSWERS = {
	{
		name = "invite", yes = "Accept", no = "Decline",
		Frame = function() return ns.InvitePending and ns.InvitePending() and PartyInvitePopup() end,
		Yes = function() AcceptGroup() end, No = function() DeclineGroup() end,
	},
	{
		name = "trade", yes = "Accept trade", no = "Cancel trade",
		Frame = function() return TradeFrame and TradeFrame:IsShown() and TradeFrame or nil end,
		Yes = function() AcceptTrade() end, No = function() CancelTrade() end,
	},
}
-- The first one waiting, and its window.
local function CombatAnswer()
	for _, answer in ipairs(COMBAT_ANSWERS) do
		local frame = answer.Frame()
		if frame then
			return answer, frame
		end
	end
end
function ns.CombatAnswerWaiting()
	return InCombatLockdown() and CombatAnswer() ~= nil
end

local function UpdatePopupHint()
	if not driver then
		return
	end
	local index = driver:GetAttribute("fc-answeredPopup") or 0
	local popup = PopupByIndex(index)
	local combatWindow
	if (not popup or not popup:IsShown()) and InCombatLockdown() then
		local _, frame = CombatAnswer()
		combatWindow = frame
		popup = not (ns.CombatAnswerShown and ns.CombatAnswerShown()) and frame or nil
	end
	if not popup or not popup:IsShown() or not ns.IsActive() then
		if popupHint then
			popupHint:Hide()
		end
		return
	end
	if not popupHint then
		-- On a frame of its own above every window (LFG Filter's included), with a dark plate so it
		-- reads over anything: under it {PAD2} declines the invite, so it must be seen.
		local plate = CreateFrame("Frame", "GamepadXIVPopupHint", UIParent, "BackdropTemplate")
		plate:SetFrameStrata("FULLSCREEN_DIALOG")
		plate:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
		plate:SetBackdropColor(0.04, 0.04, 0.06, 0.92)
		plate:SetBackdropBorderColor(1, 0.82, 0, 0.8)
		plate:EnableMouse(false)
		popupHint = plate:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		popupHint:SetPoint("CENTER", plate, "CENTER")
		popupHint.plate = plate
		hooksecurefunc(popupHint, "Show", function(self) self.plate:Show() end)
		hooksecurefunc(popupHint, "Hide", function(self) self.plate:Hide() end)
	end
	local parts = {}
	if popup and popup == combatWindow then
		tinsert(parts, ns.ButtonText("{PADBACK}", 16) .. " Answer")
	else
		for _, key in ipairs(POPUP_KEY_ORDER) do
			local button = GetPopupButton(popup, key)
			if button then
				tinsert(parts, ns.ButtonText("{" .. key .. "}", 16) .. " " .. (button.label or button:GetText() or ""))
			end
		end
	end
	popupHint:SetText(table.concat(parts, "    "))
	local plate = popupHint.plate
	plate:SetSize((popupHint:GetStringWidth() or 200) + 24, (popupHint:GetStringHeight() or 18) + 14)
	plate:ClearAllPoints()
	plate:SetPoint("TOP", popup, "BOTTOM", 0, -8)
	popupHint:Show()
end

-- The party selection buttons hear the release too, which ends holding the D-pad (S.HoldStart).
local function CreateCycle(name, step, raidOnly)
	local button = CreateSecureButton(name, S.CyclePreClick, "PreClick")
	button:SetAttribute("type", "target")
	button:SetAttribute("fc-step", step)
	button:SetAttribute("fc-raidOnly", raidOnly and 1 or 0)
	-- Play log: what each press picked, to find presses that seem to do nothing.
	button:HookScript("OnClick", function(self, _, down)
		if not down then
			return
		end
		ns.PlayLog("party cycle:", name, "unit", self:GetAttribute("unit") or "nil",
			"frame", driver:GetAttribute("fc-cycleFrame") or "nil", "of", driver:GetAttribute("fc-ufCount") or 0,
			"list", driver:GetAttribute("fc-cycle-party") or "nil", "soft", driver:GetAttribute("fc-soft") or "")
	end)
end

local function CreateTargetCycle(name, step)
	local button = CreateSecureButton(name, S.TargetCyclePreClick, "PreClick")
	button:RegisterForClicks("AnyDown")
	button:SetAttribute("type", "macro")
	button:SetAttribute("fc-step", step)
end

local function CreateFrameMove(name, dx, dy)
	local button = CreateSecureButton(name, S.FrameMovePreClick, "PreClick")
	button:SetAttribute("type", "target")
	button:SetAttribute("fc-dx", dx)
	button:SetAttribute("fc-dy", dy)
end

-- Secure code can only reach frames handed to it out of combat. The frame in each slot can change,
-- so a change in their number also forgets the cursor.
local function RefreshUnitFrameRefs()
	if InCombatLockdown() then
		return
	end
	local count = 0
	local function Add(frame)
		if frame and frame:IsProtected() then
			count = count + 1
			SecureHandlerSetFrameRef(driver, "uf" .. count, frame)
		end
	end
	for _, key in ipairs({ "memberUnitFrames", "petUnitFrames" }) do
		for _, frame in ipairs(CompactPartyFrame and CompactPartyFrame[key] or {}) do
			Add(frame)
		end
	end
	for i = 1, 40 do
		Add(_G["CompactRaidFrame" .. i])
	end
	for group = 1, 8 do
		for member = 1, 5 do
			Add(_G["CompactRaidGroup" .. group .. "Member" .. member])
		end
	end
	if driver:GetAttribute("fc-ufCount") ~= count then
		driver:SetAttribute("fc-ufCount", count)
		driver:SetAttribute("fc-ufCursor", nil)
		driver:SetAttribute("fc-cycleFrame", nil)
	end
end

-- With Party targeting on Hard, D-pad party selection steps on from the player you have targeted,
-- however you targeted them. Secure code can't tell which group member the target is, so this is
-- done here, out of combat only; in combat it steps on from the last player it selected itself.
SyncCycleToTarget = function()
	if InCombatLockdown() or not driver or ns.db.partyTargeting ~= "hard" or not UnitExists("target") then
		return
	end
	local unit, listIndex
	if IsInRaid() then
		for i = 1, 40 do
			if not unit and UnitIsUnit("raid" .. i, "target") then
				unit, listIndex = "raid" .. i, i
			end
		end
		if unit then
			driver:SetAttribute("fc-cycle-raid", listIndex)
		end
	else
		local units = { "player", "pet" }
		for i = 1, 4 do
			tinsert(units, "party" .. i)
			tinsert(units, "partypet" .. i)
		end
		for index, candidate in ipairs(units) do
			if not unit and UnitIsUnit(candidate, "target") then
				unit, listIndex = candidate, index - 1
			end
		end
		if unit then
			driver:SetAttribute("fc-cycle-party", listIndex)
		end
	end
	if unit then
		driver:SetAttribute("fc-cycleUnit", unit)
	end
end

local function CreatePlainButton(name, onClick, repeatOnHold)
	local button = CreateFrame("Button", name, UIParent)
	if repeatOnHold then
		ns.RepeatOnHold(button, onClick)
	else
		button:RegisterForClicks("AnyDown")
		button:SetScript("OnClick", onClick)
	end
	button:Hide()
end

-- Non-protected helpers: camera and cursor calls that are allowed from addon code.
local function CreateHelperButtons()
	CreatePlainButton("GamepadXIVEditToggle", function() ns.ToggleEditor() end)
	CreatePlainButton("GamepadXIVConfigToggle", function() ns.OpenConfig() end)

	CreatePlainButton("GamepadXIVLockOn", function() SetCameraLock(not cameraLocked) end)

	local savedZoom
	CreatePlainButton("GamepadXIVView", function()
		if GetCameraZoom() > 0.1 then
			savedZoom = GetCameraZoom()
			CameraZoomIn(savedZoom)
		else
			CameraZoomOut(savedZoom or 15)
		end
	end)

end

-- Controller state. Passing no device reads the combined one; some setups only answer for the active one.
local function GetPadState()
	return C_GamePad.GetDeviceMappedState() or C_GamePad.GetDeviceMappedState(C_GamePad.GetActiveDeviceID())
end

-- Whether a controller button is down right now, from the controller state.
local function PadDown(state, binding)
	for i = 1, state.buttonCount do
		if C_GamePad.ButtonIndexToBinding(i - 1) == binding then
			return state.buttons[i]
		end
	end
	return false
end

-- A window that opens from L1 + a face button can take L1's release for its own tabs, which leaves
-- the driver in the L1 layer: the next face button then opens the window again. Out of combat,
-- the layer goes back to the base once L1 has been seen up twice in a row.
local function CreateL1Release()
	local watcher = CreateFrame("Frame")
	local elapsedSince, upCount = 0, 0
	watcher:SetScript("OnUpdate", function(_, elapsed)
		elapsedSince = elapsedSince + elapsed
		if elapsedSince < 0.15 then
			return
		end
		elapsedSince = 0
		if InCombatLockdown() or driver:GetAttribute("fc-layer") ~= "L1" then
			upCount = 0
			return
		end
		local state = GetPadState()
		if not state or PadDown(state, "PADLSHOULDER") then
			upCount = 0
			return
		end
		upCount = upCount + 1
		if upCount >= 2 then
			ns.PlayLog("L1 layer stuck with L1 up: released")
			upCount = 0
			SecureHandlerExecute(driver, [[
				if self:GetAttribute("fc-layer") == "L1" then
					self:SetAttribute("fc-layer", "BASE")
					self:RunAttribute("ApplyLayer")
				end
			]])
		end
	end)
end

-- A hidden texture, only for asking the client which cursor a unit has.
local probeTexture

-- Right stick vertical value. The raw "Right" stick comes first: the "Camera" and "Look" sticks are
-- the game's processed copies, which stay near zero until the stick is pushed far.
local function GetStickY(state, wanted)
	for i = 1, state.stickCount do
		if C_GamePad.StickIndexToConfigName(i - 1) == wanted then
			return state.sticks[i].y
		end
	end
end

-- Both axes of the right stick, for the addon's ring.
function ns.GetRightStick()
	local state = GetPadState()
	if not state then
		return 0, 0
	end
	for _, wanted in ipairs({ "Right", "Camera", "Look" }) do
		for i = 1, state.stickCount do
			if C_GamePad.StickIndexToConfigName(i - 1) == wanted then
				return state.sticks[i].x, state.sticks[i].y
			end
		end
	end
	return 0, 0
end

local function GetCameraStickY(state)
	if not state then
		return 0
	end
	local y = GetStickY(state, "Right") or GetStickY(state, "Camera") or GetStickY(state, "Look")
	if y then
		return y
	end
	for i = 1, state.axisCount do
		if C_GamePad.AxisIndexToConfigName(i - 1) == "RStickY" then
			return state.axes[i]
		end
	end
	return 0
end

-- Forever bug: in gamepad mode the equipment set list is anchored to CharacterFrame.InsetRight, which
-- is not placed in this version of the character window, so the sets were drawn in the top-left
-- corner of the screen with no width. Forever's gamepad layout also hides Equip and Save. The pane
-- gets its mouse layout back instead, with the same anchors as Forever's XML. Only layout changes,
-- so nothing of Forever's code runs from this addon.
local function FixEquipmentSetList()
	local pane = PaperDollFrame and PaperDollFrame.EquipmentManagerPane
	if not (pane and pane.ScrollBox and pane.ScrollBar and pane.InitializeGamepad) then
		return
	end
	local function Fix()
		if not (InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled()) then
			return
		end
		local scrollBox, scrollBar = pane.ScrollBox, pane.ScrollBar
		scrollBox:ClearAllPoints()
		scrollBox:SetPoint("TOPLEFT", pane, "TOPLEFT", 5, -8)
		scrollBox:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -20, 105)
		scrollBar:ClearAllPoints()
		scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", -5, -12)
		scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 0, 0)
		if pane.EquipSet then
			pane.EquipSet:Show()
		end
		if pane.SaveSet then
			pane.SaveSet:Show()
		end
	end
	hooksecurefunc(pane, "InitializeGamepad", Fix)
	Fix()

	-- In gamepad mode a plain click on a set also picks it up onto the cursor. A set released over the
	-- pane was a click, so it is dropped; one released elsewhere was dragged out, so it is left alone.
	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("GLOBAL_MOUSE_UP")
	watcher:SetScript("OnEvent", function()
		if not (pane:IsVisible() and pane:IsMouseOver()) then
			return
		end
		-- The pickup can land after the release, so the cursor is checked a moment later.
		C_Timer.After(0.05, function()
			if GetCursorInfo() == "equipmentset" then
				ClearCursor()
			end
		end)
	end)
end

-- Back cycles through the open windows, then chat, like FFXIV. Forever's Back only focuses the window
-- used last, or lets go of it, and moves between windows with L2 / R2. So once a window is focused,
-- Back is pointed at Forever's own R2 button until every open window was visited, then at the game's
-- Open Chat binding. With nothing open, it opens chat; Forever only says "No interface frame to focus".
-- Only bindings change: Forever's focus manager is only read, and its buttons run from the press.
-- In combat Back opens chat if nothing was open when the fight began; otherwise it is Forever's own,
-- for loot rolls and popups.
local BACK_POPUPS = { "GamepadGroupLootRollFrame", "GroupLootFrame1", "GroupLootFrame2", "GroupLootFrame3", "GroupLootFrame4",
	"StaticPopup1", "StaticPopup2", "StaticPopup3", "StaticPopup4", "LFGDungeonReadyPopup", "LFGDungeonReadyDialog",
	"LFGInvitePopup", "LFGListInviteDialog", "LFGListApplicationDialog", "ReadyCheckFrame", "RolePollPopup", "PVPReadyDialog" }
ns.BACK_POPUPS = BACK_POPUPS -- LFG Filter lets go of the controller while one shows

-- A group invite waiting for an answer: from PARTY_INVITE_REQUEST until it is answered, cancelled or
-- runs out. LFG Filter lets go of the controller meanwhile, so Forever's Cross / Circle answer it.
do
	local pendingUntil = 0
	local inviteWatch = CreateFrame("Frame")
	for _, event in ipairs({ "PARTY_INVITE_REQUEST", "PARTY_INVITE_CANCEL", "GROUP_JOINED", "GROUP_ROSTER_UPDATE" }) do
		pcall(inviteWatch.RegisterEvent, inviteWatch, event)
	end
	inviteWatch:SetScript("OnEvent", function(_, event)
		if event == "PARTY_INVITE_REQUEST" then
			pendingUntil = GetTime() + 65
			-- Which window shows the invite in this client, for the play log.
			local names = {}
			for _, name in ipairs({ "LFGInvitePopup", "LFGListInviteDialog", "StaticPopup1", "StaticPopup2" }) do
				local frame = _G[name]
				if frame and frame.IsShown and frame:IsShown() then
					names[#names + 1] = name
				end
			end
			ns.PlayLog("group invite, shown:", #names > 0 and table.concat(names, ", ") or "none of the known windows")
		elseif event ~= "GROUP_ROSTER_UPDATE" or IsInGroup() then
			if pendingUntil > 0 then
				ns.PlayLog("group invite answered:", event)
			end
			pendingUntil = 0
		end
	end)
	function ns.InvitePending()
		return GetTime() < pendingUntil
	end

	-- Answering an invite or a trade mid-fight. The bindings only change when the fight ends, so Back
	-- (LfgFilter.lua's chat key button) opens this picker: it reads the controller's buttons itself,
	-- as the roll picker does, and answers with the game's own calls (AcceptGroup, AcceptTrade...).
	-- An invite's window stays until the fight ends, when Cross or Circle closes it as usual.
	local picker
	local function ClosePicker(why)
		if picker and picker:IsShown() then
			ns.PlayLog("answer picker closed:", why)
			picker:Hide()
		end
	end
	function ns.CombatAnswerShown()
		return picker ~= nil and picker:IsShown()
	end
	function ns.OpenCombatAnswer()
		local answer, frame = CombatAnswer()
		if not answer then
			return false
		end
		if not picker then
			picker = CreateFrame("Frame", "GamepadXIVAnswerPicker", UIParent, "BackdropTemplate")
			picker:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
			picker:SetBackdropColor(0.04, 0.04, 0.06, 0.94)
			picker:SetBackdropBorderColor(1, 0.82, 0, 0.95)
			picker:SetFrameStrata("FULLSCREEN_DIALOG")
			picker:Hide()
			picker.text = picker:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
			picker.text:SetPoint("CENTER")
			picker:SetScript("OnGamePadButtonDown", function(self, button)
				local current = self.answer
				if (button == "PAD1" or button == "PAD2") and current then
					local yes = button == "PAD1"
					local ok, err = pcall(yes and current.Yes or current.No)
					ns.PlayLog("answer picker:", current.name, yes and current.yes or current.no, ok and "" or tostring(err))
					ClosePicker("answered")
				elseif button == "PADBACK" then
					ClosePicker("by hand")
				end
			end)
			picker:SetScript("OnHide", function(self)
				pcall(self.EnableGamePadButton, self, false)
				if ns.ChatBoxReadPad then
					ns.ChatBoxReadPad(true)
				end
				UpdatePopupHint()
			end)
		end
		if ns.ChatBoxReadPad then
			ns.ChatBoxReadPad(false)
		end
		local ok, err = pcall(picker.EnableGamePadButton, picker, true)
		if not ok then
			ns.PlayLog("answer picker can't read the controller:", tostring(err))
			return false
		end
		picker.answer = answer
		picker.window = frame
		picker.text:SetText(ns.ButtonText("{PAD1}", 16) .. " " .. answer.yes .. "    " .. ns.ButtonText("{PAD2}", 16) .. " "
			.. answer.no .. "    " .. ns.ButtonText("{PADBACK}", 16) .. " Later")
		picker:SetSize(picker.text:GetStringWidth() + 28, picker.text:GetStringHeight() + 20)
		picker:ClearAllPoints()
		picker:SetPoint("TOP", frame, "BOTTOM", 0, -8)
		picker:Show()
		UpdatePopupHint()
		ns.PlayLog("answer picker opened:", answer.name)
		return true
	end
	-- Its window answered elsewhere (the mouse), cancelled or gone: the picker goes with it.
	local function CheckPicker(why)
		if picker and picker:IsShown() then
			local answer, frame = CombatAnswer()
			if answer ~= picker.answer or frame ~= picker.window then
				ClosePicker(why)
			end
		end
		UpdatePopupHint()
	end
	inviteWatch:HookScript("OnEvent", function(_, event)
		if event ~= "PARTY_INVITE_REQUEST" then
			CheckPicker(event)
		end
	end)
	local regen = CreateFrame("Frame")
	regen:RegisterEvent("PLAYER_REGEN_ENABLED")
	regen:RegisterEvent("TRADE_SHOW")
	regen:RegisterEvent("TRADE_CLOSED")
	regen:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_ENABLED" then
			-- After the fight the bindings answer again.
			ClosePicker("fight over")
		elseif event == "TRADE_SHOW" then
			ns.PlayLog("trade window shown", InCombatLockdown() and "(in combat)" or "", "Back:",
				tostring(driver and driver:GetAttribute("fc-backAction")))
			C_Timer.After(0, UpdatePopupHint)
		else
			C_Timer.After(0, function() CheckPicker(event) end)
		end
	end)
	for index = 1, 4 do
		local popup = _G["StaticPopup" .. index]
		if popup then
			popup:HookScript("OnHide", function() CheckPicker("window closed") end)
		end
	end

	-- Group quest prompts (an escort started by a party member): logged with the popup that shows, to
	-- find out why one may not show.
	local questWatch = CreateFrame("Frame")
	pcall(questWatch.RegisterEvent, questWatch, "QUEST_ACCEPT_CONFIRM")
	questWatch:SetScript("OnEvent", function(_, _, who, quest)
		ns.PlayLog("group quest prompt from", tostring(who), "for", tostring(quest), InCombatLockdown() and "(in combat)" or "")
		C_Timer.After(0.5, function()
			local shown = {}
			for index = 1, 4 do
				local popup = _G["StaticPopup" .. index]
				if popup and popup:IsShown() then
					shown[#shown + 1] = "StaticPopup" .. index .. " " .. tostring(popup.which)
				end
			end
			ns.PlayLog("group quest prompt, popups shown:", #shown > 0 and table.concat(shown, ", ") or "none")
		end)
	end)
end

local function CreateBackChat()
	local visited = {}
	-- After chat, the next Back is Forever's own, which lets go of the windows: the end of the cycle.
	local afterChat = false
	local function BackAction()
		local manager = GamepadMode and GamepadMode.FrameControlsManager
		if not manager then
			return ""
		end
		-- The game's chat box while it is open to type in. In the "im" chat style it stays the active
		-- one after it closes without sending, so being active alone kept Back from chat for good.
		local chatBox = (ChatFrameUtil and ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow())
			or (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow())
		if chatBox and chatBox:IsShown() and chatBox:HasFocus() then
			wipe(visited)
			afterChat = manager.isUIFocused and true or false
			return "", "the game's chat box is open"
		end
		-- Forever shows loot rolls and popups without focus; its Back is what focuses them. With another
		-- window focused (bags, a quest), Back steps through Forever's windows (its R2) to the roll, and
		-- only lets go once the roll has the focus.
		for _, name in ipairs(BACK_POPUPS) do
			local frame = _G[name]
			if frame and frame.IsVisible and frame:IsVisible() then
				wipe(visited)
				local shown = manager.shownFrames or {}
				if manager.isUIFocused and manager.focusedFrame ~= frame and tContains(shown, frame) then
					return "next", name .. " behind " .. tostring(manager.focusedFrame and manager.focusedFrame.GetName
						and manager.focusedFrame:GetName())
				end
				return "", name .. (manager.isUIFocused and (manager.focusedFrame == frame and " focused" or " (not in Forever's windows)") or "")
			end
		end
		local shown = manager.shownFrames or {}
		if not manager.isUIFocused then
			wipe(visited)
			afterChat = false
			return #shown == 0 and "chat" or "", #shown .. " windows open"
		end
		if afterChat then
			return "", "after chat"
		end
		local focused = manager.focusedFrame
		if not focused or not tContains(shown, focused) then
			return "", "no focused window"
		end
		visited[focused] = true
		for _, frame in ipairs(shown) do
			if not visited[frame] then
				return "next"
			end
		end
		-- The chat box can't type while a window has the controller (it gives way), so with it Back's
		-- last step is Forever's own, which lets go of the windows; Enter still opens the chat box.
		if ns.db and ns.db.chatUI == "gxiv" then
			return "", "every window visited"
		end
		return "chat"
	end
	local function Set(value, why)
		-- With the chat box replacing the game's chat, Back opens it instead (ChatBox.lua).
		if value == "chat" and ns.db and ns.db.chatUI == "gxiv" then
			value = "chatbox"
		end
		if driver:GetAttribute("fc-backAction") ~= value then
			ns.PlayLog("Back:", value == "" and "Forever's" or value, value == "" and why and ("(" .. why .. ")") or "")
			driver:SetAttribute("fc-backAction", value)
			if ns.IsActive() then
				SecureHandlerExecute(driver, [[ self:RunAttribute("ApplyLayer") ]])
			end
		end
	end
	local watcher = CreateFrame("Frame")
	-- Bindings freeze in combat; they can still change while this event runs.
	watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
	-- Loot rolls still open: Back stays Forever's through a fight then, so it can reach the roll.
	local rolls = {} -- rollID = when it runs out
	watcher:RegisterEvent("START_LOOT_ROLL")
	watcher:RegisterEvent("CANCEL_LOOT_ROLL")
	local function RollPending()
		local now = GetTime()
		for id, ends in pairs(rolls) do
			if ends > now then
				return id
			end
			rolls[id] = nil
		end
	end
	-- With nothing open, Back keeps opening chat in combat; a roll that drops mid-fight gets the roll
	-- picker from it (RollPicker.lua). With a window, popup or loot roll open it is Forever's.
	watcher:SetScript("OnEvent", function(_, event, rollID, rollTime)
		if event == "START_LOOT_ROLL" then
			rolls[rollID] = GetTime() + (tonumber(rollTime) or 60000) / 1000
			-- Whether Forever shows the roll during a fight, for the play log.
			C_Timer.After(0.5, function()
				local frame = GamepadGroupLootRollFrame
				ns.PlayLog("loot roll", tostring(rollID), "window shown:", tostring(frame and frame:IsVisible()),
					InCombatLockdown() and "(in combat)" or "", "Back:", tostring(driver:GetAttribute("fc-backAction")))
			end)
			return
		elseif event == "CANCEL_LOOT_ROLL" then
			rolls[rollID] = nil
			return
		end
		local value, why = BackAction()
		wipe(visited)
		afterChat = false
		if value == "chat" and RollPending() then
			value, why = "", "loot roll open"
		elseif value ~= "chat" then
			value, why = "", why or "combat"
		end
		Set(value, why)
	end)
	local elapsedSince = 0
	watcher:SetScript("OnUpdate", function(_, elapsed)
		elapsedSince = elapsedSince + elapsed
		if elapsedSince < 0.1 or InCombatLockdown() then
			return
		end
		elapsedSince = 0
		Set(BackAction())
	end)
	-- Whether Back is the chat box's now (for its hints in combat).
	function ns.BackOpensChat()
		return driver:GetAttribute("fc-backAction") == "chatbox"
	end
	-- A loot roll or popup takes Back the moment it shows, not up to 0.1 s later: Forever shows rolls
	-- as a fight ends, often just as Back is pressed.
	function ns.RefreshBack()
		if not InCombatLockdown() then
			Set(BackAction())
		end
	end
	for _, name in ipairs(BACK_POPUPS) do
		local frame = _G[name]
		if frame and frame.HookScript then
			frame:HookScript("OnShow", ns.RefreshBack)
		end
	end
end

-- L1 + R1 on the open world map places a pin at the map cursor, or removes the pin under it, the same
-- as Forever's own L3. The shoulders are read from the controller state rather than bound, so the
-- map keeps its own L1 and R1 actions.
local function CreateMapPinChord()
	local watcher = CreateFrame("Frame")
	local wasHeld = false
	local function IsDown(state, binding)
		for i = 1, state.buttonCount do
			if C_GamePad.ButtonIndexToBinding(i - 1) == binding then
				return state.buttons[i]
			end
		end
		return false
	end
	watcher:SetScript("OnUpdate", function()
		local map = WorldMapFrame
		if not (map and map:IsVisible() and map.GamepadTryPlaceWaypoint) then
			wasHeld = false
			return
		end
		local state = GetPadState()
		local held = state and IsDown(state, "PADLSHOULDER") and IsDown(state, "PADRSHOULDER") or false
		if held and not wasHeld then
			map:GamepadTryPlaceWaypoint()
		end
		wasHeld = held
	end)
end

-- Forever's chat never reports clicks on links (OnHyperlinkClick does not fire, even with the mouse
-- and links enabled on the window), so clicking an item in chat did nothing. The click does land on
-- the line's font string, so the link is read from that line and opened the way chat would have.
-- A line with several links opens the first item-type one.
-- Link types that only show a tooltip when opened.
local CHAT_LINK_TYPES = {
	item = true, spell = true, quest = true, achievement = true, enchant = true, currency = true,
	talent = true, battlepet = true, battlePetAbil = true, mount = true, keystone = true, instancelock = true,
}

local function EnableChatLinks()
	local handled = false
	local function MarkHandled()
		handled = true
	end
	for i = 1, NUM_CHAT_WINDOWS or 10 do
		local chatFrame = _G["ChatFrame" .. i]
		if chatFrame then
			chatFrame:HookScript("OnHyperlinkClick", MarkHandled)
		end
	end

	local function GetChatLine()
		local focus = GetMouseFoci and GetMouseFoci()[1]
		-- A forbidden frame (the trade window's secure money input) throws on any method but IsForbidden.
		if not focus or focus:IsForbidden() or focus:GetObjectType() ~= "FontString" then
			return
		end
		local container = focus:GetParent()
		local chatFrame = container and container:GetParent()
		if not chatFrame or not chatFrame.AddMessage or chatFrame.isUninteractable then
			return
		end
		return chatFrame, focus:GetText()
	end

	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("GLOBAL_MOUSE_DOWN")
	watcher:RegisterEvent("GLOBAL_MOUSE_UP")
	watcher:SetScript("OnEvent", function(_, event, button)
		if event == "GLOBAL_MOUSE_DOWN" then
			handled = false
			return
		end
		-- Off by default: SetItemRef from this addon runs the game's chat and tooltip code as this
		-- addon's, which taints Forever's window focus.
		if not (ns.db and ns.db.chatLinks) then
			return
		end
		-- Only a left click on an item-type link. Player names and channels open menus, whispers or /who,
		-- which from addon code are blocked or taint Forever's window focus.
		if button ~= "LeftButton" then
			return
		end
		local chatFrame, text = GetChatLine()
		local link, linkText
		for candidate, candidateText in (text or ""):gmatch("|H(.-)|h(.-)|h") do
			if CHAT_LINK_TYPES[candidate:match("^([^:]+)")] then
				link, linkText = candidate, "|H" .. candidate .. "|h" .. candidateText .. "|h"
				break
			end
		end
		if not link then
			return
		end
		-- Wait a frame: if chat did handle the click itself, it must not be opened twice.
		C_Timer.After(0, function()
			if not handled then
				SetItemRef(link, linkText, button, chatFrame)
			end
		end)
	end)
end

-- Forever closes an empty chat box as soon as it loses focus, and a Shift-click on an item takes the
-- focus, so the link had nowhere to go. A Shift-click while the box is open and empty first puts a
-- space in it, which keeps the box open; the space is taken out again once the link is in.
local function KeepChatOpenForLinks()
	-- With chat closed, the link is held and put into the box the next time chat opens. Opening chat
	-- from this addon's code taints Forever's focus manager, which later blocks an action and shows
	-- the "blocked from an action" popup, so chat is only ever opened by the player.
	local PENDING_SECONDS = 30
	local pendingLink, pendingTime
	-- Off by default: typing into the chat box from this addon runs the game's chat code as this
	-- addon's, which taints Forever's chat and window focus.
	-- Not while the chat box replaces the game's chat: links go to it (ChatBox.lua), and the game's box
	-- is left alone.
	local function On()
		return ns.db and ns.db.chatLinks and ns.db.chatUI ~= "gxiv"
	end
	local function HoldLink(link)
		if not On() or type(link) ~= "string" or not IsModifiedClick("CHATLINK") then
			return
		end
		if ChatFrameUtil.GetActiveWindow() then
			return -- the click already put the link into the open box
		end
		if pendingLink == link and pendingTime == GetTime() then
			return -- both hooks fire for one click
		end
		pendingLink, pendingTime = link, GetTime()
		UIErrorsFrame:AddMessage(link .. " - open chat to post it", 1, 0.82, 0)
	end
	local function InsertHeldLink(editBox)
		if not pendingLink or not On() then
			return
		end
		local link, age = pendingLink, GetTime() - pendingTime
		pendingLink = nil
		if age > PENDING_SECONDS then
			return
		end
		C_Timer.After(0, function()
			if editBox:IsShown() and editBox:GetText() == "" then
				editBox:Insert(link)
			end
		end)
	end
	if ChatFrameUtil and ChatFrameUtil.GetActiveWindow then
		if HandleModifiedItemClick then
			hooksecurefunc("HandleModifiedItemClick", HoldLink)
		end
		if ChatFrameUtil.TryInsertChatLink then
			hooksecurefunc(ChatFrameUtil, "TryInsertChatLink", HoldLink)
		end
		for i = 1, NUM_CHAT_WINDOWS or 10 do
			local editBox = _G["ChatFrame" .. i .. "EditBox"]
			if editBox then
				editBox:HookScript("OnEditFocusGained", InsertHeldLink)
			end
		end
	end

	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("GLOBAL_MOUSE_DOWN")
	watcher:SetScript("OnEvent", function(_, _, button)
		if button ~= "LeftButton" or not IsShiftKeyDown() or not On() then
			return
		end
		local editBox = ChatFrameUtil and ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow()
		if not editBox or not editBox:IsShown() or editBox:GetText() ~= "" then
			return
		end
		editBox:SetText(" ")
		C_Timer.After(0.1, function()
			local text = editBox:GetText()
			if text == " " then
				editBox:SetText("")
			elseif text:sub(1, 1) == " " then
				editBox:SetText(text:sub(2))
			end
		end)
	end)
end

-- What the right stick does while L1 is held.
ns.L1_RIGHT_STICK = {
	{ "zoom", "Zoom (up zooms in)" },
	{ "zoomInverted", "Zoom (up zooms out)" },
	{ "camera", "Turn the camera as usual" },
}

-- L1 + right stick zooms. Rotation is frozen while L1 is held, so the stick only zooms.
local function CreateZoomWatcher()
	local watcher = CreateFrame("Frame")
	-- Past a 1% dead zone the speed starts at a slow crawl and grows with the push, so zooming
	-- starts as soon as the stick tilts. Each frame zooms a little, which the camera blends
	-- smoothly; batching into larger steps made it jerky.
	local DEAD_ZONE = 0.01
	local MIN_ZOOM_PER_SECOND = 3
	local MAX_ZOOM_PER_SECOND = 25
	local frozen = false
	local SPEED_CVARS = { "GamePadCameraYawSpeed", "GamePadCameraPitchSpeed" }

	-- Temporary CVars did not reach the camera, so the speeds are set for real. The previous values
	-- are kept in the saved variables until L1 is released, so a reload or crash mid-zoom restores them.
	local function Restore()
		local saved = ns.db.frozenCameraSpeeds
		if not saved then
			return
		end
		local allRestored = true
		ns.Trail("CVar camera speeds back")
		for name, value in pairs(saved) do
			if not pcall(SetCVar, name, value) then
				allRestored = false
			end
		end
		if allRestored then
			ns.db.frozenCameraSpeeds = nil
		end
	end
	Restore()
	watcher:RegisterEvent("PLAYER_LOGOUT")
	watcher:SetScript("OnEvent", Restore)

	local function SetFrozen(freeze)
		if frozen == freeze then
			return
		end
		frozen = freeze
		if freeze then
			local saved = {}
			for _, name in ipairs(SPEED_CVARS) do
				saved[name] = GetCVar(name)
			end
			ns.db.frozenCameraSpeeds = saved
			-- 0.1 is the lowest speed the client accepts; lower values are silently ignored.
			ns.Trail("CVar camera speeds = 0.1")
			for _, name in ipairs(SPEED_CVARS) do
				pcall(SetCVar, name, "0.1")
			end
		else
			Restore()
		end
	end

	watcher:SetScript("OnUpdate", function(_, elapsed)
		local mode = ns.db.l1RightStick
		local state = GetPadState()
		-- The layer can outlive L1 (a window took its release; in combat it can't be reset), so the
		-- camera only stays frozen while L1 is really down.
		local active = ns.l1Held and ns.IsActive() and mode ~= "camera" and not (state and not PadDown(state, "PADLSHOULDER"))
		-- The addon's ring uses the right stick too, so the camera holds still while it is open.
		SetFrozen((active or ns.ringOpen) and true or false)
		if not active then
			return
		end
		local y = GetCameraStickY(state)
		local push = (math.abs(y) - DEAD_ZONE) / (1 - DEAD_ZONE)
		if push <= 0 then
			return
		end
		push = math.min(push, 1)
		local amount = (MIN_ZOOM_PER_SECOND + (MAX_ZOOM_PER_SECOND - MIN_ZOOM_PER_SECOND) * push ^ 1.5) * elapsed
		if (y > 0) ~= (mode == "zoomInverted") then
			CameraZoomIn(amount)
		else
			CameraZoomOut(amount)
		end
	end)
end

-- Forever gives the right stick to a list while the cursor is in one (the map's quest list, the bags),
-- through its stick listener frame, and the game stops turning the camera with it. With windowCamera
-- on, that frame stops hearing the stick while the list scrolling is the only thing it listens for,
-- so the stick works as with no window open: the camera turns, and auto-run steers. Only the frame's
-- stick input is switched off; Forever switches it on again whenever its stick bindings change.
-- A spell or item waiting for a spot on the ground: Cross becomes the screen click that places it
-- (fc-spellTargeting, read by UpdateTargetBindings). Bindings can't change in combat, so a change
-- there is applied once the fight is over.
-- 1 for a spell waiting for an item, unit or object, 2 for one waiting for a spot on the ground.
local function TargetingKind()
	if not (SpellIsTargeting and SpellIsTargeting()) then
		return 0
	end
	-- Each check is guarded: an API missing or shaped differently on this client must never raise an
	-- error here, which runs every frame. A spell waiting for a unit counts as a spot: with the option
	-- on it goes to the player, as a [@player] macro would.
	for _, check in ipairs({ SpellCanTargetItem, SpellCanTargetItemID, SpellCanTargetGameObject }) do
		local ok, yes = pcall(check)
		if ok and yes then
			return 1
		end
	end
	return 2
end

local function CreateGroundTargetWatcher()
	local watcher = CreateFrame("Frame")
	local applied = 0
	watcher:SetScript("OnUpdate", function()
		local ok, targeting = pcall(TargetingKind)
		targeting = ok and targeting or 0
		if targeting == applied or InCombatLockdown() or not driver then
			return
		end
		applied = targeting
		ns.Trail("ground targeting " .. targeting)
		ns.PlayLog("placing:", targeting == 2 and "spot" or targeting == 1 and "item or object" or "done",
			"under character", tostring(ns.db.groundUnderCharacter), "ui focus", tostring(GamepadMode
			and GamepadMode.FrameControlsManager and GamepadMode.FrameControlsManager.isUIFocused))
		driver:SetAttribute("fc-spellTargeting", targeting)
		SecureHandlerExecute(driver, [[
			self:RunAttribute("UpdateTargetBindings")
			self:RunAttribute("ApplyLayer")
		]])
		-- With a window focused, such as the bags the item was used from, Forever binds Cross to its
		-- cursor click. While a spot is picked with Place under the character on, Cross is taken over
		-- with a binding of this frame's own, given back as soon as the spot is placed or cancelled.
		if targeting == 2 and ns.db.groundUnderCharacter then
			SetOverrideBindingClick(watcher, true, "PAD1", "GamepadXIVGroundSelf", "LeftButton")
		else
			ClearOverrideBindings(watcher)
		end
	end)
end

-- Windows whose text is read by scrolling: there the right stick keeps scrolling, as Forever's D-pad
-- moves between their buttons.
local READING_WINDOWS = { "QuestFrame", "GossipFrame", "QuestLogFrame", "QuestLogDetailFrame", "ItemTextFrame",
	"OpenMailFrame", "QuestMapDetailsScrollFrame" }

local function ReadingWindowOpen()
	for _, name in ipairs(READING_WINDOWS) do
		local frame = _G[name]
		if frame and frame.IsVisible and frame:IsVisible() then
			return name
		end
	end
end

local function CreateWindowCamera()
	local watcher = CreateFrame("Frame")
	local released = false
	watcher:SetScript("OnUpdate", function()
		local listener = inputBindingAxisListener
		local nav = SmartNavigation
		local bindings = nav and nav.rightStickScrollBindings
		local scroll = bindings and bindings.axes and GAMEPAD_STICK_RIGHT and bindings.axes[GAMEPAD_STICK_RIGHT]
		if not (listener and listener.IsGamePadStickEnabled and listener.left and listener.right and scroll) then
			return
		end
		local onlyScrolling = listener.right.func == scroll and not listener.left.func and not listener.left.waitForCentering
		local wanted = ns.db and ns.db.windowCamera and ns.IsActive() and onlyScrolling and not ReadingWindowOpen()
		if wanted and listener:IsGamePadStickEnabled() then
			listener:EnableGamePadStick(false)
			released = true
		elseif released and not wanted then
			released = false
			-- Turned off in the settings: the list scrolls again.
			if onlyScrolling and not listener:IsGamePadStickEnabled() then
				listener:EnableGamePadStick(true)
			end
		end
	end)
end

function ns.PrintInputCVars(report)
	for name in pairs(INPUT_CVARS) do
		report(name, "=", GetCVar(name))
	end
end

-- /gxiv debug: what the game reports for the controls that cannot be checked outside the client.
-- The lines also go to the saved variables, so a /reload makes them readable from the file.
-- Which form number the bottom row follows. The game's bonus bar comes first: cat, prowl, bear and
-- moonkin for druids, stealth for rogues. Stealth also counts on its own, and warrior stances by
-- their stance number, for when the game gives them no bonus bar.
function ns.FormConditions()
	local conditions = "[bonusbar:1] 1; [bonusbar:2] 2; [bonusbar:3] 3; [bonusbar:4] 4; [stealth] 1; "
	if UnitClassBase("player") == "WARRIOR" then
		conditions = conditions .. "[stance:1] 1; [stance:2] 2; [stance:3] 3; "
	end
	return conditions .. "0"
end

function ns.PrintDebug(quiet)
	ns.db.debugLog = {}
	local function Report(...)
		if not quiet then
			ns.Print(...)
		end
		local parts = {}
		for i = 1, select("#", ...) do
			parts[i] = tostring(select(i, ...))
		end
		tinsert(ns.db.debugLog, table.concat(parts, " "))
	end
	for _, key in ipairs({ "PADDUP", "PADDDOWN", "PADDLEFT", "PADLSHOULDER", "PADLSTICKUP", "PADRTRIGGER" }) do
		Report(key, "=", GetBindingAction(key, true))
	end
	ns.PrintInputCVars(Report)
	Report("form: bonus bar", GetBonusBarOffset(), "shapeshift", GetShapeshiftForm(), "stealthed", IsStealthed(),
		"driver form", driver:GetAttribute("fc-rawForm"), "used", driver:GetAttribute("fc-form"),
		"forms change bar", driver:GetAttribute("fc-formLink"), "set", driver:GetAttribute("fc-formset-" .. (driver:GetAttribute("fc-form") or 0)))
	Report("form conditions:", ns.FormConditions(), "->", SecureCmdOptionParse(ns.FormConditions()))
	Report("bonus action bar:", C_ActionBar and C_ActionBar.HasBonusActionBar and C_ActionBar.HasBonusActionBar(),
		"gamepad stance storage:", C_GamepadUI.GetFirstGamepadActionBarStorageSlotIndexForActiveStance
			and C_GamepadUI.GetFirstGamepadActionBarStorageSlotIndexForActiveStance())
	for form = 1, ns.NUM_FORMS do
		local first = ns.db.stanceStorage and ns.db.stanceStorage[form]
		local filled = 0
		for _, slot in ipairs(ns.StanceSlots(form)) do
			if slot > 0 and HasAction(slot) then
				filled = filled + 1
			end
		end
		Report("stance bar", form, "storage", first or "not seen yet", "has", filled, "of 8 slots filled")
	end
	local state = GetPadState()
	Report("pad state:", state and "yes" or "NONE")
	Report("SoftTargetIconInteract =", GetCVar("SoftTargetIconInteract"), "experimental accepted:", ns.db.experimentalAccepted)
	local plate = C_NamePlate.GetNamePlateForUnit("softinteract")
	Report("interact target nameplate:", plate and plate:GetName() or "none")
	Report("D-pad party selection:", ns.db.dpadParty, "in raid:", driver:GetAttribute("fc-inRaid"),
		"last target command:", driver:GetAttribute("fc-targetCycle"))
	Report("target exists:", UnitExists("target"), "soft enemy:", UnitExists("softenemy"), "soft friend:", UnitExists("softfriend"))
	if state then
		for i = 1, state.stickCount do
			Report("stick", i, C_GamePad.StickIndexToConfigName(i - 1))
		end
	end
	Report("For 10 seconds: hold L1, push the right stick up and down, then the left stick forward.")
	local remaining = 10
	local function Sample()
		local padState = GetPadState()
		Report("L1 layer:", ns.l1Held, "stick:", format("%.2f", GetCameraStickY(padState)),
			"zoom:", format("%.1f", GetCameraZoom()), "soft:", driver:GetAttribute("fc-soft"))
		local probe = probeTexture
		for _, unit in ipairs({ "softinteract", "target" }) do
			Report(unit, "exists:", UnitExists(unit), "object:", UnitIsGameObject(unit), "loot:", UnitHasLootInteraction(unit),
				"interactable:", UnitIsInteractable(unit), "dead:", UnitIsDead(unit), "range:", UnitIsInInteractRange(unit),
				"cursor:", SetUnitCursorTexture(probe, unit, nil, nil, false), "low:", SetUnitCursorTexture(probe, unit, nil, true, false))
		end
		remaining = remaining - 1
		if remaining > 0 then
			C_Timer.After(1, Sample)
		end
	end
	C_Timer.After(1, Sample)
end

-- Forever tells where the active stance's gamepad slots are only while it is active. They are saved
-- per bonus bar, so later the form changes the bar at once, in combat too.
function ns.LearnStanceStorage()
	if InCombatLockdown() or not C_GamepadUI or not C_GamepadUI.GetFirstGamepadActionBarStorageSlotIndexForActiveStance then
		return
	end
	local form = GetBonusBarOffset()
	if form < 1 or form > ns.NUM_FORMS then
		return
	end
	local first = C_GamepadUI.GetFirstGamepadActionBarStorageSlotIndexForActiveStance()
	if not first then
		return
	end
	ns.db.stanceStorage = ns.db.stanceStorage or {}
	if ns.db.stanceStorage[form] == first then
		return
	end
	ns.db.stanceStorage[form] = first
	local side = ns.NUM_SETS * 2 + form * 2 - 1
	ns.sideSlots[side] = ns.StanceSlots(form)
	for i = 1, ns.NUM_SLOTS do
		driver:SetAttribute("slot-" .. side .. "-" .. i, ns.sideSlots[side][i])
	end
	SecureHandlerExecute(driver, [[ self:RunAttribute("ApplyLayer") ]])
end

-- Ring.lua: the highlighted entry's key binding for A, or nil. Out of combat only.
function ns.SetRingPickBinding(binding)
	if not driver or InCombatLockdown() or driver:GetAttribute("fc-ringPickBinding") == binding then
		return
	end
	driver:SetAttribute("fc-ringPickBinding", binding)
	SecureHandlerExecute(driver, [[ self:RunAttribute("ApplyLayer") ]])
end

-- What the secure side needs to follow the ring's page for A in combat: the page it opens on and
-- how many there are. Out of combat only.
function ns.SetRingPages(startPage, count, currentPage)
	if driver and not InCombatLockdown() then
		driver:SetAttribute("fc-ringStartPage", startPage)
		driver:SetAttribute("fc-ringPages", count)
		if currentPage then
			driver:SetAttribute("fc-ringPage", currentPage)
		end
	end
end

-- The segment the right stick's held directions point at, as the secure side reads them for A in
-- combat: right is 1, then counterclockwise. 0 with none held.
function ns.RingHeldSegment()
	if not driver then
		return 0
	end
	local up = driver:GetAttribute("fc-held-Up") == 1
	local down = driver:GetAttribute("fc-held-Down") == 1
	if driver:GetAttribute("fc-held-Right") == 1 then
		return (up and 2) or (down and 8) or 1
	elseif driver:GetAttribute("fc-held-Left") == 1 then
		return (up and 4) or (down and 6) or 5
	end
	return (up and 3) or (down and 7) or 0
end

-- The toy pages are showing (or not): A then uses nothing set up for combat.
function ns.SetRingSub(on)
	if driver and not InCombatLockdown() then
		driver:SetAttribute("fc-ringSub", on and 1 or 0)
	end
end

local function SetupDriverData()
	for i, key in ipairs(ns.KEYS) do
		driver:SetAttribute("key" .. i, key)
	end
	for side = 1, #ns.sideSlots do
		for i = 1, ns.NUM_SLOTS do
			driver:SetAttribute("slot-" .. side .. "-" .. i, ns.sideSlots[side][i])
		end
	end
	driver:SetAttribute("fc-stanceSides", ns.NUM_SETS * 2)
	for key, action in pairs(L1_BINDINGS) do
		driver:SetAttribute("l1-" .. key, action)
	end
	driver:SetAttribute("static-count", 0)
end

-- A value the client may hide in combat cannot be tested; it counts as false here.
local function IsTrue(value)
	if issecretvalue and issecretvalue(value) then
		return false
	end
	return value and true or false
end

local function GetInteractButtonAtlas()
	if InputIconTextureSetUtility.GetActiveInputIconButtonTextures(GAMEPAD_FACE_BOTTOM) then
		return InputIconTextureSetUtility.GetNormalActiveInputIconButtonTexture(GAMEPAD_FACE_BOTTOM)
	end
end

-- The action's own icon: loot, talk, skinning, mining, herbalism...
local function ShowActionIcon(texture, unit)
	-- Skinning and similar actions can count as low priority cursors.
	local found = IsTrue(SetUnitCursorTexture(texture, unit, nil, nil, false))
		or IsTrue(SetUnitCursorTexture(texture, unit, nil, true, false))
	texture:SetShown(found)
	return found
end

-- What A / Cross would interact with, in the order Forever checks: the soft interact unit, then the target.
local function GetInteractUnit()
	if IsTrue(UnitExists("softinteract")) or IsTrue(UnitIsGameObject("softinteract")) then
		return "softinteract"
	end
	if IsTrue(UnitExists("target")) and (IsTrue(UnitHasLootInteraction("target")) or IsTrue(UnitIsInteractable("target"))) then
		return "target"
	end
	-- A looted corpse that can still be skinned reports neither, only a cursor.
	if IsTrue(UnitExists("target")) and IsTrue(UnitIsDead("target")) and probeTexture
		and IsTrue(SetUnitCursorTexture(probeTexture, "target", nil, true, false)) then
		return "target"
	end
end

-- A large prompt over the character, movable in move mode. Objects and some units have no nameplate,
-- and the client's own world icon cannot show the right button, so this always works.
local function CreateInteractHud()
	local hud = CreateFrame("Frame", nil, ns.root)
	hud:SetSize(280, 46)
	hud:SetFrameStrata("HIGH")
	hud:Hide()
	ns.interactHud = hud
	probeTexture = hud:CreateTexture(nil, "BACKGROUND")
	probeTexture:Hide()

	local action = hud:CreateTexture(nil, "ARTWORK")
	action:SetSize(38, 38)
	action:SetPoint("RIGHT", hud, "CENTER", -2, 0)

	local button = hud:CreateTexture(nil, "ARTWORK")
	button:SetSize(56, 56)
	button:SetPoint("RIGHT", action, "LEFT", 6, 0)

	local name = hud:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	name:SetPoint("LEFT", hud, "CENTER", 4, 0)

	local waited = 0
	local watcher = CreateFrame("Frame")
	watcher:SetScript("OnUpdate", function(_, elapsed)
		waited = waited + elapsed
		if waited < 0.15 then
			return
		end
		waited = 0

		local unit = ns.db.showInteractPrompt and ns.IsActive() and not ns.editing and GetInteractUnit()
		local atlas = unit and GetInteractButtonAtlas()
		if not atlas then
			hud:Hide()
			return
		end
		button:SetAtlas(atlas)
		ShowActionIcon(action, unit)
		name:SetText(UnitName(unit))
		hud:SetAlpha(IsTrue(UnitIsInInteractRange(unit)) and 1 or 0.5)
		hud:Show()
	end)
	ns.ApplyLayout()
end

-- Forever's interact prompt shows the button of its own layout, X on Xbox and Square on PlayStation.
-- Here that action is on A / Cross, so the client's prompt is off and this draws one on the nameplate,
-- in the active controller's art, next to the action's own icon.
local function HookInteractPrompt()
	if not NamePlateDriverFrame or not NamePlateDriverFrame.UpdateSoftTargetIconInternal then
		return
	end
	local prompts = setmetatable({}, { __mode = "k" })

	hooksecurefunc(NamePlateDriverFrame, "UpdateSoftTargetIconInternal", function(_, frame)
		if frame:IsForbidden() or not frame.UnitFrame or not frame.UnitFrame.SoftTargetFrame then
			return
		end
		local parent = frame.UnitFrame.SoftTargetFrame
		local prompt = prompts[parent]
		local unit = frame:GetUnit()
		local atlas = ns.IsActive() and IsTrue(UnitIsUnit(unit, "softinteract")) and GetInteractButtonAtlas()
		if not atlas then
			if prompt then
				prompt.button:Hide()
				prompt.action:Hide()
			end
			return
		end
		if not prompt then
			prompt = { button = parent:CreateTexture(nil, "OVERLAY"), action = parent:CreateTexture(nil, "OVERLAY") }
			prompt.button:SetSize(30, 30)
			prompt.button:SetPoint("RIGHT", parent, "CENTER", 4, 0)
			prompt.action:SetSize(22, 22)
			prompt.action:SetPoint("LEFT", parent, "CENTER", 4, 0)
			prompts[parent] = prompt
		end
		prompt.button:SetAtlas(atlas)
		prompt.button:Show()
		ShowActionIcon(prompt.action, unit)
	end)
end

-- The keys of the flyout picker, in order. B stays free to cancel.
local FLYOUT_KEYS = { "PAD1", "PAD3", "PAD4", "PADDUP", "PADDRIGHT", "PADDDOWN", "PADDLEFT" }

-- Fills the secure copy of every flyout on the bars. It cannot be read in combat, so it is kept ready.
local function GetFlyoutSpells(flyoutID)
	local spells = {}
	local _, _, numSlots, isKnown = GetFlyoutInfo(flyoutID)
	if not isKnown then
		return spells
	end
	local lastName
	for slot = 1, numSlots do
		local spellID, overrideID, isKnownSlot, name = GetFlyoutSlotInfo(flyoutID, slot)
		if isKnownSlot then
			-- Ranks come in ascending order; only the highest one is offered.
			local spell = overrideID or spellID
			if name == lastName then
				spells[#spells] = spell
			elseif #spells < #FLYOUT_KEYS then
				spells[#spells + 1] = spell
			end
			lastName = name
		end
	end
	return spells
end

local function UpdateFlyouts()
	if InCombatLockdown() then
		ns.syncPending = true
		return
	end
	ns.flyoutSpells = ns.flyoutSpells or {}
	for side = 1, #ns.sideSlots do
		for i = 1, ns.NUM_SLOTS do
			local actionType, flyoutID = GetActionInfo(ns.sideSlots[side][i])
			if actionType == "flyout" and flyoutID then
				local spells = GetFlyoutSpells(flyoutID)
				ns.flyoutSpells[flyoutID] = spells
				driver:SetAttribute("fly-" .. flyoutID .. "-count", #spells)
				for n, spell in ipairs(spells) do
					driver:SetAttribute("fly-" .. flyoutID .. "-" .. n, spell)
				end
			end
		end
	end
end

-- What the picker shows: each choice with the button that casts it.
local flyoutPanel

local function ShowFlyoutPanel(flyoutID)
	if not flyoutPanel then
		flyoutPanel = CreateFrame("Frame", "GamepadXIVFlyoutPanel", UIParent, "BackdropTemplate")
		flyoutPanel:SetFrameStrata("HIGH")
		flyoutPanel:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
		flyoutPanel:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
		flyoutPanel.rows = {}
		for n = 1, #FLYOUT_KEYS do
			local row = {
				icon = flyoutPanel:CreateTexture(nil, "ARTWORK"),
				button = flyoutPanel:CreateTexture(nil, "OVERLAY"),
				name = flyoutPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight"),
			}
			local y = -12 - (n - 1) * 40
			row.button:SetSize(46, 46)
			row.button:SetPoint("TOPLEFT", 4, y + 5)
			row.icon:SetSize(34, 34)
			row.icon:SetPoint("TOPLEFT", 50, y)
			row.name:SetPoint("LEFT", row.icon, "RIGHT", 10, 0)
			flyoutPanel.rows[n] = row
		end
		flyoutPanel.cancel = flyoutPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		flyoutPanel.cancel:SetPoint("BOTTOM", 0, 10)
	end

	if flyoutID == "" or not ns.flyoutSpells or not ns.flyoutSpells[flyoutID] then
		flyoutPanel:Hide()
		return
	end
	local spells = ns.flyoutSpells[flyoutID]
	local utility = InputIconTextureSetUtility
	for n, row in ipairs(flyoutPanel.rows) do
		local spell = spells[n]
		row.icon:SetShown(spell ~= nil)
		row.name:SetShown(spell ~= nil)
		row.button:SetShown(spell ~= nil)
		if spell then
			row.icon:SetTexture(C_Spell.GetSpellTexture(spell))
			row.name:SetText(C_Spell.GetSpellName(spell))
			if utility.GetActiveInputIconButtonTextures(FLYOUT_KEYS[n]) then
				row.button:SetAtlas(utility.GetNormalActiveInputIconButtonTexture(FLYOUT_KEYS[n]))
			end
		end
	end
	flyoutPanel.cancel:SetText(ns.ButtonText("{PAD2}", 18) .. " cancel")
	flyoutPanel:SetSize(300, 54 + #spells * 40)
	flyoutPanel:Show()
end

-- Moving or removing an ability: the panel sits in one place and follows the steps.
local clearPanel
local clearSlot
-- A spell picked in the spellbook (Spellbook.lua), waiting in stage 3 for the slot to go in.
local pendingSpell

function ns.GetActionName(slot)
	local actionType, id = GetActionInfo(slot)
	if actionType == "spell" then
		return C_Spell.GetSpellName(id)
	elseif actionType == "item" then
		return C_Item.GetItemNameByID(id)
	elseif actionType == "macro" then
		return (GetMacroInfo(id))
	elseif actionType == "flyout" then
		return (GetFlyoutInfo(id))
	end
end

local function CreateClearPanel()
	clearPanel = CreateFrame("Frame", "GamepadXIVClearPanel", UIParent, "BackdropTemplate")
	clearPanel:SetSize(440, 118)
	clearPanel:SetFrameStrata("HIGH")
	clearPanel:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
	clearPanel:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	clearPanel:Hide()

	clearPanel.text = clearPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	clearPanel.text:SetPoint("TOP", 0, -14)
	clearPanel.text:SetWidth(390)

	clearPanel.icon = clearPanel:CreateTexture(nil, "ARTWORK")
	clearPanel.icon:SetSize(30, 30)
	clearPanel.icon:SetPoint("TOPLEFT", 16, -12)

	local function CreatePrompt(xOffset, label)
		local button = clearPanel:CreateTexture(nil, "ARTWORK")
		button:SetSize(38, 38)
		button:SetPoint("BOTTOMLEFT", clearPanel, "BOTTOM", xOffset, 6)
		local text = clearPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		text:SetPoint("LEFT", button, "RIGHT", 0, 0)
		text:SetText(label)
		return button, text
	end
	clearPanel.moveButton, clearPanel.moveText = CreatePrompt(-205, "Move")
	clearPanel.replaceButton, clearPanel.replaceText = CreatePrompt(-110, "Replace")
	clearPanel.confirmButton, clearPanel.confirmText = CreatePrompt(0, "Remove")
	clearPanel.cancelButton = CreatePrompt(105, "Cancel")
end

local function SetPromptAtlas(texture, key)
	local utility = InputIconTextureSetUtility
	if utility.GetActiveInputIconButtonTextures(key) then
		texture:SetAtlas(utility.GetNormalActiveInputIconButtonTexture(key))
	end
end

local function ShowClearStage(stage)
	if not clearPanel then
		CreateClearPanel()
	end
	if stage == 4 then
		clearPanel:Hide()
		local function EndClear()
			SecureHandlerExecute(driver, [[ self:RunAttribute("SetClear", 0) ]])
		end
		-- A list that fails to open must not leave the D-pad, A and B bound to nothing.
		local opened, err = pcall(ns.OpenAssign, clearSlot, EndClear)
		if not opened then
			ns.CloseAssign()
			EndClear()
			error(err, 0)
		end
		return
	end
	ns.CloseAssign()
	if stage ~= 3 then
		pendingSpell = nil
	end
	if stage == 0 then
		clearSlot = nil
		clearPanel:Hide()
		return
	end
	SetPromptAtlas(clearPanel.moveButton, "PAD1")
	SetPromptAtlas(clearPanel.replaceButton, "PAD4")
	SetPromptAtlas(clearPanel.confirmButton, "PAD3")
	SetPromptAtlas(clearPanel.cancelButton, "PAD2")
	local choosing = stage == 2
	clearPanel.moveButton:SetShown(choosing)
	clearPanel.moveText:SetShown(choosing)
	clearPanel.replaceButton:SetShown(choosing)
	clearPanel.replaceText:SetShown(choosing)
	clearPanel.confirmButton:SetShown(choosing)
	clearPanel.confirmText:SetShown(choosing)
	clearPanel.icon:SetShown(stage ~= 1)
	if pendingSpell then
		clearPanel.icon:SetTexture(C_Spell.GetSpellTexture(pendingSpell))
	elseif clearSlot then
		clearPanel.icon:SetTexture(C_ActionBar.GetActionTexture(clearSlot))
	end
	local name = clearSlot and ns.GetActionName(clearSlot) or ""
	if pendingSpell then
		clearPanel.text:SetText(ns.ButtonText("Put " .. (C_Spell.GetSpellName(pendingSpell) or "it") .. " where?\n"
			.. "Choose the slot. {PADRSHOULDER} + a button changes the set.", 18))
	elseif stage == 1 then
		clearPanel.text:SetText(ns.ButtonText("Choose the ability to move or remove, or an empty slot to fill.\nHold {PADLTRIGGER} or {PADRTRIGGER}, or double tap for the top row, then press its button.", 18))
	elseif stage == 2 then
		clearPanel.text:SetText("What should happen to this ability?\n" .. name)
	else
		clearPanel.text:SetText("Move " .. name .. ns.ButtonText(" where?\nChoose the slot. {PADRSHOULDER} + a button changes the set. An ability already there swaps.", 18))
	end
	clearPanel:Show()
end

function ns.StartClear()
	if InCombatLockdown() then
		ns.Print("Abilities cannot be moved or removed in combat.")
	elseif not ns.IsActive() or ns.editing then
		ns.Print("This needs the layout active and Move bars closed.")
	else
		SecureHandlerExecute(driver, [[ self:RunAttribute("SetClear", 1) ]])
	end
end

-- Swaps through the cursor, so an ability already in the destination goes to the old slot.
local function MoveAction(from, to)
	if from == to then
		return
	end
	PickupAction(from)
	PlaceAction(to)
	if GetCursorInfo() then
		PlaceAction(from)
	end
	ClearCursor()
end

local function OnClearSlotPressed(cast, _, down)
	local stage = driver:GetAttribute("fc-clear")
	if not down or InCombatLockdown() or (stage ~= 1 and stage ~= 3) then
		return
	end
	local slot = cast:GetAttribute("action")
	if stage == 3 and pendingSpell then
		ClearCursor()
		C_Spell.PickupSpell(pendingSpell)
		if GetCursorInfo() then
			PlaceAction(slot)
		else
			ns.Print("That can't go on a bar.")
		end
		ClearCursor()
		SecureHandlerExecute(driver, [[ self:RunAttribute("SetClear", 0) ]])
	elseif stage == 3 then
		MoveAction(clearSlot, slot)
		SecureHandlerExecute(driver, [[ self:RunAttribute("SetClear", 0) ]])
	else
		-- An empty slot goes straight to the list of what to put in it.
		clearSlot = slot
		local nextStage = C_ActionBar.HasAction(slot) and 2 or 4
		SecureHandlerExecute(driver, ([[ self:RunAttribute("SetClear", %d) ]]):format(nextStage))
	end
end

local function StartMove()
	if clearSlot and not InCombatLockdown() and driver:GetAttribute("fc-clear") == 2 then
		SecureHandlerExecute(driver, [[ self:RunAttribute("SetClear", 3) ]])
	end
end

-- From the spellbook: the spell waits for a slot on the crossbar, chosen once the spellbook is closed.
function ns.StartPlaceSpell(spellID)
	if InCombatLockdown() or not driver then
		return
	end
	ns.Trail("spellbook pick " .. tostring(spellID))
	clearSlot = nil
	if driver:GetAttribute("fc-clear") == 3 then
		SecureHandlerExecute(driver, [[ self:RunAttribute("SetClear", 0) ]])
	end
	pendingSpell = spellID
	SecureHandlerExecute(driver, [[ self:RunAttribute("SetClear", 3) ]])
end

local function StartReplace()
	if clearSlot and not InCombatLockdown() and driver:GetAttribute("fc-clear") == 2 then
		SecureHandlerExecute(driver, [[ self:RunAttribute("SetClear", 4) ]])
	end
end

local function ConfirmClear()
	if clearSlot and not InCombatLockdown() and driver:GetAttribute("fc-clear") == 2 then
		PickupAction(clearSlot)
		ClearCursor()
		SecureHandlerExecute(driver, [[ self:RunAttribute("SetClear", 0) ]])
	end
end

-- The equipment slots an item of each kind goes in, for comparing a roll with what is worn.
local EQUIP_SLOTS = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
	INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
	INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
	INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
	INVTYPE_SHIELD = { 17 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
	INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 },
	INVTYPE_THROWN = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_RELIC = { 18 }, INVTYPE_TABARD = { 19 },
}
ns.EQUIP_SLOTS = EQUIP_SLOTS -- the chat box's item tooltips compare with these too

-- Item details for loot rolls: the item and what you wear in its slot, beside the roll window, for as
-- long as it is open. Forever only shows the item while a button in the window has focus, without the
-- comparison. These are the addon's own tooltips, so Forever's GameTooltip is left alone.
local function SetupLootDetails(lootFrame)
	local activeRolls = {}
	local function CreateTip(name)
		local tip = CreateFrame("GameTooltip", name, UIParent, "GameTooltipTemplate")
		tip:SetClampedToScreen(true)
		return tip
	end
	local itemTip = CreateTip("GamepadXIVRollTip")
	local compareTips = { CreateTip("GamepadXIVRollCompare1"), CreateTip("GamepadXIVRollCompare2") }
	for _, tip in ipairs(compareTips) do
		local header = tip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		header:SetPoint("BOTTOMLEFT", tip, "TOPLEFT", 4, 2)
		header:SetText("Currently equipped")
	end

	local function CurrentRoll()
		local rollID = lootFrame.rollID
		if rollID and GetLootRollItemLink(rollID) then
			return rollID
		end
		for _, id in ipairs(activeRolls) do
			if GetLootRollItemLink(id) then
				return id
			end
		end
	end

	local function Refresh()
		itemTip:Hide()
		for _, tip in ipairs(compareTips) do
			tip:Hide()
		end
		local rollID = lootFrame:IsShown() and ns.db.lootDetails and CurrentRoll()
		if not rollID then
			return
		end
		itemTip:SetOwner(lootFrame, "ANCHOR_NONE")
		itemTip:ClearAllPoints()
		itemTip:SetPoint("TOPRIGHT", lootFrame, "TOPLEFT", -8, 0)
		itemTip:SetLootRollItem(rollID)
		itemTip:Show()

		local _, _, _, equipLoc = C_Item.GetItemInfoInstant(GetLootRollItemLink(rollID))
		local previous = itemTip
		for index, slot in ipairs(EQUIP_SLOTS[equipLoc] or {}) do
			local tip = compareTips[index]
			if GetInventoryItemLink("player", slot) then
				tip:SetOwner(lootFrame, "ANCHOR_NONE")
				tip:ClearAllPoints()
				tip:SetPoint("TOPRIGHT", previous, "TOPLEFT", -6, 0)
				tip:SetInventoryItem("player", slot)
				tip:Show()
				previous = tip
			end
		end
	end
	ns.RefreshLootDetails = Refresh

	local events = CreateFrame("Frame")
	events:RegisterEvent("START_LOOT_ROLL")
	events:RegisterEvent("CANCEL_LOOT_ROLL")
	events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	events:SetScript("OnEvent", function(_, event, rollID)
		if event == "START_LOOT_ROLL" then
			tinsert(activeRolls, rollID)
		elseif event == "CANCEL_LOOT_ROLL" then
			tDeleteItem(activeRolls, rollID)
		end
		-- The window updates on the same events; wait a moment so it shows the new roll first.
		C_Timer.After(0.1, Refresh)
	end)
	lootFrame:HookScript("OnShow", function()
		C_Timer.After(0.1, Refresh)
	end)
	lootFrame:HookScript("OnHide", Refresh)
end

-- WoW's own setting that compares an item with what you wear on every item tooltip, without holding Shift.
function ns.ApplyAlwaysCompare()
	if ns.db.alwaysCompareItems ~= nil and GetCVar("alwaysCompareItems") ~= nil then
		ns.Trail("CVar alwaysCompareItems")
		SetCVar("alwaysCompareItems", ns.db.alwaysCompareItems and "1" or "0")
	end
end

function ns.CreateInput()
	ns.ApplyAlwaysCompare()
	driver = CreateFrame("Frame", "GamepadXIVDriver", UIParent, "SecureHandlerStateTemplate")

	driver:SetAttribute("ApplyLayer", S.ApplyLayer)
	driver:SetAttribute("BindAll", S.BindAll)
	driver:SetAttribute("UpdateTargetBindings", S.UpdateTargetBindings)
	driver:SetAttribute("UpdateYield", S.UpdateYield)
	driver:SetAttribute("OnTrigger", S.OnTrigger)
	driver:SetAttribute("UpdateTriggerLayer", S.UpdateTriggerLayer)
	driver:SetAttribute("ReturnFromTop", S.ReturnFromTop)
	driver:SetAttribute("SetSoft", S.SetSoft)
	driver:SetAttribute("ReturnToGroupUnit", S.ReturnToGroupUnit)
	driver:SetAttribute("CycleGroup", S.CycleGroup)
	driver:SetAttribute("PartyCycleUnit", S.PartyCycleUnit)
	driver:SetAttribute("SelectGroupUnit", S.SelectGroupUnit)
	driver:SetAttribute("MoveFrameCursor", S.MoveFrameCursor)
	driver:SetAttribute("HoldStart", S.HoldStart)
	driver:SetAttribute("HoldStop", S.HoldStop)
	driver:SetAttribute("HoldTick", S.HoldTick)
	driver:SetAttribute("OpenFlyout", S.OpenFlyout)
	driver:SetAttribute("CloseFlyout", S.CloseFlyout)
	driver:SetAttribute("SetClear", S.SetClear)
	driver:SetAttribute("SwapTapSets", S.SwapTapSets)
	driver:SetAttribute("fc-clear", 0)
	driver:SetAttribute("fc-flyout", "")
	for n, key in ipairs(FLYOUT_KEYS) do
		driver:SetAttribute("flyKey-" .. key, n)
	end
	driver:SetAttribute("BeginEdit", S.BeginEdit)
	driver:SetAttribute("EndEdit", S.EndEdit)
	driver:SetAttribute("_onstate-fccombat", S.OnStateCombat)
	driver:SetAttribute("_onstate-fctarget", S.OnStateTarget)
	driver:SetAttribute("_onstate-fcenemy", S.OnStateTarget)
	driver:SetAttribute("_onstate-fcmounted", S.OnStateTarget)
	driver:SetAttribute("_onstate-fcmove", S.OnStateTarget)
	driver:SetAttribute("_onstate-fcvehicle", S.OnStateVehicle)
	driver:SetAttribute("_onstate-fcraid", S.OnStateRaid)
	driver:SetAttribute("UpdateForm", S.UpdateForm)
	driver:SetAttribute("_onstate-fcform", S.OnStateForm)

	driver:SetAttribute("fc-off", 1)
	driver:SetAttribute("fc-vehicle", 0)
	driver:SetAttribute("fc-yield", 1)
	driver:SetAttribute("fc-layer", "BASE")
	driver:SetAttribute("fc-lDown", 0)
	driver:SetAttribute("fc-rDown", 0)
	driver:SetAttribute("fc-w", "")
	driver:SetAttribute("fc-first", "")
	driver:SetAttribute("fc-editing", 0)
	-- The tutorial's buttons, used while it is open (fc-tutorial): next, back, chapters and close.
	driver:SetAttribute("fc-tutorial", 0)
	driver:SetAttribute("tutorial-PAD1", "GamepadXIVTutorialNext")
	driver:SetAttribute("tutorial-PAD2", "GamepadXIVTutorialBack")
	driver:SetAttribute("tutorial-PAD4", "GamepadXIVTutorialClose")
	driver:SetAttribute("tutorial-PAD3", "GamepadXIVTutorialChapters")
	driver:SetAttribute("fc-soft", "")
	driver:SetAttribute("fc-latch", "")
	driver:SetAttribute("fc-consumed", "")
	driver:SetAttribute("fc-triggerMode", ns.db.triggerMode)
	driver:SetAttribute("fc-wReturn", ns.db.wxhbReturn and 1 or 0)
	driver:SetAttribute("fc-form", 0)
	driver:SetAttribute("fc-rawForm", 0)

	for n, row in ipairs(ns.ROWS) do
		driver:SetAttribute("rowKey" .. n, row)
		SecureHandlerSetFrameRef(driver, "content" .. row, ns.root.sides[row].content)
		for i = 1, ns.NUM_SLOTS do
			SecureHandlerSetFrameRef(driver, "btn" .. row .. i, _G["GamepadXIVBtn" .. row .. i])
		end
	end

	driver.OnLayerChanged = function(_, ...) ns.ShowLayer(...) end
	-- The R1 tap changed the top row: kept, so the next sync does not put the old one back.
	driver.OnTapCombo = function(_, sideLR, sideRL)
		ns.db.sideLR, ns.db.sideRL = sideLR, sideRL
	end
	driver.OnTapSwap = function(_, _, sideWL, sideWR)
		ns.db.sideWL, ns.db.sideWR = sideWL, sideWR
		-- Redraws the bars' labels with the new top sets, which also flashes the top bars.
		if ns.lastShown then
			ns.ShowLayer(unpack(ns.lastShown))
		end
	end
	driver.OnEditEnded = function() ns.OnEditEnded() end
	driver.OnFlyoutChanged = function(_, flyoutID) ShowFlyoutPanel(flyoutID) end
	driver.OnRing = function(_, action) ns.OnRing(action) end
	driver.OnClearChanged = function(_, stage) ShowClearStage(stage) end
	driver.OnSoftChanged = function(_, unit) ns.ShowSoftTarget(unit) end
	driver.OnYieldChanged = function(_, yielded)
		if yielded then
			ShowFlyoutPanel("")
		end
		ns.ApplyForeverBarVisibility(yielded)
		ns.UpdatePartyPrompt()
		-- Temp CVars have no combat restriction, so Forever gets its inputs back in vehicles too.
		if ns.cvarsApplied ~= not yielded then
			ns.cvarsApplied = not yielded
			ApplyTempCVars(not yielded)
			if yielded then
				StopWalking()
				SetCameraLock(false)
			end
		end
	end

	SetupDriverData()
	SetupBaseBindings()
	CreateHelperButtons()
	ns.CreateSpellActions()
	CreateZoomWatcher()
	CreateWindowCamera()
	CreateGroundTargetWatcher()
	EnableChatLinks()
	FixEquipmentSetList()
	CreateMapPinChord()
	CreateBackChat()
	CreateL1Release()
	KeepChatOpenForLinks()
	HookInteractPrompt()
	CreateInteractHud()

	CreateTrigger("GamepadXIVL2", "L")
	CreateTrigger("GamepadXIVR2", "R")
	CreateL1()
	CreateSecureButton("GamepadXIVStickUp", S.StickUpClick)
	-- R1 keeps the trigger clock too: a quick release is the set swap tap.
	local r1 = CreateSecureButton("GamepadXIVR1", S.R1Click)
	r1:SetAttribute("fc-ready", 1)
	r1:SetAttribute("fc-ticks", 0)
	r1:SetAttribute("_onattributechanged", S.TriggerAttribute)
	RegisterAttributeDriver(r1, "fc-ready", 1)
	-- R1 + L2 while the R1 tap is on: marks R1's press as a chord, then tab targets. R1 + L3 / R3
	-- need none: the ring and the class menus mark it when they open.
	local chordL2 = CreateSecureButton("GamepadXIVR1ChordL2", S.R1ChordPre)
	chordL2:SetAttribute("type", "macro")
	chordL2:SetAttribute("macrotext", "/targetenemy")
	-- Holding the D-pad on party selection, with Party targeting on Soft, keeps stepping: the clock
	-- for it is an attribute driver, the only timer secure code has (S.HoldTick).
	local holdTicker = CreateFrame("Frame", "GamepadXIVHoldTicker", driver, "SecureHandlerAttributeTemplate")
	SecureHandlerSetFrameRef(holdTicker, "driver", driver)
	SecureHandlerSetFrameRef(driver, "holdTicker", holdTicker)
	holdTicker:SetAttribute("fc-tick", 1)
	holdTicker:SetAttribute("_onattributechanged", S.HoldTickerAttribute)
	RegisterAttributeDriver(holdTicker, "fc-tick", 1)
	CreateCycle("GamepadXIVPartyPrev", -1, false)
	CreateCycle("GamepadXIVPartyNext", 1, false)
	CreateCycle("GamepadXIVRaidPrev", -1, true)
	CreateCycle("GamepadXIVRaidNext", 1, true)
	CreateTargetCycle("GamepadXIVTargetPrev", -1)
	CreateTargetCycle("GamepadXIVTargetNext", 1)
	CreateFrameMove("GamepadXIVFrameUp", 0, 1)
	CreateFrameMove("GamepadXIVFrameDown", 0, -1)
	CreateFrameMove("GamepadXIVFrameLeft", -1, 0)
	CreateFrameMove("GamepadXIVFrameRight", 1, 0)

	local softConfirm = CreateSecureButton("GamepadXIVSoftConfirm", S.SoftConfirmPreClick, "PreClick")
	softConfirm:RegisterForClicks("AnyDown")
	softConfirm:SetAttribute("type", "target")
	-- Place under the character: targeting the player while a spot on the ground is picked puts it there.
	local groundSelf = CreateSecureButton("GamepadXIVGroundSelf")
	groundSelf:RegisterForClicks("AnyDown")
	groundSelf:SetAttribute("type", "target")
	groundSelf:SetAttribute("unit", "player")
	groundSelf:HookScript("OnClick", function()
		ns.PlayLog("placing: under the character")
	end)
	CreateSecureButton("GamepadXIVSoftCancel", S.SoftCancelClick)

	for i = 1, ns.NUM_SLOTS do
		for _, row in ipairs(ns.ROWS) do
			-- The keys press these instead of the visible slots: ActionBarButtonTemplate always casts
			-- on key up, which is too late for the soft target and loses a cast if the trigger is released first.
			local cast = CreateSecureButton("GamepadXIVCast" .. row .. i)
			cast:SetAttribute("type", "action")
			cast:SetAttribute("fc-topRow", (row == "WL" or row == "WR") and 1 or 0)
			SecureHandlerSetFrameRef(driver, "cast" .. row .. i, cast)
			SecureHandlerWrapScript(cast, "OnClick", cast, S.ActionPre, S.ActionPost)
			cast:HookScript("OnClick", OnClearSlotPressed)
			local index = i
			cast:HookScript("OnClick", function(_, _, down)
				ns.ShowPress(row, index, down)
			end)
		end
	end

	local pageUnit = GamepadMainActionBarFrame and GamepadMainActionBarFrame.PageUnit
	local pageButton = pageUnit and pageUnit.PageTracker and pageUnit.PageTracker.ChangePageButton
	driver:SetAttribute("fc-numPages", 3)

	-- Forever turns these two buttons into the pet menus for hunters and warlocks, on the bar this
	-- addon hides. They keep working from Forever's own chords, so only their art has to stay visible.
	local className = UnitClassBase("player")
	if pageUnit and (className == "HUNTER" or className == "WARLOCK") then
		driver:SetAttribute("fc-petChords", 1)
		ns.ApplyPetButtons()
	end

	-- L1 + R3 and R1 + L3 click Forever's two class buttons, which open its pet menus for hunters and
	-- warlocks, and its form, aura or stance menus for druids, paladins and warriors. Those buttons
	-- hide when the class has no menu, and the binding then keeps L3's own action.
	for side, key in pairs({ L = "LeftClassAction", R = "RightClassAction" }) do
		local button = pageUnit and pageUnit[key]
		if button and button:GetName() then
			SecureHandlerSetFrameRef(driver, "classMenu" .. side, button)
			driver:SetAttribute("classMenu-" .. side, button:GetName())
			if button:IsProtected() then
				SecureHandlerWrapScript(button, "OnClick", driver, S.ClassMenuClick)
			end
		end
	end
	-- The open menu is watched through the secure wrapper, which leaves Forever's frames untainted.
	local popupCount = 0
	local PET_POPUP_SIDE = { [GamepadPetActionFlyout or false] = "L", [GamepadPetSpellFlyout or false] = "R" }
	for _, popup in ipairs({ GamepadPetActionFlyout, GamepadPetSpellFlyout, GamepadSpellFlyout }) do
		if popup and popup:IsProtected() then
			popupCount = popupCount + 1
			SecureHandlerSetFrameRef(driver, "classPopup" .. popupCount, popup)
			local side = PET_POPUP_SIDE[popup]
			if side then
				-- The after part runs only when the before part returns something for it.
				SecureHandlerWrapScript(popup, "OnShow", driver, S.ClassPopupShown .. '\nreturn nil, "' .. side .. '"',
					"local side = message\n" .. S.PetPopupShown)
			else
				SecureHandlerWrapScript(popup, "OnShow", driver, S.ClassPopupShown)
			end
			SecureHandlerWrapScript(popup, "OnHide", driver, S.ClassPopupShown)
			popup:HookScript("OnShow", function() SetStickButtons(false) end)
			popup:HookScript("OnHide", function() SetStickButtons(true) end)
		end
	end
	driver:SetAttribute("classPopup-count", popupCount)
	-- Only hunters and warlocks see the two buttons; the others are on the bar this addon hides.
	if driver:GetAttribute("fc-petChords") == 1 then
		ns.CreateClassMenuHints(pageUnit)
	end

	for n = 1, #FLYOUT_KEYS do
		local pick = CreateSecureButton("GamepadXIVFlyoutPick" .. n)
		pick:SetAttribute("type", "spell")
		SecureHandlerSetFrameRef(driver, "flyoutPick" .. n, pick)
		SecureHandlerWrapScript(pick, "OnClick", pick, S.FlyoutPickPre, S.FlyoutPickPost)
	end
	CreateSecureButton("GamepadXIVFlyoutCancel", S.FlyoutCancelClick)
	-- The addon's ring: a toggle, and the keys it takes while open. A uses the highlighted entry:
	-- Ring.lua sets this button's click on Forever's own button for the built-in entries.
	CreateSecureButton("GamepadXIVRingToggle", S.RingToggleClick)
	local ringPick = CreateSecureButton("GamepadXIVRingpick")
	SecureHandlerWrapScript(ringPick, "OnClick", ringPick, S.RingPickPre, S.RingPickPost)
	driver:SetAttribute("ringKey-PAD1", "GamepadXIVRingpick")
	ns.ringPickButton = ringPick
	-- Letting go of the right stick, when the setting is on: acts on the release, not the press.
	ns.ringReleaseButtons = {}
	for _, dir in ipairs({ "Up", "Down", "Left", "Right" }) do
		local ringRelease = CreateSecureButton("GamepadXIVRingrelease" .. dir)
		ringRelease:SetAttribute("useOnKeyDown", false)
		ringRelease:SetAttribute("fc-dir", dir)
		SecureHandlerWrapScript(ringRelease, "OnClick", ringRelease, S.RingReleasePre, S.RingPickPost)
		tinsert(ns.ringReleaseButtons, ringRelease)
	end
	-- The Game Menu opened from the ring (A pressed its key binding): the ring closes and gives its
	-- keys back. Only out of combat, as A only takes the binding then.
	-- The chat box, opened by the ring's Chat entry, does the same.
	local function CloseRingOnShow()
		if ns.ringOpen and not InCombatLockdown() then
			driver:SetAttribute("fc-ring", 0)
			driver:SetAttribute("fc-ringPickBinding", nil)
			SecureHandlerExecute(driver, [[ self:RunAttribute("ApplyLayer") ]])
			ns.OnRing("close")
		end
	end
	if GameMenuFrame then
		GameMenuFrame:HookScript("OnShow", CloseRingOnShow)
	end
	-- The chat box can stay shown between messages, so it is its typing focus that counts.
	if ChatEdit_ActivateChat then
		hooksecurefunc("ChatEdit_ActivateChat", CloseRingOnShow)
	end
	for i = 1, NUM_CHAT_WINDOWS or 10 do
		local editBox = _G["ChatFrame" .. i .. "EditBox"]
		if editBox then
			editBox:HookScript("OnEditFocusGained", CloseRingOnShow)
		end
	end
	local ringKeys = {
		PAD2 = "close", PADRSTICK = "close", PADDLEFT = "prev", PADDRIGHT = "next", PADLSHOULDER = "prev", PADRSHOULDER = "next", PADDUP = "emotes",
	}
	for key, action in pairs(ringKeys) do
		local name = "GamepadXIVRing" .. action
		if not _G[name] then
			local button = CreateSecureButton(name, S.RingKeyClick)
			button:SetAttribute("fc-ringAction", action)
		end
		driver:SetAttribute("ringKey-" .. key, name)
	end
	-- D-pad down sits or stands, like Forever's ring; the ring stays open.
	driver:SetAttribute("ringBind-PADDDOWN", "SITORSTAND")
	driver:SetAttribute("fc-ring", 0)
	CreateSecureButton("GamepadXIVClearStart", S.ClearStartClick)
	CreateSecureButton("GamepadXIVClearCancel", S.ClearCancelClick)
	CreatePlainButton("GamepadXIVClearConfirm", ConfirmClear)
	CreatePlainButton("GamepadXIVSlotMove", StartMove)
	CreatePlainButton("GamepadXIVSlotReplace", StartReplace)
	-- The list of what to put in a slot (Assign.lua) takes the D-pad, A and B. Holding the D-pad keeps moving.
	for key, name in pairs({ PADDUP = "Up", PADDDOWN = "Down", PADDLEFT = "Left", PADDRIGHT = "Right", PAD1 = "Accept", PAD2 = "Back" }) do
		CreatePlainButton("GamepadXIVAssign" .. name, function() ns.AssignNav(name) end, key:find("^PADD") ~= nil)
		driver:SetAttribute("assignKey-" .. key, "GamepadXIVAssign" .. name)
	end

	for i = 1, ns.NUM_SLOTS do
		local button = CreateSecureButton("GamepadXIVSet" .. i, S.SetClick)
		button:SetAttribute("fc-setIndex", ns.SET_BY_KEY[i])
		button:SetAttribute("clickbutton", pageButton)
	end

	RegisterStateDriver(driver, "fctarget", "[@target,exists] 1; 0")
	-- Cross's binding follows whether the target is a living enemy and nothing else is to interact with.
	RegisterStateDriver(driver, "fcenemy", "[@softinteract,exists] 0; [@target,harm,nodead] 1; 0")
	RegisterStateDriver(driver, "fcmounted", "[mounted] 1; 0")
	RegisterStateDriver(driver, "fccombat", "[combat] 1; 0")
	RegisterStateDriver(driver, "fcmove", "[flying][swimming] 1; 0")
	RegisterStateDriver(driver, "fcform", ns.FormConditions())
	RegisterStateDriver(driver, "fcvehicle", "[overridebar][vehicleui][possessbar] 1; 0")
	RegisterStateDriver(driver, "fcraid", "[group:raid] 1; 0")

	-- Forever's window bindings are priority overrides, so they win while a window is focused.
	-- Closing one writes empty overrides back, so bindings are reasserted afterwards: on the next
	-- frame, once Forever's binding change (opening chat, focusing a window) is over, so none of this
	-- runs inside it, and once for a burst of them.
	local manager = GamepadSharedUtility and GamepadSharedUtility.InputBindingManager
	if manager then
		local queued = false
		local function SyncSoon()
			if queued then
				return
			end
			queued = true
			C_Timer.After(0, function()
				queued = false
				ns.Sync()
			end)
		end
		hooksecurefunc(manager, "RemoveSet", SyncSoon)
		hooksecurefunc(manager, "ClearBindings", SyncSoon)
	end

	-- A timer leaves Blizzard's popup code before anything here runs. The wait after one appears
	-- keeps a button press meant for the fight from answering it, such as releasing by accident.
	local function OnPopupChanged(popup)
		C_Timer.After(popup:IsShown() and 1 or 0, function()
			local _, index = GetAnsweredPopup()
			if index or (driver:GetAttribute("fc-answeredPopup") or 0) ~= 0 then
				ns.Sync()
			end
			UpdatePopupHint()
		end)
	end
	for index = 1, INVITE_POPUP do
		local popup = PopupByIndex(index)
		if popup then
			popup:HookScript("OnShow", OnPopupChanged)
			popup:HookScript("OnHide", OnPopupChanged)
		end
	end

	-- Forever shows loot rolls without focus, and nothing on screen says Back is what focuses them.
	local lootFrame = GamepadGroupLootRollFrame
	if lootFrame then
		ns.lootFrame = lootFrame
		-- Forever may place the window again when it opens, so a moved window is put back each time.
		-- Only a script hook: hooking the frame's methods could taint Forever's own focus handling.
		lootFrame:HookScript("OnShow", function()
			ns.PlaceLootFrame()
		end)
		SetupLootDetails(lootFrame)
		local lootHint = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		lootHint:SetPoint("TOP", lootFrame, "BOTTOM", 0, -8)
		lootHint:Hide()
		local function ShowLootHint()
			-- In a fight Back may be the chat box's: it opens the roll picker then (RollPicker.lua).
			lootHint:SetText(ns.ButtonMarkup("PADBACK", "Back", 28) .. " Roll on loot")
			lootHint:SetShown(ns.IsActive())
		end
		lootFrame:HookScript("OnShow", function()
			if ns.ChatBoxYield then
				ns.ChatBoxYield("the loot roll")
			end
			ShowLootHint()
		end)
		local combatEnd = CreateFrame("Frame")
		combatEnd:RegisterEvent("PLAYER_REGEN_ENABLED")
		combatEnd:SetScript("OnEvent", function()
			if lootFrame:IsShown() then
				ShowLootHint()
			end
		end)
		lootFrame:HookScript("OnHide", function()
			lootHint:Hide()
		end)
	end

	-- Forever's own bar editor needs its triggers and bar back while it is open.
	if GamepadActionBarEditFrame then
		GamepadActionBarEditFrame:HookScript("OnShow", function()
			ns.foreverEditorOpen = true
			ns.Sync()
		end)
		GamepadActionBarEditFrame:HookScript("OnHide", function()
			ns.foreverEditorOpen = false
			ns.Sync()
		end)
	end

	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterEvent("CVAR_UPDATE")
	events:RegisterEvent("INPUT_DEVICE_INTERFACE_TRANSITION")
	events:RegisterEvent("PLAYER_TARGET_CHANGED")
	events:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
	events:RegisterEvent("SPELLS_CHANGED")
	events:RegisterEvent("GROUP_ROSTER_UPDATE")
	events:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
	events:SetScript("OnEvent", function(_, event, cvar)
		if event == "UPDATE_BONUS_ACTIONBAR" then
			ns.LearnStanceStorage()
			return
		end
		if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then
			ns.LearnStanceStorage()
		end
		if event == "ACTIONBAR_SLOT_CHANGED" or event == "SPELLS_CHANGED" then
			UpdateFlyouts()
			return
		end
		-- Blizzard creates the frames on its own roster update, which may run after this one.
		if event == "GROUP_ROSTER_UPDATE" then
			C_Timer.After(0.5, RefreshUnitFrameRefs)
			return
		end
		if event == "PLAYER_REGEN_ENABLED" then
			RefreshUnitFrameRefs()
		end
		if event == "PLAYER_TARGET_CHANGED" then
			if not UnitExists("target") then
				SetCameraLock(false)
			end
			SyncCycleToTarget()
			return
		end
		if event == "CVAR_UPDATE" and cvar ~= "InputDeviceInterfaceStyle" then
			return
		end
		if event == "PLAYER_REGEN_ENABLED" and not ns.syncPending then
			return
		end
		ns.Sync()
	end)
end

function ns.SetEditSides(left, right)
	if InCombatLockdown() then
		return
	end
	driver:SetAttribute("fc-edit-left", left)
	driver:SetAttribute("fc-edit-right", right)
	if driver:GetAttribute("fc-editing") == 1 then
		SecureHandlerExecute(driver, [[ self:RunAttribute("ApplyLayer") ]])
	end
end

-- The tutorial takes the face buttons while it is open, and D-pad up / down while its chapter list
-- is; out of combat only. `free` lists face buttons a step teaches, which keep their own action on it.
local TUTORIAL_FACE = { PAD1 = "GamepadXIVTutorialNext", PAD2 = "GamepadXIVTutorialBack",
	PAD3 = "GamepadXIVTutorialChapters", PAD4 = "GamepadXIVTutorialClose" }
function ns.SetTutorialKeys(on, chapters, free)
	if not driver or InCombatLockdown() then
		return
	end
	-- Only rebinds when something changed: rebinding a held button can lose its release.
	local changed = false
	local function Set(name, value)
		if driver:GetAttribute(name) ~= value then
			driver:SetAttribute(name, value)
			changed = true
		end
	end
	Set("fc-tutorial", on and 1 or 0)
	for key, button in pairs(TUTORIAL_FACE) do
		local freed = not chapters and free and tContains(free, key)
		Set("tutorial-" .. key, not freed and button or nil)
	end
	Set("tutorial-PADDUP", on and chapters and "GamepadXIVTutorialUp" or nil)
	Set("tutorial-PADDDOWN", on and chapters and "GamepadXIVTutorialDown" or nil)
	if not changed then
		return
	end
	SecureHandlerExecute(driver, [[ self:RunAttribute("ApplyLayer") ]])
end

function ns.BeginEdit(left, right)
	ns.SetEditSides(left, right)
	SecureHandlerExecute(driver, [[ self:RunAttribute("BeginEdit") ]])
end

function ns.EndEdit()
	if InCombatLockdown() then
		return
	end
	SecureHandlerExecute(driver, [[ self:RunAttribute("EndEdit") ]])
end

function ns.IsActive()
	return driver and driver:GetAttribute("fc-yield") == 0
end

-- Forever's bind flow from the spellbook stays in charge of the buttons, but its bars are hidden and this
-- addon's bars show the result. Slots land on Forever's current page, which is the set of the same number.
local function SetEditorBarsShown(shown)
	local pageUnit = GamepadActionBarEditFrame and GamepadActionBarEditFrame.PageUnit
	if not pageUnit or not pageUnit.actionBars then
		return
	end
	for _, bar in pairs(pageUnit.actionBars) do
		if type(bar) == "table" and bar.SetAlpha then
			bar:SetAlpha(shown and 1 or 0)
		end
	end
end

local shownEditorPage

local function ShowEditorPage()
	if InCombatLockdown() then
		return
	end
	local page = GamepadActionBarEditFrame.PageUnit:GetCurrentPage()
	if page == shownEditorPage or not ns.sideSlots[page * 2] then
		return
	end
	shownEditorPage = page
	for i = 1, ns.NUM_SLOTS do
		_G["GamepadXIVBtnL" .. i]:SetAttribute("action", ns.sideSlots[page * 2 - 1][i])
		_G["GamepadXIVBtnR" .. i]:SetAttribute("action", ns.sideSlots[page * 2][i])
	end
	ns.root.setText:SetText("SET " .. page)
end

local editorWatcher = CreateFrame("Frame")
editorWatcher:Hide()
editorWatcher:SetScript("OnUpdate", ShowEditorPage)

function ns.ApplyForeverBarVisibility(foreverShown)
	local alpha = foreverShown and 1 or 0
	if GamepadMainActionBarFrame and GamepadMainActionBarFrame:GetAlpha() ~= alpha then
		ns.Trail("GamepadMainActionBarFrame:SetAlpha " .. alpha)
		GamepadMainActionBarFrame:SetAlpha(alpha)
	end
	local inBindFlow = foreverShown and ns.foreverEditorOpen
	SetEditorBarsShown(not inBindFlow)
	editorWatcher:SetShown(inBindFlow and true or false)
	if not inBindFlow then
		shownEditorPage = nil
	end
	ns.SetBarShown(inBindFlow or not foreverShown)
end

-- Pushes settings into the secure driver and rebinds. Attributes on protected frames cannot be
-- written from addon code in combat, so this waits for combat to end.
-- What L3 and R3 can do, chosen in the settings: key, label, binding.
ns.STICK_ACTIONS = {
	{ "sheathe", "Draw / sheathe weapon", "TOGGLESHEATH" },
	{ "view", "First / third person", "CLICK GamepadXIVView:LeftButton" },
	{ "autorun", "Auto-run", "TOGGLEAUTORUN" },
	{ "walk", "Walk / run", "TOGGLERUN" },
	{ "sit", "Sit / stand", "SITORSTAND" },
	{ "target", "Target nearest enemy", "TARGETNEARESTENEMY" },
	{ "assist", "Assist target", "ASSISTTARGET" },
	{ "follow", "Follow target", "FOLLOWTARGET" },
	{ "map", "World map", "TOGGLEWORLDMAP", nil, "Interface\\Icons\\INV_Misc_Map_01" },
	{ "bags", "Bags", "OPENALLBAGS", nil, "Interface\\Icons\\INV_Misc_Bag_08" },
	{ "screenshot", "Screenshot", "SCREENSHOT" },
	-- Forever's two class buttons: pet commands and pet spells for hunters and warlocks, forms or
	-- auras for druids and paladins, stances for warriors.
	{ "classLeft", "Pet commands / forms menu", "LeftClassAction" },
	{ "classRight", "Pet spells / stances menu", "RightClassAction" },
	{ "ring", "Gamepad XIV ring", "CLICK GamepadXIVRingToggle:LeftButton" },
	{ "none", "Nothing", "NONE" },
}

-- Groups for the settings list, which draws a line between them. Spells are their own group.
ns.STICK_ACTION_GROUPS = {
	sheatheSmart = "character", sheathe = "character", view = "character", autorun = "character",
	walk = "character", sit = "character",
	target = "targeting", assist = "targeting", follow = "targeting",
	map = "windows", bags = "windows", screenshot = "windows", ring = "windows",
	classLeft = "class", classRight = "class",
	none = "none",
}

-- Spells that change the player's stance, form or bar, by class. Each is cast by name, which casts
-- the highest rank the player knows. Settings show only the player's class and spells the game
-- has; the names here are fallbacks, the game's own (localized) name is shown when it has one.
ns.STANCE_SPELLS = {
	{ "ROGUE", 1784, "Stealth" },
	{ "ROGUE", 51713, "Shadow Dance" },
	{ "DRUID", 768, "Cat Form" },
	{ "DRUID", 5215, "Prowl" },
	{ "DRUID", 5487, "Bear Form" },
	{ "DRUID", 9634, "Dire Bear Form" },
	{ "DRUID", 783, "Travel Form" },
	{ "DRUID", 1066, "Aquatic Form" },
	{ "DRUID", 24858, "Moonkin Form" },
	{ "DRUID", 33891, "Tree of Life" },
	{ "DRUID", 33943, "Flight Form" },
	{ "DRUID", 40120, "Swift Flight Form" },
	{ "WARRIOR", 2457, "Battle Stance" },
	{ "WARRIOR", 71, "Defensive Stance" },
	{ "WARRIOR", 2458, "Berserker Stance" },
	{ "PRIEST", 15473, "Shadowform" },
	{ "SHAMAN", 2645, "Ghost Wolf" },
	{ "PALADIN", 465, "Devotion Aura" },
	{ "PALADIN", 7294, "Retribution Aura" },
	{ "PALADIN", 19746, "Concentration Aura" },
	{ "PALADIN", 19876, "Shadow Resistance Aura" },
	{ "PALADIN", 19888, "Frost Resistance Aura" },
	{ "PALADIN", 19891, "Fire Resistance Aura" },
	{ "PALADIN", 20218, "Sanctity Aura" },
	{ "PALADIN", 32223, "Crusader Aura" },
	{ "HUNTER", 13165, "Aspect of the Hawk" },
	{ "HUNTER", 13163, "Aspect of the Monkey" },
	{ "HUNTER", 5118, "Aspect of the Cheetah" },
	{ "HUNTER", 13159, "Aspect of the Pack" },
	{ "HUNTER", 13161, "Aspect of the Beast" },
	{ "HUNTER", 20043, "Aspect of the Wild" },
	{ "HUNTER", 34074, "Aspect of the Viper" },
	{ "HUNTER", 61846, "Aspect of the Dragonhawk" },
	{ "DEATHKNIGHT", 48266, "Blood Presence" },
	{ "DEATHKNIGHT", 48263, "Frost Presence" },
	{ "DEATHKNIGHT", 48265, "Unholy Presence" },
	{ "WARLOCK", 47241, "Metamorphosis" },
}

-- A spell's name and icon, or nil when the game does not have it.
function ns.SpellNameAndIcon(spellID)
	if C_Spell and C_Spell.GetSpellInfo then
		local info = C_Spell.GetSpellInfo(spellID)
		if info then
			return info.name, info.iconID
		end
		return
	end
	if GetSpellInfo then
		local name, _, icon = GetSpellInfo(spellID)
		return name, icon
	end
end

-- Each stance spell of the player's class becomes an action like the others: key "spell-<id>",
-- before "Nothing", with a button that casts it. Runs once at login, out of combat, before the
-- settings window is made.
-- The game's ping key bindings (the ping wheel and each ping type) become actions too, with the
-- game's own names, before the class menus. Read from the key binding list, so a client without
-- pings adds nothing. Key "ping-<binding>".
local function AddPingActions()
	if not (GetNumBindings and GetBinding) then
		return
	end
	local at = #ns.STICK_ACTIONS
	for index, action in ipairs(ns.STICK_ACTIONS) do
		if action[1] == "classLeft" then
			at = index
			break
		end
	end
	for i = 1, GetNumBindings() do
		local command = GetBinding(i)
		if type(command) == "string" and (command == "TOGGLEPINGLISTENER" or command:match("^PING")) then
			local label = _G["BINDING_NAME_" .. command]
			if label then
				local key = "ping-" .. command:lower()
				tinsert(ns.STICK_ACTIONS, at, { key, label, command })
				ns.STICK_ACTION_GROUPS[key] = "ping"
				at = at + 1
			end
		end
	end
end

function ns.CreateSpellActions()
	AddPingActions()
	local playerClass = UnitClassBase("player")
	for _, spell in ipairs(ns.STANCE_SPELLS) do
		local name, icon = ns.SpellNameAndIcon(spell[2])
		if spell[1] == playerClass and name then
			local buttonName = "GamepadXIVSpell" .. spell[2]
			tinsert(ns.STICK_ACTIONS, #ns.STICK_ACTIONS, { "spell-" .. spell[2], name, "CLICK " .. buttonName .. ":LeftButton", spell[2], icon })
			local button = CreateFrame("Button", buttonName, UIParent, "SecureActionButtonTemplate")
			button:RegisterForClicks("AnyDown", "AnyUp")
			button:SetAttribute("useOnKeyDown", true)
			button:SetAttribute("type", "spell")
			button:SetAttribute("spell", name) -- by name: the highest rank the player knows
			button:Hide()
		end
	end
end

-- The labels under Forever's two class buttons. Forever's own always read L1 + L2 and R1 + R2, so
-- they are faded out and these show the buttons the settings give each menu instead.
local classMenuHints = {}

-- The buttons set to open the addon's ring, from the settings: single stick presses first, then the
-- combinations. Each is a list of keys pressed together; empty when no button opens it.
function ns.RingKeys()
	local db = ns.db
	local list = {}
	for _, setting in ipairs({
		{ "l3Action", { "PADLSTICK" } }, { "r3Action", { "PADRSTICK" } },
		{ "r1R3Action", { "PADRSHOULDER", "PADRSTICK" } }, { "l1R3Action", { "PADLSHOULDER", "PADRSTICK" } },
		{ "r1L3Action", { "PADRSHOULDER", "PADLSTICK" } }, { "l1R1Action", { "PADLSHOULDER", "PADRSHOULDER" } },
		{ "l1StickUpAction", { "PADLSHOULDER", "PADLSTICKUP" } },
	}) do
		if db[setting[1]] == "ring" then
			tinsert(list, setting[2])
		end
	end
	return list
end

-- The keys that open a class menu, from the settings: a single stick press first, then the L1 / R1
-- combinations, and Forever's own trigger chord when nothing else is set.
local function ClassMenuKeys(menu)
	local db = ns.db
	if db.l3Action == menu then
		return { "PADLSTICK" }
	elseif db.r3Action == menu then
		return { "PADRSTICK" }
	elseif db.l1R3Action == menu then
		return { "PADLSHOULDER", "PADRSTICK" }
	elseif db.r1L3Action == menu then
		return { "PADRSHOULDER", "PADLSTICK" }
	elseif db.l1StickUpAction == menu then
		return { "PADLSHOULDER", "PADLSTICKUP" }
	elseif menu == "classLeft" then
		return { "PADLSHOULDER", "PADLTRIGGER" }
	end
	return { "PADRSHOULDER", "PADRTRIGGER" }
end

-- The pet menu buttons stay visible on Forever's hidden bar, unless the player hides them. Their
-- chords open the menus either way. Out of combat only, since they are Forever's protected buttons.
-- Each side has its own setting: the left one is the pet commands menu, the right one pet spells.
-- "show", "hide", or "disable": hidden, and L1 / R1 with that trigger target enemies again.
local PET_SIDES = {
	classLeft = { setting = "petLeftButton", frames = { "LeftClassAction", "LeftInputPrompt" } },
	classRight = { setting = "petRightButton", frames = { "RightClassAction", "RightInputPrompt" } },
}
local petButtonsShown = {}

local function PetButtonShown(menu)
	return (ns.db[PET_SIDES[menu].setting] or "show") == "show"
end

function ns.ApplyPetButtons()
	if InCombatLockdown() or not (driver and driver:GetAttribute("fc-petChords") == 1) then
		return
	end
	local pageUnit = GamepadMainActionBarFrame and GamepadMainActionBarFrame.PageUnit
	for menu, side in pairs(PET_SIDES) do
		local shown = PetButtonShown(menu)
		if shown ~= petButtonsShown[menu] then
			petButtonsShown[menu] = shown
			ns.Trail(menu .. " pet button " .. (shown and "shown" or "hidden"))
			for _, key in ipairs(side.frames) do
				local button = pageUnit and pageUnit[key]
				if button then
					button:SetIgnoreParentAlpha(shown)
				end
			end
			if classMenuHints[menu] then
				classMenuHints[menu]:SetShown(shown)
			end
		end
	end
end

function ns.UpdateClassMenuHints()
	for menu, hint in pairs(classMenuHints) do
		local parts = {}
		for _, key in ipairs(ClassMenuKeys(menu)) do
			tinsert(parts, ns.ButtonText("{" .. key .. "}", 24))
		end
		hint.text:SetText(table.concat(parts, "  |cffffffff+|r  "))
	end
end

function ns.CreateClassMenuHints(pageUnit)
	for key, menu in pairs({ LeftInputPrompt = "classLeft", RightInputPrompt = "classRight" }) do
		local prompt = pageUnit and pageUnit[key]
		if prompt then
			-- A child of Forever's prompt shows and hides with it; only Forever's own icons are faded.
			prompt:SetAlpha(0)
			local hint = CreateFrame("Frame", nil, prompt)
			hint:SetIgnoreParentAlpha(true)
			hint:SetSize(1, 1)
			hint:SetPoint("CENTER")
			hint.text = hint:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
			hint.text:SetPoint("CENTER")
			hint:SetShown(PetButtonShown(menu))
			classMenuHints[menu] = hint
		end
	end
	ns.UpdateClassMenuHints()
	if InputDeviceIconSetManager then
		InputDeviceIconSetManager:RegisterActiveInputDeviceIconSetUpdatedCallback(ns.UpdateClassMenuHints, classMenuHints)
	end
end

-- Forever's party frames show its own party select button (L1) in a prompt below the members. Party
-- selection is on D-pad up / down here, so while the crossbar is in use Forever's prompt is faded
-- and this addon draws its own in its place: D-pad up / down, below or above the party, or none.
local partyPrompt

local function FindPartyPrompt()
	if not CompactPartyFrame then
		return
	end
	for _, child in ipairs({ CompactPartyFrame:GetChildren() }) do
		if child.promptContainerFrame then
			return child.promptContainerFrame
		end
	end
end

-- A copy of one of Forever's textures, read only, for the same slot look.
local function CopyArt(target, source)
	if not source then
		return
	end
	local atlas = source.GetAtlas and source:GetAtlas()
	if atlas then
		target:SetAtlas(atlas)
	elseif source.GetTexture and source:GetTexture() then
		target:SetTexture(source:GetTexture())
	end
	if source.GetVertexColor then
		target:SetVertexColor(source:GetVertexColor())
	end
	target:SetAlpha(source:GetAlpha() or 1)
end

function ns.UpdatePartyPrompt()
	if not partyPrompt then
		local container = FindPartyPrompt()
		if not container then
			return
		end
		-- A child of Forever's prompt shows and hides with it, but keeps its own alpha.
		local prompt = CreateFrame("Frame", nil, container)
		prompt:SetIgnoreParentAlpha(true)
		prompt.slot = prompt:CreateTexture(nil, "BACKGROUND")
		prompt.slot:SetAllPoints()
		prompt.border = prompt:CreateTexture(nil, "BORDER")
		prompt.border:SetAllPoints()
		CopyArt(prompt.slot, container.backgroundSlot)
		CopyArt(prompt.border, container.backgroundBorder)
		prompt.text = prompt:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		prompt.text:SetPoint("CENTER")
		partyPrompt = { container = container, prompt = prompt }
		if InputDeviceIconSetManager then
			InputDeviceIconSetManager:RegisterActiveInputDeviceIconSetUpdatedCallback(ns.UpdatePartyPrompt, partyPrompt)
		end
	end
	local container, prompt = partyPrompt.container, partyPrompt.prompt
	local active = ns.IsActive() and true or false
	local where = ns.db.partyPrompt or "bottom"
	local alpha = active and 0 or 1
	if container:GetAlpha() ~= alpha then
		ns.Trail("party prompt SetAlpha " .. alpha)
		container:SetAlpha(alpha)
	end
	prompt:SetShown(active and where ~= "off")
	prompt.text:SetText(ns.ButtonText("{PADDUP}{PADDDOWN}", 14))
	prompt:ClearAllPoints()
	if where == "top" then
		local width, height = container:GetSize()
		prompt:SetSize(width, height)
		local offset = (container:GetLeft() and CompactPartyFrame:GetLeft()) and (container:GetLeft() - CompactPartyFrame:GetLeft()) or 0
		prompt:SetPoint("BOTTOMLEFT", CompactPartyFrame, "TOPLEFT", offset, 4)
	else
		prompt:SetAllPoints(container)
	end
end

do
	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
	watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
	-- Blizzard builds the party frames on its own roster update, which may run after this one.
	watcher:SetScript("OnEvent", function()
		C_Timer.After(0.5, ns.UpdatePartyPrompt)
	end)
end

local function StickBinding(key, fallback)
	for _, action in ipairs(ns.STICK_ACTIONS) do
		if action[1] == key then
			if action[1] == "classLeft" or action[1] == "classRight" then
				local pageUnit = GamepadMainActionBarFrame and GamepadMainActionBarFrame.PageUnit
				local button = pageUnit and pageUnit[action[3]]
				return button and button:GetName() and ("CLICK " .. button:GetName() .. ":LeftButton") or "NONE"
			end
			return action[3]
		end
	end
	return fallback
end

function ns.Sync()
	if not driver then
		return
	end
	ns.Trail("sync")
	if InCombatLockdown() then
		ns.syncPending = true
		return
	end
	ns.syncPending = false

	ns.ApplyLayout()
	ns.UpdatePartyPrompt()
	if ns.softUnit and ns.softUnit ~= "" and ns.root then
		ns.ShowSoftTarget(ns.softUnit) -- a changed highlight setting shows at once
	end
	if ns.UpdateTargetHighlight then
		ns.UpdateTargetHighlight()
	end

	local db = ns.db
	local on = db.enabled and ns.IsGamepadUI() and not ns.foreverEditorOpen

	driver:SetAttribute("fc-priority", db.priorityBindings and 1 or 0)
	driver:SetAttribute("fc-hide-WL", db.showTopLeft ~= "always" and 1 or 0)
	driver:SetAttribute("fc-hide-WR", db.showTopRight ~= "always" and 1 or 0)
	-- Off: a double tap is two plain presses, for players who never use the top bars.
	driver:SetAttribute("fc-noDouble-L", db.showTopLeft == "off" and 1 or 0)
	driver:SetAttribute("fc-noDouble-R", db.showTopRight == "off" and 1 or 0)
	driver:SetAttribute("fc-dpadParty", db.dpadParty)
	driver:SetAttribute("fc-dpadTarget", db.dpadTarget)
	driver:SetAttribute("fc-dpadTargetCombat", db.dpadTargetCombat)
	driver:SetAttribute("fc-crossEnemy", CROSS_ENEMY[db.crossEnemy])
	driver:SetAttribute("fc-airClear", db.airCircle == "clear" and 1 or 0)
	driver:SetAttribute("fc-petOff-L", db.petLeftButton == "disable" and 1 or 0)
	driver:SetAttribute("fc-petOff-R", db.petRightButton == "disable" and 1 or 0)
	driver:SetAttribute("fc-classMenuOff", db.classMenuChord == "disable" and 1 or 0)
	driver:SetAttribute("fc-groundSelf", db.groundUnderCharacter and 1 or 0)
	driver:SetAttribute("fc-skipSelf", db.skipSelf and 1 or 0)
	driver:SetAttribute("fc-skipPets", db.skipPets and 1 or 0)
	local l3 = StickBinding(db.l3Action, "TOGGLESHEATH")
	driver:SetAttribute("ctx-PADLSTICK-target", l3)
	driver:SetAttribute("ctx-PADLSTICK-notarget", l3)
	driver:SetAttribute("fc-r3", StickBinding(db.r3Action, "CLICK GamepadXIVView:LeftButton"))
	driver:SetAttribute("fc-l1StickUp", StickBinding(db.l1StickUpAction, "TOGGLEAUTORUN"))
	-- The default is left to the snippet, which picks sheathe, dismount or descend.
	driver:SetAttribute("fc-l1r1", db.l1R1Action ~= "sheatheSmart" and StickBinding(db.l1R1Action, "NONE") or nil)
	-- A class menu is named too, so the snippet can fall back when the class has no such menu.
	local CLASS_MENU = { classLeft = "L", classRight = "R" }
	driver:SetAttribute("fc-l1r3", StickBinding(db.l1R3Action, "NONE"))
	driver:SetAttribute("fc-l1r3-menu", CLASS_MENU[db.l1R3Action])
	driver:SetAttribute("fc-r1l3", StickBinding(db.r1L3Action, "NONE"))
	driver:SetAttribute("fc-r1l3-menu", CLASS_MENU[db.r1L3Action])
	driver:SetAttribute("fc-r1r3", StickBinding(db.r1R3Action, "CLICK GamepadXIVRingToggle:LeftButton"))
	-- The R1 tap: two pairs of a bottom set and a top set.
	driver:SetAttribute("fc-r1Tap", db.r1Tap and 1 or 0)
	driver:SetAttribute("fc-tapTop", db.r1TapTop and 1 or 0)
	driver:SetAttribute("fc-tapA-bottom", db.r1TapBottomA)
	driver:SetAttribute("fc-tapA-top", db.r1TapTopA)
	driver:SetAttribute("fc-tapB-bottom", db.r1TapBottomB)
	driver:SetAttribute("fc-tapB-top", db.r1TapTopB)
	driver:SetAttribute("fc-tapA-combo", db.r1TapComboA or 0)
	driver:SetAttribute("fc-tapB-combo", db.r1TapComboB or 0)
	driver:SetAttribute("fc-ringRelease", db.ringReleaseToUse and 1 or 0)
	ns.UpdateClassMenuHints()
	ns.ApplyPetButtons()
	local answeredPopup, answeredPopupIndex = GetAnsweredPopup()
	driver:SetAttribute("fc-answeredPopup", answeredPopupIndex or 0)
	for _, key in ipairs(POPUP_KEY_ORDER) do
		local button = GetPopupButton(answeredPopup, key)
		driver:SetAttribute("popup-" .. key, button and button:GetName() or nil)
	end
	driver:SetAttribute("fc-l1Party", db.l1DoubleTapParty and 1 or 0)
	local partyTargeting = driver:GetAttribute("fc-partyTargeting")
	driver:SetAttribute("fc-partyTargeting", db.partyTargeting)
	if partyTargeting and partyTargeting ~= db.partyTargeting then
		driver:SetAttribute("fc-cycle-party", nil)
		driver:SetAttribute("fc-cycle-raid", nil)
		driver:SetAttribute("fc-cycleFrame", nil)
		driver:SetAttribute("fc-cycleUnit", nil)
		SecureHandlerExecute(driver, [[ self:RunAttribute("SetSoft", "") ]])
	end
	driver:SetAttribute("fc-wReturn", db.wxhbReturn and 1 or 0)
	if driver:GetAttribute("fc-triggerMode") ~= db.triggerMode then
		driver:SetAttribute("fc-triggerMode", db.triggerMode)
		driver:SetAttribute("fc-latch", "")
		driver:SetAttribute("fc-consumed", "")
		driver:SetAttribute("fc-w", "")
		driver:SetAttribute("fc-first", "")
		driver:SetAttribute("fc-layer", "BASE")
	end
	driver:SetAttribute("fc-formset-0", db.set)
	for form = 1, ns.NUM_FORMS do
		-- While a quick swap shows pair B, the saved set is the form's own set to come back to.
		if driver:GetAttribute("fc-formhome-" .. form) then
			driver:SetAttribute("fc-formhome-" .. form, db["formSet" .. form])
		else
			driver:SetAttribute("fc-formset-" .. form, db["formSet" .. form])
		end
	end
	driver:SetAttribute("fc-formLink", db.formsChangeBar and 1 or 0)
	driver:SetAttribute("fc-dim", db.dimAlpha)
	driver:SetAttribute("fc-idleAlpha", db.idleAlpha)
	driver:SetAttribute("fc-tapTicks", db.doubleTapTicks)
	driver:SetAttribute("fc-side-WL", db.sideWL)
	driver:SetAttribute("fc-side-WR", db.sideWR)
	driver:SetAttribute("fc-side-LR", db.sideLR)
	driver:SetAttribute("fc-side-RL", db.sideRL)
	driver:SetAttribute("fc-comboTop", db.comboFollowsTop and 1 or 0)
	driver:SetAttribute("fc-off", on and 0 or 1)
	-- Forever's page can change in its own editor, so this is read again each time.
	local mainPageUnit = GamepadMainActionBarFrame and GamepadMainActionBarFrame.PageUnit
	driver:SetAttribute("fc-page", mainPageUnit and mainPageUnit:GetCurrentPage() or nil)
	UpdateFlyouts()
	UpdateCameraCVars()
	RefreshUnitFrameRefs()
	SecureHandlerExecute(driver, [[
		self:RunAttribute("UpdateForm")
		self:RunAttribute("UpdateYield")
	]])
	UpdatePopupHint()
end
