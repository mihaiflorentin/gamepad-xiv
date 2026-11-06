-- Offline simulation of the secure state machine. Not loaded by the game.
-- Run from the addon folder with: lua5.1 tests/sim.lua
-- It runs the real snippets in a strict environment: any API the restricted
-- environment does not offer fails the run. It cannot prove in-game behaviour.

local ns = {}
local chunk = assert(loadfile("Snippets.lua"))
chunk("GamepadXIV", ns)
local S = ns.Snippets

local unitsThatExist = { player = true }

local ALLOWED = {
	UnitExists = function(unit) return unitsThatExist[unit] and 1 or nil end,
	GetActionInfo = function(slot)
		if unitsThatExist["flyout" .. tostring(slot)] then
			return "flyout", 77
		end
		return "spell"
	end,
	IsMounted = function() return unitsThatExist.mounted end,
	IsFlying = function() return unitsThatExist.flying end,
	IsSwimming = function() return unitsThatExist.swimming end,
	PlayerInCombat = function() return unitsThatExist.combat end,
	SecureCmdOptionParse = function(text)
		local unit, conditions = text:match("%[@([%w]+)(.-)%]")
		-- Like the game: a missing unit satisfies nodead, but never harm.
		local plate = unitsThatExist[unit]
		if conditions:find("harm", 1, true) and plate ~= "enemy" then return nil end
		return "1"
	end,
}

local function Compile(source, params)
	local fn = assert(loadstring("local " .. params .. " = ...\n" .. source))
	local env = {}
	setmetatable(env, {
		__index = function(_, key)
			if ALLOWED[key] then
				return ALLOWED[key]
			end
			return nil
		end,
	})
	setfenv(fn, env)
	return fn, env
end

-- Global reads of unknown names are only allowed for the one snippet variable we expect.
local function CheckGlobals(name, source)
	for line in source:gmatch("[^\n]+") do
		for word in line:gmatch("([%a_][%w_]*)%s*%(") do
			local isCall = not line:find("[:.]" .. word .. "%s*%(")
			local keyword = word == "if" or word == "elseif" or word == "function" or word == "and" or word == "or" or word == "not"
			if isCall and not keyword and not ALLOWED[word] then
				error(name .. ": call to non-whitelisted " .. word .. "\n" .. line)
			end
		end
	end
end

for name, source in pairs(S) do
	CheckGlobals(name, source)
end

local function NewFrame(name)
	local frame = { name = name, attrs = {}, refs = {}, bindings = {}, methods = {}, calls = {} }
	function frame:GetName() return self.name end
	function frame:GetAttribute(key) return self.attrs[key] end
	function frame:GetFrameRef(key) return assert(self.refs[key], "missing frame ref " .. key) end
	function frame:SetBinding(_, key, action)
		assert(action ~= nil, "nil action for " .. key)
		self.bindings[key] = action
	end
	function frame:SetBindingClick(_, key, target, button)
		self.bindings[key] = "CLICK " .. target .. ":" .. button
	end
	function frame:ClearBindings() self.bindings = {} end
	function frame:ClearBinding(key) self.bindings[key] = nil end
	function frame:EnableMouse(enable) self.mouseEnabled = enable end
	function frame:SetScale(scale) self.scale = scale end
	function frame:SetAlpha(alpha) self.alpha = alpha end
	function frame:CallMethod(method, ...)
		self.calls[method] = { ... }
	end
	function frame:RunAttribute(key, ...)
		local source = assert(self.attrs[key], "missing snippet " .. key)
		local fn = Compile(source, "self_placeholder")
		-- Snippets read their arguments with `...`, so run them with the frame as `self`.
		local wrapped = assert(loadstring("local self = ...; return (function(...)\n" .. source .. "\nend)(select(2, ...))"))
		setfenv(wrapped, setmetatable({ select = select }, { __index = ALLOWED }))
		return wrapped(self, ...)
	end
	function frame:SetAttribute(key, value)
		self.attrs[key] = value
		if self.onAttribute then
			self.onAttribute(key, value)
		end
	end
	return frame
end

local driver = NewFrame("GamepadXIVDriver")
for _, key in ipairs({ "ApplyLayer", "BindAll", "UpdateTargetBindings", "UpdateYield", "OnTrigger", "BeginEdit", "EndEdit", "SetSoft", "UpdateForm", "CycleGroup", "OpenFlyout", "CloseFlyout", "SetClear" }) do
	driver.attrs[key] = S[key]
end

local KEYS = { "PADDLEFT", "PADDUP", "PADDRIGHT", "PADDDOWN", "PAD3", "PAD4", "PAD2", "PAD1" }
local actionButtons = {}
local castButtons = {}
for i, key in ipairs(KEYS) do
	driver.attrs["key" .. i] = key
	driver.attrs["base-" .. key] = "BASE_" .. key
	driver.attrs["l1-" .. key] = "L1_" .. key
	for _, row in ipairs({ "L", "R", "WL", "WR" }) do
		actionButtons[row .. i] = NewFrame("GamepadXIVBtn" .. row .. i)
		driver.refs["btn" .. row .. i] = actionButtons[row .. i]
		castButtons[row .. i] = NewFrame("GamepadXIVCast" .. row .. i)
		driver.refs["cast" .. row .. i] = castButtons[row .. i]
	end
