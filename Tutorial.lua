local _, ns = ...

-- A guided tour of the addon, one feature a step. It shows once per account (GamepadXIVAccountDB),
-- a few seconds after the first login with the layout active, and again from the settings, the
-- minimap menu or /gxiv tutorial.
--
-- Each step spotlights the part of the screen it is about (the screen around it dims) and shows a
-- controller with the buttons to press lit up and pulsing, drawn with the game's icons for the
-- controller in use. Steps are built when shown, from the settings, so they name the buttons the
-- player has now and leave out features that are off.
--
-- {PAD1} next, {PAD2} back, {PAD3} chapters and {PAD4} close come from the driver, and only while
-- no trigger or shoulder is held (fc-tutorial in ApplyLayer), so the buttons a step teaches can be
-- tried while it shows. The chapter list lists every step to jump to one; while it is open the
-- D-pad moves through it. Combat pauses the tour; it comes back when combat ends.

local AUTO_START_DELAY = 4
local ICON_SIZE = 28
local GLOW_SIZE = 62
local ART_SCALE = 0.9 -- positions are in a 512 x 256 layout (Media/controller.tga is twice that); drawn at 461 x 230
local CALLOUT_WIDTH = 500
local GOLD = { 1, 0.82, 0 }

-- Where each button sits on Media/controller.tga, in its pixels (see tools/make_controller_art.py).
local BUTTON_POSITIONS = {
	PADLTRIGGER = { 136, 22 }, PADRTRIGGER = { 376, 22 },
	PADLSHOULDER = { 136, 60 }, PADRSHOULDER = { 376, 60 },
	PADDUP = { 134, 86 }, PADDDOWN = { 134, 138 }, PADDLEFT = { 108, 112 }, PADDRIGHT = { 160, 112 },
	PAD4 = { 378, 86 }, PAD1 = { 378, 138 }, PAD3 = { 352, 112 }, PAD2 = { 404, 112 },
	PADLSTICK = { 204, 168 }, PADRSTICK = { 308, 168 },
	PADBACK = { 222, 104 }, PADFORWARD = { 290, 104 },
}
local DPAD = { "PADDUP", "PADDRIGHT", "PADDDOWN", "PADDLEFT" }
-- The button that picks each set with R1 (1-4 on the face buttons, 5-8 on the D-pad), from Core.
local SET_KEYS = {}
for index, key in ipairs(ns.KEYS or {}) do
	SET_KEYS[ns.SET_BY_KEY[index]] = key
end
local FACE = { "PAD4", "PAD2", "PAD1", "PAD3" }

local overlay, callout, art
local chapters -- the list of steps beside the callout
local CHAPTER_WIDTH = 230
local CHAPTER_ROW = 18
local steps, current = {}, 1
local paused = false

local function AccountDB()
	GamepadXIVAccountDB = GamepadXIVAccountDB or {}
	return GamepadXIVAccountDB
end

local function Text(text, size)
	return ns.ButtonText(text, size or 18)
end

-- The name of a setting's choice, from a list of { key, label } entries.
local function ChoiceLabel(list, key)
	for _, entry in ipairs(list or {}) do
		if entry[1] == key then
			return entry[2]
		end
	end
	return key
end

-- The button or combination that is set to do an action of ns.STICK_ACTIONS, as text and keys.
local function ComboFor(action)
	local db = ns.db
	local combos = {
		{ db.r3Action, "{PADRSTICK}", { "PADRSTICK" } },
		{ db.l3Action, "{PADLSTICK}", { "PADLSTICK" } },
		{ db.r1R3Action, "{PADRSHOULDER} + {PADRSTICK}", { "PADRSHOULDER", "PADRSTICK" } },
		{ db.l1R3Action, "{PADLSHOULDER} + {PADRSTICK}", { "PADLSHOULDER", "PADRSTICK" } },
		{ db.r1L3Action, "{PADRSHOULDER} + {PADLSTICK}", { "PADRSHOULDER", "PADLSTICK" } },
		{ db.l1R1Action, "{PADLSHOULDER} + {PADRSHOULDER}", { "PADLSHOULDER", "PADRSHOULDER" } },
		{ db.l1StickUpAction, "{PADLSHOULDER} + left stick forward", { "PADLSHOULDER", "PADLSTICK" } },
	}
	for _, combo in ipairs(combos) do
		if combo[1] == action then
			return combo[2], combo[3]
		end
	end
end

-- What a step acts out on the controller: actions on buttons, at a time in seconds from the start of
-- a scene that loops. A tap is a quick press, a hold presses and stays down, a move pushes a stick.
local function Tap(key, at) return { key = key, kind = "tap", at = at } end
local function Double(key, at) return { key = key, kind = "double", at = at } end
local function Hold(key, at, len) return { key = key, kind = "hold", at = at, len = len or 1.2 } end
local function DoubleHold(key, at, len) return { key = key, kind = "doublehold", at = at, len = len or 1.2 } end
local function Move(key, at, dx, dy, len) return { key = key, kind = "move", at = at, dx = dx, dy = dy, len = len or 0.5 } end
local function UpDown(key, at) return { key = key, kind = "updown", at = at } end
-- Marks actions as part of numbered step `n`, so the badge beside the button shows the step's number.
-- Returns them as a group, which a scene's list flattens.
local function S(n, ...)
	local group = { isGroup = true }
	for i = 1, select("#", ...) do
		local action = select(i, ...)
		action.step = n
		group[i] = action
	end
	return group
end

local function Flatten(lit)
	local flat = {}
	for _, entry in ipairs(lit or {}) do
		if entry.isGroup then
			for _, action in ipairs(entry) do
				tinsert(flat, action)
			end
		else
			tinsert(flat, entry)
		end
	end
	return flat
end

local function Sides(...)
	local frames = {}
	local root = ns.root
	if root and root.sides then
		for i = 1, select("#", ...) do
			tinsert(frames, root.sides[(select(i, ...))])
		end
	end
	return frames
end

local RING_DIRECTIONS = { "right", "up and right", "up", "up and left", "left", "down and left", "down", "down and right" }

-- Checks -------------------------------------------------------------------------------------------
-- A page can check that the player did what it teaches: `checks`, one per numbered step, or `goal`
-- when it has no steps. A check gets the page's state ({ since = when the previous step was done })
-- and returns true once its step is done; a step without a check is done along with the next one.
-- Next stays locked until every check has passed. Only things that can be done anywhere are checked.

local seen = {} -- when things the checks look for last happened: cast = { at, side }, slot, jump

local function Now()
	return GetTime and GetTime() or 0
end

-- The driver's input layer: BASE, L, R, LR, RL, WL, WR, SET (R1 held) or L1.
local function Layer()
	local driver = _G.GamepadXIVDriver
	return driver and driver.GetAttribute and driver:GetAttribute("fc-layer") or "BASE"
end

local function ClearStage()
	local driver = _G.GamepadXIVDriver
	return driver and driver.GetAttribute and driver:GetAttribute("fc-clear") or 0
end

local function Shown(name)
	local frame = _G[name]
	return frame ~= nil and frame.IsShown ~= nil and frame:IsShown() or false
end

-- A slot of the cross hotbar was pressed since `since`, on one of `sides` if given.
local function CastSince(since, sides)
	local cast = seen.cast
	return cast ~= nil and cast.at >= since and (not sides or tContains(sides, cast.side))
end

-- The windows the ring's entries open; none shown means the player closed what the ring opened.
local RING_WINDOWS = { "CommunitiesFrame", "CharacterFrame", "PlayerSpellsFrame", "SpellBookFrame", "WorldMapFrame",
	"ContainerFrameCombinedBags", "GameMenuFrame", "CollectionsJournal", "PVEFrame", "LFGParentFrame", "FriendsFrame",
	"ProfessionsBookFrame", "PlayerTalentFrame", "ClassTalentFrame", "QuestLogFrame", "CalendarFrame", "TimeManagerFrame",
	"GamepadXIVConfigFrame" }

local function AnyWindowShown()
	for _, name in ipairs(RING_WINDOWS) do
		if Shown(name) then
			return true
		end
	end
	return false
end

local function SpellbookShown()
	return Shown("PlayerSpellsFrame") or Shown("SpellBookFrame")
end

-- The open ring is on `page` (and has `segment` highlighted, when given); with no page, its page and segment.
local function RingOn(page, segment)
	local shownPage, selected = nil, nil
	if ns.RingSelection then
		shownPage, selected = ns.RingSelection()
	end
	if not page then
		return shownPage, selected
	end
	return shownPage == page and (not segment or selected == segment)
end

local function BagsOpen()
	return Shown("ContainerFrameCombinedBags") or (IsBagOpen and IsBagOpen(0)) or false
end

local function Since(what, since)
	return seen[what] ~= nil and seen[what] >= since
end

-- A set with an ability on its left or right side.
local function SetHasAction(set)
	for side = set * 2 - 1, set * 2 do
		for _, slot in ipairs(ns.sideSlots and ns.sideSlots[side] or {}) do
			if slot > 0 and HasAction and HasAction(slot) then
				return true
			end
		end
	end
	return false
end

-- The set the player was on before a page showed another one; it comes back when the page is left.
local restoreSet = nil

local function ShowSet(driver, form, set)
	driver:SetAttribute("fc-formset-" .. form, set)
	SecureHandlerExecute(driver, [[ self:RunAttribute("ApplyLayer") ]])
end

local function RestoreSet()
	local driver = _G.GamepadXIVDriver
	if restoreSet and driver and not InCombatLockdown() then
		ShowSet(driver, restoreSet.form, restoreSet.set)
		restoreSet = nil
	end
