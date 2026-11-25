-- Offline checks of LFG Filter's role matching (LfgFilter.lua). Not loaded by the game.
-- Run from the addon folder with: lua5.1 tests/lfgfilter.lua

tinsert, tremove, wipe = table.insert, table.remove, function(t) for k in pairs(t) do t[k] = nil end return t end
date = os.date
-- Frames do nothing here: any method is a no-op.
local frameMethods = setmetatable({}, { __index = function() return function() end end })
function CreateFrame()
	return setmetatable({}, { __index = frameMethods })
end
UIParent = CreateFrame()

local ns = {}
assert(loadfile("LfgFilter.lua"))("GamepadXIV", ns)
local Match = assert(ns.LfgFilterMatchesRoles)

-- Groups: kept when a wanted role still has a free spot.
local group = { counts = { tank = 1, tankLeft = 0, healer = 0, healerLeft = 1, dps = 2, dpsLeft = 1 } }
assert(Match(group, { healer = true }, false), "group needing a healer")
assert(not Match(group, { tank = true }, false), "group with its tank")
assert(Match(group, { tank = true, dps = true }, false), "any wanted role is enough")
assert(Match({}, { tank = true }, false), "a group without counts is not filtered out")

-- Players: kept when they fill a wanted role.
local healer = { roles = { tank = false, healer = true, dps = true } }
assert(Match(healer, { healer = true }, true), "player healing")
assert(not Match(healer, { tank = true }, true), "player not tanking")
assert(Match({}, { tank = true }, true), "a player without roles is not filtered out")

print("lfgfilter: all checks passed")
