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
	doubleTapTicks = 2, -- secure timer ticks (0.2s each): window of 0.2-0.4s
	priorityBindings = false, -- true only if Forever's own bindings outrank ours on this client
	autoFace = false,
	experimentalAccepted = false,
	experimentalDeclined = false,
	errorLog = {},
	minimapShown = true,
	minimapAngle = 220,
	savedCVars = {},
	holdToWalk = true,
	triggerMode = "hold", -- hold, toggle or mixed, like FFXIV's cross hotbar activation
	wxhbFourSlots = false, -- WXHB swaps only the face buttons, like FFXIV's 4 slot option
	dimAlpha = 0.55,
	showKeyLabels = false,
	rangeIndicator = true,
	showInteractPrompt = true,
	promptX = 0, promptY = 170, -- over the character, from the middle of the screen
	keyIconSize = 34, -- the art has wide empty margins, so this is larger than it looks
	showSetLabels = true,
	scale = 1,
	x = 0,
	y = 90,
	clusterPadding = 16, -- gap between the D-pad and face button diamonds of a side
	formsChangeBar = true,
	formSet1 = 5, -- set each form or stance starts on; R1 + button changes it while in that form
	formSet2 = 6,
	formSet3 = 7,
	formSet4 = 8,
	-- Each side's centre relative to the whole crossbar, moved with /fc move.
	posLx = -158, posLy = 0,
	posRx = 158, posRy = 0,
	posWLx = -243, posWLy = 124,
	posWRx = 243, posWRy = 124,
}

function ns.SideOf(set, isRight)
	return set * 2 - (isRight and 0 or 1)
end

function ns.DescribeSide(side)
	local set = math.ceil(side / 2)
	return set, (side % 2 == 0) and "R" or "L"
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

-- Keeps the latest errors in the saved variables, so a report does not depend on copying them by hand.
local MAX_LOGGED_ERRORS = 40
local pendingErrors = {}

local function LogError(message, tainted)
	local log = ns.db and ns.db.errorLog or pendingErrors
	message = tostring(message)
	for _, entry in ipairs(log) do
		if entry.message == message then
			entry.count = entry.count + 1
			entry.time = date("%H:%M:%S")
			entry.stack = debugstack(3, 30, 0)
			entry.tainted = tainted or entry.tainted
			return
		end
	end
	if #log >= MAX_LOGGED_ERRORS then
		tremove(log, 1)
	end
	tinsert(log, { message = message, count = 1, time = date("%H:%M:%S"), stack = debugstack(3, 30, 0), tainted = tainted })
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
	local previousHandler = geterrorhandler()
	seterrorhandler(function(message, ...)
		pcall(LogError, message)
		return previousHandler(message, ...)
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

function ns.Print(...)
	print(ns.ICON_MARKUP .. " |cff66ccffGamepad XIV:|r", ...)
end

function ns.IsGamepadUI()
	return InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled()
end

local function InitDB()
	GamepadXIVDB = GamepadXIVDB or {}
	for key, value in pairs(ns.DEFAULTS) do
		if GamepadXIVDB[key] == nil then
			GamepadXIVDB[key] = (type(value) == "table") and {} or value
		end
	end
	ns.db = GamepadXIVDB
	for _, entry in ipairs(pendingErrors) do
		tinsert(ns.db.errorLog, entry)
	end
	wipe(pendingErrors)
end

local SLASH_HELP = {
	"/fc status - shows what is active",
	"/fc on | off - turns the layout on or off",
	"/fc edit - edit the crossbar slots (also L2/R2 + Back)",
	"/fc config - settings (also L2/R2 + Start)",
	"/fc clear - move or remove an ability (also L2/R2 + R3)",
	"/fc move - drag the bars around the screen (Shift + drag moves all of them)",
	"/fc minimap - shows or hides the minimap icon",
	"/fc debug - reports bindings, L1 and the right stick",
	"/fc reset - put the bars back in their default place",
	"/fc wxhb <L|R> <set> <L|R> - side shown by a double tap, e.g. /fc wxhb R 4 L",
	"/fc exhb <LR|RL> <set> <L|R> - side shown by L2>R2 or R2>L2",
	"/fc tap <2-4> - double tap window, in 0.2s ticks",
	"/fc scale <0.5-1.5> - bar scale",
	"/fc priority on | off - use if R2 does nothing in game",
}

local function HandleSideCommand(prefix, which, setText, sideText, valid)
	local set = tonumber(setText)
	sideText = sideText and sideText:upper()
	which = which and which:upper()
	if not (valid[which] and set and set >= 1 and set <= ns.NUM_SETS and (sideText == "L" or sideText == "R")) then
		ns.Print("Usage: see /fc help")
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
	elseif command == "move" then
		ns.ToggleMove()
	elseif command == "reset" then
		ns.ResetPositions()
	elseif command == "minimap" then
		ns.db.minimapShown = not ns.db.minimapShown
		ns.UpdateMinimapButton()
	elseif command == "debug" then
		ns.PrintDebug()
	elseif command == "wxhb" then
		HandleSideCommand("W", a, b, c, { L = true, R = true })
	elseif command == "exhb" then
		local which = a and a:upper()
		if which == "LR" or which == "RL" then
			HandleSideCommand("", which, b, c, { LR = true, RL = true })
		else
			ns.Print("Usage: see /fc help")
		end
	elseif command == "tap" then
		local ticks = tonumber(a)
		if ticks and ticks >= 2 and ticks <= 4 then
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