end

-- Shows a set that has abilities on the bottom row, out of combat. False when no set has any.
local function ShowFilledSet()
	local driver = _G.GamepadXIVDriver
	if not (driver and driver.GetAttribute) then
		return true
	end
	local form = driver:GetAttribute("fc-form") or 0
	local set = driver:GetAttribute("fc-formset-" .. form)
	-- Set 0 is the game's stance bar, which the tutorial leaves alone.
	if not set or set == 0 or SetHasAction(set) then
		return true
	end
	for other = 1, ns.NUM_SETS do
		if SetHasAction(other) then
			if not InCombatLockdown() then
				restoreSet = restoreSet or { form = form, set = set }
				ShowSet(driver, form, other)
			end
			return true
		end
	end
	return false
end

-- Post-hooks on the cross hotbar's cast buttons record a press; they never change what it does.
local castsHooked = false
local function HookCasts()
	if castsHooked then
		return
	end
	castsHooked = true
	for _, side in ipairs({ "L", "R", "WL", "WR" }) do
		for i = 1, 8 do
			local button = _G["GamepadXIVCast" .. side .. i]
			if button and button.HookScript then
				button:HookScript("OnClick", function()
					seen.cast = { at = Now(), side = side }
				end)
			end
		end
	end
end
if hooksecurefunc and ToggleAutoRun then
	hooksecurefunc("ToggleAutoRun", function()
		seen.autorun = Now()
	end)
end
if hooksecurefunc and JumpOrAscendStart then
	hooksecurefunc("JumpOrAscendStart", function()
		seen.jump = Now()
	end)
end