end
local contents = {}
for n, row in ipairs({ "L", "R", "WL", "WR" }) do
	driver.attrs["rowKey" .. n] = row
	contents[row] = NewFrame("content" .. row)
	driver.refs["content" .. row] = contents[row]
end
for side = 1, 16 do
	for i = 1, 8 do
		driver.attrs["slot-" .. side .. "-" .. i] = side * 100 + i
	end
end
driver.attrs["static-count"] = 1
driver.attrs["static-key1"] = "PADFORWARD"
driver.attrs["static-action1"] = "OPENRADIAL"
driver.attrs["ctx-PAD3-target"] = "INSPECT"
driver.attrs["ctx-PAD3-notarget"] = "TOGGLEWORLDMAP"
driver.attrs["ctx-PADLSTICK-target"] = "LOCK"
driver.attrs["ctx-PADLSTICK-notarget"] = "TOGGLESHEATH"
driver.attrs["ctx-PAD2-ground"] = "BACK"
driver.attrs["soft-PAD1"] = "SOFT_CONFIRM"
driver.attrs["soft-PAD2"] = "SOFT_CANCEL"
driver.attrs["fc-soft"] = ""
driver.attrs["fc-clear"] = 0
driver.attrs["fc-latch"] = ""
driver.attrs["fc-consumed"] = ""
driver.attrs["fc-triggerMode"] = "hold"
for key, value in pairs({
	["fc-off"] = 0, ["fc-vehicle"] = 0, ["fc-tapTicks"] = 2, ["fc-dim"] = 0.55,
	["fc-form"] = 0, ["fc-rawForm"] = 0, ["fc-formLink"] = 1,
	["fc-formset-0"] = 1, ["fc-formset-1"] = 5, ["fc-formset-2"] = 6, ["fc-formset-3"] = 7, ["fc-formset-4"] = 8,
	["fc-side-WL"] = 3, ["fc-side-WR"] = 4, ["fc-side-LR"] = 5, ["fc-side-RL"] = 6,
}) do
	driver.attrs[key] = value
end

driver:RunAttribute("UpdateYield")

-- Trigger buttons run the real click and attribute snippets.
local function NewTrigger(side)
	local trigger = NewFrame("GamepadXIV" .. side .. "2")
	trigger.attrs["fc-side"] = side
	trigger.attrs["fc-ready"] = 1
	trigger.attrs["fc-ticks"] = 0
	trigger.refs.driver = driver

	local attrEnv = setmetatable({}, { __index = ALLOWED })
	local attrFn = assert(loadstring("local self, name, value = ...\n" .. S.TriggerAttribute))
	setfenv(attrFn, attrEnv)
	trigger.onAttribute = function(key, value) attrFn(trigger, key, value) end

	local clickFn = assert(loadstring("local self, button, down = ...\n" .. S.TriggerClick))
	setfenv(clickFn, setmetatable({}, { __index = ALLOWED }))
	trigger.press = function() clickFn(trigger, "LeftButton", true) end
	trigger.release = function() clickFn(trigger, "LeftButton", false) end
	-- The state driver writes the fixed value 1 back on each 0.2s tick when it differs.
	trigger.tick = function()
		if trigger.attrs["fc-ready"] ~= 1 then
			trigger:SetAttribute("fc-ready", 1)
		end
	end
	return trigger
end

local L2, R2 = NewTrigger("L"), NewTrigger("R")

