local _, ns = ...
local S = ns.Snippets

local driver

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
			elseif not down then
				RemoveTemp("GamePadRunThreshold")
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

local function CreateCycle(name, step, raidOnly)
	local button = CreateSecureButton(name, S.CyclePreClick, "PreClick")
	button:RegisterForClicks("AnyDown")
	button:SetAttribute("fc-step", step)
	button:SetAttribute("fc-raidOnly", raidOnly and 1 or 0)
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
	for _, frame in ipairs(CompactPartyFrame and CompactPartyFrame.memberUnitFrames or {}) do
		Add(frame)
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

	CreatePlainButton("GamepadXIVCursor", function()
		SetGamePadCursorControl(not IsGamePadCursorControlEnabled())
	end)
end

-- Controller state. Passing no device reads the combined one; some setups only answer for the active one.
local function GetPadState()
	return C_GamePad.GetDeviceMappedState() or C_GamePad.GetDeviceMappedState(C_GamePad.GetActiveDeviceID())
end

-- A hidden texture, only for asking the client which cursor a unit has.
local probeTexture

-- Right stick vertical value, by the stick's configured name or else by its raw axis.
local function GetCameraStickY(state)
	if not state then
		return 0
	end
	for i = 1, state.stickCount do
		local name = C_GamePad.StickIndexToConfigName(i - 1)
		if name == "Camera" or name == "Look" then
			return state.sticks[i].y
		end
	end
	for i = 1, state.axisCount do
		if C_GamePad.AxisIndexToConfigName(i - 1) == "RStickY" then
			return state.axes[i]
		end
	end
	return 0
end

-- L1 + right stick zooms. Rotation is frozen while L1 is held, so the stick only zooms.
local function CreateZoomWatcher()
	local watcher = CreateFrame("Frame")
	local DEAD_ZONE = 0.2
	local ZOOM_PER_SECOND = 15
	local MIN_STEP = 0.25
	local pending = 0
	local frozen = false

	local function SetFrozen(freeze)
		if frozen == freeze then
			return
		end
		frozen = freeze
		if freeze then
			SetTemp("GamePadCameraYawSpeed", "0")
			SetTemp("GamePadCameraPitchSpeed", "0")
		else
			RemoveTemp("GamePadCameraYawSpeed")
			RemoveTemp("GamePadCameraPitchSpeed")
		end
	end

	watcher:SetScript("OnUpdate", function(_, elapsed)
		local active = ns.l1Held and ns.IsActive()
		SetFrozen(active and true or false)
		if not active then
			pending = 0
			return
		end
		local y = GetCameraStickY(GetPadState())
		if math.abs(y) > DEAD_ZONE then
			pending = pending + ZOOM_PER_SECOND * y * elapsed
		end
		if pending >= MIN_STEP then
			CameraZoomIn(pending)
			pending = 0
		elseif pending <= -MIN_STEP then
			CameraZoomOut(-pending)
			pending = 0
		end
	end)
end

function ns.PrintInputCVars(report)
	for name in pairs(INPUT_CVARS) do
		report(name, "=", GetCVar(name))
	end
end

