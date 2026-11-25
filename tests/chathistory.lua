-- Offline checks of past groups' chat and chat colours (ChatHistory.lua, with LfgFilter.lua).
-- Not loaded by the game. Run from the addon folder with: lua5.1 tests/chathistory.lua

tinsert, tremove, wipe = table.insert, table.remove, function(t) for k in pairs(t) do t[k] = nil end return t end
date = os.date
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
local frameMethods = setmetatable({}, { __index = function() return function() end end })
function CreateFrame()
	return setmetatable({}, { __index = frameMethods })
end
UIParent = CreateFrame()

local NOW = 100000
function time() return NOW end

-- The group: units and what the game says about them.
local SECRET = "<secret name>"
function issecretvalue(value) return value == SECRET end
local group, raid, units = false, false, {}
function IsInGroup() return group end
function IsInRaid() return raid end
function IsInGuild() return false end
function IsInInstance() return false end
function GetNumSubgroupMembers() return #units - 1 end
function GetNumGroupMembers() return #units end
local function Unit(unit)
	if unit == "player" then
		return units[1]
	end
	return units[(tonumber(unit:match("%d+$")) or 0) + (unit:find("^party") and 1 or 0)]
end
function UnitExists(unit) return Unit(unit) ~= nil end
function GetUnitName(unit) return Unit(unit) and Unit(unit).name end
function UnitClass(unit) return nil, Unit(unit) and Unit(unit).class end
function UnitGroupRolesAssigned(unit) return Unit(unit) and Unit(unit).role or "NONE" end
function UnitIsUnit(unit, other) return Unit(unit) == Unit(other) end
function GetNormalizedRealmName() return "Realm" end
function Ambiguate(name) return (name:gsub("%-.*$", "")) end
UNKNOWNOBJECT = "Unknown"
ChatTypeInfo = {
	PARTY = { r = 0.6, g = 0.6, b = 1 }, PARTY_LEADER = { r = 0.4, g = 0.8, b = 1 }, GUILD = { r = 0.25, g = 1, b = 0.25 },
	WHISPER = { r = 1, g = 0.5, b = 1 }, WHISPER_INFORM = { r = 1, g = 0.4, b = 0.9 }, CHANNEL = { r = 1, g = 0.75, b = 0.75 },
	CHANNEL2 = { r = 0.9, g = 0.9, b = 0.5 }, SYSTEM = { r = 1, g = 1, b = 0 },
}

local ns = {}
assert(loadfile("LfgFilter.lua"))("GamepadXIV", ns)
assert(loadfile("ChatHistory.lua"))("GamepadXIV", ns)
local H = assert(ns.ChatHistory)
ns.db = { lfgChats = {}, lfgChatLines = 100, lfgChatKeep = "never" }
local db = ns.db

local function Say(key, text, t, extra)
	db.lfgChats[key] = db.lfgChats[key] or { lines = {}, unread = 0 }
	local line = { m = text, t = t }
	for field, value in pairs(extra or {}) do
		line[field] = value
	end
	table.insert(db.lfgChats[key].lines, line)
end

