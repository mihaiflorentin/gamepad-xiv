-- Offline checks of mounts and macros as button actions (Actions.lua).
-- Run from the addon folder with: lua5.1 tests/actions.lua
tinsert, tremove = table.insert, table.remove
local frames = {}
function CreateFrame(_, name)
	local f = { attrs = {}, events = {} }
	function f:RegisterForClicks() end
	function f:SetAttribute(k, v) self.attrs[k] = v end
	function f:Hide() end
	function f:RegisterEvent(e) self.events[e] = true end
	function f:SetScript(_, fn) self.onEvent = fn end
	if name then _G[name] = f frames[name] = f end
	return f
end
UIParent = {}
local combat = false
function InCombatLockdown() return combat end
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local mounts = {
	[1] = { "Summon Warhorse", 13819, 132261, false, true, 0, false, false, nil, false, true },
	[2] = { "Swift Gryphon", 32242, 132265, false, true, 0, false, false, nil, false, false },
	[3] = { "Brown Horse", 458, 132264, false, true, 0, false, false, nil, false, true },
}
C_MountJournal = {
	GetMountIDs = function() return { 1, 2, 3 } end,
	GetMountInfoByID = function(id) return unpack(mounts[id]) end,
}
local synced = 0
local ns = { STICK_ACTION_GROUPS = {}, Sync = function() synced = synced + 1 end }
ns.STICK_ACTIONS = { { "sheathe", "Draw / sheathe weapon", "TOGGLESHEATH" }, { "none", "Nothing", "NONE" } }
local macros = { { label = "Pull", icon = 1, data = { macro = "Pull" } } }
ns.RingMacroChoices = function() return macros end
assert(loadfile("Actions.lua"))("GamepadXIV", ns)

local failures = 0
local function Check(label, actual, expected)
	if actual ~= expected then
		failures = failures + 1
		print("FAIL " .. label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end
local function Find(key)
	for index, action in ipairs(ns.STICK_ACTIONS) do
		if action[1] == key then return action, index end
	end
end

Check("refresh out of combat", ns.RefreshCustomActions(), true)
Check("collected mounts only", Find("mount-32242"), nil)
local horse, horseAt = Find("mount-458")
local warhorse, warhorseAt = Find("mount-13819")
Check("mounts sorted by name", horseAt < warhorseAt, true)
Check("mount label", warhorse and warhorse[2], "Summon Warhorse")
Check("mount group", ns.STICK_ACTION_GROUPS["mount-13819"], "mount")
local button = warhorse and frames[warhorse[3]:match("CLICK (.-):")]
Check("mount button casts or gets off", button and button.attrs.macrotext, "/cast [nomounted] Summon Warhorse\n/dismount [mounted,noflying]")
local macro = Find("macro-Pull")
Check("macro label", macro and macro[2], "Macro: Pull")
local macroButton = macro and frames[macro[3]:match("CLICK (.-):")]
Check("macro button", macroButton and macroButton.attrs.macro, "Pull")
Check("Nothing stays last", ns.STICK_ACTIONS[#ns.STICK_ACTIONS][1], "none")

-- A second refresh keeps one entry each and reuses the buttons.
local count = #ns.STICK_ACTIONS
macros = {}
ns.RefreshCustomActions()
Check("deleted macro leaves the list", Find("macro-Pull"), nil)
Check("no duplicates", #ns.STICK_ACTIONS, count - 1)
Check("mount button reused", Find("mount-13819")[3], warhorse[3])

-- In combat it waits for the fight to end.
combat = true
Check("no refresh in combat", ns.RefreshCustomActions(), false)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("actions: all passed")