-- /fc debug: what the game reports for the controls that cannot be checked outside the client.
-- The lines also go to the saved variables, so a /reload makes them readable from the file.
function ns.PrintDebug()
	ns.db.debugLog = {}
	local function Report(...)
		ns.Print(...)
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
		Report("L1 layer:", ns.l1Held, "stick:", format("%.2f", GetCameraStickY(GetPadState())),
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

local function SetupDriverData()
	for i, key in ipairs(ns.KEYS) do
		driver:SetAttribute("key" .. i, key)
	end
	for side = 1, ns.NUM_SETS * 2 do
		for i = 1, ns.NUM_SLOTS do
			driver:SetAttribute("slot-" .. side .. "-" .. i, ns.sideSlots[side][i])
		end
	end
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
	for side = 1, ns.NUM_SETS * 2 do
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
		flyoutPanel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
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
	flyoutPanel.cancel:SetText("B / Circle: cancel")
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
	clearPanel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
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
		clearPanel.text:SetText("Choose the ability to move or remove.\nHold L2 or R2, or double tap for the top row, then press its button.")
	elseif stage == 2 then
		clearPanel.text:SetText("What should happen to this ability?\n" .. name)
	else
		clearPanel.text:SetText("Move " .. name .. " where?\nChoose the slot. R1 + a button changes the set. An ability already there swaps.")
	end
	clearPanel:Show()
end

function ns.StartClear()
	if InCombatLockdown() then
		ns.Print("Abilities cannot be moved or removed in combat.")
	elseif not ns.IsActive() or ns.editing then
		ns.Print("This needs the layout active and edit mode closed.")
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

function ns.CreateInput()
	driver = CreateFrame("Frame", "GamepadXIVDriver", UIParent, "SecureHandlerStateTemplate")

	driver:SetAttribute("ApplyLayer", S.ApplyLayer)
	driver:SetAttribute("BindAll", S.BindAll)
	driver:SetAttribute("UpdateTargetBindings", S.UpdateTargetBindings)
	driver:SetAttribute("UpdateYield", S.UpdateYield)
	driver:SetAttribute("OnTrigger", S.OnTrigger)
	driver:SetAttribute("SetSoft", S.SetSoft)
	driver:SetAttribute("CycleGroup", S.CycleGroup)
	driver:SetAttribute("MoveFrameCursor", S.MoveFrameCursor)
	driver:SetAttribute("OpenFlyout", S.OpenFlyout)
	driver:SetAttribute("CloseFlyout", S.CloseFlyout)
	driver:SetAttribute("SetClear", S.SetClear)
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
	driver.OnEditEnded = function() ns.OnEditEnded() end
	driver.OnFlyoutChanged = function(_, flyoutID) ShowFlyoutPanel(flyoutID) end
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
			if yielded then
				RemoveTemp("GamePadRunThreshold")
				SetCameraLock(false)
			end
		end
	end

	SetupDriverData()
	SetupBaseBindings()
	CreateHelperButtons()
	CreateZoomWatcher()
	HookInteractPrompt()
	CreateInteractHud()

	CreateTrigger("GamepadXIVL2", "L")
	CreateTrigger("GamepadXIVR2", "R")
	CreateL1()
	CreateSecureButton("GamepadXIVR1", S.R1Click)
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

	for n = 1, #FLYOUT_KEYS do
		local pick = CreateSecureButton("GamepadXIVFlyoutPick" .. n)
		pick:SetAttribute("type", "spell")
		SecureHandlerSetFrameRef(driver, "flyoutPick" .. n, pick)
		SecureHandlerWrapScript(pick, "OnClick", pick, S.FlyoutPickPre, S.FlyoutPickPost)
	end
	CreateSecureButton("GamepadXIVFlyoutCancel", S.FlyoutCancelClick)
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
	RegisterStateDriver(driver, "fcform", "[bonusbar:1] 1; [bonusbar:2] 2; [bonusbar:3] 3; [bonusbar:4] 4; 0")
	RegisterStateDriver(driver, "fcvehicle", "[overridebar][vehicleui][possessbar] 1; 0")
	RegisterStateDriver(driver, "fcraid", "[group:raid] 1; 0")

	-- Forever's window bindings are priority overrides, so they win while a window is focused.
	-- Closing one writes empty overrides back, so bindings are reasserted afterwards.
	local manager = GamepadSharedUtility and GamepadSharedUtility.InputBindingManager
	if manager then
		hooksecurefunc(manager, "RemoveSet", function() ns.Sync() end)
		hooksecurefunc(manager, "ClearBindings", function() ns.Sync() end)
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
	events:SetScript("OnEvent", function(_, event, cvar)
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

	local db = ns.db
	local on = db.enabled and ns.IsGamepadUI() and not ns.foreverEditorOpen

	driver:SetAttribute("fc-priority", db.priorityBindings and 1 or 0)
	driver:SetAttribute("fc-w4", db.wxhbFourSlots and 1 or 0)
	driver:SetAttribute("fc-dpadParty", db.dpadParty)
	driver:SetAttribute("fc-dpadTarget", db.dpadTarget)
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
end
