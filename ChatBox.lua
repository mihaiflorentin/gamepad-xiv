local _, ns = ...

-- The chat box: where the game's chat was, while the Chat setting is "Chat window" (LfgFilter.lua hides
-- the game's chat and keeps the conversations). Tabs along the top: All (everything the game's chat
-- would show), Whispers, Say, Party, Raid, Guild, the channels, then Combat (this session's combat log,
-- read-only). The Whispers tab has a column of the recent conversations; {PADLSHOULDER} / {PADRSHOULDER}
-- stop at each of them. Each tab's lines are in the game's colour for that chat; your own lines are
-- marked (the "Highlight my messages" setting).
--
-- Two modes, like FFXIV:
-- Typing (Back's chat step, the game's Open Chat key (Enter), a click on the box): {PADLSHOULDER} /
--   {PADRSHOULDER} or Tab change tabs, {PADDUP} / {PADDDOWN} recall what you sent (the right stick
--   doesn't scroll: it scrolled by accident), {PADRSTICK} opens the ready-made messages ({PAD1} adds one to the message and the menu
--   stays open for more), {PAD3} erases, {PADDLEFT} / {PADDRIGHT} pick a quick reply that {PADLSTICK}
--   adds at the cursor ({PAD1} too while nothing is typed), Enter or {PAD1} sends, {PAD4} opens the Chat
--   window on that tab, {PAD2} stops typing and browses, Escape closes. Nothing ready-made is sent by
--   itself: it goes into the message, so several can go out as one.
-- Browse: {PADDUP} / {PADDDOWN} scroll, {PADLSHOULDER} / {PADRSHOULDER} change tabs, {PAD3} picks the channel tabs, {PAD1} types again,
--   {PAD2} closes and gives the D-pad back. It ends in combat too.
-- Chat commands work: /w name, /r, /s, /p, /ra, /g, /o, /y, /i, /e, /1 to /9, and addon commands. The
-- game's own commands (/reload, /cast, emotes...) run through a secure macro button that {PAD1} clicks,
-- out of combat. In combat the controller keys can't be bound, so they stay the game's; the keyboard
-- (Enter, Tab, Escape) still works.

