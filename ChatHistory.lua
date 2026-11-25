local _, ns = ...

-- Past groups' chat, and the game's chat colours for the Chat window (LfgFilter.lua).
--
-- While you are in a group, everyone who was in it at any point is kept in ns.db.lfgGroupSession
-- (names, classes, roles). When you leave, the group's party, raid and instance chat goes into
-- ns.db.lfgGroupHistory as one entry, and those conversations start empty for the next group:
--   { id, kind = "party" | "raid", started, ended, where, members = { { name, class, role, me } },
--     lines = { { o, m, t, s, c, k } }, unread = 0, seq, last }
-- The Chat window lists them under History as "#GRP:<id>", read only. Only reads the game's group
-- API; nothing of the game's is called that changes anything.

local MAX_GROUPS = 30
local GROUP_CHATS = { "#PARTY", "#RAID", "#INSTANCE" }
local CHAT_TYPES = { ["#PARTY"] = "PARTY", ["#RAID"] = "RAID", ["#INSTANCE"] = "INSTANCE_CHAT", ["#SYSTEM"] = "SYSTEM" }
local STALE = 1800 -- a saved group you were last seen in this long ago, with none of its members now, is over
local OWN_MARK = "|TInterface\\Buttons\\WHITE8X8:13:3:0:0:8:8:0:8:0:8:255:209:0|t "

local H = {}
ns.ChatHistory = H

local function Secret(value)
	return issecretvalue and issecretvalue(value) or false
end

local function Plain(value)
	if value == nil or Secret(value) then
		return nil
	end
	return value
end

local function API()
	return ns.ChatAPI or {}
end

local function Log(...)
	if ns.LfgFilterLog then
		ns.LfgFilterLog(...)
	end
end

---------------------------------------------------------------------------------------------------
-- Colours

-- The game's colour (ChatTypeInfo) for a line of a conversation: its chat type, a numbered channel's
-- own colour, whispers in and out, system and loot.
function H.Color(key, chat, line)
	local info = API().Info and API().Info(key)
	local chatType = line and line.k
	if not chatType then
		if not info then
			chatType = line and line.o and "WHISPER_INFORM" or "WHISPER"
		elseif info.channel then
			chatType = chat and chat.number and ("CHANNEL" .. chat.number) or "CHANNEL"
		else
			chatType = info.chatType or CHAT_TYPES[key] or "SYSTEM"
		end
	end
	local types = ChatTypeInfo
	local color = types and (types[chatType] or (chatType:find("^CHANNEL") and types.CHANNEL))
	if color and color.r then
		return color.r, color.g, color.b
	end
	if info and info.color then
		local hex = info.color
		return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
	end
	return 1, 1, 1
end

-- The same as a colour code to start text with.
function H.ColorCode(key, chat, line)
	local r, g, b = H.Color(key, chat, line)
	return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- Your own lines stand out ("Highlight my messages", on by default): a gold bar and a gold "You".
function H.HighlightOwn()
	return not (ns.db and ns.db.chatHighlightOwn == false)
end

function H.OwnMark()
	return H.HighlightOwn() and OWN_MARK or ""
end

function H.You()
	return H.HighlightOwn() and "|cffffd100You|r" or "|cff999999You|r"
end

---------------------------------------------------------------------------------------------------
-- Saved groups

function H.Groups()
	if type(ns.db.lfgGroupHistory) ~= "table" then
		ns.db.lfgGroupHistory = {}
	end
	return ns.db.lfgGroupHistory
end

function H.Key(group)
	return "#GRP:" .. group.id
end

-- The saved group for a "#GRP:<id>" conversation key, and its place in the list.
function H.Find(key)
	local id = type(key) == "string" and tonumber(key:match("^#GRP:(%d+)$"))
	if not id or not ns.db then
		return nil
	end
	for index, group in ipairs(H.Groups()) do
		if group.id == id then
			return group, index
		end
	end
end

-- What LfgFilter's ChannelInfo gives for a saved group: Party or Raid in their colours, read only.
local infos = {
	party = { name = "Party", color = "aaaaff", chatType = "PARTY", readOnly = true, quiet = true, archived = true },
	raid = { name = "Raid", color = "ff7f00", chatType = "RAID", readOnly = true, quiet = true, archived = true },
}
for _, info in pairs(infos) do
	info.shown = function() return false end
end
function H.Info(key)
	local group = H.Find(key)
	return group and infos[group.kind == "raid" and "raid" or "party"] or nil
end

function H.Remove(key)
	local _, index = H.Find(key)
	if index then
		table.remove(H.Groups(), index)
		Log("past group deleted", key)
		return true
	end
end

