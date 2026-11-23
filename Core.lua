local ADDON, ns = ...

ns.ICON = "Interface\\AddOns\\GamepadXIV\\Icon"
ns.ICON_MARKUP = "|T" .. ns.ICON .. ":16|t"

ns.NUM_SETS = 8
ns.NUM_SLOTS = 8
ns.NUM_FORMS = 4
ns.ROWS = { "L", "R", "WL", "WR" } -- bottom left/right, then the double tap row on top

-- Physical keys in Forever's cross layout order: 1 left, 2 up, 3 right, 4 down per cluster.
ns.KEYS = { "PADDLEFT", "PADDUP", "PADDRIGHT", "PADDDOWN", "PAD3", "PAD4", "PAD2", "PAD1" }
-- Set chosen by R1 + each of those keys: 1-4 clockwise on the face buttons from the top, 5-8 on the D-pad.
ns.SET_BY_KEY = { 8, 5, 6, 7, 4, 1, 2, 3 }

ns.DEFAULTS = {
	enabled = true,
	set = 1,
	-- Which side each extra layer shows. A side is (set * 2 - 1) for left, (set * 2) for right.
	sideWL = 3, -- double tap L2: set 2 left
	sideWR = 4, -- double tap R2: set 2 right
	sideLR = 5, -- hold L2, then R2: set 3 left
	sideRL = 6, -- hold R2, then L2: set 3 right
	doubleTapTicks = 3, -- secure timer ticks (0.2s each, sooner on some game events): window of 0.4-0.6s
	priorityBindings = false, -- true only if Forever's own bindings outrank ours on this client
	autoFace = false,
	experimentalAccepted = false,
	experimentalDeclined = false,
	errorLog = {},
	minimapShown = true,
	minimapAngle = 220,
	savedCVars = {},
	ringEntries = {}, -- old ring entries, moved into ringPages on first use
	ringPages = {}, -- the ring pages: the player's entries in each, and the pages they added
	holdToWalk = true,
	triggerMode = "hold", -- hold, toggle or mixed, like FFXIV's cross hotbar activation
	wxhbReturn = false, -- using a top bar (WXHB) button goes back to the bottom bar, like FFXIV's option
	dimAlpha = 0.55,
	idleAlpha = 1, -- bar opacity out of combat with no trigger held; 1 never fades
	showKeyLabels = false,
	rangeIndicator = true,
	showInteractPrompt = true,
	promptStrata = "HIGH", -- the interact prompt's layer: BACKGROUND, LOW, MEDIUM or HIGH
	promptX = 0, promptY = 170, -- over the character, from the middle of the screen
	lootDetails = true, -- the roll item and the equipped item beside the loot roll window
	alwaysCompareItems = true, -- WoW's alwaysCompareItems: item tooltips compare with what you wear
	lootMoved = false, lootX = 0, lootY = 0, -- the loot roll window: Forever's place, or moved here from the middle
	crosshairStyle = "forever", -- a key of ns.CROSSHAIR_STYLES: Forever's own reticle or one drawn by the addon
	crosshairColor = "white", -- a key of ns.HIGHLIGHT_COLORS
	crosshairSize = 16,
	crosshairThickness = 2,
	crosshairAlpha = 1,
	crosshairOutline = true,
	keyIconSize = 32, -- the art has wide empty margins, so this is larger than it looks
	showSetLabels = true,
	showSetPicker = true, -- the CHANGE SET overlay while R1 is held
	theme = "hex", -- a key of ns.THEMES: how the crossbar slots look
	-- The next four are "theme" to use the theme's choice, or a key of their list in Theme.lua.
	background = "vignette", -- ns.BACKGROUNDS: what is drawn behind each group of four slots
	slotFill = "theme", -- ns.SLOT_FILLS: the fill inside each slot, under the icon
	l3Action = "sheathe", -- a key of ns.STICK_ACTIONS: what L3 does
	r3Action = "view", -- a key of ns.STICK_ACTIONS: what R3 does
	l1R3Action = "classLeft", -- a key of ns.STICK_ACTIONS: L1 + R3, the pet commands or forms menu
	r1L3Action = "classRight",
	r1R3Action = "ring", -- a key of ns.STICK_ACTIONS: R1 + R3, the addon's ring by default -- a key of ns.STICK_ACTIONS: R1 + L3, the pet spells or stances menu
	l1R1Action = "sheatheSmart", -- "sheatheSmart" or a key of ns.STICK_ACTIONS: L1 + R1
	l1StickUpAction = "autorun", -- a key of ns.STICK_ACTIONS: L1 + left stick forward
	l1RightStick = "zoom", -- a key of ns.L1_RIGHT_STICK: what the right stick does while L1 is held
	activeHighlight = "glow", -- a key of ns.ACTIVE_STYLES: how the selected bar is highlighted
	-- Keys of ns.HIGHLIGHT_COLORS: the highlight color of each bar while it is selected.
	activeColorBottom = "cyan", -- the bottom bars (L2, R2)
	activeColorTopLeft = "blue", -- the top left bar (double tap L2)
	activeColorTopRight = "blue", -- the top right bar (double tap R2)
	activeColorCombo = "green", -- the combos (L2 then R2, R2 then L2)
	activeStrength = 0.7, -- how bright that highlight is
	activeStrengthCombo = 0.7, -- the same for the combos
	flashStrength = 0.85, -- the flash over a bar whose set changes; 0 turns it off
	pressFeedback = true, -- a slot looks pressed while its button is held
	activeMarks = true, -- the cross and dots in the middle of the selected bar's groups
	backgroundAlpha = 0.7, -- opacity of that background
	backgroundBorder = "none", -- ns.BACKGROUND_BORDERS: a ring around each group of four slots
	slotBorder = "theme", -- ns.SLOT_BORDERS: a border around each slot
	showTopLeft = "always", -- "always", "selected" or "off": the double tap L2 bar (top left) shows always, only while selected, or never (no double tap)
	showTopRight = "always", -- the same for the double tap R2 bar (top right)
	scale = 1,
	x = 0,
	y = 90,
	clusterPadding = 16, -- gap between the D-pad and face button diamonds of a side
	buttonSpreadX = 1, -- left / right spacing of the buttons inside a diamond, 1 is normal
	buttonSpreadY = 1, -- up / down spacing of the buttons inside a diamond
	dpadTarget = "friend", -- "enemy", "friend" or "both": what D-pad left and right select
	spellbookAssign = true, -- Square in the spellbook puts the spell on a slot chosen on the crossbar
	petLeftButton = "show", -- hunters and warlocks: Forever's pet commands button, "show", "hide" or "disable"
	petRightButton = "show", -- and its pet spells button
	classMenuChord = "show", -- other classes: Forever's stance, form or aura menu from a trigger + shoulder, "show" or "disable"
	dpadTargetCombat = "same",
	crossEnemy = "forever", -- Cross on a living enemy target: "forever" (its attack toggle), "attack" (never stops) or "nothing" -- the same choices for combat, or "same" to keep dpadTarget
	dpadParty = "raid", -- "off", "raid" or "always": when the whole D-pad selects party members
	windowCamera = true, -- with a window open, the right stick turns the camera instead of scrolling lists
	l1DoubleTapParty = false, -- a double tap of L1 steps through the party or raid
	partyTargeting = "hard", -- "soft" or "hard": party selection sets a soft target or the real one
	skipPets = false, -- party selection leaves pets out, like FFXIV
	skipSelf = false, -- party selection with D-pad up / down leaves you out (in a party)
	lfgMessage = "Hello! Invite me for <activity> - <level> <class> <roles>.", -- whispered to a group's leader with A in Looking For Group
	lfgConfirm = true, -- ask before that whisper is sent
	r1Tap = true, -- a tap of R1 swaps the bottom and top rows between two pairs of sets, like FFXIV
	r1TapTop = true, -- the tap also swaps the top row
	r1TapBottomA = 1, -- pair A: the bottom row's set; with the top, the default layout
	r1TapTopA = 2, -- pair A: the top row's set (both halves)
	r1TapBottomB = 4, -- pair B: sets no other default uses (3 is the L2 + R2 bars)
	r1TapTopB = 5,
	chatLinks = true, -- open chat links under the cursor, and put Shift-clicked item links in chat
	openBagsWhenNeeded = false, -- experimental: open the bags for a spell that targets an item, and at the mailbox
	partyHighlight = "fill", -- "outline", "thick", "fill", "pulse" or "none": how the selected party member's frame is marked
	raidHighlight = "thick", -- the same, for raid frames
	partyPrompt = "bottom", -- "bottom", "top" or "off": the button prompt with the party frames
	partyMarker = "left", -- "off", "left" or "right": an arrow outside the selected party frame
	highlightColor = "gold", -- a key of ns.HIGHLIGHT_COLORS: the color of the highlight and the marker
	formsChangeBar = true,
	ringReleaseToUse = true, -- the ring uses the highlighted entry when the right stick is let go, not only on A
	formSet1 = 5, -- each form or stance has its own set, so both bottom sides change; R1 + button picks another
	formSet2 = 6,
	formSet3 = 7,
	formSet4 = 8,
	-- Each side's centre relative to the whole crossbar, moved with /gxiv move: the top bars sit
	-- closer in and lower than they used to, overlapping the bottom bars' outer groups.
	posLx = -108, posLy = 0,
	posRx = 108, posRy = 0,
	posWLx = -164, posWLy = 72,
	posWRx = 164, posWRy = 72,
	moveBarsSeparately = false, -- Move bars carries all four bars together; on, each bar has its own handle
}

