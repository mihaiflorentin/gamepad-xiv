-- Offline checks of the group details panel (LfgDetails.lua) and the member data it shows
-- (LfgFilter.lua's ReadResult). Not loaded by the game.
-- Run from the addon folder with: lua5.1 tests/lfgdetails.lua

tinsert, tremove, wipe = table.insert, table.remove, function(t) for k in pairs(t) do t[k] = nil end return t end
date, time = os.date, os.time

-- Frames: every method does nothing, except the few the panel reads, which give fixed sizes.
local created = {}
local function Stub(kind, sizes)
	local object = { kind = kind, sizes = sizes or {}, shown = false }
	created[#created + 1] = object
	return setmetatable(object, { __index = function(self, key)
		if key == "CreateTexture" then
			return function() return Stub("texture") end
		elseif key == "CreateFontString" then
			return function() return Stub("text") end
		elseif key == "Show" then
			return function() self.shown = true end
		elseif key == "Hide" then
			return function() self.shown = false end
		elseif key == "SetShown" then
			return function(_, on) self.shown = on and true or false end
		elseif key == "SetText" then
			return function(_, text) self.text = text end
		elseif key == "SetPoint" then
			return function(_, ...) self.point = { ... } end
		elseif key == "SetHeight" then
			return function(_, height) self.height = height end
		elseif key == "GetStringHeight" then
			return function() return 12 end
		elseif key == "GetFrameLevel" or key == "GetEffectiveScale" then
			return function() return 1 end
		elseif key:find("^Get") then
			return function() return self.sizes[key] end
		end
		return function() end
	end })
end
function CreateFrame(kind)
	return Stub(kind)
end
UIParent = Stub("Frame", { GetWidth = 1920 })
GameFontHighlightSmall = {}
RAID_CLASS_COLORS = { WARRIOR = { WrapTextInColorCode = function(_, text) return "W:" .. text end } }
function Ambiguate(name) return (name:gsub("%-.*$", "")) end
function CreateColor() return { WrapTextInColorCode = function(_, text) return text end } end

-- The group finder: one secret value stands in for what the game hides.
local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
function issecretvalue(value) return value == SECRET end
local players = {
	[7] = {
		{ name = "Tanky", classFilename = "WARRIOR", level = 40, assignedRole = "TANK", areaName = "Stranglethorn Vale", isLeader = false },
		{ name = "Boss", classFilename = "PRIEST", level = 41, assignedRole = "HEALER", areaName = SECRET, isLeader = true },
		{ name = SECRET, classFilename = "MAGE", level = SECRET, assignedRole = "DAMAGER", isLeader = false },
	},
	[8] = { { name = "Solo", classFilename = "ROGUE", level = 30, assignedRole = "NONE", areaName = "Duskwood",
		lfgRoles = { tank = false, healer = false, dps = true } } },
}
C_LFGList = {
	GetSearchResultInfo = function(id)
		return { numMembers = #players[id], leaderName = id == 7 and "Boss" or "Solo", isDelisted = false, hasSelf = false,
			comment = "Need a healer", name = "", age = 120, activityIDs = { 1, 2 } }
	end,
	GetActivityInfoTable = function(id) return { shortName = "", fullName = "Activity " .. id, maxNumPlayers = 5 } end,
	GetSearchResultPlayerInfo = function(id, index) return players[id][index] end,
	GetSearchResultLeaderInfo = function(id) return players[id][2] end,
	GetSearchResultMemberCounts = function()
		return { TANK = 1, HEALER = 1, DAMAGER = 1, TANK_REMAINING = 0, HEALER_REMAINING = 0, DAMAGER_REMAINING = 2 }
	end,
}
GamepadXIVAccountDB = { lfgRatings = { ["Tanky"] = { r = 3, n = "Great tank" } } }

local ns = {}
assert(loadfile("LfgFilter.lua"))("GamepadXIV", ns)
assert(loadfile("LfgDetails.lua"))("GamepadXIV", ns)

-- A group: the leader first, roles mapped, secret fields left out.
local group = ns.LfgFilterReadResult(7)
local list = group.memberList
assert(#list == 3, "three members")
assert(list[1].name == "Boss" and list[1].leader, "the leader comes first")
assert(list[1].role == "healer" and list[1].zone == nil, "the leader's role, and no zone when it is secret")
assert(list[2].name == "Tanky" and list[2].role == "tank" and list[2].zone == "Stranglethorn Vale", "a member's role and zone")
assert(list[3].name == nil and list[3].level == nil and list[3].role == "dps", "a secret name and level are left out")
assert(group.maxPlayers == 5 and group.counts.dpsLeft == 2, "size and roles needed")
assert(group.listedAt and time() - group.listedAt >= 120, "when it was listed")

-- A player looking for a group.
local solo = ns.LfgFilterReadResult(8)
assert(solo.solo and #solo.memberList == 1 and solo.memberList[1].zone == "Duskwood", "a player's zone")
assert(solo.roles.dps and not solo.roles.tank and solo.memberList[1].role == nil, "a player's roles; NONE is no role")

-- Where the panel goes.
local Side, Top = ns.LfgDetails.Side, ns.LfgDetails.Top
assert(Side(500, 1420, 1920, 330) == "right", "room on the right")
assert(Side(1000, 1920, 1920, 330) == "left", "no room on the right")
assert(Side(nil, nil, nil, 330) == "right", "sizes not known yet")
assert(Side(222, 1142, 1365, 330) == "left", "no room either side: over the filters, not the list")
assert(Top(-112, 200, 590) == -112, "level with the row")
assert(Top(-462, 300, 590) == -290, "kept above the window's bottom")
assert(Top(-112, 700, 590) == 0, "never above the window's top")

-- Drawing: shown beside the window for a group, a player and a hidden listing; hidden with nothing.
local window = Stub("Frame", { GetLeft = 1000, GetRight = 1920, GetHeight = 590 })
ns.LfgDetails.Draw(window, group, -112)
local panel
for _, object in ipairs(created) do
	if rawget(object, "point") and object.point[2] == window then
		panel = object
	end
end
assert(panel and panel.shown, "the panel is shown")
assert(panel.point[1] == "TOPRIGHT" and panel.point[3] == "TOPLEFT", "on the left, with no room on the right")
assert(rawget(panel, "height") and panel.height > 100, "sized to its content")
local texts = {}
for _, object in ipairs(created) do
	if object.kind == "text" and object.shown and rawget(object, "text") then
		texts[#texts + 1] = object.text
	end
end
local all = table.concat(texts, "\n")
assert(all:find("3/5 members", 1, true), "member count")
assert(all:find("Need a healer", 1, true), "the comment")
assert(all:find("Great tank", 1, true), "your note on a member")
assert(all:find("Activity 2", 1, true), "every activity")
ns.LfgDetails.Draw(window, solo, -112)
assert(panel.shown, "shown for a player")
ns.LfgDetails.Draw(window, { id = 9, secret = true, members = 0, comment = "", activityText = "Hidden right now" }, -112)
assert(panel.shown, "shown for a hidden listing")
ns.LfgDetails.Draw(window, nil)
assert(not panel.shown, "hidden with nothing selected")

print("lfgdetails: all checks passed")
