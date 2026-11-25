local _, ns = ...

-- Sounds for incoming chat: one choice per kind of chat (whispers, party, raid, guild and so on),
-- set in the settings' Chat tab. A choice is saved as text:
--   "none"            no sound
--   "gxiv:<file>"     one of the addon's own sounds (Sounds\<file>.ogg)
--   "kit:<KEY>"       one of the game's own, SOUNDKIT[KEY]
--   "lsm:<name>"      a sound shared through LibSharedMedia-3.0
-- A game or shared sound that isn't there any more plays the addon's whisper sound instead.
-- Your own messages make no sound, nor does a burst of messages (one sound a second per kind), nor a
-- conversation you are typing in (ns.ChatSoundSuppress, which the chat box can replace).

local Sounds = {}
ns.ChatSounds = Sounds

local PATH = "Interface\\AddOns\\GamepadXIV\\Sounds\\"
local FALLBACK = "gxiv:whisper"
local THROTTLE = 1 -- seconds between two sounds of one kind

-- The addon's own sounds, in the order the lists show them.
local OURS = {
	{ "chirp", "Chirp" }, { "whisper", "Whisper" }, { "whisper2", "Whisper (light)" }, { "alert", "Alert" }, { "bell", "Bell" },
	{ "bubble", "Bubble" }, { "chime", "Chime" }, { "drop", "Drop" }, { "knock", "Knock" },
	{ "marimba", "Marimba" }, { "ping", "Ping" }, { "rise", "Rise" }, { "sparkle", "Sparkle" },
}
local OUR_FILES = {}
for _, sound in ipairs(OURS) do
	OUR_FILES[sound[1]] = true
end

-- The game's own sounds; only those this client has are listed.
local KITS = {
	{ "TELL_MESSAGE", "Game: whisper" },
	{ "IG_PLAYER_INVITE", "Game: invite" },
	{ "RAID_WARNING", "Game: raid warning" },
	{ "READY_CHECK", "Game: ready check" },
	{ "MAP_PING", "Game: map ping" },
	{ "UI_BNET_TOAST", "Game: friend toast" },
}

-- The kinds of chat, each with its setting, and the events that count as it.
Sounds.TYPES = {
	{ id = "whisper", key = "chatSoundWhisper", label = "Whispers" },
	{ id = "party", key = "chatSoundParty", label = "Party" },
	{ id = "raid", key = "chatSoundRaid", label = "Raid" },
	{ id = "instance", key = "chatSoundInstance", label = "Instance" },
	{ id = "guild", key = "chatSoundGuild", label = "Guild" },
	{ id = "officer", key = "chatSoundOfficer", label = "Officer" },
	{ id = "say", key = "chatSoundSay", label = "Say and yell" },
	{ id = "channel", key = "chatSoundChannels", label = "Channels (General, Trade...)" },
}
local TYPE_BY_ID = {}
for _, kind in ipairs(Sounds.TYPES) do
	TYPE_BY_ID[kind.id] = kind
end

-- Each event: the kind of chat, and the conversation it belongs to as LfgFilter.lua names them
-- ("#PARTY", "#CH:Trade", or the sender for a whisper), for ns.ChatSoundSuppress.
local EVENTS = {
	CHAT_MSG_WHISPER = { "whisper" },
	CHAT_MSG_BN_WHISPER = { "whisper" },
	CHAT_MSG_PARTY = { "party", "#PARTY" }, CHAT_MSG_PARTY_LEADER = { "party", "#PARTY" },
	CHAT_MSG_RAID = { "raid", "#RAID" }, CHAT_MSG_RAID_LEADER = { "raid", "#RAID" }, CHAT_MSG_RAID_WARNING = { "raid", "#RAID" },
	CHAT_MSG_INSTANCE_CHAT = { "instance", "#INSTANCE" }, CHAT_MSG_INSTANCE_CHAT_LEADER = { "instance", "#INSTANCE" },
	CHAT_MSG_GUILD = { "guild", "#GUILD" }, CHAT_MSG_OFFICER = { "officer", "#OFFICER" },
	CHAT_MSG_SAY = { "say", "#SAY" }, CHAT_MSG_YELL = { "say", "#YELL" },
	CHAT_MSG_CHANNEL = { "channel" },
}
Sounds.EVENTS = EVENTS

