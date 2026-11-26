local _, ns = ...

-- LFG Filter: a group finder window of the addon's own, made for the controller.
--   Groups:  the game's group finder listings with filters the game's window lacks: languages, the
--            roles a group still needs (while you are on your own) or the roles a player is looking
--            to fill (while you are in a group). The list shows groups or players to match.
--   Chat:    every whisper, one conversation per player, with unread counts and quick replies.
--   Ratings: the players you grouped with, each rated Avoid, Okay or Great. Ratings are kept for
--            the whole account and show on the Groups list.
--
-- Taint: nothing of Forever's group finder is called or written. The window reads the C_LFGList API
-- and calls C_LFGList.Search, C_ChatInfo.SendChatMessage and C_PartyInfo.InviteUnit, the same calls
-- Forever's buttons make, from button presses only. Forever's window is closed with a secure click
-- on its own close button (Lfg.lua), never from addon code.
--
-- While the session log is on (/gxiv log), everything the window does is written to ns.db.lfgFilterLog,
-- with every ADDON_ACTION_BLOCKED and ADDON_ACTION_FORBIDDEN the game reports, from any addon.

local WHITE = "Interface\\Buttons\\WHITE8X8"
local MEDIA = "Interface\\AddOns\\GamepadXIV\\Media\\"
local GOLD = { 1, 0.82, 0 }
local PANEL = { 0.075, 0.075, 0.09, 0.97 }
local CONTROL = { 0.13, 0.13, 0.16, 1 }
local EDGE = { 1, 1, 1, 0.1 }
local SELECTED = { 0.24, 0.2, 0.07, 1 }
local SELECTED_EDGE = { GOLD[1], GOLD[2], GOLD[3], 0.9 }

local WIDTH, HEIGHT = 920, 590
local TITLE_HEIGHT, TAB_HEIGHT, FOOTER_HEIGHT = 38, 38, 40
local SIDE_WIDTH = 270
local FILTER_ROW_HEIGHT = 34
local LIST_ROW_HEIGHT = 31
local LIST_ROWS = 14
local LIST_SIDE_WIDTH = 330
local RESULT_ROW_HEIGHT = 50
local RESULT_ROWS = 8
local CHAT_ROW_HEIGHT = 50
local CHAT_ROWS = 8
local RATE_ROW_HEIGHT = 44
local RATE_ROWS = 10
local PICKER_ROWS = 10
local DROPDOWN_ARROW = "|TInterface\\ChatFrame\\ChatFrameExpandArrow:12:12:0:0:16:16:0:16:16:0|t" -- pointing down

local LOG_MAX = 500
local MAX_CHATS, MAX_RECENT = 40, 60
local MAX_LINES = 500 -- the most the "Lines kept" setting allows
-- Chat channels are conversations too, kept under these names and listed before whispers. LFG
-- Filter's Chat tab shows party and raid ("lfg"); the Chat window (ns.OpenGamepadChat) shows them all.
local function HasLines(chat)
	return chat and #chat.lines > 0
end
local CHANNELS = {
	["#SAY"] = { name = "Say", color = "ffffff", chatType = "SAY", shown = function() return true end },
	["#PARTY"] = { name = "Party", color = "aaaaff", chatType = "PARTY", lfg = true, important = true, shown = function() return IsInGroup() end },
	["#RAID"] = { name = "Raid", color = "ff7f00", chatType = "RAID", lfg = true, important = true, shown = function() return IsInRaid() end },
	["#INSTANCE"] = { name = "Instance", color = "ff7d01", chatType = "INSTANCE_CHAT", important = true,
		shown = function(chat) return HasLines(chat) or (LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE)) end },
	["#GUILD"] = { name = "Guild", color = "40ff40", chatType = "GUILD", important = true, shown = function(chat) return IsInGuild() or HasLines(chat) end },
	["#OFFICER"] = { name = "Officer", color = "40c040", chatType = "OFFICER", important = true, shown = HasLines },
	["#YELL"] = { name = "Yell", color = "ff4040", chatType = "YELL", shown = HasLines },
	["#SYSTEM"] = { name = "System and loot", color = "ffff00", readOnly = true, quiet = true, shown = HasLines },
}
local CHANNEL_ORDER = { "#SAY", "#RAID", "#PARTY", "#INSTANCE", "#GUILD", "#OFFICER", "#YELL" } -- then numbered channels, System
local CHANNEL_EVENTS = {
	CHAT_MSG_PARTY = "#PARTY", CHAT_MSG_PARTY_LEADER = "#PARTY",
	CHAT_MSG_RAID = "#RAID", CHAT_MSG_RAID_LEADER = "#RAID", CHAT_MSG_RAID_WARNING = "#RAID",
	CHAT_MSG_SAY = "#SAY", CHAT_MSG_YELL = "#YELL", CHAT_MSG_GUILD = "#GUILD", CHAT_MSG_OFFICER = "#OFFICER",
	CHAT_MSG_INSTANCE_CHAT = "#INSTANCE", CHAT_MSG_INSTANCE_CHAT_LEADER = "#INSTANCE",
	CHAT_MSG_CHANNEL = "channel", CHAT_MSG_SYSTEM = "#SYSTEM", CHAT_MSG_LOOT = "#SYSTEM",
}

-- A conversation's channel: one of CHANNELS, a numbered channel such as General or Trade
-- ("#CH:Trade"), or nil for a whisper.
local numberedChannels = {}
local function ChannelInfo(key)
	if type(key) ~= "string" or key:sub(1, 1) ~= "#" then
		return nil
	end
	if CHANNELS[key] then
		return CHANNELS[key]
	end
	if key:find("^#GRP:") then -- a past group's chat (ChatHistory.lua), read only
		return ns.ChatHistory and ns.ChatHistory.Info(key) or nil
	end
	local base = key:match("^#CH:(.+)$")
	if base then
		numberedChannels[key] = numberedChannels[key] or { name = base, color = "ffc0c0", chatType = "CHANNEL", channel = base,
			shown = function() return true end }
		return numberedChannels[key]
	end
end

-- Ready-made messages go out between raid marker codes standing in for the controller: the diamond for
-- the D-pad, on both sides. Every client turns {rtN}
-- into the marker icon, so players without the addon see them; chat can't carry other pictures.
local Markers = { before = "{rt3}", after = "{rt3}" } -- one local: the file is near Lua's 200
function Markers.Decorate(text, name)
	-- Not in public channels (General, Trade), where the game may not show markers.
	if not (ns.db and ns.db.chatIcons) or not text or text == "" or (name and name:find("^#CH:")) then
		return text
	end
	local decorated = Markers.before .. " " .. text .. " " .. Markers.after
	return #decorated <= 255 and decorated or text
end

