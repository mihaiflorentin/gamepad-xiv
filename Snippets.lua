local _, ns = ...

-- Restricted-environment snippets. These run inside secure handlers, so they work in combat,
-- but may only use frame handles and the whitelisted API; there is no GetTime and no addon code.
ns.Snippets = {}
local S = ns.Snippets

-- Driver: fills both rows and selects what the 8 action keys do for the current layer.
-- The bottom row shows the current set, the top row always shows the two double tap sides.
S.ApplyLayer = [[
	if self:GetAttribute("fc-yield") == 1 then
		return
	end

	local layer = self:GetAttribute("fc-layer")
	local form = self:GetAttribute("fc-form")
	local set = self:GetAttribute("fc-formset-" .. form)
	local left, right = set * 2 - 1, set * 2
	-- Set 0: the game's stance bar for this form. Its 8 slots fill the left side; the right side
	-- stays that of the player's own set.
	if set == 0 then
		left = self:GetAttribute("fc-stanceSides") + form * 2 - 1
		right = self:GetAttribute("fc-formset-0") * 2
		-- Not seen yet, or the form has no stance bar at all: the normal set stays.
		if self:GetAttribute("slot-" .. left .. "-1") == 0 then
			left = right - 1
		end
	end
	local topLeft, topRight = self:GetAttribute("fc-side-WL"), self:GetAttribute("fc-side-WR")
	local active
	local priority = self:GetAttribute("fc-priority") == 1
	local editing = self:GetAttribute("fc-editing") == 1
	local flyout = self:GetAttribute("fc-flyout")
	local clearStage = self:GetAttribute("fc-clear")
	-- The addon's own ring is open: it takes A, B, the D-pad, L1 and R1.
	local ringOpen = self:GetAttribute("fc-ring") == 1
	-- One of Forever's class menus is open: pet commands, pet spells or forms. It closes on any
	-- button, so Circle is left with nothing else to do.
	local classMenuOpen = false
	for n = 1, self:GetAttribute("classPopup-count") or 0 do
		if self:GetFrameRef("classPopup" .. n):IsShown() then
			classMenuOpen = true
		end
	end

	-- Anything else that happens while R1 is held, such as a trigger, L1, the ring, a class menu or a
	-- flyout, makes its release no tap.
	if (layer ~= "SET" and layer ~= "BASE") or ringOpen or classMenuOpen or flyout ~= "" then
		self:SetAttribute("fc-r1Chord", 1)
	end
	-- With the R1 tap on, R1 + L2 goes through a button that marks the press as a chord too.
	local tapChords = layer == "SET" and self:GetAttribute("fc-r1Tap") == 1

	if layer == "L" or layer == "R" or layer == "WL" or layer == "WR" then
		active = layer
	elseif layer == "LR" then
		active, left = "L", self:GetAttribute("fc-side-LR")
	elseif layer == "RL" then
		active, right = "R", self:GetAttribute("fc-side-RL")
	end

	if editing then
		left, right = self:GetAttribute("fc-edit-left"), self:GetAttribute("fc-edit-right")
	end

	local soft = self:GetAttribute("fc-soft")

	for i = 1, 8 do
		local slotL = self:GetAttribute("slot-" .. left .. "-" .. i)
		local slotR = self:GetAttribute("slot-" .. right .. "-" .. i)
		local slotWL = self:GetAttribute("slot-" .. topLeft .. "-" .. i)
		local slotWR = self:GetAttribute("slot-" .. topRight .. "-" .. i)
		self:GetFrameRef("btnL" .. i):SetAttribute("action", slotL)
		self:GetFrameRef("btnR" .. i):SetAttribute("action", slotR)
		self:GetFrameRef("btnWL" .. i):SetAttribute("action", slotWL)
		self:GetFrameRef("btnWR" .. i):SetAttribute("action", slotWR)
		self:GetFrameRef("castL" .. i):SetAttribute("action", slotL)
		self:GetFrameRef("castR" .. i):SetAttribute("action", slotR)
		self:GetFrameRef("castWL" .. i):SetAttribute("action", slotWL)
		self:GetFrameRef("castWR" .. i):SetAttribute("action", slotWR)

		local key = self:GetAttribute("key" .. i)
		local flyoutPick = flyout ~= "" and self:GetAttribute("flyKey-" .. key)
		local ringKey = ringOpen and self:GetAttribute("ringKey-" .. key)
		local ringBind = ringOpen and self:GetAttribute("ringBind-" .. key)
		-- A highlighted entry that is a key binding, such as the Game Menu, puts that binding on A itself.
		local ringPickBinding = ringOpen and key == "PAD1" and not PlayerInCombat() and self:GetAttribute("fc-ringPickBinding")
		if ringPickBinding then
			self:SetBinding(priority, key, ringPickBinding)
		elseif ringKey then
			self:SetBindingClick(priority, key, ringKey, "LeftButton")
		elseif ringBind then
			self:SetBinding(priority, key, ringBind)
		elseif classMenuOpen and key == "PAD2" then
			self:SetBinding(priority, key, "NONE")
		elseif clearStage == 2 then
			-- Only the choice answers now: move, remove or cancel.
			if key == "PAD1" then
				self:SetBindingClick(priority, key, "GamepadXIVSlotMove", "LeftButton")
			elseif key == "PAD3" then
				self:SetBindingClick(priority, key, "GamepadXIVClearConfirm", "LeftButton")
			elseif key == "PAD2" then
				self:SetBindingClick(priority, key, "GamepadXIVClearCancel", "LeftButton")
			else
				self:ClearBinding(key)
			end
		elseif (clearStage == 1 or clearStage == 3) and not active and layer ~= "SET" and key == "PAD2" then
			self:SetBindingClick(priority, key, "GamepadXIVClearCancel", "LeftButton")
		elseif flyout ~= "" then
			-- The picker owns the action keys until something is chosen or it is cancelled.
			if key == "PAD2" then
				self:SetBindingClick(priority, key, "GamepadXIVFlyoutCancel", "LeftButton")
			elseif flyoutPick and flyoutPick <= self:GetAttribute("fly-" .. flyout .. "-count") then
				self:SetBindingClick(priority, key, "GamepadXIVFlyoutPick" .. flyoutPick, "LeftButton")
			else
				self:ClearBinding(key)
			end
		elseif active then
			self:SetBindingClick(priority, key, "GamepadXIVCast" .. active .. i, "LeftButton")
		elseif layer == "SET" then
			self:SetBindingClick(priority, key, "GamepadXIVSet" .. i, "LeftButton")
		elseif layer == "L1" then
			self:SetBinding(priority, key, self:GetAttribute("l1-" .. key))
		else
			local action = self:GetAttribute("base-" .. key)
			if soft ~= "" then
				action = self:GetAttribute("soft-" .. key) or action
			end
			-- Forever leaves some popups unfocused, such as death and party invites, so their buttons get pressed directly.
			local popupButton = self:GetAttribute("popup-" .. key)
			-- The tutorial takes three buttons, only here: with a trigger or shoulder held they still
			-- do what it teaches. Never in combat.
			local tutorialButton = self:GetAttribute("fc-tutorial") == 1 and not PlayerInCombat()
				and self:GetAttribute("tutorial-" .. key)
			if popupButton then
				self:SetBindingClick(priority, key, popupButton, "LeftButton")
			elseif tutorialButton then
				self:SetBindingClick(priority, key, tutorialButton, "LeftButton")
			else
				self:SetBinding(priority, key, action)
			end
		end
	end

	-- The selected side grows; the others shrink and dim, like FFXIV.
	local selected = active
	if editing then
		selected = nil
	end
	local dim = self:GetAttribute("fc-dim")
	for n = 1, 4 do
		local row = self:GetAttribute("rowKey" .. n)
		local content = self:GetFrameRef("content" .. row)
		if selected and selected ~= row then
			content:SetScale(0.78)
			content:SetAlpha(dim)
			-- A top bar set to show only when selected stays hidden while another bar is selected.
			if self:GetAttribute("fc-hide-" .. row) == 1 then
				content:SetAlpha(0)
			end
		elseif not selected and not editing and self:GetAttribute("fc-hide-" .. row) == 1 then
			content:SetScale(1)
			content:SetAlpha(0)
		else
			content:SetScale(selected and 1.15 or 1)
			content:SetAlpha(1)
		end
	end

	-- R1 + L2 is tab targeting; while R1 is held L2 selects nothing.
	if tapChords then
		self:SetBindingClick(priority, "PADLTRIGGER", "GamepadXIVR1ChordL2", "LeftButton")
	elseif layer == "SET" then
		self:SetBinding(priority, "PADLTRIGGER", "TARGETNEARESTENEMY")
	else
		self:SetBindingClick(priority, "PADLTRIGGER", "GamepadXIVL2", "LeftButton")
	end
	-- L1 + R2 tab targets the next enemy, like R1 + L2: the order of a shoulder and a trigger doesn't matter.
	if layer == "L1" then
		self:SetBinding(priority, "PADRTRIGGER", "TARGETNEARESTENEMY")
	else
		self:SetBindingClick(priority, "PADRTRIGGER", "GamepadXIVR2", "LeftButton")
	end

	if active then
		-- Forever opens its pet menus from R1 + R2 and L1 + L2, so pet classes keep those two free.
		local petChords = self:GetAttribute("fc-petChords") == 1
		local rightHeld = active == "R" or active == "WR"
		local leftHeld = active == "L" or active == "WL"
		self:SetBinding(priority, "PADRSHOULDER", (petChords and rightHeld) and "NONE" or "TARGETNEARESTENEMY")
		self:SetBinding(priority, "PADLSHOULDER", (petChords and leftHeld) and "NONE" or "TARGETNEARESTENEMY")
		-- Back is always bound at priority, like the base layer's, so one binding replaces the other.
		self:SetBindingClick(true, "PADBACK", "GamepadXIVEditToggle", "LeftButton")
		self:SetBindingClick(priority, "PADFORWARD", "GamepadXIVConfigToggle", "LeftButton")
	elseif layer == "L1" then
		-- FFXIV lands here while flying; dismounting in the air would drop the player.
		local sheathe = "TOGGLESHEATH"
		if IsFlying() then
			sheathe = "SITORSTAND"
		elseif IsMounted() then
			sheathe = "DISMOUNT"
		end
		-- L1 + R1 does what is picked in the settings; by default the sheathe above.
		self:SetBinding(priority, "PADRSHOULDER", self:GetAttribute("fc-l1r1") or sheathe)
		self:SetBindingClick(priority, "PADLSHOULDER", "GamepadXIVL1", "LeftButton")
		self:SetBinding(true, "PADBACK", "TOGGLEUI")
		self:SetBinding(priority, "PADFORWARD", "SCREENSHOT")
	else
		self:SetBindingClick(priority, "PADRSHOULDER", "GamepadXIVR1", "LeftButton")
		-- Already moving forward, L1 starts auto-run instead of its layer, while L1 + forward is auto-run.
		if self:GetAttribute("fc-stickUp") == 1 and self:GetAttribute("fc-l1StickUp") == "TOGGLEAUTORUN" then
			self:SetBinding(priority, "PADLSHOULDER", "TOGGLEAUTORUN")
		else
			self:SetBindingClick(priority, "PADLSHOULDER", "GamepadXIVL1", "LeftButton")
		end
		-- Back cycles like FFXIV, as Input.lua decides each step: Forever's own Back focuses a window, then
		-- each press is Forever's R2 to the next one, and once all were visited it opens chat to type in.
		-- With nothing open it opens chat. Forever sets its own Back again after this addon's, so these
		-- take priority.
		local backAction = self:GetAttribute("fc-backAction")
		if backAction == "chat" then
			self:SetBinding(true, "PADBACK", "OPENCHAT")
		elseif backAction == "next" then
			-- Forever's own R2 while a window is focused: the next window.
			self:SetBindingClick(true, "PADBACK", "InputFunctionBindingButton_PADRTRIGGER", "LeftButton")
		else
			self:ClearBinding("PADBACK")
		end
		self:SetBinding(priority, "PADFORWARD", "OPENRADIAL")
	end
	-- The open ring pages with L1 / R1, like Forever's.
	if ringOpen then
		local ringLeft = self:GetAttribute("ringKey-PADLSHOULDER")
		local ringRight = self:GetAttribute("ringKey-PADRSHOULDER")
		if ringLeft then
			self:SetBindingClick(priority, "PADLSHOULDER", ringLeft, "LeftButton")
		end
		if ringRight then
			self:SetBindingClick(priority, "PADRSHOULDER", ringRight, "LeftButton")
		end
	end

	-- L1 + R3 and R1 + L3 do what is picked in the settings; Forever's class menus by default. A class
	-- menu the class does not have falls back to the stick's own action.
	local leftMenu = layer == "L1" and self:GetAttribute("fc-l1r3")
	local leftKind = self:GetAttribute("fc-l1r3-menu")
	if leftMenu and leftKind and not (self:GetAttribute("classMenu-" .. leftKind) and self:GetFrameRef("classMenu" .. leftKind):IsShown()) then
		leftMenu = nil
	end
	local rightMenu = layer == "SET" and self:GetAttribute("fc-r1l3")
	local rightKind = self:GetAttribute("fc-r1l3-menu")
	if rightMenu and rightKind and not (self:GetAttribute("classMenu-" .. rightKind) and self:GetFrameRef("classMenu" .. rightKind):IsShown()) then
		rightMenu = nil
	end
	if rightMenu then
		self:SetBinding(priority, "PADLSTICK", rightMenu)
	else
		self:SetBinding(priority, "PADLSTICK", self:GetAttribute("base-PADLSTICK"))
	end
	if active then
		-- Trigger + R3 moves or removes an ability, standing in for FFXIV's trigger + touchpad.
		self:SetBindingClick(priority, "PADRSTICK", "GamepadXIVClearStart", "LeftButton")
		self:SetBindingClick(priority, "PADLSTICKUP", "GamepadXIVStickUp", "LeftButton")
	else
		-- R3 does what is picked in the settings; first or third person by default. R1 + R3 has its
		-- own setting, the addon's ring by default.
		local r1r3 = layer == "SET" and self:GetAttribute("fc-r1r3")
		if leftMenu then
			self:SetBinding(priority, "PADRSTICK", leftMenu)
		elseif r1r3 then
			self:SetBinding(priority, "PADRSTICK", r1r3)
		else
			self:SetBinding(priority, "PADRSTICK", self:GetAttribute("fc-r3") or "CLICK GamepadXIVView:LeftButton")
		end
		-- Clicking the right stick in while aiming at the ring closes it, rather than doing R3's action.
		local ringStick = ringOpen and self:GetAttribute("ringKey-PADRSTICK")
		if ringStick then
			self:SetBindingClick(priority, "PADRSTICK", ringStick, "LeftButton")
		end
		if layer == "L1" then
			self:SetBinding(priority, "PADLSTICKUP", self:GetAttribute("fc-l1StickUp") or "TOGGLEAUTORUN")
		else
			self:SetBindingClick(priority, "PADLSTICKUP", "GamepadXIVStickUp", "LeftButton")
		end
	end

	-- The open ring takes the right stick's four directions, which the game makes buttons with the
	-- GamePadStickAxisButtons setting. Letting the stick go is then a key press that uses the entry,
	-- when that setting is on; in combat A reads the held directions to know the segment.
	local release = ringOpen
	-- Each direction has a release button of its own: two releases of one button at the same moment
	-- (letting go from a diagonal) reach it only once.
	for n = 1, 4 do
		local dir = (n == 1 and "Up") or (n == 2 and "Down") or (n == 3 and "Left") or "Right"
		local key = "PADRSTICK" .. dir:upper()
		if release then
			self:SetBindingClick(priority, key, "GamepadXIVRingrelease" .. dir, "LeftButton")
		else
			self:ClearBinding(key)
		end
	end

	self:CallMethod("OnLayerChanged", layer, left, right, set, form)
]]

