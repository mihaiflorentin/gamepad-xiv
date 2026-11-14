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
	if not pcall(C_CVar.SetTempCVar, name, value) then
		ns.Print("Could not set", name)
	end
end

local function RemoveTemp(name)
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
			if not pcall(C_CVar.SetCVar, name, value) then
				ns.Print("Could not set", name)
			end
			SetTemp(name, value)
		else
			RemoveTemp(name)
			if saved[name] then
				pcall(C_CVar.SetCVar, name, saved[name])
			end
			saved[name] = nil
		end
	end
	-- Makes the client read the changed input settings now, instead of at the next start.
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
-- turned off while one is open.
local function SetStickButtons(on)
	if ns.db.savedCVars.GamePadStickAxisButtons == nil then
		return -- the addon is not running its input settings
	end
	local value = on and INPUT_CVARS.GamePadStickAxisButtons or "0"
	pcall(C_CVar.SetCVar, "GamePadStickAxisButtons", value)
	SetTemp("GamePadStickAxisButtons", value)
	pcall(C_GamePad.ApplyConfigs)
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

local function SetupBaseBindings()
	local interact = ForeverButtonBinding(1, "INTERACTTARGET")
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
	driver:SetAttribute("base-PAD1", interact)
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
				ns.PlayLog("hold to walk: on")
			elseif not down then
				RemoveTemp("GamePadRunThreshold")
				ns.PlayLog("hold to walk: off")
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
	button:SetAttribute("type", "target")
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
local POPUP_KEY_ORDER = { "PAD1", "PAD2", "PAD3", "PAD4" }

-- The group finder's invite (a group from Looking For Group invites you) is a window of its own,
-- not one of the four popups; it is number 5 here.
local INVITE_POPUP = 5
local INVITE_BUTTONS = { PAD1 = "LFGInvitePopupAcceptButton", PAD2 = "LFGInvitePopupDeclineButton" }

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
local function UpdatePopupHint()
	local index = driver:GetAttribute("fc-answeredPopup") or 0
	local popup = PopupByIndex(index)
	if not popup or not popup:IsShown() or not ns.IsActive() then
		if popupHint then
			popupHint:Hide()
		end
		return
	end
	if not popupHint then
		popupHint = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	end
	local parts = {}
	for _, key in ipairs(POPUP_KEY_ORDER) do
		local button = GetPopupButton(popup, key)
		if button then
			tinsert(parts, ns.ButtonText("{" .. key .. "}", 16) .. " " .. (button:GetText() or ""))
		end
	end
	popupHint:SetText(table.concat(parts, "    "))
	popupHint:ClearAllPoints()
	popupHint:SetPoint("TOP", popup, "BOTTOM", 0, -8)
	popupHint:Show()
end

