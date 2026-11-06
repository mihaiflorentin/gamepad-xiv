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
	local topLeft, topRight = self:GetAttribute("fc-side-WL"), self:GetAttribute("fc-side-WR")
	local active
	local priority = self:GetAttribute("fc-priority") == 1
	local editing = self:GetAttribute("fc-editing") == 1
	local flyout = self:GetAttribute("fc-flyout")
	local clearStage = self:GetAttribute("fc-clear")

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
	local faceOnly = self:GetAttribute("fc-w4") == 1

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
		if clearStage == 2 then
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
			local row = active
			if faceOnly and i <= 4 then
				if active == "WL" then
					row = "L"
				elseif active == "WR" then
					row = "R"
				end
			end
			self:SetBindingClick(priority, key, "GamepadXIVCast" .. row .. i, "LeftButton")
		elseif layer == "SET" then
			self:SetBindingClick(priority, key, "GamepadXIVSet" .. i, "LeftButton")
		elseif layer == "L1" then
			self:SetBinding(priority, key, self:GetAttribute("l1-" .. key))
		else
			local action = self:GetAttribute("base-" .. key)
			if soft ~= "" then
				action = self:GetAttribute("soft-" .. key) or action
			end
			self:SetBinding(priority, key, action)
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
		else
			content:SetScale(selected and 1.15 or 1)
			content:SetAlpha(1)
		end
	end

	-- R1 + L2 is tab targeting; while R1 is held L2 selects nothing.
	if layer == "SET" then
		self:SetBinding(priority, "PADLTRIGGER", "TARGETNEARESTENEMY")
	else
		self:SetBindingClick(priority, "PADLTRIGGER", "GamepadXIVL2", "LeftButton")
	end
	if layer == "L1" then
		self:SetBinding(priority, "PADRTRIGGER", "TARGETPREVIOUSENEMY")
	else
		self:SetBindingClick(priority, "PADRTRIGGER", "GamepadXIVR2", "LeftButton")
	end

	if active then
		-- Forever opens its pet menus from R1 + R2 and L1 + L2, so pet classes keep those two free.
		local petChords = self:GetAttribute("fc-petChords") == 1
		local rightHeld = active == "R" or active == "WR"
		local leftHeld = active == "L" or active == "WL"
		self:SetBinding(priority, "PADRSHOULDER", (petChords and rightHeld) and "NONE" or "TARGETNEARESTENEMY")
		self:SetBinding(priority, "PADLSHOULDER", (petChords and leftHeld) and "NONE" or "TARGETPREVIOUSENEMY")
		self:SetBindingClick(priority, "PADBACK", "GamepadXIVEditToggle", "LeftButton")
		self:SetBindingClick(priority, "PADFORWARD", "GamepadXIVConfigToggle", "LeftButton")
	elseif layer == "L1" then
		-- FFXIV lands here while flying; dismounting in the air would drop the player.
		local sheathe = "TOGGLESHEATH"
		if IsFlying() then
			sheathe = "SITORSTAND"
		elseif IsMounted() then
			sheathe = "DISMOUNT"
		end
		self:SetBinding(priority, "PADRSHOULDER", sheathe)
		self:SetBindingClick(priority, "PADLSHOULDER", "GamepadXIVL1", "LeftButton")
		self:SetBinding(priority, "PADBACK", "TOGGLEUI")
		self:SetBinding(priority, "PADFORWARD", "SCREENSHOT")
	else
		self:SetBindingClick(priority, "PADRSHOULDER", "GamepadXIVR1", "LeftButton")
		self:SetBindingClick(priority, "PADLSHOULDER", "GamepadXIVL1", "LeftButton")
		self:SetBinding(priority, "PADBACK", "TOGGLEUIFOCUS")
		self:SetBinding(priority, "PADFORWARD", "OPENRADIAL")
	end

	self:SetBinding(priority, "PADLSTICK", self:GetAttribute("base-PADLSTICK"))
	if active then
		-- Trigger + R3 moves or removes an ability, standing in for FFXIV's trigger + touchpad.
		self:SetBindingClick(priority, "PADRSTICK", "GamepadXIVClearStart", "LeftButton")
		self:ClearBinding("PADLSTICKUP")
	elseif layer == "L1" then
		self:SetBindingClick(priority, "PADRSTICK", "GamepadXIVCursor", "LeftButton")
		self:SetBinding(priority, "PADLSTICKUP", "TOGGLEAUTORUN")
	else
		self:SetBindingClick(priority, "PADRSTICK", "GamepadXIVView", "LeftButton")
		self:ClearBinding("PADLSTICKUP")
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
]]

S.OnStateTarget = [[
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
		if self:GetAttribute("fc-clear") ~= 0 then
			self:RunAttribute("SetClear", 0)
		end
		self:RunAttribute("UpdateTargetBindings")
		self:RunAttribute("SetSoft", "")
	end
	self:RunAttribute("BindAll")
]]

-- Driver: edit mode. The slots show the chosen sides and stop casting, so clicks can edit them.
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
			isDoubleTap = 1
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

-- R1 outside a trigger layer: holds the set selection layer.
S.R1Click = [[
	local driver = self:GetFrameRef("driver")
	if down then
		driver:SetAttribute("fc-layer", "SET")
	elseif driver:GetAttribute("fc-layer") == "SET" then
		driver:SetAttribute("fc-layer", "BASE")
	end
	driver:RunAttribute("ApplyLayer")
]]

-- Set selection button: R1 + action key.
S.SetClick = [[
	if not down then
		return
	end
	local driver = self:GetFrameRef("driver")
	local set = self:GetAttribute("fc-setIndex")
	driver:SetAttribute("fc-formset-" .. driver:GetAttribute("fc-form"), set)
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

S.FlyoutCancelClick = [[
	if down then
		self:GetFrameRef("driver"):RunAttribute("CloseFlyout")
	end
]]

-- L1 held is a layer, like the triggers; a double tap steps through the party or raid.
S.L1Click = [[
	local driver = self:GetFrameRef("driver")
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
	else
		self:SetAttribute("fc-ticks", driver:GetAttribute("fc-tapTicks"))
	end
]]

-- D-pad up/down and L1 + left/right: soft target through the party or raid list.
S.CyclePreClick = [[
	if down then
		self:GetFrameRef("driver"):RunAttribute("CycleGroup", self:GetAttribute("fc-step"), self:GetAttribute("fc-raidOnly"))
	end
]]

-- Driver: moves the soft target. The first step in a party starts on the player, like FFXIV.
S.CycleGroup = [[
	local step, raidOnly = ...
	local useRaid = raidOnly == 1 and UnitExists("raid1")
	local prefix = useRaid and "raid" or "party"
	local count = useRaid and 40 or 4
	local index = self:GetAttribute("fc-cycle-" .. prefix) or 0

	if self:GetAttribute("fc-soft") == "" and not useRaid then
		index = 0
	else
		for _ = 0, count do
			index = index + step
			if index > count then
				index = 0
			elseif index < 0 then
				index = count
			end
			if index == 0 then
				if prefix == "party" then
					break
				end
			elseif UnitExists(prefix .. index) then
				break
			end
		end
	end

	self:SetAttribute("fc-cycle-" .. prefix, index)
	self:RunAttribute("SetSoft", (index == 0) and "player" or (prefix .. index))
]]