-- The steps, from the settings as they are now. A step with `skip` set is left out.
local function BuildSteps()
	local db = ns.db
	local list = {}
	-- Steps come in chapters; the chapter list shows each chapter's name above its steps.
	local chapter
	local function Chapter(name)
		chapter = name
	end
	local function Add(step)
		if not step.skip then
			step.chapter = chapter
			tinsert(list, step)
		end
	end

	-- The set in use on the bottom row, and a face button set to show switching to.
	local currentSet = ns.currentSet or db.set or 1
	if not SET_KEYS[currentSet] then
		currentSet = 1
	end
	local otherSet = currentSet == 2 and 1 or 2

	local dpadWhat = ({ enemy = "enemies", friend = "friendly targets", both = "enemies and friendly targets in turn" })[db.dpadTarget] or "targets"
	local autorun = db.l1StickUpAction == "autorun"
	local r3Label = ChoiceLabel(ns.STICK_ACTIONS, db.r3Action)
	-- R3's own action: under Camera when it switches the view, under Basics for anything else.
	local function R3Step(camera)
		return {
			skip = not db.r3Action or db.r3Action == "none" or db.r3Action == "ring" or (db.r3Action == "view") ~= camera,
			title = r3Label,
			how = (db.r3Action == "bags" and { "Press {PADRSTICK} to open your bags", "Press {PAD2} to close them" })
				or (db.r3Action == "view" and { "Press {PADRSTICK} to switch the camera view" }) or nil,
			checks = (db.r3Action == "bags" and { BagsOpen, function() return not BagsOpen() end })
				or (db.r3Action == "view" and { function(state) return not state.zoom or math.abs(GetCameraZoom() - state.zoom) > 1 end })
				or nil,
			free = db.r3Action == "bags" and { "PAD2" } or nil,
			text = (db.r3Action == "bags" and "The {PADRSTICK} button opens your bags."
				or db.r3Action == "view" and "The {PADRSTICK} button switches the camera view."
				or ("The {PADRSTICK} button: " .. r3Label:lower() .. ".")),
			lit = db.r3Action == "bags" and { S(1, Tap("PADRSTICK", 0)), S(2, Tap("PAD2", 1.2)) } or { S(1, Tap("PADRSTICK", 0), Tap("PADRSTICK", 1.2)) },
		}
	end
	local ringText, ringKeys = ComboFor("ring")
	-- The ring step asks to open Communities, wherever it is on the player's ring.
	local guildPage, ringStart, guildSegment
	if ns.RingFindBuiltin then
		guildPage, ringStart, guildSegment = ns.RingFindBuiltin("guild")
	end
	local minimap = GamepadXIVMinimapButton

	Chapter("Basics")
	Add({
		title = "Welcome to Gamepad XIV",
		text = "Play with a controller, the FFXIV way\n"
			.. "Your abilities live on a cross hotbar. Hold a trigger to bring up a bar, then cast from its slots with the D-pad and face buttons. "
			.. "This tutorial walks you through each button with a short task on every page.",
	})
	Add({
		title = "Jump",
		how = { "Press {PAD4} to jump" },
		checks = { function(state) return not JumpOrAscendStart or Since("jump", state.since) end },
		text = "The {PAD4} button makes your character jump.",
		free = { "PAD4" },
		lit = { S(1, Tap("PAD4", 0), Hold("PAD4", 1.0, 1.2)) },
	})
	Add({
		title = "Interact",
		text = "The {PAD1} button lets you loot, talk, skin, mine and gather."
			.. (db.showInteractPrompt and "\nWhen something is in reach, a prompt with {PAD1} and its name shows over your character." or ""),
		target = db.showInteractPrompt and ns.interactHud and ns.interactHud:IsShown() and { ns.interactHud } or nil,
		lit = { Tap("PAD1", 0), Tap("PAD1", 1.1) },
	})
	Add({
		title = "Cancel",
		-- Something to close first: the character window, which the player opens (addon code can't).
		how = { "Hold {PADLSHOULDER} and press {PAD1} to open your character window", "Press {PAD2} to close it" },
		checks = {
			function() return Shown("CharacterFrame") end,
			function() return not Shown("CharacterFrame") end,
		},
		text = "How to close windows and clear your target\n"
			.. "{PAD2} is your cancel button. It closes the window on screen, and with no window open it clears your target. "
			.. "Try it on your character window.",
		free = { "PAD2" },
		lit = { S(1, Hold("PADLSHOULDER", 0, 0.9), Tap("PAD1", 0.4)), S(2, Tap("PAD2", 1.6)) },
	})
	Add({
		title = "The map",
		how = { "Press {PAD3} to open the map", "Press {PAD2} to close the map" },
		checks = {
			function() return Shown("WorldMapFrame") end,
			function() return not Shown("WorldMapFrame") end,
		},
		text = "The {PAD3} button opens your map.\nThis works when nothing is targeted.",
		free = { "PAD3", "PAD2" },
		lit = { S(1, Tap("PAD3", 0)), S(2, Tap("PAD2", 1.2)) },
	})

	Add(R3Step(false))

	Chapter("Movement")
	Add({
		skip = not db.holdToWalk,
		title = "Walking",
		checks = {
			-- Holding Cancel lowers the run threshold (Input.lua), so the stick walks.
			function() return not GetCVar or (tonumber(GetCVar("GamePadRunThreshold")) or 0) > 1 end,
			function()
				if not GetUnitSpeed then
					return true
				end
				local speed = GetUnitSpeed("player")
				return speed > 0 and speed < 4.5
			end,
		},
		how = { "Press and hold {PAD2} to slow down", "Move with the left stick to walk" },
		text = "Holding {PAD2} while you move makes you walk.",
		free = { "PAD2" },
		lit = { S(1, Hold("PAD2", 0, 1.4)), S(2, Move("PADLSTICK", 0.2, 0, 1, 1.0)) },
	})
	Add({
		skip = not db.l1StickUpAction or db.l1StickUpAction == "none",
		title = autorun and "Auto-run" or "Left stick forward",
		holds = { true },
		checks = autorun and {
			function(state) return Layer() == "L1" or not ToggleAutoRun or Since("autorun", state.since) end,
			function(state) return not ToggleAutoRun or Since("autorun", state.since) end,
		} or nil,
		how = { "Press and hold {PADLSHOULDER}", "Push the left stick forward to start auto-run" },
		text = autorun
			and ("How to use auto-run\n"
				.. "Already running forward? Press {PADLSHOULDER} to activate auto-run.\n"
				.. "Pull the stick back to stop.")
			or ("Hold {PADLSHOULDER} and push the left stick forward: " .. ChoiceLabel(ns.STICK_ACTIONS, db.l1StickUpAction):lower() .. "."),
		-- Holding L1, then pushing forward.
		lit = autorun
			and { S(1, Hold("PADLSHOULDER", 0, 0.9)), S(2, Move("PADLSTICK", 0.3, 0, 1, 0.3)) }
			or { Hold("PADLSHOULDER", 0, 0.9), Move("PADLSTICK", 0.3, 0, 1, 0.3) },
	})

	Chapter("Camera")
	Add({
		skip = db.l1RightStick == "camera",
		title = "Zoom",
		holds = { 3 }, -- L1 stays held through zooming in and out
		checks = db.l1RightStick == "zoom" and {
			function(state)
				if Layer() == "L1" then
					state.zoom = state.zoom or (GetCameraZoom and GetCameraZoom())
					return true
				end
				state.zoom, state.zoomIn = nil, nil
			end,
			-- Zoomed in: closer than when L1 went down, or as close as it goes.
			function(state)
				if not state.zoom then
					return true
				end
				local zoom = GetCameraZoom()
				if zoom < state.zoom - 0.3 or zoom < 0.5 then
					state.zoomIn = zoom
					return true
				end
			end,
			function(state) return not state.zoomIn or GetCameraZoom() > state.zoomIn + 0.3 end,
		} or nil,
		how = db.l1RightStick == "zoom" and { "Press and hold {PADLSHOULDER} so the stick zooms instead of turning the camera",
			"Push the right stick up to zoom in", "Push the right stick down to zoom out" } or nil,
		text = db.l1RightStick == "zoom" and "How to zoom the camera"
			or ("Hold {PADLSHOULDER} and move the right stick up or down: " .. ChoiceLabel(ns.L1_RIGHT_STICK, db.l1RightStick):lower() .. "."),
		lit = { S(1, Hold("PADLSHOULDER", 0, 2.2)), S(2, Move("PADRSTICK", 0.3, 0, 1, 0.4)), S(3, Move("PADRSTICK", 1.3, 0, -1, 0.4)) },
	})
	Add(R3Step(true))

	Chapter("Cross hotbar")
	Add({
		title = "The cross hotbar",
		text = "The cross hotbar holds your abilities.\n"
			.. "It has two bars side by side: the left bar on {PADLTRIGGER} and the right bar on {PADRTRIGGER}.\n"
			.. "Each bar has eight slots, laid out like the D-pad and the face buttons. The button you press matches the slot's place on the bar.\n"
			.. "The next pages show how to use it, then the top row and your other sets.",
		target = Sides("L", "R"),
		lit = {},
	})
	Add({
		title = "Filling your bars",
		-- Forever's Bind to Action Bar, which shows this addon's crossbar (Input.lua); the mouse works too.
		checks = {
			function(state) return SpellbookShown() or Since("slot", state.since) end,
			function(state) return Shown("GamepadActionBarEditFrame") or Since("slot", state.since) end,
			function(state) return Since("slot", state.since) end,
			function() return not SpellbookShown() end,
		},
		how = { "Hold {PADLSHOULDER} and press {PAD2} to open your spellbook", "Select an ability and press {PAD3} to bring up the Bind to Action Bar menu",
			"Hold {PADLTRIGGER} or {PADRTRIGGER} and press a button to put it in that slot", "Press {PAD2} to close your spellbook" },
		free = { "PAD2" },
		text = "Put abilities on your bars from the spellbook.\nYou can also drag abilities, items and macros onto any slot with the mouse.",
		target = Sides("L", "R", "WL", "WR"),
		lit = { S(1, Hold("PADLSHOULDER", 0, 1.0), Tap("PAD2", 0.4)), S(2, Tap("PAD3", 1.5)), S(3, Hold("PADLTRIGGER", 2.4, 0.9), Tap("PAD1", 2.8)), S(4, Tap("PAD2", 3.9)) },
	})
	Add({
		title = "Using an ability",
		holds = { true },
		checks = {
			function() return Layer() == "L" or Layer() == "R" end,
			function(state) return CastSince(state.since) end,
		},
		how = { (db.triggerMode == "toggle" and "Press" or "Press and hold") .. " {PADLTRIGGER} to bring up the left bar", "Press {PAD1} to cast an ability" },
		text = (db.triggerMode == "toggle" and "Press {PADLTRIGGER} for the left bar, or {PADRTRIGGER} for the right bar."
				or "Use your abilities from the cross hotbar.") .. "\n"
			.. "The cross hotbar is where your abilities live: a left bar on {PADLTRIGGER} and a right bar on {PADRTRIGGER}. "
			.. "While a bar is up, each D-pad direction and face button uses one of its eight slots."
			.. (db.triggerMode == "mixed" and " Tap the trigger instead to keep the bar up." or ""),
		target = Sides("L", "R"),
		lit = { S(1, Hold("PADLTRIGGER", 0, 1.4)), S(2, Tap("PAD1", 0.6)) },
	})
	Add({
		title = "The top crossbar",
		holds = { true },
		checks = {
			function() return Layer() == "WL" or Layer() == "WR" end,
			function(state) return CastSince(state.since, { "WL", "WR" }) end,
		},
		how = { "Double tap {PADLTRIGGER} and keep holding it to bring up the top bar", "Press {PAD4} to cast an ability" },
		text = "How to use the top crossbar\n"
			.. "Above the bottom row sit two more bars, one for each trigger, with 16 more slots. A top bar stays selected while you hold its trigger.",
		target = Sides("WL", "WR"),
		lit = { S(1, DoubleHold("PADLTRIGGER", 0, 1.3)), S(2, Tap("PAD4", 0.9)) },
	})
	Add({
		title = "Expanded Hold",
		holds = { true, true },
		checks = {
			function() return Layer() ~= "BASE" and Layer() ~= "SET" and Layer() ~= "L1" end,
			function() return Layer() == "LR" or Layer() == "RL" end,
			function(state) return CastSince(state.since) end,
		},
		how = { "Press and hold {PADLTRIGGER} to bring up the left bar", "Keep holding it and press and hold {PADRTRIGGER} to switch the left bar to an extra bar",
			"Press {PAD1} to cast an ability from it" },
		text = "How to use Expanded Hold\n"
			.. "Expanded Hold gives you two extra bars on the bottom row. The order you press the triggers in picks the bar.\n"
			.. "Hold {PADLTRIGGER} then {PADRTRIGGER}: the left bar switches to an extra bar.\n"
			.. "Hold {PADRTRIGGER} then {PADLTRIGGER}: the right bar switches to a different extra bar.\n"
			.. "Let go of the triggers and your usual bars are back.",
		target = Sides("L", "R"),
		lit = { S(1, Hold("PADLTRIGGER", 0, 2.2)), S(2, Hold("PADRTRIGGER", 0.6, 1.6)), S(3, Tap("PAD1", 1.4)) },
	})
	Add({
		title = "Eight sets",
		holds = { true },
		checks = {
			function() return Layer() == "SET" end,
			function() return ns.currentSet == otherSet end,
		},
		how = { "Press and hold {PADRSHOULDER} to see your sets", "Press {" .. SET_KEYS[otherSet] .. "} to put set " .. otherSet .. " on the bottom row" },
		text = "How to switch sets\n"
			.. "A set is a pair of bars, left and right, with 16 slots. You have eight of them, so you can keep abilities for different uses, "
			.. "like fighting, gathering or travel, and switch the bottom row between them.\n"
			.. "Hold {PADRSHOULDER} and press a face button or a D-pad direction to switch. {PADRSHOULDER} + {" .. SET_KEYS[currentSet] .. "} brings back the set you're on now.",
		target = Sides("L", "R"),
		lit = { S(1, Hold("PADRSHOULDER", 0, 1.3)), S(2, Tap(SET_KEYS[otherSet], 0.6)) },
	})
	Add({
		skip = not db.r1Tap,
		title = "Quick set swap",
		checks = {
			-- The set on screen may be in neither pair, so step 2 waits for the next change, not the first set.
			function(state)
				if ns.currentSet ~= state.set then
					state.swapped = ns.currentSet
					return true
				end
			end,
			function(state) return ns.currentSet ~= state.swapped end,
		},
		how = { "Tap {PADRSHOULDER} and let go quickly to swap to the other pair", "Tap it again to swap back" },
		text = "How to use Quick set swap\n"
			.. (db.r1TapTop and "Quick set swap switches your bottom and top rows together, between two pairs of sets. "
				or "Quick set swap switches your bottom row between two sets. ")
			.. "A quick tap of {PADRSHOULDER} swaps to the other pair, so you can keep one pair for fighting and one for something else, like healing or gathering.",
		target = Sides("L", "R", "WL", "WR"),
		lit = { S(1, Tap("PADRSHOULDER", 0)), S(2, Tap("PADRSHOULDER", 1.2)) },
	})
	-- Picking the slot is undone by B as well, so the last step waits for a change made after it.
	local MOVE_CHECKS = {
		function() return Layer() == "L" or Layer() == "R" or ClearStage() ~= 0 end,
		function() return ClearStage() ~= 0 end,
		function() return ClearStage() ~= 0 and Layer() == "BASE" end,
		function(state)
			local picked = ClearStage() == 2 or ClearStage() == 3
			state.picked = picked and (state.picked or Now()) or state.picked
			return picked
		end,
		function(state) return ClearStage() == 3 or (ClearStage() == 0 and Since("slot", state.picked or state.since)) end,
	}
	local MOVE_HOW = { "Press and hold {PADRTRIGGER}", "Press {PADRSTICK} to start choosing", "Release {PADRTRIGGER}",
		"Press the ability's slot, the same way you cast it, to pick it", "Press {PAD1} to move it, or {PAD3} to remove it" }
	local function MoveLit(first, at)
		return S(first, Hold("PADRTRIGGER", at, 0.9)), S(first + 1, Tap("PADRSTICK", at + 0.4)),
			S(first + 3, Hold("PADRTRIGGER", at + 1.5, 0.8), Tap("PADDRIGHT", at + 1.9)), S(first + 4, Tap("PAD1", at + 2.9))
	end
	local moveStep = {
		title = "Move or remove an ability",
		text = "How to move or remove an ability\nRearrange your bars with the controller: pick an ability on your bars, then move it to another slot or take it off. {PAD2} cancels at any point.",
		target = Sides("L", "R"),
	}
	-- While on this page the bottom row shows a set that has abilities; the player's own set comes back
	-- when the page is left. With none on any set, the page starts by putting one there.
	function moveStep.prepare(step)
		if ShowFilledSet() then
			step.how, step.checks, step.holds, step.free = MOVE_HOW, MOVE_CHECKS, { true }, nil
			step.lit = { MoveLit(1, 0) }
			return
		end
		local how = { "Hold {PADLSHOULDER} and press {PAD2} to open your spellbook",
			"Select an ability and press {PAD3} to bring up the Bind to Action Bar menu",
			"Hold {PADRTRIGGER} and press a button to put it in that slot", "Press {PAD2} to close your spellbook" }
		local checks = {
			function(state) return SpellbookShown() or Since("slot", state.since) end,
			function(state) return Shown("GamepadActionBarEditFrame") or Since("slot", state.since) end,
			function(state) return Since("slot", state.since) end,
			-- The ability may have gone to another set; the bottom row then shows that one.
			function() return not SpellbookShown() and ShowFilledSet() end,
		}
		for index = 1, #MOVE_HOW do
			tinsert(how, MOVE_HOW[index])
			tinsert(checks, MOVE_CHECKS[index])
		end
		step.how, step.checks, step.holds, step.free = how, checks, { [5] = true }, { "PAD2" }
		step.lit = { S(1, Hold("PADLSHOULDER", 0, 1.0), Tap("PAD2", 0.4)), S(2, Tap("PAD3", 1.5)),
			S(3, Hold("PADRTRIGGER", 2.4, 0.9), Tap("PAD1", 2.8)), S(4, Tap("PAD2", 3.9)), MoveLit(5, 4.9) }
	end
	moveStep.prepare(moveStep)
	Add(moveStep)

	Chapter("Targeting")
	Add({
		title = "Targeting",
		text = "The {PADDLEFT} and {PADDRIGHT} buttons select " .. dpadWhat .. ".",
		lit = { Tap("PADDRIGHT", 0), Tap("PADDRIGHT", 1.0) },
	})
	Add({
		title = "Party members",
		-- A party drawn beside the box, so this works alone; D-pad up / down move through it.
		party = true,
		how = { "Press {PADDDOWN} to select the next party member", "Press {PADDUP} to go back up" },
		checks = {
			function(state) return state.partyDown end,
			function(state) return state.partyUp end,
		},
		text = "How to navigate the party frame\nYou will use this when healing, buffing or interacting with your party members. {PADDUP} and {PADDDOWN} move through your party, starting with you.",
		lit = { S(1, Tap("PADDDOWN", 0), Tap("PADDDOWN", 0.8)), S(2, Tap("PADDUP", 1.8)) },
	})
	Add({
		title = "Enemy targeting",
		how = { "Press and hold {PADLTRIGGER}", "Press {PADRSHOULDER} to target the next enemy" },
		text = "How to target enemies\nSwitch between nearby enemies without letting go of your bars. "
			.. "{PADLTRIGGER} + {PADRSHOULDER} and {PADRTRIGGER} + {PADLSHOULDER} both target the next enemy. The order you press the two buttons in doesn't matter.",
		lit = { S(1, Hold("PADLTRIGGER", 0, 0.9)), S(2, Tap("PADRSHOULDER", 0.4)) },
	})

	Chapter("Menus and windows")
	Add({
		title = "Window shortcuts",
		holds = { true },
		checks = {
			function() return Layer() == "L1" or Shown("CharacterFrame") end,
			function() return Shown("CharacterFrame") end,
			function() return not Shown("CharacterFrame") end,
		},
		how = { "Press and hold {PADLSHOULDER}", "Press {PAD1} to open your character window", "Press {PAD2} to close it" },
		text = "Shortcuts for your most used windows\nHold {PADLSHOULDER} and press a face button to open one.\n{PAD1} character     {PAD2} spellbook     {PAD3} map     {PAD4} bags",
		free = { "PAD2" },
		lit = { S(1, Hold("PADLSHOULDER", 0, 1.2)), S(2, Tap("PAD1", 0.5)), S(3, Tap("PAD2", 1.8)) },
	})
	-- The ring's steps: open it, open an entry, then close the window that entry opened.
	local ringHow, ringChecks, ringHolds, ringLit = {}, {}, nil, {}
	local ringAt = 0
	-- A step, and what the scene does for it (each action starting `wait` seconds after the last).
	local function RingStep(text, check, ...)
		tinsert(ringHow, text)
		ringChecks[#ringHow] = check
		for i = 1, select("#", ...) do
			local action = select(i, ...)
			action.step = #ringHow
			tinsert(ringLit, action)
		end
	end
	if ringKeys then
		local ringShown = function() return Shown("GamepadXIVRing") end
		-- The ring stays open until the stick opens an entry; closing it earlier undoes the steps.
		ringHolds = {}
		if #ringKeys == 2 then
			ringHolds[1] = true
			RingStep("Press and hold {" .. ringKeys[1] .. "}", function() return Layer() ~= "BASE" or ringShown() end, Hold(ringKeys[1], 0, 0.8))
			RingStep(((ringText or ""):find("forward") and "Push the left stick forward" or ("Press {" .. ringKeys[2] .. "}")) .. " to open the ring", ringShown,
				Tap(ringKeys[2], 0.35))
			RingStep("Let go of {" .. ringKeys[1] .. "}; the ring stays open", function() return ringShown() and Layer() == "BASE" end)
		else
			RingStep("Press {" .. ringKeys[1] .. "} to open the ring", ringShown, Tap(ringKeys[1], 0.35))
		end
		if guildPage then
			-- A real errand: open Communities, wherever the player's ring has it, by the name the ring shows.
			local guildName = _G.RADIAL_LABEL_GUILD or "Communities"
			if guildPage ~= ringStart then
				local turns = math.abs(guildPage - ringStart)
				RingStep("Press {" .. (guildPage < ringStart and "PADLSHOULDER" or "PADRSHOULDER") .. "}"
					.. (turns > 1 and (" " .. turns .. " times") or "") .. " to turn the page",
					function() return RingOn(guildPage) end,
					Tap(guildPage < ringStart and "PADLSHOULDER" or "PADRSHOULDER", 1.2))
				ringAt = 0.6
			end
			local angle = math.rad((guildSegment - 1) * 45)
			RingStep("Point the right stick " .. RING_DIRECTIONS[guildSegment] .. ", at " .. guildName,
				function() return RingOn(guildPage, guildSegment) or Shown("CommunitiesFrame") end,
				Move("PADRSTICK", 1.2 + ringAt, math.cos(angle), math.sin(angle), 0.8))
			ringHolds[#ringKeys] = #ringHow + 1
			RingStep("Let go of the stick to open it", function() return not ringShown() and Shown("CommunitiesFrame") end)
			RingStep("Press {PAD2} to close " .. guildName, function() return not AnyWindowShown() end, Tap("PAD2", 2.9 + ringAt))
		else
			RingStep("Point the right stick at an entry", function() local _, segment = RingOn(); return (segment or 0) > 0 or not ringShown() end,
				Move("PADRSTICK", 1.2, 0.7, 0.7, 0.8))
			ringHolds[#ringKeys] = #ringHow + 1
			RingStep("Let go of the stick to open it", function() return not ringShown() and AnyWindowShown() end)
			RingStep("Press {PAD2} to close the window it opened", function() return not AnyWindowShown() end, Tap("PAD2", 2.9))
		end
	end
	Add({
		skip = not ringText,
		title = "The ring",
		holds = ringHolds,
		checks = ringKeys and ringChecks or nil,
		how = ringKeys and ringHow or nil,
		free = { "PAD2" },
		text = "How to use the ring\n"
			.. "The ring holds your windows, items and emotes, so you can reach any of them without the mouse. "
			.. (ringText or "") .. " opens it. Point the right stick at an entry and let go to open it, or press {PAD1}. "
			.. "{PADLSHOULDER} and {PADRSHOULDER} turn the pages.",
		lit = ringLit,
	})
	Add({
		title = "Moving items",
		text = "How to move items\n"
			.. "With a bank, guild bank, mailbox, auction house or trade window open, select an item in your bags and press {PAD3} "
			.. "to move it from your bags into that window, for example into the bank. Press {PAD3} on an item in the window to bring it back to your bags. "
			.. "At a vendor, {PAD3} sells the item instead.",
		lit = { Tap("PAD3", 0), Tap("PAD3", 1.0) },
	})

	-- The last page: the tour is over, and this is where everything can be changed.
	Chapter("All set")
	Add({
		title = "You're all set",
		how = { "Left click the minimap icon or type /gxiv config", "Press {PAD2} to close the settings" },
		checks = {
			function() return Shown("GamepadXIVConfigFrame") end,
			function() return not Shown("GamepadXIVConfigFrame") end,
		},
		free = { "PAD2" },
		text = "That's the whole tour. You're ready to play.\n"
			.. "Everything you've seen can be changed in the settings: the bars, the buttons, targeting, the ring and more. "
			.. "Open them once so you know where they are.\n"
			.. "Want to see this again? Use the Tutorial button in the settings, Tutorial in the minimap icon's right-click menu, or type /gxiv tutorial.",
		target = minimap and minimap:IsVisible() and { minimap } or nil,
		lit = {},
	})
	return list
end

-- Spotlight ---------------------------------------------------------------------------------------

-- The screen rectangle around the frames, in UIParent's units, or nil when none is shown.
local function TargetRect(frames)
	local left, right, top, bottom
	local base = UIParent:GetEffectiveScale()
	for _, frame in ipairs(frames or {}) do
		if frame and frame.IsVisible and frame:IsVisible() and frame:GetLeft() then
			local s = frame:GetEffectiveScale() / base
			local l, r, t, b = frame:GetLeft() * s, frame:GetRight() * s, frame:GetTop() * s, frame:GetBottom() * s
			left = left and math.min(left, l) or l
			right = right and math.max(right, r) or r
			top = top and math.max(top, t) or t
			bottom = bottom and math.min(bottom, b) or b
		end
	end
	if not left then
		return nil
	end
	local pad = 10
	return left - pad, right + pad, top + pad, bottom - pad
end

local function CreateOverlay()
	overlay = CreateFrame("Frame", nil, UIParent)
	overlay:SetAllPoints()
	overlay:SetFrameStrata("DIALOG")
	overlay:EnableMouse(false)
	overlay:Hide()
	overlay.dims = {}
	for i = 1, 4 do
		local dim = overlay:CreateTexture(nil, "BACKGROUND")
		dim:SetColorTexture(0, 0, 0, 0.6)
		overlay.dims[i] = dim
	end
	overlay.ring = CreateFrame("Frame", nil, overlay, "BackdropTemplate")
	overlay.ring:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
	overlay.ring:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
	local pulse = overlay.ring:CreateAnimationGroup()
	local fade = pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.3)
	fade:SetDuration(0.7)
	pulse:SetLooping("BOUNCE")
	overlay.ring.pulse = pulse
end

local function PlaceSpotlight(frames)
	local width, height = UIParent:GetWidth(), UIParent:GetHeight()
	local left, right, top, bottom = TargetRect(frames)
	local d = overlay.dims
	for _, dim in ipairs(d) do
		dim:ClearAllPoints()
	end
	if not left then
		d[1]:SetAllPoints(overlay)
		for i = 2, 4 do
			d[i]:Hide()
		end
		d[1]:Show()
		overlay.ring:Hide()
		overlay.ring.pulse:Stop()
		return nil
	end
	left, right = math.max(0, left), math.min(width, right)
	bottom, top = math.max(0, bottom), math.min(height, top)
	-- Above, below, left and right of the target.
	d[1]:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", 0, top)
	d[1]:SetPoint("TOPRIGHT", overlay, "TOPRIGHT")
	d[2]:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT")
	d[2]:SetPoint("TOPRIGHT", overlay, "BOTTOMRIGHT", 0, bottom)
	d[3]:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", 0, bottom)
	d[3]:SetPoint("TOPRIGHT", overlay, "BOTTOMLEFT", left, top)
	d[4]:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", right, bottom)
	d[4]:SetPoint("TOPRIGHT", overlay, "BOTTOMLEFT", width, top)
	for _, dim in ipairs(d) do
		dim:Show()
	end
	overlay.ring:ClearAllPoints()
	overlay.ring:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT", left, bottom)
	overlay.ring:SetPoint("TOPRIGHT", overlay, "BOTTOMLEFT", right, top)
	overlay.ring:Show()
	overlay.ring.pulse:Play()
	return left, right, top, bottom
end

-- The controller ----------------------------------------------------------------------------------

local function IconAtlas(key)
	local utility = InputIconTextureSetUtility
	if utility and utility.GetActiveInputIconButtonTextures and utility.GetActiveInputIconButtonTextures(key) then
		return utility.GetNormalActiveInputIconButtonTexture(key)
	end
end

local function CreateArt(parent)
	art = CreateFrame("Frame", nil, parent)
	art:SetSize(512 * ART_SCALE, 256 * ART_SCALE)
	local body = art:CreateTexture(nil, "BACKGROUND")
	body:SetAllPoints()
	body:SetTexture("Interface\\AddOns\\GamepadXIV\\Media\\controller")
	art.buttons = {}
	for key, pos in pairs(BUTTON_POSITIONS) do
		local holder = CreateFrame("Frame", nil, art)
		holder:SetSize(ICON_SIZE, ICON_SIZE)
		holder:SetPoint("CENTER", art, "TOPLEFT", pos[1] * ART_SCALE, -pos[2] * ART_SCALE)

		local glow = holder:CreateTexture(nil, "BORDER")
		glow:SetSize(GLOW_SIZE, GLOW_SIZE)
		glow:SetPoint("CENTER")
		glow:SetTexture("Interface\\AddOns\\GamepadXIV\\Media\\tutorial_glow")
		glow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
		glow:SetBlendMode("ADD")
		glow:Hide()

		holder.icon = holder:CreateTexture(nil, "ARTWORK")
		holder.icon:SetAllPoints()
		holder.name = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		holder.name:SetPoint("CENTER")

		holder.glow = glow
		holder.groups = {}
		art.buttons[key] = holder
	end
end

local function DrawIcons()
	for key, holder in pairs(art.buttons) do
		local atlas = IconAtlas(key)
		if atlas then
			holder.icon:SetAtlas(atlas)
			holder.icon:Show()
			holder.name:SetText("")
		else
			holder.icon:Hide()
			holder.name:SetText(ns.BUTTON_NAMES and ns.BUTTON_NAMES[key] or key)
		end
	end
end

-- How long each kind of action lasts, in seconds.
-- SLOW stretches every scene; 1.15 plays them 15% slower than the timings written in the steps.
local SLOW = 1.15
local PRESS_DOWN, PRESS_UP, TAP_GAP, PUSH, RETURN = 0.08 * SLOW, 0.1 * SLOW, 0.1 * SLOW, 0.22 * SLOW, 0.2 * SLOW
local function Duration(action)
	local tap = PRESS_DOWN + PRESS_UP
	if action.kind == "tap" then
		return tap
	elseif action.kind == "double" then
		return tap + TAP_GAP + tap
	elseif action.kind == "hold" then
		return tap + action.len
	elseif action.kind == "doublehold" then
		return tap + TAP_GAP + tap + action.len
	elseif action.kind == "move" then
		return PUSH + action.len + RETURN
	elseif action.kind == "updown" then
		return 2 * (PUSH + 0.3 + RETURN)
	end
	return 0
end

-- One button's part of the scene, as an animation group that repeats every `cycle` seconds, so all
-- the buttons stay in step. Scale and Translation animations add up, so a press scales the icon
-- down and the release scales it back, and the glow swells while the button is down.
local function BuildPart(holder, actions, cycle)
	local group = holder:CreateAnimationGroup()
	group:SetLooping("REPEAT")
	local order, t = 0, 0
	local function Wait(duration)
		if duration > 0.005 then
			order = order + 1
			local wait = group:CreateAnimation("Animation")
			wait:SetDuration(duration)
			wait:SetOrder(order)
		end
	end
	local function Scale(target, factor, duration)
		local anim = group:CreateAnimation("Scale")
		anim:SetTarget(target)
		anim:SetScale(factor, factor)
		anim:SetDuration(duration)
		anim:SetOrder(order)
	end
	local function Press(down)
		order = order + 1
		Scale(holder.icon, down and 0.75 or 1 / 0.75, down and PRESS_DOWN or PRESS_UP)
		Scale(holder.glow, down and 1.5 or 1 / 1.5, down and PRESS_DOWN or PRESS_UP)
	end
	local function Shift(dx, dy, duration)
		order = order + 1
		for _, target in ipairs({ holder.icon, holder.glow }) do
			local anim = group:CreateAnimation("Translation")
			anim:SetTarget(target)
			anim:SetOffset(dx, dy)
			anim:SetDuration(duration)
			anim:SetOrder(order)
		end
	end
	local function Push(dx, dy, len)
		local reach = 10
		Shift(dx * reach, dy * reach, PUSH)
		Wait(len)
		Shift(-dx * reach, -dy * reach, RETURN)
	end

	table.sort(actions, function(a, b) return a.at < b.at end)
	for _, action in ipairs(actions) do
		Wait(action.at - t)
		local kind = action.kind
		if kind == "tap" or kind == "double" or kind == "doublehold" then
			Press(true)
			Press(false)
			if kind ~= "tap" then
				Wait(TAP_GAP)
				Press(true)
				if kind == "double" then
					Press(false)
				else
					Wait(action.len)
					Press(false)
				end
			end
		elseif kind == "hold" then
			Press(true)
			Wait(action.len)
			Press(false)
		elseif kind == "move" then
			Push(action.dx, action.dy, action.len)
		elseif kind == "updown" then
			Push(0, 1, 0.3)
			Push(0, -1, 0.3)
		end
		t = math.max(t, action.at + Duration(action))
	end
	Wait(cycle - t)
	return group
end

-- Order badges: each press of a scene gets its number beside its button, bright while that press plays.
-- A press repeated right after itself (✕, ✕) keeps its number; a button used at two points gets two badges.
local BADGE_FLIP = 0.03 -- how long the gold takes to come and go: effectively at once

local badges = {}

local function Badge(index)
	local badge = badges[index]
	if not badge then
		badge = CreateFrame("Frame", nil, art)
		badge:SetSize(24, 24)
		badge:SetFrameLevel(art:GetFrameLevel() + 5)
		local glow = "Interface\\AddOns\\GamepadXIV\\Media\\tutorial_glow"
		badge.back = badge:CreateTexture(nil, "BACKGROUND")
		badge.back:SetPoint("CENTER")
		badge.back:SetSize(36, 36)
		badge.back:SetTexture(glow)
		badge.back:SetVertexColor(0, 0, 0)
		badge.idle = badge:CreateTexture(nil, "BORDER")
		badge.idle:SetPoint("CENTER")
		badge.idle:SetSize(24, 24)
		badge.idle:SetTexture(glow)
		badge.idle:SetVertexColor(0.45, 0.45, 0.5)
		badge.active = badge:CreateTexture(nil, "ARTWORK")
		badge.active:SetPoint("CENTER")
		badge.active:SetSize(24, 24)
		badge.active:SetTexture(glow)
		badge.active:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
		badge.text = badge:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		badge.text:SetPoint("CENTER", 0, 0)
		local font, _, flags = badge.text:GetFont()
		if font then
			badge.text:SetFont(font, 14, "OUTLINE")
		end
		badge.groups = {}
		badges[index] = badge
	end
	return badge
end

-- The badge's part of the scene: grey, and gold during each of its presses, padded to the cycle.
local function BuildBadge(badge, actions, cycle)
	local group = badge:CreateAnimationGroup()
	group:SetLooping("REPEAT")
	local order, t = 0, 0
	local function Wait(duration)
		if duration > 0.005 then
			order = order + 1
			local wait = group:CreateAnimation("Animation")
			wait:SetDuration(duration)
			wait:SetOrder(order)
		end
	end
	local function Flip(from, to)
		order = order + 1
		local anim = group:CreateAnimation("Alpha")
		anim:SetTarget(badge.active)
		anim:SetFromAlpha(from)
		anim:SetToAlpha(to)
		anim:SetDuration(BADGE_FLIP)
		anim:SetOrder(order)
	end
	for _, action in ipairs(actions) do
		local start = math.max(t, action.at)
		Wait(start - t)
		Flip(0, 1)
		local stay = action.at + Duration(action) - (start + BADGE_FLIP)
		Wait(stay)
		Flip(1, 0)
		t = start + BADGE_FLIP + math.max(stay, 0) + BADGE_FLIP
	end
	Wait(cycle - t)
	return group
end

local function NumberPresses(lit, cycle)
	for _, badge in ipairs(badges) do
		for _, group in ipairs(badge.groups) do
			group:Stop()
		end
		wipe(badge.groups)
		badge:Hide()
	end
	local sorted = {}
	for _, action in ipairs(lit or {}) do
		tinsert(sorted, action)
	end
	table.sort(sorted, function(a, b) return a.at < b.at end)
	-- Number the presses, and gather each number's presses per button.
	local entries = {}
	local stepped = sorted[1] ~= nil and sorted[1].step ~= nil
	if stepped then
		-- Numbered like the page's steps: one badge per button and step.
		local byKeyStep = {}
		for _, action in ipairs(sorted) do
			local id = action.key .. "#" .. (action.step or 0)
			if not byKeyStep[id] then
				byKeyStep[id] = { key = action.key, number = action.step, actions = {} }
				tinsert(entries, byKeyStep[id])
			end
			tinsert(byKeyStep[id].actions, action)
		end
	else
		return -- no numbered steps on the page, so no numbers on the controller
	end
	local perKey = {}
	for index, entry in ipairs(entries) do
		local holder = art.buttons[entry.key]
		if holder then
			perKey[entry.key] = (perKey[entry.key] or 0) + 1
			local badge = Badge(index)
			badge:ClearAllPoints()
			badge:SetPoint("CENTER", holder, "CENTER", 18 + (perKey[entry.key] - 1) * 22, 15)
			badge.text:SetText(entry.number)
			badge.active:SetAlpha(0)
			badge:Show()
			local group = BuildBadge(badge, entry.actions, cycle)
			tinsert(badge.groups, group)
			group:Play()
		end
	end
end

local function LightButtons(lit)
	-- Copies, stretched by SLOW, so the steps' own tables stay as written.
	local slowed = {}
	for _, action in ipairs(Flatten(lit)) do
		local copy = {}
		for k, v in pairs(action) do
			copy[k] = v
		end
		copy.at = action.at * SLOW
		copy.len = action.len and action.len * SLOW
		tinsert(slowed, copy)
	end
	lit = slowed
	local byKey, cycle = {}, 0
	for _, action in ipairs(lit or {}) do
		byKey[action.key] = byKey[action.key] or {}
		tinsert(byKey[action.key], action)
		cycle = math.max(cycle, action.at + Duration(action))
	end
	-- A pause before the scene starts again.
	cycle = cycle + 0.9
	for key, holder in pairs(art.buttons) do
		for _, group in ipairs(holder.groups) do
			group:Stop()
		end
		wipe(holder.groups)
		local actions = byKey[key]
		if actions then
			holder:SetAlpha(1)
			holder.glow:SetAlpha(0.6)
			holder.glow:Show()
			local group = BuildPart(holder, actions, cycle)
			tinsert(holder.groups, group)
			group:Play()
		else
			holder:SetAlpha(0.35)
			holder.glow:Hide()
		end
	end
	NumberPresses(lit, cycle)
end

-- The callout -------------------------------------------------------------------------------------

local function CreateCalloutButton(text, onClick)
	local button = CreateFrame("Button", nil, callout, "UIPanelButtonTemplate")
	button:SetSize(90, 24)
	button:SetText(text)
	button:SetScript("OnClick", onClick)
	return button
end

local ShowStep, PlaceCallout, SomethingOpen, Locked, UpdateChecks
local checkState -- checks for the page on screen
local partyFrame -- the party beside the box on the Party members page

local function ChaptersShown()
	return chapters ~= nil and chapters:IsShown()
end

local function HideChapters()
	if ChaptersShown() then
		chapters:Hide()
		if callout:IsShown() then
			ShowStep()
		end
	end
end

local function Close(finished)
	paused = false
	if chapters then
		chapters:Hide()
	end
	if partyFrame then
		partyFrame:Hide()
	end
	if overlay then
		overlay:Hide()
		callout:Hide()
	end
	ns.SetTutorialKeys(false)
	RestoreSet()
	if finished then
		current = 1
	end
end

-- Opens the chapter picked in the list.
local function GoTo(index)
	if steps[index] then
		current = index
		HideChapters()
		ShowStep()
	end
end

local function Next()
	if not (callout and callout:IsShown()) then
		return
	end
	if ChaptersShown() then
		GoTo(chapters.pick)
		return
	end
	if Locked(steps[current]) then
		return
	end
	if current >= #steps then
		Close(true)
		ns.Print("Tutorial finished. Replay it from the Tutorial button in the settings, the minimap menu or /gxiv tutorial.")
		return
	end
	current = current + 1
	ShowStep()
end

local function Back()
	if ChaptersShown() then
		HideChapters()
		return
	end
	if callout and callout:IsShown() and current > 1 then
		current = current - 1
		ShowStep()
	end
end

-- One row per chapter name and per step, laid out from the steps as built now.
local function ChapterRow(index)
	local row = chapters.rows[index]
	if row then
		return row
	end
	row = CreateFrame("Button", nil, chapters)
	row:SetSize(CHAPTER_WIDTH - 12, CHAPTER_ROW)
	row.pick = row:CreateTexture(nil, "BACKGROUND")
	row.pick:SetAllPoints()
	row.pick:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.18)
	row.hover = row:CreateTexture(nil, "HIGHLIGHT")
	row.hover:SetAllPoints()
	row.hover:SetColorTexture(1, 1, 1, 0.08)
	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.text:SetPoint("LEFT", 8, 0)
	row.text:SetJustifyH("LEFT")
	row:SetScript("OnClick", function(self)
		if self.step then
			GoTo(self.step)
		end
	end)
	chapters.rows[index] = row
	return row
end

local function UpdateChapters()
	local y, used, last = -8, 0, nil
	for index, step in ipairs(steps) do
		if step.chapter and step.chapter ~= last then
			last = step.chapter
			used = used + 1
			local header = ChapterRow(used)
			header.step = nil
			header:EnableMouse(false)
			header.pick:Hide()
			header.text:SetFontObject("GameFontNormalSmall")
			header.text:SetText(step.chapter:upper())
			header.text:SetTextColor(unpack(GOLD))
			header.text:SetPoint("LEFT", 4, 0)
			if used > 1 then
				y = y - 6
			end
			header:ClearAllPoints()
			header:SetPoint("TOPLEFT", 6, y)
			header:Show()
			y = y - CHAPTER_ROW
		end
		used = used + 1
		local row = ChapterRow(used)
		row.step = index
		row:EnableMouse(true)
		row.pick:SetShown(index == chapters.pick)
		row.text:SetFontObject("GameFontHighlightSmall")
		row.text:SetText(step.title)
		row.text:SetTextColor(unpack(index == current and GOLD or { 0.9, 0.9, 0.9 }))
		row.text:SetPoint("LEFT", 14, 0)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 6, y)
		row:Show()
		y = y - CHAPTER_ROW
	end
	for index = used + 1, #chapters.rows do
		chapters.rows[index]:Hide()
	end
	chapters:SetHeight(-y + 8)
end

-- Beside the callout, on whichever side has room.
local function PlaceChapters()
	if not ChaptersShown() then
		return
	end
	chapters:ClearAllPoints()
	if (callout:GetRight() or 0) + 6 + CHAPTER_WIDTH <= (UIParent:GetRight() or UIParent:GetWidth()) then
		chapters:SetPoint("TOPLEFT", callout, "TOPRIGHT", 6, 0)
	else
		chapters:SetPoint("TOPRIGHT", callout, "TOPLEFT", -6, 0)
	end
end

local function CreateChapters()
	chapters = CreateFrame("Frame", "GamepadXIVTutorialChapterList", callout, "BackdropTemplate")
	chapters:SetWidth(CHAPTER_WIDTH)
	chapters:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	chapters:SetBackdropColor(0.06, 0.06, 0.08, 0.97)
	chapters:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.7)
	chapters:EnableMouse(true)
	chapters:Hide()
	chapters.rows = {}
	chapters.pick = 1