function ns.SideOf(set, isRight)
	return set * 2 - (isRight and 0 or 1)
end

function ns.DescribeSide(side)
	local set = math.ceil(side / 2)
	return set, (side % 2 == 0) and "R" or "L"
end

-- The 8 gamepad storage slots of a form's stance bar. Forever only tells where they are while the
-- form is active, so the first slot is learned then and saved (ns.LearnStanceStorage); until then
-- the slots are empty (0).
function ns.StanceSlots(form)
	local first = ns.db and ns.db.stanceStorage and ns.db.stanceStorage[form]
	local slots = {}
	for i = 1, ns.NUM_SLOTS do
		slots[i] = first and (first + i - 1) or 0
	end
	return slots
end

-- Regular action slots backing the sides Forever's own storage cannot hold.
-- Forever's 3 pages give 9 eight-slot bars; the other 7 sides use bars 2-6.
local function BuildSideSlots()
	local util = GamepadActionBarBindingUtil
	local sides = {}

	local function FromPage(side, page, firstUnitSlot)
		local slots = {}
		for i = 1, ns.NUM_SLOTS do
			slots[i] = util and util.GetGamepadStorageSlotIndexFromPageAndPageUnitSlotID(page, firstUnitSlot + i - 1)
		end
		sides[side] = slots
	end

	local LEFT_BAR, RIGHT_BAR, BOTTOM_BAR = 9, 17, 25
	for page = 1, 3 do
		FromPage(page * 2 - 1, page, LEFT_BAR)
		FromPage(page * 2, page, RIGHT_BAR)
	end
	FromPage(7, 1, BOTTOM_BAR)
	FromPage(8, 2, BOTTOM_BAR)
	FromPage(9, 3, BOTTOM_BAR)

	local nextRegular = 13
	for side = 10, ns.NUM_SETS * 2 do
		local slots = {}
		for i = 1, ns.NUM_SLOTS do
			slots[i] = nextRegular
			nextRegular = nextRegular + 1
		end
		sides[side] = slots
	end

	-- The game's stance bars (bonus bars 1-4: stealth, cat, prowl, bear, moonkin, battle stance and
	-- so on). Forever keeps their 8 slots in its own gamepad storage, on the left side; the right side
	-- stays the player's own set (ApplyLayer), so it is 0 here.
	for form = 1, ns.NUM_FORMS do
		sides[ns.NUM_SETS * 2 + form * 2 - 1] = ns.StanceSlots(form)
		local right = {}
		for i = 1, ns.NUM_SLOTS do
			right[i] = 0
		end
		sides[ns.NUM_SETS * 2 + form * 2] = right
	end

	for side = 1, ns.NUM_SETS * 2 do
		for i = 1, ns.NUM_SLOTS do
			local slot = sides[side][i]
			if not slot then
				return nil
			end
			if side >= 10 and C_GamepadUI.IsValidGamepadActionStorageSlotIndex(slot) then
				ns.Print("Warning: slot", slot, "overlaps Forever's gamepad storage.")
			end
		end
	end
	return sides