local function Duration(seconds)
	seconds = math.max(0, seconds or 0)
	if seconds < 3600 then
		return math.max(1, math.floor(seconds / 60)) .. "m"
	end
	local hours, minutes = math.floor(seconds / 3600), math.floor(seconds % 3600 / 60)
	return hours .. "h" .. (minutes > 0 and (" " .. minutes .. "m") or "")
end

-- Under the group's name in the list: "5 members · 2h · The Deadmines" (how long the group lasted).
function H.Subtitle(group)
	local count = #(group.members or {})
	local parts = { count > 0 and (count .. " member" .. (count == 1 and "" or "s")) or "Members not known" }
	if group.started and group.ended and group.ended > group.started then
		parts[#parts + 1] = Duration(group.ended - group.started)
	end
	if group.where and group.where ~= "" then
		parts[#parts + 1] = group.where
	end
	return table.concat(parts, " \194\183 ")
end

-- Removes saved groups' lines past the "Chat lines kept" and "Chat kept for" settings, the groups
-- left without lines, and the oldest groups past MAX_GROUPS.
function H.Prune(now)
	if not ns.db then
		return 0
	end
	now = now or time()
	local groups, dropped = H.Groups(), 0
	for index = #groups, 1, -1 do
		local group = groups[index]
		if type(group) ~= "table" or type(group.lines) ~= "table" then
			table.remove(groups, index)
			dropped = dropped + 1
		else
			if API().Prune then
				API().Prune(group, now)
			end
			if #group.lines == 0 then
				table.remove(groups, index)
				dropped = dropped + 1
			end
		end
	end
	table.sort(groups, function(a, b) return (a.ended or 0) < (b.ended or 0) end)
	while #groups > MAX_GROUPS do
		table.remove(groups, 1)
		dropped = dropped + 1
	end
	return dropped
end

---------------------------------------------------------------------------------------------------
-- The group you are in

local function AddMember(session, name, class, role, me)
	for _, member in ipairs(session.members) do
		if member.name == name then
			member.class = class or member.class
			member.role = role or member.role
			return
		end
	end
	session.members[#session.members + 1] = { name = name, class = class, role = role, me = me or nil }
end

local function HasGroupLines()
	local chats = type(ns.db.lfgChats) == "table" and ns.db.lfgChats or {}
	for _, key in ipairs(GROUP_CHATS) do
		local chat = chats[key]
		if type(chat) == "table" and type(chat.lines) == "table" and #chat.lines > 0 then
			return true
		end
	end
	return false
end

-- Saves the group's chat (party, raid and instance, in the order said) as a past group and empties
-- those conversations. Without a group being kept (chat from before this was added), the members
-- are not known. Nothing is saved when nobody said anything. Returns the saved group.
function H.Archive(reason, now)
	if not ns.db then
		return nil
	end
	now = now or time()
	local session = type(ns.db.lfgGroupSession) == "table" and ns.db.lfgGroupSession or nil
	ns.db.lfgGroupSession = nil
	local chats = type(ns.db.lfgChats) == "table" and ns.db.lfgChats or {}
	local lines, raid = {}, session and session.kind == "raid"
	for _, key in ipairs(GROUP_CHATS) do
		local chat = chats[key]
		if type(chat) == "table" and type(chat.lines) == "table" and #chat.lines > 0 then
			raid = raid or key == "#RAID"
			for _, line in ipairs(chat.lines) do
				local copy = {}
				for field, value in pairs(line) do
					copy[field] = value
				end
				copy.k = copy.k or CHAT_TYPES[key]
				copy.order = #lines + 1
				lines[#lines + 1] = copy
			end
			chat.lines = {}
			chat.unread = 0
			chat.seq = (chat.seq or 0) + 1
		end
	end
	if #lines == 0 then
		Log("group over, nothing said:", reason)
		return nil
	end
	table.sort(lines, function(a, b)
		if (a.t or 0) ~= (b.t or 0) then
			return (a.t or 0) < (b.t or 0)
		end
		return a.order < b.order
	end)
	for _, line in ipairs(lines) do
		line.order = nil
	end
	local last = lines[#lines].t or now
	ns.db.lfgGroupNextId = math.max(tonumber(ns.db.lfgGroupNextId) or 0, 0) + 1
	local id = ns.db.lfgGroupNextId
	for _, other in ipairs(H.Groups()) do
		if type(other) == "table" and (other.id or 0) >= id then
			id = other.id + 1
		end
	end
	ns.db.lfgGroupNextId = id
	local ended = math.max(last, session and session.seen or 0)
	local group = {
		id = id, kind = raid and "raid" or "party",
		started = math.min(session and session.started or lines[1].t or now, lines[1].t or now),
		ended = ended, last = ended, where = session and session.where or nil,
		members = session and session.members or {},
		lines = lines, unread = 0, seq = 1,
	}
	local groups = H.Groups()
	groups[#groups + 1] = group
	H.Prune(now)
	Log("group saved:", reason, group.kind, #group.members, "members", #lines, "lines")
	return H.Find(H.Key(group)) and group or nil
end

-- Reads who is in the group now (and their class and role) into the kept group, starting one when
-- there is none. Secret values are skipped.
function H.UpdateRoster(now)
	if not ns.db or not IsInGroup() then
		return
	end
	now = now or time()
	local FullName = API().FullName or function(name) return name end
	local raid = IsInRaid()
	local units = { "player" }
	if raid then
		for index = 1, GetNumGroupMembers() do
			units[#units + 1] = "raid" .. index
		end
	else
		for index = 1, GetNumSubgroupMembers() do
			units[#units + 1] = "party" .. index
		end
	end
	local found = {}
	for _, unit in ipairs(units) do
		if Plain(UnitExists(unit)) then
			local name = Plain(GetUnitName(unit, true))
			if name == UNKNOWNOBJECT or name == "" then
				name = nil -- not loaded yet
			end
			name = name and FullName(name)
			if name then
				local _, class = UnitClass(unit)
				local role = UnitGroupRolesAssigned and Plain(UnitGroupRolesAssigned(unit)) or nil
				if role ~= "TANK" and role ~= "HEALER" and role ~= "DAMAGER" then
					role = nil
				end
				found[#found + 1] = { name = name, class = Plain(class), role = role, me = Plain(UnitIsUnit(unit, "player")) and true or nil }
			end
		end
	end
	local session = type(ns.db.lfgGroupSession) == "table" and ns.db.lfgGroupSession or nil
	-- Kept from a group you were in when you logged out, but this is another one: that one is over.
	-- Only told once the others' names are known.
	if session and now - (session.seen or 0) > STALE then
		local others, same = 0, false
		for _, member in ipairs(found) do
			if not member.me then
				others = others + 1
				for _, old in ipairs(session.members or {}) do
					same = same or old.name == member.name
				end
			end
		end
		if others > 0 and not same then
			H.Archive("another group", now)
			session = nil
		end
	end
	if not session then
		session = { started = now, members = {} }
		ns.db.lfgGroupSession = session
		Log("group started")
	end
	session.members = type(session.members) == "table" and session.members or {}
	session.kind = (raid or session.kind == "raid") and "raid" or "party"
	session.seen = now
	for _, member in ipairs(found) do
		AddMember(session, member.name, member.class, member.role, member.me)
	end
	local inInstance = Plain(IsInInstance())
	if inInstance and GetInstanceInfo then
		local where = Plain((GetInstanceInfo()))
		if type(where) == "string" and where ~= "" then
			session.where = where
		end
	end
end

-- Out of a group now: the kept group (or chat from before) is saved.
function H.CheckLeft(reason)
	if not ns.db or IsInGroup() then
		return false
	end
	if type(ns.db.lfgGroupSession) ~= "table" and not HasGroupLines() then
		return false
	end
	local session = ns.db.lfgGroupSession
	if type(session) == "table" and reason == "left" then
		session.seen = time()
	end
	H.Archive(reason)
	if ns.RefreshLfgFilter then
		ns.RefreshLfgFilter()
	end
	if ns.UpdateLfgHint then
		ns.UpdateLfgHint()
	end
	return true
end

-- Past groups are pruned with the rest of the chat (login and the chat settings).
local prune = ns.PruneLfgChats
function ns.PruneLfgChats(reason)
	if ns.db then
		local dropped = H.Prune(time())
		if dropped > 0 then
			Log("past groups pruned:", reason, dropped)
		end
	end
	if prune then
		return prune(reason)
	end
end

---------------------------------------------------------------------------------------------------
-- Events

-- Leaving is acted on a moment later, and only once the game has had time to say whether you are in a
-- group after a loading screen, so a group is never cut in two.
local ready, pending = false, false
local function LaterCheck(delay, reason)
	if pending or not (C_Timer and C_Timer.After) then
		return
	end
	pending = true
	C_Timer.After(delay, function()
		pending = false
		ready = true
		if not ns.db then
			return
		end
		if IsInGroup() then
			H.UpdateRoster()
		else
			H.CheckLeft(reason)
		end
	end)
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "GROUP_LEFT", "PLAYER_ENTERING_WORLD", "PLAYER_ROLES_ASSIGNED" }) do
	pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event)
	if not ns.db then
		return
	end
	if event == "PLAYER_ENTERING_WORLD" then
		LaterCheck(5, "login")
	elseif IsInGroup() then
		H.UpdateRoster()
	elseif ready then
		LaterCheck(1, "left")
	end
end)