-- Raid marker codes ({rt1}, {star} and the game's own words for them) as icons, for showing chat here.
function Markers.Icons(text)
	if type(text) ~= "string" or not text:find("{", 1, true) then
		return text
	end
	return (text:gsub("{([^}]+)}", function(tag)
		local index = tonumber(tag:lower():match("^rt(%d)$"))
		if not index and ICON_TAG_LIST then
			index = ICON_TAG_LIST[tag:lower()]
		end
		if index and index >= 1 and index <= 8 then
			return "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. index .. ":0|t"
		end
	end))
end

local function HexColor(hex)
	return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end
local KEEP_SECONDS = { day = 86400, week = 7 * 86400, month = 30 * 86400 } -- "never": kept until the line limit

-- The LFG settings, shown both in the addon's settings (LFG tab) and on LFG Filter's Settings tab.
ns.LFG_SETTINGS = {
	{ type = "choice", key = "lfgFinder", label = "Group finder",
		choices = function() return { { "filter", "LFG Filter" }, { "game", "The game's" } } end,
		onChange = function() if ns.ApplyLfgFinderChoice then ns.ApplyLfgFinderChoice() end end,
		tip = "Which group finder the ring and the game's Toggle Group Finder key open. LFG Filter is made for the controller; {PADLSTICK} switches between the two from either window." },
	{ type = "choice", key = "lfgAsk", label = "{PAD1} on a group",
		choices = function() return { { "ask", "Ask first" }, { "send", "Send the message" }, { "chat", "Open Chat" }, { "off", "Do nothing" } } end,
		tip = "Ask first: {PAD1} asks whether to whisper the group finder message to the leader. Send the message: it is sent straight away. Open Chat: nothing is sent; LFG Filter's Chat opens on the leader, to write your own message or none. Do nothing: {PAD1} on a group does nothing at all." },
	{ type = "check", key = "chatIcons", chat = true, label = "Controller icons on ready-made messages",
		tip = "A message with a quick reply or a {PADRSTICK} message in it goes out between two purple diamond raid markers, once. Messages you only typed don't. Everyone sees them, with or without the addon. Chat can't carry other pictures or emoji." },
	{ type = "choice", key = "lfgChatLines", chat = true, label = "Chat lines kept",
		choices = function() return { { 50, "50 per conversation" }, { 100, "100 per conversation" }, { 200, "200 per conversation" }, { 500, "500 per conversation" } } end,
		onChange = function() if ns.PruneLfgChats then ns.PruneLfgChats("setting") end end,
		tip = "How many lines LFG Filter keeps of each conversation, whispers, party and raid. Older lines are removed." },
	{ type = "choice", key = "lfgChatKeep", chat = true, label = "Chat kept for",
		choices = function() return { { "day", "A day" }, { "week", "A week" }, { "month", "A month" }, { "never", "Always (never removed)" } } end,
		onChange = function() if ns.PruneLfgChats then ns.PruneLfgChats("setting") end end,
		tip = "How long LFG Filter keeps chat. Lines older than this are removed, and a conversation with none left goes." },
}
local SEARCH_TIMEOUT = 10
local REBIND_EVERY = 0.25

local TAB_FINDER, TAB_LIST, TAB_CHAT, TAB_RATINGS, TAB_SETTINGS = 1, 2, 3, 4, 5
local TAB_NAMES = { "Group finder", "Listing", "Chat", "Ratings", "Settings" }
local TAB_KEYS = { "finder", "list", "chat", "ratings", "settings" } -- saved by name, so new tabs don't shift it

local ROLES = { "tank", "healer", "dps" }
local ROLE_NAMES = { tank = "Tank", healer = "Healer", dps = "DPS" }
local ROLE_COUNT_KEY = { tank = "TANK", healer = "HEALER", dps = "DAMAGER" }
local ROLE_ATLAS = {
	tank = "groupfinder-icon-role-large-tank",
	healer = "groupfinder-icon-role-large-heal",
	dps = "groupfinder-icon-role-large-dps",
}
local RATINGS = {
	{ name = "Avoid", color = { 0.95, 0.32, 0.3 }, icon = "Interface\\RaidFrame\\ReadyCheck-NotReady" },
	{ name = "Okay", color = { 0.85, 0.85, 0.85 }, icon = "Interface\\COMMON\\Indicator-Gray" },
	{ name = "Great", color = { 0.35, 0.9, 0.45 }, icon = "Interface\\RaidFrame\\ReadyCheck-Ready" },
}
-- Each rating as shown by a name: its icon and its name in its colour.
for _, rating in ipairs(RATINGS) do
	rating.markup = "|T" .. rating.icon .. ":14:14|t"
	rating.tag = rating.markup .. " " .. string.format("|cff%02x%02x%02x%s|r",
		math.floor(rating.color[1] * 255), math.floor(rating.color[2] * 255), math.floor(rating.color[3] * 255), rating.name)
end
-- {PADRSTICK} in Chat: messages by category. "<ask>" is your group finder message.
local PHRASES = {
	{ name = "Greetings", "Hello!", "Hi there!", "Hey, how's it going?", "Good morning!", "Good evening!", "Welcome back!" },
	{ name = "Looking for a group", "<ask>", "Can I join?", "Any spots left?", "I can tank.", "I can heal.", "I can DPS.",
		"What level is the group?", "Which dungeon are you doing?" },
	{ name = "Inviting", "Sure, sending an invite.", "Inviting you now.", "Can you come to the instance?",
		"We meet at the entrance.", "Do you need a summon?" },
	{ name = "In the group", "What role do you need?", "We need a tank.", "We need a healer.", "We need DPS.",
		"Ready?", "Ready!", "Give me a minute.", "Be right back.", "On my way!", "Can I get a summon, please?",
		"Sorry, I'm on a controller with no keyboard, so I can only send short messages." },
	{ name = "Combat", "Pull!", "Wait, don't pull yet.", "Focus my target.", "Kill the skull first.", "Stop attacking!",
		"Run back!", "Add incoming!", "Patrol coming.", "I'll tank this one.", "CC the marked target.", "Wipe, release and run back." },
	{ name = "Resources", "OOM", "Need mana.", "Mana break, please.", "Need a heal!", "Low health!", "Need a drink.", "Can I have some water?",
		"Need a rest.", "Out of ammo.", "Wait for mana before the next pull." },
	{ name = "Loot", "Can I roll Need on this?", "Need, it's an upgrade for me.", "Greed.", "Pass.", "Anyone need this?",
		"Who can disenchant?" },
	{ name = "Declining", "Sorry, the group is full.", "Sorry, we already have one.", "Sorry, not right now.",
		"No thanks.", "Maybe next time!" },
	{ name = "Agreeing", "Yes.", "Yes, please.", "OK.", "Sure!", "Sounds good.", "Of course.", "Deal!", "Count me in." },
	{ name = "Congratulations", "Congratulations!", "Grats!", "Grats on the level!", "Grats on the drop!", "Well done!",
		"Nice one!", "Well deserved!" },
	{ name = "Thanks and goodbye", "Thanks!", "Thanks for the group!", "Thank you, take care!", "Take care!", "Good game, thanks all!", "Have fun!", "Bye!" },
}

-- {PAD4} on the Ratings tab: notes to pick, or type your own. Praise and Complaints, each by subject.
local NOTE_PRESETS = {
	{ name = "Praise", groups = {
		{ name = "General", "Great player", "Knows the dungeons", "Good with the mechanics", "Follows the plan", "Good leader",
			"Learns fast", "Fair with loot", "Stays until the end", "Quiet but good", "New to the game" },
		{ name = "Social", "Friendly", "Helpful", "Patient", "Funny", "Explains the fights", "Kind to new players",
			"Good chat", "Would group again" },
		{ name = "Tank", "Great tank", "Good pulls", "Good pace", "Holds threat well", "Picks up adds fast", "Marks the targets",
			"Waits for the healer's mana", "Uses the cooldowns", "Knows the route" },
		{ name = "Healer", "Great healer", "Keeps everyone up", "Good with mana", "Dispels and cleanses", "Calls out low mana",
			"Buffs the group", "Stays calm", "Saved the run" },
		{ name = "DPS", "Great DPS", "Interrupts", "Watches threat", "Kills the marked target first", "Uses crowd control",
			"Kills adds fast", "Buffs the group", "Shares water and food", "Stays out of the bad stuff" },
	} },
	{ name = "Complaints", groups = {
		{ name = "General", "Leaves early", "AFK a lot", "Doesn't follow the plan", "Stands in fire", "Doesn't know the dungeon",
			"Slow", "Disconnects a lot", "Ninja looter", "Needs on everything", "Joins without being near the dungeon",
			"Won't help summon" },
		{ name = "Social", "Rude", "Toxic", "Blames others", "Spams the chat", "Ignores the group", "Begs for items or gold",
			"Kicks without a reason" },
		{ name = "Tank", "Pulls too much", "Pulls too little", "Pulls too fast", "Waits too long between pulls", "Loses threat", "Doesn't wait for the healer", "Runs off from the group",
			"Doesn't use the cooldowns", "Doesn't mark" },
		{ name = "Healer", "Lets people die", "Out of mana a lot", "Doesn't dispel", "Heals only the tank", "Does damage instead of healing",
			"Doesn't say when drinking", "Doesn't buff" },
		{ name = "DPS", "Pulls without the tank", "Pulls threat", "Bad at managing aggro", "Doesn't interrupt", "Breaks crowd control", "Doesn't use crowd control", "Low damage", "Doesn't AoE",
			"Ignores the marks", "Doesn't buff" },
	} },
}

local QUICK_REPLIES = {
	"Hello!",
	"<ask>",
	"Sure, sending an invite.",
	"Sorry, the group is full.",
	"What role do you need?",
	"On my way!",
	"Thanks!",
}

---------------------------------------------------------------------------------------------------
-- Log

local function Clamp(value, low, high)
	return math.max(low, math.min(high, value))
end

local function Secret(value)
	return issecretvalue and issecretvalue(value) or false
end

-- A value, or the default when it is secret (the group finder's data can be, in chat lockdown).
local function Plain(value, default)
	if Secret(value) then
		return default
	end
	if value == nil then
		return default
	end
	return value
end

-- On with the session log (/gxiv log, or [Debug] Log this session).
function ns.LfgFilterLog(...)
	if not (ns.db and ns.db.playLogOn) then
		return
	end
	local parts = { date("%H:%M:%S") }
	for i = 1, select("#", ...) do
		local value = select(i, ...)
		parts[#parts + 1] = Secret(value) and "<secret>" or tostring(value)
	end
	local log = ns.db.lfgFilterLog
	if type(log) ~= "table" then
		log = {}
		ns.db.lfgFilterLog = log
	end
	log[#log + 1] = table.concat(parts, " ")
	while #log > LOG_MAX do
		tremove(log, 1)
	end
end
local Log = ns.LfgFilterLog

function ns.ClearLfgFilterLog()
	local count = ns.db and type(ns.db.lfgFilterLog) == "table" and #ns.db.lfgFilterLog or 0
	if ns.db then
		ns.db.lfgFilterLog = {}
	end
	ns.Print("LFG Filter log cleared (" .. count .. " lines). It records while /gxiv log is on and is saved on /reload or logout.")
end

-- Calls a game API function, logging an error or a missing function instead of stopping.
local function Call(label, fn, ...)
	if type(fn) ~= "function" then
		Log("api missing:", label)
		return nil
	end
	local results = { pcall(fn, ...) }
	if not results[1] then
		Log("api error:", label, results[2])
		return nil
	end
	return unpack(results, 2, table.maxn(results))
end

---------------------------------------------------------------------------------------------------
-- Saved data

local function Filters()
	local filters = ns.db.lfgFilter
	if type(filters) ~= "table" then
		filters = {}
		ns.db.lfgFilter = filters
	end
	filters.category = filters.category or 0
	-- The activities picked, a set; none means all. (One activity was saved as `activity` before.)
	filters.activities = filters.activities or {}
	if filters.activity then
		if filters.activity ~= 0 then
			filters.activities[filters.activity] = true
		end
		filters.activity = nil
	end
	filters.languages = filters.languages or {}
	filters.needs = filters.needs or {}
	filters.looking = filters.looking or {}
	filters.show = filters.show or "auto"
	return filters
end

local function Chats()
	if type(ns.db.lfgChats) ~= "table" then
		ns.db.lfgChats = {}
	end
	return ns.db.lfgChats
end

local function Recent()
	if type(ns.db.lfgRecent) ~= "table" then
		ns.db.lfgRecent = {}
	end
	return ns.db.lfgRecent
end

local function Ratings()
	GamepadXIVAccountDB = GamepadXIVAccountDB or {}
	local account = GamepadXIVAccountDB
	if type(account.lfgRatings) ~= "table" then
		account.lfgRatings = {}
	end
	return account.lfgRatings
end

-- Names are kept as Name-Realm, so ratings match across characters.
local function FullName(name)
	if type(name) ~= "string" or Secret(name) or name == "" then
		return nil
	end
	if not name:find("-", 1, true) then
		local realm = GetNormalizedRealmName and GetNormalizedRealmName()
		if realm and realm ~= "" then
			name = name .. "-" .. realm
		end
	end
	return name
end

local function Short(name)
	-- A Battle.net friend's conversation ("BN:Name#1234"): their BattleTag's name.
	local tag = type(name) == "string" and name:match("^BN:([^#]+)")
	if tag then
		return tag
	end
	return name and Ambiguate(name, "short") or "?"
end

-- A player's saved entry. Ratings are saved under "Name-Realm"; the group finder can give a name
-- without the realm for players on yours, so that is tried too.
function ns.LfgRatingEntry(name)
	if type(name) ~= "string" or name == "" then
		return nil
	end
	local ratings = Ratings()
	local entry = ratings[name]
	if not entry and not name:find("-", 1, true) then
		local realm = GetNormalizedRealmName and GetNormalizedRealmName()
		entry = realm and ratings[name .. "-" .. realm] or nil
	end
	return entry
end

-- How many times you grouped with a player, for the account (GamepadXIVAccountDB.lfgGroupCounts).
-- Counted from when this came in; a player only in the older Recent list counts once.
function ns.LfgGroupCounts()
	GamepadXIVAccountDB = GamepadXIVAccountDB or {}
	if type(GamepadXIVAccountDB.lfgGroupCounts) ~= "table" then
		GamepadXIVAccountDB.lfgGroupCounts = {}
	end
	return GamepadXIVAccountDB.lfgGroupCounts
end
-- The roles a player had in your groups, for the account (GamepadXIVAccountDB.lfgPlayerRoles):
-- name = { tank = true, healer = true, dps = true }.
function ns.LfgPlayerRoles()
	GamepadXIVAccountDB = GamepadXIVAccountDB or {}
	if type(GamepadXIVAccountDB.lfgPlayerRoles) ~= "table" then
		GamepadXIVAccountDB.lfgPlayerRoles = {}
	end
	return GamepadXIVAccountDB.lfgPlayerRoles
end
-- Their role icons, tank, healer, DPS, or "" when none was seen.
-- Whether they had that role in one of your groups.
function ns.LfgHadRole(name, role)
	return ns.LfgRoleIcons(name, 14):find(ns.LfgFilterKit.ROLE_ATLAS[role], 1, true) ~= nil
end

-- The past groups kept for their chat (ChatHistory.lua) count too.
function ns.LfgRoleIcons(name, size)
	if type(name) ~= "string" then
		return ""
	end
	local roles = {}
	for role in pairs(type(ns.LfgPlayerRoles()[name]) == "table" and ns.LfgPlayerRoles()[name] or {}) do
		roles[role] = true
	end
	local KEYS = { TANK = "tank", HEALER = "healer", DAMAGER = "dps" }
	for _, group in ipairs(ns.ChatHistory and ns.ChatHistory.Groups() or {}) do
		for _, member in ipairs(group.members or {}) do
			if member.name == name and KEYS[member.role or ""] then
				roles[KEYS[member.role]] = true
			end
		end
	end
	local icons = {}
	for _, role in ipairs({ "tank", "healer", "dps" }) do
		if roles[role] then
			icons[#icons + 1] = "|A:" .. ns.LfgFilterKit.ROLE_ATLAS[role] .. ":" .. (size or 14) .. ":" .. (size or 14) .. "|a"
		end
	end
	return table.concat(icons, " ")
end

-- Dungeons (and raids) run with each player, for the account (GamepadXIVAccountDB.lfgDungeons):
-- name = { n = runs, last = the run counted last }. A run is one group in one instance. The first time,
-- the past groups kept for their chat (ChatHistory.lua) that were in an instance are counted.
function ns.LfgDungeons()
	GamepadXIVAccountDB = GamepadXIVAccountDB or {}
	local account = GamepadXIVAccountDB
	if type(account.lfgDungeons) ~= "table" then
		account.lfgDungeons = {}
	end
	if not account.lfgDungeonsSeeded and ns.ChatHistory and ns.ChatHistory.Groups then
		account.lfgDungeonsSeeded = true
		for _, group in ipairs(ns.ChatHistory.Groups()) do
			if group.where and group.where ~= "" then
				for _, member in ipairs(group.members or {}) do
					if member.name and not member.me then
						local entry = account.lfgDungeons[member.name] or { n = 0 }
						entry.n = entry.n + 1
						account.lfgDungeons[member.name] = entry
					end
				end
			end
		end
	end
	return account.lfgDungeons
end
function ns.LfgDungeonCount(name)
	local entry = type(name) == "string" and ns.LfgDungeons()[name]
	return entry and entry.n or 0
end

function ns.LfgGroupCount(name)
	if type(name) ~= "string" or name == "" or not ns.db then
		return 0
	end
	local counts = ns.LfgGroupCounts()
	local realm = not name:find("-", 1, true) and GetNormalizedRealmName and GetNormalizedRealmName()
	local full = realm and (name .. "-" .. realm) or name
	local count = counts[name] or counts[full]
	if count then
		return count
	end
	for _, member in ipairs(type(ns.db.lfgRecent) == "table" and ns.db.lfgRecent or {}) do
		if member.name == name or member.name == full then
			return 1
		end
	end
	return 0
end

local function RatingOf(name)
	local entry = ns.LfgRatingEntry(name)
	return entry and entry.r or 0
end

local function NoteOf(name)
	local entry = ns.LfgRatingEntry(name)
	return entry and entry.n or nil
end

-- Sets a player's rating (0 clears it) and keeps their note; a player with neither is forgotten.
local function SetRating(name, rating, class)
	local ratings = Ratings()
	local entry = ratings[name] or {}
	entry.r = rating > 0 and rating or nil
	entry.c = class or entry.c
	entry.t = time()
	ratings[name] = (entry.r or entry.n) and entry or nil
end

local function SetNote(name, note, class)
	local ratings = Ratings()
	local entry = ratings[name] or {}
	note = note and strtrim(note) or ""
	entry.n = note ~= "" and note or nil
	entry.c = class or entry.c
	entry.t = entry.t or time()
	ratings[name] = (entry.r or entry.n) and entry or nil
end

local function ClassColored(name, class)
	local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	local text = Short(name)
	if type(name) == "string" and name:find("^BN:") then
		return "|cff82c5ff" .. text .. "|r" -- Battle.net blue
	end
	if color then
		return color:WrapTextInColorCode(text)
	end
	return text
end

local function Ago(stamp)
	local seconds = math.max(0, time() - (stamp or time()))
	if seconds < 60 then
		return "now"
	elseif seconds < 3600 then
		return math.floor(seconds / 60) .. "m"
	elseif seconds < 86400 then
		return math.floor(seconds / 3600) .. "h"
	end
	return math.floor(seconds / 86400) .. "d"
end

-- Unread whispers, and party and raid chat (all = also guild, officer and instance, for the Chat window).
local function UnreadTotal(all)
	local total = 0
	if ns.db then
		for name, chat in pairs(Chats()) do
			local channel = ChannelInfo(name)
			if not channel or channel.lfg or (all and channel.important) then
				total = total + (chat.unread or 0)
			end
		end
	end
	return total
end
ns.LfgFilterUnread = UnreadTotal

local function UnreadFrom(name)
	local chat = name and ns.db and Chats()[name]
	return chat and chat.unread or 0
end

---------------------------------------------------------------------------------------------------
-- The group finder's data

local state = {
	tab = 1, -- 1 Groups, 2 Chat, 3 Ratings
	focus = "list", -- Groups tab: "list" or "filters"
	listCursor = 1, listScroll = 0,
	filterCursor = 1,
	picker = nil, pickerCursor = 1, pickerScroll = 0, languagesChanged = false, -- the open dropdown
	chatCursor = 1, chatScroll = 0,
	rateCursor = 1, rateScroll = 0,
	replyIndex = 1,
	results = {}, total = 0,
	searching = false, searchStart = 0, searchedOnce = false, searchFailed = false,
	asked = {}, -- leaders whispered this session
	confirm = nil, -- the group a whisper waits on
}

local window
local Refresh -- redraws the window

local activityCache = {}

local function ActivityName(activityID)
	local info = Call("GetActivityInfoTable", C_LFGList.GetActivityInfoTable, activityID)
	if type(info) ~= "table" then
		return "?"
	end
	local short = Plain(info.shortName, "")
	return short ~= "" and short or Plain(info.fullName, "?")
end

-- A category's activities. With "Level-appropriate only" on (the default), only the ones the game suggests
-- for your level.
local function Activities(categoryID)
	if activityCache[categoryID] then
		return activityCache[categoryID]
	end
	local list = Call("GetAvailableActivities", C_LFGList.GetAvailableActivities, categoryID) or {}
	local showAll = Filters().allLevels
	local level = UnitLevel("player")
	local kept = {}
	for _, id in ipairs(list) do
		local info = Call("GetActivityInfoTable", C_LFGList.GetActivityInfoTable, id)
		local min = info and Plain(info.minLevelSuggestion, 0) or 0
		local max = info and Plain(info.maxLevelSuggestion, 0) or 0
		if showAll or not ((min > 0 and min > level) or (max > 0 and max < level)) then
			kept[#kept + 1] = { id = id, name = ActivityName(id), order = info and Plain(info.orderIndex, 0) or 0 }
		end
	end
	table.sort(kept, function(a, b)
		if a.order ~= b.order then
			return a.order < b.order
		end
		return a.name < b.name
	end)
	activityCache[categoryID] = kept
	return kept
end

-- The picked activities still on offer in this category, in its order; empty when none is picked.
function state.Picked(categoryID)
	local picked = {}
	local set = Filters().activities
	if next(set) and categoryID then
		for _, activity in ipairs(Activities(categoryID)) do
			if set[activity.id] then
				picked[#picked + 1] = activity.id
			end
		end
	end
	return picked
end

local categoryCache
local function Categories()
	if categoryCache then
		return categoryCache
	end
	categoryCache = {}
	for _, id in ipairs(Call("GetAvailableCategories", C_LFGList.GetAvailableCategories) or {}) do
		local info = Call("GetLfgCategoryInfo", C_LFGList.GetLfgCategoryInfo, id)
		if #Activities(id) > 0 then
			categoryCache[#categoryCache + 1] = { id = id, name = info and Plain(info.name, nil) or ("Category " .. id) }
		end
	end
	Log("categories:", #categoryCache)
	return categoryCache
end

local function ClearCaches()
	wipe(activityCache)
	categoryCache = nil
end

local function CurrentCategory()
	local filters = Filters()
	local list = Categories()
	for index, category in ipairs(list) do
		if category.id == filters.category then
			return category, index
		end
	end
	if list[1] then
		filters.category = list[1].id
		wipe(filters.activities)
		return list[1], 1
	end
end

local function Languages()
	local offered = Call("GetAvailableLanguageSearchFilter", C_LFGList.GetAvailableLanguageSearchFilter)
	local locked = Call("GetDefaultLanguageSearchFilter", C_LFGList.GetDefaultLanguageSearchFilter)
	locked = type(locked) == "table" and locked or {}
	local list = {}
	for _, code in ipairs(type(offered) == "table" and offered or {}) do
		if type(code) == "string" then
			local name = _G["LFG_LIST_LANGUAGE_" .. code:upper()]
			list[#list + 1] = { code = code, name = type(name) == "string" and name or code, locked = locked[code] and true or false }
		end
	end
	table.sort(list, function(a, b)
		if a.locked ~= b.locked then
			return a.locked
		end
		return a.name < b.name
	end)
	return list
end

-- What the search is sent: nil (your own language, as the game's window searches) when no other
-- language is picked, otherwise every picked language and the ones the game always includes.
local function LanguageFilter()
	local filters = Filters()
	local set, extra = {}, false
	for _, language in ipairs(Languages()) do
		if language.locked then
			set[language.code] = true
		elseif filters.languages[language.code] then
			set[language.code] = true
			extra = true
		end
	end
	return extra and set or nil
end

local function LanguageSummary()
	local names = {}
	for _, language in ipairs(Languages()) do
		if language.locked or Filters().languages[language.code] then
			names[#names + 1] = language.name
		end
	end
	if #names == 0 then
		return "Your language"
	elseif #names <= 2 then
		return table.concat(names, ", ")
	end
	return names[1] .. ", " .. names[2] .. " +" .. (#names - 2)
end

-- Groups while you are on your own, players while you are in a group, unless picked.
local function ShowPlayers()
	local show = Filters().show
	if show == "groups" then
		return false
	elseif show == "players" then
		return true
	end
	return IsInGroup() and true or false
end

local function SetStatus(text)
	state.status = text
	if window and window:IsShown() then
		Refresh()
	end
end

local function DoSearch(reason)
	if state.searching and GetTime() - state.searchStart < SEARCH_TIMEOUT then
		Log("search waits for the running one:", reason)
		state.searchAgain = reason or "again"
		return
	end
	state.searchAgain = nil
	local category = CurrentCategory()
	if not category then
		Log("search: no category available")
		SetStatus("The group finder has no categories for you yet.")
		return
	end
	local filters = Filters()
	local activities = {}
	local picked = state.Picked(category.id)
	if #picked > 0 then
		activities = picked
	else
		for _, activity in ipairs(Activities(category.id)) do
			activities[#activities + 1] = activity.id
		end
	end
	if #activities == 0 then
		Log("search: no activities in category", category.id)
		SetStatus("Nothing to search for at your level.")
		return
	end
	local languages = LanguageFilter()
	Log("search", reason or "", "category", category.id, category.name, "activities", #activities,
		"languages", languages and "picked" or "default", "inCombat", tostring(InCombatLockdown()))
	ns.Trail("lfg filter: C_LFGList.Search")
	local ok, err = pcall(C_LFGList.Search, category.id, 0, 0, languages, false, nil, activities)
	if not ok then
		Log("search error:", err)
		SetStatus("The search failed. See /gxiv lfgfilterlog.")
		return
	end
	state.searching = true
	state.searchFailed = false
	state.searchStart = GetTime()
	state.refreshAt, state.refreshDue = GetTime() + state.AUTO_REFRESH, nil
	state.status = nil
	if window and window:IsShown() then
		Refresh()
	end
end

-- One listing, read into a plain table. A listing whose data is secret is kept, unfiltered.
-- entry.memberList (leader first) is what the details panel beside the list shows (LfgDetails.lua).
local function ReadResult(id)
	local info = Call("GetSearchResultInfo", C_LFGList.GetSearchResultInfo, id)
	if type(info) ~= "table" then
		return nil
	end
	local entry = { id = id }
	if Secret(info.numMembers) or Secret(info.leaderName) or Secret(info.isDelisted) then
		entry.secret = true
		entry.members = 0
		entry.activityText = "Hidden right now"
		entry.comment = ""
		entry.rating = 0
		return entry
	end
	-- A player as GetSearchResultPlayerInfo / GetSearchResultLeaderInfo give them; any field can be
	-- missing or secret, and is then left out.
	local function Member(player)
		if type(player) ~= "table" then
			return nil
		end
		local zone = Plain(player.areaName, nil)
		local member = {
			name = FullName(Plain(player.name, nil)),
			class = Plain(player.classFilename, nil),
			level = Plain(player.level, nil),
			zone = type(zone) == "string" and zone ~= "" and zone or nil,
			leader = Plain(player.isLeader, false) and true or false,
		}
		local assigned = Plain(player.assignedRole, nil)
		for _, role in ipairs(ROLES) do
			if assigned == ROLE_COUNT_KEY[role] then
				member.role = role
			end
		end
		local roles = Plain(player.lfgRoles, nil)
		if type(roles) == "table" then
			member.roles = { tank = Plain(roles.tank, false), healer = Plain(roles.healer, false), dps = Plain(roles.dps, false) }
		end
		return member
	end
	entry.delisted = info.isDelisted and true or false
	entry.self = Plain(info.hasSelf, false) and true or false
	entry.members = Plain(info.numMembers, 0)
	entry.solo = entry.members <= 1
	entry.leader = FullName(info.leaderName)
	entry.comment = Plain(info.comment, "")
	entry.title = Plain(info.name, "")
	entry.age = Plain(info.age, 0)
	entry.listedAt = time() - (tonumber(entry.age) or 0)
	entry.newPlayers = Plain(info.newPlayerFriendly, false)
	local activities = Plain(info.activityIDs, {})
	if #activities == 1 then
		entry.activityText = ActivityName(activities[1])
	elseif #activities > 1 then
		entry.activityText = ActivityName(activities[1]) .. " +" .. (#activities - 1)
	else
		entry.activityText = ""
	end
	entry.activities = activities
	-- The group's size: the most players its activities take (5 for a dungeon).
	local most = 0
	for _, activityID in ipairs(activities) do
		local activity = Call("GetActivityInfoTable", C_LFGList.GetActivityInfoTable, activityID)
		local size = type(activity) == "table" and tonumber(Plain(activity.maxNumPlayers, 0)) or 0
		most = math.max(most, size or 0)
	end
	entry.maxPlayers = math.max(most > 0 and most or 5, entry.members)
	entry.memberList = {}
	if entry.solo then
		local player = Call("GetSearchResultPlayerInfo", C_LFGList.GetSearchResultPlayerInfo, id, 1)
		if type(player) == "table" then
			entry.class = Plain(player.classFilename, nil)
			entry.level = Plain(player.level, nil)
			local member = Member(player)
			entry.roles = member.roles
			member.name = member.name or entry.leader
			entry.memberList[1] = member
		end
	else
		local leader = Call("GetSearchResultLeaderInfo", C_LFGList.GetSearchResultLeaderInfo, id)
		if type(leader) == "table" then
			entry.class = Plain(leader.classFilename, nil)
			entry.level = Plain(leader.level, nil)
		end
		local counts = Call("GetSearchResultMemberCounts", C_LFGList.GetSearchResultMemberCounts, id)
		if type(counts) == "table" then
			entry.counts = {}
			for _, role in ipairs(ROLES) do
				local key = ROLE_COUNT_KEY[role]
				entry.counts[role] = Plain(counts[key], 0)
				entry.counts[role .. "Left"] = Plain(counts[key .. "_REMAINING"], 0)
			end
		end
		-- The members, and the ones you rated.
		entry.avoided, entry.liked = 0, 0
		local hasLeader = false
		for index = 1, math.min(entry.members, 40) do
			local player = Call("GetSearchResultPlayerInfo", C_LFGList.GetSearchResultPlayerInfo, id, index)
			local member = Member(player)
			local name = member and member.name
			if member then
				member.leader = member.leader or (name ~= nil and name == entry.leader)
				hasLeader = hasLeader or member.leader
				tinsert(entry.memberList, member.leader and 1 or #entry.memberList + 1, member)
			end
			local rating = RatingOf(name)
			if rating == 1 then
				entry.avoided = entry.avoided + 1
			elseif rating == 3 then
				entry.liked = entry.liked + 1
			end
			-- Members you rated or wrote a note on, other than the leader.
			if name and name ~= entry.leader and (rating > 0 or NoteOf(name)) then
				entry.known = entry.known or {}
				tinsert(entry.known, name)
			end
		end
		if not hasLeader and type(leader) == "table" then
			local member = Member(leader)
			member.name = member.name or entry.leader
			member.leader = true
			tinsert(entry.memberList, 1, member)
		end
	end
	entry.rating = RatingOf(entry.leader)
	entry.note = NoteOf(entry.leader)
	return entry
end
ns.LfgFilterReadResult = ReadResult -- for the tests

local function MatchesRoles(entry, wanted, players)
	if players then
		local roles = entry.roles
		if not roles then
			return true -- nothing to filter on
		end
		for _, role in ipairs(ROLES) do
			if wanted[role] and roles[role] then
				return true
			end
		end
		return false
	end
	if not entry.counts then
		return true
	end
	for _, role in ipairs(ROLES) do
		if wanted[role] and entry.counts[role .. "Left"] > 0 then
			return true
		end
	end
	return false
end
ns.LfgFilterMatchesRoles = MatchesRoles -- for the tests

local function BuildResults()
	local total, ids = Call("GetFilteredSearchResults", C_LFGList.GetFilteredSearchResults)
	ids = type(ids) == "table" and ids or {}
	local players = ShowPlayers()
	local filters = Filters()
	local wanted = players and filters.looking or filters.needs
	local anyRole = wanted.tank or wanted.healer or wanted.dps
	local results = {}
	local skipped = { delisted = 0, self = 0, kind = 0, roles = 0, secret = 0 }
	for _, id in ipairs(ids) do
		local entry = ReadResult(id)
		if entry then
			if entry.secret then
				skipped.secret = skipped.secret + 1
				results[#results + 1] = entry
			elseif entry.delisted then
				skipped.delisted = skipped.delisted + 1
			elseif entry.self then
				skipped.self = skipped.self + 1
			elseif entry.solo ~= players then
				skipped.kind = skipped.kind + 1
			elseif anyRole and not MatchesRoles(entry, wanted, players) then
				skipped.roles = skipped.roles + 1
			elseif filters.hideAvoided and (entry.rating == 1 or (entry.avoided or 0) > 0) then
				skipped.avoided = (skipped.avoided or 0) + 1
			else
				results[#results + 1] = entry
			end
		end
	end
	-- What is typed in the search box: the leader, the activity, the comment, a member, your note.
	local query = state.FindText(TAB_FINDER)
	if query then
		local shown = {}
		for _, entry in ipairs(results) do
			local found = state.Found(query, entry.leader, entry.activityText, entry.title, entry.comment, entry.note)
			for _, member in ipairs(entry.memberList or {}) do
				found = found or state.Found(query, member.name, NoteOf(member.name))
			end
			if found then
				shown[#shown + 1] = entry
			end
		end
		results = shown
	end
	-- Great first and Avoid last, then unread whispers, then the newest.
	local function Rank(entry)
		if entry.rating == 1 or (entry.avoided or 0) > 0 then
			return 2
		elseif entry.rating == 3 then
			return 0
		end
		return 1
	end
	table.sort(results, function(a, b)
		local rankA, rankB = Rank(a), Rank(b)
		if rankA ~= rankB then
			return rankA < rankB
		end
		local unreadA, unreadB = UnreadFrom(a.leader), UnreadFrom(b.leader)
		if (unreadA > 0) ~= (unreadB > 0) then
			return unreadA > 0
		end
		return (a.age or 0) < (b.age or 0)
	end)
	state.results = results
	state.total = Plain(total, #ids)
	-- The cursor stays on the same listing when the list changes.
	if state.selectedResult then
		for index, entry in ipairs(results) do
			if entry.id == state.selectedResult then
				state.listCursor = index
				break
			end
		end
	end
	Log("results:", #ids, "shown", #results, players and "players" or "groups",
		"hidden: delisted", skipped.delisted, "own", skipped.self, "other kind", skipped.kind,
		"roles", skipped.roles, "secret (kept)", skipped.secret)
end

---------------------------------------------------------------------------------------------------
-- Whispers, invites, chat history

-- Removes chat past the "Chat lines kept" and "Chat kept for" settings.
local function PruneChat(chat, now)
	local limit = Clamp(tonumber(ns.db.lfgChatLines) or 100, 10, MAX_LINES)
	local keep = KEEP_SECONDS[ns.db.lfgChatKeep]
	local removed = 0
	while #chat.lines > limit do
		tremove(chat.lines, 1)
		removed = removed + 1
	end
	if keep then
		while chat.lines[1] and (chat.lines[1].t or 0) < now - keep do
			tremove(chat.lines, 1)
			removed = removed + 1
		end
	end
	if removed > 0 then
		chat.seq = (chat.seq or 0) + 1
		chat.unread = math.min(chat.unread or 0, #chat.lines)
	end
	return removed
end

function ns.PruneLfgChats(reason)
	if not ns.db then
		return
	end
	local now, removed, dropped = time(), 0, 0
	local chats = Chats()
	for name, chat in pairs(chats) do
		removed = removed + PruneChat(chat, now)
		if #chat.lines == 0 and (chat.last or 0) < now - 3600 then
			chats[name] = nil
			dropped = dropped + 1
		end
	end
	Log("chat pruned:", reason, "lines", removed, "conversations", dropped)
	ns.RefreshLfgFilter()
end

-- kind: the line's chat type when it isn't the conversation's own (PARTY_LEADER, RAID_WARNING, LOOT), for its colour.
local function AddLine(name, outgoing, text, class, sender, senderClass, kind)
	local chats = Chats()
	local chat = chats[name]
	if not chat then
		chat = { lines = {}, unread = 0 }
		chats[name] = chat
	end
	chat.class = class or chat.class
	chat.last = time()
	chat.closed = nil -- a new message opens a closed conversation again
	chat.seq = (chat.seq or 0) + 1
	tinsert(chat.lines, { o = outgoing or nil, m = text, t = time(), s = sender, c = senderClass, k = kind })
	PruneChat(chat, time())
	-- Drop the oldest conversations.
	local count, oldestName, oldest = 0, nil, nil
	for key, other in pairs(chats) do
		count = count + 1
		if not oldest or (other.last or 0) < oldest then
			oldestName, oldest = key, other.last or 0
		end
	end
	if count > MAX_CHATS and oldestName and oldestName ~= name then
		chats[oldestName] = nil
	end
	return chat
end

-- A player can have several notes, kept as one text ("Friendly; Good pulls") so everything that shows
-- a note shows them all.
function state.NoteList(name)
	local list = {}
	for part in ((name and NoteOf(name)) or ""):gmatch("[^;]+") do
		part = strtrim(part)
		if part ~= "" then
			list[#list + 1] = part
		end
	end
	return list
end
function state.ToggleNote(target, note, on)
	local list, found = state.NoteList(target.name), nil
	for index, part in ipairs(list) do
		if part == note then
			found = index
		end
	end
	if found and not on then
		table.remove(list, found)
	elseif not found and on ~= false then
		list[#list + 1] = note
	end
	SetNote(target.name, table.concat(list, "; "), target.class)
end

-- Auto refresh: the game only takes a search from a button press, so once the countdown ends the
-- search runs on your next press in the window (the Nav buttons), not from a timer.
state.AUTO_REFRESH = 30
function state.RefreshText()
	if state.searching or not state.refreshAt then
		return ""
	elseif state.refreshDue then
		return "  |cff999999- press any button to refresh|r"
	end
	return "  |cff999999- refresh in " .. math.max(0, math.ceil(state.refreshAt - GetTime())) .. "s, on your next press|r"
end
function state.TickRefresh()
	if not state.refreshAt or state.searching then
		return
	end
	if not state.refreshDue and GetTime() >= state.refreshAt then
		state.refreshDue = true
	end
	if state.headerBase and window.resultsHeader:IsVisible() then
		window.resultsHeader:SetText(state.headerBase .. state.RefreshText())
	end
end

-- The search box over the Group finder, Chat and Ratings lists ({PADRTRIGGER}): what is typed per tab,
-- and whether any of the texts has it, ignoring case.
state.find = {}
function state.FindText(tab)
	local text = state.find[tab]
	text = text and strtrim(text):lower() or ""
	return text ~= "" and text or nil
end
function state.Found(query, ...)
	for index = 1, select("#", ...) do
		local text = select(index, ...)
		if type(text) == "string" and text:lower():find(query, 1, true) then
			return true
		end
	end
	return false
end

-- The Ratings tab's sort and filters ({PADLTRIGGER}), saved per character (ns.db.lfgRateSort ...).
state.RATE_VIEW_ORDER = { "Sort", "Show", "Role" }
state.RATE_VIEW = {
	Sort = { { "recent", "Last grouped" }, { "name", "Name" }, { "dungeons", "Most dungeons" }, { "rating", "Rating, Great first" } },
	Show = { { "all", "Everyone" }, { "3", "Great" }, { "2", "Okay" }, { "1", "Avoid" }, { "none", "Not rated" }, { "notes", "With notes" } },
	Role = { { "any", "Any role" }, { "tank", "Tank" }, { "healer", "Healer" }, { "dps", "DPS" } },
}
function state.RateView(key)
	local value = ns.db and ns.db["lfgRate" .. key]
	for _, choice in ipairs(state.RATE_VIEW[key]) do
		if choice[1] == value then
			return choice[1], choice[2]
		end
	end
	return state.RATE_VIEW[key][1][1], state.RATE_VIEW[key][1][2]
end

-- A player you know is in your group now: in chat, how often you grouped before, your rating, your
-- note. Avoid in red.
function state.SayKnown(name, class, times)
	local parts = {}
	if times > 0 then
		parts[#parts + 1] = "grouped " .. (times == 1 and "once" or (times .. " times")) .. " before"
	end
	local rating = RatingOf(name)
	if rating > 0 then
		parts[#parts + 1] = "rated " .. RATINGS[rating].tag
	end
	local note = NoteOf(name)
	if note then
		parts[#parts + 1] = "note: |cffdddddd" .. note .. "|r"
	end
	Log("known player in the group:", name, table.concat(parts, ", "))
	local text = ClassColored(name, class) .. " is in your group: " .. table.concat(parts, ", ") .. "."
	ns.Print(rating == 1 and (text .. " |cffff5555You rated them Avoid.|r") or text)
end

-- The Chat window's tabs: which conversations its list shows. In state: the file is near Lua's 200 locals.
state.chatTabs = {
	{ name = "All" },
	{ name = "Whispers", kind = "whisper" },
	{ name = "Group", kind = "group" },
	{ name = "Guild", kind = "guild" },
	{ name = "Channels", kind = "channel" },
}
state.chatTab = 1
state.groupKeys = { ["#PARTY"] = true, ["#RAID"] = true, ["#INSTANCE"] = true }
function state.ChatKind(name, item)
	if (item and item.group) or tostring(name):find("^#GRP:") then
		return "group"
	elseif not ChannelInfo(name) then
		return "whisper"
	elseif state.groupKeys[name] then
		return "group"
	elseif name == "#GUILD" or name == "#OFFICER" then
		return "guild"
	end
	return "channel"
end
-- Unread messages under a tab, for its badge.
function state.ChatTabUnread(tab)
	local total = 0
	for name, chat in pairs(ns.db and Chats() or {}) do
		local channel = ChannelInfo(name)
		if (not channel or channel.important or channel.lfg) and (not tab.kind or state.ChatKind(name) == tab.kind) then
			total = total + (chat.unread or 0)
		end
	end
	return total
end
function state.SelectChatTab(index)
	local count = #state.chatTabs
	index = (index - 1) % count + 1
	if index ~= state.chatTab then
		state.chatTab = index
		state.chatCursor, state.chatScroll = 1, 0
		state.selectedName = nil
		Log("chat tab", state.chatTabs[index].name)
	end
end

-- Opening on a conversation: back to All when the tab shown doesn't have it.
function state.ShowChatTabOf(name)
	local kind = state.chatTabs[state.chatTab].kind
	if kind and state.ChatKind(name) ~= kind then
		state.chatTab = 1
	end
end

-- Raid and party first while you are in one, then whispers, the newest first.
local function SortedChats()
	local list = {}
	local chats = Chats()
	local all = state.chatMode
	for _, key in ipairs(CHANNEL_ORDER) do
		local channel = CHANNELS[key]
		if (all or channel.lfg) and channel.shown(chats[key]) then
			chats[key] = chats[key] or { lines = {}, unread = 0, last = 0 }
			list[#list + 1] = { name = key, chat = chats[key] }
		end
	end
	if all then
		local numbered = {}
		for name, chat in pairs(chats) do
			if name:find("^#CH:") then
				numbered[#numbered + 1] = { name = name, chat = chat }
			end
		end
		table.sort(numbered, function(a, b) return a.name < b.name end)
		for _, item in ipairs(numbered) do
			list[#list + 1] = item
		end
		if CHANNELS["#SYSTEM"].shown(chats["#SYSTEM"]) then
			list[#list + 1] = { name = "#SYSTEM", chat = chats["#SYSTEM"] }
		end
	end
	-- Whispers: the ones from the last 30 minutes, opened or unread, here; the rest and the closed
	-- ones in History, a row at the end (and a Back row at the top of History).
	local history = state.chatHistory
	if history then
		list = { { special = "back", chat = { lines = {}, unread = 0 } } }
	end
	local whispers, older = {}, 0
	local now = time()
	for name, chat in pairs(chats) do
		if not ChannelInfo(name) then
			local recent = now - math.max(chat.last or 0, chat.opened or 0) < 1800
			local active = (not chat.closed and recent) or (chat.unread or 0) > 0
			if active ~= (history or false) then
				whispers[#whispers + 1] = { name = name, chat = chat }
			elseif not active then
				older = older + 1
			end
		end
	end
	-- Past groups' chat (ChatHistory.lua) is in History too, with the whispers by time.
	for _, group in ipairs(ns.ChatHistory and ns.ChatHistory.Groups() or {}) do
		if history then
			whispers[#whispers + 1] = { name = ns.ChatHistory.Key(group), chat = group, group = group }
		else
			older = older + 1
		end
	end
	table.sort(whispers, function(a, b)
		return (a.chat.last or 0) > (b.chat.last or 0)
	end)
	for _, item in ipairs(whispers) do
		list[#list + 1] = item
	end
	if not history and older > 0 then
		list[#list + 1] = { special = "history", count = older, chat = { lines = {}, unread = 0 } }
	end
	-- What is typed in the search box: the conversation's name or any of its messages.
	local query = state.FindText(TAB_CHAT)
	if query then
		local shown = {}
		for _, item in ipairs(list) do
			local found = item.special ~= nil
			if not found then
				local info = ChannelInfo(item.name)
				found = state.Found(query, item.name, info and info.name)
				for _, line in ipairs(item.chat and item.chat.lines or {}) do
					if found then
						break
					end
					found = state.Found(query, line.m, line.s)
				end
			end
			if found then
				shown[#shown + 1] = item
			end
		end
		list = shown
	end
	-- The Chat window's tab: only its conversations (History holds whispers and past groups).
	local kind = state.chatMode and state.chatTabs[state.chatTab].kind
	if kind then
		local shown = {}
		for _, item in ipairs(list) do
			if item.special == "back" or (item.special == "history" and (kind == "whisper" or kind == "group"))
					or (not item.special and state.ChatKind(item.name, item) == kind) then
				shown[#shown + 1] = item
			end
		end
		list = shown
	end
	return list
end

-- A conversation's name as shown: Party or Raid in their chat colours, a player in their class colour.
local function ChatName(name, chat)
	local channel = ChannelInfo(name)
	if channel then
		return "|cff" .. channel.color .. channel.name .. "|r"
	end
	return ClassColored(name, chat and chat.class)
end

local Whisper

-- The game locks chat for addons in some fights (instance boss fights, Mythic+, rated PvP): sending
-- then is blocked and shows "Interface action failed because of an AddOn". The message isn't sent.
function ns.ChatLocked()
	local locked = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
	if not locked then
		return false
	end
	local ok, result = pcall(locked)
	return ok and result and true or false
end

function ns.SayChatLocked(why)
	Log("chat locked by the game, not sent:", why)
	ns.Print("The game locks chat for addons during this fight, so the message wasn't sent. It stays in the box: send it once the fight ends.")
end

-- Sends to a conversation: a whisper, or party or raid chat.
local function SendTo(name, text, why)
	local channel = ChannelInfo(name)
	if not channel then
		return Whisper(name, text, why)
	end
	if not text or text == "" or channel.readOnly then
		return false
	end
	if text:sub(1, 1) == "/" then
		ns.Print("Slash commands only work in the game's chat: press L3 in the Chat window, or switch chat in the settings.")
		return false
	end
	if ns.ChatLocked() then
		ns.SayChatLocked(why)
		return false
	end
	local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
	ns.Trail("lfg filter: " .. channel.chatType:lower() .. " chat")
	local target
	if channel.channel then
		local chat = Chats()[name]
		target = chat and chat.number or GetChannelName(channel.channel)
		if not target or target == 0 then
			ns.Print("You are not in the " .. channel.name .. " channel.")
			return false
		end
	end
	local ok, err = pcall(send, text, channel.chatType, nil, target)
	Log(channel.chatType, why, ok and "sent" or ("failed: " .. tostring(err)), text)
	return ok
end

local function SelectedChat()
	local list = SortedChats()
	-- The conversation stays selected when rows are added above it.
	if state.selectedName then
		for index, item in ipairs(list) do
			if item.name == state.selectedName then
				state.chatCursor = index
				break
			end
		end
	end
	state.chatCursor = math.max(1, math.min(state.chatCursor, #list))
	local item = list[state.chatCursor]
	if item and item.special then
		return nil, nil, list, item.special
	end
	return item and item.name, item and item.chat, list
end

-- The name to send to: without the realm for players on yours. Names are kept with the realm the
-- client reports, which the server doesn't take back in a whisper or an invite.
local function Target(name)
	if not name then
		return nil
	end
	local realm = GetNormalizedRealmName and GetNormalizedRealmName()
	if realm and realm ~= "" and name:sub(-#realm - 1) == "-" .. realm then
		return name:sub(1, -#realm - 2)
	end
	return Ambiguate(name, "none")
end

function Whisper(target, text, why)
	if not target or not text or text == "" then
		Log("whisper skipped:", why, "no target or text")
		return false
	end
	if ns.ChatLocked() then
		ns.SayChatLocked(why)
		return false
	end
	if target:find("^BN:") then
		return ns.BNetWhisper(target, text, why)
	end
	target = Target(target)
	local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
	ns.Trail("lfg filter: whisper")
	local ok, err = pcall(send, text, "WHISPER", nil, target)
	Log("whisper", why, target, ok and "sent" or ("failed: " .. tostring(err)), text)
	if not ok then
		ns.Print("The whisper could not be sent. See /gxiv lfgfilterlog.")
	end
	return ok
end

-- Battle.net friends: their conversation is "BN:" and their BattleTag, which stays the same between
-- sessions; the account ID the game sends to (BNSendWhisper) is looked up again by it.
function ns.BNetKey(accountID)
	local info = accountID and C_BattleNet and C_BattleNet.GetAccountInfoByID and C_BattleNet.GetAccountInfoByID(accountID)
	local tag = info and Plain(info.battleTag, nil)
	return tag and ("BN:" .. tag) or nil
end
function ns.BNetAccountID(key)
	local tag = key:match("^BN:(.+)$")
	local count = BNGetNumFriends and BNGetNumFriends() or 0
	for index = 1, count do
		local info = C_BattleNet and C_BattleNet.GetFriendAccountInfo and C_BattleNet.GetFriendAccountInfo(index)
		if info and Plain(info.battleTag, nil) == tag then
			return info.bnetAccountID
		end
	end
end
function ns.BNetWhisper(key, text, why)
	local id = ns.BNetAccountID(key)
	local send = (C_BattleNet and C_BattleNet.SendWhisper) or BNSendWhisper
	if not id or not send then
		ns.Print("Couldn't find " .. Short(key) .. " in your Battle.net friends.")
		Log("bnet whisper", why, key, "no account")
		return false
	end
	ns.Trail("lfg filter: bnet whisper")
	local ok, err = pcall(send, id, text)
	Log("bnet whisper", why, key, ok and "sent" or ("failed: " .. tostring(err)), text)
	if not ok then
		ns.Print("The whisper could not be sent. See /gxiv lfgfilterlog.")
	end
	return ok
end

local function Invite(name)
	if not name then
		return
	end
	if name:find("^BN:") then
		ns.Print("Invite " .. Short(name) .. " from your friends list: Battle.net friends can't be invited by name.")
		return
	end
	if IsInGroup() and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
		ns.Print("Only the group leader or an assistant can invite.")
		Log("invite refused: not leader", name)
		return
	end
	local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
	ns.Trail("lfg filter: invite")
	name = Target(name)
	local ok, err = pcall(invite, name)
	Log("invite", name, ok and "sent" or ("failed: " .. tostring(err)))
	if ok then
		ns.Print("Invited " .. Short(name) .. ".")
	end
end

-- A quick reply by its place in the list, or a message given as text; "<ask>" becomes your group
-- finder message. The lists can be edited (MessagesEditor.lua), so a place past the end is the first.
local function ReplyText(index, name)
	local reply = type(index) == "string" and index or QUICK_REPLIES[index] or QUICK_REPLIES[1] or ""
	if reply == "<ask>" then
		local category = CurrentCategory()
		return ns.LfgMessage and ns.LfgMessage({ leaderName = name, activityIDs = state.Picked(category and category.id) }) or "Hi! Can I join?"
	end
	return reply
end

-- A ready-made message (already through ReplyText) goes into the message being typed, at the cursor,
-- and the cursor goes in the box; nothing is sent ({PAD1} or Enter sends the whole message, with the
-- raid markers once: window.input.Submit). ns.ChatInsert is in ChatBox.lua. Kept in state: the file is
-- near Lua's 200 locals.
function state.AddToMessage(text, why)
	local input = window and window.input
	if not input or type(text) ~= "string" or strtrim(text) == "" then
		return false
	end
	local ok = ns.ChatInsert and ns.ChatInsert(input, text)
	if ok then
		Log("added to the message:", why)
	else
		ns.Print("That doesn't fit: a chat message holds 255 letters.")
	end
	if not input:HasFocus() then
		input:SetFocus()
	end
	return ok
end

-- The message just picked in a message list ("phrase:N"), for 1.5 seconds: "Added" by the list's title
-- and a tick on it, or why it wasn't.
function state.Added(kind)
	local added = state.added
	if added and added.kind == kind and GetTime() - added.at <= 1.5 then
		return added
	end
end

-- The group's activities you picked in the filter, or all of the group's when you picked none of them.
local function AskActivities(entry)
	local set = Filters().activities
	local both = {}
	for _, id in ipairs(entry.activities or {}) do
		if set[id] then
			both[#both + 1] = id
		end
	end
	return #both > 0 and both or entry.activities
end

local function AskToJoin(entry)
	local text = ns.LfgMessage and ns.LfgMessage({ leaderName = entry.leader, activityIDs = AskActivities(entry) }) or ""
	if Whisper(entry.leader, text, "ask to join") then
		state.asked[entry.leader] = true
	end
end

-- The chat tab opens on this player, making a conversation if there is none yet.
local function OpenChatWith(name, class)
	if not name then
		return
	end
	local chats = Chats()
	if not chats[name] then
		chats[name] = { lines = {}, unread = 0, class = class, last = time() }
	end
	chats[name].closed = nil
	chats[name].opened = time()
	state.chatHistory = nil
	state.selectedName = name
	state.ShowChatTabOf(name)
	for index, item in ipairs(SortedChats()) do
		if item.name == name then
			state.chatCursor = index
		end
	end
	state.tab = TAB_CHAT
	Log("chat opened with", name)
	Refresh()
end

-- Open Chat from the game's group finder (Lfg.lua): LFG Filter opens on its Chat with the leader.
function ns.LfgChatWith(name, class)
	OpenChatWith(name, class)
	ns.OpenGamepadChat(true)
end

---------------------------------------------------------------------------------------------------
-- Window parts

local function Flat(frame, color, edge)
	frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	frame:SetBackdropColor(unpack(color))
	frame:SetBackdropBorderColor(unpack(edge or EDGE))
end

local function Text(parent, font, size)
	local text = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
	if size then
		local file, _, flags = text:GetFont()
		text:SetFont(file, size, flags)
	end
	text:SetWordWrap(false)
	return text
end

-- A round red bubble with a count, hidden at zero.
local function CreateBadge(parent)
	local badge = CreateFrame("Frame", nil, parent)
	badge:SetSize(20, 20)
	badge:SetFrameLevel(parent:GetFrameLevel() + 5)
	badge.circle = badge:CreateTexture(nil, "ARTWORK")
	badge.circle:SetAllPoints()
	badge.circle:SetTexture(MEDIA .. "circle_mask")
	badge.circle:SetVertexColor(0.86, 0.16, 0.16, 1)
	badge.text = Text(badge, "GameFontHighlightSmall")
	badge.text:SetPoint("CENTER", 0, 0)
	function badge:SetCount(count)
		count = count or 0
		self:SetShown(count > 0)
		self.text:SetText(count > 99 and "99+" or tostring(count))
		self:SetWidth(math.max(20, self.text:GetStringWidth() + 10))
	end
	badge:Hide()
	return badge
end

local function SetRowSelected(row, selected)
	if selected then
		row:SetBackdropColor(unpack(SELECTED))
		row:SetBackdropBorderColor(unpack(SELECTED_EDGE))
	else
		row:SetBackdropColor(unpack(row.baseColor or CONTROL))
		row:SetBackdropBorderColor(unpack(EDGE))
	end
end

local function CreateRow(parent, height, onClick)
	local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
	row:SetHeight(height)
	Flat(row, CONTROL)
	row:RegisterForClicks("LeftButtonUp")
	row:SetScript("OnClick", onClick)
	row:EnableMouseWheel(true)
	return row
end

local function RoleIcon(parent, size)
	local icon = parent:CreateTexture(nil, "ARTWORK")
	icon:SetSize(size, size)
	return icon
end

-- What the details panel beside the list (LfgDetails.lua) uses of this file. A field, not a local:
-- this file's main chunk is at Lua's 200-local limit.
ns.LfgFilterKit = {
	Flat = Flat, Log = Log, ClassColored = ClassColored, Short = Short, RatingOf = RatingOf, NoteOf = NoteOf,
	Ago = Ago, ActivityName = ActivityName,
	GOLD = GOLD, RATINGS = RATINGS, ROLES = ROLES, ROLE_NAMES = ROLE_NAMES, ROLE_ATLAS = ROLE_ATLAS,
}

---------------------------------------------------------------------------------------------------
-- Groups tab

local filterRows -- built each redraw
local FilterRowsList

local function StepCategory(delta)
	local list = Categories()
	if #list == 0 then
		return
	end
	local _, index = CurrentCategory()
	index = ((index or 1) - 1 + delta) % #list + 1
	Filters().category = list[index].id
	wipe(Filters().activities)
	Log("category ->", list[index].id, list[index].name)
	DoSearch("category changed")
end


local SHOW_OPTIONS = { "auto", "groups", "players" }
local function StepShow(delta)
	local index = 1
	for i, value in ipairs(SHOW_OPTIONS) do
		if value == Filters().show then
			index = i
		end
	end
	index = (index - 1 + delta) % #SHOW_OPTIONS + 1
	Filters().show = SHOW_OPTIONS[index]
	Log("show ->", Filters().show)
	BuildResults()
end

local function ShowText()
	local show = Filters().show
	if show == "groups" then
		return "Groups"
	elseif show == "players" then
		return "Players"
	end
	return "Auto: " .. (ShowPlayers() and "Players" or "Groups")
end

local function ActivityText()
	local category = CurrentCategory()
	local picked = state.Picked(category and category.id)
	if #picked == 0 then
		return "All"
	elseif #picked == 1 then
		return ActivityName(picked[1])
	end
	return ActivityName(picked[1]) .. " +" .. (#picked - 1)
end

function FilterRowsList()
	local players = ShowPlayers()
	local filters = Filters()
	local wanted = players and filters.looking or filters.needs
	local rows = {
		{ kind = "cycle", label = "Show", picker = "show", value = ShowText, step = StepShow },
		{ kind = "cycle", label = "Category", value = function()
			local category = CurrentCategory()
			return category and category.name or "None"
		end, picker = "category", step = StepCategory },
		{ kind = "cycle", label = "Activity", picker = "activity", value = ActivityText },
		{ kind = "toggle", label = "Level-appropriate only", value = function() return not filters.allLevels end,
			toggle = function()
				filters.allLevels = not filters.allLevels or nil
				ClearCaches()
				-- Picked activities out of range now are dropped.
				local category = CurrentCategory()
				local kept = {}
				for _, id in ipairs(state.Picked(category and category.id)) do
					kept[id] = true
				end
				filters.activities = kept
				Log("level-appropriate only", filters.allLevels and "off" or "on")
				DoSearch("level filter changed")
			end },
		{ kind = "cycle", label = "Languages", picker = "languages", value = LanguageSummary },
		{ kind = "toggle", label = "Hide anyone rated Avoid", value = function() return filters.hideAvoided end,
			toggle = function()
				filters.hideAvoided = not filters.hideAvoided or nil
				Log("hide avoided", filters.hideAvoided and "on" or "off")
				BuildResults()
			end },
		{ kind = "header", label = players and "Players looking to fill" or "Groups that still need" },
	}
	for _, role in ipairs(ROLES) do
		rows[#rows + 1] = { kind = "toggle", role = role, label = ROLE_NAMES[role], value = function() return wanted[role] end,
			toggle = function()
				wanted[role] = not wanted[role] or nil
				Log(players and "looking" or "needs", role, wanted[role] and "on" or "off")
				BuildResults()
			end }
	end
	rows[#rows + 1] = { kind = "action", label = "Reset filters", run = function()
		ns.db.lfgFilter = nil
		Log("filters reset")
		DoSearch("filters reset")
	end }
	rows[#rows + 1] = { kind = "action", label = "Search", run = function() DoSearch("search row") end }
	return rows
end

local function GroupAction(entry)
	if not entry or entry.secret then
		return nil
	end
	if entry.solo then
		return "Invite"
	end
	if ns.db.lfgAsk == "chat" then
		return "Open Chat"
	elseif ns.db.lfgAsk == "off" then
		return nil
	end
	return state.asked[entry.leader] and "Ask again" or "Ask to join"
end

local function ActivateResult(entry)
	if not entry then
		return
	end
	if entry.secret then
		ns.Print("This listing is hidden right now. Try again out of combat.")
		return
	end
	if entry.solo then
		Invite(entry.leader)
	elseif ns.db.lfgAsk == "off" then
		Log("group picked, nothing done (Do nothing)")
	elseif ns.db.lfgAsk == "chat" then
		OpenChatWith(entry.leader, entry.class)
	elseif ns.db.lfgAsk ~= "send" then
		state.confirm = entry
		Log("confirm shown for", entry.leader)
	else
		AskToJoin(entry)
	end
end

---------------------------------------------------------------------------------------------------
-- Controller

local GAME_WINDOW_COMMAND = "CLICK GamepadXIVLfgFilterGameWindow:LeftButton"
local NAV_KEYS = {
	PADDUP = "Up", PADDDOWN = "Down", PADDLEFT = "Left", PADDRIGHT = "Right",
	PAD1 = "Accept", PAD2 = "Back", PAD3 = "Alt", PAD4 = "Extra",
	PADLSHOULDER = "PrevTab", PADRSHOULDER = "NextTab", PADRSTICK = "Phrases", PADLTRIGGER = "CloseChat", PADRTRIGGER = "Find",
}


-- Keeps a cursor in its list and scrolled into view.
local function Fit(cursorKey, scrollKey, count, visible)
	state[cursorKey .. "Count"] = count -- for the D-pad to go round (ns.StepWrap)
	state[cursorKey] = Clamp(state[cursorKey], 1, math.max(1, count))
	local scroll = state[scrollKey]
	if state[cursorKey] <= scroll then
		scroll = state[cursorKey] - 1
	elseif state[cursorKey] > scroll + visible then
		scroll = state[cursorKey] - visible
	end
	state[scrollKey] = Clamp(scroll, 0, math.max(0, count - visible))
end

local function MoveFilter(delta)
	local rows = FilterRowsList()
	local index = state.filterCursor
	for _ = 1, #rows do
		index = (index - 1 + delta) % #rows + 1
		if rows[index].kind ~= "header" then
			break
		end
	end
	state.filterCursor = index
end

-- The Listing tab's choices, saved per character.
local function ListForm()
	local form = ns.db.lfgListForm
	if type(form) ~= "table" then
		form = {}
		ns.db.lfgListForm = form
	end
	form.category = form.category or 0
	form.activities = form.activities or {}
	return form
end

-- Dropdowns over the filters: one choice for Show, Category and Activity, several for Languages.
local PICKER_TITLES = {
	show = "Show", category = "Category", activity = "Activity", languages = "Search in these languages",
	listCategory = "Category", listActivities = "Activities to list", groupRole = "Your role in the group",
	phrases = "Ready-made messages", notes = "Note", rateView = "Sort and filter",
}
-- "Note: Praise, Tank" over a section's or a subject's notes.
function state.NoteTitle(kind)
	local sectionIndex, groupIndex = tostring(kind):match("^notes:(%d+):?(%d*)$")
	local section = NOTE_PRESETS[tonumber(sectionIndex) or 0]
	local group = section and section.groups[tonumber(groupIndex) or 0]
	return section and ("Note: " .. section.name .. (group and (", " .. group.name) or "")) or nil
end
local MULTI_PICKERS = { languages = true, listActivities = true, activity = true } -- these tick several and stay open

local PickerItemsAll
-- The dropdown's items, narrowed to the ones matching what is typed in its search box.
local function PickerItems(kind)
	local items = PickerItemsAll(kind)
	local query = state.pickerQuery and strtrim(state.pickerQuery):lower() or ""
	if query == "" then
		return items
	end
	local kept = {}
	for _, item in ipairs(items) do
		if (item.search or item.text):lower():find(query, 1, true) then
			kept[#kept + 1] = item
		end
	end
	return kept
end

-- A shared LFG setting (ns.LFG_SETTINGS) from a "setting:<key>" dropdown.
local function SettingRow(kind)
	local key = type(kind) == "string" and kind:match("^setting:(.+)$")
	for _, row in ipairs(key and ns.LFG_SETTINGS or {}) do
		if row.key == key then
			return row
		end
	end
end

function PickerItemsAll(kind)
	local items = {}
	local filters = Filters()
	local setting = SettingRow(kind)
	local phraseGroup = type(kind) == "string" and tonumber(kind:match("^phrase:(%d+)$"))
	if kind == "rateView" then
		for _, key in ipairs(state.RATE_VIEW_ORDER) do
			local _, label = state.RateView(key)
			items[#items + 1] = { text = key .. ":  |cffffd100" .. label .. "|r  " .. DROPDOWN_ARROW, search = key, value = "<rateView>", key = key }
		end
		return items
	elseif type(kind) == "string" and kind:find("^rate:") then
		local key = kind:match("^rate:(%a+)$")
		local current = state.RateView(key)
		for _, choice in ipairs(state.RATE_VIEW[key] or {}) do
			items[#items + 1] = { text = choice[2], value = choice[1], checked = choice[1] == current }
		end
		return items
	end
	if kind == "notes" then
		local target = state.noteTarget
		local notes = target and state.NoteList(target.name) or {}
		local current = {}
		for _, note in ipairs(notes) do
			current[note] = true
		end
		items[#items + 1] = { text = "|cffffd100Add my own note...|r", search = "type", value = "<type>" }
		for _, note in ipairs(notes) do
			items[#items + 1] = { text = "|cffff7777Remove|r  " .. note, search = "remove " .. note, value = "<remove>", note = note }
		end
		if #notes > 1 then
			items[#items + 1] = { text = "|cffff7777Remove all notes|r", search = "remove all", value = "<remove all>" }
		end
		local searching = state.pickerQuery and strtrim(state.pickerQuery) ~= ""
		for index, section in ipairs(NOTE_PRESETS) do
			if searching then
				-- Searching from the top finds every note.
				for _, group in ipairs(section.groups) do
					for _, note in ipairs(group) do
						items[#items + 1] = { text = note .. "  |cff999999" .. group.name .. "|r", search = note, value = note, checked = current[note] }
					end
				end
			else
				items[#items + 1] = { text = section.name .. "  " .. DROPDOWN_ARROW, search = section.name, value = "<section>", section = index }
			end
		end
	elseif type(kind) == "string" and kind:find("^notes:") then
		-- "notes:1" a section's subjects, "notes:1:2" a subject's notes.
		local target = state.noteTarget
		local current = {}
		for _, note in ipairs(target and state.NoteList(target.name) or {}) do
			current[note] = true
		end
		local sectionIndex, groupIndex = kind:match("^notes:(%d+):?(%d*)$")
		local section = NOTE_PRESETS[tonumber(sectionIndex) or 0]
		local group = section and section.groups[tonumber(groupIndex) or 0]
		if group then
			for _, note in ipairs(group) do
				items[#items + 1] = { text = note, value = note, checked = current[note] }
			end
		elseif section then
			for index, subject in ipairs(section.groups) do
				local has = false
				for _, note in ipairs(subject) do
					has = has or current[note]
				end
				items[#items + 1] = { text = subject.name .. "  " .. DROPDOWN_ARROW, search = subject.name, value = "<group>",
					group = index, checked = has }
			end
		end
	elseif kind == "phrases" then
		for index, group in ipairs(PHRASES) do
			items[#items + 1] = { text = group.name .. "  |cff999999" .. #group .. "|r", search = group.name, value = index }
		end
	elseif phraseGroup and PHRASES[phraseGroup] then
		-- The one just added has a tick for a moment (state.Added).
		local added = state.Added(kind)
		for _, phrase in ipairs(PHRASES[phraseGroup]) do
			local text = phrase == "<ask>" and ((ns.LfgMessage and ns.LfgMessage({})) or "") .. "  |cff999999your message|r" or phrase
			items[#items + 1] = { text = text, search = phrase, value = phrase, checked = added and not added.failed and added.value == phrase }
		end
	elseif setting then
		for _, choice in ipairs(setting.choices()) do
			items[#items + 1] = { text = choice[2], value = choice[1], checked = ns.db[setting.key] == choice[1] }
		end
	elseif kind == "listCategory" then
		local form = ListForm()
		for _, category in ipairs(Categories()) do
			items[#items + 1] = { text = category.name, value = category.id, checked = form.category == category.id }
		end
	elseif kind == "listActivities" then
		local form = ListForm()
		for _, activity in ipairs(form.category ~= 0 and Activities(form.category) or {}) do
			items[#items + 1] = { text = activity.name, value = activity.id, checked = form.activities[activity.id] and true or false }
		end
	elseif kind == "groupRole" then
		local current = UnitGroupRolesAssigned and UnitGroupRolesAssigned("player")
		for _, role in ipairs(ROLES) do
			local key = ROLE_COUNT_KEY[role]
			items[#items + 1] = { text = ROLE_NAMES[role], value = key, checked = current == key }
		end
	elseif kind == "languages" then
		for _, language in ipairs(Languages()) do
			items[#items + 1] = { text = language.name .. (language.locked and "  |cff999999always|r" or ""), search = language.name, value = language.code,
				locked = language.locked, checked = language.locked or filters.languages[language.code] and true or false }
		end
	elseif kind == "show" then
		local auto = "Auto (" .. (IsInGroup() and "players while in a group" or "groups while on your own") .. ")"
		items[1] = { text = auto, value = "auto", checked = filters.show == "auto" }
		items[2] = { text = "Groups", value = "groups", checked = filters.show == "groups" }
		items[3] = { text = "Players looking for a group", value = "players", checked = filters.show == "players" }
	elseif kind == "category" then
		local current = CurrentCategory()
		for _, category in ipairs(Categories()) do
			items[#items + 1] = { text = category.name, value = category.id, checked = current and current.id == category.id }
		end
	elseif kind == "activity" then
		local category = CurrentCategory()
		local picked = state.Picked(category and category.id)
		items[1] = { text = "All", search = "all", value = 0, checked = #picked == 0 }
		for _, activity in ipairs(category and Activities(category.id) or {}) do
			items[#items + 1] = { text = activity.name, value = activity.id, checked = filters.activities[activity.id] and true or false }
		end
	end
	return items
end

local function OpenPicker(kind)
	state.picker = kind
	state.pickerQuery = nil
	if window and window.picker then
		window.picker.search:SetText("")
	end
	state.pickerCursor, state.pickerScroll = 1, 0
	state.languagesChanged = false
	for index, item in ipairs(PickerItems(kind)) do
		if item.checked and not MULTI_PICKERS[kind] then
			state.pickerCursor = index
		end
	end
	Log("dropdown opened:", kind)
end

local function ClosePicker()
	local kind = state.picker
	state.picker = nil
	state.pickerQuery = nil
	if window and window.picker then
		window.picker.search:ClearFocus()
		window.picker.search:SetText("")
	end
	Log("dropdown closed:", kind, "languages changed:", tostring(state.languagesChanged))
	if (kind == "languages" or kind == "activity") and state.languagesChanged then
		DoSearch(kind .. " changed")
	end
end

local function PickerAccept()
	local kind = state.picker
	local item = PickerItems(kind)[state.pickerCursor]
	if not item then
		return
	end
	local filters = Filters()
	if kind == "activity" then
		-- Ticks several; All clears them. The search runs when the list closes.
		if item.value == 0 then
			wipe(filters.activities)
		else
			filters.activities[item.value] = not filters.activities[item.value] or nil
		end
		state.languagesChanged = true
		Log("activity", item.value, item.value ~= 0 and tostring(filters.activities[item.value]) or "all")
		return
	elseif kind == "listActivities" then
		local form = ListForm()
		if not form.activities[item.value] then
			local count = 0
			for _ in pairs(form.activities) do
				count = count + 1
			end
			local max = Constants and Constants.LFGConstsExposed and Constants.LFGConstsExposed.GROUP_FINDER_MAX_ACTIVITY_CAPACITY
			if max and count >= max then
				ns.Print("You can list for at most " .. max .. " activities.")
				return
			end
		end
		form.activities[item.value] = not form.activities[item.value] or nil
		Log("list activity", item.value, form.activities[item.value] and "on" or "off")
		return
	elseif kind == "languages" then
		if item.locked then
			ns.Print("This language is always searched.")
			return
		end
		filters.languages[item.value] = not filters.languages[item.value] or nil
		state.languagesChanged = true
		Log("language", item.value, filters.languages[item.value] and "on" or "off")
		return
	end
	if kind == "phrases" then
		Log("message category", item.value)
		OpenPicker("phrase:" .. item.value)
		return
	elseif type(kind) == "string" and kind:find("^phrase:") then
		-- Into the message being typed; the list stays open for the next one, {PAD2} goes back.
		local name = SelectedChat()
		if name then
			local ok = state.AddToMessage(ReplyText(item.value, name), "message menu")
			state.added = { kind = kind, value = item.value, at = GetTime(), failed = not ok }
			if C_Timer and C_Timer.After then
				C_Timer.After(1.55, Refresh) -- the "Added" goes again
			end
		end
		return
	end
	if item.value == "<rateView>" then
		OpenPicker("rate:" .. item.key)
		return
	elseif kind:find("^rate:") then
		local key = kind:match("^rate:(%a+)$")
		ns.db["lfgRate" .. key] = item.value
		state.rateCursor, state.rateScroll = 1, 0
		Log("ratings", key, item.value)
		OpenPicker("rateView")
		return
	elseif item.value == "<section>" then
		OpenPicker("notes:" .. item.section)
		return
	elseif item.value == "<group>" then
		OpenPicker(kind .. ":" .. item.group)
		return
	end
	if kind == "notes" or kind:find("^notes:") then
		-- Notes tick on and off, and the list stays open for more; typing one closes it.
		local target = state.noteTarget
		if not target then
			ClosePicker()
		elseif item.value == "<type>" then
			ClosePicker()
			window.noteInput.target = target
			window.noteInput:SetText("")
			window.noteInput:Show()
			window.noteInput:SetFocus()
		elseif item.value == "<remove all>" then
			SetNote(target.name, "", target.class)
			Log("notes removed for", target.name)
		else
			local note = item.note or item.value
			state.ToggleNote(target, note, item.value ~= "<remove>" and not item.checked)
			Log("note", item.checked and "off" or "on", "for", target.name, note)
		end
		state.pickerCursor = Clamp(state.pickerCursor, 1, math.max(1, #PickerItems(state.picker or kind)))
		return
	end
	ClosePicker()
	Log("picked", kind, item.value)
	local setting = SettingRow(kind)
	if setting then
		ns.db[setting.key] = item.value
		if setting.onChange then
			setting.onChange()
		end
	elseif kind == "listCategory" then
		local form = ListForm()
		if form.category ~= item.value then
			form.category = item.value
			wipe(form.activities)
		end
	elseif kind == "groupRole" then
		ns.Trail("lfg filter: UnitSetRole")
		local ok, err = pcall(UnitSetRole, "player", item.value)
		Log("group role", item.value, ok and "set" or ("failed: " .. tostring(err)))
	elseif kind == "show" then
		filters.show = item.value
		BuildResults()
	elseif kind == "category" then
		if filters.category ~= item.value then
			filters.category = item.value
			wipe(filters.activities)
			DoSearch("category picked")
		end
	end
end

local Nav = {}

-- {PADLTRIGGER} in Chat: closes a whisper conversation (it goes to History), or in History deletes it.
function Nav.CloseChat()
	if state.tab == TAB_RATINGS then
		OpenPicker("rateView") -- {PADLTRIGGER} on Ratings: sort and filter
		return
	end
	if state.tab ~= TAB_CHAT then
		return
	end
	local name, chat = SelectedChat()
	if name and ChannelInfo(name) and ChannelInfo(name).archived then
		ns.ChatHistory.Remove(name) -- a past group's chat
		return
	end
	if not name or ChannelInfo(name) then
		return
	end
	if state.chatHistory then
		Chats()[name] = nil
		Log("chat deleted", name)
	else
		chat.closed = true
		chat.opened = nil
		Log("chat closed", name)
	end
end

-- {PADLSTICK} while typing in Chat (Bind gives it the key only then): the quick reply goes into the
-- message at the cursor.
function Nav.AddReply()
	local name = state.tab == TAB_CHAT and not state.picker and not state.membersFor and SelectedChat()
	if name and not (ChannelInfo(name) or {}).readOnly then
		state.AddToMessage(ReplyText(state.replyIndex, name), "quick reply " .. state.replyIndex)
	end
end

-- {PADRSTICK} in Chat: the message menu, categories first.
function Nav.Phrases()
	local name = state.tab == TAB_CHAT and SelectedChat()
	if name and not (ChannelInfo(name) or {}).readOnly then
		OpenPicker("phrases")
	end
end

-- An empty list can't hold the cursor, so it stays in the filters until there are results.
local function FixFocus()
	if state.tab == TAB_FINDER and state.focus == "list" and #state.results == 0 then
		state.focus = "filters"
	end
end

function Nav.Up()
	if state.confirm then
		state.confirm = nil
	end
	if state.tab == TAB_FINDER then
		if state.picker then
			state.pickerCursor = ns.StepWrap(state.pickerCursor, -1, #PickerItems(state.picker))
		elseif state.focus == "filters" then
			MoveFilter(-1)
		else
			state.listCursor = ns.StepWrap(state.listCursor, -1, state.listCursorCount)
		end
	elseif state.tab == TAB_CHAT then
		state.selectedName = nil
		state.chatCursor = ns.StepWrap(state.chatCursor, -1, state.chatCursorCount)
	else
		state.rateCursor = ns.StepWrap(state.rateCursor, -1, state.rateCursorCount)
	end
end

function Nav.Down()
	if state.confirm then
		state.confirm = nil
	end
	if state.tab == TAB_FINDER then
		if state.picker then
			state.pickerCursor = ns.StepWrap(state.pickerCursor, 1, #PickerItems(state.picker))
		elseif state.focus == "filters" then
			MoveFilter(1)
		else
			state.listCursor = ns.StepWrap(state.listCursor, 1, state.listCursorCount)
		end
	elseif state.tab == TAB_CHAT then
		state.selectedName = nil
		state.chatCursor = ns.StepWrap(state.chatCursor, 1, state.chatCursorCount)
	else
		state.rateCursor = ns.StepWrap(state.rateCursor, 1, state.rateCursorCount)
	end
end

local RateRows

local function StepSide(delta)
	if state.tab == TAB_FINDER then
		if state.picker then
			return
		end
		if state.focus == "filters" then
			local row = FilterRowsList()[state.filterCursor]
			-- Right goes to the list from any filter; Cross opens or ticks one.
			if delta > 0 and #state.results > 0 then
				state.focus = "list"
			end
		elseif delta > 0 then
			local entry = state.results[state.listCursor]
			if entry and entry.leader then
				OpenChatWith(entry.leader, entry.class)
			end
		else
			state.focus = "filters"
		end
	elseif state.tab == TAB_CHAT then
		state.replyIndex = (state.replyIndex - 1 + delta) % #QUICK_REPLIES + 1
		ns.db.lfgFilterReply = state.replyIndex
	else
		local row = RateRows()[state.rateCursor]
		if row then
			local rating = Clamp(RatingOf(row.name) + delta, 0, 3)
			SetRating(row.name, rating, row.class)
			Log("rated", row.name, rating)
		end
	end
end

function Nav.Left()
	StepSide(-1)
end

function Nav.Right()
	StepSide(1)
end

function Nav.Accept()
	if state.tab == TAB_FINDER then
		if state.confirm then
			local entry = state.confirm
			state.confirm = nil
			AskToJoin(entry)
		elseif state.picker then
			PickerAccept()
		elseif state.focus == "filters" then
			local row = FilterRowsList()[state.filterCursor]
			if not row then
				return
			elseif row.kind == "cycle" then
				OpenPicker(row.picker)
			elseif row.kind == "toggle" then
				row.toggle()
			elseif row.kind == "action" then
				row.run()
			end
		else
			ActivateResult(state.results[state.listCursor])
		end
	elseif state.tab == TAB_CHAT then
		local name, _, _, special = SelectedChat()
		if special then
			state.chatHistory = special == "history" or nil
			state.selectedName = nil
			state.chatCursor, state.chatScroll = 1, 0
			Log(state.chatHistory and "chat history opened" or "back to chats")
		elseif not name or (ChannelInfo(name) or {}).readOnly then
			return -- nothing can be sent here; a message being typed stays
		elseif strtrim(window.input:GetText() or "") ~= "" then
			window.input:Submit() -- the message typed, as Enter sends it
		else
			-- Nothing typed: the quick reply goes in, to send with {PAD1} again.
			state.AddToMessage(ReplyText(state.replyIndex, name), "quick reply " .. state.replyIndex)
		end
	else
		local row = RateRows()[state.rateCursor]
		if row then
			OpenChatWith(row.name, row.class)
		end
	end
end

function Nav.Back()
	if state.confirm then
		state.confirm = nil
		Log("confirm cancelled")
	elseif window.input:HasFocus() then
		window.input:ClearFocus()
	elseif window.noteInput:HasFocus() then
		window.noteInput:ClearFocus()
	elseif window.picker.search:HasFocus() then
		window.picker.search:ClearFocus()
	elseif state.picker then
		ClosePicker()
	elseif state.tab == TAB_FINDER and state.focus == "filters" and #state.results > 0 then
		state.focus = "list"
	else
		window:Hide()
	end
end

-- Square: filters on the Groups tab, typing on the Chat tab, clearing a rating.
function Nav.Alt()
	state.confirm = nil
	if state.tab == TAB_FINDER then
		if state.picker then
			window.picker.search:SetFocus()
			Log("dropdown search focused")
			return
		end
		state.focus = state.focus == "filters" and "list" or "filters"
	elseif state.tab == TAB_CHAT then
		local name = SelectedChat()
		if window.input:HasFocus() then
			-- While typing, Square erases, as in the chat box.
			if ns.ChatErase then
				ns.ChatErase(window.input)
			end
		elseif name and not (ChannelInfo(name) or {}).readOnly then
			window.input:SetFocus()
			Log("typing started")
		end
	else
		local row = RateRows()[state.rateCursor]
		if row then
			SetRating(row.name, 0, row.class)
			Log("rating cleared", row.name)
		end
	end
end

-- Triangle: search on the Groups tab, invite on the Chat tab (on a past group: its members).
function Nav.Extra()
	state.confirm = nil
	if state.tab == TAB_FINDER then
		if state.picker then
			ClosePicker()
		else
			DoSearch("search button")
		end
	elseif state.tab == TAB_CHAT then
		local name, chat = SelectedChat()
		if name and ChannelInfo(name) and ChannelInfo(name).archived and #(chat.members or {}) > 0 then
			state.membersFor, state.memberCursor, state.memberScroll = name, 1, 0
			Log("past group members shown", name)
		elseif name and not ChannelInfo(name) then
			Invite(name)
		end
	elseif state.tab == TAB_RATINGS then
		local row = RateRows()[state.rateCursor]
		if row then
			state.noteTarget = row
			OpenPicker("notes")
		end
	end
end

local function SelectTab(index)
	state.confirm = nil
	if state.picker then
		ClosePicker()
	end
	state.tab = (index - 1) % #TAB_NAMES + 1
	ns.db.lfgFilterTab = TAB_KEYS[state.tab]
	Log("tab", state.tab)
end

---------------------------------------------------------------------------------------------------
-- Listing tab: lists your group, or you on your own so groups can invite you.

-- "List group" / "List me", or "Update listing" when listed.
function state.ListLabel()
	if C_LFGList.HasActiveEntryInfo() then
		return "Update listing"
	end
	return IsInGroup() and "List group" or "List me"
end

local function CanEditListing()
	return not IsInGroup() or UnitIsGroupLeader("player")
end

local function CanRoleCheck()
	return IsInGroup() and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player"))
end

-- Just after a change the game can still return the old roles for a moment: the new ones show
-- right away (SetMyRole keeps them for a second).
local function MyRoles()
	if state.myRoles and GetTime() < state.myRolesUntil then
		return state.myRoles
	end
	local roles = Call("C_LFGListRoles.GetRoles", C_LFGListRoles and C_LFGListRoles.GetRoles)
	return type(roles) == "table" and roles or {}
end

local function SetMyRole(role)
	local roles = MyRoles()
	local new = { tank = roles.tank and true or false, healer = roles.healer and true or false, dps = roles.dps and true or false }
	new[role] = not new[role]
	if not (C_LFGListRoles and C_LFGListRoles.SetRoles) then
		Log("my roles: C_LFGListRoles.SetRoles missing")
		return
	end
	ns.Trail("lfg filter: C_LFGListRoles.SetRoles")
	local ok, result = pcall(C_LFGListRoles.SetRoles, new)
	Log("my roles", "tank", tostring(new.tank), "healer", tostring(new.healer), "dps", tostring(new.dps), ok and ("ok " .. tostring(result)) or ("failed: " .. tostring(result)))
	if ok then
		state.myRoles, state.myRolesUntil = new, GetTime() + 1
		C_Timer.After(1.1, ns.RefreshLfgFilter)
	end
end

local function ListedActivities(form)
	local ids = {}
	for _, activity in ipairs(form.category ~= 0 and Activities(form.category) or {}) do
		if form.activities[activity.id] then
			ids[#ids + 1] = activity.id
		end
	end
	return ids
end

local function ListActivitiesText()
	local form = ListForm()
	local ids = ListedActivities(form)
	if #ids == 0 then
		return "|cff999999Pick at least one|r"
	elseif #ids == 1 then
		return ActivityName(ids[1])
	end
	return ActivityName(ids[1]) .. " +" .. (#ids - 1)
end

local function ListCategoryText()
	local form = ListForm()
	for _, category in ipairs(Categories()) do
		if category.id == form.category then
			return category.name
		end
	end
	return "|cff999999Pick one|r"
end

-- Lists the group, or updates the listing, then shows the Group finder searching for it.
local function PostListing()
	if not CanEditListing() then
		ns.Print("Only the group leader can list the group.")
		Log("list refused: not the leader")
		return
	end
	local form = ListForm()
	local ids = ListedActivities(form)
	if #ids == 0 then
		ns.Print("Pick a category and at least one activity first.")
		return
	end
	if not IsInGroup() then
		-- On your own, groups look for you by role.
		local roles = MyRoles()
		if not (roles.tank or roles.healer or roles.dps) then
			ns.Print("Pick at least one of your roles first, so groups know what you can do.")
			return
		end
	end
	if IsInGroup() then
		local count = GetNumGroupMembers()
		for _, id in ipairs(ids) do
			local info = Call("GetActivityInfoTable", C_LFGList.GetActivityInfoTable, id)
			local max = info and Plain(info.maxNumPlayers, 0) or 0
			if max ~= 0 and max <= count then
				ns.Print("Your group is already full for " .. ActivityName(id) .. ".")
				Log("list refused: group full for", id)
				return
			end
		end
	end
	local data = { activityIDs = ids, newPlayerFriendly = form.newPlayers and true or false }
	local update = C_LFGList.HasActiveEntryInfo()
	ns.Trail(update and "lfg filter: C_LFGList.UpdateListing" or "lfg filter: C_LFGList.CreateListing")
	local ok, result = pcall(update and C_LFGList.UpdateListing or C_LFGList.CreateListing, data)
	Log(update and "update listing" or "create listing", #ids, "activities", ok and ("returned " .. tostring(result)) or ("failed: " .. tostring(result)))
	if not ok or result == false then
		ns.Print((IsInGroup() and "The group" or "You") .. " could not be listed. See /gxiv lfgfilterlog.")
		return
	end
	if not IsInGroup() and not update then
		ns.Print("You are listed: groups looking for players can see you and invite you.")
	end
	-- Search the listed activities in the Group finder once the listing is up.
	local filters = Filters()
	filters.category = form.category
	filters.activities = {}
	for _, id in ipairs(ids) do
		filters.activities[id] = true
	end
	state.listingPending = true
	SelectTab(TAB_FINDER)
	C_Timer.After(3, function()
		if state.listingPending then
			state.listingPending = nil
			Log("no listing update after 3 s, searching anyway")
			DoSearch("after listing (timeout)")
		end
	end)
end

local function RemoveListing()
	ns.Trail("lfg filter: C_LFGList.RemoveListing")
	local ok, err = pcall(C_LFGList.RemoveListing)
	Log("remove listing", ok and "ok" or ("failed: " .. tostring(err)))
end

local function RoleCheck()
	if not CanRoleCheck() then
		ns.Print("Only the group leader or an assistant can start a role check.")
		return
	end
	ns.Trail("lfg filter: InitiateRolePoll")
	local ok, err = pcall(InitiateRolePoll)
	Log("role check", ok and "started" or ("failed: " .. tostring(err)))
end

local function ListRowsList()
	local form = ListForm()
	local roles = MyRoles()
	local listed = C_LFGList.HasActiveEntryInfo()
	local rows = { { kind = "header", label = "Your roles", note = "for listing and signing up" } }
	for _, role in ipairs(ROLES) do
		rows[#rows + 1] = { kind = "toggle", role = role, label = ROLE_NAMES[role], value = function() return roles[role] end,
			toggle = function() SetMyRole(role) end }
	end
	rows[#rows + 1] = { kind = "header", label = IsInGroup() and "Your group's listing" or "Your listing",
		note = listed and "|cff55ee55listed|r" or (IsInGroup() and "not listed" or "groups can invite you") }
	rows[#rows + 1] = { kind = "cycle", label = "Category", picker = "listCategory", value = ListCategoryText }
	rows[#rows + 1] = { kind = "cycle", label = "Activities", picker = "listActivities", value = ListActivitiesText }
	rows[#rows + 1] = { kind = "toggle", label = "New player friendly", value = function() return form.newPlayers end,
		toggle = function() form.newPlayers = not form.newPlayers or nil end }
	rows[#rows + 1] = { kind = "action", label = state.ListLabel(), run = PostListing }
	if listed then
		rows[#rows + 1] = { kind = "action", label = "Remove listing", run = RemoveListing }
	end
	if IsInGroup() then
		rows[#rows + 1] = { kind = "header", label = "Party" }
		rows[#rows + 1] = { kind = "cycle", label = "Your role", picker = "groupRole", value = function()
			local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned("player")
			for _, key in ipairs(ROLES) do
				if ROLE_COUNT_KEY[key] == role then
					return ROLE_NAMES[key]
				end
			end
			return "|cff999999None|r"
		end }
		rows[#rows + 1] = { kind = "action", label = "Role check for the party", run = RoleCheck }
	end
	return rows
end

local function MoveListRow(delta)
	local rows = ListRowsList()
	local index = state.createCursor or 1
	for _ = 1, #rows do
		index = (index - 1 + delta) % #rows + 1
		if rows[index].kind ~= "header" then
			break
		end
	end
	state.createCursor = index
end

local ListNav = {}
function ListNav.Up() MoveListRow(-1) end
function ListNav.Down() MoveListRow(1) end
function ListNav.Left() end
function ListNav.Right() end
function ListNav.Accept()
	local row = ListRowsList()[state.createCursor or 1]
	if not row then
		return
	elseif row.kind == "cycle" then
		OpenPicker(row.picker)
	elseif row.kind == "toggle" then
		row.toggle()
	elseif row.kind == "action" then
		row.run()
	end
end
function ListNav.Back() window:Hide() end
function ListNav.Alt() end
function ListNav.Phrases() end
function ListNav.CloseChat() end
function ListNav.Extra() PostListing() end

---------------------------------------------------------------------------------------------------
-- Settings tab: the LFG settings, the same as in the addon's settings (LFG tab).

local function SettingsRowsList()
	local rows = {
		{ kind = "action", label = "Group finder message", value = function() return ns.db.lfgMessage or "" end, message = true,
			tip = "The whisper {PAD1} sends to a group's leader. Filled in when sent: <level>, <class>, <name> (yours), <leader>, <activity> and <roles>. Press {PAD1} to type it; a keyboard or the on-screen keyboard is needed." },
	}
	for _, setting in ipairs(ns.LFG_SETTINGS) do
		if setting.type == "check" then
			rows[#rows + 1] = { kind = "toggle", label = setting.label, tip = setting.tip,
				value = function() return ns.db[setting.key] end,
				toggle = function()
					ns.db[setting.key] = not ns.db[setting.key]
					Log("setting", setting.key, tostring(ns.db[setting.key]))
					if setting.onChange then
						setting.onChange()
					end
				end }
		elseif setting.type == "choice" then
			rows[#rows + 1] = { kind = "cycle", label = setting.label, tip = setting.tip, picker = "setting:" .. setting.key,
				value = function()
					for _, choice in ipairs(setting.choices()) do
						if choice[1] == ns.db[setting.key] then
							return choice[2]
						end
					end
					return tostring(ns.db[setting.key])
				end,
				step = function(delta)
					local choices = setting.choices()
					local index = 1
					for i, choice in ipairs(choices) do
						if choice[1] == ns.db[setting.key] then
							index = i
						end
					end
					ns.db[setting.key] = choices[(index - 1 + delta) % #choices + 1][1]
					Log("setting", setting.key, tostring(ns.db[setting.key]))
					if setting.onChange then
						setting.onChange()
					end
				end }
		end
	end
	return rows
end

local SettingsNav = {}
function SettingsNav.Up()
	if window.settingsInput:HasFocus() then
		return
	end
	state.settingsCursor = ns.StepWrap(state.settingsCursor, -1, #SettingsRowsList())
end
function SettingsNav.Down()
	if window.settingsInput:HasFocus() then
		return
	end
	state.settingsCursor = ns.StepWrap(state.settingsCursor, 1, #SettingsRowsList())
end
local function StepSetting(delta)
	if window.settingsInput:HasFocus() then
		SettingsNav.tag = (SettingsNav.tag - 1 + delta) % #SettingsNav.tags + 1
		return
	end
	local row = SettingsRowsList()[state.settingsCursor or 1]
	if row and row.kind == "cycle" then
		row.step(delta)
	elseif row and row.kind == "toggle" then
		row.toggle()
	end
end
function SettingsNav.Left() StepSetting(-1) end
function SettingsNav.Right() StepSetting(1) end

-- Holding the D-pad repeats a direction while it works on the same thing (ns.RepeatOnHold): up / down
-- everywhere; left / right only for the quick reply, a rating and the message's tag. Elsewhere they
-- flip a setting back and forth, move between the filters and the list, open a chat or search.
local function HoldContext(name)
	if not window:IsShown() or state.confirm then
		return false
	end
	local where = state.tab .. ":" .. tostring(state.picker) .. ":" .. tostring(state.focus)
	if name == "Left" or name == "Right" then
		local typing = state.tab == TAB_SETTINGS and window.settingsInput:HasFocus()
		if state.picker or not (state.tab == TAB_CHAT or state.tab == TAB_RATINGS or typing) then
			return false
		end
	end
	return where
end
local HOLD_NAV = { Up = true, Down = true, Left = true, Right = true }
function SettingsNav.Accept()
	if window.settingsInput:HasFocus() then
		return -- Enter saves while typing
	end
	local row = SettingsRowsList()[state.settingsCursor or 1]
	if not row then
		return
	elseif row.message then
		window.settingsInput:SetText(ns.db.lfgMessage or "")
		window.settingsInput:SetFocus()
		window.settingsInput:SetCursorPosition(#(ns.db.lfgMessage or ""))
		Log("editing the group finder message")
	elseif row.kind == "cycle" then
		OpenPicker(row.picker)
	elseif row.kind == "toggle" then
		row.toggle()
	end
end
function SettingsNav.Back()
	if window.settingsInput:HasFocus() then
		window.settingsInput.cancelled = true
		window.settingsInput:ClearFocus()
	else
		window:Hide()
	end
end
-- While typing the message, {PADDLEFT} / {PADDRIGHT} pick a tag and {PAD3} puts it in at the cursor.
-- Otherwise {PAD3} on the message puts the default back.
SettingsNav.tags = { "<activity>", "<level>", "<class>", "<roles>", "<name>", "<leader>" }
SettingsNav.tag = 1
function SettingsNav.Alt()
	local input = window.settingsInput
	if input:HasFocus() then
		input:Insert(SettingsNav.tags[SettingsNav.tag])
		return
	end
	local row = SettingsRowsList()[state.settingsCursor or 1]
	if row and row.message and ns.DEFAULTS and ns.DEFAULTS.lfgMessage then
		ns.db.lfgMessage = ns.DEFAULTS.lfgMessage
		Log("group finder message reset")
	end
end
function SettingsNav.Phrases() end
function SettingsNav.CloseChat() end
function SettingsNav.Extra() end

-- While a dropdown is open, the controller works only it.
local PickerNav = {}
function PickerNav.Up()
	state.pickerCursor = ns.StepWrap(state.pickerCursor, -1, #PickerItems(state.picker))
end
function PickerNav.Down()
	state.pickerCursor = ns.StepWrap(state.pickerCursor, 1, #PickerItems(state.picker))
end
function PickerNav.Left() end
function PickerNav.Right() end
function PickerNav.Accept() PickerAccept() end
function PickerNav.Back()
	if window.picker.search:HasFocus() then
		window.picker.search:ClearFocus()
	elseif state.picker:find("^phrase:") then
		OpenPicker("phrases") -- back to the categories
	elseif state.picker:find("^notes:") then
		OpenPicker(state.picker:match("^(.+):%d+$")) -- up a level
	elseif state.picker:find("^rate:") then
		OpenPicker("rateView")
	else
		ClosePicker()
		state.BackToTyping()
	end
end
function PickerNav.Alt()
	window.picker.search:SetFocus()
	Log("dropdown search focused")
end
function PickerNav.Extra() ClosePicker() end
function PickerNav.Phrases()
	ClosePicker()
	state.BackToTyping()
end
-- Out of the message lists with a message being typed (the search box may have had the cursor): back
-- to typing it.
function state.BackToTyping()
	if state.tab == TAB_CHAT and window.input:IsShown() and strtrim(window.input:GetText() or "") ~= "" then
		window.input:SetFocus()
	end
end
function PickerNav.CloseChat() end

-- A past group's members, opened with {PAD4} on the group in Chat: {PAD1} whispers one, {PAD2} or
-- {PAD4} closes the list. Kept in state: the file is near Lua's 200 locals.
state.MembersNav = {
	Up = function() state.memberCursor = ns.StepWrap(state.memberCursor, -1, state.memberCursorCount) end,
	Down = function() state.memberCursor = ns.StepWrap(state.memberCursor, 1, state.memberCursorCount) end,
	Accept = function()
		local _, group = SelectedChat()
		local member = group and group.members and group.members[state.memberCursor]
		if member and not member.me then
			Log("whisper from a past group's members", member.name)
			OpenChatWith(member.name, member.class)
		end
	end,
	Back = function() state.membersFor = nil end,
	Left = function() end, Right = function() end, Alt = function() end, Phrases = function() end, CloseChat = function() end,
}
state.MembersNav.Extra = state.MembersNav.Back

-- {PADRTRIGGER}: the search box, on the tabs that have one.
state.FIND_TABS = { [TAB_FINDER] = true, [TAB_CHAT] = true, [TAB_RATINGS] = true }
function Nav.Find()
	if state.FIND_TABS[state.tab] and not state.picker and window.findBox then
		window.findBox:SetFocus()
		Log("search box focused")
	end
end

function Nav.PrevTab()
	if state.chatMode then
		state.SelectChatTab(state.chatTab - 1)
	else
		SelectTab(state.tab - 1)
	end
end

function Nav.NextTab()
	if state.chatMode then
		state.SelectChatTab(state.chatTab + 1)
	else
		SelectTab(state.tab + 1)
	end
end

local boundKeys = {}
local Unbind

-- A game window that needs the controller over this one: the party role check, a popup, an invite.
local function GamePopupOpen()
	if RolePollPopup and RolePollPopup:IsShown() then
		return "role check"
	end
	if LFGInvitePopup and LFGInvitePopup:IsShown() then
		return "invite"
	end
	if GamepadPopupHandler and GamepadPopupHandler.IsStaticPopupShowing and GamepadPopupHandler:IsStaticPopupShowing() then
		return "popup"
	end
	-- Loot rolls, invites, ready checks and the game's other popups (Input.lua's list for Back).
	for _, name in ipairs(ns.BACK_POPUPS or {}) do
		local frame = _G[name]
		if frame and frame.IsVisible and frame:IsVisible() then
			return name
		end
	end
	-- A group invite, whatever its window is called in this client (Input.lua).
	if ns.InvitePending and ns.InvitePending() then
		return "group invite"
	end
end

-- Forever's menu navigation has the controller: it binds the buttons to its own
-- InputFunctionBindingButton_ keys while one of its windows (the role check, a popup, a menu) has focus.
local function ForeverHasController()
	for _, key in ipairs({ "PAD1", "PAD2", "PADDUP", "PADDDOWN" }) do
		local action = GetBindingAction(key, true)
		if type(action) == "string" and action:find("InputFunctionBindingButton_", 1, true) then
			return key .. " " .. action
		end
	end
end

local function Bind(reason)
	if InCombatLockdown() or not window then
		return
	end
	-- A game window that takes the controller keeps it until it closes; then this window takes it back.
	-- Forever's navigation can be taken back with {PADBACK} (state.forced, until the window closes);
	-- the game's popups (a loot roll, an invite) keep the controller until they close.
	local gamePopup = GamePopupOpen()
	-- Under the game's popups (an invite, a role check) while one is open, so it never covers them.
	local strata = gamePopup and "HIGH" or "DIALOG"
	if window:GetFrameStrata() ~= strata then
		window:SetFrameStrata(strata)
	end
	local forever = not gamePopup and not state.forced and ForeverHasController()
	local popup = gamePopup or forever
	if popup then
		if next(boundKeys) or not state.yielded then
			Log("controller left to the game:", popup)
			if next(boundKeys) then
				Unbind("game window has the controller")
			end
		end
		state.yielded = true
		state.canTakeBack = forever and true or nil
		local takeBack = "CLICK GamepadXIVLfgFilterTakeBack:LeftButton"
		if forever and GetBindingAction("PADBACK", true) ~= takeBack then
			SetOverrideBindingClick(window, true, "PADBACK", "GamepadXIVLfgFilterTakeBack", "LeftButton")
		elseif not forever and GetBindingAction("PADBACK", true) == takeBack then
			SetOverrideBinding(window, true, "PADBACK", nil)
		end
		return
	end
	if GetBindingAction("PADBACK", true) == "CLICK GamepadXIVLfgFilterTakeBack:LeftButton" then
		SetOverrideBinding(window, true, "PADBACK", nil)
	end
	state.canTakeBack = nil
	if state.yielded then
		state.yielded = nil
		Log("controller back to LFG Filter")
	end
	if state.tab == TAB_CHAT and window.input and window.input:HasFocus() then
		-- Typing a message: {PADLSTICK} adds the quick reply (Nav.AddReply).
		if GetBindingAction("PADLSTICK", true) ~= "CLICK GamepadXIVLfgFilterNavAddReply:LeftButton" then
			SetOverrideBindingClick(window, true, "PADLSTICK", "GamepadXIVLfgFilterNavAddReply", "LeftButton")
		end
	elseif state.chatMode then
		-- The game's own Open Chat binding: its chat box shows while you type (see the chat section below).
		if GetBindingAction("PADLSTICK", true) ~= "OPENCHAT" then
			SetOverrideBinding(window, true, "PADLSTICK", "OPENCHAT")
		end
	elseif window.gameButton and GetBindingAction("PADLSTICK", true) ~= GAME_WINDOW_COMMAND then
		SetOverrideBindingClick(window, true, "PADLSTICK", "GamepadXIVLfgFilterGameWindow", "LeftButton")
	elseif not window.gameButton and GetBindingAction("PADLSTICK", true) == "CLICK GamepadXIVLfgFilterNavAddReply:LeftButton" then
		SetOverrideBinding(window, true, "PADLSTICK", nil)
	end
	for key, name in pairs(NAV_KEYS) do
		local command = "CLICK GamepadXIVLfgFilterNav" .. name .. ":LeftButton"
		if GetBindingAction(key, true) ~= command then
			if boundKeys[key] then
				Log("binding taken back:", key, "was", GetBindingAction(key, true), reason)
			end
			SetOverrideBindingClick(window, true, key, "GamepadXIVLfgFilterNav" .. name, "LeftButton")
			boundKeys[key] = true
		end
	end
end

function Unbind(reason)
	if InCombatLockdown() then
		Log("unbind waits for combat to end:", reason)
		state.unbindPending = true
		return
	end
	state.unbindPending = nil
	ClearOverrideBindings(window)
	wipe(boundKeys)
	Log("bindings cleared:", reason)
end

---------------------------------------------------------------------------------------------------
-- Ratings tab

function RateRows()
	local rows, seen = {}, {}
	for _, member in ipairs(Recent()) do
		if member.name and not seen[member.name] then
			seen[member.name] = true
			rows[#rows + 1] = { name = member.name, class = member.class, where = member.where, t = member.t }
		end
	end
	local rated = {}
	for name, rating in pairs(Ratings()) do
		if not seen[name] then
			rated[#rated + 1] = { name = name, class = rating.c, t = rating.t, where = "Rated earlier" }
		end
	end
	table.sort(rated, function(a, b) return a.name < b.name end)
	for _, row in ipairs(rated) do
		rows[#rows + 1] = row
	end
	-- What is typed in the search box (the name, where you met, your note), and the Show and Role filters.
	local query = state.FindText(TAB_RATINGS)
	local show, role = state.RateView("Show"), state.RateView("Role")
	local shown = {}
	for _, row in ipairs(rows) do
		local rating = RatingOf(row.name)
		local keep = not query or state.Found(query, row.name, row.where, NoteOf(row.name))
		if show == "none" then
			keep = keep and rating == 0
		elseif show == "notes" then
			keep = keep and NoteOf(row.name) ~= nil
		elseif show ~= "all" then
			keep = keep and rating == tonumber(show)
		end
		if role ~= "any" then
			keep = keep and ns.LfgRoleIcons(row.name) ~= "" and ns.LfgHadRole(row.name, role)
		end
		if keep then
			row.order = #shown
			shown[#shown + 1] = row
		end
	end
	local sort = state.RateView("Sort")
	local RATING_ORDER = { [3] = 0, [2] = 1, [0] = 2, [1] = 3 }
	if sort ~= "recent" then
		table.sort(shown, function(a, b)
			local x, y
			if sort == "name" then
				x, y = Short(a.name):lower(), Short(b.name):lower()
			elseif sort == "dungeons" then
				x, y = -ns.LfgDungeonCount(a.name), -ns.LfgDungeonCount(b.name)
			else
				x, y = RATING_ORDER[RatingOf(a.name)] or 2, RATING_ORDER[RatingOf(b.name)] or 2
			end
			if x ~= y then
				return x < y
			end
			return a.order < b.order
		end)
	end
	return shown
end

---------------------------------------------------------------------------------------------------
-- Drawing

local function Hint(text)
	return ns.ButtonText(text, 18)
end

local function DrawTabs()
	local unread = UnreadTotal()
	-- The Chat window is this window with only the chat.
	window.titleText:SetText(state.chatMode and "Chat" or "LFG Filter")
	for _, tab in ipairs(window.tabs) do
		tab:SetShown(not state.chatMode)
	end
	-- The Chat window has its own tabs in the same row.
	for index, tab in ipairs(window.chatTabs) do
		local selected = index == state.chatTab
		tab:SetShown(state.chatMode)
		SetRowSelected(tab, selected)
		tab.label:SetTextColor(selected and GOLD[1] or 0.8, selected and GOLD[2] or 0.8, selected and GOLD[3] or 0.8)
		tab.badge:SetCount(state.chatMode and state.ChatTabUnread(state.chatTabs[index]) or 0)
	end
	window.tabRight:ClearAllPoints()
	local last = state.chatMode and window.chatTabs[#window.chatTabs] or window.tabs[#window.tabs]
	window.tabRight:SetPoint("LEFT", last, "RIGHT", 12, 0)
	for index, tab in ipairs(window.tabs) do
		local selected = index == state.tab
		SetRowSelected(tab, selected)
		tab.label:SetTextColor(selected and GOLD[1] or 0.8, selected and GOLD[2] or 0.8, selected and GOLD[3] or 0.8)
	end
	window.tabs[TAB_CHAT].badge:SetCount(unread)
	window.tabLeft:SetText(Hint("{PADLSHOULDER}"))
	window.tabRight:SetText(Hint("{PADRSHOULDER}"))
end

local function DrawSettings()
	local rows = SettingsRowsList()
	state.settingsCursor = Clamp(state.settingsCursor or 1, 1, #rows)
	for index, frame in ipairs(window.settingFrames) do
		local row = rows[index]
		frame:SetShown(row ~= nil)
		if row then
			SetRowSelected(frame, not state.picker and index == state.settingsCursor)
			frame.label:SetText(ns.ButtonText(row.label, 16))
			frame.toggle:SetShown(row.kind == "toggle")
			if row.kind == "toggle" then
				frame.toggle:SetChecked(row.value() and true or false)
				frame.value:SetText("")
			elseif row.kind == "cycle" then
				frame.value:SetText(row.value() .. "  " .. DROPDOWN_ARROW)
			else
				local text = row.value()
				frame.value:SetText("|cff999999" .. (#text > 26 and (text:sub(1, 24) .. "...") or text) .. "|r")
			end
		end
	end
	local row = rows[state.settingsCursor]
	local tip = row and row.tip
	if type(tip) == "function" then
		tip = tip()
	end
	local editing = window.settingsInput:HasFocus()
	local message = (row and row.message) or editing
	window.settingsTip:SetShown(not message)
	window.settingsTip:SetText(tip and ns.ButtonText(tip, 16) or "")
	local editor = window.msgEditor
	editor:SetShown(message and true or false)
	if message then
		if not editing then
			window.settingsInput:SetText(ns.db.lfgMessage or "")
		end
		editor.box:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], editing and 1 or 0.35)
		local tags = {}
		for index, tag in ipairs(SettingsNav.tags) do
			tags[#tags + 1] = (editing and index == SettingsNav.tag) and ("|cffffd100[" .. tag .. "]|r") or ("|cffaaaaaa" .. tag .. "|r")
		end
		editor.tags:SetText(table.concat(tags, "   "))
		editor.help:SetText(ns.ButtonText(editing
			and "Typing: Enter saves, {PAD2} cancels. {PADDLEFT}{PADDRIGHT} pick a tag, {PAD3} puts it in."
			or "{PAD1} edits the message, {PAD3} puts the default back. A keyboard or the on-screen keyboard is needed to type.", 16))
		editor.UpdatePreview()
	end
end

-- The List group tab: the rows on the left, the listing and the party on the right.
local function DrawListing()
	local rows = ListRowsList()
	state.createCursor = Clamp(state.createCursor or 2, 1, #rows)
	if rows[state.createCursor].kind == "header" then
		state.createCursor = state.createCursor % #rows + 1
	end
	for index, frame in ipairs(window.listFrames) do
		local row = rows[index]
		frame:SetShown(row ~= nil)
		if row then
			local selected = not state.picker and index == state.createCursor
			frame.baseColor = row.kind == "header" and PANEL or CONTROL
			SetRowSelected(frame, selected)
			frame.label:SetText(row.label)
			frame.icon:Hide()
			frame.value:SetText("")
			frame.toggle:Hide()
			frame.label:SetTextColor(0.92, 0.92, 0.92)
			if row.kind == "header" then
				frame.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
				frame.value:SetText(row.note and ("|cff999999" .. row.note .. "|r") or "")
			elseif row.kind == "cycle" then
				frame.value:SetText(row.value() .. "  " .. DROPDOWN_ARROW)
			elseif row.kind == "toggle" then
				if row.role then
					frame.icon:SetAtlas(ROLE_ATLAS[row.role])
					frame.icon:Show()
				end
				frame.toggle:SetChecked(row.value() and true or false)
				frame.toggle:Show()
			elseif row.kind == "action" then
				frame.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
			end
		end
	end

	-- Your listing.
	local lines = {}
	local entry = C_LFGList.HasActiveEntryInfo() and Call("GetActiveEntryInfo", C_LFGList.GetActiveEntryInfo)
	if type(entry) == "table" then
		local names = {}
		for _, id in ipairs(Plain(entry.activityIDs, {})) do
			names[#names + 1] = ActivityName(id)
		end
		lines[#lines + 1] = "|cff55ee55Listed|r for " .. (#names > 0 and table.concat(names, ", ") or "?")
		local duration = Plain(entry.duration, nil)
		if duration then
			lines[#lines + 1] = "|cff999999Expires in " .. math.floor(duration / 60) .. " min|r"
		end
	else
		lines[#lines + 1] = IsInGroup() and "|cff999999Not listed. Pick a category and activities, then List group.|r"
			or "|cff999999Not listed. Pick your roles, a category and the activities you want, then List me: groups looking for players see you and can invite you.|r"
	end
	if not CanEditListing() then
		lines[#lines + 1] = "|cffff8855Only the group leader can list or change the listing.|r"
	end
	window.listStatus:SetText(table.concat(lines, "\n"))

	-- The party and the roles they took.
	local members = { { unit = "player" } }
	if IsInGroup() and not IsInRaid() then
		for index = 1, GetNumSubgroupMembers() do
			members[#members + 1] = { unit = "party" .. index }
		end
	end
	for index, frame in ipairs(window.partyFrames) do
		local member = members[index]
		local unit = member and member.unit
		frame:SetShown(unit ~= nil and UnitExists(unit))
		if unit and UnitExists(unit) then
			local _, class = UnitClass(unit)
			frame.name:SetText(ClassColored(FullName(GetUnitName(unit, true)), Plain(class, nil)) .. (UnitIsGroupLeader(unit) and "  |cffffd100leader|r" or ""))
			local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or "NONE"
			local key = role == "TANK" and "tank" or role == "HEALER" and "healer" or role == "DAMAGER" and "dps" or nil
			if key then
				frame.role:SetAtlas(ROLE_ATLAS[key])
				frame.role:Show()
				frame.roleText:SetText(ROLE_NAMES[key])
			else
				-- No role in a group yet: yours are the ones picked on the left, for listing and signing up.
				local picked = {}
				local roles = unit == "player" and MyRoles() or {}
				for _, name in ipairs(ROLES) do
					if roles[name] then
						picked[#picked + 1] = name
					end
				end
				frame.role:SetShown(#picked > 0)
				if #picked > 0 then
					frame.role:SetAtlas(ROLE_ATLAS[picked[1]])
					for i, name in ipairs(picked) do
						picked[i] = ROLE_NAMES[name]
					end
				end
				frame.roleText:SetText(#picked > 0 and table.concat(picked, ", ") or "|cff999999No role|r")
			end
		end
	end
	window.partyTitle:SetText(IsInGroup() and "Your party" or "You")
end

local function DrawFilters(active)
	local rows = FilterRowsList()
	for index, frame in ipairs(window.filterFrames) do
		local row = rows[index]
		frame:SetShown(row ~= nil)
		if row then
			local selected = active and state.focus == "filters" and not state.picker and index == state.filterCursor
			frame.baseColor = row.kind == "header" and PANEL or CONTROL
			SetRowSelected(frame, selected)
			frame.label:SetText(row.label)
			frame.icon:Hide()
			frame.value:SetText("")
			frame.toggle:Hide()
			if row.kind == "header" then
				frame.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
				frame.value:SetText(IsInGroup() and "|cff999999in a group|r" or "|cff999999on your own|r")
			else
				frame.label:SetTextColor(0.92, 0.92, 0.92)
			end
			if row.kind == "cycle" then
				frame.value:SetText(row.value() .. "  " .. DROPDOWN_ARROW)
			elseif row.kind == "toggle" then
				if row.role then
					frame.icon:SetAtlas(ROLE_ATLAS[row.role])
					frame.icon:Show()
				end
				frame.toggle:SetChecked(row.value() and true or false)
				frame.toggle:Show()
			elseif row.kind == "action" then
				frame.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
			end
		end
	end

end

-- The open dropdown, under its row in the given column of rows.
local function DrawPicker(side, rows, rowHeight)
	local picker = window.picker
	picker:SetShown(state.picker ~= nil)
	if state.picker then
		local list = PickerItems(state.picker)
		local multi = MULTI_PICKERS[state.picker]
		local setting = SettingRow(state.picker)
		local phraseGroup = tonumber(state.picker:match("^phrase:(%d+)$") or "")
		local added = state.Added(state.picker)
		picker.title:SetText((setting and ns.ButtonText(setting.label, 16) or phraseGroup and PHRASES[phraseGroup] and PHRASES[phraseGroup].name
			or PICKER_TITLES[state.picker] or state.NoteTitle(state.picker)
			or (state.picker:find("^rate:") and state.picker:match("^rate:(%a+)$")) or "") .. (added and (added.failed and "  |cffff6060Too long to add|r" or "  |cff40ff40Added|r") or ""))
		-- Placed under its row, moved up when it would run past the bottom.
		local rowIndex = 1
		for index, row in ipairs(rows) do
			if row.picker == state.picker then
				rowIndex = index
			end
		end
		local shownRows = math.min(#list, PICKER_ROWS)
		local height = 72 + math.max(1, shownRows) * 30
		local top = 22 + rowIndex * rowHeight
		local room = side:GetHeight()
		top = math.max(22, math.min(top, room - height))
		picker:ClearAllPoints()
		picker:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -top)
		picker:SetPoint("RIGHT", side, "RIGHT")
		picker:SetHeight(height)
		Fit("pickerCursor", "pickerScroll", #list, PICKER_ROWS)
		for index, frame in ipairs(picker.rows) do
			local position = state.pickerScroll + index
			local item = list[position]
			frame:SetShown(item ~= nil)
			frame.position = position
			if item then
				SetRowSelected(frame, position == state.pickerCursor)
				frame.label:SetText(item.text)
				local gold = item.checked and not multi
				frame.label:SetTextColor(gold and GOLD[1] or 0.92, gold and GOLD[2] or 0.92, gold and GOLD[3] or 0.92)
				frame.toggle:SetShown(multi)
				frame.toggle:SetChecked(item.checked and true or false)
				frame.check:SetShown(gold and true or false)
			end
		end
		picker.more:SetText(#list > PICKER_ROWS and ((state.pickerScroll + 1) .. "-" .. (state.pickerScroll + shownRows) .. " of " .. #list) or "")
		picker.empty:SetShown(#list == 0)
		picker.empty:SetText((state.pickerQuery or "") ~= "" and "Nothing matches your search." or "Nothing to pick.")
	end
end

-- The role column of a row, one scheme for every row:
--   Groups:  under each role icon, how many players the group has in that role (0, 0, 3). The icon
--            is bright while the group still needs that role and dimmed once the role is full.
--   Players: the icon is bright for the roles the player can fill and dimmed for the others, no numbers.
local function DrawRoleSummary(frame, entry)
	for index, role in ipairs(ROLES) do
		local icon, count = frame.roleIcons[index], frame.roleCounts[index]
		icon:SetAtlas(ROLE_ATLAS[role])
		if entry.solo then
			local on = entry.roles and entry.roles[role]
			icon:SetShown(true)
			icon:SetDesaturated(not on)
			icon:SetAlpha(on and 1 or 0.25)
			count:SetText("")
		elseif entry.counts then
			local have, left = entry.counts[role], entry.counts[role .. "Left"]
			icon:SetShown(true)
			icon:SetDesaturated(left == 0)
			icon:SetAlpha(left > 0 and 1 or 0.3)
			count:SetText(have)
			if left > 0 then
				count:SetTextColor(1, 1, 1)
			else
				count:SetTextColor(0.5, 0.5, 0.5)
			end
		else
			icon:Hide()
			count:SetText("")
		end
	end
end

local function DrawResults(active)
	local results = state.results
	Fit("listCursor", "listScroll", #results, RESULT_ROWS)
	state.selectedResult = results[state.listCursor] and results[state.listCursor].id or nil
	local players = ShowPlayers()
	for index, frame in ipairs(window.resultFrames) do
		local position = state.listScroll + index
		local entry = results[position]
		frame:SetShown(entry ~= nil)
		frame.position = position
		if entry then
			SetRowSelected(frame, active and state.focus == "list" and position == state.listCursor)
			if entry.class then
				frame.icon:SetAtlas("groupfinder-icon-class-" .. entry.class:lower())
			else
				frame.icon:SetTexture("Interface\\Icons\\INV_Misc_GroupNeedMore")
			end
			local name = entry.secret and "Hidden listing" or ClassColored(entry.leader, entry.class)
			if entry.level then
				name = name .. " |cff999999" .. entry.level .. "|r"
			end
			if entry.rating > 0 then
				local rating = RATINGS[entry.rating]
				name = name .. "  " .. rating.tag
			end
			if (entry.avoided or 0) > 0 then
				name = name .. "  |cffff5555" .. entry.avoided .. " avoided|r"
			end
			if state.asked[entry.leader or ""] then
				name = name .. "  |cff55ee55asked|r"
			end
			frame.name:SetText(name)
			local detail = entry.comment ~= "" and entry.comment or entry.title or ""
			-- Your notes on the leader and on members you rated come first.
			local notes = {}
			if entry.note then
				notes[#notes + 1] = "|cffffd100Note:|r " .. entry.note
			end
			for _, name in ipairs(entry.known or {}) do
				local rating = RatingOf(name)
				local mark = rating > 0 and (" " .. RATINGS[rating].tag) or ""
				notes[#notes + 1] = "|cffffd100" .. Short(name) .. "|r" .. mark .. (NoteOf(name) and (": " .. NoteOf(name)) or "")
			end
			if #notes > 0 then
				detail = table.concat(notes, "  |cff666666|||r  ") .. (detail ~= "" and ("  |cff666666|||r  " .. detail) or "")
			end
			detail = detail:gsub("\n", " ")
			-- Line 2: the activity in gold, then your notes and the comment in grey after it. The
			-- activity takes at most 60% of the line when something follows it; both end in "..." when cut.
			local room = (frame:GetWidth() or 0) > 200 and (frame:GetWidth() - 50 - 152) or 410
			local activity = entry.activityText or ""
			frame.activity:SetWidth(0)
			frame.activity:SetText(activity)
			local wide = frame.activity.GetUnboundedStringWidth and frame.activity:GetUnboundedStringWidth() or frame.activity:GetStringWidth() or 0
			frame.activity:SetWidth(activity == "" and 1 or math.max(1, math.min(wide + 2, detail ~= "" and room * 0.6 or room)))
			frame.detail:SetText(detail)
			frame.size:SetText(entry.solo and "" or (entry.members .. "|cff999999/" .. (entry.maxPlayers or 5) .. "|r"))
			DrawRoleSummary(frame, entry)
			frame.badge:SetCount(UnreadFrom(entry.leader))
		end
	end
	-- The listing the details panel beside the list shows (LfgDetails.lua, drawn from Refresh): the
	-- row under the mouse, else the controller's row while the cursor is in the list.
	local hover = state.hoverRow
	local pick, slot
	if hover and hover:IsVisible() and results[hover.position] then
		pick, slot = results[hover.position], hover.slot
	elseif active and state.focus == "list" and results[state.listCursor] then
		pick, slot = results[state.listCursor], state.listCursor - state.listScroll
	end
	state.detailsEntry, state.detailsSlot = pick, slot
	local header
	if state.searching then
		header = "Searching..."
	elseif state.status then
		header = state.status
	elseif not state.searchedOnce then
		header = "Press " .. Hint("{PAD4}") .. " to search"
	elseif #results == 0 then
		header = state.searchFailed and "The search failed. Try again." or ("No " .. (players and "players" or "groups") .. " match your filters")
	else
		header = #results .. " " .. (players and "players looking for a group" or "groups") .. "  |cff999999of " .. state.total .. " listings|r"
	end
	state.headerBase = header
	window.resultsHeader:SetText(header .. state.RefreshText())
end

local function DrawConfirm()
	local confirm = window.confirm
	local entry = state.confirm
	confirm:SetShown(entry ~= nil and state.tab == TAB_FINDER)
	if entry then
		confirm.title:SetText("Whisper " .. Short(entry.leader) .. "?")
		confirm.message:SetText("\"" .. (ns.LfgMessage and ns.LfgMessage({ leaderName = entry.leader, activityIDs = AskActivities(entry) }) or "") .. "\"")
		confirm.keys:SetText(Hint("{PAD1} Send     {PAD2} Cancel"))
	end
end

local function DrawChat(active)
	local name, chat, list = SelectedChat()
	state.selectedName = name -- kept selected when a whisper reorders the list
	Fit("chatCursor", "chatScroll", #list, CHAT_ROWS)
	for index, frame in ipairs(window.chatFrames) do
		local position = state.chatScroll + index
		local item = list[position]
		frame:SetShown(item ~= nil)
		frame.position = position
		if item and item.special then
			frame.baseColor = { 0.1, 0.1, 0.12, 1 }
			frame.stripe:Hide()
			SetRowSelected(frame, active and position == state.chatCursor)
			if item.special == "history" then
				frame.name:SetText("|cffffd100History|r")
				frame.preview:SetText("|cff999999" .. item.count .. " older or closed chat" .. (item.count == 1 and "" or "s") .. "|r")
			else
				frame.name:SetText("|cffffd100< Back to chats|r")
				frame.preview:SetText("|cff999999Older and closed chats below|r")
			end
			frame.time:SetText("")
			frame.badge:SetCount(0)
		elseif item then
			-- Channels stand apart: a stripe and a tint in the channel's colour.
			local channel = ChannelInfo(item.name)
			if channel then
				local r, g, b = HexColor(channel.color)
				frame.baseColor = { r * 0.22, g * 0.22, b * 0.22, 1 }
				frame.stripe:SetColorTexture(r, g, b, 1)
				frame.stripe:Show()
			else
				frame.baseColor = nil
				frame.stripe:Hide()
			end
			SetRowSelected(frame, active and position == state.chatCursor)
			frame.name:SetText(ChatName(item.name, item.chat))
			local last = item.chat.lines[#item.chat.lines]
			local who = last and (last.o and (ns.ChatHistory.You() .. "|cff999999:|r ") or last.s and ("|cff999999" .. Short(last.s) .. ":|r ") or "") or ""
			-- The last message in the game's colour for its chat; a past group: its members and how long it lasted.
			frame.preview:SetText(item.group and ("|cff999999" .. ns.ChatHistory.Subtitle(item.group) .. "|r")
				or last and (who .. ns.ChatHistory.ColorCode(item.name, item.chat, last) .. Markers.Icons(last.m) .. "|r")
				or "|cff999999No messages yet|r")
			frame.time:SetText(last and Ago(item.chat.last) or "")
			frame.badge:SetCount(item.chat.unread or 0)
		end
	end
	window.chatEmpty:SetShown(#list == 0)
	if not name then
		window.chatLog:Clear()
		window.chatLog.shownFor, window.chatLog.shownSeq = nil, nil
	end

	-- A past group (ChatHistory.lua): read only, its members above the chat and in a list ({PAD4}).
	local group = name and (ChannelInfo(name) or {}).archived and chat or nil
	if state.membersFor and state.membersFor ~= (group and name) then
		state.membersFor = nil
	end
	window.DrawGroupPane(group)

	-- Names in class colours, the text in the game's colour for the chat; your own lines marked.
	local log = window.chatLog
	local own = ns.ChatHistory.HighlightOwn()
	if log.shownFor ~= name or log.shownSeq ~= (chat and chat.seq or 0) or log.shownOwn ~= own then
		log:Clear()
		if chat then
			for _, line in ipairs(chat.lines) do
				local who = line.o and ns.ChatHistory.You() or line.s and ClassColored(line.s, line.c)
					or (not ChannelInfo(name) and ClassColored(name, chat.class)) or nil
				log:AddMessage((line.o and ns.ChatHistory.OwnMark() or "") .. "|cff777777" .. date("%H:%M", line.t) .. "|r  "
					.. (who and (who .. ":  ") or "") .. Markers.Icons(line.m), ns.ChatHistory.Color(name, chat, line))
			end
		end
		log.shownFor, log.shownSeq, log.shownOwn = name, chat and chat.seq or 0, own
	end
	-- What is on screen is read.
	if chat and (chat.unread or 0) > 0 and window:IsShown() then
		Log("read", name, chat.unread)
		chat.unread = 0
		window.tabs[TAB_CHAT].badge:SetCount(UnreadTotal())
		if ns.UpdateLfgHint then
			ns.UpdateLfgHint()
		end
	end
	local rating = name and RatingOf(name) or 0
	local note = name and NoteOf(name)
	window.chatTitle:SetText(group and (ChatName(name, chat) .. "  |cff999999" .. date("%d %b %H:%M", group.started or 0)
		.. " - " .. date("%H:%M", group.ended or 0) .. "|r") or name and (ChatName(name, chat) .. (note and ("  |cffffd100Note:|r " .. note) or "") .. (rating > 0 and ("  " .. RATINGS[rating].tag) or "")) or "")
	-- The quick reply and the key that adds it: {PAD1} while nothing is typed, {PADLSTICK} while typing.
	local typed = strtrim(window.input:GetText() or "") ~= ""
	local addKey = not typed and "{PAD1}" or window.input:HasFocus() and "{PADLSTICK}"
	window.reply:SetText(name and not group and (Hint("{PADDLEFT}") .. "  " .. ReplyText(state.replyIndex, name) .. "  " .. Hint("{PADDRIGHT}")
		.. (addKey and ("     |cffbbbbbb" .. Hint(addKey) .. " Add|r") or "")) or "")
	window.input:SetShown(name ~= nil and not group)
end

local function DrawRatings(active)
	local rows = RateRows()
	Fit("rateCursor", "rateScroll", #rows, RATE_ROWS)
	for index, frame in ipairs(window.rateFrames) do
		local position = state.rateScroll + index
		local row = rows[position]
		frame:SetShown(row ~= nil)
		frame.position = position
		if row then
			SetRowSelected(frame, active and position == state.rateCursor)
			if row.class then
				frame.icon:SetAtlas("groupfinder-icon-class-" .. row.class:lower())
			else
				frame.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
			end
			local roleIcons = ns.LfgRoleIcons(row.name, 15)
			frame.name:SetText(ClassColored(row.name, row.class) .. (roleIcons ~= "" and ("  " .. roleIcons) or ""))
			local note = NoteOf(row.name)
			local dungeons = ns.LfgDungeonCount(row.name)
			frame.where:SetText((note and ("|cffffd100Note:|r |cffdddddd" .. note .. "|r   ") or "")
				.. (dungeons > 0 and ("|cffdddddd" .. dungeons .. (dungeons == 1 and " dungeon" or " dungeons") .. "|r   ") or "")
				.. "|cff999999" .. (row.where or "") .. "|r" .. (row.t and ("  |cff777777" .. Ago(row.t) .. " ago|r") or ""))
			local rating = RatingOf(row.name)
			for value, pill in ipairs(frame.pills) do
				local on = value == rating
				local color = RATINGS[value].color
				pill:SetBackdropColor(color[1] * (on and 0.55 or 0.12), color[2] * (on and 0.55 or 0.12), color[3] * (on and 0.55 or 0.12), 1)
				pill:SetBackdropBorderColor(color[1], color[2], color[3], on and 1 or 0.25)
				pill.text:SetTextColor(color[1], color[2], color[3], on and 1 or 0.5)
			end
			frame.badge:SetCount(UnreadFrom(row.name))
		end
	end
	window.rateEmpty:SetShown(#rows == 0)
end

local function FooterText()
	if state.tab == TAB_FINDER then
		if state.confirm then
			return ""
		elseif state.picker == "languages" then
			return "{PAD1} Tick     {PAD3} Search     {PAD2} Done"
		elseif state.picker then
			return "{PAD1} Choose     {PAD3} Search     {PAD2} Cancel"
		elseif state.focus == "filters" then
			local row = FilterRowsList()[state.filterCursor]
			if row and row.kind == "cycle" then
				local list = #state.results > 0 and (ShowPlayers() and "{PADDRIGHT} Players     " or "{PADDRIGHT} Groups     ") or ""
				return "{PAD1} Open     " .. list .. "{PAD4} Search     {PAD3} List     {PAD2} Back"
			end
			local list = #state.results > 0 and (ShowPlayers() and "{PADDRIGHT} Players     " or "{PADDRIGHT} Groups     ") or ""
			return "{PAD1} Select     " .. list .. "{PAD4} Search     {PAD2} " .. (#state.results > 0 and "Back" or "Close")
		end
		local action = GroupAction(state.results[state.listCursor])
		local text = action and ("{PAD1} " .. action .. "     ") or ""
		local entry = state.results[state.listCursor]
		if entry and entry.leader then
			text = text .. "{PADDRIGHT} Chat     "
		end
		return text .. "{PADDLEFT} Filters     {PAD4} Search     {PAD2} Close"
	elseif state.tab == TAB_SETTINGS then
		if state.picker then
			return "{PAD1} Choose     {PAD3} Search     {PAD2} Cancel"
		elseif window.settingsInput:HasFocus() then
			return "Enter saves     {PADDLEFT}{PADDRIGHT} Tag     {PAD3} Put the tag in     {PAD2} Cancel"
		end
		local row = SettingsRowsList()[state.settingsCursor or 1]
		if row and row.message then
			return "{PAD1} Edit     {PAD3} Default     {PAD2} Close"
		end
		return "{PADDLEFT}{PADDRIGHT} Change     {PAD1} Select     {PAD2} Close"
	elseif state.tab == TAB_LIST then
		if state.picker then
			return MULTI_PICKERS[state.picker] and "{PAD1} Tick     {PAD3} Search     {PAD2} Done" or "{PAD1} Choose     {PAD3} Search     {PAD2} Cancel"
		end
		local row = ListRowsList()[state.createCursor or 1]
		local verb = row and (row.kind == "cycle" and "Open" or row.kind == "toggle" and "Switch" or "Select") or "Select"
		return "{PAD1} " .. verb .. "     {PAD4} " .. state.ListLabel() .. "     {PAD2} Close"
	elseif state.tab == TAB_CHAT then
		if state.picker then
			return "{PADDUP}{PADDDOWN} Move     {PAD1} " .. (state.picker == "phrases" and "Open" or "Add") .. "     {PAD3} Search     {PAD2} Back"
		end
		-- {PAD1} sends what is typed, or puts the quick reply in while nothing is.
		local send = strtrim(window.input:GetText() or "") ~= "" and "{PAD1} Send     " or "{PAD1} Add reply     "
		local name, chat, _, special = SelectedChat()
		if special then
			return "{PAD1} " .. (special == "history" and "Open history" or "Back to chats") .. "     {PAD2} Close"
		elseif name and ChannelInfo(name) and ChannelInfo(name).archived then
			local members = chat.members or {}
			if state.membersFor == name then
				local member = members[state.memberCursor]
				return (member and not member.me and "{PAD1} Whisper     " or "") .. "{PAD4} Hide members     {PAD2} Back"
			end
			return "|cff999999Past group, read only|r     " .. (#members > 0 and "{PAD4} Members     " or "")
				.. "{PADLTRIGGER} Delete     {PAD2} Close"
		elseif not name or (ChannelInfo(name) and ChannelInfo(name).readOnly) then
			return "{PAD2} Close"
		elseif ChannelInfo(name) then
			return "{PADDLEFT}{PADDRIGHT} Reply     " .. send .. "{PADRSTICK} Ready-made messages     {PAD3} " .. (window.input:HasFocus() and "Erase" or "Type") .. "     {PAD2} Close"
		end
		return "{PADDLEFT}{PADDRIGHT} Reply     " .. send .. "{PADRSTICK} Ready-made messages     {PAD3} " .. (window.input:HasFocus() and "Erase" or "Type") .. "     {PAD4} Invite     {PADLTRIGGER} "
			.. (state.chatHistory and "Delete" or "Close chat") .. "     {PAD2} Close"
	end
	if state.picker then
		return "{PAD1} Choose     {PAD3} Search     {PAD2} Cancel"
	end
	if window.noteInput:HasFocus() then
		return "Type a note on " .. Short(window.noteInput.target and window.noteInput.target.name) .. ", Enter adds it     {PAD2} Cancel"
	end
	return "{PADDLEFT}{PADDRIGHT} Rate     {PAD4} Note     {PAD1} Chat     {PAD3} Clear rating     {PADLTRIGGER} Sort and filter     {PAD2} Close"
end

function Refresh()
	if not window or not window:IsShown() then
		return
	end
	FixFocus()
	DrawTabs()
	local groups, chat, ratings = state.tab == TAB_FINDER, state.tab == TAB_CHAT, state.tab == TAB_RATINGS
	local listing = state.tab == TAB_LIST
	local settings = state.tab == TAB_SETTINGS
	window.groups:SetShown(groups)
	window.listing:SetShown(listing)
	window.settings:SetShown(settings)
	window.chat:SetShown(chat)
	window.ratings:SetShown(ratings)
	window.picker:Hide()
	if groups then
		DrawFilters(true)
		DrawResults(true)
		DrawPicker(window.filterSide, FilterRowsList(), FILTER_ROW_HEIGHT)
	elseif listing then
		DrawListing()
		DrawPicker(window.listSide, ListRowsList(), LIST_ROW_HEIGHT)
	elseif settings then
		DrawSettings()
		DrawPicker(window.settingsSide, SettingsRowsList(), LIST_ROW_HEIGHT + 6)
	elseif chat then
		DrawChat(true)
		DrawPicker(window.chatSide, {}, CHAT_ROW_HEIGHT)
	else
		DrawRatings(true)
		DrawPicker(window.rateSide, {}, RATE_ROW_HEIGHT)
	end
	DrawConfirm()
	-- The details panel beside the window: only over the results, never with a dropdown or a question open.
	if ns.LfgDetails then
		local shown = groups and not state.picker and not state.confirm and not state.yielded and state.detailsEntry or nil
		ns.LfgDetails.Draw(window, shown,
			-(TITLE_HEIGHT + TAB_HEIGHT + 4 + 10 + 22 + ((state.detailsSlot or 1) - 1) * RESULT_ROW_HEIGHT))
	end
	if state.chatMode then
		local unread = UnreadTotal(true)
		window.mode:SetText(unread > 0 and ("|cffff5555" .. unread .. " unread|r") or "")
	else
		window.mode:SetText(IsInGroup() and "|cff999999You are in a group: showing players|r" or "|cff999999On your own: showing groups|r")
	end
	local findBox = window.findBox
	findBox:SetShown(state.FIND_TABS[state.tab] and true or false)
	if not findBox:HasFocus() and findBox:GetText() ~= (state.find[state.tab] or "") then
		findBox:SetText(state.find[state.tab] or "")
	end
	findBox.placeholder:SetText(Hint("{PADRTRIGGER} Search"))
	findBox.placeholder:SetShown(findBox:GetText() == "" and not findBox:HasFocus())
	window.selected:SetShown(not state.yielded)
	local tagText = not state.yielded and "{PAD2} Close" or state.canTakeBack and "{PADBACK} Select" or nil
	window.selectTag:SetShown(tagText ~= nil)
	if tagText then
		window.selectTag.text:SetText(ns.ButtonText(tagText, 16))
		window.selectTag:SetWidth(math.max(120, (window.selectTag.text:GetStringWidth() or 0) + 20))
	end
	window.footer:SetText(state.yielded and (state.canTakeBack and Hint("|cff999999The game's window has the controller.|r  {PADBACK} Take it back")
		or "|cff999999The game's window has the controller. LFG Filter gets it back when that window closes.|r") or Hint(FooterText()))
	if chat and window.input:HasFocus() then
		window.gameHint:SetText("") -- {PADLSTICK} adds the quick reply while typing
	elseif state.chatMode then
		window.gameHint:SetText(Hint("{PADLSTICK} Game's chat"))
	else
		window.gameHint:SetText(window.gameButton and Hint("{PADLSTICK} Game's group finder") or "")
	end
end
ns.RefreshLfgFilter = function()
	if window and window:IsShown() then
		Refresh()
	end
	if ns.ChatBoxRefresh then
		ns.ChatBoxRefresh()
	end
end

---------------------------------------------------------------------------------------------------
-- Building the window

local function CreateToggle(parent)
	local toggle = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	toggle:SetSize(34, 16)
	Flat(toggle, CONTROL)
	toggle.knob = toggle:CreateTexture(nil, "OVERLAY")
	toggle.knob:SetSize(12, 12)
	toggle.knob:SetTexture(WHITE)
	function toggle:SetChecked(on)
		self.knob:ClearAllPoints()
		if on then
			self:SetBackdropColor(GOLD[1] * 0.85, GOLD[2] * 0.85, GOLD[3], 1)
			self:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
			self.knob:SetPoint("RIGHT", -2, 0)
			self.knob:SetVertexColor(0.08, 0.08, 0.1, 1)
		else
			self:SetBackdropColor(unpack(CONTROL))
			self:SetBackdropBorderColor(1, 1, 1, 0.25)
			self.knob:SetPoint("LEFT", 2, 0)
			self.knob:SetVertexColor(0.55, 0.55, 0.6, 1)
		end
	end
	toggle:SetChecked(false)
	return toggle
end

local function Run(action)
	return function(...)
		local ok, err = pcall(action, ...)
		if not ok then
			Log("error:", err)
			ns.Print("LFG Filter error, see /gxiv lfgfilterlog:", tostring(err))
		end
		Refresh()
	end
end

local function BuildGroups(content)
	local groups = CreateFrame("Frame", nil, content)
	groups:SetAllPoints()
	window.groups = groups

	local side = CreateFrame("Frame", nil, groups)
	side:SetPoint("TOPLEFT", 12, -10)
	side:SetPoint("BOTTOMLEFT", 12, 10)
	side:SetWidth(SIDE_WIDTH)
	local sideTitle = Text(side, "GameFontNormal")
	sideTitle:SetPoint("TOPLEFT", 2, 0)
	sideTitle:SetText("Filters")
	window.filterFrames = {}
	for index = 1, 12 do
		local row = CreateRow(side, FILTER_ROW_HEIGHT - 4, Run(function()
			state.focus = "filters"
			state.filterCursor = index
			Nav.Accept()
		end))
		row:SetPoint("TOPLEFT", 0, -22 - (index - 1) * FILTER_ROW_HEIGHT)
		row:SetPoint("RIGHT", side, "RIGHT")
		row.icon = RoleIcon(row, 20)
		row.icon:SetPoint("LEFT", 8, 0)
		row.label = Text(row)
		row.label:SetPoint("LEFT", 34, 0)
		row.value = Text(row, "GameFontHighlightSmall")
		row.value:SetPoint("RIGHT", -10, 0)
		row.value:SetJustifyH("RIGHT")
		row.value:SetPoint("LEFT", row.label, "RIGHT", 6, 0)
		row.toggle = CreateToggle(row)
		row.toggle:SetPoint("RIGHT", -10, 0)
		window.filterFrames[index] = row
	end

	-- The dropdown list opens under its row, over the filters.
	window.filterSide = side
	local picker = CreateFrame("Frame", nil, window, "BackdropTemplate")
	picker:SetFrameLevel(window:GetFrameLevel() + 40)
	Flat(picker, { 0.06, 0.06, 0.075, 0.99 }, { GOLD[1], GOLD[2], GOLD[3], 0.6 })
	picker:EnableMouse(true)
	picker:EnableMouseWheel(true)
	picker:SetScript("OnMouseWheel", Run(function(_, delta)
		state.pickerCursor = state.pickerCursor - delta
	end))
	picker.title = Text(picker, "GameFontNormal")
	picker.title:SetPoint("TOPLEFT", 10, -9)
	picker.more = Text(picker, "GameFontDisableSmall")
	picker.more:SetPoint("TOPRIGHT", -10, -10)
	-- Typing narrows the list; the controller keeps moving through what is left.
	picker.search = CreateFrame("EditBox", "GamepadXIVLfgFilterSearch", picker, "SearchBoxTemplate")
	picker.search:SetHeight(22)
	picker.search:SetPoint("TOPLEFT", 14, -32)
	picker.search:SetPoint("TOPRIGHT", -8, -32)
	picker.search:SetAutoFocus(false)
	picker.search:HookScript("OnTextChanged", function(self)
		if not state.picker then
			return
		end
		local text = self:GetText() or ""
		if text ~= (state.pickerQuery or "") then
			state.pickerQuery = text
			state.pickerCursor, state.pickerScroll = 1, 0
			Refresh()
		end
	end)
	picker.search:HookScript("OnEnterPressed", function(self)
		self:ClearFocus()
	end)
	picker.rows = {}
	for index = 1, PICKER_ROWS do
		local row = CreateRow(picker, 26, nil)
		row:SetScript("OnClick", Run(function()
			state.pickerCursor = row.position or index
			PickerAccept()
		end))
		row:SetPoint("TOPLEFT", 6, -64 - (index - 1) * 30)
		row:SetPoint("RIGHT", -6, 0)
		row.label = Text(row)
		row.label:SetPoint("LEFT", 10, 0)
		row.label:SetPoint("RIGHT", -50, 0)
		row.label:SetJustifyH("LEFT")
		row.toggle = CreateToggle(row)
		row.toggle:SetPoint("RIGHT", -8, 0)
		row.check = row:CreateTexture(nil, "OVERLAY")
		row.check:SetSize(16, 16)
		row.check:SetPoint("RIGHT", -10, 0)
		row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
		row:SetScript("OnMouseWheel", Run(function(_, delta)
			state.pickerCursor = state.pickerCursor - delta
		end))
		picker.rows[index] = row
	end
	picker.empty = Text(picker, "GameFontDisable")
	picker.empty:SetPoint("CENTER", 0, -8)
	picker.empty:SetText("Nothing to pick.")
	picker:Hide()
	window.picker = picker

	local list = CreateFrame("Frame", nil, groups)
	list:SetPoint("TOPLEFT", side, "TOPRIGHT", 14, 0)
	list:SetPoint("BOTTOMRIGHT", -12, 10)
	window.resultsHeader = Text(list, "GameFontNormal")
	window.resultsHeader:SetPoint("TOPLEFT", 2, 0)
	window.resultsHeader:SetPoint("RIGHT", list, "RIGHT")
	window.resultsHeader:SetJustifyH("LEFT")
	window.resultFrames = {}
	for index = 1, RESULT_ROWS do
		local row = CreateRow(list, RESULT_ROW_HEIGHT - 4, nil)
		row:SetScript("OnClick", Run(function()
			state.focus = "list"
			if state.listCursor == row.position then
				ActivateResult(state.results[row.position])
			end
			state.listCursor = row.position
		end))
		row:SetPoint("TOPLEFT", 0, -22 - (index - 1) * RESULT_ROW_HEIGHT)
		row:SetPoint("RIGHT", list, "RIGHT")
		row.slot = index
		-- Left: the class icon, then two lines between x 50 and the right block (152 from the right),
		-- cut with "..." rather than running into it: the leader's name and level, then the activity
		-- and the comment. Right block: the member count, then a column per role (DrawRoleSummary).
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(32, 32)
		row.icon:SetPoint("LEFT", 8, 0)
		row.name = Text(row)
		row.name:SetPoint("TOPLEFT", 50, -8)
		row.name:SetPoint("TOPRIGHT", -152, -8)
		row.name:SetJustifyH("LEFT")
		row.activity = Text(row, "GameFontNormalSmall")
		row.activity:SetPoint("BOTTOMLEFT", 50, 8)
		row.activity:SetJustifyH("LEFT")
		row.detail = Text(row, "GameFontDisableSmall")
		row.detail:SetPoint("BOTTOMLEFT", row.activity, "BOTTOMRIGHT", 10, 0)
		row.detail:SetPoint("BOTTOMRIGHT", -152, 8)
		row.detail:SetJustifyH("LEFT")
		row.roleIcons, row.roleCounts = {}, {}
		for roleIndex = 1, 3 do
			local icon = RoleIcon(row, 18)
			icon:SetPoint("TOP", row, "TOPRIGHT", -84 + (roleIndex - 1) * 30, -6)
			local count = Text(row, "GameFontHighlightSmall")
			count:SetPoint("TOP", icon, "BOTTOM", 0, -2)
			row.roleIcons[roleIndex], row.roleCounts[roleIndex] = icon, count
		end
		row.size = Text(row)
		row.size:SetWidth(40)
		row.size:SetPoint("RIGHT", -102, 0)
		row.size:SetJustifyH("RIGHT")
		row.badge = CreateBadge(row)
		row.badge:SetPoint("TOPRIGHT", 6, 6)
		row:SetScript("OnMouseWheel", Run(function(_, delta)
			state.listCursor = state.listCursor - delta
		end))
		-- The mouse over a row shows its details beside the window, like the controller's cursor.
		-- Only once the mouse has moved: a row appearing under a cursor left still (the window opening,
		-- new results) doesn't take the details from the controller's cursor.
		row:SetScript("OnEnter", Run(function()
			local x, y = GetCursorPosition()
			if x ~= state.cursorX or y ~= state.cursorY then
				state.hoverRow = row
			end
		end))
		row:SetScript("OnLeave", Run(function()
			if state.hoverRow == row then
				state.hoverRow = nil
			end
		end))
		window.resultFrames[index] = row
	end
end

local function BuildListing(content)
	local listing = CreateFrame("Frame", nil, content)
	listing:SetAllPoints()
	window.listing = listing

	local side = CreateFrame("Frame", nil, listing)
	side:SetPoint("TOPLEFT", 12, -10)
	side:SetPoint("BOTTOMLEFT", 12, 10)
	side:SetWidth(LIST_SIDE_WIDTH)
	window.listSide = side
	local title = Text(side, "GameFontNormal")
	title:SetPoint("TOPLEFT", 2, 0)
	title:SetText("List your group")
	window.listFrames = {}
	for index = 1, LIST_ROWS do
		local row = CreateRow(side, LIST_ROW_HEIGHT - 4, Run(function()
			state.createCursor = index
			ListNav.Accept()
		end))
		row:SetPoint("TOPLEFT", 0, -22 - (index - 1) * LIST_ROW_HEIGHT)
		row:SetPoint("RIGHT", side, "RIGHT")
		row.icon = RoleIcon(row, 18)
		row.icon:SetPoint("LEFT", 8, 0)
		row.label = Text(row)
		row.label:SetPoint("LEFT", 34, 0)
		row.value = Text(row, "GameFontHighlightSmall")
		row.value:SetPoint("RIGHT", -10, 0)
		row.value:SetJustifyH("RIGHT")
		row.value:SetPoint("LEFT", row.label, "RIGHT", 6, 0)
		row.toggle = CreateToggle(row)
		row.toggle:SetPoint("RIGHT", -10, 0)
		window.listFrames[index] = row
	end

	local pane = CreateFrame("Frame", nil, listing, "BackdropTemplate")
	pane:SetPoint("TOPLEFT", side, "TOPRIGHT", 14, -22)
	pane:SetPoint("BOTTOMRIGHT", -12, 10)
	Flat(pane, { 0.05, 0.05, 0.06, 0.9 })
	local statusTitle = Text(listing, "GameFontNormal")
	statusTitle:SetPoint("BOTTOMLEFT", pane, "TOPLEFT", 2, 6)
	statusTitle:SetText("Your listing")
	window.listStatus = Text(pane)
	window.listStatus:SetPoint("TOPLEFT", 14, -14)
	window.listStatus:SetPoint("RIGHT", -14, 0)
	window.listStatus:SetJustifyH("LEFT")
	window.listStatus:SetWordWrap(true)
	window.listStatus:SetSpacing(4)
	window.partyTitle = Text(pane, "GameFontNormal")
	window.partyTitle:SetPoint("TOPLEFT", 14, -110)
	window.partyFrames = {}
	for index = 1, 5 do
		local row = CreateFrame("Frame", nil, pane, "BackdropTemplate")
		row:SetHeight(36)
		Flat(row, CONTROL)
		row:SetPoint("TOPLEFT", 10, -134 - (index - 1) * 40)
		row:SetPoint("RIGHT", -10, 0)
		row.role = RoleIcon(row, 22)
		row.role:SetPoint("LEFT", 8, 0)
		row.name = Text(row)
		row.name:SetPoint("LEFT", 40, 0)
		row.roleText = Text(row, "GameFontHighlightSmall")
		row.roleText:SetPoint("RIGHT", -12, 0)
		window.partyFrames[index] = row
	end
end

local function BuildSettings(content)
	local settings = CreateFrame("Frame", nil, content)
	settings:SetAllPoints()
	window.settings = settings
	local side = CreateFrame("Frame", nil, settings)
	side:SetPoint("TOPLEFT", 12, -10)
	side:SetPoint("BOTTOMLEFT", 12, 10)
	side:SetWidth(LIST_SIDE_WIDTH + 60)
	window.settingsSide = side
	local title = Text(side, "GameFontNormal")
	title:SetPoint("TOPLEFT", 2, 0)
	title:SetText("LFG settings (also in the addon's settings, LFG tab)")
	window.settingFrames = {}
	for index = 1, 10 do
		local row = CreateRow(side, LIST_ROW_HEIGHT + 2, Run(function()
			state.settingsCursor = index
			SettingsNav.Accept()
		end))
		row:SetPoint("TOPLEFT", 0, -22 - (index - 1) * (LIST_ROW_HEIGHT + 6))
		row:SetPoint("RIGHT", side, "RIGHT")
		row.label = Text(row)
		row.label:SetPoint("LEFT", 12, 0)
		row.value = Text(row, "GameFontHighlightSmall")
		row.value:SetPoint("RIGHT", -10, 0)
		row.value:SetJustifyH("RIGHT")
		row.toggle = CreateToggle(row)
		row.toggle:SetPoint("RIGHT", -10, 0)
		window.settingFrames[index] = row
	end
	local pane = CreateFrame("Frame", nil, settings, "BackdropTemplate")
	pane:SetPoint("TOPLEFT", side, "TOPRIGHT", 14, -22)
	pane:SetPoint("BOTTOMRIGHT", -12, 10)
	Flat(pane, { 0.05, 0.05, 0.06, 0.9 })
	-- The group finder message: the message in a box, what is sent, and the tags to fill in.
	local editor = CreateFrame("Frame", nil, pane)
	editor:SetAllPoints()
	window.msgEditor = editor
	local editorTitle = Text(editor, "GameFontNormal")
	editorTitle:SetPoint("TOPLEFT", 16, -16)
	editorTitle:SetText("Group finder message")
	local editorNote = Text(editor, "GameFontDisableSmall")
	editorNote:SetPoint("TOPLEFT", editorTitle, "BOTTOMLEFT", 0, -4)
	editorNote:SetText("Whispered to a group's leader when you ask to join.")
	editor.box = CreateFrame("Frame", nil, editor, "BackdropTemplate")
	editor.box:SetPoint("TOPLEFT", 14, -58)
	editor.box:SetPoint("RIGHT", -14, 0)
	editor.box:SetHeight(84)
	Flat(editor.box, { 0.02, 0.02, 0.03, 1 })
	local previewTitle = Text(editor, "GameFontNormal")
	previewTitle:SetPoint("TOPLEFT", editor.box, "BOTTOMLEFT", 2, -16)
	previewTitle:SetText("What is sent")
	editor.preview = Text(editor)
	editor.preview:SetPoint("TOPLEFT", previewTitle, "BOTTOMLEFT", 0, -6)
	editor.preview:SetPoint("RIGHT", -16, 0)
	editor.preview:SetJustifyH("LEFT")
	editor.preview:SetWordWrap(true)
	local tagsTitle = Text(editor, "GameFontNormal")
	tagsTitle:SetPoint("TOPLEFT", editor.preview, "BOTTOMLEFT", 0, -18)
	tagsTitle:SetText("Tags, filled in when sent")
	editor.tags = Text(editor, "GameFontHighlightSmall")
	editor.tags:SetPoint("TOPLEFT", tagsTitle, "BOTTOMLEFT", 0, -6)
	editor.tags:SetPoint("RIGHT", -16, 0)
	editor.tags:SetJustifyH("LEFT")
	editor.tags:SetWordWrap(true)
	local tagsHelp = Text(editor, "GameFontDisableSmall")
	tagsHelp:SetPoint("TOPLEFT", editor.tags, "BOTTOMLEFT", 0, -6)
	tagsHelp:SetPoint("RIGHT", -16, 0)
	tagsHelp:SetJustifyH("LEFT")
	tagsHelp:SetWordWrap(true)
	tagsHelp:SetText("<activity> the group's dungeon, <level> and <class> yours, <roles> the roles you ticked, <name> your name, <leader> the leader's name.")
	editor.help = Text(editor, "GameFontHighlightSmall")
	editor.help:SetPoint("BOTTOMLEFT", 16, 14)
	editor.help:SetPoint("RIGHT", -16, 0)
	editor.help:SetJustifyH("LEFT")
	editor.help:SetWordWrap(true)
	editor:Hide()
	window.settingsTip = Text(pane)
	window.settingsTip:SetPoint("TOPLEFT", 14, -14)
	window.settingsTip:SetPoint("RIGHT", -14, 0)
	window.settingsTip:SetJustifyH("LEFT")
	window.settingsTip:SetWordWrap(true)
	window.settingsTip:SetSpacing(4)
	local input = CreateFrame("EditBox", "GamepadXIVLfgFilterMessageInput", editor.box)
	input:SetPoint("TOPLEFT", 10, -10)
	input:SetPoint("BOTTOMRIGHT", -10, 10)
	input:SetFontObject(ChatFontNormal or GameFontHighlight)
	input:SetMultiLine(true)
	input:SetAutoFocus(false)
	input:SetMaxLetters(255)
	input:SetScript("OnMouseDown", function(self)
		self:SetFocus()
	end)
	input:SetScript("OnEnterPressed", function(self)
		local text = strtrim((self:GetText() or ""):gsub("\n", " "))
		if text ~= "" then
			ns.db.lfgMessage = text
			Log("group finder message saved")
		end
		self:ClearFocus()
	end)
	input:SetScript("OnEscapePressed", function(self)
		self.cancelled = true
		self:ClearFocus()
	end)
	input:SetScript("OnEditFocusLost", function(self)
		if self.cancelled then
			self:SetText(ns.db.lfgMessage or "")
		end
		self.cancelled = nil
		Refresh()
	end)
	input:SetScript("OnEditFocusGained", function()
		Refresh()
	end)
	input:SetScript("OnTextChanged", function()
		editor.UpdatePreview()
	end)
	-- What is sent, from the text being typed, filled in with an example group.
	function editor.UpdatePreview()
		local saved = ns.db.lfgMessage
		ns.db.lfgMessage = (input:GetText() or ""):gsub("\n", " ")
		local category = CurrentCategory()
		local preview = ns.LfgMessage and ns.LfgMessage({ leaderName = "Leader", activityIDs = state.Picked(category and category.id) }) or ""
		ns.db.lfgMessage = saved
		editor.preview:SetText(preview ~= "" and ("|cffff80ff" .. preview .. "|r") or "|cff999999(empty)|r")
	end
	window.settingsInput = input
end

local function BuildChat(content)
	local chat = CreateFrame("Frame", nil, content)
	chat:SetAllPoints()
	window.chat = chat

	local side = CreateFrame("Frame", nil, chat)
	side:SetPoint("TOPLEFT", 12, -10)
	side:SetPoint("BOTTOMLEFT", 12, 10)
	side:SetWidth(SIDE_WIDTH)
	local title = Text(side, "GameFontNormal")
	title:SetPoint("TOPLEFT", 2, 0)
	title:SetText("Chats")
	window.chatFrames = {}
	for index = 1, CHAT_ROWS do
		local row = CreateRow(side, CHAT_ROW_HEIGHT - 4, nil)
		row:SetScript("OnClick", Run(function()
			state.selectedName = nil
			state.chatCursor = row.position
			-- History and Back to chats open with a click, as {PAD1} opens them.
			local _, _, list = SelectedChat()
			local item = list and list[row.position]
			if item and item.special then
				state.chatHistory = item.special == "history" or nil
				state.chatCursor, state.chatScroll = 1, 0
				Log(state.chatHistory and "chat history opened (mouse)" or "back to chats (mouse)")
			end
		end))
		row:SetPoint("TOPLEFT", 0, -22 - (index - 1) * CHAT_ROW_HEIGHT)
		row:SetPoint("RIGHT", side, "RIGHT")
		row.stripe = row:CreateTexture(nil, "ARTWORK")
		row.stripe:SetPoint("TOPLEFT", 1, -1)
		row.stripe:SetPoint("BOTTOMLEFT", 1, 1)
		row.stripe:SetWidth(4)
		row.stripe:Hide()
		row.name = Text(row)
		row.name:SetPoint("TOPLEFT", 12, -8)
		row.time = Text(row, "GameFontDisableSmall")
		row.time:SetPoint("TOPRIGHT", -12, -9)
		row.preview = Text(row, "GameFontDisableSmall")
		row.preview:SetPoint("BOTTOMLEFT", 10, 8)
		row.preview:SetPoint("RIGHT", -10, 0)
		row.preview:SetJustifyH("LEFT")
		row.badge = CreateBadge(row)
		row.badge:SetPoint("TOPRIGHT", 6, 6)
		row:SetScript("OnMouseWheel", Run(function(_, delta)
			state.selectedName = nil
			state.chatCursor = state.chatCursor - delta
		end))
		window.chatFrames[index] = row
	end
	window.chatSide = side
	window.chatEmpty = Text(side, "GameFontDisable")
	window.chatEmpty:SetPoint("TOP", 0, -60)
	window.chatEmpty:SetWidth(SIDE_WIDTH - 20)
	window.chatEmpty:SetWordWrap(true)
	window.chatEmpty:SetText("Whispers you send and receive show up here.")

	local pane = CreateFrame("Frame", nil, chat, "BackdropTemplate")
	pane:SetPoint("TOPLEFT", side, "TOPRIGHT", 14, -22)
	pane:SetPoint("BOTTOMRIGHT", -12, 10)
	Flat(pane, { 0.05, 0.05, 0.06, 0.9 })
	window.chatTitle = Text(chat, "GameFontNormal")
	window.chatTitle:SetPoint("BOTTOMLEFT", pane, "TOPLEFT", 2, 6)

	local log = CreateFrame("ScrollingMessageFrame", nil, pane)
	log:SetPoint("TOPLEFT", 12, -10)
	log:SetPoint("BOTTOMRIGHT", -12, 84)
	log:SetFontObject(GameFontHighlight)
	log:SetJustifyH("LEFT")
	log:SetFading(false)
	log:SetMaxLines(MAX_LINES)
	-- Links like the game's chat: a name opens its chat, Shift-click puts a link in the message, an item
	-- or other link shows its tooltip (the chat box's, ChatBox.lua).
	log:SetHyperlinksEnabled(true)
	log:SetScript("OnHyperlinkClick", function(_, link, text, button)
		local name = tostring(link):match("^player:([^:]+)")
		Log("link clicked:", tostring(link):match("^(%a+)") or "?", button)
		if IsShiftKeyDown() and window.input:HasFocus() then
			window.input:Insert(name and Short(name) or text)
		elseif name then
			Run(function() OpenChatWith(name) end)()
		elseif ns.ChatLinkClicked then
			ns.ChatLinkClicked(link, text, log)
		end
	end)
	log:EnableMouseWheel(true)
	log:SetScript("OnMouseWheel", function(self, delta)
		if delta > 0 then
			self:ScrollUp()
		else
			self:ScrollDown()
		end
	end)
	window.chatLog = log

	local replyBar = CreateFrame("Frame", nil, pane, "BackdropTemplate")
	replyBar:SetPoint("BOTTOMLEFT", 8, 44)
	replyBar:SetPoint("BOTTOMRIGHT", -8, 44)
	replyBar:SetHeight(32)
	Flat(replyBar, CONTROL, { GOLD[1], GOLD[2], GOLD[3], 0.35 })
	window.reply = Text(replyBar)
	window.reply:SetPoint("LEFT", 10, 0)
	window.reply:SetPoint("RIGHT", -10, 0)
	window.reply:SetJustifyH("LEFT")

	local input = CreateFrame("EditBox", "GamepadXIVLfgFilterInput", pane, "InputBoxTemplate")
	input:SetPoint("BOTTOMLEFT", 16, 10)
	input:SetPoint("BOTTOMRIGHT", -12, 10)
	input:SetHeight(26)
	input:SetAutoFocus(false)
	input:SetMaxLetters(255)
	-- Sends the whole message ({PAD1} or Enter); with ready-made messages in it (state.AddToMessage),
	-- between the raid markers once.
	function input:Submit()
		local text = strtrim(self:GetText() or "")
		local name = SelectedChat()
		if text ~= "" and name then
			local readyMade = self.readyMade == true
			SendTo(name, readyMade and Markers.Decorate(text, name) or text, readyMade and "typed with ready-made messages" or "typed")
		end
		self:SetText("")
		self.readyMade = nil
		self:ClearFocus()
	end
	input:SetScript("OnEnterPressed", input.Submit)
	input:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	input:SetScript("OnTextChanged", function(self)
		-- Emptied: no ready-made message in it any more. The hints change between Add and Send.
		local empty = strtrim(self:GetText() or "") == ""
		if (self:GetText() or "") == "" then
			self.readyMade = nil
		end
		if empty ~= self.wasEmpty then
			self.wasEmpty = empty
			Refresh()
		end
	end)
	input.hint = Text(input, "GameFontDisableSmall")
	input.hint:SetPoint("LEFT", 2, 0)
	-- {PADLSTICK} adds the quick reply while typing (Bind).
	input:SetScript("OnEditFocusGained", function(self)
		self.hint:Hide()
		if window:IsShown() then
			Bind("typing")
			Refresh()
		end
	end)
	input:SetScript("OnEditFocusLost", function(self)
		self.hint:SetShown(self:GetText() == "")
		if window:IsShown() then
			Bind("typing stopped")
			Refresh()
		end
	end)
	input.hint:SetText("Type a message and press Enter")
	window.input = input

	-- A past group (ChatHistory.lua): read only, who was in it above its chat, and a list of them
	-- ({PAD4}) to whisper one from.
	local roleKeys = { TANK = "tank", HEALER = "healer", DAMAGER = "dps" }
	local header = Text(pane)
	header:SetPoint("TOPLEFT", 12, -10)
	header:SetPoint("RIGHT", -12, 0)
	header:SetJustifyH("LEFT")
	header:SetWordWrap(true)
	if header.SetMaxLines then
		header:SetMaxLines(2)
	end
	header:Hide()
	local members = CreateFrame("Frame", nil, pane, "BackdropTemplate")
	members:SetPoint("TOPLEFT", 8, -48)
	members:SetPoint("BOTTOMRIGHT", -8, 8)
	Flat(members, PANEL)
	members:EnableMouseWheel(true)
	members:SetScript("OnMouseWheel", Run(function(_, delta)
		state.memberCursor = state.memberCursor - delta
	end))
	members:Hide()
	members.rows = {}
	for index = 1, 11 do
		local row = CreateRow(members, 28, nil)
		row:SetPoint("TOPLEFT", 6, -6 - (index - 1) * 32)
		row:SetPoint("RIGHT", members, "RIGHT", -6, 0)
		row:SetScript("OnClick", Run(function()
			-- A click picks a member, a click on the picked one whispers them.
			if state.memberCursor == row.position then
				state.MembersNav.Accept()
			else
				state.memberCursor = row.position
			end
		end))
		row:SetScript("OnMouseWheel", Run(function(_, delta)
			state.memberCursor = state.memberCursor - delta
		end))
		row.role = RoleIcon(row, 18)
		row.role:SetPoint("LEFT", 8, 0)
		row.name = Text(row)
		row.name:SetPoint("LEFT", 34, 0)
		row.class = Text(row, "GameFontDisableSmall")
		row.class:SetPoint("RIGHT", -10, 0)
		members.rows[index] = row
	end
	function window.DrawGroupPane(group)
		local layout = group and "group" or "chat"
		if log.layout ~= layout then
			log.layout = layout
			log:ClearAllPoints()
			log:SetPoint("TOPLEFT", 12, group and -48 or -10)
			log:SetPoint("BOTTOMRIGHT", -12, group and 10 or 84)
			replyBar:SetShown(not group)
		end
		header:SetShown(group ~= nil)
		local open = group ~= nil and state.membersFor ~= nil
		members:SetShown(open)
		log:SetShown(not open)
		if not group then
			return
		end
		local list = group.members or {}
		local names = {}
		for _, member in ipairs(list) do
			local role = roleKeys[member.role or ""]
			names[#names + 1] = (role and ("|A:" .. ROLE_ATLAS[role] .. ":14:14|a") or "") .. ClassColored(member.name, member.class)
		end
		header:SetText(#list > 0 and ("|cffffd100" .. #list .. " members:|r  " .. table.concat(names, "   "))
			or "|cff999999Who was in this group is not known: it was saved before groups were kept.|r")
		if not open then
			return
		end
		Fit("memberCursor", "memberScroll", #list, #members.rows)
		for index, row in ipairs(members.rows) do
			local position = state.memberScroll + index
			local member = list[position]
			row:SetShown(member ~= nil)
			row.position = position
			if member then
				SetRowSelected(row, position == state.memberCursor)
				local role = roleKeys[member.role or ""]
				row.role:SetShown(role ~= nil)
				if role then
					row.role:SetAtlas(ROLE_ATLAS[role])
				end
				local rating = RatingOf(member.name)
				row.name:SetText(ClassColored(member.name, member.class) .. (member.me and "  |cff999999(you)|r" or "")
					.. (rating > 0 and ("  " .. RATINGS[rating].tag) or ""))
				row.class:SetText(member.class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[member.class] or "")
			end
		end
	end
end

local function BuildRatings(content)
	local ratings = CreateFrame("Frame", nil, content)
	ratings:SetAllPoints()
	window.ratings = ratings
	-- Where the note list opens.
	window.rateSide = CreateFrame("Frame", nil, ratings)
	window.rateSide:SetPoint("TOPLEFT", 12, -10)
	window.rateSide:SetPoint("BOTTOMLEFT", 12, 10)
	window.rateSide:SetWidth(360)
	local title = Text(ratings, "GameFontNormal")
	title:SetPoint("TOPLEFT", 14, -10)
	title:SetText("Players you grouped with")
	local note = Text(ratings, "GameFontDisableSmall")
	note:SetPoint("LEFT", title, "RIGHT", 12, 0)
	note:SetText("Ratings are kept for every character on your account. You are warned when someone you avoid joins.")
	window.rateFrames = {}
	for index = 1, RATE_ROWS do
		local row = CreateRow(ratings, RATE_ROW_HEIGHT - 4, nil)
		row:SetScript("OnClick", Run(function()
			state.rateCursor = row.position
		end))
		row:SetPoint("TOPLEFT", 12, -32 - (index - 1) * RATE_ROW_HEIGHT)
		row:SetPoint("RIGHT", ratings, "RIGHT", -12, 0)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(28, 28)
		row.icon:SetPoint("LEFT", 8, 0)
		row.name = Text(row)
		row.name:SetPoint("LEFT", 46, 6)
		row.where = Text(row, "GameFontHighlightSmall")
		row.where:SetPoint("LEFT", 46, -9)
		row.where:SetPoint("RIGHT", row, "RIGHT", -260, 0)
		row.where:SetJustifyH("LEFT")
		row.pills = {}
		for value = 3, 1, -1 do
			local pill = CreateFrame("Button", nil, row, "BackdropTemplate")
			pill:SetSize(74, 24)
			Flat(pill, CONTROL)
			pill:SetPoint("RIGHT", row, "RIGHT", -12 - (3 - value) * 80, 0)
			pill.text = Text(pill, "GameFontHighlightSmall")
			pill.text:SetPoint("CENTER")
			pill.text:SetText(RATINGS[value].markup .. " " .. RATINGS[value].name)
			pill:SetScript("OnClick", Run(function()
				state.rateCursor = row.position
				local rows = RateRows()
				local target = rows[row.position]
				if target then
					SetRating(target.name, RatingOf(target.name) == value and 0 or value, target.class)
					Log("rated with the mouse", target.name, value)
				end
			end))
			row.pills[value] = pill
		end
		row.badge = CreateBadge(row)
		row.badge:SetPoint("TOPRIGHT", 6, 6)
		row:SetScript("OnMouseWheel", Run(function(_, delta)
			state.rateCursor = state.rateCursor - delta
		end))
		window.rateFrames[index] = row
	end
	-- {PAD4}: a note on the selected player, typed here.
	local noteInput = CreateFrame("EditBox", "GamepadXIVLfgFilterNoteInput", ratings, "InputBoxTemplate")
	noteInput:SetPoint("BOTTOMLEFT", 20, 10)
	noteInput:SetPoint("BOTTOMRIGHT", -14, 10)
	noteInput:SetHeight(26)
	noteInput:SetAutoFocus(false)
	noteInput:SetMaxLetters(120)
	noteInput:SetScript("OnEnterPressed", function(self)
		local target = self.target
		if target then
			local text = strtrim((self:GetText() or ""):gsub(";", ","))
			if text ~= "" then
				state.ToggleNote(target, text, true)
				Log("note added for", target.name)
			end
		end
		self:ClearFocus()
	end)
	noteInput:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	noteInput:SetScript("OnEditFocusLost", function(self)
		self.target = nil
		self:Hide()
		Refresh()
	end)
	noteInput:Hide()
	window.noteInput = noteInput
	window.rateEmpty = Text(ratings, "GameFontDisable")
	window.rateEmpty:SetPoint("CENTER")
	window.rateEmpty:SetText("Players you group with show up here.")
end

local function BuildConfirm()
	local confirm = CreateFrame("Frame", nil, window, "BackdropTemplate")
	confirm:SetPoint("BOTTOM", 0, FOOTER_HEIGHT + 12)
	confirm:SetSize(520, 110)
	confirm:SetFrameLevel(window:GetFrameLevel() + 30)
	Flat(confirm, { 0.06, 0.06, 0.08, 0.98 }, { GOLD[1], GOLD[2], GOLD[3], 0.7 })
	confirm.title = Text(confirm, "GameFontNormalLarge")
	confirm.title:SetPoint("TOP", 0, -14)
	confirm.message = Text(confirm)
	confirm.message:SetPoint("TOP", confirm.title, "BOTTOM", 0, -10)
	confirm.message:SetWidth(490)
	confirm.message:SetWordWrap(true)
	confirm.keys = Text(confirm)
	confirm.keys:SetPoint("BOTTOM", 0, 14)
	confirm:Hide()
	window.confirm = confirm
end

local function CreateWindow()
	window = CreateFrame("Frame", "GamepadXIVLfgFilterFrame", UIParent, "BackdropTemplate")
	Flat(window, PANEL, { GOLD[1], GOLD[2], GOLD[3], 0.35 })
	window:SetSize(WIDTH, HEIGHT)
	window:SetPoint("CENTER")
	window:SetFrameStrata("DIALOG")
	window:SetToplevel(true)
	window:SetClampedToScreen(true)
	window:EnableMouse(true)
	window:SetMovable(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		Refresh() -- the details panel picks its side again
	end)
	window:Hide()

	local titleBar = window:CreateTexture(nil, "BACKGROUND", nil, 1)
	titleBar:SetPoint("TOPLEFT", 1, -1)
	titleBar:SetPoint("TOPRIGHT", -1, -1)
	titleBar:SetHeight(TITLE_HEIGHT)
	titleBar:SetColorTexture(0.1, 0.1, 0.125, 1)
	local icon = window:CreateTexture(nil, "ARTWORK")
	icon:SetSize(22, 22)
	icon:SetPoint("LEFT", titleBar, "LEFT", 12, 0)
	icon:SetAtlas("gamepad-radial-icon-groupfinder")
	local title = Text(window, "GameFontNormalLarge")
	title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
	title:SetText("LFG Filter")
	window.titleText = title
	window.mode = Text(window, "GameFontHighlightSmall")
	window.mode:SetPoint("LEFT", title, "RIGHT", 14, -1)
	local close = CreateFrame("Button", nil, window, "BackdropTemplate")
	close:SetSize(26, 26)
	Flat(close, CONTROL)
	close:SetPoint("RIGHT", titleBar, "RIGHT", -6, 0)
	local closeText = Text(close, "GameFontNormal")
	closeText:SetPoint("CENTER")
	closeText:SetText("X")
	close:SetScript("OnClick", function() window:Hide() end)

	-- Tabs.
	window.tabs = {}
	local names = TAB_NAMES
	local tabWidth = 140
	window.tabLeft = Text(window)
	window.tabLeft:SetPoint("TOPLEFT", 16, -TITLE_HEIGHT - 10)
	for index, name in ipairs(names) do
		local tab = CreateRow(window, TAB_HEIGHT - 8, Run(function() SelectTab(index) end))
		tab:SetWidth(tabWidth)
		tab:SetPoint("TOPLEFT", 52 + (index - 1) * (tabWidth + 8), -TITLE_HEIGHT - 6)
		tab.label = Text(tab, "GameFontNormal")
		tab.label:SetPoint("CENTER")
		tab.label:SetText(name)
		tab.badge = CreateBadge(tab)
		tab.badge:SetPoint("TOPRIGHT", 8, 8)
		window.tabs[index] = tab
	end
	window.chatTabs = {}
	for index, info in ipairs(state.chatTabs) do
		local tab = CreateRow(window, TAB_HEIGHT - 8, Run(function() state.SelectChatTab(index) end))
		tab:SetWidth(tabWidth)
		tab:SetPoint("TOPLEFT", 52 + (index - 1) * (tabWidth + 8), -TITLE_HEIGHT - 6)
		tab.label = Text(tab, "GameFontNormal")
		tab.label:SetPoint("CENTER")
		tab.label:SetText(info.name)
		tab.badge = CreateBadge(tab)
		tab.badge:SetPoint("TOPRIGHT", 8, 8)
		tab:Hide()
		window.chatTabs[index] = tab
	end
	window.tabRight = Text(window)
	window.tabRight:SetPoint("LEFT", window.tabs[#window.tabs], "RIGHT", 12, 0)
	local tabLine = window:CreateTexture(nil, "ARTWORK")
	tabLine:SetPoint("TOPLEFT", 1, -TITLE_HEIGHT - TAB_HEIGHT)
	tabLine:SetPoint("TOPRIGHT", -1, -TITLE_HEIGHT - TAB_HEIGHT)
	tabLine:SetHeight(1)
	tabLine:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.35)

	local content = CreateFrame("Frame", nil, window)
	content:SetPoint("TOPLEFT", 0, -TITLE_HEIGHT - TAB_HEIGHT - 4)
	content:SetPoint("BOTTOMRIGHT", 0, FOOTER_HEIGHT)
	BuildGroups(content)
	BuildListing(content)
	BuildSettings(content)
	BuildChat(content)
	BuildRatings(content)
	BuildConfirm()

	-- The search box, at the top right over the Group finder, Chat and Ratings lists.
	local findBox = CreateFrame("EditBox", "GamepadXIVLfgFilterFind", content, "InputBoxTemplate")
	-- Short and high, so it keeps clear of the first row under it.
	findBox:SetSize(170, 18)
	findBox:SetPoint("TOPRIGHT", -18, -4)
	findBox:SetFontObject(GameFontHighlightSmall)
	findBox:SetAutoFocus(false)
	findBox:SetMaxLetters(40)
	findBox.placeholder = findBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	findBox.placeholder:SetPoint("LEFT", 2, 0)
	findBox:SetScript("OnTextChanged", function(self, typed)
		self.placeholder:SetShown((self:GetText() or "") == "")
		if not typed then
			return
		end
		state.find[state.tab] = self:GetText()
		if state.tab == TAB_FINDER then
			state.listCursor, state.listScroll = 1, 0
			BuildResults()
		elseif state.tab == TAB_CHAT then
			state.chatCursor, state.chatScroll, state.selectedName = 1, 0, nil
		else
			state.rateCursor, state.rateScroll = 1, 0
		end
		Refresh()
	end)
	findBox:SetScript("OnEnterPressed", findBox.ClearFocus)
	findBox:SetScript("OnEscapePressed", findBox.ClearFocus)
	findBox:SetScript("OnEditFocusGained", function() Refresh() end)
	findBox:SetScript("OnEditFocusLost", function() Refresh() end)
	window.findBox = findBox

	local footerBar = window:CreateTexture(nil, "BACKGROUND", nil, 1)
	footerBar:SetPoint("BOTTOMLEFT", 1, 1)
	footerBar:SetPoint("BOTTOMRIGHT", -1, 1)
	footerBar:SetHeight(FOOTER_HEIGHT)
	footerBar:SetColorTexture(0.1, 0.1, 0.125, 1)
	window.footer = Text(window)
	window.footer:SetPoint("CENTER", footerBar, "CENTER")

	for name, action in pairs(Nav) do
		local button = CreateFrame("Button", "GamepadXIVLfgFilterNav" .. name, window)
		local onClick = Run(function()
			if not window:IsShown() then
				return
			end
			-- The auto refresh that came due runs from this press (the game takes a search only then).
			if state.refreshDue and state.tab == TAB_FINDER and not state.searching then
				state.refreshDue = nil
				DoSearch("auto refresh")
			end
			-- Typing a search: {PAD1}, {PAD2} and {PADRTRIGGER} leave the box, the text stays.
			if window.findBox:HasFocus() and (name == "Accept" or name == "Back" or name == "Find") then
				window.findBox:ClearFocus()
				return
			end
			-- The controller's cursor picks the details again, not a mouse left over a row.
			state.hoverRow = nil
			state.cursorX, state.cursorY = GetCursorPosition()
			FixFocus()
			if state.picker and PickerNav[name] then
				PickerNav[name]()
			elseif state.tab == TAB_CHAT and state.membersFor and state.MembersNav[name] then
				state.MembersNav[name]()
			elseif state.tab == TAB_LIST and ListNav[name] then
				ListNav[name]()
			elseif state.tab == TAB_SETTINGS and SettingsNav[name] then
				SettingsNav[name]()
			else
				action()
			end
			FixFocus()
		end)
		if HOLD_NAV[name] then
			ns.RepeatOnHold(button, onClick, function() return HoldContext(name) end)
		else
			button:RegisterForClicks("AnyDown")
			button:SetScript("OnClick", onClick)
		end
	end

	-- L3: the game's own group finder, through a secure click on its micro menu button (from the
	-- hardware press, so Forever's window opens untainted), and this window closes.
	if LFDMicroButton then
		local game = CreateFrame("Button", "GamepadXIVLfgFilterGameWindow", UIParent, "SecureActionButtonTemplate")
		game:RegisterForClicks("AnyDown", "AnyUp")
		game:SetAttribute("useOnKeyDown", true)
		game:SetAttribute("type", "click")
		game:SetAttribute("clickbutton", LFDMicroButton)
		game:Hide()
		game:HookScript("OnClick", function(_, _, down)
			if down then
				Log("game's group finder opened from LFG Filter")
				C_Timer.After(0, function()
					window:Hide()
				end)
			end
		end)
		window.gameButton = game
	end
	window.gameHint = Text(window, "GameFontHighlightSmall")
	window.gameHint:SetPoint("RIGHT", window, "TOPRIGHT", -44, -TITLE_HEIGHT / 2)

	-- As the chat box: a bright frame while the window has the controller, and a tag above its top left
	-- corner with the button that leaves it, or the one that takes the controller back from the game.
	window.selected = CreateFrame("Frame", nil, window, "BackdropTemplate")
	window.selected:SetPoint("TOPLEFT", -3, 3)
	window.selected:SetPoint("BOTTOMRIGHT", 3, -3)
	window.selected:SetBackdrop({ edgeFile = WHITE, edgeSize = 2 })
	window.selected:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.95)
	window.selected:EnableMouse(false)
	window.selectTag = CreateFrame("Frame", nil, window, "BackdropTemplate")
	window.selectTag:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	window.selectTag:SetBackdropColor(0.04, 0.04, 0.06, 0.92)
	window.selectTag:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.95)
	window.selectTag:SetPoint("BOTTOMLEFT", window, "TOPLEFT", -3, 5)
	window.selectTag:SetSize(120, 24)
	window.selectTag.text = window.selectTag:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	window.selectTag.text:SetPoint("CENTER")
	local takeBack = CreateFrame("Button", "GamepadXIVLfgFilterTakeBack", window)
	takeBack:RegisterForClicks("AnyDown")
	takeBack:SetScript("OnClick", Run(function()
		state.forced = true
		Log("controller taken back from the game with Back")
		Bind("taken back")
	end))

	local elapsed = 0
	window:SetScript("OnUpdate", function(_, delta)
		elapsed = elapsed + delta
		if elapsed < REBIND_EVERY then
			return
		end
		elapsed = 0
		state.TickRefresh()
		local wasYielded = state.yielded
		Bind("check")
		if wasYielded ~= state.yielded then
			Refresh()
		end
		if state.searching and GetTime() - state.searchStart > SEARCH_TIMEOUT then
			state.searching = false
			state.searchFailed = true
			Log("search timed out")
			Refresh()
		end
	end)
	window:SetScript("OnShow", function()
		state.cursorX, state.cursorY = GetCursorPosition()
		Log("window shown, in group:", tostring(IsInGroup()), "gamepad UI:", tostring(ns.IsGamepadUI and ns.IsGamepadUI()))
		ClearCaches()
		Bind("shown")
		BuildResults()
		Refresh()
	end)
	window:SetScript("OnHide", function()
		state.forced = nil
		if ns.ChatLinkUnpin then
			ns.ChatLinkUnpin()
		end
		state.confirm = nil
		state.membersFor = nil
		state.yielded = nil
		state.picker = nil
		state.hoverRow = nil
		window.input:ClearFocus()
		Unbind("hidden")
		Log("window hidden")
	end)

	if InputDeviceIconSetManager and InputDeviceIconSetManager.RegisterActiveInputDeviceIconSetUpdatedCallback then
		InputDeviceIconSetManager:RegisterActiveInputDeviceIconSetUpdatedCallback(function()
			ns.RefreshLfgFilter()
		end, window)
	end
	Log("window created")
end

function ns.LfgFilterShown()
	return window and window:IsShown() or false
end

-- Opens the window, or closes it if it is open. With a tab number (TAB_CHAT, say), opens on that tab.
function ns.OpenLfgFilter(tab, chatMode)
	if not ns.db then
		return
	end
	if InCombatLockdown() then
		ns.Print((chatMode and "The Chat window" or "LFG Filter") .. " is not available in combat.")
		return
	end
	chatMode = chatMode and true or false
	if not window then
		local ok, err = pcall(CreateWindow)
		if not ok then
			Log("create failed:", err)
			ns.Print("LFG Filter could not open, see /gxiv lfgfilterlog:", tostring(err))
			return
		end
	end
	if window:IsShown() and state.chatMode ~= chatMode then
		-- Switching between LFG Filter and the Chat window.
		state.chatMode = chatMode
		state.picker = nil
		state.tab = chatMode and TAB_CHAT or (tab or TAB_FINDER)
		Log("window mode:", chatMode and "chat" or "lfg")
		if state.tab == TAB_FINDER then
			BuildResults()
			if not state.lastSearchOurs then
				DoSearch("switched to LFG Filter")
			end
		end
		Refresh()
		return
	end
	if window:IsShown() and not tab then
		window:Hide()
		return
	end
	state.chatMode = chatMode
	if chatMode then
		state.tab = TAB_CHAT
	elseif tab then
		state.tab = tab
	elseif not state.restored or state.lastChatMode then
		-- The tab and quick reply you last used; the filters are saved as you change them.
		state.tab = TAB_FINDER
		for index, key in ipairs(TAB_KEYS) do
			if ns.db.lfgFilterTab == key then
				state.tab = index
			end
		end
		state.replyIndex = Clamp(tonumber(ns.db.lfgFilterReply) or 1, 1, #QUICK_REPLIES)
	end
	if not chatMode then
		state.restored = true
	end
	state.lastChatMode = chatMode
	window:Show()
	if not state.lastSearchOurs and state.tab == TAB_FINDER then
		DoSearch(state.searchedOnce and "results were another window's" or "first open")
	end
end

---------------------------------------------------------------------------------------------------
-- The Chat window, and the game's chat replaced by it ("Chat" setting, chatUI = "gxiv").
-- The game's chat frames are made see-through (SetAlpha, kept at 0 by a hook on it) rather than hidden,
-- so none of the game's chat code runs from here. They come back while the game's chat box is open
-- (its own "/" or Open Chat key, or L3 in the Chat window), which keeps slash commands working.

-- What the chat box (ChatBox.lua) uses of the chat here.
ns.ChatAPI = {
	-- Every conversation the Chat window lists, without History.
	List = function()
		-- All of them: not narrowed by the Chat window's tab or its search box.
		local mode, history, tab, find = state.chatMode, state.chatHistory, state.chatTab, state.find[TAB_CHAT]
		state.chatMode, state.chatHistory, state.chatTab, state.find[TAB_CHAT] = true, nil, 1, nil
		local ok, list = pcall(SortedChats)
		state.chatMode, state.chatHistory, state.chatTab, state.find[TAB_CHAT] = mode, history, tab, find
		if not ok then
			error(list)
		end
		return list
	end,
	Send = function(name, text, why) return SendTo(name, text, why) end,
	Info = ChannelInfo, Name = ChatName, Chats = Chats, Icons = Markers.Icons, Color = ClassColored, Short = Short,
	Log = Log, Unread = UnreadTotal,
	-- For past groups (ChatHistory.lua): the "Chat lines kept" and "Chat kept for" settings on a
	-- conversation, and names as conversations are kept (Name-Realm).
	Prune = PruneChat, FullName = FullName,
	-- Ready-made messages: { name = category, "message", ... }. They go into the message being typed
	-- (ns.ChatInsert, ChatBox.lua), never out on their own.
	Phrases = PHRASES, QuickReplies = QUICK_REPLIES,
	-- The quick reply the D-pad picked, shared with the Chat window.
	ReplyIndex = function(delta)
		local index = Clamp(tonumber(ns.db.lfgFilterReply) or 1, 1, #QUICK_REPLIES)
		if delta then
			index = (index - 1 + delta) % #QUICK_REPLIES + 1
			ns.db.lfgFilterReply = index
			state.replyIndex = index
		end
		return index
	end,
	-- A ready-made message as it goes into the message: "<ask>" becomes the group finder message.
	ExpandPhrase = function(text, name)
		if text == "<ask>" then
			return ReplyText(text, name)
		end
		return text
	end,
	-- A message with ready-made ones in it, between the raid markers: only with "Controller icons on
	-- ready-made messages" on, never in General and the other public channels, and as typed when the
	-- markers would take it past 255 letters.
	Decorate = Markers.Decorate,
	-- Copies of ready-made message lists, keeping only text that can be sent: categories need a name,
	-- empty messages are left out and long ones cut to what chat takes.
	CopyMessages = function(phrases, replies)
		local function Usable(text)
			return type(text) == "string" and strtrim(text) ~= "" and text:sub(1, 255) or nil
		end
		local outPhrases, outReplies = {}, {}
		for _, group in ipairs(type(phrases) == "table" and phrases or {}) do
			if type(group) == "table" and Usable(group.name) then
				local copy = { name = Usable(group.name) }
				for _, text in ipairs(group) do
					copy[#copy + 1] = Usable(text)
				end
				outPhrases[#outPhrases + 1] = copy
			end
		end
		for _, text in ipairs(type(replies) == "table" and replies or {}) do
			outReplies[#outReplies + 1] = Usable(text)
		end
		return outPhrases, outReplies
	end,
	-- Puts the player's own lists (MessagesEditor.lua, GamepadXIVAccountDB) in place of the ones
	-- above; nil puts the defaults back. The same two tables stay in use, filled in place, so whatever
	-- holds them (the chat box) sees the change. Quick replies are never left empty.
	SetMessages = function(phrases, replies)
		local api = ns.ChatAPI
		if not api.defaultPhrases then
			api.defaultPhrases, api.defaultReplies = api.CopyMessages(PHRASES, QUICK_REPLIES)
		end
		local newPhrases = api.CopyMessages(phrases or api.defaultPhrases)
		local _, newReplies = api.CopyMessages(nil, replies)
		if #newReplies == 0 then
			_, newReplies = api.CopyMessages(nil, api.defaultReplies)
		end
		wipe(PHRASES)
		for index, group in ipairs(newPhrases) do
			PHRASES[index] = group
		end
		wipe(QUICK_REPLIES)
		for index, text in ipairs(newReplies) do
			QUICK_REPLIES[index] = text
		end
		state.replyIndex = Clamp(tonumber(state.replyIndex) or 1, 1, #QUICK_REPLIES)
		if ns.db then
			api.ReplyIndex(0) -- the saved choice, clamped to the new list
		end
		if ns.RefreshLfgFilter then
			ns.RefreshLfgFilter()
		end
	end,
	OpenWindow = function(name)
		if name then
			state.selectedName = name
			state.ShowChatTabOf(name)
		end
		ns.OpenGamepadChat()
	end,
}

local UpdateChatKey -- in the block below, which keeps its locals out of the file's 200
do
-- Opens the Chat window, or closes it. With focus, the cursor goes in its message box.
function ns.OpenGamepadChat(focus)
	if window and window:IsShown() and state.chatMode and not focus then
		window:Hide()
		return
	end
	ns.OpenLfgFilter(TAB_CHAT, true)
	if focus and window and window:IsShown() and SelectedChat() then
		window.input:SetFocus()
	end
end

local feed
local chatHidden, chatRevealed = false, false
local alphaHooked = {}

local function GameChatFrames()
	local frames = {}
	for index = 1, NUM_CHAT_WINDOWS or 10 do
		frames[#frames + 1] = _G["ChatFrame" .. index]
		frames[#frames + 1] = _G["ChatFrame" .. index .. "Tab"]
		frames[#frames + 1] = _G["ChatFrame" .. index .. "EditBox"] -- in the "im" chat style it is not inside its frame
	end
	for _, name in ipairs({ "GeneralDockManager", "ChatFrameMenuButton", "ChatFrameChannelButton",
			"ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton" }) do
		frames[#frames + 1] = _G[name]
	end
	return frames
end

local function SetGameChatShown(shown)
	for _, frame in ipairs(GameChatFrames()) do
		if not alphaHooked[frame] and frame.SetAlpha then
			alphaHooked[frame] = true
			hooksecurefunc(frame, "SetAlpha", function(self, alpha)
				if chatHidden and not chatRevealed and type(alpha) == "number" and alpha > 0 then
					self:SetAlpha(0)
				end
			end)
		end
		frame:SetAlpha(shown and 1 or 0)
	end
end

local function GameChatTyping()
	local box = (ChatFrameUtil and ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow())
		or (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow())
	return box and box:IsShown() and box:HasFocus()
end

-- For finding what still shows where the chat is: every shown frame over ChatFrame1 that can be seen.
function ns.LogChatArea(reason)
	local anchor = ChatFrame1
	if not anchor or not anchor:GetLeft() then
		Log("chat area: no ChatFrame1")
		return
	end
	local left, right, top, bottom = anchor:GetLeft(), anchor:GetRight(), anchor:GetTop(), anchor:GetBottom()
	local found = 0
	local frame = EnumerateFrames()
	while frame and found < 40 do
		local ok, visible = pcall(function()
			return not frame:IsForbidden() and frame:IsVisible() and frame:GetEffectiveAlpha() > 0.05 and frame:GetLeft()
				and frame:GetLeft() < right and frame:GetRight() > left and frame:GetBottom() < top and frame:GetTop() > bottom
				and (frame:GetWidth() < 1200)
		end)
		if ok and visible then
			local name = frame:GetName() or (frame:GetParent() and frame:GetParent():GetName() and (frame:GetParent():GetName() .. ".child")) or "?"
			if name:find("Chat") or name:find("chat") or name == "?" then
				found = found + 1
				Log("chat area:", reason, name, "alpha", format("%.2f", frame:GetEffectiveAlpha()), frame:GetFrameStrata())
			end
		end
		frame = EnumerateFrames(frame)
	end
	Log("chat area:", reason, found, "chat frames still seen; ChatFrame1 alpha", format("%.2f", anchor:GetAlpha()),
		"chatStyle", tostring(GetCVar and GetCVar("chatStyle")))
end


local chatKeyOwner = CreateFrame("Frame")
local chatOpenButton = CreateFrame("Button", "GamepadXIVChatOpenKey", UIParent)
chatOpenButton:RegisterForClicks("AnyDown")
chatOpenButton:SetScript("OnClick", function()
	-- A loot roll came up as Back was pressed: Back is its now (Input.lua), not chat. Only rolls, so
	-- Enter still opens chat with a popup up.
	for _, name in ipairs({ "GamepadGroupLootRollFrame", "GroupLootFrame1", "GroupLootFrame2", "GroupLootFrame3", "GroupLootFrame4" }) do
		local frame = _G[name]
		if frame and frame.IsVisible and frame:IsVisible() and not InCombatLockdown() then
			Log("chat key pressed with", name, "showing: left for Back")
			if ns.RefreshBack then
				ns.RefreshBack()
			end
			return
		end
	end
	-- A loot roll mid-fight: Back can't be Forever's now, so it opens the roll picker.
	local rollFrame = GamepadGroupLootRollFrame
	if ns.PlayLog then
		ns.PlayLog("chat key pressed:", InCombatLockdown() and "in combat" or "out of combat",
			"roll window", tostring(rollFrame and rollFrame:IsVisible()), "rollID", tostring(rollFrame and rollFrame.rollID),
			"roll waiting", tostring(ns.RollWaiting and ns.RollWaiting()),
			"chat box", tostring(ns.ChatBoxActive and ns.ChatBoxActive()))
	end
	-- A party invite or trade mid-fight: the bindings can't answer it yet, so Back opens the answer picker.
	if ns.CombatAnswerWaiting and ns.CombatAnswerWaiting() then
		if ns.ChatBoxActive and ns.ChatBoxActive() then
			ns.CloseChatBox()
		end
		if ns.OpenCombatAnswer() then
			return
		end
	end
	if InCombatLockdown() and ns.RollWaiting and ns.RollWaiting() then
		if ns.ChatBoxActive and ns.ChatBoxActive() then
			ns.CloseChatBox()
		end
		if ns.OpenRollPicker() then
			return
		end
	end
	if ns.ChatBoxActive and ns.ChatBoxActive() then
		ns.CloseChatBox()
		return
	end
	Log("chat box opened with the Open Chat key or Back")
	if ns.FocusChatBox then
		ns.FocusChatBox()
	else
		ns.OpenGamepadChat(true)
	end
end)

-- The game's Open Chat key opens the Chat window while it replaces the game's chat.
function UpdateChatKey(reason)
	if reason == "UPDATE_BINDINGS" and GetTime() - (chatKeyOwner.setAt or 0) < 2 then
		return
	end
	if InCombatLockdown() then
		state.chatKeyPending = true
		return
	end
	local keys = chatHidden and { GetBindingKey("OPENCHAT") } or {}
	local same = #keys == (chatKeyOwner.count or 0)
	for _, key in ipairs(keys) do
		same = same and GetBindingAction(key, true) == "CLICK GamepadXIVChatOpenKey:LeftButton"
	end
	if same then
		return
	end
	ClearOverrideBindings(chatKeyOwner)
	chatKeyOwner.count = #keys
	chatKeyOwner.setAt = GetTime()
	for _, key in ipairs(keys) do
		SetOverrideBindingClick(chatKeyOwner, false, key, "GamepadXIVChatOpenKey", "LeftButton")
	end
	Log("open chat key ->", #keys > 0 and table.concat(keys, ", ") or "the game's")
end

-- The Chat setting: the game's chat, or the Chat window with a feed of new messages where the game's
-- chat was. It also swaps the ring's Chat entry.
function ns.ApplyChatChoice(reason)
	if not ns.db then
		return
	end
	local ours = ns.db.chatUI == "gxiv"
	if not feed then
		feed = CreateFrame("Frame") -- runs the check below; the chat box itself is ChatBox.lua
		-- The chat box shows what the game's main chat frame gets: chat, system lines, addon prints.
		if ChatFrame1 then
			hooksecurefunc(ChatFrame1, "AddMessage", function(_, text, r, g, b)
				if chatHidden and not Secret(text) and type(text) == "string" and ns.ChatBoxFeed then
					ns.ChatBoxFeed(text, r, g, b)
				end
			end)
		end
		local elapsed = 0
		feed:SetScript("OnUpdate", function(_, delta)
			elapsed = elapsed + delta
			if elapsed < 0.2 or not chatHidden then
				return
			end
			elapsed = 0
			-- The game's chat box is open ("/" key): show the game's chat until it closes.
			local typing = GameChatTyping() and true or false
			if typing ~= chatRevealed then
				chatRevealed = typing
				SetGameChatShown(typing)
				if ns.ChatBoxSetShown then
					ns.ChatBoxSetShown(not typing)
				end
				Log(typing and "game's chat shown while typing" or "game's chat hidden again")
				if typing and window and window:IsShown() and state.chatMode then
					window:Hide()
				end
				-- A link Share in Chat put in the game's box, not sent from there, moves to the chat box.
				if typing and ns.ChatBoxGameChatOpened then
					ns.ChatBoxGameChatOpened()
				elseif not typing and ns.ChatBoxGameChatClosed then
					ns.ChatBoxGameChatClosed()
				end
			end
		end)
	end
	local wasHidden = chatHidden
	chatHidden = ours
	chatRevealed = false
	if ns.ChatBoxSetShown then
		ns.ChatBoxSetShown(ours)
	end
	-- The game's chat is only touched when it is replaced, or given back.
	if ours or wasHidden then
		SetGameChatShown(not ours)
	end
	-- The ring's Chat entry.
	local from, to = ours and "chat" or "gxivchat", ours and "gxivchat" or "chat"
	for _, page in ipairs(ns.db.ringPages or {}) do
		for segment, entry in pairs(page.slots or {}) do
			if type(entry) == "table" and entry.builtin == from then
				page.slots[segment] = { builtin = to }
			end
		end
	end
	UpdateChatKey()
	Log("chat:", ours and "Chat window" or "the game's", reason or "")
	if ours then
		C_Timer.After(2, function() ns.LogChatArea(reason or "applied") end)
	end
end
end

---------------------------------------------------------------------------------------------------
-- Events

-- The game's Toggle Group Finder key opens LFG Filter instead, while "Open LFG Filter instead" is on.
-- An override binding of the addon's own on a plain button; the game's binding is left as it is.
local keyOwner = CreateFrame("Frame")
local openButton = CreateFrame("Button", "GamepadXIVLfgFilterOpenKey", UIParent)
openButton:RegisterForClicks("AnyDown")
openButton:SetScript("OnClick", function()
	Log("opened with the Toggle Group Finder key")
	ns.OpenLfgFilter()
end)

local function UpdateKeyOverride(reason)
	if not ns.db then
		return
	end
	if InCombatLockdown() then
		state.keyPending = true
		return
	end
	if reason == "UPDATE_BINDINGS" and GetTime() - (keyOwner.setAt or 0) < 2 then
		return -- our own change fired this; a key held by a higher binding would loop otherwise
	end
	local keys = ns.db.lfgFinder ~= "game" and { GetBindingKey("TOGGLEGROUPFINDER") } or {}
	-- Nothing to change: setting the same bindings again would fire UPDATE_BINDINGS again.
	local same = #keys == (keyOwner.count or 0)
	for _, key in ipairs(keys) do
		same = same and GetBindingAction(key, true) == "CLICK GamepadXIVLfgFilterOpenKey:LeftButton"
	end
	if same then
		return
	end
	ClearOverrideBindings(keyOwner)
	keyOwner.count = #keys
	keyOwner.setAt = GetTime()
	for _, key in ipairs(keys) do
		SetOverrideBindingClick(keyOwner, false, key, "GamepadXIVLfgFilterOpenKey", "LeftButton")
	end
	Log("group finder key ->", #keys > 0 and table.concat(keys, ", ") or "no key bound", reason)
end
ns.UpdateLfgFilterKey = UpdateKeyOverride

-- The group finder setting: LFG Filter or the game's own. It swaps the entry on every ring page and
-- what the Group Finder key opens.
function ns.ApplyLfgFinderChoice()
	local from, to = "lfd", "lfgfilter"
	if ns.db.lfgFinder == "game" then
		from, to = "lfgfilter", "lfd"
	end
	local swapped = 0
	for _, page in ipairs(ns.db.ringPages or {}) do
		for segment, entry in pairs(page.slots or {}) do
			if type(entry) == "table" and entry.builtin == from then
				page.slots[segment] = { builtin = to }
				swapped = swapped + 1
			end
		end
	end
	Log("group finder:", ns.db.lfgFinder, "ring entries swapped", swapped)
	UpdateKeyOverride("setting")
end

local roster = {}
local rosterSeeded = false

-- Party members go to the Ratings tab; someone you rated Avoid joining is announced.
local function UpdateRoster()
	if not ns.db then
		return
	end
	local now = {}
	local prefix, count = "party", GetNumSubgroupMembers and GetNumSubgroupMembers() or 0
	if IsInRaid() then
		prefix, count = "raid", GetNumGroupMembers()
	end
	local where
	local inInstance, _ = IsInInstance()
	if inInstance then
		where = GetInstanceInfo()
	else
		where = GetRealZoneText and GetRealZoneText() or ""
	end
	for index = 1, count do
		local unit = prefix .. index
		if UnitExists(unit) and not UnitIsUnit(unit, "player") then
			local name = FullName(GetUnitName(unit, true))
			if name then
				now[name] = true
				local _, class = UnitClass(unit)
				-- A new group with them: not in the group the last time it was looked at, even
				-- across a reload (ns.db.lfgInGroup).
				local before = type(ns.db.lfgInGroup) == "table" and ns.db.lfgInGroup or {}
				local timesBefore = ns.LfgGroupCount(name)
				if not before[name] then
					local counts = ns.LfgGroupCounts()
					counts[name] = timesBefore + 1
					-- Someone you grouped with before: how often, your rating and your note.
					if timesBefore > 0 or RatingOf(name) > 0 or NoteOf(name) then
						state.SayKnown(name, Plain(class, nil), timesBefore)
					end
				end
				-- In a dungeon or raid: one more run with them, once per group and instance.
				local _, instanceType = IsInInstance()
				local session = ns.db.lfgGroupSession
				if (instanceType == "party" or instanceType == "raid") and type(session) == "table" and session.started then
					local run = tostring(session.started) .. ":" .. tostring(Plain(where, ""))
					local dungeons = ns.LfgDungeons()
					local entry = dungeons[name] or { n = 0 }
					if entry.last ~= run then
						entry.n, entry.last = entry.n + 1, run
						Log("dungeon run with", name, entry.n)
					end
					dungeons[name] = entry
				end
				-- The role they have in this group, kept with the others they had before.
				local assigned = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
				local role = assigned == "TANK" and "tank" or assigned == "HEALER" and "healer" or assigned == "DAMAGER" and "dps" or nil
				if role then
					local roles = ns.LfgPlayerRoles()
					roles[name] = type(roles[name]) == "table" and roles[name] or {}
					roles[name][role] = true
				end
				local recent = Recent()
				for i = #recent, 1, -1 do
					if recent[i].name == name then
						tremove(recent, i)
					end
				end
				tinsert(recent, 1, { name = name, class = Plain(class, nil), where = Plain(where, ""), t = time() })
				while #recent > MAX_RECENT do
					tremove(recent)
				end
				if rosterSeeded and not roster[name] then
					Log("joined:", name, "rating", RatingOf(name))
				end
			end
		end
	end
	roster = now
	rosterSeeded = true
	ns.db.lfgInGroup = now
end

local events = CreateFrame("Frame")
events:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
events:RegisterEvent("LFG_LIST_SEARCH_FAILED")
events:RegisterEvent("LFG_LIST_SEARCH_RESULT_UPDATED")
events:RegisterEvent("LFG_LIST_AVAILABILITY_UPDATE")
events:RegisterEvent("CHAT_MSG_WHISPER")
events:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
events:RegisterEvent("CHAT_MSG_BN_WHISPER")
events:RegisterEvent("CHAT_MSG_BN_WHISPER_INFORM")
for event in pairs(CHANNEL_EVENTS) do
	pcall(events.RegisterEvent, events, event)
end
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
-- Events this client may not have are skipped.
for _, name in ipairs({ "LFG_LIST_ACTIVE_ENTRY_UPDATE", "LFG_LIST_ROLE_UPDATE", "PLAYER_ROLES_ASSIGNED",
		"PARTY_LEADER_CHANGED", "ROLE_POLL_BEGIN", "UPDATE_BINDINGS", "PLAYER_LOGIN", "PLAYER_REGEN_ENABLED" }) do
	pcall(events.RegisterEvent, events, name)
end
events:RegisterEvent("ADDON_ACTION_BLOCKED")
events:RegisterEvent("ADDON_ACTION_FORBIDDEN")

local resultUpdatePending = false
events:SetScript("OnEvent", function(_, event, ...)
	if not ns.db then
		return
	end
	if event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" or event == "LFG_LIST_SEARCH_FAILED" then
		local ours = state.searching
		state.searching = false
		state.lastSearchOurs = ours
		if ours then
			state.searchedOnce = true
			state.searchFailed = event == "LFG_LIST_SEARCH_FAILED"
		end
		Log(event, ours and "(ours)" or "(another window's)")
		if state.searchAgain then
			local reason = state.searchAgain
			state.searchAgain = nil
			DoSearch(reason .. " (waited)")
			return
		end
		if window and window:IsShown() then
			BuildResults()
			Refresh()
		end
	elseif event == "LFG_LIST_SEARCH_RESULT_UPDATED" then
		-- These come in bursts; redraw once.
		if window and window:IsShown() and state.tab == TAB_FINDER and not resultUpdatePending then
			resultUpdatePending = true
			C_Timer.After(0.3, function()
				resultUpdatePending = false
				if window:IsShown() then
					BuildResults()
					Refresh()
				end
			end)
		end
	elseif event == "LFG_LIST_ACTIVE_ENTRY_UPDATE" then
		local listed = C_LFGList.HasActiveEntryInfo()
		Log(event, "created new:", tostring((...)), "listed:", tostring(listed), "ours pending:", tostring(state.listingPending))
		if state.listingPending and listed then
			state.listingPending = nil
			DoSearch("after listing")
		end
		ns.RefreshLfgFilter()
	elseif event == "LFG_LIST_ROLE_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" or event == "PARTY_LEADER_CHANGED" or event == "ROLE_POLL_BEGIN" then
		Log(event)
		if event == "PLAYER_ROLES_ASSIGNED" then
			UpdateRoster() -- the members' roles for the Ratings tab
		end
		ns.RefreshLfgFilter()
	elseif event == "LFG_LIST_AVAILABILITY_UPDATE" then
		ClearCaches()
		ns.RefreshLfgFilter()
	elseif CHANNEL_EVENTS[event] then
		local text, who = ...
		local guid = select(12, ...)
		if Secret(text) or Secret(who) then
			Log(event, "secret, not kept")
			return
		end
		local key = CHANNEL_EVENTS[event]
		if key == "channel" then
			local base = select(9, ...)
			if Secret(base) or type(base) ~= "string" or base == "" then
				base = select(4, ...)
				base = type(base) == "string" and not Secret(base) and base:gsub("^%d+%.%s*", ""):gsub("%s+%-.*$", "") or nil
			end
			if not base or base == "" then
				return
			end
			key = "#CH:" .. base
			local number = select(8, ...)
			if not Secret(number) and type(number) == "number" and number > 0 then
				Chats()[key] = Chats()[key] or { lines = {}, unread = 0 }
				Chats()[key].number = number
			end
		end
		local sender = key ~= "#SYSTEM" and FullName(who) or nil
		local class
		if not Secret(guid) and guid and GetPlayerInfoByGUID then
			local ok, _, englishClass = pcall(GetPlayerInfoByGUID, guid)
			class = ok and Plain(englishClass, nil) or nil
		end
		local outgoing = sender ~= nil and Target(sender) == UnitName("player")
		-- The line's own chat type, kept when it isn't the conversation's (party leader, raid warning, loot).
		local kind = not key:find("^#CH:") and event:sub(10) or nil -- CHAT_MSG_PARTY_LEADER: PARTY_LEADER
		if kind == (ChannelInfo(key).chatType or "SYSTEM") then
			kind = nil
		end
		local chat = AddLine(key, outgoing, text, nil, sender, class, kind)
		local viewing = window and window:IsShown() and state.tab == TAB_CHAT and state.selectedName == key
		if not outgoing and not viewing and not ChannelInfo(key).quiet then
			chat.unread = (chat.unread or 0) + 1
		end
		ns.RefreshLfgFilter()
		if ns.UpdateLfgHint then
			ns.UpdateLfgHint()
		end
	elseif event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_WHISPER_INFORM" or event == "CHAT_MSG_BN_WHISPER"
			or event == "CHAT_MSG_BN_WHISPER_INFORM" then
		local text, who = ...
		local guid = select(12, ...)
		if Secret(text) or Secret(who) then
			Log(event, "secret, not kept")
			return
		end
		local bnet = event:find("_BN_", 1, true) ~= nil
		local name
		if bnet then
			-- A Battle.net friend: the 13th value is their account.
			local accountID = select(13, ...)
			name = not Secret(accountID) and ns.BNetKey(accountID) or nil
			guid = nil
		else
			name = FullName(who)
		end
		if not name then
			Log(event, "no name")
			return
		end
		local class
		if not Secret(guid) and guid and GetPlayerInfoByGUID then
			local ok, _, englishClass = pcall(GetPlayerInfoByGUID, guid)
			class = ok and Plain(englishClass, nil) or nil
		end
		local outgoing = event == "CHAT_MSG_WHISPER_INFORM" or event == "CHAT_MSG_BN_WHISPER_INFORM"
		local chat = AddLine(name, outgoing, text, class)
		local viewing = window and window:IsShown() and state.tab == TAB_CHAT and state.selectedName == name
		if not outgoing and not viewing then
			chat.unread = (chat.unread or 0) + 1
		end
		if outgoing then
			chat.unread = 0
		end
		Log(outgoing and "whisper out" or "whisper in", name, "unread", chat.unread)
		-- Keep the same conversation selected as the list reorders.
		do
			local selected = state.selectedName
			for index, item in ipairs(SortedChats()) do
				if item.name == selected then
					state.chatCursor = index
				end
			end
		end
		ns.RefreshLfgFilter()
		if ns.UpdateLfgHint then
			ns.UpdateLfgHint()
		end
	elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
		UpdateRoster()
		if window and window:IsShown() then
			BuildResults()
			Refresh()
		end
	elseif event == "PLAYER_LOGIN" or event == "UPDATE_BINDINGS" then
		UpdateKeyOverride(event)
		if event == "PLAYER_LOGIN" then
			ns.PruneLfgChats("login")
			ns.ApplyChatChoice("login")
		else
			UpdateChatKey(event)
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if state.unbindPending and window and not window:IsShown() then
			Unbind("after combat")
		end
		if state.keyPending then
			state.keyPending = nil
			UpdateKeyOverride("after combat")
		end
		if state.chatKeyPending then
			state.chatKeyPending = nil
			UpdateChatKey()
		end
	elseif event == "PLAYER_REGEN_DISABLED" then
		if window and window:IsShown() then
			Log("combat: window closed")
			window:Hide()
		end
	elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
		local addon, action = ...
		Log("!!", event, "addon:", addon, "action:", action, "lfg window:", tostring(LFGParentFrame and LFGParentFrame:IsShown()),
			"our window:", tostring(window and window:IsShown()))
	end
end)