local function Same(a, b, what)
	assert(math.abs(a - b) < 1e-6, what .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

-- Joining a party keeps who is in it, everyone who was in it at any point.
group, units = true, { { name = "Me", class = "MAGE" }, { name = "Bob", class = "WARRIOR", role = "TANK" } }
H.UpdateRoster(NOW)
local session = assert(db.lfgGroupSession, "a group is kept while in one")
assert(#session.members == 2 and session.kind == "party", "two members, a party")
assert(session.members[1].name == "Me-Realm" and session.members[1].me, "you, with the realm")
assert(session.members[2].role == "TANK" and session.members[2].class == "WARRIOR", "role and class")
units[2] = { name = "Cat", class = "PRIEST", role = "HEALER" }
units[3] = { name = SECRET, class = "ROGUE" }
H.UpdateRoster(NOW + 60)
assert(#session.members == 3, "Bob stays after leaving; a secret name is skipped")

-- Leaving saves the group's chat as one past group, in the order it was said, and empties the chats.
Say("#PARTY", "hi", NOW + 100, { s = "Bob-Realm", c = "WARRIOR" })
Say("#INSTANCE", "pull", NOW + 150, { s = "Cat-Realm" })
Say("#PARTY", "ok", NOW + 200, { o = true, k = "PARTY_LEADER" })
group, units = false, {}
NOW = NOW + 300
assert(H.CheckLeft("left"), "leaving saves the group")
local groups = H.Groups()
assert(#groups == 1, "one past group")
local past = groups[1]
assert(past.kind == "party" and #past.members == 3, "party with its three members")
assert(#past.lines == 3 and past.lines[1].m == "hi" and past.lines[2].m == "pull" and past.lines[3].m == "ok", "lines in order")
assert(past.lines[1].k == "PARTY" and past.lines[2].k == "INSTANCE_CHAT" and past.lines[3].k == "PARTY_LEADER", "chat types kept")
assert(past.started == 100000 and past.ended == NOW, "started and ended")
assert(#db.lfgChats["#PARTY"].lines == 0 and #db.lfgChats["#INSTANCE"].lines == 0, "the chats start empty")
assert(db.lfgGroupSession == nil, "no group kept")
assert(H.Subtitle(past) == "3 members \194\183 5m", "subtitle: " .. H.Subtitle(past))

-- Leaving twice does nothing more; a group where nobody spoke is not saved.
assert(not H.CheckLeft("left") and #H.Groups() == 1, "second leave")
group, units = true, { { name = "Me", class = "MAGE" }, { name = "Dan", class = "DRUID" } }
H.UpdateRoster(NOW)
group, units = false, {}
H.CheckLeft("left")
assert(#H.Groups() == 1 and db.lfgGroupSession == nil, "a quiet group is not saved")

-- Raid chat from before groups were kept, while not in a group: saved with members not known.
Say("#RAID", "old raid", NOW - 5000)
Say("#RAID", "bye", NOW - 4000)
assert(H.CheckLeft("login"), "old raid chat is saved")
local old = H.Groups()[1] -- sorted by when they ended: this one is older
assert(old.kind == "raid" and #old.members == 0 and old.ended == NOW - 4000, "raid, members not known, ended at its last line")
assert(H.Subtitle(old):find("^Members not known"), "subtitle without members")

-- Conversation keys: read only, listed under History, deleted with the close action.
local key = H.Key(old)
local info = assert(ns.ChatAPI.Info(key), "ChannelInfo knows past groups")
assert(info.readOnly and info.archived and info.name == "Raid", "read only Raid")
assert(not ns.ChatAPI.Send(key, "hello", "test"), "nothing is sent to a past group")
local list = ns.ChatAPI.List()
assert(list[#list].special == "history" and list[#list].count == 2, "History counts past groups")
assert(H.Remove(key) and not H.Find(key) and #H.Groups() == 1, "deleted")
assert(ns.ChatAPI.Info(key) == nil, "a deleted group is no conversation")

-- At most 30 past groups, the oldest go; ids are never reused.
local lastId
for index = 1, 35 do
	Say("#PARTY", "line " .. index, NOW + index)
	NOW = NOW + 10
	lastId = H.Archive("test").id
end
assert(#H.Groups() == 30, "capped at 30")
assert(H.Groups()[30].id == lastId and H.Groups()[30].lines[1].m == "line 35", "the newest kept")
assert(not H.Find(H.Key(past)), "the oldest gone")

-- Lines kept: the "Chat lines kept" setting, and "Chat kept for" when pruning.
db.lfgChatLines = 10
for index = 1, 15 do
	Say("#PARTY", "many " .. index, NOW + index)
end
local many = H.Archive("test")
assert(#many.lines == 10 and many.lines[1].m == "many 6", "only the last 10 lines")
db.lfgChatKeep = "day"
NOW = NOW + 2 * 86400
Say("#PARTY", "new", NOW)
local fresh = H.Archive("test")
ns.PruneLfgChats("test")
assert(#H.Groups() == 1 and H.Groups()[1] == fresh, "groups older than a day are pruned")
db.lfgChatKeep, db.lfgChatLines = "never", 100

-- A group kept from a session long ago, with none of the same people: saved before the new one starts,
-- but only once the others' names are known.
group, units = true, { { name = "Me", class = "MAGE" }, { name = "Eve", class = "HUNTER" } }
H.UpdateRoster(NOW)
Say("#PARTY", "first group", NOW + 5)
NOW = NOW + 7200
local before = #H.Groups()
units[2] = { name = "Unknown", class = "PALADIN" }
H.UpdateRoster(NOW)
assert(#H.Groups() == before and #db.lfgGroupSession.members == 2, "names not loaded yet: same group, Unknown not kept")
NOW = NOW + 7200
units[2] = { name = "Fay", class = "PALADIN" }
H.UpdateRoster(NOW)
local groups2 = H.Groups()
assert(groups2[#groups2].lines[1].m == "first group" and #groups2[#groups2].members == 2, "the old group is saved")
assert(#db.lfgGroupSession.members == 2 and db.lfgGroupSession.members[2].name == "Fay-Realm", "a new group starts")
group, units = false, {}
H.CheckLeft("left")

-- Colours: the game's colour for the chat type, a line's own type, whispers in and out, numbered channels.
Same(select(2, H.Color("#GUILD", {}, { m = "x" })), 1, "guild")
Same(select(1, H.Color("#PARTY", {}, { m = "x", k = "PARTY_LEADER" })), 0.4, "party leader")
Same(select(2, H.Color("Bob-Realm", {}, { m = "x" })), 0.5, "whisper in")
Same(select(2, H.Color("Bob-Realm", {}, { m = "x", o = true })), 0.4, "whisper out")
Same(select(3, H.Color("#CH:Trade", { number = 2 }, { m = "x" })), 0.5, "channel 2")
Same(select(3, H.Color("#CH:General", { number = 7 }, { m = "x" })), 0.75, "channel without its own colour")
Same(select(3, H.Color("#SYSTEM", {}, { m = "x" })), 0, "system")
assert(H.ColorCode("#GUILD", {}, { m = "x" }) == "|cff40ff40", "colour code " .. H.ColorCode("#GUILD", {}, { m = "x" }))
db.chatHighlightOwn = false
assert(H.OwnMark() == "" and H.You():find("999999"), "highlight off")
db.chatHighlightOwn = nil
assert(H.OwnMark() ~= "" and H.You():find("ffd100"), "highlight on by default")

print("chathistory: all checks passed")