local GOLD = { 1, 0.82, 0 }
local WHITE = "Interface\\Buttons\\WHITE8X8"
local MAX_TABS = 7
local MAX_WHISPERS = 6 -- rows in the Whispers column
local MAX_SENT = 30 -- lines {PADDUP} / {PADDDOWN} recall
local MAX_COMBAT = 300 -- Combat tab lines, this session only
local COLUMN_WIDTH = 120
local ARROW_WIDTH = 24
local HINT_SIZE = 18 -- button icons in the hint and quick reply lines
local BUTTON = "GamepadXIVChatBox"
local MACRO = "GamepadXIVChatBoxMacro"
-- Your own lines: a gold bar at the start (a chat line can't have a background of its own).
local OWN_MARK = "|T" .. WHITE .. ":13:3:0:0:8:8:0:8:0:8:255:209:0|t "

local box, feed, convo, input, prefix, column
local tabButtons = {}
local current = "all" -- "all", "whispers", "combat", a channel ("#PARTY") or a whisper partner's name
local shownSeq
local mode -- nil, "typing" or "browse"
local allTarget = "#SAY" -- where a message typed on the All tab goes ({PADLTRIGGER} / {PADRTRIGGER}, or a command)
local jumpAt -- scrolled up when a message came: back to the newest at this time (10 s after it)
local JUMP_SECONDS = 10
local shownKey, shownCount -- the conversation drawn last and how many lines it had
local StepAllTarget
local owner = CreateFrame("Frame") -- holds the controller keys while typing or browsing
local menu -- ready-made messages ({PADRSTICK} while typing)
local menuState = { group = nil, index = 1 }
local sent, recall = {}, nil -- what you sent this session, and the one {PADDUP} / {PADDDOWN} show
local combatLines, combatSeq = {}, 0
local combatRefused -- the client keeps COMBAT_LOG_EVENT_UNFILTERED from addons
local macroButton, macroReady, macroBound, macroPressed
local layoutKey

local Draw
local Command
local Links = {} -- links from the game's Shift-clicks and Share in Chat: the block at the end
local Line = {} -- the line picked while browsing: its menu, its item's tooltip, its band ("Lines")

-- Fonts for the chat box: the game's, plus any LibSharedMedia has (other addons add theirs there).
local FONTS = {
	{ "default", "The game's chat font" },
	{ "Fonts\\FRIZQT__.TTF", "Friz Quadrata" },
	{ "Fonts\\ARIALN.TTF", "Arial Narrow" },
	{ "Fonts\\MORPHEUS.TTF", "Morpheus" },
	{ "Fonts\\SKURRI.TTF", "Skurri" },
}

function ns.ChatBoxFonts()
	local list, seen = {}, {}
	for _, font in ipairs(FONTS) do
		list[#list + 1] = font
		seen[font[1]] = true
	end
	local media = LibStub and LibStub("LibSharedMedia-3.0", true)
	if media then
		for _, name in ipairs(media:List("font") or {}) do
			local path = media:Fetch("font", name)
			if path and not seen[path] then
				seen[path] = true
				list[#list + 1] = { path, name }
			end
		end
	end
	return list
end

local function API()
	return ns.ChatAPI
end

local function Log(...)
	if ns.ChatAPI then
		ns.ChatAPI.Log("chat box:", ...)
	end
end

local function Secret(value)
	return issecretvalue and issecretvalue(value) or false
end

local function Plain(value)
	if Secret(value) then
		return nil
	end
	return value
end

-- Icons for the hint lines; names only when the controller has no icon for a button.
local STICK_NAMES = { PADRSTICKUP = "Right stick up", PADRSTICKDOWN = "Right stick down" }
local function Buttons(text, size)
	if ns.BUTTON_NAMES then
		for key, name in pairs(STICK_NAMES) do
			ns.BUTTON_NAMES[key] = ns.BUTTON_NAMES[key] or name
		end
	end
	return ns.ButtonText(text, size)
end

-- Ready-made messages (the {PADRSTICK} menu, the quick replies) are never sent on their own: they go
-- into the message being typed, here and in the Chat window (LfgFilter.lua), at the cursor (the end
-- while the box isn't focused) and a single space from the text around them. The box remembers it got
-- one (box.readyMade, forgotten when it is emptied), so sending puts the raid markers round the whole
-- message once (ns.ChatAPI.Decorate). False when it doesn't fit in the box's letters (255).
local function Letters(text)
	return select(2, text:gsub("[^\128-\191]", ""))
end

-- Backspace for {PAD3}: the character before the cursor (a whole UTF-8 character), or a whole link.
-- Used by the chat box and LFG Filter's / the Chat window's message box.
function ns.ChatErase(box)
	local text = box:GetText() or ""
	local cursor = box:GetCursorPosition()
	if cursor <= 0 then
		return
	end
	local start = Links.StartBefore(text:sub(1, cursor)) or cursor
	while start > 1 and text:byte(start) and text:byte(start) >= 0x80 and text:byte(start) < 0xC0 do
		start = start - 1
	end
	box:SetText(text:sub(1, start - 1) .. text:sub(cursor + 1))
	box:SetCursorPosition(start - 1)
end

function ns.ChatInsert(box, text)
	text = type(text) == "string" and text:gsub("^%s+", ""):gsub("%s+$", "") or ""
	if not box or text == "" then
		return false
	end
	local old = box:GetText() or ""
	local at = box:HasFocus() and tonumber(box:GetCursorPosition()) or #old
	at = math.max(0, math.min(at, #old))
	while at < #old and old:byte(at + 1) >= 0x80 and old:byte(at + 1) < 0xC0 do
		at = at + 1 -- not inside a letter
	end
	local before, after = old:sub(1, at), old:sub(at + 1)
	local lead = (before ~= "" and not before:find("%s$")) and " " or ""
	local trail = (after ~= "" and not after:find("^%s")) and " " or ""
	local max = tonumber(box.GetMaxLetters and box:GetMaxLetters()) or 0
	if max <= 0 then
		max = 255
	end
	local count = tonumber(box.GetNumLetters and box:GetNumLetters()) or Letters(old)
	if count + Letters(lead .. text .. trail) > max then
		return false
	end
	local new = before .. lead .. text .. trail .. after
	box:SetText(new)
	if box:GetText() ~= new then
		-- The box cut it anyway (it counts letters its own way): put back what was typed.
		box:SetText(old)
		box:SetCursorPosition(at)
		return false
	end
	box:SetCursorPosition(#before + #lead + #text)
	box.readyMade = true
	return true
end

-- The player you whispered with last: where the Whispers tab sends while no conversation is picked.
local function LastWhisper()
	local best, bestTime
	for name, chat in pairs(API().Chats()) do
		local line = chat.lines and chat.lines[#chat.lines]
		if not API().Info(name) and line and (not bestTime or (line.t or 0) > bestTime) then
			best, bestTime = name, line.t or 0
		end
	end
	return best
end

-- A typed name (/w bob) as the conversation's key: an existing one that matches, or Name-Realm as
-- LfgFilter.lua keeps whispers.
local function WhisperKey(name)
	if type(name) ~= "string" or name == "" then
		return name
	end
	local lower = name:lower()
	for key in pairs(API().Chats()) do
		if not API().Info(key) and (key:lower() == lower or (Ambiguate and Ambiguate(key, "short"):lower() == lower)) then
			return key
		end
	end
	if not name:find("-", 1, true) then
		if name:byte(1) < 0x80 then
			name = name:sub(1, 1):upper() .. name:sub(2):lower()
		end
		local realm = GetNormalizedRealmName and GetNormalizedRealmName()
		if realm and realm ~= "" then
			name = name .. "-" .. realm
		end
	end
	return name
end

local function IsWhisperKey(key)
	return type(key) == "string" and key ~= "all" and key ~= "whispers" and key ~= "combat" and not API().Info(key)
end

local function IsChannelKey(key)
	local channel = type(key) == "string" and API().Info(key)
	return channel and not channel.readOnly
end

-- The tab a stop belongs to.
local function TabOf(key)
	if IsWhisperKey(key) then
		return "whispers"
	end
	return key
end

-- Where a message typed on the current tab goes.
local function Target()
	if current == "all" then
		return allTarget
	elseif current == "combat" then
		return "#SAY"
	elseif current == "whispers" then
		return LastWhisper()
	end
	return current
end

-- The recent whisper conversations, as the Chat window lists them (active in the last 30 minutes and not
-- closed, or unread), the newest first. The one picked stays listed (a /w name without lines yet).
local function RecentWhispers()
	local list, found = {}, false
	for _, item in ipairs(API().List()) do
		if item.name and not API().Info(item.name) then
			list[#list + 1] = { key = item.name, chat = item.chat }
			found = found or item.name == current
		end
	end
	if IsWhisperKey(current) and not found then
		table.insert(list, 1, { key = current, chat = API().Chats()[current] })
	end
	while #list > MAX_WHISPERS do
		if list[#list].key == current then
			table.remove(list, #list - 1)
		else
			table.remove(list)
		end
	end
	return list
end

-- Channel tabs: which channels have a tab. ns.db.chatBoxTabs[key] = true (always) / false (never);
-- without a choice, Say, Party, Guild and the others have a tab once they have messages (Party / Raid
-- while in a group), and numbered channels (General, Trade, Local Defense...) have none until you pick them.
local pickedWhisper -- the player picked last on the Whispers tab, where it opens again
local STANDARD_TABS = { "#SAY", "#YELL", "#GUILD", "#OFFICER" }
-- Party, Raid and Instance always have a tab while you are in that group: not in the menu, and an
-- older choice for them is ignored.
local GROUP_TABS = { ["#PARTY"] = true, ["#RAID"] = true, ["#INSTANCE"] = true }

local function TabChoices()
	ns.db.chatBoxTabs = ns.db.chatBoxTabs or {}
	return ns.db.chatBoxTabs
end

-- A numbered channel's key: the one its messages already use, or "#CH:<name>".
local function ChannelKey(name)
	local base = tostring(name or ""):gsub("%s+%-.*$", "")
	for key in pairs(API().Chats()) do
		if key:find("^#CH:") and key:sub(5):gsub("%s+%-.*$", "") == base then
			return key
		end
	end
	return "#CH:" .. base
end

-- The channels you can give a tab: the standard ones, and the numbered channels you are in.
local function TabCandidates()
	local list, seen = {}, {}
	local function Add(key, number)
		if not seen[key] and IsChannelKey(key) then
			seen[key] = true
			list[#list + 1] = key
			if number then
				local chats = API().Chats()
				chats[key] = chats[key] or { lines = {}, unread = 0 }
				chats[key].number = number
			end
		end
	end
	for _, key in ipairs(STANDARD_TABS) do
		Add(key)
	end
	if GetChannelList then
		local values = { GetChannelList() }
		-- id, name, disabled for each channel
		for i = 1, #values, 3 do
			local id, name = values[i], values[i + 1]
			if type(id) == "number" and type(name) == "string" and not Secret(name) then
				Add(ChannelKey(name), id)
			end
		end
	end
	for key in pairs(TabChoices()) do
		if not GROUP_TABS[key] then
			Add(key)
		end
	end
	return list
end

local function ChannelHasTab(key, automatic)
	if GROUP_TABS[key] then
		return automatic
	end
	local choice = TabChoices()[key]
	if choice ~= nil then
		return choice
	end
	return automatic
end

-- Every stop {PADLSHOULDER} / {PADRSHOULDER} go through: All, each recent whisper (or Whispers when there
-- are none), the channels you can write to, Combat.
local function Stops()
	local stops = { { key = "all", tab = "all" } }
	local whispers = RecentWhispers()
	-- Whispers is one stop: {PADDUP} / {PADDDOWN} pick the player in its column. It opens on the player
	-- picked last, or the newest.
	if #whispers == 0 then
		stops[#stops + 1] = { key = "whispers", tab = "whispers" }
	else
		local pick = whispers[1]
		for _, item in ipairs(whispers) do
			if item.key == pickedWhisper then
				pick = item
			end
		end
		for _, item in ipairs(whispers) do
			if item.key == current then
				pick = item
			end
		end
		pickedWhisper = pick.key
		stops[#stops + 1] = { key = pick.key, tab = "whispers", chat = pick.chat }
	end
	local pinned = IsChannelKey(current) and current
	local listed = {}
	for _, item in ipairs(API().List()) do
		if item.name and IsChannelKey(item.name) and ChannelHasTab(item.name, not item.name:find("^#CH:")) then
			listed[item.name] = true
			stops[#stops + 1] = { key = item.name, tab = item.name, chat = item.chat }
			if item.name == pinned then
				pinned = nil
			end
		end
	end
	-- Channels you chose to always have a tab, before they have messages.
	for key, choice in pairs(TabChoices()) do
		if choice == true and not listed[key] and IsChannelKey(key) and not GROUP_TABS[key] then
			stops[#stops + 1] = { key = key, tab = key, chat = API().Chats()[key] }
			if key == pinned then
				pinned = nil
			end
		end
	end
	if pinned then
		-- A channel picked with its command (/y) before it has lines.
		stops[#stops + 1] = { key = pinned, tab = pinned, chat = API().Chats()[pinned] }
	end
	stops[#stops + 1] = { key = "combat", tab = "combat" }
	return stops, whispers
end

local function TabLabel(tab, chat)
	if tab == "all" then
		return "All"
	elseif tab == "combat" then
		return "|cffff9060Combat|r"
	elseif tab == "whispers" then
		local unread = 0
		for name, other in pairs(API().Chats()) do
			if not API().Info(name) then
				unread = unread + (other.unread or 0)
			end
		end
		return "|cffff80ffWhispers|r" .. (unread > 0 and (" |cffff5555(" .. unread .. ")|r") or "")
	end
	local unread = chat and chat.unread or 0
	local channel = API().Info(tab)
	local label = channel and ("|cff" .. channel.color .. channel.name .. "|r") or API().Color(tab, chat and chat.class)
	return label .. (unread > 0 and (" |cffff5555(" .. unread .. ")|r") or "")
end

local TargetText
function TargetText(key)
	if key == "all" then
		return TargetText(allTarget)
	elseif key == "combat" then
		return "Say:"
	elseif key == "whispers" then
		local last = LastWhisper()
		return last and ("|cffff80ffTo " .. API().Short(last) .. ":|r") or "|cffff80ff/w name:|r"
	end
	local channel = API().Info(key)
	if channel then
		return "|cff" .. channel.color .. channel.name .. ":|r"
	end
	return "|cffff80ffTo " .. API().Short(key) .. ":|r"
end

local function Typing()
	return input and input:HasFocus() and true or false
end

local function MenuOpen()
	return menu and menu:IsShown() and true or false
end

-- The conversation you are typing to, for muting its sound (Sounds.lua): a channel key or a player's
-- name, nil while not typing or on All and Combat.
function ns.ChatBoxActiveKey()
	if not Typing() or current == "all" or current == "combat" then
		return nil
	end
	return Target()
end

---------------------------------------------------------------------------------------------------
-- Chat commands typed in the chat box.

local COMMANDS = {
	s = "#SAY", say = "#SAY", p = "#PARTY", party = "#PARTY", ra = "#RAID", raid = "#RAID", rw = "#RAID",
	g = "#GUILD", guild = "#GUILD", o = "#OFFICER", officer = "#OFFICER", y = "#YELL", yell = "#YELL", sh = "#YELL",
	i = "#INSTANCE", instance = "#INSTANCE",
}
local WHISPER = { w = true, whisper = true, t = true, tell = true, send = true, msg = true }
local REPLY = { r = true, reply = true }
local EMOTE = { e = true, em = true, me = true, emote = true }

-- An addon's slash command (SlashCmdList), never the game's own: those in SecureCmdList (/cast,
-- /target...) and the game's other commands (/reload, /who...), whose entries the game set itself.
local function FindAddonCommand(command)
	if SecureCmdList then
		for key in pairs(SecureCmdList) do
			for i = 1, 20 do
				local alias = _G["SLASH_" .. key .. i]
				if not alias then
					break
				end
				if alias:lower() == command then
					return nil
				end
			end
		end
	end
	for key, handler in pairs(SlashCmdList or {}) do
		for i = 1, 20 do
			local alias = _G["SLASH_" .. key .. i]
			if not alias then
				break
			end
			if alias:lower() == command then
				if issecurevariable and issecurevariable(SlashCmdList, key) then
					return nil -- the game's
				end
				return handler, key
			end
		end
	end
end

-- The answer for the last command word, as typing asks on every key.
local lookup = {}
local function IsAddonCommand(command)
	if lookup.command ~= command then
		lookup.command, lookup.found = command, FindAddonCommand(command) ~= nil
	end
	return lookup.found
end

-- True when Command() below handles the text itself, false for a game command the macro button runs.
local function OwnCommand(text)
	local command = text:match("^/(%S+)")
	if not command then
		return true -- "/" alone: Send explains
	end
	command = command:lower()
	if COMMANDS[command] or WHISPER[command] or REPLY[command] or EMOTE[command] or tonumber(command) then
		return true
	end
	return IsAddonCommand("/" .. command)
end

-- Returns the conversation and the message, true when the command ran here, or nil for one only the
-- game can run.
function Command(text)
	local command, rest = text:match("^/(%S+)%s*(.-)%s*$")
	if not command then
		return nil
	end
	command = command:lower()
	rest = rest or ""
	if COMMANDS[command] then
		return COMMANDS[command], rest
	end
	if WHISPER[command] then
		local name, message = rest:match('^"([^"]+)"%s*(.*)$')
		if not name then
			name, message = rest:match("^(%S+)%s*(.*)$")
		end
		if not name then
			return nil
		end
		return WhisperKey(name), message
	end
	if REPLY[command] then
		local name = ChatEdit_GetLastTellTarget and ChatEdit_GetLastTellTarget()
		if type(name) ~= "string" or name == "" then
			ns.Print("No one has whispered you yet.")
			return true
		end
		return WhisperKey(name), rest
	end
	if EMOTE[command] then
		if rest ~= "" then
			if ns.ChatLocked and ns.ChatLocked() then
				ns.Print("The game locks chat for addons during this fight, so the emote wasn't sent.")
				return true
			end
			local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
			send(rest, "EMOTE")
		end
		return true
	end
	local number = tonumber(command)
	if number then
		local id, name = GetChannelName(number)
		if not id or id == 0 or type(name) ~= "string" then
			ns.Print("You aren't in channel " .. number .. ".")
			return true
		end
		local key = "#CH:" .. name:gsub("%s+%-.*$", "")
		local chats = API().Chats()
		chats[key] = chats[key] or { lines = {}, unread = 0 }
		chats[key].number = number
		return key, rest
	end
	local handler, key = FindAddonCommand("/" .. command)
	if handler then
		Log("command", command, "->", key)
		handler(rest or "")
		return true
	end
	return nil
end

-- What you sent, for {PADDUP} / {PADDDOWN}.
local function Remember(text)
	if text ~= "" and sent[#sent] ~= text then
		sent[#sent + 1] = text
		if #sent > MAX_SENT then
			table.remove(sent, 1)
		end
	end
	recall = nil
end

-- Up (-1) goes back to older lines, the newest first; down (1) past the newest empties the input.
local function Recall(delta)
	if #sent == 0 or (delta > 0 and not recall) then
		return
	end
	local index = (recall or (#sent + 1)) + delta
	if index < 1 then
		index = 1
	end
	if index > #sent then
		recall = nil
		input:SetText("")
	else
		recall = index
		input:SetText(sent[index])
		input:SetCursorPosition(#sent[index])
		input.readyMade = nil -- sent as typed, as it was remembered
	end
end

---------------------------------------------------------------------------------------------------
-- The controller keys while typing or browsing. Only out of combat; combat start gives them back.

local function BindKey(key, name)
	SetOverrideBindingClick(owner, true, key, BUTTON .. name, "LeftButton")
end

-- A game command is typed: {PAD1} clicks the macro button, which runs it.
local function WantMacro()
	if not macroReady or not Typing() or MenuOpen() then
		return false
	end
	local text = strtrim(input:GetText() or "")
	return text:find("^/%S") and not OwnCommand(text) and true or false
end

local function UpdateMacroKey()
	if InCombatLockdown() or not Typing() then
		return
	end
	local want = WantMacro()
	if want then
		local text = strtrim(input:GetText() or ""):sub(1, 255)
		if macroButton:GetAttribute("macrotext") ~= text then
			macroButton:SetAttribute("macrotext", text)
		end
	end
	if want ~= macroBound then
		macroBound = want
		if want then
			SetOverrideBindingClick(owner, true, "PAD1", MACRO, "LeftButton")
		else
			BindKey("PAD1", "Send")
		end
	end
end

local function ApplyBindings()
	if InCombatLockdown() then
		return
	end
	ClearOverrideBindings(owner)
	macroBound = false
	if Typing() then
		-- D-pad up / down recall what you sent, or move in the messages menu while it is open.
		BindKey("PADLSHOULDER", "Prev")
		BindKey("PADRSHOULDER", "Next")
		BindKey("PADRSTICK", "Phrases")
		BindKey("PADDLEFT", "ReplyPrev")
		BindKey("PADDRIGHT", "ReplyNext")
		BindKey("PADLSTICK", "AddReply")
		BindKey("PADDUP", "Up")
		BindKey("PADDDOWN", "Down")
		BindKey("PAD3", "Erase")
		BindKey("PAD1", "Send")
		BindKey("PAD2", "Back")
		BindKey("PAD4", "Window")
		BindKey("PADLTRIGGER", "ChannelPrev")
		BindKey("PADRTRIGGER", "ChannelNext")
		UpdateMacroKey()
	elseif mode == "browse" and MenuOpen() then
		-- The channel tabs menu while browsing.
		BindKey("PADDUP", "Up")
		BindKey("PADDDOWN", "Down")
		BindKey("PAD1", "Send")
		BindKey("PAD2", "Back")
		BindKey("PAD3", "Back")
	elseif mode == "browse" then
		BindKey("PADDUP", "BrowseUp")
		BindKey("PADDDOWN", "BrowseDown")
		BindKey("PADLSHOULDER", "Prev")
		BindKey("PADRSHOULDER", "Next")
		BindKey("PAD1", "Type")
		BindKey("PAD2", "Close")
		BindKey("PAD3", "Tabs")
	end
end

-- Another binding took one of the keys (the addon's driver sets its own again at times).
local function BindingsLost()
	if InCombatLockdown() then
		return false
	end
	if Typing() then
		return GetBindingAction("PADLSHOULDER", true) ~= "CLICK " .. BUTTON .. "Prev:LeftButton"
			or GetBindingAction("PADDUP", true) ~= "CLICK " .. BUTTON .. "Up:LeftButton"
			or GetBindingAction("PADLTRIGGER", true) ~= "CLICK " .. BUTTON .. "ChannelPrev:LeftButton"
	elseif mode == "browse" and MenuOpen() then
		return GetBindingAction("PADDUP", true) ~= "CLICK " .. BUTTON .. "Up:LeftButton"
	elseif mode == "browse" then
		return GetBindingAction("PADDUP", true) ~= "CLICK " .. BUTTON .. "BrowseUp:LeftButton"
			or GetBindingAction("PAD2", true) ~= "CLICK " .. BUTTON .. "Close:LeftButton"
	end
	return false
end

-- Typing in combat: bindings can't change there, so the chat box reads the controller's buttons itself
-- (as RollPicker.lua does) and presses the same buttons its bindings would. Out of combat the bindings
-- do it.
local PAD_TYPING = {
	PADLSHOULDER = "Prev", PADRSHOULDER = "Next", PADRSTICK = "Phrases", PADDLEFT = "ReplyPrev", PADDRIGHT = "ReplyNext",
	PADLSTICK = "AddReply", PADDUP = "Up", PADDDOWN = "Down",
	PAD3 = "Erase", PAD1 = "Send", PAD2 = "Back", PADLTRIGGER = "ChannelPrev", PADRTRIGGER = "ChannelNext",
}
function Line.ReadPad(on)
	if not box then
		return
	end
	if not Line.pad then
		Line.pad = CreateFrame("Frame", nil, box)
		Line.pad:SetScript("OnGamePadButtonDown", function(self, key)
			local name = PAD_TYPING[key]
			pcall(self.SetPropagateGamePadInput, self, name == nil and key ~= "PADBACK")
			if key == "PADBACK" then
				-- Back as out of the box: to a loot roll waiting (the roll picker), else out of the chat box.
				if ns.RollWaiting and ns.RollWaiting() and ns.OpenRollPicker then
					Log("combat pad: Back to the loot roll")
					ns.OpenRollPicker()
				else
					Log("combat pad: Back closes the chat box")
					mode = nil
					input:ClearFocus() -- OnEditFocusLost turns this off and redraws
				end
				return
			end
			local button = name and _G[BUTTON .. name]
			Log("combat pad:", tostring(key), name or "not the chat box's")
			if button and Typing() then
				button:Click("LeftButton", true)
			end
		end)
	end
	-- Never with the roll picker: it reads the buttons then, and the box takes them back after it.
	on = on and Typing() and InCombatLockdown() and not (ns.RollPickerShown and ns.RollPickerShown()) or false
	if Line.padOn ~= on then
		Line.padOn = on
		local ok, err = pcall(Line.pad.EnableGamePadButton, Line.pad, on)
		Log("combat pad", on and "on" or "off", ok and "" or tostring(err))
	end
end

function ns.ChatBoxReadPad(on)
	Line.ReadPad(on)
end

local function StartTyping()
	if ns.FocusChatBox then
		ns.FocusChatBox()
	end
end

-- Stops typing; with browse, the D-pad keeps scrolling the messages until {PAD2}.
local function StopTyping(browse)
	mode = (browse and not InCombatLockdown()) and "browse" or nil
	if Typing() then
		input:ClearFocus() -- OnEditFocusLost binds for the mode
	else
		ApplyBindings()
		Draw()
	end
	Log(mode == "browse" and "browsing" or "closed")
end

local function EndBrowse()
	if mode == "browse" then
		mode = nil
		ApplyBindings()
		Log("browse closed")
	end
	Draw()
end

-- Any click on the box: type.
local function StartFromMouse()
	if not Typing() then
		StartTyping()
	end
end

---------------------------------------------------------------------------------------------------
-- Tabs

local function Step(delta)
	local stops = Stops()
	local index
	for i, stop in ipairs(stops) do
		if stop.key == current then
			index = i
		end
	end
	if not index then
		for i, stop in ipairs(stops) do
			if stop.tab == TabOf(current) then
				index = i
				break
			end
		end
	end
	index = index or 1
	current = stops[(index - 1 + delta) % #stops + 1].key
	Log("tab", current)
	Draw()
end

local function SelectTab(tab)
	if tab == "whispers" then
		local whispers = RecentWhispers()
		current = whispers[1] and whispers[1].key or "whispers"
	else
		current = tab or "all"
	end
	Log("tab", current)
	Draw()
end

-- On the Whispers tab, {PADDUP} / {PADDDOWN} move through the players in the column on the left.
local function OnWhispers()
	return TabOf(current) == "whispers" and #RecentWhispers() > 0
end

local function WhisperStep(delta)
	local list = RecentWhispers()
	if #list == 0 then
		return
	end
	local index = 1
	for i, item in ipairs(list) do
		if item.key == current then
			index = i
		end
	end
	index = math.max(1, math.min(#list, index + delta))
	if list[index].key ~= current then
		current = list[index].key
		Log("whisper", current)
		Draw()
	end
end

-- On the All tab, {PADLTRIGGER} / {PADRTRIGGER} pick where the message goes: Say, the channels with a tab,
-- the other channels you are in, then your recent whispers.
function StepAllTarget(delta)
	if current ~= "all" then
		return
	end
	local list = { "#SAY" }
	local seen = { ["#SAY"] = true }
	for _, stop in ipairs((Stops())) do
		if IsChannelKey(stop.key) and not seen[stop.key] then
			seen[stop.key] = true
			list[#list + 1] = stop.key
		end
	end
	-- Every numbered channel you are in, with a tab or not: General, Trade, LookingForGroup, the defense ones.
	for _, key in ipairs(TabCandidates()) do
		if key:find("^#CH:") and not seen[key] then
			seen[key] = true
			list[#list + 1] = key
		end
	end
	for _, item in ipairs(RecentWhispers()) do
		if not seen[item.key] then
			seen[item.key] = true
			list[#list + 1] = item.key
		end
	end
	local index = 1
	for i, key in ipairs(list) do
		if key == allTarget then
			index = i
		end
	end
	allTarget = list[(index - 1 + delta) % #list + 1]
	Log("all tab sends to", allTarget)
	Draw()
end

-- Scrolled up when new messages come: back to the newest 10 seconds later, unless you keep scrolling.
local function ShownMessages()
	return current == "all" and feed or convo
end

local function NoteArrival()
	local frame = ShownMessages()
	if frame and frame.GetScrollOffset and frame:IsShown() and frame:GetScrollOffset() > 0 and not jumpAt then
		jumpAt = GetTime() + JUMP_SECONDS
	end
end

local function JumpIfDue()
	if jumpAt and GetTime() >= jumpAt then
		jumpAt = nil
		local frame = ShownMessages()
		if frame and frame.ScrollToBottom then
			frame:ScrollToBottom()
		end
	end
end

local function Scroll(delta)
	local frame = ShownMessages()
	if frame and delta < 0 and frame.GetScrollOffset and frame:GetScrollOffset() <= 1 then
		jumpAt = nil -- back at the newest by hand
	end
	if jumpAt then
		jumpAt = GetTime() + JUMP_SECONDS
	end
	if frame then
		if delta > 0 then
			frame:ScrollUp()
		else
			frame:ScrollDown()
		end
	end
	if Line.Soon then
		Line.Soon()
	end
end

---------------------------------------------------------------------------------------------------
-- The ready-made messages menu: the categories, then a category's messages.
local MENU_ROWS = 12
local ADDED_SECONDS = 1.5 -- how long "Added" shows in the menu
local TICK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t"

-- A ready-made message ("<ask>": the group finder message) into the message being typed, at the cursor.
local function AddToMessage(text, why)
	local api = API()
	text = api.ExpandPhrase and api.ExpandPhrase(text, Target()) or text
	if type(text) ~= "string" or strtrim(text) == "" then
		return false
	end
	if ns.ChatInsert(input, text) then
		Log("added to the message:", why)
		return true
	end
	ns.Print("That doesn't fit: a chat message holds 255 letters.")
	return false
end

-- The quick reply the D-pad picked, into the message.
local function AddReply()
	local replies = API().QuickReplies
	if replies and API().ReplyIndex then
		AddToMessage(replies[API().ReplyIndex()], "quick reply")
	end
end

local function MenuItems()
	if menuState.kind == "line" then
		return Line.items or {}
	end
	local phrases = API().Phrases or {}
	local items = {}
	if menuState.kind == "tabs" then
		local shown = {}
		for _, stop in ipairs((Stops())) do
			shown[stop.key] = true
		end
		for _, key in ipairs(TabCandidates()) do
			local channel = API().Info(key)
			local on = shown[key] and true or false
			local name = channel and channel.name or key
			name = name:gsub("(%l)(%u)", "%1 %2") -- LocalDefense -> Local Defense
			items[#items + 1] = { text = (on and "|cff40ff40[x]|r  " or "|cff777777[  ]|r  ")
				.. "|cff" .. (channel and channel.color or "ffffff") .. name .. "|r", value = key, on = on }
		end
		return items
	end
	if menuState.group then
		for _, text in ipairs(phrases[menuState.group] or {}) do
			items[#items + 1] = { text = text == "<ask>" and "Your group finder message" or text, value = text }
		end
	else
		for index, group in ipairs(phrases) do
			items[#items + 1] = { text = group.name .. "  >", value = index }
		end
	end
	return items
end

local function DrawMenu()
	if not MenuOpen() then
		return
	end
	local items = MenuItems()
	menuState.index = math.max(1, math.min(menuState.index, #items))
	local phrases = API().Phrases or {}
	menu.title:SetText(menuState.kind == "line" and (Line.title or "Options") or menuState.kind == "tabs" and "Channel tabs"
		or menuState.group and phrases[menuState.group] and phrases[menuState.group].name or "Ready-made messages")
	-- For a moment after {PAD1}: "Added" by the title and a tick on the message (or why it wasn't).
	local added = menuState.added
	if added and (added.group ~= menuState.group or GetTime() - added.at > ADDED_SECONDS) then
		added = nil
	end
	if added then
		menu.title:SetText(menu.title:GetText() .. (added.failed and "  |cffff6060Too long to add|r" or "  |cff40ff40Added|r"))
	end
	local first = math.max(1, math.min(menuState.index - math.floor(MENU_ROWS / 2), #items - MENU_ROWS + 1))
	for slot = 1, MENU_ROWS do
		local row = menu.rows[slot]
		local item = items[first + slot - 1]
		row:SetShown(item ~= nil)
		if item then
			local selected = first + slot - 1 == menuState.index
			row.text:SetText((added and not added.failed and added.index == first + slot - 1 and (TICK .. " ") or "") .. item.text)
			row.text:SetTextColor(selected and GOLD[1] or 0.9, selected and GOLD[2] or 0.9, selected and GOLD[3] or 0.9)
			row.bg:SetShown(selected)
			row.itemIndex = first + slot - 1
		end
	end
	menu:SetHeight(46 + math.min(#items, MENU_ROWS) * 20)
	menu.hint:SetText(Buttons("{PADDUP}{PADDDOWN} Move   {PAD1} "
		.. (menuState.kind == "line" and "Pick" or menuState.kind == "tabs" and "Tab on / off" or menuState.group and "Add" or "Open")
		.. "   {PAD2} Back", 13))
end

local function CloseMenu()
	if menu then
		menu:Hide()
	end
	ApplyBindings()
	Draw()
end

local function OpenMenu()
	if not menu then
		return
	end
	menuState.group, menuState.index, menuState.kind, menuState.added = nil, 1, nil, nil
	menu:Show()
	ApplyBindings()
	DrawMenu()
	Log("messages menu")
end

-- Channel tabs: on and off, from browse ({PAD3}), the settings or the menu.
local function OpenTabsMenu()
	if not menu then
		return
	end
	menuState.group, menuState.index, menuState.kind = nil, 1, "tabs"
	menu:Show()
	ApplyBindings()
	DrawMenu()
	Log("channel tabs menu")
end

local function MenuMove(delta)
	local items = MenuItems()
	if #items > 0 then
		menuState.index = (menuState.index - 1 + delta) % #items + 1
	end
	DrawMenu()
end

local function MenuPick(index)
	local item = MenuItems()[index or menuState.index]
	if not item then
		return
	end
	if menuState.kind == "line" then
		menuState.kind = nil
		menu:Hide()
		Log("line menu:", item.text)
		item.action()
		ApplyBindings()
		Draw()
		return
	end
	if menuState.kind == "tabs" then
		TabChoices()[item.value] = not item.on
		Log("channel tab", item.value, not item.on)
		if item.on and current == item.value then
			current = "all"
		end
		DrawMenu()
		Draw()
		return
	end
	if not menuState.group then
		menuState.group, menuState.index = item.value, 1
		DrawMenu()
		return
	end
	-- A message goes into what you are typing; the menu stays open for the next one.
	local ok = AddToMessage(item.value, "message menu")
	menuState.added = { group = menuState.group, index = index or menuState.index, at = GetTime(), failed = not ok }
	DrawMenu()
	if C_Timer and C_Timer.After then
		C_Timer.After(ADDED_SECONDS + 0.05, DrawMenu)
	end
end

local function MenuBack()
	if menuState.kind == "tabs" or menuState.kind == "line" then
		menuState.kind = nil
		CloseMenu()
	elseif menuState.group then
		menuState.index = menuState.group
		menuState.group = nil
		DrawMenu()
	else
		CloseMenu()
	end
end

---------------------------------------------------------------------------------------------------
-- Lines. While browsing, the line at the bottom of the messages is the picked one, marked with a
-- band: {PAD3} opens its menu (whisper, invite, who, friend or ignore its player; its link into a
-- message; the channel tabs), and an item linked in it shows its tooltip above the box, beside what
-- you wear in that slot. The mouse does the same on the links: a name whispers, Shift-click asks who
-- (or puts the name in while typing), a right-click opens the menu, an item shows its tooltip.

local LINK_TIPS = { item = true, spell = true, achievement = true, quest = true, currency = true, enchant = true,
	talent = true, mount = true, keystone = true, battlepet = true, transmogappearance = true, instancelock = true }

-- The bottom line on screen: its text, its rows (a wrapped line has several) and the frame.
function Line.Bottom()
	local frame = ShownMessages()
	if not (frame and frame:IsShown()) then
		return
	end
	local lowest, lowestBottom
	for _, row in ipairs(frame.visibleLines or {}) do
		local bottom = row:IsShown() and (row:GetText() or "") ~= "" and row:GetBottom()
		if bottom and (not lowestBottom or bottom < lowestBottom) then
			lowest, lowestBottom = row, bottom
		end
	end
	if lowest then
		local info = lowest.messageInfo
		local rows = { lowest }
		if info then
			rows = {}
			for _, row in ipairs(frame.visibleLines) do
				if row:IsShown() and row.messageInfo == info then
					rows[#rows + 1] = row
				end
			end
		end
		return info and info.message or lowest:GetText(), rows, frame
	end
	if frame.GetNumMessages and frame.GetMessageInfo then
		local index = frame:GetNumMessages() - (frame:GetScrollOffset() or 0)
		if index >= 1 then
			return (frame:GetMessageInfo(index)), nil, frame
		end
	end
end

-- A line's player (not you) and first link with a tooltip.
function Line.Parse(text)
	if type(text) ~= "string" then
		return
	end
	local player = text:match("|Hplayer:([^:|]+)")
	if player and Ambiguate and UnitName and Ambiguate(player, "short") == UnitName("player") then
		player = nil
	end
	local link
	for full, kind in text:gmatch("(|c[^|]*|H(%a+):.-|h.-|h|r)") do
		if LINK_TIPS[kind] then
			link = full
			break
		end
	end
	if not link then
		for full, kind in text:gmatch("(|H(%a+):.-|h.-|h)") do
			if LINK_TIPS[kind] then
				link = full
				break
			end
		end
	end
	return player, link
end

function Line.HideTip()
	if Line.tip then
		Line.tip:Hide()
		for _, tip in ipairs(Line.compare) do
			tip:Hide()
		end
	end
	Line.tipLink = nil
end

-- The link's tooltip above the box, and for an item what you wear in its slot beside it.
function Line.ShowTip(link, owner)
	if Line.tipLink == link and Line.tip and Line.tip:IsShown() then
		return
	end
	if not Line.tip then
		local function Tip(name)
			local tip = CreateFrame("GameTooltip", name, UIParent, "GameTooltipTemplate")
			tip:SetClampedToScreen(true)
			return tip
		end
		Line.tip = Tip("GamepadXIVChatItemTip")
		Line.compare = { Tip("GamepadXIVChatCompare1"), Tip("GamepadXIVChatCompare2") }
		for _, tip in ipairs(Line.compare) do
			local header = tip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			header:SetPoint("BOTTOMLEFT", tip, "TOPLEFT", 4, 2)
			header:SetText("Currently equipped")
		end
	end
	Line.HideTip()
	local hyper = link:match("|H(.-)|h")
	local tip = Line.tip
	if owner then
		-- Clicked in another window (LFG Filter's Chat): by the mouse.
		tip:SetOwner(owner, "ANCHOR_CURSOR")
	else
		tip:SetOwner(box, "ANCHOR_NONE")
		tip:ClearAllPoints()
		-- Above the "Back to the game" tag.
		tip:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 0, 34)
	end
	if not hyper or not pcall(tip.SetHyperlink, tip, hyper) then
		tip:Hide()
		return
	end
	tip:Show()
	Line.tipLink = link
	if hyper:find("^item:") and C_Item and C_Item.GetItemInfoInstant then
		local _, _, _, equipLoc = C_Item.GetItemInfoInstant(hyper)
		local previous = tip
		for index, slot in ipairs((ns.EQUIP_SLOTS or {})[equipLoc] or {}) do
			local compare = Line.compare[index]
			if compare and GetInventoryItemLink("player", slot) then
				compare:SetOwner(box, "ANCHOR_NONE")
				compare:ClearAllPoints()
				compare:SetPoint("BOTTOMLEFT", previous, "BOTTOMRIGHT", 6, 0)
				compare:SetInventoryItem("player", slot)
				compare:Show()
				previous = compare
			end
		end
	end
end

function Line.Unpin()
	if Line.pinned then
		Line.pinned, Line.pinnedOwner = nil, nil
		Line.HideTip()
	end
end

-- A link clicked in LFG Filter's Chat: its tooltip by the mouse, again to hide it. True when handled.
function ns.ChatLinkClicked(link, text, owner)
	local kind = tostring(link):match("^(%a+):")
	if not (kind and LINK_TIPS[kind]) then
		return false
	end
	if Line.pinned == text then
		Line.Unpin()
	else
		Line.pinned, Line.pinnedOwner = text, owner
		Line.ShowTip(text, owner)
	end
	return true
end

function ns.ChatLinkUnpin()
	Line.Unpin()
end

-- The band on the picked line and its item's tooltip, while browsing; a clicked link's tooltip stays.
function Line.Update()
	if not box then
		return
	end
	if not Line.band then
		Line.band = box:CreateTexture(nil, "BACKGROUND", nil, 2)
		Line.band:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.16)
		Line.band:Hide()
	end
	local browsing = box:IsShown() and mode == "browse" and not Typing()
	local text, rows, frame
	if browsing then
		text, rows, frame = Line.Bottom()
	end
	local top, bottom
	if rows and #rows > 0 then
		for _, row in ipairs(rows) do
			local rowTop, rowBottom = row:GetTop(), row:GetBottom()
			if rowTop and rowBottom then
				top = math.max(top or rowTop, rowTop)
				bottom = math.min(bottom or rowBottom, rowBottom)
			end
		end
	end
	if top and bottom and frame:GetBottom() then
		Line.band:ClearAllPoints()
		Line.band:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -4, bottom - frame:GetBottom() - 1)
		Line.band:SetPoint("RIGHT", frame, "RIGHT", 4, 0)
		Line.band:SetHeight(top - bottom + 2)
		Line.band:Show()
	else
		Line.band:Hide()
	end
	if menu and menu:IsShown() then
		-- The tooltip would cover the open menu.
		Line.HideTip()
		return
	end
	if Line.pinned then
		-- A clicked link's tooltip stays while the mouse is on the box (or the window it was clicked in)
		-- or on the tooltip, and closes once the mouse goes elsewhere.
		local near = (Line.pinnedOwner or box):IsMouseOver()
		for _, tip in ipairs(Line.tip and { Line.tip, unpack(Line.compare) } or {}) do
			near = near or (tip:IsShown() and tip:IsMouseOver())
		end
		if near and (Line.pinnedOwner or box):IsVisible() then
			Line.ShowTip(Line.pinned, Line.pinnedOwner)
			return
		end
		Line.pinned, Line.pinnedOwner = nil, nil
	end
	local _, link = Line.Parse(text)
	if browsing and link then
		Line.ShowTip(link)
	else
		Line.HideTip()
	end
end

-- After a scroll the frame lays its lines out again first.
function Line.Soon()
	if C_Timer and C_Timer.After then
		C_Timer.After(0, Line.Update)
	end
end

function Line.Whisper(name)
	local key = WhisperKey(name)
	if current == "all" then
		allTarget = key
	else
		current = key
	end
	Log("whisper from a line:", key)
	StartTyping()
end

local function Run(what, call, ...)
	local ok, err = pcall(call, ...)
	Log("line menu", what, ok and "done" or ("failed: " .. tostring(err)))
	if not ok then
		ns.Print("That couldn't be done from the chat box: " .. what .. ".")
	end
end

-- The menu for a player and a link (the picked line's, or a right-clicked name). pick: the entry to
-- start on ("who").
function Line.Menu(player, link, pick)
	if not menu then
		return
	end
	local items = {}
	if player then
		local name = Ambiguate and Ambiguate(player, "none") or player
		items[#items + 1] = { text = "Whisper", action = function() Line.Whisper(player) end }
		items[#items + 1] = { text = "Invite to group", action = function()
			Run("invite " .. name, C_PartyInfo and C_PartyInfo.InviteUnit or InviteUnit, name)
		end }
		items[#items + 1] = { key = "who", text = "Who is", action = function()
			Run("who " .. name, C_FriendList.SendWho, 'n-"' .. name .. '"', Enum.SocialWhoOrigin and Enum.SocialWhoOrigin.Chat)
		end }
		items[#items + 1] = { text = "Add friend", action = function() Run("friend " .. name, C_FriendList.AddFriend, name) end }
		items[#items + 1] = { text = "Ignore", action = function() Run("ignore " .. name, C_FriendList.AddIgnore, name) end }
	end
	if link then
		items[#items + 1] = { text = "Put the link in a message", action = function()
			StartTyping()
			ns.ChatInsert(input, link)
		end }
	end
	items[#items + 1] = { text = "Channel tabs  >", action = OpenTabsMenu }
	Line.items = items
	Line.title = player and API().Color(player) or "Options"
	menuState.group, menuState.index, menuState.kind = nil, 1, "line"
	for index, item in ipairs(items) do
		if pick and item.key == pick then
			menuState.index = index
		end
	end
	menu:Show()
	Line.HideTip()
	ApplyBindings()
	DrawMenu()
	Log("line menu for", tostring(player), link and "with a link" or "")
end

-- {PAD3} while browsing: the picked line's menu.
function Line.OpenMenu()
	local player, link = Line.Parse((Line.Bottom()))
	Line.Menu(player, link)
end

-- From the mouse: browse mode first, as the menu's keys are only bound there (out of combat).
function Line.MenuFromMouse(player, link, pick)
	if InCombatLockdown() then
		ns.Print("Player options open from the chat box out of combat.")
		return
	end
	mode = "browse"
	if Typing() then
		input:ClearFocus()
	else
		ApplyBindings()
	end
	Line.Menu(player, link, pick)
end

-- A click on a link in the messages, like the game's chat.
function Line.Click(link, text, button)
	Line.clicked = true
	local kind, rest = tostring(link):match("^(%a+):(.*)$")
	Log("link clicked:", tostring(kind), button, IsShiftKeyDown() and "shift" or "")
	if kind == "player" then
		local name = rest:match("^([^:]+)")
		if not name or name == "" then
			return
		end
		if button == "RightButton" then
			Line.MenuFromMouse(name, nil)
		elseif IsShiftKeyDown() then
			if Typing() then
				ns.ChatInsert(input, Ambiguate and Ambiguate(name, "none") or name)
			else
				Run("who " .. name, C_FriendList.SendWho, 'n-"' .. (Ambiguate and Ambiguate(name, "none") or name) .. '"',
					Enum.SocialWhoOrigin and Enum.SocialWhoOrigin.Chat)
			end
		else
			Line.Whisper(name)
		end
	elseif kind and LINK_TIPS[kind] then
		if IsShiftKeyDown() and Typing() then
			ns.ChatInsert(input, text)
		elseif Line.pinned == text then
			Line.Unpin()
		else
			Line.pinned = text
			Line.ShowTip(text)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Sending

-- A message with ready-made ones in it goes out between the raid markers, once (LfgFilter.lua's rules).
local function Decorated(target, text)
	if input.readyMade == true and API().Decorate then
		return API().Decorate(text, target)
	end
	return text
end

local function Send()
	local text = strtrim(input:GetText() or "")
	if text == "" then
		-- Nothing typed: the quick reply the D-pad picked goes in, to send with {PAD1} again.
		AddReply()
		return
	end
	if text:sub(1, 1) == "/" then
		local target, message = Command(text)
		if target == true then
			Remember(text)
			input:SetText("")
			input:ClearFocus()
			return
		elseif not target then
			if text:find("^/%S") and not OwnCommand(text) then
				-- A game command: only the secure macro button can run it, from {PAD1} out of combat.
				if InCombatLockdown() then
					ns.Print("Game commands such as /cast and emotes work from the chat box out of combat. In combat, use the \"/\" key, which opens the game's chat box.")
				else
					ns.Print(Buttons("Press {PAD1} to run game commands such as /reload; Enter can't run them.", 12))
				end
			else
				ns.Print("Type /w name and the message.")
			end
			return
		end
		-- On All you stay on All: the command picks where All's messages go, as in the game's chat.
		if message == "" then
			-- Just the channel or player: switch to it (on All: send there) and keep typing.
			if current == "all" then
				allTarget = target
			else
				current = target
			end
			input:SetText("")
			Draw()
			return
		end
		if API().Send(target, Decorated(target, message), "chat box command") then
			Remember(text)
			if current == "all" then
				allTarget = target
			else
				current = target
			end
			input:SetText("")
			input:ClearFocus()
		end
		return
	end
	local target = Target()
	if not target then
		ns.Print("No whispers yet: type /w name and the message.")
		return
	end
	if API().Send(target, Decorated(target, text), "chat box") then
		Remember(text)
		input:SetText("")
		input:ClearFocus()
	end
end

-- The secure button {PAD1} clicks for a game command. Made and set up out of combat only.
local function OnMacroRan(_, _, down)
	-- It runs on the press; the release comes after, so acting on it is after the command in any case.
	-- A command that starts a fight takes the keys away before the release: combat start finishes it.
	if down == true then
		macroPressed = true
		return
	end
	macroPressed = false
	local text = input and strtrim(input:GetText() or "") or ""
	Log("game command", text)
	Remember(text)
	if input then
		input:SetText("")
		mode = nil
		input:ClearFocus()
	end
end

local function EnsureMacroButton()
	if macroReady or InCombatLockdown() then
		return
	end
	macroButton = macroButton or CreateFrame("Button", MACRO, UIParent, "SecureActionButtonTemplate")
	macroButton:RegisterForClicks("AnyDown", "AnyUp")
	macroButton:SetAttribute("useOnKeyDown", true)
	macroButton:SetAttribute("type", "macro")
	macroButton:Hide()
	macroButton:HookScript("PostClick", OnMacroRan)
	macroReady = true
end

---------------------------------------------------------------------------------------------------
-- Drawing

local function HighlightOwn()
	return not (ns.db and ns.db.chatHighlightOwn == false)
end

local function Stamp(t)
	return "|cff777777" .. date("%H:%M", t or time()) .. "|r "
end

-- The game's colour for a conversation's chat type (ChatTypeInfo), for the message text.
local function LineColor(key, chat, own)
	local chatType
	local channel = API().Info(key)
	if channel then
		chatType = channel.chatType
		if chatType == "CHANNEL" and chat and chat.number and ChatTypeInfo and ChatTypeInfo["CHANNEL" .. chat.number] then
			chatType = "CHANNEL" .. chat.number
		end
	else
		chatType = own and "WHISPER_INFORM" or "WHISPER"
	end
	local info = ChatTypeInfo and chatType and ChatTypeInfo[chatType]
	if info and info.r then
		return info.r, info.g, info.b
	end
	return 1, 1, 1
end

-- A conversation line: time, who (class coloured), the message. Your own: a gold "You" and the bar.
-- A name you can click, and pick with the line menu ("Lines").
local function PlayerLink(name, shown)
	if type(name) ~= "string" or name == "" or not shown then
		return shown
	end
	return "|Hplayer:" .. name .. "|h" .. shown .. "|h"
end

local function FormatLine(line, who, to)
	local message = API().Icons(tostring(line.m or ""))
	if line.o then
		local own = HighlightOwn()
		local you = own and "|cffffd100You|r" or "|cff999999You|r"
		if to then
			you = you .. " |cff999999to|r " .. to
		end
		return (own and OWN_MARK or "") .. Stamp(line.t) .. you .. ": " .. message
	end
	return Stamp(line.t) .. (who and (who .. ": ") or "") .. message
end

local function CombatText(entry)
	return "|cff777777" .. date("%H:%M:%S", entry.t) .. "|r " .. entry.text
end

local function AddCombatLine(text, r, g, b)
	combatSeq = combatSeq + 1
	local entry = { text = text, r = r or 1, g = g or 1, b = b or 1, t = time() }
	combatLines[#combatLines + 1] = entry
	if #combatLines > MAX_COMBAT then
		table.remove(combatLines, 1)
	end
	-- Shown now: one more line rather than all of them again.
	if box and box:IsShown() and current == "combat" and shownSeq == "combat:" .. (combatSeq - 1) then
		shownSeq = "combat:" .. combatSeq
		convo:AddMessage(CombatText(entry), entry.r, entry.g, entry.b)
	end
end

-- The bottom of the box from the bottom up: the hint, the input, the quick reply, then the messages,
-- which keep at least MIN_MESSAGES of height.
local MIN_MESSAGES = 70
local columnFit = MAX_WHISPERS

local function Bottom(typing)
	local hintHeight = math.max(20, math.ceil(box.hint:GetStringHeight() or 20))
	local replyHeight = box.reply:IsShown() and math.max(20, math.ceil(box.reply:GetStringHeight() or 20)) or 0
	local inputBottom = 6 + hintHeight + 4
	local replyBottom = inputBottom + 26
	local messagesBottom = typing and (replyBottom + replyHeight + 4) or inputBottom
	return messagesBottom, inputBottom, replyBottom
end

local function Layout(typing)
	local messagesBottom, inputBottom, replyBottom = Bottom(typing)
	local height = box:GetHeight() or 0
	if height > 0 then
		messagesBottom = math.min(messagesBottom, height - 30 - 20)
		columnFit = math.max(1, math.min(MAX_WHISPERS, math.floor((height - 30 - messagesBottom) / 21)))
	end
	local key = messagesBottom .. ":" .. inputBottom .. ":" .. replyBottom .. ":" .. tostring(column:IsShown())
	if key == layoutKey then
		return
	end
	layoutKey = key
	prefix:ClearAllPoints()
	prefix:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 10, inputBottom + 4)
	box.reply:ClearAllPoints()
	box.reply:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 10, replyBottom)
	box.reply:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -10, replyBottom)
	local left = column:IsShown() and (8 + COLUMN_WIDTH + 6) or 8
	for _, frame in ipairs({ feed, convo }) do
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", box, "TOPLEFT", frame == convo and left or 8, -30)
		frame:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -8, messagesBottom)
	end
	column:ClearAllPoints()
	column:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -30)
	column:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 8, messagesBottom)
	column:SetWidth(COLUMN_WIDTH)
end

-- The hint and quick reply lines as big as the box has room for: smaller icons, then a shorter hint.
local function FitBottom(typing, hint, short, reply)
	local room = (box:GetHeight() or 0) - 30 - MIN_MESSAGES
	local width = (box:GetWidth() or 0) - 20
	-- The hint stays on one line: smaller icons first, then the short hint.
	local tries = { { hint, HINT_SIZE }, { hint, 14 }, { hint, 12 }, { short or hint, HINT_SIZE }, { short or hint, 12 } }
	for index, try in ipairs(tries) do
		box.hint:SetText(Buttons(try[1], try[2]))
		if reply then
			box.reply:SetText(Buttons(reply, try[2]))
		end
		local textWidth = box.hint.GetUnboundedStringWidth and box.hint:GetUnboundedStringWidth()
		local oneLine = width <= 0 or type(textWidth) ~= "number" or textWidth <= width
		if index == #tries or (oneLine and (room <= 0 or Bottom(typing) <= room)) then
			break
		end
	end
	Layout(typing)
	for slot = columnFit + 1, MAX_WHISPERS do
		column.rows[slot]:Hide()
	end
end

local function DrawTabs(stops)
	-- One button per tab: the whisper stops share the Whispers tab.
	local tabs, seen = {}, {}
	for _, stop in ipairs(stops) do
		if not seen[stop.tab] then
			seen[stop.tab] = true
			tabs[#tabs + 1] = { tab = stop.tab, chat = stop.tab == stop.key and stop.chat or nil }
		end
	end
	local selectedTab = TabOf(current)
	local index = 1
	for i, tab in ipairs(tabs) do
		tab.label = TabLabel(tab.tab, tab.chat)
		box.measure:SetText(tab.label)
		tab.width = box.measure:GetStringWidth() + 18
		if tab.tab == selectedTab then
			index = i
		end
	end
	-- As many tabs around the current one as fit between the two arrows.
	local room = (box:GetWidth() or 0) - 2 * (ARROW_WIDTH + 10)
	if room <= 0 then
		room = math.huge
	end
	local first, last, used = index, index, tabs[index].width
	while last - first + 1 < MAX_TABS do
		local grew = false
		if last < #tabs and used + 4 + tabs[last + 1].width <= room then
			last = last + 1
			used = used + 4 + tabs[last].width
			grew = true
		end
		if last - first + 1 < MAX_TABS and first > 1 and used + 4 + tabs[first - 1].width <= room then
			first = first - 1
			used = used + 4 + tabs[first].width
			grew = true
		end
		if not grew then
			break
		end
	end
	local x = 10 + ARROW_WIDTH
	for slot = 1, MAX_TABS do
		local button = tabButtons[slot]
		local tab = tabs[first + slot - 1]
		local shown = tab ~= nil and first + slot - 1 <= last
		button:SetShown(shown)
		if shown then
			button.text:SetText(tab.label)
			button:SetWidth(tab.width)
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", box, "TOPLEFT", x, -4)
			x = x + tab.width + 4
			local selected = tab.tab == selectedTab
			button:SetBackdropColor(selected and 0.24 or 0.1, selected and 0.2 or 0.1, selected and 0.07 or 0.13, selected and 0.95 or 0.7)
			button:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], selected and 0.9 or 0.15)
			button.tab = tab.tab
		end
	end
	box.prevTab.text:SetText(Buttons("{PADLSHOULDER}", 11))
	box.nextTab.text:SetText(Buttons("{PADRSHOULDER}", 11))
end

local function DrawColumn(whispers, show)
	column:SetShown(show)
	if not show then
		return
	end
	for slot = 1, MAX_WHISPERS do
		local row = column.rows[slot]
		local item = whispers[slot]
		row:SetShown(item ~= nil)
		if item then
			local unread = item.chat and item.chat.unread or 0
			row.key = item.key
			row.text:SetText(API().Color(item.key, item.chat and item.chat.class)
				.. (unread > 0 and (" |cffff5555(" .. unread .. ")|r") or ""))
			row.bg:SetShown(item.key == current)
		end
	end
end

-- Redraws the conversation with fill(), which returns how many lines it added. A new line on the one
-- you scrolled up in keeps your place, then jumps back to the newest later (NoteArrival); the same on
-- every tab. added: how many of them are new, when the list drops its oldest lines.
local function Refill(key, fill, added)
	local same = shownKey == key
	local offset = same and convo.GetScrollOffset and convo:GetScrollOffset() or 0
	local before = same and shownCount or 0
	shownKey = key
	convo:Clear()
	local count = fill()
	shownCount = count
	if offset > 0 and convo.SetScrollOffset then
		convo:SetScrollOffset(offset + math.max(0, added or (count - before)))
		NoteArrival()
	end
end

-- looking: typing or browsing. shown: the box is on screen, so a tab's conversation can be read.
local function DrawMessages(looking, shown)
	local own = HighlightOwn() and "1" or "0"
	if current == "all" then
		shownSeq = nil
		-- Everything shows in the feed: read once you look at it there, typing or browsing.
		if looking then
			for _, chat in pairs(API().Chats()) do
				chat.unread = 0
			end
		end
	elseif current == "combat" then
		local seq = "combat:" .. combatSeq
		if shownSeq ~= seq then
			local added = shownKey == "combat" and tonumber(shownSeq and shownSeq:match("^combat:(%d+)$"))
			added = added and math.max(0, combatSeq - added) or nil
			shownSeq = seq
			Refill("combat", function()
				if #combatLines == 0 then
					convo:AddMessage(combatRefused
						and "|cff999999The game's combat log shows here as it gets lines. If nothing comes, the game only fills it while its own Combat Log tab is open.|r"
						or "|cff999999Combat messages from this session show here.|r")
				end
				for _, entry in ipairs(combatLines) do
					convo:AddMessage(CombatText(entry), entry.r, entry.g, entry.b)
				end
				return #combatLines
			end, added)
		end
	elseif current == "whispers" then
		-- No recent conversation: every whisper line, in time order, each with who it's with.
		local lines, seq = {}, 0
		for name, chat in pairs(API().Chats()) do
			if not API().Info(name) then
				seq = seq + (chat.seq or 0) + #(chat.lines or {})
				for _, line in ipairs(chat.lines or {}) do
					lines[#lines + 1] = { line = line, name = name, chat = chat }
				end
				if (chat.unread or 0) > 0 and shown then
					chat.unread = 0
				end
			end
		end
		seq = "whispers:" .. seq .. ":" .. own
		if shownSeq ~= seq then
			shownSeq = seq
			table.sort(lines, function(a, b) return (a.line.t or 0) < (b.line.t or 0) end)
			Refill("whispers", function()
				for _, item in ipairs(lines) do
					local who = PlayerLink(item.name, API().Color(item.name, item.chat.class))
					convo:AddMessage(FormatLine(item.line, who, who), LineColor(item.name, item.chat, item.line.o))
				end
				return #lines
			end)
		end
	else
		local chat = API().Chats()[current]
		local seq = current .. ":" .. tostring(chat and chat.seq or 0) .. ":" .. own
		if shownSeq ~= seq then
			shownSeq = seq
			local whisper = not API().Info(current)
			Refill(current, function()
				local count = 0
				for _, line in ipairs(chat and chat.lines or {}) do
					local who = (line.s and PlayerLink(line.s, API().Color(line.s, line.c)))
						or (whisper and PlayerLink(current, API().Color(current, chat.class))) or nil
					convo:AddMessage(FormatLine(line, who), LineColor(current, chat, line.o))
					count = count + 1
				end
				return count
			end)
		end
		-- Read once it is on screen: a tab's conversation doesn't fade like the All feed.
		if chat and (chat.unread or 0) > 0 and shown then
			chat.unread = 0
		end
	end
end

local fadeOff -- the All feed stops fading while you type or browse, so scrolling shows every line
local function UpdateFade(active)
	if fadeOff == active then
		return
	end
	fadeOff = active
	local fade = tonumber(ns.db and ns.db.chatFade) or 30
	feed:SetFading(fade > 0 and not active)
	if fade > 0 then
		feed:SetTimeVisible(fade)
	end
	if active and feed.ResetAllFadeTimes then
		feed:ResetAllFadeTimes()
	end
end

function Draw()
	if not box or not box:IsShown() then
		return
	end
	local stops, whispers = Stops()
	local found = false
	for _, stop in ipairs(stops) do
		if stop.key == current then
			found = true
		end
	end
	if not found then
		current = (current == "whispers" and whispers[1]) and whispers[1].key or "all"
	end
	local typing = Typing()
	local browsing = mode == "browse"
	DrawTabs(stops)
	DrawColumn(whispers, TabOf(current) == "whispers" and #whispers > 0)

	-- All shows the feed; a tab shows its conversation.
	local all = current == "all"
	feed:SetShown(all)
	convo:SetShown(not all)
	DrawMessages(typing or browsing, box:IsVisible())
	UpdateFade(typing or browsing)

	input:SetShown(typing)
	prefix:SetShown(typing)
	local replies = API().QuickReplies
	local replyText
	box.reply:SetShown(typing and replies ~= nil)
	if typing and replies then
		local reply = replies[API().ReplyIndex()]
		if reply == "<ask>" then
			reply = "Your group finder message"
		end
		local empty = strtrim(input:GetText() or "") == ""
		replyText = "{PADDLEFT} " .. tostring(reply) .. " {PADDRIGHT}   |cffbbbbbb" .. (empty and "{PAD1}" or "{PADLSTICK}") .. " Add|r"
	end
	prefix:SetText(TargetText(current))
	local alpha = tonumber(ns.db and ns.db.chatBoxAlpha) or 0.45
	local active = typing or browsing
	box:SetBackdropColor(0.04, 0.04, 0.06, active and math.max(alpha, 0.85) or alpha)
	box:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], active and 0.6 or 0.2)
	if box.selected then
		box.selected:SetShown(active and true or false)
		if active then
			-- Typing, {PAD2} goes to browsing first, so leaving takes it twice.
			local tag = box.selected.tag
			-- In combat {PAD2} stops typing at once (no browsing there); otherwise Back closes it.
			local backKey = ns.BackOpensChat and ns.BackOpensChat()
			local keys = InCombatLockdown() and (typing and "{PAD2}" or backKey and "{PADBACK}" or "Escape:") or typing and "{PAD2}{PAD2}" or "{PAD2}"
			local text = Buttons(keys .. " Back to the game", 16)
			if tag.text:GetText() ~= text then
				tag.text:SetText(text)
				tag:SetWidth(math.max(120, (tag.text:GetStringWidth() or 0) + 20))
			end
		end
	end
	local hint, short
	if typing and InCombatLockdown() then
		hint = "|cffff8080In combat|r   {PADLSHOULDER}{PADRSHOULDER} Tab   {PADRSTICK} Ready-made messages   {PAD3} Erase   {PAD1} Send   {PAD2} Stop typing"
	elseif typing then
		-- The main keys only, in one line: D-pad up / down (sent lines) and the right stick (scroll) are in the
		-- Chat setting's tip, as the stick has no icon of its own.
		-- {PAD1} with nothing typed puts the quick reply in.
		local cross = macroBound and "Run" or strtrim(input:GetText() or "") == "" and "Add reply" or "Send"
		local channel = current == "all" and "{PADLTRIGGER}{PADRTRIGGER} Channel   " or ""
		hint = "{PADLSHOULDER}{PADRSHOULDER} Tab   " .. channel .. "{PADRSTICK} Ready-made messages   {PAD3} Erase   {PAD1} " .. cross
			.. "   {PAD4} Window   {PAD2} Browse"
		short = "{PADLSHOULDER}{PADRSHOULDER} Tab   {PADRSTICK} Ready-made messages   {PAD1} " .. cross .. "   {PAD2} Browse"
	elseif browsing then
		hint = "{PADLSHOULDER}{PADRSHOULDER} Tab   {PADDUP}{PADDDOWN} " .. (OnWhispers() and "Players" or "Scroll")
			.. "   {PAD3} Options   {PAD1} Type   {PAD2} Close"
	else
		local unread = API().Unread(true)
		hint = (unread > 0 and ("|cffff5555" .. unread .. " unread|r     ") or "") .. "Enter or {PADBACK}: chat"
	end
	FitBottom(typing, hint, short, replyText)
end

-- The look from the Chat settings: font, size, outline, how long new messages stay.
function ns.ChatBoxStyle()
	if not box then
		return
	end
	local db = ns.db or {}
	local defaultPath, defaultSize = (ChatFontNormal or GameFontHighlight):GetFont()
	local path = db.chatFont ~= "default" and db.chatFont or defaultPath
	local size = tonumber(db.chatFontSize) or defaultSize or 14
	local flags = db.chatFontOutline == "outline" and "OUTLINE" or db.chatFontOutline == "thick" and "THICKOUTLINE" or ""
	for _, frame in ipairs({ feed, convo, input }) do
		frame:SetFont(path, size, flags)
		if not frame:GetFont() then
			frame:SetFont(defaultPath, size, flags) -- a font that isn't there
		end
	end
	fadeOff = nil
	UpdateFade(Typing() or mode == "browse")
	shownSeq = nil -- redraw the conversation in the new font
	Draw()
end

function ns.ChatBoxRefresh()
	Draw()
end

-- A loot roll came up: the chat box stops typing or browsing and gives the controller back, so Back
-- and Forever's keys reach the roll window. What you typed stays in the box.
function ns.ChatBoxYield(why)
	if not box or InCombatLockdown() or not (Typing() or mode == "browse") then
		return
	end
	Log("gave the controller to", why)
	mode = nil
	if Typing() then
		input:ClearFocus()
	else
		ApplyBindings()
		Draw()
	end
end

-- A line of yours in the All feed: you are its speaker ("[You]: ", "[You] says: "), not just named in it.
local function OwnFeedLine(text)
	local name, rest = text:match("|Hplayer:([^:|]+)[^|]*|h.-|h(.*)$")
	if not (name and UnitName and Ambiguate and Ambiguate(name, "short") == UnitName("player")) then
		return false
	end
	return rest:find("^:") or rest:find("^ says:") or rest:find("^ yells:") or false
end

function ns.ChatBoxFeed(text, r, g, b)
	if feed then
		text = API() and API().Icons(text) or text
		if ns.db and ns.db.chatTimestamps then
			text = "|cff777777" .. date("%H:%M") .. "|r " .. text
		end
		if HighlightOwn() and OwnFeedLine(text) then
			text = OWN_MARK .. text
		end
		feed:AddMessage(text, r, g, b)
		if current == "all" then
			NoteArrival()
		end
	end
end

---------------------------------------------------------------------------------------------------
-- The Combat tab: the game's combat log lines while its frame is shown (it only gets them then), or a
-- short line of ours for what you and your pet do and what is done to you.

local combatFrame
local hitByUs, hitCount = {}, 0
local MINE = COMBATLOG_OBJECT_AFFILIATION_MINE or 1

local function HookCombatLog()
	if combatFrame then
		return
	end
	local frame = _G.COMBATLOG
	if not (type(frame) == "table" and frame.AddMessage) then
		frame = nil
		for index = 1, NUM_CHAT_WINDOWS or 10 do
			local name = GetChatWindowInfo and GetChatWindowInfo(index)
			if name and COMBAT_LOG and name == COMBAT_LOG then
				frame = _G["ChatFrame" .. index]
				break
			end
		end
	end
	if not frame then
		return
	end
	combatFrame = frame
	hooksecurefunc(frame, "AddMessage", function(self, text, r, g, b)
		if box and box:IsShown() and type(text) == "string" and not Secret(text) then
			AddCombatLine(text, Plain(r), Plain(g), Plain(b))
		end
	end)
	Log("combat tab follows", frame:GetName() or "the combat log")
end

local function Mine(flags)
	flags = Plain(flags)
	return type(flags) == "number" and bit and bit.band(flags, MINE) ~= 0 or false
end

local function CombatEvent()
	if not (box and box:IsShown()) or (combatFrame and combatFrame:IsVisible()) then
		return
	end
	local get = CombatLogGetCurrentEventInfo or (C_CombatLog and C_CombatLog.GetCurrentEventInfo)
	if not get then
		return
	end
	local info = { get() }
	local event, sourceGUID, sourceName, destGUID, destName = Plain(info[2]), Plain(info[4]), Plain(info[5]), Plain(info[8]), Plain(info[9])
	local mineSource, mineDest = Mine(info[6]), Mine(info[10])
	local me = UnitGUID("player")
	local function Who(guid, name, capital)
		if guid and guid == me then
			return capital and "You" or "you"
		end
		return name and API().Short(name) or "Something"
	end
	local function Whose(guid, name, spell)
		if guid and guid == me then
			return "Your " .. spell
		end
		return (name and API().Short(name) or "Something") .. "'s " .. spell
	end
	if event == "UNIT_DIED" then
		if destGUID and (mineDest or hitByUs[destGUID]) then
			hitByUs[destGUID] = nil
			AddCombatLine(Who(destGUID, destName, true) .. (destGUID == me and " die." or " dies."), GOLD[1], GOLD[2], GOLD[3])
		end
		return
	end
	if not (mineSource or mineDest) or not event then
		return
	end
	local text, crit
	local r, g, b = 1, 1, 1
	if event == "SWING_DAMAGE" then
		local amount = Plain(info[12])
		crit = Plain(info[18])
		if amount then
			text = Who(sourceGUID, sourceName, true) .. (sourceGUID == me and " hit " or " hits ") .. Who(destGUID, destName) .. " for " .. amount
		end
	elseif event == "SPELL_DAMAGE" or event == "SPELL_PERIODIC_DAMAGE" or event == "RANGE_DAMAGE" then
		local spell, amount = Plain(info[13]), Plain(info[15])
		crit = Plain(info[21])
		if spell and amount then
			text = Whose(sourceGUID, sourceName, spell) .. " hits " .. Who(destGUID, destName) .. " for " .. amount
		end
	elseif event == "SPELL_HEAL" or event == "SPELL_PERIODIC_HEAL" then
		local spell, amount = Plain(info[13]), Plain(info[15])
		crit = Plain(info[18])
		if spell and amount then
			text = Whose(sourceGUID, sourceName, spell) .. " heals " .. Who(destGUID, destName) .. " for " .. amount
			r, g, b = 0.4, 1, 0.4
		end
	elseif event == "SWING_MISSED" then
		local miss = Plain(info[12])
		if miss then
			text = Who(sourceGUID, sourceName, true) .. (sourceGUID == me and " miss " or " misses ") .. Who(destGUID, destName)
				.. " (" .. tostring(miss):lower() .. ")"
			r, g, b = 0.7, 0.7, 0.7
		end
	elseif event == "SPELL_MISSED" or event == "RANGE_MISSED" then
		local spell, miss = Plain(info[13]), Plain(info[15])
		if spell and miss then
			text = Whose(sourceGUID, sourceName, spell) .. " misses " .. Who(destGUID, destName) .. " (" .. tostring(miss):lower() .. ")"
			r, g, b = 0.7, 0.7, 0.7
		end
	end
	if not text then
		return
	end
	if mineDest and not mineSource and r == 1 then
		r, g, b = 1, 0.4, 0.4 -- done to you
	end
	if mineSource and destGUID and not mineDest then
		if not hitByUs[destGUID] then
			hitCount = hitCount + 1
			if hitCount > 200 then
				wipe(hitByUs)
				hitCount = 1
			end
		end
		hitByUs[destGUID] = true
	end
	AddCombatLine(text .. (crit and " (critical)" or "") .. ".", r, g, b)
end

---------------------------------------------------------------------------------------------------
-- Making the box

-- Over the game's chat frames, which are see-through but still take the mouse: in their strata (no
-- higher than MEDIUM, under the game's windows) and a few levels above the highest of them.
local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3 }
local function RaiseAboveChat()
	if not box then
		return
	end
	local strata, level = "LOW", 0
	local function Consider(frame)
		if type(frame) ~= "table" or not frame.GetFrameStrata or not frame:IsShown() then
			return
		end
		local frameStrata = frame:GetFrameStrata()
		if not STRATA[frameStrata] then
			return
		end
		if STRATA[frameStrata] > STRATA[strata] then
			strata, level = frameStrata, frame:GetFrameLevel()
		elseif frameStrata == strata then
			level = math.max(level, frame:GetFrameLevel())
		end
	end
	for index = 1, NUM_CHAT_WINDOWS or 10 do
		for _, suffix in ipairs({ "", "Tab", "EditBox", "ButtonFrame" }) do
			Consider(_G["ChatFrame" .. index .. suffix])
		end
	end
	for _, name in ipairs({ "GeneralDockManager", "ChatFrameMenuButton", "ChatFrameChannelButton",
			"CombatLogQuickButtonFrame_Custom" }) do
		Consider(_G[name])
	end
	local want = math.min(level + 10, 9000)
	if box:GetFrameStrata() ~= strata then
		box:SetFrameStrata(strata)
	end
	if box:GetFrameLevel() ~= want then
		box:SetFrameLevel(want)
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(_, event, arg)
	if event == "COMBAT_LOG_EVENT_UNFILTERED" then
		CombatEvent()
	elseif event == "PLAYER_REGEN_DISABLED" then
		-- The last moment bindings can change: the controller goes back to the game for the fight.
		if macroPressed then
			OnMacroRan(nil, nil, false)
		end
		if mode == "browse" then
			mode = nil
		end
		ClearOverrideBindings(owner)
		macroBound = false
		if Typing() and strtrim(input:GetText() or "") == "" then
			mode = nil
			input:ClearFocus()
		end
		-- Still typing: the controller keeps working in the box. InCombatLockdown is still false here.
		C_Timer.After(0, function() Line.ReadPad(true) end)
		Draw()
	elseif event == "PLAYER_REGEN_ENABLED" then
		Line.ReadPad(false)
		EnsureMacroButton()
		ApplyBindings()
		Draw()
	elseif event == "ADDON_LOADED" then
		if arg == "Blizzard_CombatLog" then
			HookCombatLog()
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		HookCombatLog()
		Links.Hook()
	end
end)

local combatEventOn = false
local function ListenToCombat(on)
	if on == combatEventOn then
		return
	end
	-- This client forbids COMBAT_LOG_EVENT_UNFILTERED to addons: even a pcall'd RegisterEvent raises
	-- ADDON_ACTION_FORBIDDEN (seen at every login). So the Combat tab only follows the game's combat log.
	combatEventOn = on
	combatRefused = true
end

local function Create()
	box = CreateFrame("Frame", "GamepadXIVChatBox", UIParent, "BackdropTemplate")
	box:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	box:SetFrameStrata("LOW")
	box:EnableMouse(true)
	box:SetScript("OnMouseDown", StartFromMouse)
	box:Hide()
	-- A bright frame around the box while it has the controller (typing or browsing).
	box.selected = CreateFrame("Frame", nil, box, "BackdropTemplate")
	box.selected:SetPoint("TOPLEFT", -3, 3)
	box.selected:SetPoint("BOTTOMRIGHT", 3, -3)
	box.selected:SetBackdrop({ edgeFile = WHITE, edgeSize = 2 })
	box.selected:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.95)
	box.selected:EnableMouse(false)
	-- A tag above the box's top left corner saying how to leave it ({PAD2}), as the frame alone is easy
	-- to miss. The messages menu opens over it.
	local tag = CreateFrame("Frame", nil, box.selected, "BackdropTemplate")
	tag:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	tag:SetBackdropColor(0.04, 0.04, 0.06, 0.92)
	tag:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.95)
	tag:SetPoint("BOTTOMLEFT", box.selected, "TOPLEFT", 0, 2)
	tag.text = tag:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	tag.text:SetPoint("CENTER")
	tag.text:SetText("")
	tag:SetSize(120, 24)
	box.selected.tag = tag
	box.selected:Hide()
	ns.PlaceChatBox()
	box.measure = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	box.measure:Hide()

	for slot = 1, MAX_TABS do
		local button = CreateFrame("Button", nil, box, "BackdropTemplate")
		button:SetHeight(20)
		button:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
		button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		button.text:SetPoint("CENTER")
		button:SetScript("OnClick", function(self)
			SelectTab(self.tab)
			StartFromMouse()
		end)
		tabButtons[slot] = button
	end
	-- {PADLSHOULDER} and {PADRSHOULDER} at the ends of the tabs: the previous and next tab.
	local function Arrow(point, x, delta)
		local button = CreateFrame("Button", nil, box)
		button:SetSize(ARROW_WIDTH, 20)
		button:SetPoint(point, box, point, x, -4)
		button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		button.text:SetPoint("CENTER")
		button:SetScript("OnClick", function()
			Step(delta)
			StartFromMouse()
		end)
		return button
	end
	box.prevTab = Arrow("TOPLEFT", 6, -1)
	box.nextTab = Arrow("TOPRIGHT", -6, 1)

	box.hint = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	box.hint:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 10, 6)
	box.hint:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -8, 6)
	box.hint:SetJustifyH("RIGHT")
	box.hint:SetTextColor(0.8, 0.8, 0.8)
	box.hint:SetWordWrap(true)
	if box.hint.SetMaxLines then
		box.hint:SetMaxLines(3) -- the typing hint takes two lines on a narrow box; the messages move up
	end

	local function Messages(name, fading)
		local frame = CreateFrame("ScrollingMessageFrame", name, box)
		frame:SetPoint("TOPLEFT", box, "TOPLEFT", 8, -30)
		frame:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -8, 72)
		frame:SetFontObject(ChatFontNormal or GameFontHighlight)
		frame:SetJustifyH("LEFT")
		frame:SetFading(fading)
		frame:SetTimeVisible(30)
		frame:SetFadeDuration(3)
		frame:SetMaxLines(MAX_COMBAT)
		frame:EnableMouse(true)
		frame:SetHyperlinksEnabled(true)
		frame:SetScript("OnHyperlinkClick", function(_, link, text, button)
			Line.Click(link, text, button)
		end)
		-- A click that isn't on a link types, as before; one on a link does what the link does.
		frame:SetScript("OnMouseUp", function(_, button)
			C_Timer.After(0, function()
				if Line.clicked then
					Line.clicked = nil
				elseif button == "LeftButton" then
					Line.Unpin()
					StartFromMouse()
				end
			end)
		end)
		frame:EnableMouseWheel(true)
		frame:SetScript("OnMouseWheel", function(self, delta)
			if delta > 0 then
				self:ScrollUp()
			else
				self:ScrollDown()
			end
			Line.Soon()
		end)
		return frame
	end
	feed = Messages("GamepadXIVChatFeed", true)
	convo = Messages("GamepadXIVChatConversation", false)

	-- The Whispers tab's column of recent conversations.
	column = CreateFrame("Frame", "GamepadXIVChatBoxWhispers", box, "BackdropTemplate")
	column:SetBackdrop({ bgFile = WHITE })
	column:SetBackdropColor(0, 0, 0, 0.25)
	column:Hide()
	column.rows = {}
	for slot = 1, MAX_WHISPERS do
		local row = CreateFrame("Button", nil, column)
		row:SetHeight(20)
		row:SetPoint("TOPLEFT", column, "TOPLEFT", 0, -(slot - 1) * 21)
		row:SetPoint("RIGHT", column, "RIGHT", 0, 0)
		row.bg = row:CreateTexture(nil, "BACKGROUND")
		row.bg:SetAllPoints()
		row.bg:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.2)
		row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.text:SetPoint("LEFT", 6, 0)
		row.text:SetPoint("RIGHT", -4, 0)
		row.text:SetJustifyH("LEFT")
		row.text:SetWordWrap(false)
		row:SetScript("OnClick", function(self)
			if self.key then
				current = self.key
				Log("tab", current)
				Draw()
			end
			StartFromMouse()
		end)
		column.rows[slot] = row
	end

	box.reply = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	box.reply:SetJustifyH("LEFT")
	box.reply:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	box.reply:SetWordWrap(false)
	prefix = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	input = CreateFrame("EditBox", "GamepadXIVChatBoxInput", box, "InputBoxTemplate")
	input:SetPoint("LEFT", prefix, "RIGHT", 10, 0)
	input:SetPoint("RIGHT", box, "RIGHT", -10, 0)
	input:SetHeight(22)
	input:SetAutoFocus(false)
	input:SetMaxLetters(255)
	-- As in the game's chat box, a link's colour and link codes don't count toward the 255 letters.
	if input.SetCountInvisibleLetters then
		input:SetCountInvisibleLetters(false)
	end
	input:Hide()
	input:SetScript("OnEnterPressed", function(self)
		-- Enter with nothing typed stops typing, as in the game's chat; {PAD1} adds the quick reply then.
		if strtrim(self:GetText() or "") == "" then
			mode = nil
			self:ClearFocus()
		else
			Send()
		end
	end)
	input:SetScript("OnTextChanged", function(self)
		if (self:GetText() or "") == "" then
			self.readyMade = nil
		end
		UpdateMacroKey()
		Draw()
	end)
	input:SetScript("OnEscapePressed", function(self)
		mode = nil
		self:ClearFocus()
	end)
	input:SetScript("OnTabPressed", function()
		Step(IsShiftKeyDown() and -1 or 1)
	end)
	input:SetScript("OnEditFocusGained", function()
		mode = "typing"
		recall = nil
		ApplyBindings()
		Line.ReadPad(true)
		Draw()
	end)
	input:SetScript("OnEditFocusLost", function()
		Links.lostAt = GetTime() -- a Shift-click can take the focus before its link comes
		if MenuOpen() then
			menu:Hide()
		end
		if mode ~= "browse" then
			mode = nil
		end
		ApplyBindings()
		Line.ReadPad(false)
		Draw()
	end)

	menu = CreateFrame("Frame", "GamepadXIVChatBoxMenu", box, "BackdropTemplate")
	menu:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	menu:SetBackdropColor(0.06, 0.06, 0.08, 0.97)
	menu:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.6)
	menu:SetFrameStrata("DIALOG")
	menu:SetWidth(300)
	-- Above the "Back to the game" tag, so the tag never covers its last entries.
	menu:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 0, 34)
	menu:EnableMouse(true)
	menu:Hide()
	menu.title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	menu.title:SetPoint("TOPLEFT", 10, -8)
	menu.hint = menu:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	menu.hint:SetPoint("BOTTOMLEFT", 10, 6)
	menu.rows = {}
	for slot = 1, MENU_ROWS do
		local row = CreateFrame("Button", nil, menu)
		row:SetHeight(20)
		row:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -26 - (slot - 1) * 20)
		row:SetPoint("RIGHT", menu, "RIGHT", -4, 0)
		row.bg = row:CreateTexture(nil, "BACKGROUND")
		row.bg:SetAllPoints()
		row.bg:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.15)
		row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.text:SetPoint("LEFT", 8, 0)
		row.text:SetPoint("RIGHT", -8, 0)
		row.text:SetJustifyH("LEFT")
		row.text:SetWordWrap(false)
		row:SetScript("OnClick", function(self)
			menuState.index = self.itemIndex or menuState.index
			MenuPick(self.itemIndex)
		end)
		menu.rows[slot] = row
	end

	local actions = {
		Prev = function() if not MenuOpen() then Step(-1) end end,
		Next = function() if not MenuOpen() then Step(1) end end,
		Send = function()
			if MenuOpen() then
				MenuPick()
			else
				Send()
			end
		end,
		Back = function()
			if MenuOpen() then
				MenuBack()
			else
				StopTyping(true)
			end
		end,
		Phrases = function()
			if MenuOpen() then
				CloseMenu()
			else
				OpenMenu()
			end
		end,
		Erase = function() ns.ChatErase(input) end,
		AddReply = AddReply,
		ReplyPrev = function() if API().ReplyIndex then API().ReplyIndex(-1) end Draw() end,
		ReplyNext = function() if API().ReplyIndex then API().ReplyIndex(1) end Draw() end,
		Up = function()
			if MenuOpen() then
				MenuMove(-1)
			elseif OnWhispers() then
				WhisperStep(-1)
			else
				Recall(-1)
			end
		end,
		Down = function()
			if MenuOpen() then
				MenuMove(1)
			elseif OnWhispers() then
				WhisperStep(1)
			else
				Recall(1)
			end
		end,
		-- Browse: the D-pad moves through the players on the Whispers tab, and scrolls elsewhere.
		BrowseUp = function() if OnWhispers() then WhisperStep(-1) else Scroll(1) end end,
		BrowseDown = function() if OnWhispers() then WhisperStep(1) else Scroll(-1) end end,
		ChannelPrev = function() StepAllTarget(-1) end,
		ChannelNext = function() StepAllTarget(1) end,
		ScrollUp = function() Scroll(1) end,
		ScrollDown = function() Scroll(-1) end,
		Window = function()
			local key = current == "whispers" and LastWhisper() or (current ~= "all" and current ~= "combat" and current) or nil
			mode = nil
			input:ClearFocus()
			API().OpenWindow(key)
		end,
		Type = StartTyping,
		Close = EndBrowse,
		Tabs = function() Line.OpenMenu() end,
	}
	-- Which actions work in browse mode, and which only there.
	local BROWSE = { Prev = true, Next = true, ScrollUp = true, ScrollDown = true, BrowseUp = true, BrowseDown = true,
		Type = true, Close = true, Tabs = true }
	local BROWSE_MENU = { Up = true, Down = true, Send = true, Back = true } -- the channel tabs menu while browsing
	local BROWSE_ONLY = { Type = true, Close = true, Tabs = true, BrowseUp = true, BrowseDown = true }
	-- The D-pad and stick ones repeat while held, as long as they keep doing the same thing.
	local function MenuOrSent()
		return MenuOpen() and "menu" or OnWhispers() and "players" or "sent"
	end
	local function BrowseWhat()
		return OnWhispers() and "players" or current
	end
	local function Showing()
		return current
	end
	local held = { Up = MenuOrSent, Down = MenuOrSent, ReplyPrev = true, ReplyNext = true, ScrollUp = Showing, ScrollDown = Showing,
		BrowseUp = BrowseWhat, BrowseDown = BrowseWhat }
	for name, action in pairs(actions) do
		local button = CreateFrame("Button", BUTTON .. name, box)
		local function OnClick()
			if Typing() then
				if not BROWSE_ONLY[name] then
					action()
				end
			elseif mode == "browse" and (BROWSE[name] or (BROWSE_MENU[name] and MenuOpen())) then
				action()
			end
		end
		if held[name] then
			ns.RepeatOnHold(button, OnClick, type(held[name]) == "function" and held[name] or nil)
		else
			button:RegisterForClicks("AnyDown")
			button:SetScript("OnClick", OnClick)
		end
	end
	if InputDeviceIconSetManager and InputDeviceIconSetManager.RegisterActiveInputDeviceIconSetUpdatedCallback then
		InputDeviceIconSetManager:RegisterActiveInputDeviceIconSetUpdatedCallback(function()
			layoutKey = nil
			Draw()
			DrawMenu()
		end, box)
	end
	box:SetScript("OnHide", function()
		Line.pinned = nil
		Line.HideTip()
		if Typing() then
			mode = nil
			input:ClearFocus()
		end
		if mode == "browse" then
			mode = nil
			ApplyBindings()
		end
	end)
	box:SetScript("OnSizeChanged", function()
		layoutKey = nil
	end)
	-- The tab counts tick on while nothing redraws; the keys and the place over the game's chat are
	-- checked more often.
	local elapsed, check = 0, 0
	box:SetScript("OnUpdate", function(_, delta)
		check = check + delta
		if check >= 0.25 then
			check = 0
			if BindingsLost() then
				-- Forever's window navigation binds the buttons to its InputFunctionBindingButton_ keys
				-- while one of its windows (bags, character...) has focus: give way instead of fighting
				-- it four times a second, so Circle closes that window again.
				local taken
				for _, key in ipairs({ "PAD1", "PAD2", "PADDUP", "PADDDOWN" }) do
					local action = GetBindingAction(key, true)
					if type(action) == "string" and action:find("InputFunctionBindingButton_", 1, true) then
						taken = key .. " " .. action
						break
					end
				end
				if taken then
					Log("a game window has the controller (" .. taken .. "): stopped typing")
					mode = nil
					if Typing() then
						input:ClearFocus()
					else
						ApplyBindings()
						Draw()
					end
				else
					Log("keys taken back")
					ApplyBindings()
				end
			end
		end
		if check == 0 then
			Line.Update()
		end
		elapsed = elapsed + delta
		if elapsed >= 1 then
			elapsed = 0
			RaiseAboveChat()
			JumpIfDue()
			Draw()
		end
	end)
	EnsureMacroButton()
	HookCombatLog()
	ns.ChatBoxStyle()
end

-- The chat box's own size from the settings (chatBoxWidth / chatBoxHeight, 0 = the game's chat size).
ns.CHAT_BOX_MIN_WIDTH, ns.CHAT_BOX_MIN_HEIGHT = 300, 150
ns.CHAT_BOX_MAX_WIDTH, ns.CHAT_BOX_MAX_HEIGHT = 1200, 800
local function OwnSize(key, low, high)
	local value = tonumber(ns.db and ns.db[key]) or 0
	if value <= 0 then
		return nil
	end
	return math.max(low, math.min(high, value))
end

-- Where the game's chat was, or where Move bars put it (chatBoxX / chatBoxY from the screen's middle);
-- the game's chat size, or the one from the settings or the Move bars grip.
function ns.PlaceChatBox()
	if not box then
		return
	end
	local db = ns.db or {}
	local width, height = 440, 230
	if ChatFrame1 and ChatFrame1:GetWidth() > 0 then
		width, height = ChatFrame1:GetWidth() + 12, ChatFrame1:GetHeight() + 64
	end
	local ownWidth = OwnSize("chatBoxWidth", ns.CHAT_BOX_MIN_WIDTH, ns.CHAT_BOX_MAX_WIDTH)
	local ownHeight = OwnSize("chatBoxHeight", ns.CHAT_BOX_MIN_HEIGHT, ns.CHAT_BOX_MAX_HEIGHT)
	width, height = ownWidth or width, ownHeight or height
	box:ClearAllPoints()
	if db.chatBoxMoved then
		box:SetSize(width, height)
		box:SetPoint("CENTER", UIParent, "CENTER", db.chatBoxX or 0, db.chatBoxY or 0)
	elseif ChatFrame1 and (ownWidth or ownHeight) then
		box:SetSize(width, height)
		box:SetPoint("BOTTOMLEFT", ChatFrame1, "BOTTOMLEFT", -6, -34)
	elseif ChatFrame1 then
		box:SetPoint("TOPLEFT", ChatFrame1, "TOPLEFT", -6, 30)
		box:SetPoint("BOTTOMRIGHT", ChatFrame1, "BOTTOMRIGHT", 6, -34)
	else
		box:SetPoint("BOTTOMLEFT", 30, 100)
		box:SetSize(width, height)
	end
	layoutKey = nil
	if box:IsShown() then
		Draw()
	end
end

-- The chat box, made if it isn't yet (for Move bars).
function ns.ChatBoxFrame()
	if not box then
		Create()
	end
	return box
end

function ns.ChatBoxSetShown(shown)
	if not box then
		Create()
	end
	if not shown then
		if Typing() then
			mode = nil
			input:ClearFocus()
		end
		if mode == "browse" then
			mode = nil
			ApplyBindings()
		end
	end
	box:SetShown(shown and true or false)
	ListenToCombat(shown and true or false)
	if shown then
		RaiseAboveChat()
	end
	Draw()
end

-- Enter, Back or a click: type in the chat box.
-- The channel tabs menu, from the settings: browse mode with the menu open.
function ns.ChatBoxChooseTabs()
	if InCombatLockdown() then
		ns.Print("Channel tabs can be chosen out of combat.")
		return
	end
	if not box or not box:IsShown() then
		ns.Print("Channel tabs are for the chat box: set Chat to \"Chat window (controller)\" first.")
		return
	end
	mode = "browse"
	ApplyBindings()
	OpenTabsMenu()
	Draw()
end

-- Back or the Open Chat key with the chat box already typing or browsing: it gives the controller
-- back. In combat {PAD2} can't be bound to the chat box, so this is the way out there.
function ns.ChatBoxActive()
	return box and (Typing() or mode == "browse") and true or false
end

function ns.CloseChatBox()
	if box and (Typing() or mode == "browse") then
		Log("closed with Back")
		StopTyping(false)
	end
end

function ns.FocusChatBox()
	if not box or not box:IsShown() then
		if ns.OpenGamepadChat then
			ns.OpenGamepadChat(true)
		end
		return
	end
	Log("typing, tab", current)
	mode = "typing"
	input:Show()
	input:SetFocus()
	Links.PutHeld()
end

---------------------------------------------------------------------------------------------------
-- Links. The game puts a Shift-clicked link in its open chat box (ChatFrameUtil.InsertLink), and
-- Forever's Share in Chat opens the game's chat box with the link in it (ChatFrameUtil.OpenChat, as
-- ChatFrameUtil.LinkItem does with no chat box open). While the chat box replaces the game's chat,
-- these hooks bring the link here. They run after the game's function and only read its arguments.
-- Nothing here writes the game's chat state or takes the focus from its box: either runs the game's
-- chat code as this addon's and taints it, which ends in the "blocked from an action" popup. So Share
-- in Chat still opens the game's box (the game's chat shows while it is open, LfgFilter.lua): the link
-- can be sent from there, and when that box closes without sending it, the chat box opens with it.
do
	local HELD_SECONDS = 30 -- a link Shift-clicked with the chat box closed waits this long for it
	local HANDOFF_SECONDS = 600
	local taken -- the link the hooks saw last: { text, at, opened, tried, inserted }
	local handoff -- the link the game's box opened with: { text, at, inserted }
	local held -- a link waiting for the chat box to open: { text, at }
	local hooked = {}
	local told

	local function On()
		return input and ns.db and ns.db.chatUI == "gxiv" and true or false
	end

	-- The game's chat box is open to type in (as LfgFilter.lua tells it). In the "im" chat style the
	-- box stays the active one after it closes, so being active alone isn't enough.
	local function GameChatOpen()
		local editBox = (ChatFrameUtil and ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow())
			or (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow())
		return editBox and editBox:IsShown() and editBox:HasFocus() and true or false
	end

	-- The letters a message shows: colour codes and the link data take no room in chat's 255. A colour
	-- is |c and eight hex digits, or a named one: this client's item links start with |cnIQ3:.
	function Links.Visible(text)
		local shown = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:|]*:", ""):gsub("|r", "")
			:gsub("|H.-|h", ""):gsub("|h", ""):gsub("|T.-|t", "?"):gsub("|A.-|a", "?")
		local _, letters = shown:gsub("[^\128-\191]", "")
		return letters
	end

	-- Where the link that ends just before the cursor starts, its colour included, so erasing takes it
	-- out whole instead of leaving half a code that chat won't send. Nil when no link ends there.
	function Links.StartBefore(before)
		if before:sub(-2) ~= "|h" and before:sub(-4) ~= "|h|r" then
			return nil
		end
		local start
		for at in before:gmatch("()|H") do
			start = at
		end
		if not start then
			return nil
		end
		local colour = before:sub(1, start - 1)
		return colour:match("()|c%x%x%x%x%x%x%x%x$") or colour:match("()|cn[^:|]*:$") or start
	end

	local function TooLong()
		ns.Print("The link doesn't fit in the chat box: the message would be too long.")
		Log("link too long for the message")
		return false
	end

	-- Into the input at its cursor, as the raw link text: whole, or not at all.
	local function Put(text)
		local before, cursor = input:GetText() or "", input:GetCursorPosition()
		local max = input.GetMaxLetters and input:GetMaxLetters() or 255
		if max and max > 0 and Links.Visible(before .. text) > max then
			return TooLong()
		end
		input:Insert(text)
		-- The edit box cut it anyway (it counts the letters its own way): a cut link can't be sent.
		if not (input:GetText() or ""):find(text, 1, true) then
			input:SetText(before)
			input:SetCursorPosition(cursor)
			return TooLong()
		end
		return true
	end

	local function HandOff(text, at, inserted)
		handoff = { text = text, at = at, inserted = inserted }
		if not told then
			told = true
			ns.Print("Send the link from the game's chat box, or close that box to move the link to the chat box.")
		end
	end

	-- A frame after a link came: where it went decides what the chat box does.
	local function Settle()
		local link = taken
		if not link or not On() then
			return
		end
		if GameChatOpen() then
			-- Share in Chat opened the game's box with the link. A Shift-click into a game's box the
			-- player opened stays there.
			if link.opened then
				HandOff(link.text, link.at, link.inserted)
			end
		elseif link.tried then
			return
		elseif Typing() then
			link.tried = true
			link.inserted = Put(link.text)
		elseif Links.lostAt and link.at >= Links.lostAt and link.at - Links.lostAt <= 1 and box:IsShown()
				and not (GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()) then
			-- The click took the focus from the chat box just before: typing again, with the link.
			link.tried = true
			ns.FocusChatBox()
			link.inserted = Put(link.text)
		elseif ns.db.chatLinks then
			-- Nothing took it (a Shift-click with chat closed): it goes in when the chat box opens.
			held = { text = link.text, at = link.at }
			if UIErrorsFrame then
				UIErrorsFrame:AddMessage(link.text .. " - open chat to post it", 1, 0.82, 0)
			end
		end
	end

	local function Take(text, opened, how)
		if not On() or type(text) ~= "string" or Secret(text) or not text:find("|H", 1, true) then
			return
		end
		local now = GetTime()
		-- One click can pass through several of the hooked functions.
		if taken and taken.text == text and taken.at == now then
			taken.opened = taken.opened or opened
			return
		end
		taken = { text = text, at = now, opened = opened }
		Log("link from", how)
		-- Typing here: in at the cursor now. Share in Chat has already moved the focus to the game's box.
		if Typing() then
			taken.tried = true
			taken.inserted = Put(text)
		end
		C_Timer.After(0, Settle)
	end

	local function Sent(text)
		if handoff and type(text) == "string" and not Secret(text) and text:find(handoff.text, 1, true) then
			handoff = nil
			Log("link sent from the game's chat box")
		end
	end

	-- LfgFilter.lua: the game's chat box opened. If it opened with a link none of the hooks saw (code
	-- that kept its own copy of the function), the link is handed off the same way. Only reads the box.
	function ns.ChatBoxGameChatOpened()
		if not On() or (handoff and GetTime() - handoff.at < 2) then
			return
		end
		local editBox = (ChatFrameUtil and ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow())
			or (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow())
		if not editBox then
			return
		end
		local text = editBox:GetText()
		if Secret(text) then
			return
		end
		-- OpenChat's text goes in on the box's next update.
		if (type(text) ~= "string" or text == "") and editBox.setText == 1 then
			text = editBox.text
		end
		if type(text) == "string" and not Secret(text) and text:find("|H", 1, true) then
			Log("link found in the game's chat box")
			HandOff(text, GetTime(), false)
		end
	end

	-- LfgFilter.lua: the game's chat box closed and the chat box shows again.
	function ns.ChatBoxGameChatClosed()
		local link = handoff
		handoff = nil
		if not link or not On() or GetTime() - link.at > HANDOFF_SECONDS then
			return
		end
		local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
		if focus and focus ~= input then
			-- Another box is typing: taking its focus would run its code as this addon's.
			if not link.inserted then
				held = { text = link.text, at = GetTime() }
			end
			return
		end
		Log("link moved from the game's chat box")
		ns.FocusChatBox()
		if not link.inserted then
			Put(link.text)
		end
	end

	function Links.PutHeld()
		local link = held
		held = nil
		if link and On() and GetTime() - link.at <= HELD_SECONDS then
			Put(link.text)
		end
	end

	local function Hook(target, key, name, handler)
		if hooked[key] or type(target) ~= "table" or type(target[name]) ~= "function" then
			return
		end
		hooked[key] = true
		if target == _G then
			pcall(hooksecurefunc, name, handler)
		else
			pcall(hooksecurefunc, target, name, handler)
		end
	end

	-- The ChatFrameUtil functions and the older globals that may still point at the original ones.
	function Links.Hook()
		Hook(ChatFrameUtil, "util insert", "InsertLink", function(text) Take(text, false, "ChatFrameUtil.InsertLink") end)
		Hook(ChatFrameUtil, "util open", "OpenChat", function(text) Take(text, true, "ChatFrameUtil.OpenChat") end)
		Hook(_G, "insert", "ChatEdit_InsertLink", function(text) Take(text, false, "ChatEdit_InsertLink") end)
		Hook(_G, "open", "ChatFrame_OpenChat", function(text) Take(text, true, "ChatFrame_OpenChat") end)
		Hook(_G, "item", "HandleModifiedItemClick", function(link)
			if IsModifiedClick and IsModifiedClick("CHATLINK") then
				Take(link, false, "HandleModifiedItemClick")
			end
		end)
		Hook(C_ChatInfo, "info send", "SendChatMessage", Sent)
		Hook(_G, "send", "SendChatMessage", Sent)
	end
	Links.Hook()
end