end

-- A controller button as text, in the art of the controller in use. The fallback covers no controller.
function ns.ButtonMarkup(key, fallback, size)
	local utility = InputIconTextureSetUtility
	if utility and utility.GetActiveInputIconButtonTextures(key) then
		return CreateAtlasMarkup(utility.GetNormalActiveInputIconButtonTexture(key), size or 18, size or 18)
	end
	return fallback
end

-- Plain names for when a controller has no icon for a button. Text names buttons as {PAD1},
-- {PADLSHOULDER} and so on, never by one controller's labels; see AGENTS.md.
ns.BUTTON_NAMES = {
	PADLSHOULDER = "L1", PADRSHOULDER = "R1", PADLTRIGGER = "L2", PADRTRIGGER = "R2",
	PADLSTICK = "L3", PADRSTICK = "R3", PAD1 = "A", PAD2 = "B", PAD3 = "X", PAD4 = "Y",
	PADDUP = "Up", PADDDOWN = "Down", PADDLEFT = "Left", PADDRIGHT = "Right",
	PADBACK = "Back", PADFORWARD = "Start", PADLSTICKUP = "Left stick forward",
}

-- The button art fills only about half of its square, so icons in text are drawn this much larger
-- than the size asked for, which is the size the visible button should have.
local BUTTON_ART_SCALE = 1.8

-- Fills in the {KEY} buttons in a text: as icons of the controller in use, with the button about the
-- given size, or as plain names when size is nil (for search and chat).
function ns.ButtonText(text, size)
	return (text:gsub("{(%u[%u%d]*)}", function(key)
		local name = ns.BUTTON_NAMES[key] or key
		return size and ns.ButtonMarkup(key, name, math.floor(size * BUTTON_ART_SCALE + 0.5)) or name
	end))
end

-- Breadcrumbs: the last things this addon did that run the game's own code (CVar changes, calls
-- into Blizzard frames, slash commands, ring entries), kept in memory only. A taint error names the
-- addon but shows the stack of the Blizzard code that failed, often long after the call that tainted
-- it; the breadcrumbs before the error are saved with it to show what that call may have been.
local MAX_TRAIL = 40
local trail = {}