local lastPlayed = {} -- kind -> GetTime() of its last sound

local function Secret(value)
	return issecretvalue and issecretvalue(value) or false
end

local function Media()
	return LibStub and LibStub("LibSharedMedia-3.0", true)
end

-- "kit:TELL_MESSAGE" -> "kit", "TELL_MESSAGE"
local function Parse(choice)
	if type(choice) ~= "string" then
		return nil
	end
	return choice:match("^(%a+):(.+)$")
end

-- What a choice plays: "file", path or "kit", id; nil for none. Missing sounds give the fallback.
function Sounds.Resolve(choice)
	if choice == nil or choice == "none" then
		return nil
	end
	local kind, name = Parse(choice)
	if kind == "gxiv" and OUR_FILES[name] then
		return "file", PATH .. name .. ".ogg"
	elseif kind == "kit" then
		local id = SOUNDKIT and SOUNDKIT[name]
		if id then
			return "kit", id
		end
	elseif kind == "lsm" then
		local media = Media()
		local ok, path = false, nil
		if media then
			ok, path = pcall(media.Fetch, media, "sound", name, true)
		end
		if ok and path then
			return "file", path
		end
	end
	if choice == FALLBACK then
		return nil -- can't happen with the file in place; keeps a typo from looping
	end
	return Sounds.Resolve(FALLBACK)
end

-- Plays a choice on the chosen sound channel. Returns whether something played.
function Sounds.Play(choice)
	local how, what = Sounds.Resolve(choice)
	if not how then
		return false
	end
	local channel = ns.db and ns.db.chatSoundOutput == "SFX" and "SFX" or "Master"
	if how == "kit" then
		return (pcall(PlaySound, what, channel))
	end
	return (pcall(PlaySoundFile, what, channel))
end