-- Driver: full (re)binding of everything the addon owns.
S.BindAll = [[
	self:ClearBindings()
	local yielded = self:GetAttribute("fc-yield") == 1

	-- Alpha alone would leave invisible buttons clickable.
	for n = 1, 4 do
		local row = self:GetAttribute("rowKey" .. n)
		for i = 1, 8 do
			self:GetFrameRef("btn" .. row .. i):EnableMouse(not yielded)
		end
	end

	if yielded then
		self:CallMethod("OnYieldChanged", true)
		return
	end

	local priority = self:GetAttribute("fc-priority") == 1

	for i = 1, self:GetAttribute("static-count") do
		self:SetBinding(priority, self:GetAttribute("static-key" .. i), self:GetAttribute("static-action" .. i))
	end

	self:RunAttribute("UpdateTargetBindings")
	self:RunAttribute("ApplyLayer")
	self:CallMethod("OnYieldChanged", false)
]]

-- Driver: buttons whose base action depends on having a target (FFXIV's context-sensitive X and L3).
S.UpdateTargetBindings = [[
	local suffix = UnitExists("target") and "-target" or "-notarget"
	self:SetAttribute("base-PAD3", self:GetAttribute("ctx-PAD3" .. suffix))
	self:SetAttribute("base-PADLSTICK", self:GetAttribute("ctx-PADLSTICK" .. suffix))
	-- Flying or swimming, B descends instead of cancelling.
	self:SetAttribute("base-PAD2", (IsFlying() or IsSwimming()) and "SITORSTAND" or self:GetAttribute("ctx-PAD2-ground"))
	-- D-pad left and right tab target, unless the party selection option takes the whole D-pad.
	local dpadParty = self:GetAttribute("fc-dpadParty")
	local partyMode = dpadParty == "always" or (dpadParty == "raid" and self:GetAttribute("fc-inRaid") == 1)
	local dpadSuffix = partyMode and "-party" or "-target"
	self:SetAttribute("base-PADDLEFT", self:GetAttribute("ctx-PADDLEFT" .. dpadSuffix))
	self:SetAttribute("base-PADDRIGHT", self:GetAttribute("ctx-PADDRIGHT" .. dpadSuffix))
	self:SetAttribute("base-PADDUP", self:GetAttribute("ctx-PADDUP" .. dpadSuffix))
	self:SetAttribute("base-PADDDOWN", self:GetAttribute("ctx-PADDDOWN" .. dpadSuffix))
]]

S.OnStateTarget = [[
	self:RunAttribute("UpdateTargetBindings")
	self:RunAttribute("ApplyLayer")
]]

S.OnStateRaid = [[
	self:SetAttribute("fc-inRaid", newstate)
	self:RunAttribute("UpdateTargetBindings")
	self:RunAttribute("ApplyLayer")
]]

-- Driver: leaves everything to Forever while a vehicle/possess bar or Forever's own editor is up.
S.OnStateVehicle = [[
	self:SetAttribute("fc-vehicle", newstate)
	self:RunAttribute("UpdateYield")
]]

-- Driver: each form or stance remembers its own set, so entering one changes the bottom row.
S.OnStateForm = [[
	self:SetAttribute("fc-rawForm", newstate)
	self:RunAttribute("UpdateForm")
]]

S.UpdateForm = [[
	local form = 0
	if self:GetAttribute("fc-formLink") == 1 then
		form = self:GetAttribute("fc-rawForm")
	end
	self:SetAttribute("fc-form", form)
	self:RunAttribute("ApplyLayer")
]]

S.UpdateYield = [[
	local yield = (self:GetAttribute("fc-off") == 1 or self:GetAttribute("fc-vehicle") == 1) and 1 or 0
	if yield == 1 and self:GetAttribute("fc-editing") == 1 then
		self:RunAttribute("EndEdit")
	end

	-- Plain rebinds must keep a held trigger's layer; only a real hand-over clears input state.
	if yield ~= self:GetAttribute("fc-yield") then
		self:SetAttribute("fc-yield", yield)
		self:SetAttribute("fc-lDown", 0)
		self:SetAttribute("fc-rDown", 0)
		self:SetAttribute("fc-w", "")
		self:SetAttribute("fc-first", "")
		self:SetAttribute("fc-latch", "")
		self:SetAttribute("fc-consumed", "")
		self:SetAttribute("fc-layer", "BASE")
		self:SetAttribute("fc-flyout", "")
		self:SetAttribute("fc-stickUp", 0)
		if self:GetAttribute("fc-clear") ~= 0 then
			self:RunAttribute("SetClear", 0)
		end
		self:RunAttribute("UpdateTargetBindings")
		self:RunAttribute("SetSoft", "")
	end
	self:RunAttribute("BindAll")
]]

-- Driver: edit state, used while the bars are moved. Every row shows and the slots stop casting.
S.BeginEdit = [[
	self:SetAttribute("fc-editing", 1)
	for n = 1, 4 do
		local row = self:GetAttribute("rowKey" .. n)
		for i = 1, 8 do
			local button = self:GetFrameRef("btn" .. row .. i)
			button:SetAttribute("type", nil)
			button:SetAttribute("typerelease", nil)
			self:GetFrameRef("cast" .. row .. i):SetAttribute("type", nil)
		end
	end
	self:RunAttribute("ApplyLayer")
]]

S.EndEdit = [[
	self:SetAttribute("fc-editing", 0)
	for n = 1, 4 do
		local row = self:GetAttribute("rowKey" .. n)
		for i = 1, 8 do
			local button = self:GetFrameRef("btn" .. row .. i)
			button:SetAttribute("type", "action")
			button:SetAttribute("typerelease", "actionrelease")
			self:GetFrameRef("cast" .. row .. i):SetAttribute("type", "action")
		end
	end
	self:RunAttribute("ApplyLayer")
	self:CallMethod("OnEditEnded")
]]

-- Entering combat always ends edit mode, even with no addon code able to touch the frames.
S.OnStateCombat = [[
	if newstate == 1 and self:GetAttribute("fc-editing") == 1 then
		self:RunAttribute("EndEdit")
	end
	if newstate == 1 and self:GetAttribute("fc-clear") ~= 0 then
		self:RunAttribute("SetClear", 0)
	end
	-- The tutorial's buttons go back to their own actions in combat.
	if self:GetAttribute("fc-tutorial") == 1 then
		self:RunAttribute("ApplyLayer")
	end
]]

-- Driver: moving or removing an ability. 0 is off, 1 waits for a slot, 2 asks what to do with it,
-- 3 waits for the slot to move it to. Slots do not cast from 1 on, so pressing one only selects it.
S.SetClear = [[
	local stage = ...
	self:SetAttribute("fc-clear", stage)
	local castType = "action"
	if stage ~= 0 then
		castType = nil
	end
	for n = 1, 4 do
		local row = self:GetAttribute("rowKey" .. n)
		for i = 1, 8 do
			self:GetFrameRef("cast" .. row .. i):SetAttribute("type", castType)
		end
	end
	self:RunAttribute("ApplyLayer")
	self:CallMethod("OnClearChanged", stage)
]]

S.ClearStartClick = [[
	if not down then
		return
	end
	local driver = self:GetFrameRef("driver")
	if not PlayerInCombat() and driver:GetAttribute("fc-editing") ~= 1 then
		driver:RunAttribute("SetClear", 1)
	end
]]

S.ClearCancelClick = [[
	if down then
		self:GetFrameRef("driver"):RunAttribute("SetClear", 0)
	end
]]

-- Driver: FFXIV's soft target. Actions go to this unit without changing the real target.
-- It ends with the next action, or when A confirms it or B cancels it.
S.SetSoft = [[
	local unit = ...
	self:SetAttribute("fc-soft", unit)
	local value = unit
	if unit == "" then
		value = nil
	end
	for n = 1, 4 do
		local row = self:GetAttribute("rowKey" .. n)
		for i = 1, 8 do
			self:GetFrameRef("cast" .. row .. i):SetAttribute("unit", value)
		end
	end
	self:CallMethod("OnSoftChanged", unit)
	self:RunAttribute("ApplyLayer")
]]

-- Cast button: a press spends the soft target once the action has gone out.
S.ActionPre = [[
	if not down then
		return
	end
	local driver = self:GetFrameRef("driver")
	if driver:GetAttribute("fc-clear") ~= 0 or driver:GetAttribute("fc-editing") == 1 then
		return
	end
	-- A flyout opens the controller picker instead of Blizzard's mouse list.
	local actionType, flyoutID = GetActionInfo(self:GetAttribute("action"))
	if actionType == "flyout" then
		driver:RunAttribute("OpenFlyout", flyoutID)
		return false
	end
	local soft = driver:GetAttribute("fc-soft")
	if soft == "" then
		return
	end
	-- A vanished soft target falls back to the real target instead of failing the action.
	if not UnitExists(soft) then
		driver:RunAttribute("SetSoft", "")
		return
	end
	return nil, "soft"
]]

S.ActionPost = [[
	self:GetFrameRef("driver"):RunAttribute("SetSoft", "")
]]

-- A while a soft target is set: makes it the real target.
S.SoftConfirmPreClick = [[
	if down then
		local driver = self:GetFrameRef("driver")
		self:SetAttribute("unit", driver:GetAttribute("fc-soft"))
		driver:RunAttribute("SetSoft", "")
	end
]]

-- B while a soft target is set.
S.SoftCancelClick = [[
	if down then
		self:GetFrameRef("driver"):RunAttribute("SetSoft", "")
	end
]]

-- Driver: trigger state machine. Arguments: "L"/"R", down (1/0), isDoubleTap (1/0), isQuick (1/0).
-- Layers: L, R, WL, WR (double tap held), LR, RL (second trigger while first is held), BASE.
-- fc-triggerMode: hold; toggle (each press flips the side, a double tap also stays selected without
-- holding); or mixed (a quick tap flips, a hold holds).
S.OnTrigger = [[
	local side, down, isDoubleTap, isQuick = ...
	local mode = self:GetAttribute("fc-triggerMode")
	local latch = self:GetAttribute("fc-latch")
	local consumed = self:GetAttribute("fc-consumed")
	local lDown = self:GetAttribute("fc-lDown")
	local rDown = self:GetAttribute("fc-rDown")
	local w = self:GetAttribute("fc-w")
	local first = self:GetAttribute("fc-first")
	local other = (side == "L") and "R" or "L"

	if down == 1 then
		local otherDown = (side == "L") and rDown or lDown
		if otherDown == 0 and isDoubleTap == 1 then
			w = side
			first = side
		elseif mode ~= "hold" and latch == side then
			latch = ""
			consumed = side
			w = ""
		elseif mode == "toggle" then
			latch = side
			first = side
			w = ""
		elseif otherDown == 1 then
			if first == "" then
				first = other
			end
		else
			first = side
		end
	else
		local otherDown = (side == "L") and rDown or lDown
		if w == side and mode == "toggle" then
			-- Stays selected until the next press.
		elseif w == side then
			w = ""
			latch = ""
		elseif mode == "mixed" and consumed ~= side and isQuick == 1 and otherDown == 0 then
			latch = side
		end
		if consumed == side then
			consumed = ""
		end
		first = ""
	end

	if side == "L" then
		lDown = down
	else
		rDown = down
	end

	local lHeld = latch == "L" or (lDown == 1 and mode ~= "toggle" and consumed ~= "L")
	local rHeld = latch == "R" or (rDown == 1 and mode ~= "toggle" and consumed ~= "R")

	if first == "" then
		if lHeld and not rHeld then
			first = "L"
		elseif rHeld and not lHeld then
			first = "R"
		end
	end

	local layer = "BASE"
	if w ~= "" then
		layer = "W" .. w
	elseif lHeld and rHeld then
		layer = (first == "L") and "LR" or "RL"
	elseif lHeld then
		layer = "L"
	elseif rHeld then
		layer = "R"
	end

	self:SetAttribute("fc-lDown", lDown)
	self:SetAttribute("fc-rDown", rDown)
	self:SetAttribute("fc-w", w)
	self:SetAttribute("fc-first", first)
	self:SetAttribute("fc-latch", latch)
	self:SetAttribute("fc-consumed", consumed)
	self:SetAttribute("fc-layer", layer)
	self:RunAttribute("ApplyLayer")
]]

-- Trigger button click. The double tap clock is adapted from CrossHotbar (BSD, ChainStratagem):
-- an attribute driver writes "fc-ready" back to 1 on each 0.2s state driver tick, so counting
-- those writes gives a window without GetTime.
S.TriggerClick = [[
	local driver = self:GetFrameRef("driver")
	local isDoubleTap = 0
	local isQuick = 0
	if not down and self:GetAttribute("fc-ready") == 0 then
		isQuick = 1
	end
	if down then
		if self:GetAttribute("fc-ready") == 0 then
			if driver:GetAttribute("fc-noDouble-" .. self:GetAttribute("fc-side")) ~= 1 then
				isDoubleTap = 1
			end
			self:SetAttribute("fc-ticks", 0)
		else
			self:SetAttribute("fc-ticks", driver:GetAttribute("fc-tapTicks"))
		end
	end
	driver:RunAttribute("OnTrigger", self:GetAttribute("fc-side"), down and 1 or 0, isDoubleTap, isQuick)
]]

S.TriggerAttribute = [[
	if name == "fc-ready" then
		if value == 1 and ticksLeft and ticksLeft > 0 then
			ticksLeft = ticksLeft - 1
			if ticksLeft > 0 then
				self:SetAttribute("fc-ready", 0)
			end
		end
	elseif name == "fc-ticks" then
		ticksLeft = value
		self:SetAttribute("fc-ready", (value > 0) and 0 or 1)
	end
]]

-- R1 outside a trigger layer: holds the set selection layer. With the R1 tap on, letting it go
-- quickly without having pressed anything else swaps between the two set pairs, like FFXIV's
-- option. Quick is within 2 ticks of the trigger clock, about 0.2-0.4 seconds, so holding R1 to
-- look at the sets and letting go changes nothing.
S.R1Click = [[
	local driver = self:GetFrameRef("driver")
	if down then
		driver:SetAttribute("fc-r1Chord", 0)
		self:SetAttribute("fc-ticks", 2)
		driver:SetAttribute("fc-layer", "SET")
	elseif driver:GetAttribute("fc-layer") == "SET" then
		driver:SetAttribute("fc-layer", "BASE")
		local quick = self:GetAttribute("fc-ready") == 0
		if quick and driver:GetAttribute("fc-r1Tap") == 1 and driver:GetAttribute("fc-r1Chord") == 0 then
			driver:RunAttribute("SwapTapSets")
		end
	end
	if not down then
		driver:SetAttribute("fc-r1Chord", 1)
	end
	driver:RunAttribute("ApplyLayer")
]]

-- Driver: the R1 tap. The bottom row changes to pair B when it shows pair A's set, else to pair A.
-- With the top row option on, the top row changes with it, to both halves of the pair's top set.
S.SwapTapSets = [[
	local form = self:GetAttribute("fc-form")
	local current = self:GetAttribute("fc-formset-" .. form)
	local pair = (current == self:GetAttribute("fc-tapA-bottom")) and "B" or "A"
	local bottom = self:GetAttribute("fc-tap" .. pair .. "-bottom")
	local top = self:GetAttribute("fc-tapTop") == 1 and self:GetAttribute("fc-tap" .. pair .. "-top")
	if not bottom then
		return
	end
	self:SetAttribute("fc-formset-" .. form, bottom)
	if top then
		self:SetAttribute("fc-side-WL", top * 2 - 1)
		self:SetAttribute("fc-side-WR", top * 2)
		self:CallMethod("OnTapSwap", pair, top * 2 - 1, top * 2)
	end
]]

-- R1 + L2 with the R1 tap on: marks R1's press as a chord, then the button tab targets.
S.R1ChordPre = [[
	if down then
		self:GetFrameRef("driver"):SetAttribute("fc-r1Chord", 1)
	end
]]

-- Set selection button: R1 + action key.
S.SetClick = [[
	if not down then
		return
	end
	local driver = self:GetFrameRef("driver")
	driver:SetAttribute("fc-r1Chord", 1)
	local set = self:GetAttribute("fc-setIndex")
	local form = driver:GetAttribute("fc-form")
	-- In a form, picking the normal bar's own set gives the form its own set back, 4 + its number.
	-- Otherwise that form would show the same set as the normal bar and never change it.
	if form > 0 and set == driver:GetAttribute("fc-formset-0") then
		driver:SetAttribute("fc-formset-" .. form, 4 + form)
	else
		driver:SetAttribute("fc-formset-" .. form, set)
	end
	driver:RunAttribute("ApplyLayer")

	-- Sets 1-3 are Forever's pages. Keeping its page on the same number sends the spellbook's bind
	-- flow to this set. With 3 pages, one click forward or back always gets there.
	local page = driver:GetAttribute("fc-page")
	local pages = driver:GetAttribute("fc-numPages")
	if page and set <= pages and set ~= page then
		driver:SetAttribute("fc-page", set)
		self:SetAttribute("type", "click")
		if (set - page) % pages == 1 then
			return "LeftButton"
		end
		return "RightButton"
	end
	self:SetAttribute("type", nil)
]]

-- Driver: a flyout's choices go on the keys. Argument: the flyout's id.
S.OpenFlyout = [[
	local flyoutID = ...
	local count = self:GetAttribute("fly-" .. flyoutID .. "-count")
	if not count or count == 0 then
		return
	end
	for n = 1, count do
		self:GetFrameRef("flyoutPick" .. n):SetAttribute("spell", self:GetAttribute("fly-" .. flyoutID .. "-" .. n))
	end
	self:SetAttribute("fc-flyout", flyoutID)
	self:RunAttribute("ApplyLayer")
	self:CallMethod("OnFlyoutChanged", flyoutID)
]]

S.CloseFlyout = [[
	self:SetAttribute("fc-flyout", "")
	self:RunAttribute("ApplyLayer")
	self:CallMethod("OnFlyoutChanged", "")
]]

S.FlyoutPickPre = [[
	if down then
		return nil, "close"
	end
]]

S.FlyoutPickPost = [[
	self:GetFrameRef("driver"):RunAttribute("CloseFlyout")
]]

-- Wrapped on Forever's class menus: their Circle binding follows whether one is open.
S.ClassPopupShown = [[
	control:RunAttribute("ApplyLayer")
]]

-- R1 + R3, or another button set to it: opens or closes the addon's ring.
S.RingToggleClick = [[
	if not down then
		return
	end
	local driver = self:GetFrameRef("driver")
	local open = 1
	if driver:GetAttribute("fc-ring") == 1 then
		open = 0
	end
	driver:SetAttribute("fc-ring", open)
	driver:SetAttribute("fc-held-Up", 0)
	driver:SetAttribute("fc-held-Down", 0)
	driver:SetAttribute("fc-held-Left", 0)
	driver:SetAttribute("fc-held-Right", 0)
	-- The page the ring opens on, and no emotes or toy pages yet: what A uses in combat follows these.
	driver:SetAttribute("fc-ringPage", driver:GetAttribute("fc-ringStartPage") or 1)
	driver:SetAttribute("fc-ringSub", 0)
	-- Opened with R1 or L1 held, that shoulder is still down. The ring takes L1 and R1
	-- for its pages, so the layer goes back to the base now rather than on the release.
	local layer = driver:GetAttribute("fc-layer")
	if open == 1 and (layer == "SET" or layer == "L1") then
		driver:SetAttribute("fc-layer", "BASE")
	end
	driver:RunAttribute("ApplyLayer")
	if open == 1 then
		driver:CallMethod("OnRing", "open")
	else
		driver:CallMethod("OnRing", "close")
	end
]]

-- A uses the highlighted entry. Built-in entries are a secure click on Forever's own button, which
-- the addon sets on this button while the highlight moves. That can't change in combat, so there
-- the click is dropped and the addon handles the entry (or says it can't).
S.RingPickPre = [[
	if not down then
		return false
	end
	local driver = self:GetFrameRef("driver")
	if PlayerInCombat() then
		-- The ring can't point A at an entry in combat, so it set up every segment of every page
		-- beforehand, as p2s3-type and so on. The stick directions the game reports as held say
		-- which segment: right is 1, then counterclockwise, as the ring draws them.
		local up = driver:GetAttribute("fc-held-Up") == 1
		local down = driver:GetAttribute("fc-held-Down") == 1
		local segment = 0
		if driver:GetAttribute("fc-held-Right") == 1 then
			segment = (up and 2) or (down and 8) or 1
		elseif driver:GetAttribute("fc-held-Left") == 1 then
			segment = (up and 4) or (down and 6) or 5
		elseif up then
			segment = 3
		elseif down then
			segment = 7
		end
		local prefix = "p" .. (driver:GetAttribute("fc-ringPage") or 0) .. "s" .. segment .. "-"
		if segment == 0 or driver:GetAttribute("fc-ringSub") == 1 then
			prefix = "none-"
		end
		self:SetAttribute("type", self:GetAttribute(prefix .. "type"))
		self:SetAttribute("macro", self:GetAttribute(prefix .. "macro"))
		self:SetAttribute("macrotext", self:GetAttribute(prefix .. "macrotext"))
		self:SetAttribute("spell", self:GetAttribute(prefix .. "spell"))
		self:SetAttribute("item", self:GetAttribute(prefix .. "item"))
		self:SetAttribute("toy", self:GetAttribute(prefix .. "toy"))
	elseif self:GetAttribute("fc-keep") == 1 then
		return nil, "pick"
	end
	driver:SetAttribute("fc-ring", 0)
	driver:RunAttribute("ApplyLayer")
	return nil, "pick"
]]

-- The same as A, when the right stick is let go. Each direction the stick passes presses and
-- releases one of the four stick buttons, each bound to its own release button (fc-dir); which ones
-- are held is kept on the driver. The entry is used when a direction that was pressed comes up and
-- none is held any more. Moving round from one entry to the next always keeps one held. A release
-- without its press (the stick was already pushed when the ring opened) is ignored.
S.RingReleasePre = [[
	local driver = self:GetFrameRef("driver")
	local key = "fc-held-" .. self:GetAttribute("fc-dir")
	if down then
		driver:SetAttribute(key, 1)
		return false
	end
	if driver:GetAttribute(key) ~= 1 then
		return false
	end
	driver:SetAttribute(key, 0)
	if driver:GetAttribute("fc-held-Up") == 1 or driver:GetAttribute("fc-held-Down") == 1
		or driver:GetAttribute("fc-held-Left") == 1 or driver:GetAttribute("fc-held-Right") == 1 then
		return false
	end
	-- With the setting off, the directions are only kept for A in combat. In combat, letting go
	-- can't tell which segment it was: a diagonal comes back as two releases, one after the other.
	-- A uses the entry there.
	if driver:GetAttribute("fc-ringRelease") ~= 1 then
		return false
	end
	if PlayerInCombat() then
		return false
	elseif self:GetAttribute("fc-keep") == 1 then
		return nil, "pick"
	end
	driver:SetAttribute("fc-ring", 0)
	driver:RunAttribute("ApplyLayer")
	return nil, "pick"
]]

S.RingPickPost = [[
	self:GetFrameRef("driver"):CallMethod("OnRing", message)
]]

-- A key the open ring took: close, change page or show the emotes. Closing hands the keys back.
S.RingKeyClick = [[
	if not down then
		return
	end
	local driver = self:GetFrameRef("driver")
	local action = self:GetAttribute("fc-ringAction")
	-- The page and the emotes are followed here too, for what A uses in combat.
	if driver:GetAttribute("fc-ringSub") ~= 1 and (action == "prev" or action == "next") then
		local count = driver:GetAttribute("fc-ringPages") or 0
		local step = 1
		if action == "prev" then
			step = -1
		end
		if count > 1 then
			driver:SetAttribute("fc-ringPage", ((driver:GetAttribute("fc-ringPage") or 1) - 1 + step) % count + 1)
		end
	elseif action == "emotes" then
		if driver:GetAttribute("fc-ringSub") == 1 then
			driver:SetAttribute("fc-ringSub", 0)
		else
			driver:SetAttribute("fc-ringSub", 1)
		end
	end
	if action == "pick" or action == "close" then
		driver:SetAttribute("fc-ring", 0)
		driver:RunAttribute("ApplyLayer")
	end
	driver:CallMethod("OnRing", action)
]]

S.FlyoutCancelClick = [[
	if down then
		self:GetFrameRef("driver"):RunAttribute("CloseFlyout")
	end
]]

-- L1 held is a layer, like the triggers; a double tap steps through the party or raid.
S.L1Click = [[
	local driver = self:GetFrameRef("driver")
	self:SetAttribute("unit", nil)
	if not down then
		if driver:GetAttribute("fc-layer") == "L1" then
			driver:SetAttribute("fc-layer", "BASE")
			driver:RunAttribute("ApplyLayer")
		end
		return
	end
	if driver:GetAttribute("fc-layer") == "BASE" then
		driver:SetAttribute("fc-layer", "L1")
		driver:RunAttribute("ApplyLayer")
	end
	if self:GetAttribute("fc-ready") == 0 then
		self:SetAttribute("fc-ticks", 0)
		driver:RunAttribute("CycleGroup", 1, 1)
		self:SetAttribute("unit", driver:GetAttribute("fc-realPick"))
		driver:SetAttribute("fc-realPick", nil)
	else
		self:SetAttribute("fc-ticks", driver:GetAttribute("fc-tapTicks"))
	end
]]

-- Left stick pushed forward: only tracked, so L1 can start auto-run while already moving.
S.StickUpClick = [[
	local driver = self:GetFrameRef("driver")
	local value = down and 1 or 0
	if driver:GetAttribute("fc-stickUp") ~= value then
		driver:SetAttribute("fc-stickUp", value)
		driver:RunAttribute("ApplyLayer")
	end
]]

-- D-pad up/down and L1 + left/right: soft target through the party or raid list.
S.CyclePreClick = [[
	if down then
		local driver = self:GetFrameRef("driver")
		driver:RunAttribute("CycleGroup", self:GetAttribute("fc-step"), self:GetAttribute("fc-raidOnly"))
		self:SetAttribute("unit", driver:GetAttribute("fc-realPick"))
		driver:SetAttribute("fc-realPick", nil)
	end
]]

-- D-pad left/right: enemy tab targeting, friend tab targeting, or turns between the two, since neither
-- of WoW's bindings covers both. Secure code cannot tell enemies from friends around the player.
S.TargetCyclePreClick = [[
	if not down then
		return
	end
	local driver = self:GetFrameRef("driver")
	local mode = driver:GetAttribute("fc-dpadTarget")
	local command
	if mode == "enemy" then
		command = "/targetenemy"
	elseif mode == "friend" then
		command = "/targetfriend"
	else
		command = driver:GetAttribute("fc-targetCycle") == "/targetenemy" and "/targetfriend" or "/targetenemy"
		driver:SetAttribute("fc-targetCycle", command)
	end
	if self:GetAttribute("fc-step") < 0 then
		command = command .. " 1"
	end
	self:SetAttribute("macrotext", command)
]]

-- D-pad with party selection active: moves over the party or raid frames on screen.
S.FrameMovePreClick = [[
	if down then
		local driver = self:GetFrameRef("driver")
		driver:RunAttribute("MoveFrameCursor", self:GetAttribute("fc-dx"), self:GetAttribute("fc-dy"))
		self:SetAttribute("unit", driver:GetAttribute("fc-realPick"))
		driver:SetAttribute("fc-realPick", nil)
	end
]]

-- Driver: party selection's result. With Party targeting on Hard, the button that was pressed sets
-- the real target, since only a click can do that.
S.SelectGroupUnit = [[
	local unit = ...
	if self:GetAttribute("fc-partyTargeting") == "hard" then
		self:SetAttribute("fc-realPick", unit)
	else
		self:RunAttribute("SetSoft", unit)
	end
]]

-- Driver: a press with no soft target selects the frame the cursor was last on (or the top left one).
-- On Hard there is no selection to lose, so every press moves.
-- Otherwise the nearest frame in that direction on the same row or column wins, then the far end of
-- that row or column, then the nearest frame on another one. Without frames, it steps through the list.
S.MoveFrameCursor = [[
	local dx, dy = ...
	local real = self:GetAttribute("fc-partyTargeting") == "hard"
	local cursor = self:GetAttribute("fc-ufCursor")
	local cursorUnit
	local currentX, currentY, tolerance
	if cursor then
		local frame = self:GetFrameRef("uf" .. cursor)
		local unit = frame and frame:IsVisible() and frame:GetAttribute("unit")
		local left, bottom, width, height
		if unit and UnitExists(unit) then
			left, bottom, width, height = frame:GetRect()
		end
		if left then
			if self:GetAttribute("fc-soft") == "" and not real then
				self:RunAttribute("SelectGroupUnit", unit)
				return
			end
			cursorUnit = unit
			currentX, currentY = left + width / 2, bottom + height / 2
			tolerance = (dx ~= 0 and height or width) / 2
		end
	end

	local bestIndex, bestUnit, bestScore
	for index = 1, self:GetAttribute("fc-ufCount") or 0 do
		local frame = self:GetFrameRef("uf" .. index)
		local unit = frame and frame:IsVisible() and frame:GetAttribute("unit")
		local left, bottom, width, height
		if unit and UnitExists(unit) then
			left, bottom, width, height = frame:GetRect()
		end
		if left then
			local x, y = left + width / 2, bottom + height / 2
			local score
			if not currentX then
				score = x - y
			elseif index ~= cursor then
				local along = (x - currentX) * dx + (y - currentY) * dy
				local across = abs((x - currentX) * dy) + abs((y - currentY) * dx)
				if across <= tolerance then
					score = along > 0 and along or 100000 + along
				elseif along > 0 then
					score = 200000 + along + across
				end
			end
			if score and (not bestScore or score < bestScore) then
				bestIndex, bestUnit, bestScore = index, unit, score
			end
		end
	end

	if bestUnit then
		self:SetAttribute("fc-ufCursor", bestIndex)
		self:SetAttribute("fc-cycleFrame", bestIndex)
		self:RunAttribute("SelectGroupUnit", bestUnit)
	elseif not currentX then
		self:RunAttribute("CycleGroup", dx - dy, dx ~= 0 and 1 or 0)
	elseif real then
		self:RunAttribute("SelectGroupUnit", cursorUnit)
	end
]]

-- Driver: the unit at a step of the party cycle, with each member followed by their pet.
S.PartyCycleUnit = [[
	local index = ...
	local member = (index - index % 2) / 2
	if index % 2 == 0 then
		return member == 0 and "player" or ("party" .. member)
	end
	return member == 0 and "pet" or ("partypet" .. member)
]]

-- Driver: moves the soft target. The first step in a party starts on the player, like FFXIV.
S.CycleGroup = [[
	local step, raidOnly = ...
	local inRaid = UnitExists("raid1")
	local useRaid = raidOnly == 1 and inRaid

	-- With party or raid frames on screen, the list follows them as drawn: column by column, top to
	-- bottom. Pets shown below the members then come after them, and frames sorted by role keep their order.
	if useRaid or not inRaid then
		local current = self:GetAttribute("fc-cycleFrame")
		local fresh = self:GetAttribute("fc-soft") == ""
		if self:GetAttribute("fc-partyTargeting") == "hard" then
			fresh = not current
		end
		local currentKey
		if current and not fresh then
			local frame = self:GetFrameRef("uf" .. current)
			local unit = frame and frame:IsVisible() and frame:GetAttribute("unit")
			if unit and UnitExists(unit) then
				local left, bottom, width, height = frame:GetRect()
				if left then
					local x = left + width / 2
					currentKey = (x - x % 1) * 10000 - (bottom + height / 2)
				end
			end
		end
		local firstIndex, firstKey, lastIndex, lastKey, nextIndex, nextKey
		for index = 1, self:GetAttribute("fc-ufCount") or 0 do
			local frame = self:GetFrameRef("uf" .. index)
			local unit = frame and frame:IsVisible() and frame:GetAttribute("unit")
			local left, bottom, width, height
			if unit and UnitExists(unit) then
				left, bottom, width, height = frame:GetRect()
			end
			if left then
				local x = left + width / 2
				local key = (x - x % 1) * 10000 - (bottom + height / 2)
				if not firstKey or key < firstKey then
					firstIndex, firstKey = index, key
				end
				if not lastKey or key > lastKey then
					lastIndex, lastKey = index, key
				end
				if currentKey and step > 0 and key > currentKey and (not nextKey or key < nextKey) then
					nextIndex, nextKey = index, key
				elseif currentKey and step < 0 and key < currentKey and (not nextKey or key > nextKey) then
					nextIndex, nextKey = index, key
				end
			end
		end
		if firstIndex then
			local pick = firstIndex
			if nextIndex then
				pick = nextIndex
			elseif currentKey and step < 0 then
				pick = lastIndex
			end
			self:SetAttribute("fc-cycleFrame", pick)
			self:SetAttribute("fc-ufCursor", pick)
			self:RunAttribute("SelectGroupUnit", self:GetFrameRef("uf" .. pick):GetAttribute("unit"))
			return
		end
	end

	-- Without frames on screen: the unit list, in a party with each member followed by their pet.
	local prefix = useRaid and "raid" or "party"
	-- 0 player, 1 pet, 2 party1, 3 partypet1, and so on.
	local count = useRaid and 40 or 9
	local stored = self:GetAttribute("fc-cycle-" .. prefix)
	local index = stored or 0
	local restart = self:GetAttribute("fc-soft") == ""
	if self:GetAttribute("fc-partyTargeting") == "hard" then
		restart = not stored
	end

	if restart and not useRaid then
		index = 0
	else
		for _ = 0, count do
			index = index + step
			if index > count then
				index = 0
			elseif index < 0 then
				index = count
			end
			if useRaid then
				if index > 0 and UnitExists("raid" .. index) then
					break
				end
			elseif UnitExists(self:RunAttribute("PartyCycleUnit", index)) then
				break
			end
		end
	end

	self:SetAttribute("fc-cycle-" .. prefix, index)
	if useRaid then
		self:RunAttribute("SelectGroupUnit", (index == 0) and "player" or ("raid" .. index))
	else
		self:RunAttribute("SelectGroupUnit", self:RunAttribute("PartyCycleUnit", index))
	end
]]