function ns.Trail(text)
	local now = GetTime()
	local last = trail[#trail]
	if last and last.text == text then
		last.count = last.count + 1
		last.time = now
		return
	end
	if #trail >= MAX_TRAIL then
		tremove(trail, 1)
	end
	trail[#trail + 1] = { text = text, time = now, combat = InCombatLockdown(), count = 1 }
end

-- The breadcrumbs as lines, oldest first, with how long before now each happened.
local function TrailLines()
	local now, lines = GetTime(), {}
	for _, crumb in ipairs(trail) do
		lines[#lines + 1] = format("-%.1fs%s %s%s", now - crumb.time, crumb.combat and " [combat]" or "", crumb.text,
			crumb.count > 1 and (" x" .. crumb.count) or "")
	end
	return lines
end

do
	local context = CreateFrame("Frame")
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
		context:RegisterEvent(event)
	end
	context:SetScript("OnEvent", function(_, event)
		ns.Trail(event)
	end)
end

-- What was going on when an error first happened: versions, character, place and the addon's state.
-- Unit names can be secret values in combat, so none go in. Each part is protected: the log must
-- never fail on a missing API.
local function ErrorContext()
	local parts = {}
	local function Add(label, getter)
		local ok, value = pcall(getter)
		if ok and value ~= nil then
			parts[#parts + 1] = label .. ": " .. tostring(value)
		end
	end
	Add("addon", function() return (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON, "Version") end)
	Add("client", function() local version, build = GetBuildInfo() return version .. " (" .. build .. ")" end)
	Add("class", function() local _, class = UnitClass("player") return class .. " level " .. UnitLevel("player") end)
	Add("form", function() return GetShapeshiftForm() end)
	Add("zone", function() return GetZoneText() .. (IsInInstance() and " (instance)" or "") end)
	Add("combat", function() return InCombatLockdown() and "yes" or "no" end)
	Add("group", function() return IsInRaid() and "raid" or IsInGroup() and "party" or "none" end)
	Add("mounted", function() return IsMounted() and "yes" or "no" end)
	Add("vehicle", function() return UnitInVehicle("player") and "yes" or "no" end)
	Add("gamepad UI", function() return ns.IsGamepadUI() and "on" or "off" end)
	Add("crossbar", function() return ns.IsActive and (ns.IsActive() and "active" or "off") end)
	Add("driver", function()
		local driver = _G.GamepadXIVDriver
		return driver and ("layer " .. tostring(driver:GetAttribute("fc-layer")) .. ", yield " .. tostring(driver:GetAttribute("fc-yield")))
	end)
	Add("play log", function() return ns.db and (ns.db.playLogOn and "on" or "off") end)
	return parts
end

-- Whether an error is this addon's: its taint, or its files in the message or the stack.
local function IsOurs(message, stack)
	local path = "AddOns/" .. ADDON .. "/"
	return message:find("tainted by '" .. ADDON .. "'", 1, true) or message:find(path, 1, true)
		or (stack and stack:find(path, 1, true)) and true or false
end

-- Keeps the latest errors in the saved variables, so a report does not depend on copying them by hand.
-- The first time an error happens, it also keeps what was going on (context) and, for this addon's
-- errors and blocked actions, the breadcrumbs before it (trail).
local MAX_LOGGED_ERRORS = 40
local pendingErrors = {}

local MAX_GROUPED_ACTIONS = 30

local function LogError(message, tainted, stack)
	local log = ns.db and ns.db.errorLog or pendingErrors
	message = tostring(message)
	stack = stack or debugstack(3, 30, 0)
	local ours = tainted and true or IsOurs(message, stack)
	local now = date("%Y-%m-%d %H:%M:%S")
	-- One tainted call can get dozens of Forever's actions blocked at once, one event each. They go in
	-- one entry, so they don't push every other error out of the log.
	local event, action = message:match("^(ADDON_ACTION_%u+): (.+)$")
	if event then
		for _, entry in ipairs(log) do
			if entry.event == event and entry.tainted == tainted and entry.time == now then
				entry.count = entry.count + 1
				if #entry.actions < MAX_GROUPED_ACTIONS and not tContains(entry.actions, action) then
					tinsert(entry.actions, action)
				end
				return
			end
		end
	end
	for _, entry in ipairs(log) do
		if entry.message == message then
			entry.count = entry.count + 1
			entry.time = date("%Y-%m-%d %H:%M:%S")
			entry.stack = stack
			entry.tainted = tainted or entry.tainted
			if ours and not entry.trail then
				entry.trail = TrailLines()
			end
			return
		end
	end
	if #log >= MAX_LOGGED_ERRORS then
		tremove(log, 1)
	end
	tinsert(log, { message = message, count = 1, first = now, time = now, stack = stack, tainted = tainted,
		event = event, actions = event and { action } or nil, context = ErrorContext(), trail = ours and TrailLines() or nil })
end

-- Names the values on Forever's chat and binding path that addon code has written, so a blocked
-- action can be traced to its cause without the taint log.
local MAX_TAINTED_FIELDS = 30

local function FindTaintedState()
	local found = {}
	local function Scan(name, target)
		if type(target) ~= "table" then
			return
		end
		for key in pairs(target) do
			local isSecure, owner = issecurevariable(target, key)
			if not isSecure and #found < MAX_TAINTED_FIELDS then
				tinsert(found, name .. "." .. tostring(key) .. " (" .. tostring(owner) .. ")")
			end
		end
	end

	local manager = GamepadMode and GamepadMode.FrameControlsManager
	Scan("GamepadMode", GamepadMode)
	Scan("FrameControlsManager", manager)
	Scan("fallthroughBindings", manager and manager.gamepadFallthroughCatcherBindings)
	Scan("InputBindingManager", GamepadSharedUtility and GamepadSharedUtility.InputBindingManager)
	Scan("GamepadMainActionBarFrame", GamepadMainActionBarFrame)
	Scan("ChatFrame1", ChatFrame1)
	Scan("ChatFrame1EditBox", ChatFrame1EditBox)
	for _, name in ipairs({ "ACTIVE_CHAT_EDIT_BOX", "LAST_ACTIVE_CHAT_EDIT_BOX", "DEFAULT_CHAT_FRAME" }) do
		local isSecure, owner = issecurevariable(name)
		if not isSecure then
			tinsert(found, name .. " (" .. tostring(owner) .. ")")
		end
	end
	return #found > 0 and table.concat(found, ", ") or "none found"
end

do
	-- Errors are read after Forever's error window has taken them, never by replacing the game's
	-- error handler: a handler of ours would run Forever's own one, which shows the error window and
	-- focuses it, as this addon's code. That marks Forever's window focus as tainted by this addon on
	-- every error of any addon, and in combat its action bars and bindings are then blocked.
	local errorsHooked = false
	local function HookErrors()
		local errors = ScriptErrorsFrame
		if errorsHooked or not errors or type(errors.DisplayMessageInternal) ~= "function" then
			return
		end
		errorsHooked = true
		hooksecurefunc(errors, "DisplayMessageInternal", function(_, message, _, stack)
			-- Warnings come without a stack; a message the game keeps secret can't be read.
			if stack and not (issecretvalue and (issecretvalue(message) or issecretvalue(stack))) then
				pcall(LogError, message, nil, stack)
			end
		end)
	end
	HookErrors()
	local errorsLoaded = CreateFrame("Frame")
	errorsLoaded:RegisterEvent("ADDON_LOADED")
	errorsLoaded:SetScript("OnEvent", function(_, _, name)
		if name == "Blizzard_ScriptErrorsFrame" then
			HookErrors()
		end
	end)

	local blocked = CreateFrame("Frame")
	blocked:RegisterEvent("ADDON_ACTION_BLOCKED")
	blocked:RegisterEvent("ADDON_ACTION_FORBIDDEN")
	blocked:SetScript("OnEvent", function(_, event, addon, action)
		if addon == ADDON then
			local scanned, tainted = pcall(FindTaintedState)
			pcall(LogError, event .. ": " .. tostring(action), scanned and tainted or "scan failed: " .. tostring(tainted))
		end
	end)
end

-- Catches the moment a value on Forever's chat and binding path is first written while this addon's
-- code is running, which an error later only shows as "tainted by GamepadXIV". The first time each
-- session, it saves what called it, the breadcrumbs and the loaded addons in taintOrigin, apart from
-- the error log so nothing pushes it out. Only reads; the hooks run after Forever's own functions.
local WATCHED = {
	{ "FrameControlsManager", function() return GamepadMode and GamepadMode.FrameControlsManager end,
		{ "SetFallThroughCatcherActive" }, { "fallThroughCatcherActive" } },
	{ "InputBindingManager", function() return GamepadSharedUtility and GamepadSharedUtility.InputBindingManager end,
		{ "AddBindingSet", "RemoveSet", "ClearBindings" }, { "currentCoreBindingActive" } },
	-- The chat box the game opened last, a global; reports showed it written while this addon ran.
	{ "ChatFrameUtil", function() return ChatFrameUtil end, { "ActivateChat", "DeactivateChat" }, {}, { "LAST_ACTIVE_CHAT_EDIT_BOX" } },
}

local function LoadedAddons()
	local names = {}
	local count = (C_AddOns and C_AddOns.GetNumAddOns or GetNumAddOns)()
	for i = 1, count do
		local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded)(i)
		if loaded then
			local name = (C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo)(i)
			names[#names + 1] = tostring(name)
		end
	end
	return table.concat(names, ", ")
end

local taintCaught = false

local function CheckTaint(where)
	if taintCaught or not (issecurevariable and ns.db) then
		return
	end
	for _, watch in ipairs(WATCHED) do
		local target = watch[2]()
		if type(target) == "table" then
			local checks = {}
			for _, field in ipairs(watch[4]) do
				tinsert(checks, { watch[1] .. "." .. field, issecurevariable(target, field) })
			end
			for _, global in ipairs(watch[5] or {}) do
				tinsert(checks, { global, issecurevariable(global) })
			end
			for _, check in ipairs(checks) do
				local name, isSecure, owner = check[1], check[2], check[3]
				if not isSecure and owner == ADDON then
					taintCaught = true
					ns.Trail("taint " .. name)
					local origin = { time = date("%Y-%m-%d %H:%M:%S"), field = name, where = where,
						stack = debugstack(3, 30, 0), trail = TrailLines(), context = ErrorContext() }
					local ok, addons = pcall(LoadedAddons)
					origin.addons = ok and addons or nil
					ns.db.taintOrigin = origin
					return
				end
			end
		end
	end
end
ns.CheckTaint = CheckTaint

-- /gxiv taint: whether each watched value is clean now, and what was caught this session.
function ns.TaintStatus()
	for _, watch in ipairs(WATCHED) do
		local target = watch[2]()
		for _, field in ipairs(watch[4]) do
			local isSecure, owner = issecurevariable(target or {}, field)
			ns.Print(watch[1] .. "." .. field .. ": " .. (isSecure and "clean" or ("tainted by " .. tostring(owner))))
		end
		for _, global in ipairs(watch[5] or {}) do
			local isSecure, owner = issecurevariable(global)
			ns.Print(global .. ": " .. (isSecure and "clean" or ("tainted by " .. tostring(owner))))
		end
	end
	local origin = ns.db.taintOrigin
	ns.Print(origin and ("Caught: " .. tostring(origin.field) .. " at " .. tostring(origin.time) .. " (" .. tostring(origin.where) .. ")")
		or "Nothing caught yet.")
end

do
	local hooked = {}
	local function Install()
		-- /gxiv taintwatch off leaves Forever's functions unhooked, to test whether the hooks matter.
		if ns.db and ns.db.taintWatchOff then
			return
		end
		for _, watch in ipairs(WATCHED) do
			local target = watch[2]()
			if type(target) == "table" and not hooked[watch[1]] then
				hooked[watch[1]] = true
				for _, method in ipairs(watch[3]) do
					if type(target[method]) == "function" then
						hooksecurefunc(target, method, function()
							if watch[1] == "ChatFrameUtil" then
								ns.Trail(method == "ActivateChat" and "chat opened" or "chat closed")
							end
							pcall(CheckTaint, watch[1] .. ":" .. method)
						end)
					end
				end
			end
		end
		-- Already written before the hooks were in place.
		pcall(CheckTaint, "install")
	end
	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("ADDON_LOADED")
	watcher:RegisterEvent("PLAYER_LOGIN")
	watcher:SetScript("OnEvent", function()
		pcall(Install)
	end)
	-- A value written by a path none of the hooks see is still caught within a second; its stack is
	-- only the timer's then, but the breadcrumbs show what came just before.
	local elapsed = 0
	watcher:SetScript("OnUpdate", function(_, delta)
		elapsed = elapsed + delta
		if elapsed >= 1 and not taintCaught and not (ns.db and ns.db.taintWatchOff) then
			elapsed = 0
			pcall(CheckTaint, "timer")
		end
	end)
end

-- What the game decides when loot opens, saved in lootLog (the last 30), for finding why auto loot
-- did not happen: the event's own autoLoot flag, the setting, the modifier, and what came just before.
do
	local MAX_LOOT_LOG = 30
	local function Bool(value)
		return value and "yes" or "no"
	end
	local loot = CreateFrame("Frame")
	for _, event in ipairs({ "LOOT_READY", "LOOT_OPENED", "LOOT_CLOSED" }) do
		pcall(loot.RegisterEvent, loot, event)
	end
	loot:SetScript("OnEvent", function(_, event, autoLoot, isFromItem)
		pcall(function()
			local db = ns.db
			if not db then
				return
			end
			local cvar = C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("autoLootDefault")
			local parts = { date("%H:%M:%S"), event }
			if event ~= "LOOT_CLOSED" then
				tinsert(parts, "autoLoot " .. tostring(autoLoot))
				tinsert(parts, "fromItem " .. tostring(isFromItem))
				tinsert(parts, "items " .. tostring(GetNumLootItems and GetNumLootItems()))
			end
			tinsert(parts, "cvar " .. tostring(cvar))
			tinsert(parts, "toggle " .. Bool(IsModifiedClick and IsModifiedClick("AUTOLOOTTOGGLE")))
			tinsert(parts, "shift " .. Bool(IsShiftKeyDown()) .. " ctrl " .. Bool(IsControlKeyDown()) .. " alt " .. Bool(IsAltKeyDown()))
			tinsert(parts, "A " .. tostring(GetBindingAction and GetBindingAction("PAD1", true)))
			local trail = TrailLines()
			tinsert(parts, "last: " .. table.concat(trail, " / ", math.max(1, #trail - 2)))
			db.lootLog = db.lootLog or {}
			if #db.lootLog >= MAX_LOOT_LOG then
				tremove(db.lootLog, 1)
			end
			tinsert(db.lootLog, table.concat(parts, " | "))
		end)
	end)
end

-- /gxiv petmenu: for 6 seconds, notes every named frame that shows and was hidden before, so the
-- frame Forever opens for its pet menus can be found. Printed and saved in petMenuDebug.
function ns.WatchPetMenu()
	local function VisibleNames()
		local names = {}
		local frame = EnumerateFrames()
		while frame do
			local ok, name = pcall(frame.GetName, frame)
			if ok and name and not (frame.IsForbidden and frame:IsForbidden()) and frame:IsVisible() then
				names[name] = true
			end
			frame = EnumerateFrames(frame)
		end
		return names
	end
	local before, seen, found = VisibleNames(), {}, {}
	local popups = {}
	for _, name in ipairs({ "GamepadPetActionFlyout", "GamepadPetSpellFlyout", "GamepadSpellFlyout" }) do
		local popup = _G[name]
		tinsert(popups, name .. (popup and (popup:IsProtected() and " protected" or " not protected") or " missing"))
	end
	ns.Print("Open the pet menu now (6 seconds).")
	local ticks = 0
	local ticker
	ticker = C_Timer.NewTicker(0.2, function()
		ticks = ticks + 1
		for name in pairs(VisibleNames()) do
			if not before[name] and not seen[name] then
				seen[name] = true
				tinsert(found, name)
			end
		end
		if ticks >= 30 then
			ticker:Cancel()
			local driver = _G.GamepadXIVDriver
			local text = "shown: " .. (#found > 0 and table.concat(found, ", ") or "nothing new") .. " | " .. table.concat(popups, ", ")
				.. " | petChords " .. tostring(driver and driver:GetAttribute("fc-petChords"))
				.. " off L " .. tostring(driver and driver:GetAttribute("fc-petOff-L")) .. " R " .. tostring(driver and driver:GetAttribute("fc-petOff-R"))
			ns.db.petMenuDebug = text
			ns.Print(text)
		end
	end)
end

-- /gxiv log: a quiet log of play, saved to playLog and never printed, for finding what went wrong in
-- a dungeon or raid. Unit names can be secret values in combat, so only unit tokens and spell IDs
-- go in. Every write is protected: the log must never break play.
local MAX_PLAY_LOG = 2000

function ns.PlayLog(...)
	local db = ns.db
	if not (db and db.playLogOn) then
		return
	end
	local count = select("#", ...)
	local parts = { (date("%H:%M:%S")) }
	for i = 1, count do
		local ok, text = pcall(tostring, (select(i, ...)))
		parts[#parts + 1] = ok and text or "?"
	end
	local ok, line = pcall(table.concat, parts, " ")
	db.playLog = db.playLog or {}
	if #db.playLog >= MAX_PLAY_LOG then
		tremove(db.playLog, 1)
	end
	tinsert(db.playLog, ok and line or "?")
end

local function LayerState()
	local driver = _G.GamepadXIVDriver
	if not driver then
		return "no driver"
	end
	return "layer " .. tostring(driver:GetAttribute("fc-layer")) .. " soft '" .. tostring(driver:GetAttribute("fc-soft"))
		.. "' back '" .. tostring(driver:GetAttribute("fc-backAction")) .. "' ring " .. tostring(driver:GetAttribute("fc-ring"))
		.. " clear " .. tostring(driver:GetAttribute("fc-clear")) .. " yield " .. tostring(driver:GetAttribute("fc-yield"))
end

do
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UI_ERROR_MESSAGE", "UNIT_SPELLCAST_FAILED",
			"UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_INTERRUPTED", "GROUP_ROSTER_UPDATE", "START_LOOT_ROLL",
			"PLAYER_TARGET_CHANGED", "PLAYER_DEAD", "PLAYER_UNGHOST", "ZONE_CHANGED_NEW_AREA" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", function(_, event, ...)
		if not (ns.db and ns.db.playLogOn) then
			return
		end
		pcall(function(...)
			if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_DEAD" then
				ns.PlayLog(event, LayerState())
			elseif event == "UI_ERROR_MESSAGE" then
				local _, message = ...
				ns.PlayLog("error message:", message, "|", LayerState())
			elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_SUCCEEDED" then
				local unit, _, spellID = ...
				if unit == "player" then
					local target = UnitExists("target") and (UnitIsUnit("target", "player") and "self" or UnitCanAttack("player", "target")
						and "enemy" or "friend") or "none"
					ns.PlayLog(event == "UNIT_SPELLCAST_SUCCEEDED" and "cast" or event, spellID, "target", target, "|", LayerState())
				end
			elseif event == "GROUP_ROSTER_UPDATE" then
				ns.PlayLog("group:", GetNumGroupMembers(), IsInRaid() and "raid" or "party")
			elseif event == "PLAYER_TARGET_CHANGED" then
				local kind = not UnitExists("target") and "none" or UnitIsUnit("target", "player") and "self"
					or UnitCanAttack("player", "target") and "enemy" or "friend"
				-- Which group member, as party selection on Hard sets the real target.
				local member = ""
				if kind == "friend" then
					local prefix, count = IsInRaid() and "raid" or "party", IsInRaid() and 40 or 4
					for i = 1, count do
						for _, unit in ipairs({ prefix .. i, prefix .. "pet" .. i }) do
							if member == "" and UnitExists(unit) and UnitIsUnit(unit, "target") then
								member = unit
							end
						end
					end
				end
				ns.PlayLog("target:", kind, member)
			else
				ns.PlayLog(event, ...)
			end
		end, ...)
	end)
end

function ns.TogglePlayLog()
	ns.db.playLogOn = not ns.db.playLogOn
	if ns.db.playLogOn then
		ns.db.playLog = {}
		ns.PlayLog("log on", GetZoneText and GetZoneText(), LayerState())
	end
	ns.Print("Play log", ns.db.playLogOn and "on, quietly. /gxiv log again stops it; /reload writes it." or "off.")
end

function ns.Print(...)
	ns.Trail("print")
	print(ns.ICON_MARKUP .. " |cff66ccffGamepad XIV:|r", ...)
end

function ns.IsGamepadUI()
	return InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled()
end

-- One-time changes to saved settings, in order. Each runs once per character profile: the number of
-- the last one that ran is saved, so later versions never run it again and never undo what players
-- set afterwards. Only add new entries at the end; never change or remove one that has shipped.
local APPEARANCE_KEYS = {
	"theme", "background", "backgroundBorder", "slotFill", "slotBorder", "backgroundAlpha",
	"activeHighlight", "activeColorBottom", "activeColorTopLeft", "activeColorTopRight", "activeColorCombo",
	"activeStrength", "activeMarks",
}
local MIGRATIONS = {
	-- 1 (0.1.8): the redone crossbar themes. Everyone starts once on the new look.
	function(db)
		for _, key in ipairs(APPEARANCE_KEYS) do
			db[key] = ns.DEFAULTS[key]
		end
	end,
	-- 2 (0.1.9): a form on the same set as the normal bar never changed it. It goes to the game's
	-- stance bar instead.
	function(db)
		for form = 1, ns.NUM_FORMS do
			if db["formSet" .. form] == (db.set or 1) then
				db["formSet" .. form] = 0
			end
		end
	end,
	-- 3 (0.1.9): a form changes both bottom sides, so forms on the game's stance bar (8 slots, left
	-- side only) go back to their own set, 5-8.
	function(db)
		for form = 1, ns.NUM_FORMS do
			if db["formSet" .. form] == 0 then
				db["formSet" .. form] = 4 + form
			end
		end
	end,
	-- 4 (0.1.9): letting go of the stick uses the ring's entry, now on by default.
	function(db)
		db.ringReleaseToUse = true
	end,
	-- 5 (0.1.9): the ring's Shop is the Toy Box now.
	function(db)
		for _, page in ipairs(db.ringPages or {}) do
			for segment, entry in pairs(page.slots or {}) do
				if type(entry) == "table" and entry.builtin == "store" then
					page.slots[segment] = { toybox = true }
				end
			end
		end
	end,
	-- 6: the group finder message names the activity; a message left on the first default follows.
	function(db)
		if db.lfgMessage == "Hello! Invite me <level> <class>." or db.lfgMessage == "Hello! Invite me for <activity> <level> <class>." then
			db.lfgMessage = "Hello! Invite me for <activity> - <level> <class>."
		end
	end,
	-- 7: the quick set swap's first pairs (1 + 5, 2 + 6) left the default top row (set 2) behind,
	-- so its first tap emptied the top row. Pair A is now the default layout, 1 + 2, and pair B
	-- 3 + 4; a top row the old pairs moved to set 5 or 6 goes back to set 2.
	function(db)
		if db.r1TapBottomA == 1 and db.r1TapTopA == 5 and db.r1TapBottomB == 2 and db.r1TapTopB == 6 then
			db.r1TapTopA, db.r1TapBottomB, db.r1TapTopB = 2, 3, 4
			if (db.sideWL == 9 or db.sideWL == 11) and db.sideWR == db.sideWL + 1 then
				db.sideWL, db.sideWR = 3, 4
			end
		end
	end,
	-- 8: pair B 3 + 4 put the L2 + R2 bars (set 3) on the bottom row; it is now 4 + 5.
	function(db)
		if db.r1TapBottomA == 1 and db.r1TapTopA == 2 and db.r1TapBottomB == 3 and db.r1TapTopB == 4 then
			db.r1TapBottomB, db.r1TapTopB = 4, 5
		end
	end,
	-- 9: the quick set swap is on by default; it was off while it was tested.
	function(db)
		db.r1Tap = true
	end,
	-- 10: the bars' default layout is closer together. Bars still where the old default put them move.
	function(db)
		if db.posLx == -158 and db.posLy == 0 and db.posRx == 158 and db.posRy == 0
				and db.posWLx == -243 and db.posWLy == 124 and db.posWRx == 243 and db.posWRy == 124 then
			for _, key in ipairs({ "posLx", "posLy", "posRx", "posRy", "posWLx", "posWLy", "posWRx", "posWRy" }) do
				db[key] = ns.DEFAULTS[key]
			end
		end
	end,
	-- 11: the group finder message also names the roles ticked in Looking For Group.
	function(db)
		if db.lfgMessage == "Hello! Invite me for <activity> - <level> <class>." then
			db.lfgMessage = "Hello! Invite me for <activity> - <level> <class> <roles>."
		end
	end,
	-- 12: the combos have their own brightness, which starts at what the selected bar brightness was.
	function(db)
		if db.activeStrength then
			db.activeStrengthCombo = db.activeStrength
		end
	end,
	-- 13: linking items in chat is on by default again; v0.1.26 had it off.
	function(db)
		db.chatLinks = true
	end,
}

local function RunMigrations(db)
	local done = db.migration or 0
	for index = done + 1, #MIGRATIONS do
		MIGRATIONS[index](db)
	end
	db.migration = math.max(done, #MIGRATIONS)
end
ns.RunMigrations = RunMigrations

local function InitDB()
	GamepadXIVDB = GamepadXIVDB or {}
	GamepadXIVDB.popupLog = nil -- left by 0.1.4's temporary logging
	GamepadXIVDB.taintTrace = nil -- left by a temporary debug session
	GamepadXIVDB.targetTrace = nil -- left by an earlier temporary debug session
	GamepadXIVDB.holdLog = nil -- left by the Press and Hold Casting test
	GamepadXIVDB.pressHoldCasting = nil -- a setting that was tried and removed
	GamepadXIVDB.wxhbFourSlots = nil -- removed: a double tap always uses all 8 slots of the top bar
	GamepadXIVDB.themeLooks = nil -- an earlier, unreleased form of migration 1
	GamepadXIVDB.startKey = nil -- left by the menu button experiment
	GamepadXIVDB.startKeyLog = nil
	GamepadXIVDB.formLog = nil -- left by a temporary debug session
	GamepadXIVDB.backLog = nil -- left by the Back button debug sessions
	-- Themes that were removed fall back to Round.
	local removed = { sleek = true, rounded = true, slate = true, halo = true, neon = true, glass = true }
	if removed[GamepadXIVDB.theme] then
		GamepadXIVDB.theme = "round"
	end
	for key, value in pairs(ns.DEFAULTS) do
		if GamepadXIVDB[key] == nil then
			GamepadXIVDB[key] = (type(value) == "table") and {} or value
		end
	end
	RunMigrations(GamepadXIVDB)
	ns.db = GamepadXIVDB
	if ns.LoadProfileAtStart then
		pcall(ns.LoadProfileAtStart)
	end
	for _, entry in ipairs(pendingErrors) do
		tinsert(ns.db.errorLog, entry)
	end
	wipe(pendingErrors)
end

local SLASH_HELP = {
	"/gxiv status - shows what is active",
	"/gxiv on | off - turns the layout on or off",
	"/gxiv config - settings (also L2/R2 + Start)",
	"/gxiv clear - move, remove or add an ability (also L2/R2 + R3)",
	"/gxiv tutorial - a short tutorial of the buttons",
	"/gxiv move - drag the bars around the screen (Shift + drag moves all of them; also L2/R2 + Back)",
	"/gxiv minimap - shows or hides the minimap icon",
	"/gxiv debug - reports bindings, L1 and the right stick (/gxiv debug quiet: saved only, not printed)",
	"/gxiv log - a quiet log of combat, casts, error messages and party selection, for bug reports",
	"/gxiv reset - put the bars back in their default place",
	"/gxiv wxhb <L|R> <set> <L|R> - side shown by a double tap, e.g. /gxiv wxhb R 4 L",
	"/gxiv exhb <LR|RL> <set> <L|R> - side shown by L2>R2 or R2>L2",
	"/gxiv tap <2-6> - double tap window, in 0.2s ticks",
	"/gxiv scale <0.5-1.5> - bar scale",
	"/gxiv priority on | off - use if R2 does nothing in game",
}

local function HandleSideCommand(prefix, which, setText, sideText, valid)
	local set = tonumber(setText)
	sideText = sideText and sideText:upper()
	which = which and which:upper()
	if not (valid[which] and set and set >= 1 and set <= ns.NUM_SETS and (sideText == "L" or sideText == "R")) then
		ns.Print("Usage: see /gxiv help")
		return
	end
	ns.db["side" .. prefix .. which] = ns.SideOf(set, sideText == "R")
	ns.Sync()
	ns.Print(prefix .. which, "now shows set", set, sideText)
end

local function HandleSlash(message)
	local command, a, b, c = strsplit(" ", strlower(strtrim(message or "")))
	if command == "on" or command == "off" then
		ns.db.enabled = (command == "on")
		ns.Sync()
	elseif command == "edit" then
		ns.ToggleEditor()
	elseif command == "config" then
		ns.OpenConfig()
	elseif command == "clear" then
		ns.StartClear()
	elseif command == "tutorial" or command == "tour" then
		ns.StartTutorial()
	elseif command == "move" then
		ns.ToggleMove()
	elseif command == "reset" then
		ns.ResetPositions()
	elseif command == "minimap" then
		ns.db.minimapShown = not ns.db.minimapShown
		ns.UpdateMinimapButton()
	elseif command == "debug" then
		-- "/gxiv debug quiet" only saves the report, for when chat should stay clean (a dungeon).
		local quiet = a == "quiet"
		ns.PrintDebug(quiet)
		if quiet then
			ns.Print("Debug report saved quietly; /reload to write it.")
		end
	elseif command == "ringlog" then
		ns.ToggleRingLog()
	elseif command == "log" then
		ns.TogglePlayLog()
	elseif command == "taint" then
		ns.TaintStatus()
	elseif command == "taintwatch" then
		ns.db.taintWatchOff = a == "off" or nil
		ns.Print("Taint watch " .. (ns.db.taintWatchOff and "off" or "on") .. " after a /reload.")
	elseif command == "petmenu" then
		ns.WatchPetMenu()
	elseif command == "lfglog" then
		ns.ToggleLfgLog()
	elseif command == "wxhb" then
		HandleSideCommand("W", a, b, c, { L = true, R = true })
	elseif command == "exhb" then
		local which = a and a:upper()
		if which == "LR" or which == "RL" then
			HandleSideCommand("", which, b, c, { LR = true, RL = true })
		else
			ns.Print("Usage: see /gxiv help")
		end
	elseif command == "tap" then
		local ticks = tonumber(a)
		if ticks and ticks >= 2 and ticks <= 6 then
			ns.db.doubleTapTicks = ticks
			ns.Sync()
		end
	elseif command == "scale" then
		local scale = tonumber(a)
		if scale and scale >= 0.5 and scale <= 1.5 then
			ns.db.scale = scale
			ns.Sync()
		end
	elseif command == "priority" then
		ns.db.priorityBindings = (a == "on")
		ns.Sync()
		ns.Print("priority bindings:", tostring(ns.db.priorityBindings))
	elseif command == "status" then
		ns.Print("enabled:", tostring(ns.db.enabled), "gamepad UI:", tostring(ns.IsGamepadUI()), "set:", ns.db.set)
		ns.Print("active:", tostring(ns.IsActive()), "pending combat sync:", tostring(ns.syncPending or false))
		ns.Print("priority bindings:", tostring(ns.db.priorityBindings))
		ns.PrintInputCVars(ns.Print)
		for i = 1, 8 do
			ns.Print("Forever GAMEPADACTIONBUTTON" .. i, tostring(GetBindingKey("GAMEPADACTIONBUTTON" .. i)))
		end
	else
		for _, line in ipairs(SLASH_HELP) do
			ns.Print(line)
		end
	end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" and name == ADDON then
		InitDB()
		ns.HookExperimentalWarning()
	elseif event == "PLAYER_LOGIN" or event == "PLAYER_REGEN_ENABLED" then
		-- A /reload in combat cannot create secure frames until combat ends.
		if InCombatLockdown() then
			loader:RegisterEvent("PLAYER_REGEN_ENABLED")
			return
		end
		loader:UnregisterEvent("PLAYER_REGEN_ENABLED")
		ns.sideSlots = BuildSideSlots()
		if not ns.sideSlots then
			ns.Print("Forever's gamepad action bars are not available. The addon stays off.")
			return
		end
		ns.CreateBar()
		ns.CreateInput()
		ns.CreateEditor()
		ns.CreateConfig()
		ns.CreateMinimapButton()
		SLASH_GAMEPADXIV1 = "/fc"
		SLASH_GAMEPADXIV2 = "/gxiv"
		SlashCmdList.GAMEPADXIV = HandleSlash
		ns.Sync()
	end
end)
