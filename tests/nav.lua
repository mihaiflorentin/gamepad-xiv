-- Offline checks of the navigation core (Nav.lua): the window registry, the Back cycle, focus and
-- keys, and moving a cursor by screen position. Not loaded by the game.
-- Run from the addon folder with: lua5.1 tests/nav.lua

local frames, events = {}, {}
function CreateFrame(_, name)
	local frame = { name = name, scripts = {}, shown = true }
	function frame:SetScript(script, fn) self.scripts[script] = fn end
	function frame:RegisterForClicks(...) self.clicks = { ... } end
	function frame:RegisterEvent(event) events[event] = self end
	function frame:Show() self.shown = true end
	function frame:Hide() self.shown = false end
	function frame:GetName() return self.name end
	if name then _G[name] = frame end
	table.insert(frames, frame)
	return frame
end
UIParent = CreateFrame("Frame", "UIParent")

local combat = false
function InCombatLockdown() return combat end
local bindings = {}
function SetOverrideBindingClick(_, _, key, button) bindings[key] = "CLICK " .. button .. ":LeftButton" end
function ClearOverrideBindings() bindings = {} end
function SetOverrideBinding(_, _, key, action) bindings[key] = action end
function GetBindingAction(key) return bindings[key] or "" end
local errors = {}
function geterrorhandler() return function(err) table.insert(errors, err) end end

local ns = { db = {} }
assert(loadfile("Repeat.lua"))("GamepadXIV", ns)
assert(loadfile("Nav.lua"))("GamepadXIV", ns)

