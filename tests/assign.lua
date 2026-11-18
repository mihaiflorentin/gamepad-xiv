-- Offline checks of the list that puts an ability, item or macro in a slot (Assign.lua).
-- Run from the addon folder with: lua5.1 tests/assign.lua
tinsert = table.insert
local function Frame()
	local f = { shown = false }
	return setmetatable(f, { __index = function(t, k)
		if k == "Show" then return function(self) self.shown = true end end
		if k == "Hide" then return function(self) self.shown = false end end
		if k == "IsShown" then return function(self) return self.shown end end
		if k == "SetShown" then return function(self, v) self.shown = v and true or false end end
		if k == "CreateTexture" or k == "CreateFontString" then return function() return Frame() end end
		if k == "SetText" then return function(self, v) self.text = v end end
		return function() end
	end })
end
function CreateFrame() return Frame() end
UIParent = Frame()
local combat, cursor, placed = false, nil, {}
function InCombatLockdown() return combat end
function ClearCursor() cursor = nil end
function GetCursorInfo() return cursor end
C_Spell = { PickupSpell = function(id) cursor = "spell" .. id end }
C_Item = { PickupItem = function(id) cursor = "item" .. id end }
function PickupMacro(name) cursor = "macro" .. name end
function PlaceAction(slot) placed[#placed + 1] = slot .. ":" .. tostring(cursor) cursor = "old" end
C_ActionBar = { HasAction = function() return false end, GetActionTexture = function() end }

local ns = { ButtonText = function(t) return t end, Trail = function() end, Print = function() end }
ns.RingSpellChoices = function() return { { label = "Fireball", data = { spell = 133 } }, { label = "Frostbolt", data = { spell = 116 } } } end
ns.RingItemChoices = function() return { { label = "Hearthstone", data = { item = 6948 } } } end
ns.RingMacroChoices = function() return {} end
assert(loadfile("Assign.lua"))("GamepadXIV", ns)

local failures = 0
local function Check(label, actual, expected)
	if actual ~= expected then
		failures = failures + 1
		print("FAIL " .. label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

local done = 0
ns.OpenAssign(5, function() done = done + 1 end)
ns.AssignNav("Accept")          -- Abilities
ns.AssignNav("Down")            -- Frostbolt
ns.AssignNav("Accept")
Check("ability placed", placed[1], "5:spell116")
Check("cursor let go", cursor, nil)
Check("done once", done, 1)

ns.OpenAssign(7, function() done = done + 1 end)
ns.AssignNav("Down")            -- Items
ns.AssignNav("Accept")
ns.AssignNav("Back")            -- back to the sections, on Items
ns.AssignNav("Accept")
ns.AssignNav("Accept")
Check("item placed", placed[2], "7:item6948")

ns.OpenAssign(8, function() done = done + 1 end)
ns.AssignNav("Back")
Check("cancel ends it", done, 3)
Check("nothing placed on cancel", placed[3], nil)

ns.OpenAssign(9, function() done = done + 1 end)
combat = true
ns.AssignNav("Accept"); ns.AssignNav("Accept")
Check("not in combat", placed[3], nil)

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("assign: all passed")