-- The choices for a kind's setting: none, the addon's sounds, the game's, then shared ones. A shared
-- sound picked before, whose addon is now off, stays in the list, marked.
function Sounds.Choices(current)
	local list = { { "none", "None" } }
	local seen = { none = true }
	local function Add(value, label)
		if not seen[value] then
			seen[value] = true
			list[#list + 1] = { value, label }
		end
	end
	for _, sound in ipairs(OURS) do
		Add("gxiv:" .. sound[1], sound[2])
	end
	for _, kit in ipairs(KITS) do
		if SOUNDKIT and SOUNDKIT[kit[1]] then
			Add("kit:" .. kit[1], kit[2])
		end
	end
	local media = Media()
	if media then
		local ok, names = pcall(media.List, media, "sound")
		for _, name in ipairs(ok and type(names) == "table" and names or {}) do
			local path = media:Fetch("sound", name, true)
			-- LibSharedMedia's own "None", and our sounds should another addon share them.
			if name ~= "None" and path and not (type(path) == "string" and path:find("GamepadXIV", 1, true)) then
				Add("lsm:" .. name, name)
			end
		end
	end
	if type(current) == "string" and not seen[current] then
		local _, name = Parse(current)
		Add(current, (name or current) .. " |cff999999(missing: plays Whisper)|r")
	end
	return list
end

-- Whether no sound should play for a conversation: the one you are typing in, when the chat box tells.
-- The chat box may replace this.
ns.ChatSoundSuppress = ns.ChatSoundSuppress or function(key)
	if not (key and ns.ChatBoxActiveKey) then
		return false
	end
	local ok, active = pcall(ns.ChatBoxActiveKey)
	if not ok or type(active) ~= "string" then
		return false
	end
	if active == key then
		return true
	end
	-- A whisper may be named with or without the realm.
	local short = key:match("^([^%-#]+)%-")
	return short ~= nil and active == short
end

local function PlayerNames()
	local name = UnitName and UnitName("player")
	local realm = GetNormalizedRealmName and GetNormalizedRealmName()
	return name, realm
end

-- Whether the sender is you, with or without the realm.
local function FromMe(sender, guid)
	if not Secret(guid) and guid and UnitGUID and guid == UnitGUID("player") then
		return true
	end
	local name, realm = PlayerNames()
	if not name then
		return false
	end
	return sender == name or (realm and realm ~= "" and sender == name .. "-" .. realm) or false
end

local function FullName(name)
	if not name:find("-", 1, true) then
		local _, realm = PlayerNames()
		if realm and realm ~= "" then
			return name .. "-" .. realm
		end
	end
	return name
end

-- A numbered channel's conversation, "#CH:Trade", as LfgFilter.lua keys it.
local function ChannelKey(...)
	local base = select(9, ...)
	if Secret(base) or type(base) ~= "string" or base == "" then
		base = select(4, ...)
		if Secret(base) or type(base) ~= "string" then
			return nil
		end
		base = base:gsub("^%d+%.%s*", ""):gsub("%s+%-.*$", "")
	end
	return base ~= "" and ("#CH:" .. base) or nil
end

-- A chat event: plays its kind's sound, unless it shouldn't. Returns what played, for the tests.
function Sounds.OnChat(event, ...)
	local entry = EVENTS[event]
	if not entry or not (ns.db and ns.db.chatSounds) then
		return nil
	end
	local kind = TYPE_BY_ID[entry[1]]
	local choice = ns.db[kind.key]
	if choice == nil or choice == "none" then
		return nil
	end
	local sender = select(2, ...)
	local guid = select(12, ...)
	if Secret(sender) or type(sender) ~= "string" or sender == "" then
		return nil
	end
	if FromMe(sender, guid) then
		return nil
	end
	local key = entry[2]
	if kind.id == "whisper" then
		key = FullName(sender)
	elseif kind.id == "channel" then
		key = ChannelKey(...)
	end
	local suppress = ns.ChatSoundSuppress
	if suppress then
		local ok, quiet = pcall(suppress, key, kind.id)
		if ok and quiet then
			return nil
		end
	end
	local now = GetTime()
	if lastPlayed[kind.id] and now - lastPlayed[kind.id] < THROTTLE then
		return nil
	end
	if Sounds.Play(choice) then
		lastPlayed[kind.id] = now
		return choice
	end
	return nil
end

-- The settings rows for the Chat tab (Config.lua).
function Sounds.SettingRows()
	local rows = {
		{ type = "check", key = "chatSounds", label = "Chat sounds",
			tip = "A sound when a message comes in, chosen for each kind of chat below. Not for your own messages, nor for the conversation you are typing in. Sounds added to the addon's folder need a game restart, not only /reload." },
		{ type = "choice", key = "chatSoundOutput", label = "Sound channel",
			choices = function() return { { "Master", "Master" }, { "SFX", "Sound effects" } } end,
			onChange = function() Sounds.Play(ns.db.chatSoundWhisper) end,
			tip = "Master plays even with sound effects off, at the master volume. Sound effects follows the game's sound effects volume." },
	}
	for _, kind in ipairs(Sounds.TYPES) do
		local key = kind.key
		rows[#rows + 1] = { type = "choice", key = key, label = kind.label,
			choices = function() return Sounds.Choices(ns.db and ns.db[key]) end,
			onChange = function() Sounds.Play(ns.db[key]) end,
			tip = "The sound for this kind of chat; picking one plays it." }
	end
	return rows
end

local events = CreateFrame("Frame")
for event in pairs(EVENTS) do
	events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event, ...)
	Sounds.OnChat(event, ...)
end)