local fails = 0
local function Check(label, actual, expected)
	if actual ~= expected then
		fails = fails + 1
		print("FAIL " .. label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

-- Windows: open flags the tests flip, and a log of what their keys did.
local open, pressed, focusLog = {}, {}, {}
local function Window(name, group, order, keys)
	local window = { name = name, group = group, order = order, keys = {} }
	window.IsOpen = function() return open[name] end
	for _, key in ipairs(keys or { "PAD1", "PADDUP" }) do
		window.keys[key] = function() table.insert(pressed, name .. ":" .. key) end
	end
	window.OnFocus = function() table.insert(focusLog, "+" .. name) end
	window.OnBlur = function() table.insert(focusLog, "-" .. name) end
	return ns.NavRegister(window)
end

Window("Bags", "player", 10)
Window("Trade", "transaction", 10, { "PAD1", "PAD2" })
Window("Invite", "popup", 10)
Window("Map", "player", 20)
Window("Chat", "hud", 10)

local function Names(list)
	local names = {}
	for i, window in ipairs(list) do names[i] = window.name end
	return table.concat(names, ",")
end

-- Order: popups, then trade windows, then the player's windows, then the HUD; only open ones.
open.Bags, open.Trade, open.Map, open.Chat = true, true, true, true
Check("open windows in priority order", Names(ns.NavOpenWindows()), "Trade,Bags,Map,Chat")
open.Invite = true
Check("a popup comes first", Names(ns.NavOpenWindows()), "Invite,Trade,Bags,Map,Chat")
open.Invite = nil

-- The player's own order and skips.
ns.db.navOrder = { Chat = 1 }
Check("custom order moves a window", Names(ns.NavOpenWindows()), "Chat,Trade,Bags,Map")
ns.db.navOrder = nil
ns.db.navSkip = { Map = true }
Check("a skipped window is left out", Names(ns.NavOpenWindows()), "Trade,Bags,Chat")
ns.db.navSkip = nil

-- Back steps forward and wraps; the other way steps back and wraps.
Check("first Back focuses the first", ns.NavCycle(1), "Trade")
Check("next", ns.NavCycle(1), "Bags")
Check("next again", ns.NavCycle(1), "Map")
Check("next again", ns.NavCycle(1), "Chat")
Check("wraps to the first", ns.NavCycle(1), "Trade")
Check("back wraps to the last", ns.NavCycle(-1), "Chat")
Check("back", ns.NavCycle(-1), "Map")
ns.NavFocus(nil)
Check("backwards with nothing focused: the last", ns.NavCycle(-1), "Chat")

-- Focus calls OnBlur and OnFocus and binds the window's keys.
focusLog = {}
ns.NavFocus("Trade")
Check("blur then focus", table.concat(focusLog, ","), "-Chat,+Trade")
Check("PAD1 bound to the nav button", bindings.PAD1, "CLICK GamepadXIVNavPAD1:LeftButton")
Check("PAD2 bound for Trade", bindings.PAD2, "CLICK GamepadXIVNavPAD2:LeftButton")
Check("D-pad up not taken by Trade", bindings.PADDUP, nil)
Check("Back never taken", bindings.PADBACK, nil)

-- A key press goes to the focused window.
pressed = {}
GamepadXIVNavPAD1.scripts.OnClick(GamepadXIVNavPAD1, "LeftButton", true)
Check("press reaches Trade", pressed[1], "Trade:PAD1")
ns.NavFocus("Bags")
pressed = {}
GamepadXIVNavPAD1.scripts.OnClick(GamepadXIVNavPAD1, "LeftButton", true)
Check("press reaches Bags after the focus moved", pressed[1], "Bags:PAD1")
Check("Bags binds the D-pad", bindings.PADDUP, "CLICK GamepadXIVNavPADDUP:LeftButton")
Check("Bags doesn't bind PAD2", bindings.PAD2, nil)

-- An error in a handler is reported and the press doesn't break the next one.
ns.NavWindow("Bags").keys.PAD1 = function() error("boom") end
errors = {}
GamepadXIVNavPAD1.scripts.OnClick(GamepadXIVNavPAD1, "LeftButton", true)
Check("handler error reported", #errors, 1)
ns.NavWindow("Bags").keys.PAD1 = function() table.insert(pressed, "Bags:PAD1") end

-- The driver took a key: noticed, then bound again.
bindings.PADDUP = "CLICK GamepadXIVDriver:LeftButton"
Check("lost key noticed", ns.Nav.BindingsLost(), true)
ns.Nav.ApplyBindings()
Check("bound again", bindings.PADDUP, "CLICK GamepadXIVNavPADDUP:LeftButton")

-- A closed window hands the focus to the next open one.
open.Bags = nil
ns.NavClosed("Bags")
Check("closing moves the focus on", ns.NavFocused(), "Trade")

-- A popup that opens takes the focus; a lower window that opens doesn't.
open.Invite = true
Check("popup takes the focus", ns.NavOpened("Invite"), true)
Check("focused popup", ns.NavFocused(), "Invite")
open.Bags = true
Check("bags opening doesn't take it from the popup", ns.NavOpened("Bags"), false)
Check("still the popup", ns.NavFocused(), "Invite")
open.Invite = nil

-- Nothing to focus: unknown or closed windows.
Check("unknown window", ns.NavFocus("Nope"), false)
open.Map = nil
Check("closed window", ns.NavFocus("Map"), false)

-- Combat start ends the focus and gives every key back; in combat focus can't change.
ns.NavFocus("Trade")
events.PLAYER_REGEN_DISABLED.scripts.OnEvent(events.PLAYER_REGEN_DISABLED, "PLAYER_REGEN_DISABLED")
Check("combat ends the focus", ns.NavFocused(), nil)
Check("combat gives the keys back", next(bindings), nil)
combat = true
Check("no focus in combat", ns.NavFocus("Trade"), false)
Check("no cycle focus in combat", ns.NavFocused(), nil)
combat = false

-- All windows closed: Back focuses nothing.
for name in pairs(open) do open[name] = nil end
Check("nothing open", ns.NavCycle(1), nil)
Check("no focus", ns.NavFocused(), nil)

-- Moving by screen position: a 3 x 2 grid of 10 x 10 slots, 2 apart, top row first.
--   1 2 3
--   4 5 6
local grid = {}
for row = 0, 1 do
	for col = 0, 2 do
		table.insert(grid, { l = col * 12, b = 100 - row * 12, w = 10, h = 10 })
	end
end
Check("right", ns.NavPick(grid, 1, "RIGHT"), 2)
Check("down", ns.NavPick(grid, 2, "DOWN"), 5)
Check("left", ns.NavPick(grid, 6, "LEFT"), 5)
Check("up", ns.NavPick(grid, 4, "UP"), 1)
Check("right wraps to the row's start", ns.NavPick(grid, 3, "RIGHT"), 1)
Check("left wraps to the row's end", ns.NavPick(grid, 4, "LEFT"), 6)
Check("down wraps to the column's top", ns.NavPick(grid, 5, "DOWN"), 2)
Check("no wrap when asked", ns.NavPick(grid, 3, "RIGHT", false), 3)
ns.Repeating = true
Check("held D-pad stops at the end", ns.NavPick(grid, 3, "RIGHT"), 3)
ns.Repeating = nil

-- A short last row: down from the middle of a full row lands on the nearest in the short row.
--   1 2 3
--   4
table.remove(grid, 6); table.remove(grid, 5)
Check("down to a short row", ns.NavPick(grid, 1, "DOWN"), 4)
Check("down from beyond the short row's end: wraps up the column", ns.NavPick(grid, 3, "DOWN"), 3)

-- A list of rows: up from the top wraps to the bottom.
local list = {}
for i = 1, 4 do table.insert(list, { l = 0, b = 100 - i * 20, w = 100, h = 18 }) end
Check("list down", ns.NavPick(list, 1, "DOWN"), 2)
Check("list up wraps", ns.NavPick(list, 1, "UP"), 4)

-- Hints draw the buttons.
ns.ButtonText = function(text) return (text:gsub("{(%u[%u%d]*)}", "<%1>")) end
local hinted = ns.NavRegister({ name = "Hinted", IsOpen = function() return true end,
	Hint = function() return "{PAD1} Use   {PAD2} Back" end })
Check("hint text", ns.NavHint(hinted), "<PAD1> Use   <PAD2> Back")
Check("no hint", ns.NavHint(ns.NavWindow("Map")), "")

if fails == 0 then
	print("nav: all checks passed")
else
	print("nav: " .. fails .. " failed")
	os.exit(1)
end