local function CreateCycle(name, step, raidOnly)
	local button = CreateSecureButton(name, S.CyclePreClick, "PreClick")
	button:RegisterForClicks("AnyDown")
	button:SetAttribute("type", "target")
	button:SetAttribute("fc-step", step)
	button:SetAttribute("fc-raidOnly", raidOnly and 1 or 0)
	-- Play log: what each press picked, to find presses that seem to do nothing.
	button:HookScript("OnClick", function(self)
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
	button:RegisterForClicks("AnyDown")
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

local function CreatePlainButton(name, onClick)
	local button = CreateFrame("Button", name, UIParent)
	button:RegisterForClicks("AnyDown")
	button:SetScript("OnClick", onClick)
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
-- In combat Back is Forever's own, for loot rolls and popups.
local BACK_POPUPS = { "GamepadGroupLootRollFrame", "GroupLootFrame1", "GroupLootFrame2", "GroupLootFrame3", "GroupLootFrame4",
	"StaticPopup1", "StaticPopup2", "StaticPopup3", "StaticPopup4", "LFGDungeonReadyPopup", "LFGDungeonReadyDialog",
	"LFGInvitePopup", "LFGListInviteDialog", "LFGListApplicationDialog", "ReadyCheckFrame", "RolePollPopup", "PVPReadyDialog" }

local function CreateBackChat()
	local visited = {}
	-- After chat, the next Back is Forever's own, which lets go of the windows: the end of the cycle.
	local afterChat = false
	local function BackAction()
		local manager = GamepadMode and GamepadMode.FrameControlsManager
		if not manager then
			return ""
		end
		if ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() then
			wipe(visited)
			afterChat = manager.isUIFocused and true or false
			return ""
		end
		-- Forever shows loot rolls and popups without focus; its Back is what focuses them.
		for _, name in ipairs(BACK_POPUPS) do
			local frame = _G[name]
			if frame and frame.IsVisible and frame:IsVisible() then
				wipe(visited)
				return ""
			end
		end
		local shown = manager.shownFrames or {}
		if not manager.isUIFocused then
			wipe(visited)
			afterChat = false
			return #shown == 0 and "chat" or ""
		end
		if afterChat then
			return ""
		end
		local focused = manager.focusedFrame
		if not focused or not tContains(shown, focused) then
			return ""
		end
		visited[focused] = true
		for _, frame in ipairs(shown) do
			if not visited[frame] then
				return "next"
			end
		end
		return "chat"
	end
	local function Set(value)
		if driver:GetAttribute("fc-backAction") ~= value then
			ns.PlayLog("Back:", value == "" and "Forever's" or value)
			driver:SetAttribute("fc-backAction", value)
			if ns.IsActive() then
				SecureHandlerExecute(driver, [[ self:RunAttribute("ApplyLayer") ]])
			end
		end
	end
	local watcher = CreateFrame("Frame")
	-- Bindings freeze in combat; they can still change while this event runs.
	watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
	watcher:SetScript("OnEvent", function()
		wipe(visited)
		afterChat = false
		Set("")
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
	local function HoldLink(link)
		if type(link) ~= "string" or not IsModifiedClick("CHATLINK") then
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
		if not pendingLink then
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
		if button ~= "LeftButton" or not IsShiftKeyDown() then
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

local function GetActionName(slot)
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
	clearPanel:SetSize(420, 118)
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
	clearPanel.moveButton, clearPanel.moveText = CreatePrompt(-190, "Move")
	clearPanel.confirmButton, clearPanel.confirmText = CreatePrompt(-65, "Remove")
	clearPanel.cancelButton = CreatePrompt(70, "Cancel")
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
	if stage == 0 then
		clearSlot = nil
		clearPanel:Hide()
		return
	end
	SetPromptAtlas(clearPanel.moveButton, "PAD1")
	SetPromptAtlas(clearPanel.confirmButton, "PAD3")
	SetPromptAtlas(clearPanel.cancelButton, "PAD2")
	local choosing = stage == 2
	clearPanel.moveButton:SetShown(choosing)
	clearPanel.moveText:SetShown(choosing)
	clearPanel.confirmButton:SetShown(choosing)
	clearPanel.confirmText:SetShown(choosing)
	clearPanel.icon:SetShown(stage ~= 1)
	if clearSlot then
		clearPanel.icon:SetTexture(C_ActionBar.GetActionTexture(clearSlot))
	end
	local name = clearSlot and GetActionName(clearSlot) or ""
	if stage == 1 then
		clearPanel.text:SetText(ns.ButtonText("Choose the ability to move or remove.\nHold {PADLTRIGGER} or {PADRTRIGGER}, or double tap for the top row, then press its button.", 18))
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
	if stage == 3 then
		MoveAction(clearSlot, slot)
		SecureHandlerExecute(driver, [[ self:RunAttribute("SetClear", 0) ]])
	elseif C_ActionBar.HasAction(slot) then
		clearSlot = slot
		SecureHandlerExecute(driver, [[ self:RunAttribute("SetClear", 2) ]])
	else
		ns.Print("That slot is empty.")
	end
end

local function StartMove()
	if clearSlot and not InCombatLockdown() and driver:GetAttribute("fc-clear") == 2 then
		SecureHandlerExecute(driver, [[ self:RunAttribute("SetClear", 3) ]])
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
	driver:SetAttribute("SetSoft", S.SetSoft)
	driver:SetAttribute("ReturnToGroupUnit", S.ReturnToGroupUnit)
	driver:SetAttribute("CycleGroup", S.CycleGroup)
	driver:SetAttribute("PartyCycleUnit", S.PartyCycleUnit)
	driver:SetAttribute("SelectGroupUnit", S.SelectGroupUnit)
	driver:SetAttribute("MoveFrameCursor", S.MoveFrameCursor)
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
		-- Temp CVars have no combat restriction, so Forever gets its inputs back in vehicles too.
		if ns.cvarsApplied ~= not yielded then
			ns.cvarsApplied = not yielded
			ApplyTempCVars(not yielded)
			ns.PlayLog("yield:", yielded and "on" or "off")
			if yielded then
				RemoveTemp("GamePadRunThreshold")
				SetCameraLock(false)
			end
		end
	end

	SetupDriverData()
	SetupBaseBindings()
	CreateHelperButtons()
	ns.CreateSpellActions()
	CreateZoomWatcher()
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
	CreateSecureButton("GamepadXIVSoftCancel", S.SoftCancelClick)

	for i = 1, ns.NUM_SLOTS do
		for _, row in ipairs(ns.ROWS) do
			-- The keys press these instead of the visible slots: ActionBarButtonTemplate always casts
			-- on key up, which is too late for the soft target and loses a cast if the trigger is released first.
			local cast = CreateSecureButton("GamepadXIVCast" .. row .. i)
			cast:SetAttribute("type", "action")
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
		for _, key in ipairs({ "LeftClassAction", "RightClassAction", "LeftInputPrompt", "RightInputPrompt" }) do
			if pageUnit[key] then
				pageUnit[key]:SetIgnoreParentAlpha(true)
			end
		end
	end

	-- L1 + R3 and R1 + L3 click Forever's two class buttons, which open its pet menus for hunters and
	-- warlocks, and its form, aura or stance menus for druids, paladins and warriors. Those buttons
	-- hide when the class has no menu, and the binding then keeps L3's own action.
	for side, key in pairs({ L = "LeftClassAction", R = "RightClassAction" }) do
		local button = pageUnit and pageUnit[key]
		if button and button:GetName() then
			SecureHandlerSetFrameRef(driver, "classMenu" .. side, button)
			driver:SetAttribute("classMenu-" .. side, button:GetName())
		end
	end
	-- The open menu is watched through the secure wrapper, which leaves Forever's frames untainted.
	local popupCount = 0
	for _, popup in ipairs({ GamepadPetActionFlyout, GamepadPetSpellFlyout, GamepadSpellFlyout }) do
		if popup and popup:IsProtected() then
			popupCount = popupCount + 1
			SecureHandlerSetFrameRef(driver, "classPopup" .. popupCount, popup)
			SecureHandlerWrapScript(popup, "OnShow", driver, S.ClassPopupShown)
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

	for i = 1, ns.NUM_SLOTS do
		local button = CreateSecureButton("GamepadXIVSet" .. i, S.SetClick)
		button:SetAttribute("fc-setIndex", ns.SET_BY_KEY[i])
		button:SetAttribute("clickbutton", pageButton)
	end

	RegisterStateDriver(driver, "fctarget", "[@target,exists] 1; 0")
	RegisterStateDriver(driver, "fcmounted", "[mounted] 1; 0")
	RegisterStateDriver(driver, "fccombat", "[combat] 1; 0")
	RegisterStateDriver(driver, "fcmove", "[flying][swimming] 1; 0")
	RegisterStateDriver(driver, "fcform", ns.FormConditions())
	RegisterStateDriver(driver, "fcvehicle", "[overridebar][vehicleui][possessbar] 1; 0")
	RegisterStateDriver(driver, "fcraid", "[group:raid] 1; 0")

	-- Forever's window bindings are priority overrides, so they win while a window is focused.
	-- Closing one writes empty overrides back, so bindings are reasserted afterwards.
	local manager = GamepadSharedUtility and GamepadSharedUtility.InputBindingManager
	if manager then
		hooksecurefunc(manager, "RemoveSet", function() ns.Sync() end)
		hooksecurefunc(manager, "ClearBindings", function() ns.Sync() end)
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
		lootFrame:HookScript("OnShow", function()
			lootHint:SetText(ns.ButtonMarkup("PADBACK", "Back", 28) .. " Roll on loot")
			lootHint:SetShown(ns.IsActive())
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
	if GamepadMainActionBarFrame then
		GamepadMainActionBarFrame:SetAlpha(foreverShown and 1 or 0)
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
			classMenuHints[menu] = hint
		end
	end
	ns.UpdateClassMenuHints()
	if InputDeviceIconSetManager then
		InputDeviceIconSetManager:RegisterActiveInputDeviceIconSetUpdatedCallback(ns.UpdateClassMenuHints, classMenuHints)
	end
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
	if InCombatLockdown() then
		ns.syncPending = true
		return
	end
	ns.syncPending = false

	ns.ApplyLayout()
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
	driver:SetAttribute("fc-ringRelease", db.ringReleaseToUse and 1 or 0)
	ns.UpdateClassMenuHints()
	local answeredPopup, answeredPopupIndex = GetAnsweredPopup()
	driver:SetAttribute("fc-answeredPopup", answeredPopupIndex or 0)
	for _, key in ipairs(POPUP_KEY_ORDER) do
		local button = GetPopupButton(answeredPopup, key)
		driver:SetAttribute("popup-" .. key, button and button:GetName() or nil)
	end
	local partyTargeting = driver:GetAttribute("fc-partyTargeting")
	driver:SetAttribute("fc-partyTargeting", db.partyTargeting)
	if partyTargeting and partyTargeting ~= db.partyTargeting then
		driver:SetAttribute("fc-cycle-party", nil)
		driver:SetAttribute("fc-cycle-raid", nil)
		driver:SetAttribute("fc-cycleFrame", nil)
		driver:SetAttribute("fc-cycleUnit", nil)
		SecureHandlerExecute(driver, [[ self:RunAttribute("SetSoft", "") ]])
	end
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
		driver:SetAttribute("fc-formset-" .. form, db["formSet" .. form])
	end
	driver:SetAttribute("fc-formLink", db.formsChangeBar and 1 or 0)
	driver:SetAttribute("fc-dim", db.dimAlpha)
	driver:SetAttribute("fc-tapTicks", db.doubleTapTicks)
	driver:SetAttribute("fc-side-WL", db.sideWL)
	driver:SetAttribute("fc-side-WR", db.sideWR)
	driver:SetAttribute("fc-side-LR", db.sideLR)
	driver:SetAttribute("fc-side-RL", db.sideRL)
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
