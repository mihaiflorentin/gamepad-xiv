-- Offline checks of the breadcrumbs saved with taint errors (Core.lua). Not loaded by the game.
-- Run from the addon folder with: lua5.1 tests/trail.lua

format = string.format
tinsert, tremove = table.insert, table.remove
date = os.date
function tContains(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
local stackText = "stack"
function debugstack() return stackText end
function GetBuildInfo() return "1.60.1", "12345" end
function UnitClass() return "Druid", "DRUID" end
function UnitLevel() return 60 end
local clock, combat = 100, false
function GetTime() return clock end
function InCombatLockdown() return combat end
local handler
function geterrorhandler() return function() end end
function seterrorhandler(fn) handler = fn end
local function Frame()
	return setmetatable({}, { __index = function() return function() end end })
end
function CreateFrame() return Frame() end

local ns = {}
assert(loadfile("Core.lua"))("GamepadXIV", ns)
ns.db = { errorLog = {} }

local failures = 0
local function Check(label, actual, expected)
	if actual ~= expected then
		failures = failures + 1
		print("FAIL " .. label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

ns.Trail("CVar alwaysCompareItems")
clock = 101
ns.Trail("press feedback SetButtonState")
ns.Trail("press feedback SetButtonState")
combat = true
clock = 110.5

-- An ordinary error keeps no breadcrumbs.
handler("Interface/AddOns/Other/x.lua:1: boom")
Check("ordinary error", ns.db.errorLog[1].trail, nil)

-- A taint error naming this addon keeps them, oldest first, with the time before the error.
local TAINT = "BuffFrame.lua:1234: attempt to perform arithmetic (a secret number value, while execution tainted by 'GamepadXIV')"
handler(TAINT)
local trail = ns.db.errorLog[2].trail
Check("trail kept", type(trail), "table")
Check("trail length", #trail, 2)
Check("first crumb", trail[1], "-10.5s CVar alwaysCompareItems")
Check("repeats collapse", trail[2], "-9.5s press feedback SetButtonState x2")

-- The first time also keeps the context; a missing API is left out instead of failing.
local context = table.concat(ns.db.errorLog[2].context, "; ")
Check("context client", context:find("client: 1.60.1 (12345)", 1, true) ~= nil, true)
Check("context class", context:find("class: DRUID level 60", 1, true) ~= nil, true)
Check("context combat", context:find("combat: yes", 1, true) ~= nil, true)
Check("context missing api", context:find("zone", 1, true), nil)

-- An error with this addon's files in the stack keeps the breadcrumbs too.
stackText = "[Interface/AddOns/GamepadXIV/Bar.lua]:12: in function"
handler("attempt to index a nil value")
Check("stack is ours", type(ns.db.errorLog[3].trail), "table")
table.remove(ns.db.errorLog, 3)
stackText = "stack"

-- Later repeats keep the first trail.
ns.Trail("sync")
handler(TAINT)
Check("count", ns.db.errorLog[2].count, 2)
Check("first trail kept", #ns.db.errorLog[2].trail, 2)

-- Only the last 40 are kept.
for i = 1, 50 do
	ns.Trail("crumb " .. i)
end
handler("x (while execution tainted by 'GamepadXIV') other")
local long = ns.db.errorLog[3].trail
Check("capped", #long, 40)
Check("newest last", long[40]:match("crumb 50$") ~= nil, true)
Check("combat marked", long[40]:find("[combat]", 1, true) ~= nil, true)

-- A burst of blocked actions from one tainted call is one entry, not one each.
ns.db.errorLog = {}
for i = 1, 39 do
	handler("ADDON_ACTION_BLOCKED: Bar" .. (i % 8) .. ":SetSize()", "fields (GamepadXIV)")
end
Check("burst grouped", #ns.db.errorLog, 1)
Check("burst count", ns.db.errorLog[1].count, 39)
Check("burst actions", #ns.db.errorLog[1].actions, 8)
handler("ADDON_ACTION_FORBIDDEN: SetPreferredGamepadInteractTarget()", "fields (GamepadXIV)")
Check("other event apart", #ns.db.errorLog, 2)

-- The moment Forever's focus value is first written while this addon runs is kept apart, once.
local manager = {}
GamepadMode = { FrameControlsManager = manager }
local secure = true
function issecurevariable(t, key) if t == manager and key == "fallThroughCatcherActive" then return secure, not secure and "GamepadXIV" or nil end return true end
local hooks = {}
function hooksecurefunc(t, name, fn) hooks[name] = fn end
function manager.SetFallThroughCatcherActive() end
C_AddOns = { GetNumAddOns = function() return 2 end, IsAddOnLoaded = function(i) return true end,
	GetAddOnInfo = function(i) return i == 1 and "GamepadXIV" or "Prat-3.0" end }
ns.Trail("sync")
assert(loadfile("Core.lua"))("GamepadXIV", ns)
ns.db = { errorLog = {} }
ns.CheckTaint("install")
Check("no taint, nothing kept", ns.db.taintOrigin, nil)
secure = false
ns.CheckTaint("FrameControlsManager:SetFallThroughCatcherActive")
local origin = ns.db.taintOrigin
Check("taint origin kept", type(origin), "table")
Check("taint origin field", origin and origin.field, "FrameControlsManager.fallThroughCatcherActive")
Check("taint origin addons", origin and origin.addons, "GamepadXIV, Prat-3.0")
Check("taint origin stack", origin and origin.stack, "stack")
origin.where = "first"
ns.CheckTaint("again")
Check("taint origin once", ns.db.taintOrigin.where, "first")

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("trail: all passed")