local failures = 0
local function Check(label, actual, expected)
	if actual == expected then
		print("ok   " .. label)
	else
		failures = failures + 1
		print("FAIL " .. label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

local function Layer() return driver.attrs["fc-layer"] end
local function SlotL(i) return actionButtons["L" .. i].attrs["action"] end
local function SlotR(i) return actionButtons["R" .. i].attrs["action"] end
local function SlotWL(i) return actionButtons["WL" .. i].attrs["action"] end
local function SlotWR(i) return actionButtons["WR" .. i].attrs["action"] end
local function Wait(trigger, ticks)
	for _ = 1, ticks do
		trigger.tick()
	end
end

Check("idle: base layer", Layer(), "BASE")
Check("idle: PAD1 has its base action", driver.bindings.PAD1, "BASE_PAD1")
Check("idle: triggers bound", driver.bindings.PADRTRIGGER, "CLICK GamepadXIVR2:LeftButton")
Check("idle: X opens the map without a target", driver.bindings.PAD3, "TOGGLEWORLDMAP")
Check("idle: L1 is its layer button", driver.bindings.PADLSHOULDER, "CLICK GamepadXIVL1:LeftButton")
Check("idle: both rows filled", SlotWR(1), 401)

R2.press()
Check("R2 hold: right layer", Layer(), "R")
Check("R2 hold: PAD1 fires right button 8", driver.bindings.PAD1, "CLICK GamepadXIVCastR8:LeftButton")
Check("R2 hold: right side shows set 1 right", SlotR(1), 201)
Check("R2 hold: bottom right grows", contents.R.scale, 1.15)
Check("R2 hold: the rest shrinks", contents.WR.scale, 0.78)
Check("R2 hold: R1 targets next enemy", driver.bindings.PADRSHOULDER, "TARGETNEARESTENEMY")
R2.release()
Check("R2 release: base layer", Layer(), "BASE")
Check("R2 release: PAD1 back to base", driver.bindings.PAD1, "BASE_PAD1")
Wait(R2, 3)

-- The user's main case: double tap and hold, cast several spells, release returns.
R2.press(); R2.release()
R2.press()
Check("double tap R2 hold: WXHB right", Layer(), "WR")
Check("top row: shows configured side", SlotWR(1), 401)
Check("WXHB: same keys, on the top row", driver.bindings.PAD1, "CLICK GamepadXIVCastWR8:LeftButton")
Check("bottom row untouched", SlotR(1), 201)
Check("selected bar grows", contents.WR.scale, 1.15)
Check("other bars shrink", contents.R.scale, 0.78)
Check("other bars dim", contents.L.alpha, 0.55)
Wait(R2, 5)
Check("WXHB: long hold stays on the bar", Layer(), "WR")
R2.release()
Check("WXHB release: back to base", Layer(), "BASE")
Check("WXHB release: all bars full size", contents.R.scale, 1)
Check("WXHB release: all bars full alpha", contents.L.alpha, 1)
Wait(R2, 3)

L2.press(); L2.release(); L2.press()
Check("double tap L2 hold: WXHB left", Layer(), "WL")
Check("WXHB left: top left bar", driver.bindings.PAD1, "CLICK GamepadXIVCastWL8:LeftButton")
Check("top left shows configured side", SlotWL(1), 301)
L2.release()
Wait(L2, 3)

-- Slow second press is a normal hold.
R2.press(); R2.release()
Wait(R2, 2)
R2.press()
Check("slow second press: normal right layer", Layer(), "R")
R2.release()
Wait(R2, 3)

-- One tick left: still a double tap (window spans 2 ticks).
R2.press(); R2.release()
Wait(R2, 1)
R2.press()
Check("press within window: WXHB", Layer(), "WR")
R2.release()
Wait(R2, 3)

-- Triple tap must not count the third press as a new double tap.
R2.press(); R2.release(); R2.press(); R2.release(); R2.press()
Check("third quick press: normal layer", Layer(), "R")
R2.release()
Wait(R2, 3)

L2.press(); R2.press()
Check("L2 then R2: expanded LR", Layer(), "LR")
Check("LR: shows configured side", SlotL(1), 501)
R2.release()
Check("releasing R2 returns to L", Layer(), "L")
Check("L: side restored", SlotL(1), 101)
L2.release()
Wait(L2, 3); Wait(R2, 3)

R2.press(); L2.press()
Check("R2 then L2: expanded RL", Layer(), "RL")
Check("RL: shows configured side", SlotR(1), 601)
L2.release()
Check("releasing L2 returns to R", Layer(), "R")
R2.release()
Wait(L2, 3); Wait(R2, 3)

L2.press(); R2.press(); L2.release()
Check("releasing the first trigger keeps the other", Layer(), "R")
R2.release()
Wait(L2, 3); Wait(R2, 3)

-- R1 set selection.
local function RunButton(snippet, attrs)
	local button = NewFrame("button")
	button.refs.driver = driver
	for key, value in pairs(attrs or {}) do
		button.attrs[key] = value
	end
	local fn = assert(loadstring("local self, button, down = ...\n" .. snippet))
	setfenv(fn, setmetatable({}, { __index = ALLOWED }))
	return button, fn
end

local r1, r1Fn = RunButton(S.R1Click)
r1Fn(r1, "LeftButton", true)
Check("R1 hold: set layer", Layer(), "SET")
Check("R1 hold: PAD1 picks set 8", driver.bindings.PAD1, "CLICK GamepadXIVSet8:LeftButton")
local setButton, setFn = RunButton(S.SetClick, { ["fc-setIndex"] = 4 })
setFn(setButton, "LeftButton", true)
Check("set 4 selected", driver.attrs["fc-formset-0"], 4)
Check("R1 hold: L2 is tab target", driver.bindings.PADLTRIGGER, "TARGETNEARESTENEMY")
Check("set 4: left side", SlotL(1), 701)
r1Fn(r1, "LeftButton", false)
Check("R1 release: base layer", Layer(), "BASE")
Check("R1 release: L2 selects again", driver.bindings.PADLTRIGGER, "CLICK GamepadXIVL2:LeftButton")
Check("top row does not follow the set", SlotWL(1), 301)
R2.press()
Check("set 4: R2 layer uses its right side", SlotR(1), 801)
R2.release()
driver.attrs["fc-formset-0"] = 1
driver:RunAttribute("ApplyLayer")
Wait(R2, 3)

-- Forms and stances change the bottom row and remember their own set.
local formFn = assert(loadstring("local self, stateid, newstate = ...\n" .. S.OnStateForm))
setfenv(formFn, setmetatable({}, { __index = ALLOWED }))
formFn(driver, "fcform", 1)
Check("form 1: bottom row uses its set", SlotL(1), 901)
Check("form 1: top row unchanged", SlotWL(1), 301)
r1Fn(r1, "LeftButton", true)
setFn(setButton, "LeftButton", true)
r1Fn(r1, "LeftButton", false)
Check("form 1: R1 changes its own set", driver.attrs["fc-formset-1"], 4)
Check("form 1: normal set kept", driver.attrs["fc-formset-0"], 1)
Check("form 1: bottom row follows", SlotL(1), 701)
driver.attrs["fc-formLink"] = 0
driver:RunAttribute("UpdateForm")
Check("link off: normal set", SlotL(1), 101)
driver.attrs["fc-formLink"] = 1
driver:RunAttribute("UpdateForm")
Check("link on: form set again", SlotL(1), 701)
formFn(driver, "fcform", 0)
Check("no form: normal set back", SlotL(1), 101)
driver.attrs["fc-formset-1"] = 5

-- Target-dependent bindings.
unitsThatExist.target = true
driver:RunAttribute("UpdateTargetBindings")
driver:RunAttribute("ApplyLayer")
Check("with target: X is the inspect button", driver.bindings.PAD3, "INSPECT")
Check("with target: L3 locks on", driver.bindings.PADLSTICK, "LOCK")
unitsThatExist.target = nil
driver:RunAttribute("UpdateTargetBindings")
driver:RunAttribute("ApplyLayer")
Check("no target: L3 sheathes", driver.bindings.PADLSTICK, "TOGGLESHEATH")

-- A plain rebind while a trigger is held keeps the layer.
R2.press(); R2.release(); R2.press()
Check("rebind setup: WXHB held", Layer(), "WR")
driver:RunAttribute("UpdateYield")
Check("rebind keeps WXHB", Layer(), "WR")
Check("rebind keeps its keys", driver.bindings.PAD1, "CLICK GamepadXIVCastWR8:LeftButton")
R2.release()
Wait(R2, 3)

-- R1 released while a trigger is held does not cancel the trigger layer.
r1Fn(r1, "LeftButton", true)
R2.press()
r1Fn(r1, "LeftButton", false)
Check("R1 up under R2 keeps the right layer", Layer(), "R")
R2.release()
Wait(R2, 3)

-- Trigger + Start opens the settings, Start alone the radial.
Check("Start: radial", driver.bindings.PADFORWARD, "OPENRADIAL")
R2.press()
Check("R2 + Start: settings", driver.bindings.PADFORWARD, "CLICK GamepadXIVConfigToggle:LeftButton")
R2.release()
Wait(R2, 3)

-- Edit mode shows any side on the bar and stops the slots from casting.
actionButtons.L1.attrs.type = "action"
driver.attrs["fc-edit-left"] = 3
driver.attrs["fc-edit-right"] = 4
driver:RunAttribute("BeginEdit")
Check("edit: left shows chosen side", SlotL(1), 301)
Check("edit: right shows chosen side", SlotR(1), 401)
Check("edit: slots do not cast", actionButtons.L1.attrs.type, nil)
Check("edit: keys do not cast", castButtons.WR8.attrs.type, nil)
driver.attrs["fc-edit-left"] = 9
driver:RunAttribute("ApplyLayer")
Check("edit: side can change", SlotL(1), 901)
R2.press()
Check("edit: a held trigger does not change the shown side", SlotR(1), 401)
R2.release()
Wait(R2, 3)

-- Entering combat always ends edit mode and restores casting.
local combatFn = assert(loadstring("local self, stateid, newstate = ...\n" .. S.OnStateCombat))
setfenv(combatFn, setmetatable({}, { __index = ALLOWED }))
combatFn(driver, "fccombat", 0)
Check("combat end: editing untouched", driver.attrs["fc-editing"], 1)
combatFn(driver, "fccombat", 1)
Check("combat: edit mode ended", driver.attrs["fc-editing"], 0)
Check("combat: slots cast again", actionButtons.L1.attrs.type, "action")
Check("combat: keys cast again", castButtons.WR8.attrs.type, "action")
Check("cast buttons follow the slots", castButtons.R1.attrs.action, SlotR(1))
Check("combat: normal side restored", SlotL(1), 101)
Check("combat: visuals notified", driver.calls.OnEditEnded ~= nil, true)

-- A vehicle also ends edit mode.
driver:RunAttribute("BeginEdit")
driver.attrs["fc-vehicle"] = 1
driver:RunAttribute("UpdateYield")
Check("vehicle: edit mode ended", driver.attrs["fc-editing"], 0)
driver.attrs["fc-vehicle"] = 0
driver:RunAttribute("UpdateYield")

-- Vehicles hand everything back to Forever.
Check("active: action buttons take the mouse", actionButtons.L1.mouseEnabled, true)
R2.press()
driver.attrs["fc-vehicle"] = 1
driver:RunAttribute("UpdateYield")
Check("vehicle: no bindings kept", next(driver.bindings), nil)
Check("vehicle: layer reset", Layer(), "BASE")
Check("vehicle: yield flagged", driver.calls.OnYieldChanged[1], true)
Check("vehicle: invisible buttons ignore the mouse", actionButtons.L1.mouseEnabled, false)
driver.attrs["fc-vehicle"] = 0
driver:RunAttribute("UpdateYield")
Check("vehicle end: rebound", driver.bindings.PADRTRIGGER, "CLICK GamepadXIVR2:LeftButton")
R2.release()
Wait(R2, 3)

-- Party cycling is a soft target and starts on the player, like FFXIV.
local function NewCycle(step, raidOnly)
	local button, fn = RunButton(S.CyclePreClick, { ["fc-step"] = step, ["fc-raidOnly"] = raidOnly and 1 or 0 })
	return function()
		fn(button, "LeftButton", true)
		return driver.attrs["fc-soft"]
	end
end

local function ClearSoft() driver:RunAttribute("SetSoft", "") end

unitsThatExist.party1 = true
unitsThatExist.party2 = true
local nextParty, prevParty = NewCycle(1), NewCycle(-1)
Check("party: starts on the player", nextParty(), "player")
Check("party: next 1", nextParty(), "party1")
Check("party: next 2", nextParty(), "party2")
Check("party: wraps to self", nextParty(), "player")
Check("party: previous wraps to last", prevParty(), "party2")

-- Soft target: slots aim at it, the hard target is untouched, A and B handle it.
Check("soft: casts aim at it", castButtons.R1.attrs.unit, "party2")
Check("soft: A confirms", driver.bindings.PAD1, "SOFT_CONFIRM")
Check("soft: B cancels", driver.bindings.PAD2, "SOFT_CANCEL")

local actionButton, preFn = RunButton(S.ActionPre)
local _, message = preFn(actionButton, "LeftButton", true)
Check("soft: a press asks for the post step", message, "soft")
local postFn = assert(loadstring("local self, message, button = ...\n" .. S.ActionPost))
setfenv(postFn, setmetatable({}, { __index = ALLOWED }))
postFn(actionButton, "soft", "LeftButton")
Check("soft: ends after the action", driver.attrs["fc-soft"], "")
Check("soft: slots aim at the real target again", castButtons.R1.attrs.unit, nil)
Check("soft: A back to confirm", driver.bindings.PAD1, "BASE_PAD1")
local _, noMessage = preFn(actionButton, "LeftButton", true)
Check("no soft: no post step", noMessage, nil)

-- A soft target that is gone falls back to the real target.
nextParty()
nextParty()
Check("gone soft: setup", driver.attrs["fc-soft"], "party1")
unitsThatExist.party1 = nil
local _, goneMessage = preFn(actionButton, "LeftButton", true)
Check("gone soft: no post step", goneMessage, nil)
Check("gone soft: cleared", driver.attrs["fc-soft"], "")
Check("gone soft: casts aim at the real target", castButtons.R1.attrs.unit, nil)
unitsThatExist.party1 = true

nextParty()
local confirm, confirmFn = RunButton(S.SoftConfirmPreClick)
confirmFn(confirm, "LeftButton", true)
Check("soft confirm: targets the unit", confirm.attrs.unit, "player")
Check("soft confirm: soft ended", driver.attrs["fc-soft"], "")
nextParty()
local cancel, cancelFn = RunButton(S.SoftCancelClick)
cancelFn(cancel, "LeftButton", true)
Check("soft cancel: ended", driver.attrs["fc-soft"], "")

driver.attrs["fc-cycle-party"] = 0
unitsThatExist.raid1 = true
unitsThatExist.raid2 = true
local nextRaid = NewCycle(1, true)
Check("raid: next 1", nextRaid(), "raid1")
Check("raid: next 2", nextRaid(), "raid2")
Check("raid: wraps past the end", nextRaid(), "raid1")
ClearSoft()
Check("party buttons stay on party in a raid", nextParty(), "player")
unitsThatExist.raid1 = nil
unitsThatExist.raid2 = nil
ClearSoft()
driver.attrs["fc-cycle-party"] = 0
Check("alliance buttons fall back to party outside a raid", NewCycle(1, true)(), "player")
ClearSoft()

-- Double tap L1 selects party members.
do
	local l1 = NewFrame("GamepadXIVL1")
	l1.attrs["fc-ready"] = 1
	l1.attrs["fc-ticks"] = 0
	l1.refs.driver = driver
	local attrFn = assert(loadstring("local self, name, value = ...\n" .. S.TriggerAttribute))
	setfenv(attrFn, setmetatable({}, { __index = ALLOWED }))
	l1.onAttribute = function(key, value) attrFn(l1, key, value) end
	local clickFn = assert(loadstring("local self, button, down = ...\n" .. S.L1Click))
	setfenv(clickFn, setmetatable({}, { __index = ALLOWED }))
	local function Press() clickFn(l1, "LeftButton", true) end
	local function Release() clickFn(l1, "LeftButton", false) end
	local function Tap()
		Press()
		Release()
	end
	local function L1Wait(ticks)
		for _ = 1, ticks do
			if l1.attrs["fc-ready"] ~= 1 then
				l1:SetAttribute("fc-ready", 1)
			end
		end
	end
	ClearSoft()
	driver.attrs["fc-cycle-party"] = 0
	Tap()
	Check("L1 single tap: nothing selected", driver.attrs["fc-soft"], "")
	Tap()
	Check("L1 double tap: starts on the player", driver.attrs["fc-soft"], "player")
	L1Wait(4)
	Tap()
	Check("L1 slow tap: selection unchanged", driver.attrs["fc-soft"], "player")
	L1Wait(4)
	Tap(); Tap()
	Check("L1 double tap again: next member", driver.attrs["fc-soft"], "party1")
	L1Wait(4)
	Tap(); L1Wait(3); Tap()
	Check("L1 slow second tap: unchanged", driver.attrs["fc-soft"], "party1")
	L1Wait(4)

	-- Held L1 is a layer.
	Check("no L1: left stick forward unbound", driver.bindings.PADLSTICKUP, nil)
	Check("no L1: R3 is the view", driver.bindings.PADRSTICK, "CLICK GamepadXIVView:LeftButton")
	Press()
	Check("L1 held: layer", Layer(), "L1")
	Check("L1 held: left stick forward auto-runs", driver.bindings.PADLSTICKUP, "TOGGLEAUTORUN")
	Check("L1 held: D-pad and face buttons change", driver.bindings.PAD1, "L1_PAD1")
	Check("L1 held: R2 targets", driver.bindings.PADRTRIGGER, "TARGETPREVIOUSENEMY")
	Check("L1 held: R3 is the cursor", driver.bindings.PADRSTICK, "CLICK GamepadXIVCursor:LeftButton")
	Check("L1 held: visuals told", driver.calls.OnLayerChanged[1], "L1")
	Check("L1 held: on foot R1 sheathes", driver.bindings.PADRSHOULDER, "TOGGLESHEATH")
	unitsThatExist.mounted = true
	driver:RunAttribute("ApplyLayer")
	Check("L1 held: mounted R1 dismounts", driver.bindings.PADRSHOULDER, "DISMOUNT")
	unitsThatExist.flying = true
	driver:RunAttribute("ApplyLayer")
	Check("L1 held: flying R1 descends", driver.bindings.PADRSHOULDER, "SITORSTAND")
	unitsThatExist.flying = nil
	unitsThatExist.mounted = nil
	Release()
	Check("L1 release: base", Layer(), "BASE")
	Check("L1 release: stick free", driver.bindings.PADLSTICKUP, nil)
	Check("L1 release: R2 selects", driver.bindings.PADRTRIGGER, "CLICK GamepadXIVR2:LeftButton")
	L1Wait(4)
	R2.press()
	Press()
	Check("L1 under R2: layer kept", Layer(), "R")
	Release()
	Check("L1 release under R2: layer kept", Layer(), "R")
	R2.release()
	Wait(R2, 3)
	L1Wait(4)
	ClearSoft()
	driver.attrs["fc-cycle-party"] = 0
end

-- A flyout opens the controller picker, even after the trigger is released.
do
	driver.attrs["fc-flyout"] = ""
	driver.attrs["flyKey-PAD1"] = 1
	driver.attrs["flyKey-PAD3"] = 2
	driver.attrs["fly-77-count"] = 2
	driver.attrs["fly-77-1"] = 1001
	driver.attrs["fly-77-2"] = 1002
	for n = 1, 2 do
		driver.refs["flyoutPick" .. n] = NewFrame("pick" .. n)
	end
	local cast, castFn = RunButton(S.ActionPre, { action = 208 })
	unitsThatExist.flyout208 = true
	R2.press()
	Check("flyout: press cancels the normal click", castFn(cast, "LeftButton", true), false)
	Check("flyout: picker open", driver.attrs["fc-flyout"], 77)
	Check("flyout: first choice on A", driver.bindings.PAD1, "CLICK GamepadXIVFlyoutPick1:LeftButton")
	Check("flyout: second choice on X", driver.bindings.PAD3, "CLICK GamepadXIVFlyoutPick2:LeftButton")
	Check("flyout: B cancels", driver.bindings.PAD2, "CLICK GamepadXIVFlyoutCancel:LeftButton")
	Check("flyout: unused key is free", driver.bindings.PAD4, nil)
	Check("flyout: spell loaded", driver.refs.flyoutPick1.attrs.spell, 1001)
	R2.release()
	Check("flyout: trigger release keeps the picker", driver.bindings.PAD1, "CLICK GamepadXIVFlyoutPick1:LeftButton")
	local pick, pickPre = RunButton(S.FlyoutPickPre)
	local _, closeMessage = pickPre(pick, "LeftButton", true)
	Check("flyout: a pick asks to close", closeMessage, "close")
	local pickPost = assert(loadstring("local self, message, button = ...\n" .. S.FlyoutPickPost))
	setfenv(pickPost, setmetatable({}, { __index = ALLOWED }))
	pickPost(pick, "close", "LeftButton")
	Check("flyout: closed after a pick", driver.attrs["fc-flyout"], "")
	Check("flyout: keys are back", driver.bindings.PAD1, "BASE_PAD1")
	Check("flyout: panel told", driver.calls.OnFlyoutChanged[1], "")
	driver:RunAttribute("OpenFlyout", 77)
	local cancelButton, cancelFlyout = RunButton(S.FlyoutCancelClick)
	cancelFlyout(cancelButton, "LeftButton", true)
	Check("flyout: B closed it", driver.attrs["fc-flyout"], "")
	driver:RunAttribute("OpenFlyout", 99)
	Check("flyout: unknown flyout stays closed", driver.attrs["fc-flyout"], "")
	unitsThatExist.flyout208 = nil
	Wait(R2, 3)
end

-- Trigger + R3 removes an ability: choose the slot, then confirm.
do
	R2.press()
	Check("clear: R2 + R3 starts it", driver.bindings.PADRSTICK, "CLICK GamepadXIVClearStart:LeftButton")
	local start, startFn = RunButton(S.ClearStartClick)
	startFn(start, "LeftButton", true)
	Check("clear: asks for the slot", driver.attrs["fc-clear"], 1)
	Check("clear: panel told", driver.calls.OnClearChanged[1], 1)
	Check("clear: slots do not cast", castButtons.R8.attrs.type, nil)
	Check("clear: the held bar's keys select", driver.bindings.PAD1, "CLICK GamepadXIVCastR8:LeftButton")
	local cast, castFn = RunButton(S.ActionPre, { action = 208 })
	unitsThatExist.flyout208 = true
	Check("clear: a flyout slot does not open", castFn(cast, "LeftButton", true), nil)
	unitsThatExist.flyout208 = nil
	R2.release()
	Check("clear: no trigger, B cancels", driver.bindings.PAD2, "CLICK GamepadXIVClearCancel:LeftButton")
	Check("clear: no trigger, others stay", driver.bindings.PAD1, "BASE_PAD1")
	driver:RunAttribute("SetClear", 2)
	Check("clear choice: A moves", driver.bindings.PAD1, "CLICK GamepadXIVSlotMove:LeftButton")
	Check("clear choice: X removes", driver.bindings.PAD3, "CLICK GamepadXIVClearConfirm:LeftButton")
	Check("clear choice: B cancels", driver.bindings.PAD2, "CLICK GamepadXIVClearCancel:LeftButton")
	Check("clear choice: other keys free", driver.bindings.PAD4, nil)
	Wait(R2, 3)
	R2.press()
	Check("clear choice: a trigger changes nothing", driver.bindings.PAD1, "CLICK GamepadXIVSlotMove:LeftButton")
	R2.release()
	Wait(R2, 3)
	driver:RunAttribute("SetClear", 3)
	Check("move: slots still do not cast", castButtons.R8.attrs.type, nil)
	Check("move: B cancels", driver.bindings.PAD2, "CLICK GamepadXIVClearCancel:LeftButton")
	R2.press()
	Check("move: the held bar's keys select", driver.bindings.PAD1, "CLICK GamepadXIVCastR8:LeftButton")
	R2.release()
	Wait(R2, 3)
	local moveR1, moveR1Fn = RunButton(S.R1Click)
	moveR1Fn(moveR1, "LeftButton", true)
	Check("move: R1 + B still picks a set", driver.bindings.PAD2, "CLICK GamepadXIVSet7:LeftButton")
	moveR1Fn(moveR1, "LeftButton", false)
	local cancelClear, cancelClearFn = RunButton(S.ClearCancelClick)
	cancelClearFn(cancelClear, "LeftButton", true)
	Check("clear: cancelled", driver.attrs["fc-clear"], 0)
	Check("clear: slots cast again", castButtons.R8.attrs.type, "action")
	Check("clear: keys back", driver.bindings.PAD1, "BASE_PAD1")
	driver:RunAttribute("SetClear", 1)
	local combatClear = assert(loadstring("local self, stateid, newstate = ...\n" .. S.OnStateCombat))
	setfenv(combatClear, setmetatable({}, { __index = ALLOWED }))
	combatClear(driver, "fccombat", 1)
	Check("clear: combat ends it", driver.attrs["fc-clear"], 0)
	unitsThatExist.combat = true
	startFn(start, "LeftButton", true)
	Check("clear: cannot start in combat", driver.attrs["fc-clear"], 0)
	unitsThatExist.combat = nil
end

-- Sets 1-3 keep Forever's page on the same number.
do
	driver.attrs["fc-numPages"] = 3
	driver.attrs["fc-page"] = 1
	local function PickSet(set)
		local button, fn = RunButton(S.SetClick, { ["fc-setIndex"] = set })
		return fn(button, "LeftButton", true), button.attrs.type
	end
	local mouseButton, clickType = PickSet(2)
	Check("page: forward one", mouseButton, "LeftButton")
	Check("page: clicks Forever's button", clickType, "click")
	Check("page: tracked", driver.attrs["fc-page"], 2)
	mouseButton = PickSet(1)
	Check("page: back one", mouseButton, "RightButton")
	mouseButton = PickSet(3)
	Check("page: 1 to 3 goes back", mouseButton, "RightButton")
	mouseButton, clickType = PickSet(3)
	Check("page: same page, no click", clickType, nil)
	mouseButton, clickType = PickSet(6)
	Check("page: set above 3, no click", clickType, nil)
	Check("page: unchanged above 3", driver.attrs["fc-page"], 3)
	PickSet(1)
	driver.attrs["fc-page"] = nil
	driver:RunAttribute("ApplyLayer")
end

-- Flying and swimming: B descends.
Check("ground: B cancels", driver.bindings.PAD2, "BACK")
unitsThatExist.flying = true
driver:RunAttribute("UpdateTargetBindings")
driver:RunAttribute("ApplyLayer")
Check("flying: B descends", driver.bindings.PAD2, "SITORSTAND")
unitsThatExist.flying = nil
unitsThatExist.swimming = true
driver:RunAttribute("UpdateTargetBindings")
driver:RunAttribute("ApplyLayer")
Check("swimming: B dives", driver.bindings.PAD2, "SITORSTAND")
unitsThatExist.swimming = nil
driver:RunAttribute("UpdateTargetBindings")
driver:RunAttribute("ApplyLayer")

-- WXHB with face buttons only.
driver.attrs["fc-w4"] = 1
R2.press(); R2.release(); R2.press()
Check("w4: D-pad stays on the bottom row", driver.bindings.PADDLEFT, "CLICK GamepadXIVCastR1:LeftButton")
Check("w4: face buttons use the top row", driver.bindings.PAD1, "CLICK GamepadXIVCastWR8:LeftButton")
R2.release()
driver.attrs["fc-w4"] = 0
Wait(R2, 3)

-- Toggle mode.
driver.attrs["fc-triggerMode"] = "toggle"
R2.press(); R2.release()
Check("toggle: press latches", Layer(), "R")
Wait(R2, 3)
R2.press(); R2.release()
Check("toggle: second press unlatches", Layer(), "BASE")
Wait(R2, 3)
R2.press(); R2.release(); R2.press()
Check("toggle: double tap selects WXHB", Layer(), "WR")
R2.release()
Check("toggle: WXHB stays after release", Layer(), "WR")
Wait(R2, 3)
Check("toggle: WXHB stays over time", Layer(), "WR")
R2.press(); R2.release()
Check("toggle: next press leaves WXHB", Layer(), "BASE")
Wait(R2, 3)
L2.press(); L2.release(); L2.press(); L2.release()
Check("toggle: WXHB left stays", Layer(), "WL")
Wait(L2, 3)
R2.press(); R2.release()
Check("toggle: other trigger replaces WXHB", Layer(), "R")
Wait(R2, 3)
R2.press(); R2.release()
Check("toggle: and clears", Layer(), "BASE")
Wait(R2, 3)
R2.press()
Wait(R2, 3)
R2.release()
Check("toggle: long press still latches", Layer(), "R")
Wait(R2, 3)
L2.press(); L2.release()
Check("toggle: other trigger takes over", Layer(), "L")
Wait(L2, 3)
L2.press(); L2.release()
Check("toggle: back to base", Layer(), "BASE")
Wait(L2, 3)

-- Mixed mode.
driver.attrs["fc-triggerMode"] = "mixed"
R2.press()
Check("mixed: holding selects", Layer(), "R")
Wait(R2, 3)
R2.release()
Check("mixed: long hold release returns", Layer(), "BASE")
Wait(R2, 3)
R2.press(); R2.release()
Check("mixed: quick tap latches", Layer(), "R")
Wait(R2, 3)
R2.press()
Check("mixed: next press unlatches", Layer(), "BASE")
R2.release()
Check("mixed: its release does not latch again", Layer(), "BASE")
Wait(R2, 3)
R2.press(); R2.release(); R2.press()
Check("mixed: double tap holds WXHB", Layer(), "WR")
R2.release()
Check("mixed: WXHB release clears", Layer(), "BASE")
driver.attrs["fc-triggerMode"] = "hold"
Wait(R2, 3)

-- Hunters and warlocks keep Forever's pet chords free.
driver.attrs["fc-petChords"] = 1
R2.press()
Check("pet chords: R2 leaves R1 free", driver.bindings.PADRSHOULDER, "NONE")
Check("pet chords: R2 + L1 still targets", driver.bindings.PADLSHOULDER, "TARGETPREVIOUSENEMY")
R2.release()
Wait(R2, 3)
L2.press()
Check("pet chords: L2 leaves L1 free", driver.bindings.PADLSHOULDER, "NONE")
Check("pet chords: L2 + R1 still targets", driver.bindings.PADRSHOULDER, "TARGETNEARESTENEMY")
L2.release()
Wait(L2, 3)
driver.attrs["fc-petChords"] = 0

print(failures == 0 and "ALL PASSED" or (failures .. " FAILED"))
os.exit(failures == 0 and 0 or 1)