end

local function ToggleChapters()
	if not (callout and callout:IsShown()) then
		return
	end
	if ChaptersShown() then
		HideChapters()
		return
	end
	chapters.pick = current
	chapters:Show()
	UpdateChapters()
	PlaceChapters()
	ShowStep()
end

-- The party for the Party members page: you, then four others, with the selection moving like the
-- real D-pad party selection, from the top down.
local PARTY = {
	{ class = "PRIEST", name = "Thalindra", health = 0.92 },
	{ class = "WARRIOR", name = "Brakk", health = 0.64 },
	{ class = "DRUID", name = "Elowen", health = 1 },
	{ class = "MAGE", name = "Grimsby", health = 0.38 },
}
local PARTY_ROW = 38

local function PartyShown()
	return partyFrame ~= nil and partyFrame:IsShown()
end

local function UpdateParty()
	for index, row in ipairs(partyFrame.rows) do
		row.selected:SetShown(index == partyFrame.pick)
	end
end

local function CreateParty()
	partyFrame = CreateFrame("Frame", "GamepadXIVTutorialParty", callout, "BackdropTemplate")
	partyFrame:SetWidth(190)
	partyFrame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	partyFrame:SetBackdropColor(0.06, 0.06, 0.08, 0.97)
	partyFrame:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.7)
	partyFrame:Hide()
	partyFrame.rows = {}
	local _, playerClass = UnitClass and UnitClass("player")
	local members = { { class = playerClass or "WARRIOR", name = UnitName and UnitName("player") or "You", health = 1 } }
	for _, member in ipairs(PARTY) do
		tinsert(members, member)
	end
	for index, member in ipairs(members) do
		local row = CreateFrame("Frame", nil, partyFrame)
		row:SetSize(174, PARTY_ROW - 6)
		row:SetPoint("TOPLEFT", 8, -8 - (index - 1) * PARTY_ROW)
		local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[member.class] or { r = 0.6, g = 0.6, b = 0.6 }
		row.back = row:CreateTexture(nil, "BACKGROUND")
		row.back:SetAllPoints()
		row.back:SetColorTexture(0.12, 0.12, 0.14, 1)
		row.bar = row:CreateTexture(nil, "ARTWORK")
		row.bar:SetPoint("TOPLEFT", 1, -1)
		row.bar:SetPoint("BOTTOMLEFT", 1, 1)
		row.bar:SetWidth(172 * member.health)
		row.bar:SetColorTexture(color.r, color.g, color.b, 0.75)
		row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.name:SetPoint("LEFT", 8, 0)
		row.name:SetText(member.name)
		row.selected = row:CreateTexture(nil, "OVERLAY")
		row.selected:SetPoint("TOPLEFT", -3, 3)
		row.selected:SetPoint("BOTTOMRIGHT", 3, -3)
		row.selected:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.35)
		row.selected:SetBlendMode("ADD")
		partyFrame.rows[index] = row
	end
	partyFrame:SetHeight(#members * PARTY_ROW + 10)
end

-- Beside the callout, on the side the chapter list doesn't use first.
local function PlaceParty()
	partyFrame:ClearAllPoints()
	if (callout:GetLeft() or 0) - 6 - partyFrame:GetWidth() >= 0 then
		partyFrame:SetPoint("TOPRIGHT", callout, "TOPLEFT", -6, 0)
	else
		partyFrame:SetPoint("TOPLEFT", callout, "TOPRIGHT", 6, 0)
	end
end

local function ShowParty(show)
	if show and not partyFrame then
		CreateParty()
	end
	if partyFrame then
		partyFrame.pick = 0
		partyFrame:SetShown(show and true or false)
		if show then
			UpdateParty()
			PlaceParty()
		end
	end
end

local function MoveParty(delta)
	local count = #partyFrame.rows
	if partyFrame.pick == 0 then
		partyFrame.pick = delta > 0 and 1 or count
	else
		partyFrame.pick = (partyFrame.pick - 1 + delta) % count + 1
	end
	UpdateParty()
	if checkState then
		if delta > 0 then
			checkState.partyDown = true
		else
			checkState.partyUp = true
		end
	end
end

local function MovePick(delta)
	if ChaptersShown() then
		chapters.pick = math.max(1, math.min(#steps, chapters.pick + delta))
		UpdateChapters()
	elseif PartyShown() then
		MoveParty(delta)
	end
end

local function CreateCallout()
	callout = CreateFrame("Frame", "GamepadXIVTutorial", UIParent, "BackdropTemplate")
	callout:SetFrameStrata("FULLSCREEN_DIALOG")
	callout:SetClampedToScreen(true)
	callout:EnableMouse(true)
	callout:SetWidth(CALLOUT_WIDTH)
	callout:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	callout:SetBackdropColor(0.06, 0.06, 0.08, 0.97)
	callout:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.7)
	callout:Hide()

	callout.title = callout:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	callout.title:SetPoint("TOPLEFT", 16, -14)
	callout.count = callout:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	callout.count:SetPoint("TOPRIGHT", -16, -16)

	CreateArt(callout)
	art:SetPoint("TOP", 0, -46)

	-- How far along the tutorial is: a thin gold bar under the title.
	callout.progressBack = callout:CreateTexture(nil, "ARTWORK")
	callout.progressBack:SetPoint("TOPLEFT", 16, -38)
	callout.progressBack:SetSize(CALLOUT_WIDTH - 32, 2)
	callout.progressBack:SetColorTexture(1, 1, 1, 0.1)
	callout.progress = callout:CreateTexture(nil, "OVERLAY")
	callout.progress:SetPoint("TOPLEFT", callout.progressBack, "TOPLEFT")
	callout.progress:SetHeight(2)
	callout.progress:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.8)

	-- A page's first line is what to do, larger and white; the rest is detail, smaller and grey.
	callout.text = callout:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	callout.text:SetPoint("TOP", art, "BOTTOM", 0, -8)
	callout.text:SetPoint("LEFT", callout, "LEFT", 16, 0)
	callout.text:SetWidth(CALLOUT_WIDTH - 32)
	callout.text:SetJustifyH("LEFT")
	callout.text:SetSpacing(3)
	local font, _, flags = callout.text:GetFont()
	if font then
		callout.text:SetFont(font, 15, flags)
	end
	-- Numbered steps for a button combination, between the headline and the detail.
	callout.how = callout:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	callout.how:SetPoint("TOPLEFT", callout.text, "BOTTOMLEFT", 0, -10) -- placed again in ShowStep
	callout.how:SetWidth(CALLOUT_WIDTH - 32)
	callout.how:SetJustifyH("LEFT")
	callout.how:SetSpacing(6)
	callout.detail = callout:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	callout.detail:SetPoint("TOPLEFT", callout.text, "BOTTOMLEFT", 0, -8)
	callout.detail:SetWidth(CALLOUT_WIDTH - 32)
	callout.detail:SetJustifyH("LEFT")
	callout.detail:SetSpacing(4)
	callout.detail:SetTextColor(0.78, 0.78, 0.8)

	callout.next = CreateCalloutButton("Next", Next)
	callout.next:SetPoint("BOTTOMRIGHT", -14, 12)
	callout.back = CreateCalloutButton("Back", Back)
	callout.back:SetPoint("RIGHT", callout.next, "LEFT", -4, 0)
	callout.close = CreateCalloutButton("Close", function() Close(false) end)
	callout.close:SetPoint("BOTTOMLEFT", 14, 12)
	callout.chapters = CreateCalloutButton("Chapters", ToggleChapters)
	callout.chapters:SetPoint("LEFT", callout.close, "RIGHT", 4, 0)

	-- Moves aside while the ring or the map is open, and back when it closes.
	local since = 0
	callout:SetScript("OnUpdate", function(_, elapsed)
		since = since + elapsed
		if since < 0.1 then
			return
		end
		since = 0
		if SomethingOpen() ~= callout.aside then
			PlaceCallout()
		end
		UpdateChecks()
	end)

	callout.keys = callout:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	callout.keys:SetPoint("BOTTOM", 0, 46)
	CreateChapters()
end

-- The pages done this time the tutorial is open.
local completed = {}

local function CheckCount(step)
	if step.checks then
		return #(step.how or {})
	end
	return step.goal and 1 or 0
end

function Locked(step)
	return CheckCount(step) > 0 and not completed[step.title]
end

local READY = "|TInterface\\RaidFrame\\ReadyCheck-Ready:16:16|t"

-- What the controller acts out: on a page with checks, the step the player is on, with the buttons
-- earlier steps still need held; when the page is done, or has no checks, the whole scene.
local function SceneFor(step)
	local lit = Flatten(step.lit)
	if CheckCount(step) == 0 or completed[step.title] or not checkState then
		return lit
	end
	local pending = checkState.done + 1
	local keep = {}
	for _, action in ipairs(lit) do
		local n = action.step
		local held = n and step.holds and step.holds[n]
		held = held == true and n + 1 or held
		if n == pending or (held and n < pending and pending <= held) then
			tinsert(keep, action)
		end
	end
	if #keep == 0 then
		return {}
	end
	local first = math.huge
	for _, action in ipairs(keep) do
		first = math.min(first, action.at)
	end
	local scene = {}
	for _, action in ipairs(keep) do
		local copy = {}
		for k, v in pairs(action) do
			copy[k] = v
		end
		copy.at = action.at - first
		tinsert(scene, copy)
	end
	return scene
end

-- Runs the next check of the page on screen; called from the callout's OnUpdate.
function UpdateChecks()
	local step = steps[current]
	local count = step and CheckCount(step) or 0
	if count == 0 or completed[step.title] or not checkState then
		return
	end
	local index = checkState.done + 1
	while index < count and step.checks and not step.checks[index] do
		index = index + 1
	end
	local check = step.checks and step.checks[index] or step.goal
	if check and check(checkState) then
		checkState.done = index
		checkState.since = Now()
		if index >= count then
			completed[step.title] = true
		end
		ShowStep(true)
		return
	end
	-- A step in `holds` is a button to keep held: it is undone when let go before the step it is held
	-- for is done. `true` means the next step; a number names the last step that needs it.
	for held = checkState.done, 1, -1 do
		local holdUntil = step.holds and step.holds[held]
		holdUntil = holdUntil == true and held + 1 or holdUntil
		if holdUntil and checkState.done < holdUntil and step.checks[held] and not step.checks[held](checkState) then
			checkState.done = held - 1
			ShowStep(true)
			return
		end
	end
end

function ShowStep(refresh)
	local step = steps[current]
	if not step then
		return
	end
	if not refresh then
		RestoreSet()
		if step.prepare then
			step.prepare(step)
		end
		checkState = { done = completed[step.title] and CheckCount(step) or 0, since = Now(), set = ns.currentSet,
			target = UnitExists and UnitExists("target"), zoom = GetCameraZoom and GetCameraZoom() }
		HookCasts()
	end
	local locked = Locked(step)
	callout.title:SetText(step.title)
	callout.count:SetText((step.chapter and (step.chapter .. "   ") or "") .. current .. " / " .. #steps)
	local main, detail = step.text:match("^(.-)\n(.*)$")
	callout.text:SetText(Text(main or step.text, 20))
	callout.detail:SetText(detail and Text(detail, 17) or "")
	local how = {}
	for index, line in ipairs(step.how or {}) do
		if step.checks and index <= checkState.done then
			tinsert(how, READY .. "  |cff8fd18f" .. line .. "|r")
		else
			tinsert(how, "|cff8c8c8c" .. index .. ".|r  " .. line)
		end
	end
	if step.goal and completed[step.title] then
		tinsert(how, READY .. "  |cff8fd18fDone|r")
	end
	callout.how:SetText(#how > 0 and Text(table.concat(how, "\n"), 18) or "")
	callout.how:SetShown(#how > 0)
	-- The headline, then the detail, then the steps to do.
	callout.how:ClearAllPoints()
	callout.how:SetPoint("TOPLEFT", detail and callout.detail or callout.text, "BOTTOMLEFT", 0, -12)
	callout.progress:SetWidth(math.max(1, (CALLOUT_WIDTH - 32) * current / #steps))
	-- The buttons this step teaches keep their own action on it, so they can be tried.
	local free = step.free or {}
	-- Not on a refresh: rebinding while a button is held (L1 for the character window) can lose
	-- its release and leave the driver in that layer.
	if not refresh then
		ShowParty(step.party and not ChaptersShown())
		ns.SetTutorialKeys(true, ChaptersShown() or step.party, free)
	end
	if ChaptersShown() then
		callout.keys:SetText(Text("{PADDUP}{PADDDOWN} choose   {PAD1} open   {PAD2} back   {PAD4} close", 14))
		UpdateChapters()
	else
		local hints = {}
		for _, hint in ipairs({ { "PAD1", "next" }, { "PAD2", "back" }, { "PAD3", "chapters" }, { "PAD4", "close" } }) do
			if not tContains(free, hint[1]) and not (locked and hint[1] == "PAD1") then
				tinsert(hints, "{" .. hint[1] .. "} " .. hint[2])
			end
		end
		callout.keys:SetText(Text(table.concat(hints, "   "), 14))
	end
	callout.back:SetEnabled(current > 1)
	callout.next:SetText(current == #steps and "Finish" or "Next")
	callout.next:SetEnabled(not locked)
	if refresh then
		local detailHeight = detail and (8 + callout.detail:GetStringHeight()) or 0
		if #how > 0 then
			detailHeight = detailHeight + 10 + callout.how:GetStringHeight()
		end
		callout:SetHeight(46 + art:GetHeight() + 8 + callout.text:GetStringHeight() + detailHeight + 80)
		LightButtons(SceneFor(step))
		return
	end
	LightButtons(SceneFor(step))
	local detailHeight = detail and (8 + callout.detail:GetStringHeight()) or 0
	if #how > 0 then
		detailHeight = detailHeight + 10 + callout.how:GetStringHeight()
	end
	callout:SetHeight(46 + art:GetHeight() + 8 + callout.text:GetStringHeight() + detailHeight + 80)
	callout:Show()
	callout.aside = nil
	PlaceCallout()
end

-- Something the player opened to try a step (the ring, the map, Communities): the tutorial steps aside
-- to the right edge, clear of the windows that open on the left, and stops dimming the screen until it closes.
function SomethingOpen()
	for _, name in ipairs({ "GamepadXIVRing", "GamepadXIVClearPanel", "GamepadXIVFlyoutPanel", "WorldMapFrame", "CommunitiesFrame", "GameMenuFrame", "CharacterFrame", "PlayerSpellsFrame", "SpellBookFrame", "GamepadActionBarEditFrame",
		"GamepadXIVConfigFrame" }) do
		local frame = _G[name]
		if frame and frame.IsShown and frame:IsShown() then
			return true
		end
	end
	return false
end

function PlaceCallout()
	local step = steps[current]
	local aside = SomethingOpen()
	callout.aside = aside
	callout:ClearAllPoints()
	if aside then
		overlay:Hide()
		callout:SetPoint("RIGHT", UIParent, "RIGHT", -24, 0)
		PlaceChapters()
		return
	end
	local left, right, top, bottom = PlaceSpotlight(step.target)
	-- Keep clear of the crossbars and of what the page points at: above them if the box fits,
	-- else below, right or left, with a gap. Centred on them, kept on screen.
	local bl, br, bt, bb = TargetRect(Sides("L", "R", "WL", "WR"))
	if bl then
		-- Also the R1 set picker, which shows above the top row (Bar.lua), and the set labels under
		-- the bottom row, even while they're hidden.
		local picker = ns.root and ns.root.setPicker
		bt = bt + 24 + (picker and picker.GetHeight and picker:GetHeight() or 130)
		bb = bb - 28
	end
	if left and bl then
		left, right, top, bottom = math.min(left, bl), math.max(right, br), math.max(top, bt), math.min(bottom, bb)
	elseif bl then
		left, right, top, bottom = bl, br, bt, bb
	end
	if not left then
		callout:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	else
		local gap = 30
		local width, height = UIParent:GetWidth(), UIParent:GetHeight()
		local w, h = callout:GetWidth(), callout:GetHeight()
		local cx = math.max(w / 2 + 8, math.min(width - w / 2 - 8, (left + right) / 2))
		local cy = math.max(h / 2 + 8, math.min(height - h / 2 - 8, (top + bottom) / 2))
		if height - top - gap >= h + 8 then
			callout:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", cx, top + gap)
		elseif bottom - gap >= h + 8 then
			callout:SetPoint("TOP", UIParent, "BOTTOMLEFT", cx, bottom - gap)
		elseif width - right - gap >= w + 8 then
			callout:SetPoint("LEFT", UIParent, "BOTTOMLEFT", right + gap, cy)
		elseif left - gap >= w + 8 then
			callout:SetPoint("RIGHT", UIParent, "BOTTOMLEFT", left - gap, cy)
		else
			callout:SetPoint("TOP", UIParent, "TOP", 0, -8)
		end
	end
	overlay:Show()
	PlaceChapters()
end

-- Starting, pausing and the first run -------------------------------------------------------------

function ns.StartTutorial(resume)
	if InCombatLockdown() then
		ns.Print("The tutorial can't start in combat.")
		return
	end
	if not (ns.IsActive and ns.IsActive()) then
		ns.Print("The tutorial needs the layout active. See /gxiv status.")
		return
	end
	if not overlay then
		CreateOverlay()
		CreateCallout()
		DrawIcons()
		if InputDeviceIconSetManager and InputDeviceIconSetManager.RegisterActiveInputDeviceIconSetUpdatedCallback then
			InputDeviceIconSetManager:RegisterActiveInputDeviceIconSetUpdatedCallback(function()
				DrawIcons()
				if callout:IsShown() then
					ShowStep()
				end
			end, callout)
		end
	end
	steps = BuildSteps()
	if not resume then
		current = 1
		wipe(completed) -- a new run starts with every page to do again; a resume after combat keeps them
	end
	current = math.min(current, #steps)
	AccountDB().tutorialSeen = true
	ShowStep()
end

function ns.IsTutorialShown()
	return callout ~= nil and callout:IsShown()
end

-- The driver's buttons for {PAD1} / {PAD2} / {PAD3} / {PAD4}, and D-pad up / down in the chapter list.
for name, action in pairs({ GamepadXIVTutorialNext = Next, GamepadXIVTutorialBack = Back,
	GamepadXIVTutorialClose = function() Close(false) end, GamepadXIVTutorialChapters = ToggleChapters,
	GamepadXIVTutorialUp = function() MovePick(-1) end, GamepadXIVTutorialDown = function() MovePick(1) end }) do
	local button = CreateFrame("Button", name, UIParent)
	button:RegisterForClicks("AnyDown")
	button:SetScript("OnClick", action)
	button:Hide()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
events:SetScript("OnEvent", function(_, event)
	if event == "ACTIONBAR_SLOT_CHANGED" then
		seen.slot = Now()
	elseif event == "PLAYER_REGEN_DISABLED" then
		-- Bindings can still change while this event runs.
		if ns.IsTutorialShown() then
			Close(false)
			paused = true
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if paused then
			paused = false
			ns.StartTutorial(true)
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		if AccountDB().tutorialSeen then
			return
		end
		C_Timer.After(AUTO_START_DELAY, function()
			if not AccountDB().tutorialSeen and not InCombatLockdown() and ns.IsActive and ns.IsActive()
				and not ns.IsTutorialShown() then
				ns.StartTutorial()
			end
		end)
	end
end)
