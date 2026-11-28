-- Offline checks of the chat box (ChatBox.lua): typing and browse modes and their keys, recalling sent
-- lines, game commands through the macro button, the whisper stops, the Combat tab and the colours.
-- Not loaded by the game. Run from the addon folder with: lua5.1 tests/chatbox.lua
-- The WoW API is stubbed just enough to run the file; it cannot prove in-game behaviour.

local fails = 0
local function Check(label, actual, expected)
	if actual ~= expected then
		fails = fails + 1
		print("FAIL " .. label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

---------------------------------------------------------------------------------------------------
-- Stubs

local frames = {}
local focused -- the EditBox with the keyboard focus
local methods = {}
local function Noop() end
local function NewFrame(kind, name, parent)
	local frame = { kind = kind, name = name, scripts = {}, hooks = {}, shown = kind ~= "Frame" or true,
		attributes = {}, lines = {}, text = "", parent = parent, strata = "LOW", level = 1, width = 440 }
	frame.shown = true
	setmetatable(frame, { __index = function(_, key) return methods[key] or Noop end })
	frames[#frames + 1] = frame
	if name then
		_G[name] = frame
	end
	return frame
end
local function Run(frame, script, ...)
	if frame.scripts[script] then
		frame.scripts[script](frame, ...)
	end
	for _, hook in ipairs(frame.hooks[script] or {}) do
		hook(frame, ...)
	end
end
function methods:SetScript(script, fn) self.scripts[script] = fn end
function methods:GetScript(script) return self.scripts[script] end
function methods:HookScript(script, fn)
	self.hooks[script] = self.hooks[script] or {}
	table.insert(self.hooks[script], fn)
end
function methods:Show() if not self.shown then self.shown = true; Run(self, "OnShow") end end
function methods:Hide() if self.shown then self.shown = false; Run(self, "OnHide") end end
function methods:SetShown(shown) if shown then self:Show() else self:Hide() end end
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown and (not self.parent or self.parent == UIParent or self.parent:IsVisible()) end
function methods:GetName() return self.name end
function methods:SetText(text)
	self.text = text or ""
	self.cursor = nil
	if self.kind == "EditBox" then
		Run(self, "OnTextChanged", false)
	end
end
function methods:GetText() return self.text end
function methods:GetCursorPosition() return rawget(self, "cursor") or #self.text end
function methods:SetCursorPosition(at) self.cursor = at end
function methods:Insert(text)
	local at = rawget(self, "cursor") or #self.text
	self.text = self.text:sub(1, at) .. text .. self.text:sub(at + 1)
	self.cursor = at + #text
	Run(self, "OnTextChanged", true)
end
function methods:SetMaxLetters(max) self.maxLetters = max end
function methods:GetMaxLetters() return rawget(self, "maxLetters") or 0 end
function methods:SetFocus()
	if focused ~= self then
		local old = focused
		focused = self
		if old then Run(old, "OnEditFocusLost") end
		Run(self, "OnEditFocusGained")
	end
end
function methods:ClearFocus()
	if focused == self then
		focused = nil
		Run(self, "OnEditFocusLost")
	end
end
function methods:HasFocus() return focused == self end
function methods:SetAttribute(key, value) self.attributes[key] = value end
function methods:GetAttribute(key) return self.attributes[key] end
function methods:AddMessage(text, r, g, b) table.insert(self.lines, { text = text, r = r, g = g, b = b }) end
function methods:Clear() self.lines = {} end
function methods:GetStringWidth() return #(self.text or "") * 6 end
function methods:GetStringHeight() return 20 end
function methods:GetWidth() return self.width end
function methods:GetHeight() return 200 end
function methods:SetWidth(width) self.width = width end
function methods:GetFrameStrata() return self.strata end
function methods:SetFrameStrata(strata) self.strata = strata end
function methods:GetFrameLevel() return self.level end
function methods:SetFrameLevel(level) self.level = level end
function methods:GetFont() return "font", 14, "" end
function methods:CreateFontString() local fs = NewFrame("FontString", nil, self) return fs end
function methods:CreateTexture() return NewFrame("Texture", nil, self) end
function methods:RegisterEvent(event) rawset(self, "events", rawget(self, "events") or {}); self.events[event] = true end
function methods:UnregisterEvent(event) if rawget(self, "events") then self.events[event] = nil end end

function CreateFrame(kind, name, parent)
	return NewFrame(kind, name, parent)
end
UIParent = NewFrame("Frame", "UIParent")
ChatFrame1 = NewFrame("ScrollingMessageFrame", "ChatFrame1", UIParent)
ChatFrame2 = NewFrame("ScrollingMessageFrame", "ChatFrame2", UIParent)
ChatFrame1.level, ChatFrame1.strata = 5, "LOW"
COMBATLOG = ChatFrame2
NUM_CHAT_WINDOWS = 2
GameFontHighlight = NewFrame("Font")
ChatFontNormal = NewFrame("Font")

local bindings = {} -- owner -> key -> action
function SetOverrideBindingClick(owner, _, key, name, button)
	bindings[owner] = bindings[owner] or {}
	bindings[owner][key] = "CLICK " .. name .. ":" .. (button or "LeftButton")
end
function ClearOverrideBindings(owner) bindings[owner] = nil end
function GetBindingAction(key)
	for _, list in pairs(bindings) do
		if list[key] then
			return list[key]
		end
	end
	return ""
end
local combat = false
function InCombatLockdown() return combat end

function hooksecurefunc(target, method, hook)
	if type(target) == "string" then
		target, method, hook = _G, target, method
	end
	local original = target[method]
	target[method] = function(...)
		local result = original(...)
		hook(...)
		return result
	end
end
function strtrim(text) return (text:gsub("^%s+", ""):gsub("%s+$", "")) end
date = os.date
time = os.time
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function UnitName() return "Me" end
function UnitGUID() return "Player-1" end
function Ambiguate(name) return (name:gsub("%-.*$", "")) end
function IsShiftKeyDown() return false end
ChatTypeInfo = {
	SAY = { r = 1, g = 1, b = 1 }, PARTY = { r = 0.67, g = 0.67, b = 1 }, WHISPER = { r = 1, g = 0.5, b = 1 },
	WHISPER_INFORM = { r = 1, g = 0.4, b = 0.9 }, GUILD = { r = 0.25, g = 1, b = 0.25 },
}
-- /gxiv is an addon's (tainted), /reload the game's (secure).
SlashCmdList = { GXIV = function(rest) _G.gxivRan = rest end, RELOAD = function() error("must not run here") end }
SLASH_GXIV1, SLASH_RELOAD1 = "/gxiv", "/reload"
SecureCmdList = { TARGET = true, USE = true }
SLASH_TARGET1, SLASH_USE1 = "/target", "/use"
-- Emotes, /reload and /roll: run here by calling the game's function behind each.
EMOTE1_TOKEN, EMOTE1_CMD1, EMOTE1_CMD2 = "DANCE", "/dance", "/DANCE"
performed, rolled, reloaded = {}, nil, 0
function RandomRoll(low, high) rolled = low .. "-" .. high end
C_UI = { Reload = function() reloaded = reloaded + 1 end }
function issecurevariable(_, key) return key ~= "GXIV" end

-- The chat data, as LfgFilter.lua keeps it.
local now = os.time()
local chats = {
	Ann = { lines = { { m = "hey", t = now - 60 } }, unread = 2, last = now - 60 },
	Bob = { lines = { { m = "yo", t = now - 300 }, { o = true, m = "sup", t = now - 200 } }, unread = 0, last = now - 200 },
	Old = { lines = { { m = "long ago", t = now - 7200 } }, unread = 0, last = now - 7200 },
	["#PARTY"] = { lines = { { m = "pull?", t = now - 30, s = "Tank" }, { o = true, m = "go", t = now - 20 } }, unread = 0, seq = 2 },
}
local CHANNELS = { ["#SAY"] = { name = "Say", color = "ffffff", chatType = "SAY" },
	["#PARTY"] = { name = "Party", color = "aaaaff", chatType = "PARTY" },
	["#SYSTEM"] = { name = "System", color = "ffff00", readOnly = true } }
local sentTo = {}
local ns = { db = { chatHighlightOwn = true, chatFade = 30 }, BUTTON_NAMES = {} }
local printed = {}
function ns.Print(text) printed[#printed + 1] = text end
function ns.ButtonText(text) return text end
function ns.RepeatOnHold(button, onClick)
	button:SetScript("OnClick", function(_, mouse, down)
		if down ~= false then onClick(button, mouse, down) end
	end)
end
ns.ChatAPI = {
	List = function()
		local list = { { name = "#SAY", chat = chats["#SAY"] or { lines = {} } }, { name = "#PARTY", chat = chats["#PARTY"] } }
		local whispers = {}
		for name, chat in pairs(chats) do
			if name:sub(1, 1) ~= "#" and (os.time() - (chat.last or 0) < 1800 or (chat.unread or 0) > 0) then
				whispers[#whispers + 1] = { name = name, chat = chat }
			end
		end
		table.sort(whispers, function(a, b) return a.chat.last > b.chat.last end)
		for _, item in ipairs(whispers) do list[#list + 1] = item end
		list[#list + 1] = { special = "history" }
		return list
	end,
	Send = function(name, text) sentTo[#sentTo + 1] = name .. ":" .. text; return true end,
	ExpandPhrase = function(text) return text == "<ask>" and "ASK MSG" or text end,
	Decorate = function(text, name)
		if name:find("^#CH:") then return text end
		local decorated = "{rt3} " .. text .. " {rt3}"
		return #decorated <= 255 and decorated or text
	end,
	Info = function(key)
		if type(key) == "string" and key:find("^#TAB:") then return ns.ChatCustomTabInfo(key) end
		return type(key) == "string" and CHANNELS[key] or nil
	end,
	Chats = function() return chats end,
	Icons = function(text) return text end,
	Color = function(name) return name end,
	Short = function(name) return name end,
	Log = function() end,
	Unread = function() return 0 end,
	Phrases = { { name = "Greet", "Hello!", "<ask>", "Bye!" } }, QuickReplies = { "hi" },
	ReplyIndex = function() return 1 end,
	OpenWindow = function() end,
}

-- The game's chat functions links go through (Blizzard_ChatFrameBase), its edit box and the clock.
local clock, timers = 100, {}
function GetTime() return clock end
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function NextFrame()
	clock = clock + 0.02
	local due = timers
	timers = {}
	for _, fn in ipairs(due) do fn() end
end
local chatLinkClick = false
function IsModifiedClick(kind) return kind == "CHATLINK" and chatLinkClick end
function GetCurrentKeyBoardFocus() return focused end
local errorsShown = {}
UIErrorsFrame = { AddMessage = function(_, text) errorsShown[#errorsShown + 1] = text end }
local gameBox = NewFrame("EditBox", "ChatFrame1EditBox", UIParent)
gameBox.shown = false
local gameActive -- stays set after the box closes, as in the "im" chat style
local gameSent = {}
ChatFrameUtil = {
	GetActiveWindow = function() return gameActive end,
	InsertLink = function(text)
		if gameActive and gameActive:HasFocus() then
			gameActive:Insert(text)
			return true
		end
		return false
	end,
	OpenChat = function(text)
		gameActive = gameBox
		gameBox:Show()
		gameBox:SetFocus()
		if text then gameBox:SetText(text) end
		return gameBox
	end,
}
ChatEdit_InsertLink = ChatFrameUtil.InsertLink -- the deprecated globals point at the same functions
ChatFrame_OpenChat = ChatFrameUtil.OpenChat
function ChatFrameUtil.LinkItem(_, link)
	if ChatFrameUtil.GetActiveWindow() and ChatFrameUtil.GetActiveWindow():HasFocus() then
		ChatFrameUtil.InsertLink(link)
	else
		ChatFrameUtil.OpenChat(link)
	end
end
C_ChatInfo = { SendChatMessage = function(text) gameSent[#gameSent + 1] = text end,
	PerformEmote = function(token, target) performed[#performed + 1] = token .. ":" .. tostring(target) end }
local unhookedOpenChat = ChatFrameUtil.OpenChat -- a copy kept before the hooks, as other code may

assert(loadfile("ChatBox.lua"))("GamepadXIV", ns)

---------------------------------------------------------------------------------------------------
-- Checks

local function Click(name, down)
	local button = _G["GamepadXIVChatBox" .. name] or _G[name]
	assert(button, "no button " .. name)
	if down == nil then down = true end
	Run(button, "OnClick", "LeftButton", down)
	Run(button, "PostClick", "LeftButton", down)
end
local function Fire(event, ...)
	for _, frame in ipairs(frames) do
		if rawget(frame, "events") and frame.events[event] and frame.scripts.OnEvent then
			frame.scripts.OnEvent(frame, event, ...)
		end
	end
end
local input
local function Key(key) return GetBindingAction(key) end
local function Type(text) input:SetText(text) end

Check("LastWhisper is not a global", rawget(_G, "LastWhisper"), nil)
Check("Draw is not a global", rawget(_G, "Draw"), nil)

ns.ChatBoxSetShown(true)
input = GamepadXIVChatBoxInput
Check("not typing at first", input:HasFocus(), false)
Check("no keys taken at first", Key("PADDUP"), "")
Check("over the game's chat", GamepadXIVChatBox:GetFrameLevel() > ChatFrame1.level, true)

-- Typing.
ns.FocusChatBox()
Check("typing", input:HasFocus(), true)
Check("typing: L1 tabs", Key("PADLSHOULDER"), "CLICK GamepadXIVChatBoxPrev:LeftButton")
Check("typing: D-pad up recalls", Key("PADDUP"), "CLICK GamepadXIVChatBoxUp:LeftButton")
Check("typing: the right stick is left to the game", Key("PADRSTICKUP"), "")
Check("typing: Cross sends", Key("PAD1"), "CLICK GamepadXIVChatBoxSend:LeftButton")
Check("typing: Circle", Key("PAD2"), "CLICK GamepadXIVChatBoxBack:LeftButton")
Check("active key on All", ns.ChatBoxActiveKey(), nil)

-- Protected game commands go through the macro button; emotes, /reload, /roll and the chat box's own
-- commands don't.
Type("/use Hearthstone")
Check("game command: Cross runs the macro", Key("PAD1"), "CLICK GamepadXIVChatBoxMacro:LeftButton")
Check("game command: macrotext", GamepadXIVChatBoxMacro:GetAttribute("macrotext"), "/use Hearthstone")
Type("/dance")
Check("emote: Send", Key("PAD1"), "CLICK GamepadXIVChatBoxSend:LeftButton")
Type("/reload")
Check("/reload: Send", Key("PAD1"), "CLICK GamepadXIVChatBoxSend:LeftButton")
Type("/target [@focus]")
Check("secure command: macro", Key("PAD1"), "CLICK GamepadXIVChatBoxMacro:LeftButton")
Type("/w Bob hi")
Check("whisper command: Send", Key("PAD1"), "CLICK GamepadXIVChatBoxSend:LeftButton")
Type("/gxiv")
Check("addon command: Send", Key("PAD1"), "CLICK GamepadXIVChatBoxSend:LeftButton")
Type("/use Hearthstone")
input.scripts.OnEnterPressed(input)
Check("Enter can't run a game command: still typing", input:HasFocus(), true)
Check("Enter can't run a game command: says so", printed[#printed] and printed[#printed]:find("{PAD1}", 1, true) ~= nil, true)
Click("GamepadXIVChatBoxMacro", true)
Check("macro press: still typing until the release", input:HasFocus(), true)
Click("GamepadXIVChatBoxMacro", false)
Check("macro ran: input emptied", input:GetText(), "")
Check("macro ran: typing stopped", input:HasFocus(), false)
Check("macro ran: keys given back", Key("PAD1"), "")

-- Sending and recalling.
ns.FocusChatBox()
Type("hello")
Click("Send")
Check("sent to Say from All", sentTo[#sentTo], "#SAY:hello")
Check("sent: typing stopped", input:HasFocus(), false)
ns.FocusChatBox()
Type("/gxiv test")
Click("Send")
Check("addon command ran", _G.gxivRan, "test")
ns.FocusChatBox()
Click("Down")
Check("down with nothing recalled: nothing", input:GetText(), "")
Click("Up")
Check("up: newest", input:GetText(), "/gxiv test")
Click("Up")
Check("up again: older", input:GetText(), "hello")
Click("Up")
Check("up again: older", input:GetText(), "/use Hearthstone")
Click("Up")
Check("up at the oldest: stays", input:GetText(), "/use Hearthstone")
Click("Down")
Check("down: newer", input:GetText(), "hello")
Click("Down")
Click("Down")
Check("down past the newest: empty", input:GetText(), "")

-- Browse.
Click("Back")
Check("Circle: typing stopped", input:HasFocus(), false)
Check("browse: D-pad up scrolls", Key("PADDUP"), "CLICK GamepadXIVChatBoxBrowseUp:LeftButton")
Check("browse: Cross types", Key("PAD1"), "CLICK GamepadXIVChatBoxType:LeftButton")
Check("browse: Circle closes", Key("PAD2"), "CLICK GamepadXIVChatBoxClose:LeftButton")
Check("browse: L1 tabs", Key("PADLSHOULDER"), "CLICK GamepadXIVChatBoxPrev:LeftButton")
Check("browse: Square picks channel tabs", Key("PAD3"), "CLICK GamepadXIVChatBoxTabs:LeftButton")
Click("Send")
Check("browse: typing's buttons do nothing", sentTo[#sentTo], "#SAY:hello")
Click("Type")
Check("browse Cross: typing again", input:HasFocus(), true)
Click("Back")
Click("Close")
Check("browse closed: D-pad given back", Key("PADDUP"), "")
Check("browse closed: Cross given back", Key("PAD1"), "")

-- Browse ends in combat; typing gives the controller back in combat.
ns.FocusChatBox()
Click("Back")
Fire("PLAYER_REGEN_DISABLED")
combat = true
Check("combat: browse over", Key("PADDUP"), "")
combat = false
Fire("PLAYER_REGEN_ENABLED")
Check("after combat: still closed", Key("PADDUP"), "")
ns.FocusChatBox()
Type("half a message")
Fire("PLAYER_REGEN_DISABLED")
combat = true
Check("combat while typing: keys given back", Key("PAD1"), "")
Check("combat while typing: still typing with text", input:HasFocus(), true)
combat = false
Fire("PLAYER_REGEN_ENABLED")
Check("after combat: keys again", Key("PAD1"), "CLICK GamepadXIVChatBoxSend:LeftButton")
Type("")

-- Stops: All, Whispers (one stop, on the newest), the channels, Combat.
local order = {}
for _ = 1, 6 do
	Click("Next")
	order[#order + 1] = ns.ChatBoxActiveKey() or "-"
end
Check("stops in order", table.concat(order, " "), "Ann #SAY #PARTY - - Ann")
Check("the old whisper is no stop", order[3] ~= "Old", true)
Click("Down")
Check("typing on Whispers: D-pad down recalls, same player", ns.ChatBoxActiveKey(), "Ann")
Type("")
Click("Back")
Check("browse on Whispers: D-pad up scrolls", Key("PADDUP"), "CLICK GamepadXIVChatBoxBrowseUp:LeftButton")
Check("browse on Whispers: D-pad right picks players", Key("PADDRIGHT"), "CLICK GamepadXIVChatBoxBrowseRight:LeftButton")
local function Picked() -- the player highlighted in the column
	for _, row in ipairs(GamepadXIVChatBoxWhispers.rows) do
		if row:IsShown() and row.bg:IsShown() then return row.key end
	end
end
Click("BrowseDown")
Check("browse: D-pad down keeps the player", Picked(), "Ann")
Click("BrowseRight")
Check("browse: D-pad right: the next player", Picked(), "Bob")
Click("Next")
Click("Prev")
Check("Whispers opens on the player picked last", Picked(), "Bob")
Check("whispers column shown", GamepadXIVChatBoxWhispers:IsShown(), true)
Check("whispers column: newest first", GamepadXIVChatBoxWhispers.rows[1].key, "Ann")
Check("whispers column: then Bob", GamepadXIVChatBoxWhispers.rows[2].key, "Bob")
Check("whispers column: no more", GamepadXIVChatBoxWhispers.rows[3]:IsShown(), false)
Run(GamepadXIVChatBoxWhispers.rows[1], "OnClick", "LeftButton")
Check("whispers column click picks", ns.ChatBoxActiveKey(), "Ann")
Run(GamepadXIVChatBoxWhispers.rows[2], "OnClick", "LeftButton")
local convo = GamepadXIVChatConversation
local own
for _, line in ipairs(convo.lines) do
	if line.text:find("sup", 1, true) then own = line end
end
Check("own whisper line: gold You", own and own.text:find("|cffffd100You|r", 1, true) ~= nil, true)
Check("own whisper line: marked", own and own.text:find("WHITE8X8", 1, true) ~= nil, true)
Check("own whisper line: whisper inform colour", own and own.b, 0.9)
Check("a click on a player: typing", input:HasFocus(), true)
Click("Back")
Click("BrowseLeft")
Check("Ann", Picked(), "Ann")
Check("looking at Ann reads her lines", chats.Ann.unread, 0)
Click("Type")
Check("typing to Ann", ns.ChatBoxActiveKey(), "Ann")
Check("ReplyPrev while typing: not a player pick", (function() Click("ReplyPrev") return ns.ChatBoxActiveKey() end)(), "Ann")
Type("hi Ann")
Click("Send")
Check("sent to the picked whisper", sentTo[#sentTo], "Ann:hi Ann")

-- Party: the party colour, the sender's name.
ns.FocusChatBox()
for _ = 1, 8 do
	if ns.ChatBoxActiveKey() == "#PARTY" then break end
	Click("Next")
end
Check("on Party", ns.ChatBoxActiveKey(), "#PARTY")
Check("no whispers column on Party", GamepadXIVChatBoxWhispers:IsShown(), false)
local party = convo.lines[1]
Check("party line: party colour", party and party.b, 1)
Check("party line: party colour red", party and party.r, 0.67)
ns.db.chatHighlightOwn = false
ns.ChatBoxRefresh()
local plain = convo.lines[2]
Check("highlight off: no mark", plain and plain.text:find("WHITE8X8", 1, true), nil)
ns.db.chatHighlightOwn = true

-- Combat: the game's combat log lines while its frame is shown, at most 300.
Fire("PLAYER_ENTERING_WORLD")
for i = 1, 310 do
	ChatFrame2:AddMessage("hit " .. i, 1, 1, 1)
end
Click("Prev") -- Say
Click("Prev") -- Bob? no: back through the stops to the last one
for _ = 1, 10 do
	Click("Prev")
	if ns.ChatBoxActiveKey() == nil and GamepadXIVChatConversation:IsShown() then
		break
	end
end
local text = convo.lines[#convo.lines] and convo.lines[#convo.lines].text or ""
Check("combat tab: newest line", text:find("hit 310", 1, true) ~= nil, true)
Check("combat tab: kept at most 300", #convo.lines, 300)
ChatFrame2:AddMessage("hit 311", 1, 1, 1)
Check("combat tab: a new line is added", convo.lines[#convo.lines].text:find("hit 311", 1, true) ~= nil, true)
ChatFrame2:Hide()
ChatFrame2:AddMessage("hidden", 1, 1, 1)
Check("combat log hidden: still taken from it", convo.lines[#convo.lines].text:find("hidden", 1, true) ~= nil, true)
Type("from combat")
Click("Send")
Check("typing on Combat says", sentTo[#sentTo], "#SAY:from combat")

-- Hiding the box stops everything.
ns.FocusChatBox()
Click("Back")
ns.ChatBoxSetShown(false)
Check("hidden: browse over", Key("PADDUP"), "")

-- /w with a typed name lands on the existing conversation, a new one on Name-Realm.
ns.ChatBoxSetShown(true)
ns.FocusChatBox()
Type("/w bob")
Click("Send")
Check("typed name: the existing conversation", ns.ChatBoxActiveKey(), "Bob")
GetNormalizedRealmName = function() return "Realm" end
Type("/w carol")
Click("Send")
Check("typed name: a new one as Name-Realm", ns.ChatBoxActiveKey(), "Carol-Realm")
Type("hello Carol")
Click("Send")
Check("sent to Name-Realm", sentTo[#sentTo], "Carol-Realm:hello Carol")

-- Ready-made messages go into the message, never out on their own; the whole message goes out between
-- the markers once.
local menu, reply = GamepadXIVChatBoxMenu, GamepadXIVChatBox.reply
local sentBefore = #sentTo
ns.FocusChatBox()
Check("typing: L3 adds the quick reply", Key("PADLSTICK"), "CLICK GamepadXIVChatBoxAddReply:LeftButton")
Check("quick reply line: Cross adds while empty", reply.text:find("{PAD1} Add", 1, true) ~= nil, true)
Check("hint: Cross adds the reply while empty", GamepadXIVChatBox.hint.text:find("{PAD1} Add reply", 1, true) ~= nil, true)
Click("Send")
Check("Cross on empty: quick reply put in", input:GetText(), "hi")
Check("Cross on empty: nothing sent", #sentTo, sentBefore)
Check("Cross on empty: still typing", input:HasFocus(), true)
Check("quick reply line: L3 adds while typing", reply.text:find("{PADLSTICK} Add", 1, true) ~= nil, true)
Check("hint: Cross sends with text", GamepadXIVChatBox.hint.text:find("{PAD1} Send", 1, true) ~= nil, true)
Click("AddReply")
Check("L3: added after a space", input:GetText(), "hi hi")
Click("Send")
Check("send: marked once", sentTo[#sentTo], "Carol-Realm:{rt3} hi hi {rt3}")
Check("send: typing stopped", input:HasFocus(), false)

ns.FocusChatBox()
Click("Phrases")
Check("menu open", menu:IsShown(), true)
Check("menu hint: Open on the categories", menu.hint.text:find("{PAD1} Open", 1, true) ~= nil, true)
Click("Send")
Check("menu: a category opened", menu.title.text, "Greet")
Check("menu hint: Add in a category", menu.hint.text:find("{PAD1} Add", 1, true) ~= nil, true)
Click("Send")
Check("menu pick: put in", input:GetText(), "Hello!")
Check("menu pick: nothing sent", #sentTo, sentBefore + 1)
Check("menu pick: menu stays open", menu:IsShown(), true)
Check("menu pick: Added shown", menu.title.text:find("Added", 1, true) ~= nil, true)
Click("Down")
Click("Send")
Check("two picks: one space between", input:GetText(), "Hello! ASK MSG")
Run(menu.rows[3], "OnClick", "LeftButton")
Check("a click adds too", input:GetText(), "Hello! ASK MSG Bye!")
Click("Back")
Check("Circle: back to the categories", menu.title.text, "Ready-made messages")
Click("Back")
Check("Circle on the categories: closed", menu:IsShown(), false)
Check("menu closed: still typing", input:HasFocus(), true)
Click("Send")
Check("several ready-made messages: one message, marked once", sentTo[#sentTo], "Carol-Realm:{rt3} Hello! ASK MSG Bye! {rt3}")

-- A command's message is marked too.
ns.FocusChatBox()
Type("/w Bob ")
Click("AddReply")
Click("Send")
Check("whisper command with a quick reply: marked once", sentTo[#sentTo], "Bob:{rt3} hi {rt3}")
ns.FocusChatBox()
Type("/w Carol-Realm")
Click("Send")

-- At the cursor, a space either side; typed text only goes out as typed.
ns.FocusChatBox()
Type("one two")
input:SetCursorPosition(3)
Click("AddReply")
Check("at the cursor", input:GetText(), "one hi two")
Type("")
Type("typed")
Click("Send")
Check("emptied box forgets the ready-made message", sentTo[#sentTo], "Carol-Realm:typed")
ns.FocusChatBox()
Type("just typed")
Click("Send")
Check("typed only: not marked", sentTo[#sentTo], "Carol-Realm:just typed")

-- 255 letters: what doesn't fit isn't added.
ns.FocusChatBox()
Type(string.rep("x", 253))
local printedBefore = #printed
Click("AddReply")
Check("too long: not added", input:GetText(), string.rep("x", 253))
Check("too long: says so", #printed == printedBefore + 1 and printed[#printed]:find("255", 1, true) ~= nil, true)
Type(string.rep("x", 252))
Click("AddReply")
Check("just fits", #input:GetText(), 255)
Click("Phrases")
Click("Send")
Click("Send")
Check("menu: too long not added", #input:GetText(), 255)
Check("menu: too long shown", menu.title.text:find("Too long", 1, true) ~= nil, true)
Click("Phrases")
Check("R3 again closes the menu", menu:IsShown(), false)
Type("")
input.scripts.OnEnterPressed(input)
Check("Enter with nothing typed: stops typing", input:HasFocus(), false)
Check("Enter with nothing typed: nothing added", input:GetText(), "")

-- ns.ChatInsert on its own (the Chat window's box uses it too): the end while not focused, and nothing
-- when the box would cut the text.
local other = CreateFrame("EditBox", "TestOtherBox", UIParent)
other:SetMaxLetters(255)
other:SetText("abc def")
other:SetCursorPosition(2)
Check("unfocused: at the end", ns.ChatInsert(other, "  Hi  ") and other:GetText(), "abc def Hi")
Check("flag set", other.readyMade, true)
other:SetText("abc ")
Check("no double space", ns.ChatInsert(other, "Hi") and other:GetText(), "abc Hi")
Check("nothing to add", ns.ChatInsert(other, "   "), false)
other:SetText("caf\195\169")
other:SetFocus()
other:SetCursorPosition(4) -- inside the two bytes of the last letter
Check("not inside a letter", ns.ChatInsert(other, "x") and other:GetText(), "caf\195\169 x")
other:ClearFocus()
local cut = CreateFrame("EditBox", "TestCutBox", UIParent)
function cut:SetText(text) self.text = (text or ""):sub(1, 5) end
cut:SetText("abc")
Check("cut by the box: refused", ns.ChatInsert(cut, "Hello"), false)
Check("cut by the box: text kept", cut:GetText(), "abc")

-- A game command that starts a fight: combat start finishes it when the release never comes.
ns.FocusChatBox()
Type("/startattack")
Click("GamepadXIVChatBoxMacro", true)
Fire("PLAYER_REGEN_DISABLED")
combat = true
Check("macro then combat: input emptied", input:GetText(), "")
Check("macro then combat: typing stopped", input:HasFocus(), false)
combat = false
Fire("PLAYER_REGEN_ENABLED")

-- A short box: smaller icons, then the short hint, so the messages keep their room.
ns.FocusChatBox()
local hint = GamepadXIVChatBox.hint
function hint:GetStringHeight() return 60 end
ns.ChatBoxRefresh()
Check("short box: short hint", hint.text:find("{PAD4}", 1, true), nil)
Check("short box: still says how to send", hint.text:find("{PAD1}", 1, true) ~= nil, true)
hint.GetStringHeight = nil
input:ClearFocus()

-- The feed marks lines you said, not lines that only name you.
GamepadXIVChatFeed.lines = {}
ns.ChatBoxFeed("|Hplayer:Me-Realm:1|h[Me]|h: hello", 1, 1, 1)
ns.ChatBoxFeed("|Hplayer:Me-Realm:1|h[Me]|h has joined the guild.", 1, 1, 0)
Check("feed: your line marked", GamepadXIVChatFeed.lines[1].text:find("WHITE8X8", 1, true) ~= nil, true)
Check("feed: a line naming you isn't", GamepadXIVChatFeed.lines[2].text:find("WHITE8X8", 1, true), nil)

-- The client forbids COMBAT_LOG_EVENT_UNFILTERED to addons: the chat box never asks for it, also not
-- when it hides and shows again around the game's chat box (the "blocked from an action" popup).
for _, shown in ipairs({ true, false, true, false, true }) do
	ns.ChatBoxSetShown(shown)
end
local asked = false
for _, frame in ipairs(frames) do
	if rawget(frame, "events") and frame.events.COMBAT_LOG_EVENT_UNFILTERED then
		asked = true
	end
end
Check("combat log event never registered", asked, false)

---------------------------------------------------------------------------------------------------
-- Links: Shift-click and Share in Chat while the chat box replaces the game's chat.

local ITEM = "|cff1eff00|Hitem:2589::::::::45:::::|h[Linen Cloth]|h|r"
local PIN = "|cffffff00|Hworldmap:1429:4500:5500|h[|A:Waypoint-MapPin-ChatIcon:13:13:0:0|a Map Pin Location]|h|r"
ns.db.chatUI, ns.db.chatLinks = "gxiv", true
ns.ChatBoxSetShown(true)
input:ClearFocus()
Type("")
-- LfgFilter.lua's watcher: the game's chat shows while its box is open, the chat box after.
local revealed = false
local function GameChatTick()
	local typing = gameActive and gameActive:IsShown() and gameActive:HasFocus() and true or false
	if typing ~= revealed then
		revealed = typing
		ns.ChatBoxSetShown(not typing)
		if typing then
			ns.ChatBoxGameChatOpened()
		else
			ns.ChatBoxGameChatClosed()
		end
	end
end
local function CloseGameBox(send)
	if send then
		C_ChatInfo.SendChatMessage(gameBox:GetText(), "SAY")
	end
	gameBox:SetText("")
	gameBox:ClearFocus()
	NextFrame()
	GameChatTick()
end

-- Shift-click while typing: in at the cursor, once, and the game's box stays closed.
ns.FocusChatBox()
Type("look ")
chatLinkClick = true
ChatFrameUtil.InsertLink(ITEM)
ChatEdit_InsertLink(ITEM) -- the same click through the older global
Check("Shift-click while typing: in at the cursor", input:GetText(), "look " .. ITEM)
NextFrame()
Check("Shift-click while typing: only once", input:GetText(), "look " .. ITEM)
Check("Shift-click while typing: the game's box stays closed", gameBox:IsShown(), false)
Check("Shift-click while typing: still typing", input:HasFocus(), true)
input:SetCursorPosition(3)
ChatFrameUtil.InsertLink(PIN)
Check("Shift-click: at the cursor, not the end", input:GetText(), "loo" .. PIN .. "k " .. ITEM)
input:SetText("look " .. ITEM)
Click("Erase")
Check("erase takes a link out whole", input:GetText(), "look ")
Click("Erase")
Check("erase after a link: one letter", input:GetText(), "look")
local NAMED = "|cnIQ3:|Hitem:2592::::::::45:::::|h[Wool Cloth]|h|r" -- this client's item links
input:SetText("a " .. NAMED)
Click("Erase")
Check("erase takes a link with a named colour out whole", input:GetText(), "a ")
input:SetText("")
input.Insert = function(self, text) methods.Insert(self, text:sub(1, 12)) end -- an edit box that cuts it
ChatFrameUtil.InsertLink(NAMED)
input.Insert = nil
Check("a link the edit box cut: taken out again", input:GetText(), "")
Check("a link the edit box cut: says so", printed[#printed]:find("doesn't fit", 1, true) ~= nil, true)
NextFrame()
input:SetText(string.rep("a", 250))
ChatFrameUtil.InsertLink(ITEM)
NextFrame()
Check("a link that doesn't fit: left out, not cut", input:GetText(), string.rep("a", 250))
Check("a link that doesn't fit: says so", printed[#printed]:find("doesn't fit", 1, true) ~= nil, true)
chatLinkClick = false

-- Share in Chat with the chat box closed: the game's box opens with the link (nothing stops that);
-- closing it without sending opens the chat box with the link.
Type("")
input:ClearFocus()
ChatFrameUtil.LinkItem(nil, PIN)
Check("share: the game's box has it", gameBox:GetText(), PIN)
NextFrame()
GameChatTick()
Check("share: the chat box hides while the game's box is open", GamepadXIVChatBox:IsShown(), false)
Check("share: says how to move it", printed[#printed]:find("close that box", 1, true) ~= nil, true)
CloseGameBox(false)
Check("share, closed: the chat box is back", GamepadXIVChatBox:IsShown(), true)
Check("share, closed: typing in it", input:HasFocus(), true)
Check("share, closed: with the link", input:GetText(), PIN)

-- Sent from the game's box: the chat box doesn't open with it again.
Type("")
input:ClearFocus()
local said = #printed
ChatFrameUtil.LinkItem(nil, ITEM)
NextFrame()
GameChatTick()
Check("share again: told only once", #printed, said)
CloseGameBox(true)
Check("share, sent: sent from the game's box", gameSent[#gameSent], ITEM)
Check("share, sent: the chat box doesn't open", input:HasFocus(), false)
Check("share, sent: nothing in it", input:GetText(), "")

-- Share in Chat while typing: the game's box takes the focus; the link joins what was typed after.
ns.FocusChatBox()
Type("see ")
ChatFrame_OpenChat(PIN)
Check("share while typing: the game's box has the focus", gameBox:HasFocus(), true)
NextFrame()
GameChatTick()
CloseGameBox(false)
Check("share while typing: after what was typed", input:GetText(), "see " .. PIN)
Check("share while typing: typing again", input:HasFocus(), true)

-- Opened through a copy of the function no hook sees: the link is read from the game's box.
Type("")
input:ClearFocus()
unhookedOpenChat(ITEM)
NextFrame()
GameChatTick()
CloseGameBox(false)
Check("share, unhooked: the chat box opens with the link", input:GetText(), ITEM)
Check("share, unhooked: typing", input:HasFocus(), true)

-- The Shift-click took the focus from the chat box just before its link came: typing again, with it.
ns.FocusChatBox()
Type("x ")
chatLinkClick = true
input:ClearFocus()
ChatFrameUtil.InsertLink(ITEM)
NextFrame()
Check("Shift-click that took the focus: typing again", input:HasFocus(), true)
Check("Shift-click that took the focus: with the link", input:GetText(), "x " .. ITEM)

-- Shift-click with the chat box closed: held until it opens, for 30 seconds.
Type("")
input:ClearFocus()
clock = clock + 2
ChatFrameUtil.InsertLink(ITEM)
NextFrame()
Check("Shift-click, closed: not in yet", input:GetText(), "")
Check("Shift-click, closed: says to open chat", errorsShown[#errorsShown]:find("open chat", 1, true) ~= nil, true)
ns.FocusChatBox()
Check("Shift-click, closed: in when it opens", input:GetText(), ITEM)
Type("")
input:ClearFocus()
clock = clock + 2
ChatFrameUtil.InsertLink(PIN)
NextFrame()
clock = clock + 31
ns.FocusChatBox()
Check("Shift-click, closed: dropped after 30 seconds", input:GetText(), "")

-- A Shift-click into a game's box the player opened stays there.
input:ClearFocus()
ChatFrameUtil.OpenChat("")
NextFrame()
GameChatTick()
ChatFrameUtil.InsertLink(ITEM)
NextFrame()
CloseGameBox(false)
Check("Shift-click into the game's open box: the chat box stays closed", input:HasFocus(), false)
chatLinkClick = false

-- With the game's chat, links are left to the game.
ns.db.chatUI = "game"
ns.FocusChatBox()
ChatFrameUtil.InsertLink(ITEM)
NextFrame()
Check("the game's chat: nothing here", input:GetText(), "")
input:ClearFocus()

-- The All tab: a command sends there and stays on All; the triggers pick where All's messages go.
ns.FocusChatBox()
for _ = 1, 12 do
	if GamepadXIVChatFeed:IsShown() then break end
	Click("Next")
end
Check("on All", GamepadXIVChatFeed:IsShown(), true)
Type("/p hi party")
Click("Send")
Check("all: /p sends to the party", sentTo[#sentTo], "#PARTY:hi party")
ns.FocusChatBox()
Check("all: still on All after /p", GamepadXIVChatFeed:IsShown(), true)
Type("again")
Click("Send")
Check("all: next message goes to the party too", sentTo[#sentTo], "#PARTY:again")
ns.FocusChatBox()
Check("all: triggers bound while typing", Key("PADLTRIGGER"), "CLICK GamepadXIVChatBoxChannelPrev:LeftButton")
Click("ChannelPrev")
Type("back to say")
Click("Send")
Check("all: L2 steps back to Say", sentTo[#sentTo], "#SAY:back to say")

-- Square's menu: Languages, Say and Yell, Cross steps through what this character knows.
IsInGroup = IsInGroup or function() return false end
ns.ChatLanguages = function() return { { "default", "The game's default" }, { 7, "Common" }, { 2, "Darnassian" } } end
ns.db.chatLanguageSAY, ns.db.chatLanguageYELL = "default", "default"
ns.FocusChatBox()
Type("")
Click("Back")
for _, frame in ipairs({ GamepadXIVChatFeed, GamepadXIVChatConversation }) do
	frame.visibleLines = {}
	frame.GetNumMessages = function() return 0 end
end
Click("Tabs")
local langIndex
for i, item in ipairs(menu.rows) do
	if item:IsShown() and item.text.text and item.text.text:find("Languages", 1, true) then langIndex = i end
end
Check("square menu: Languages listed", langIndex ~= nil, true)
for _ = 1, 12 do
	if menu.title.text == "Languages" then break end
	Click("Down")
	if menu.rows[langIndex] and menu.rows[langIndex].bg:IsShown() then Click("Send") end
end
Check("languages menu open", menu.title.text, "Languages")
Check("languages: Say first, default", menu.rows[1].text.text:find("The game's default", 1, true) ~= nil, true)
Click("Send")
Check("Cross: next language", ns.db.chatLanguageSAY, 7)
Click("Send")
Check("Cross again", ns.db.chatLanguageSAY, 2)
Click("Send")
Check("wraps to the default", ns.db.chatLanguageSAY, "default")
Click("Down")
Click("Send")
Check("Yell row", ns.db.chatLanguageYELL, 7)
Click("Back")
Check("Circle closes it", menu:IsShown(), false)

-- All's Messages: a hidden kind is left out of the All feed; untagged lines (addon messages) always show.
local filters = {}
ChatFrameUtil.AddMessageEventFilter = function(event, fn) filters[event] = fn end
ChatFrameUtil.RemoveMessageEventFilter = function(event) filters[event] = nil end
GetTime = GetTime or function() return 0 end
ns.SetChatTabShows("all", "loot", false)
Check("filters on once something is hidden", filters.CHAT_MSG_LOOT ~= nil, true)
GamepadXIVChatFeed.GetScrollOffset = function() return 0 end
GamepadXIVChatConversation.GetScrollOffset = function() return 0 end
local function FeedCount() return #GamepadXIVChatFeed.lines end
local before = FeedCount()
filters.CHAT_MSG_LOOT(ChatFrame1, "CHAT_MSG_LOOT", "You receive loot: [Linen Cloth].")
ns.ChatBoxFeed("You receive loot: [Linen Cloth].", 0, 0.7, 0)
Check("hidden loot left out of All", FeedCount(), before)
filters.CHAT_MSG_SAY(ChatFrame1, "CHAT_MSG_SAY", "hello", "Someone")
ns.ChatBoxFeed("[Someone] says: hello", 1, 1, 1)
Check("Say still shows", FeedCount(), before + 1)
ns.ChatBoxFeed("An addon message", 1, 1, 1)
Check("untagged line shows", FeedCount(), before + 2)
filters.CHAT_MSG_LOOT(ChatFrame2 or {}, "CHAT_MSG_LOOT", "x")
ns.ChatBoxFeed("Another addon message", 1, 1, 1)
Check("another chat frame's event doesn't tag the main frame's line", FeedCount(), before + 3)
ns.SetChatTabShows("all", "channel:Trade", false)
filters.CHAT_MSG_CHANNEL(ChatFrame1, "CHAT_MSG_CHANNEL", "WTS", "Seller", "", "2. Trade - City", "", "", 0, 2, "Trade")
ns.ChatBoxFeed("[2. Trade] [Seller]: WTS", 1, 0.75, 0.75)
Check("hidden channel left out", FeedCount(), before + 3)
Check("shown switch reads back", ns.ChatTabShows("all", "say"), true)
Check("hidden switch reads back", ns.ChatTabShows("all", "loot"), false)

-- Tabs from the settings: System and loot is off until picked, Say on by default; reset puts them back.
Check("System and loot off by default", ns.ChatTabShown("#SYSTEM"), false)
Check("Say on by default", ns.ChatTabShown("#SAY"), true)
Check("General off by default", ns.ChatTabShown("#CH:General"), false)
ns.SetChatTab("#SYSTEM", true)
Check("System and loot picked", ns.ChatTabShown("#SYSTEM"), true)
ns.ResetChatTabs()
Check("reset: System and loot off", ns.ChatTabShown("#SYSTEM"), false)
Check("reset: loot back in All", ns.ChatTabShows("all", "loot"), true)
Check("reset: filters off", filters.CHAT_MSG_LOOT, nil)

-- System and loot: a stop once picked; you can't write there, so typing on it goes to Say.
ns.FocusChatBox()
Type("")
local function CountStops()
	for _ = 1, 20 do
		if GamepadXIVChatFeed:IsShown() then break end
		Click("Next")
	end
	local n = 0
	repeat
		Click("Next")
		n = n + 1
	until GamepadXIVChatFeed:IsShown() or n > 20
	return n
end
local withoutSystem = CountStops()
ns.SetChatTab("#SYSTEM", true)
Check("System and loot adds a stop", CountStops(), withoutSystem + 1)
local readOnlySends = 0
for _ = 1, withoutSystem + 1 do
	Click("Next")
	if ns.ChatBoxActiveKey() == nil and not GamepadXIVChatFeed:IsShown() then
		Type("from a read-only tab")
		Click("Send")
		Check("read-only tab: typing goes to Say", sentTo[#sentTo], "#SAY:from a read-only tab")
		readOnlySends = readOnlySends + 1
		ns.FocusChatBox()
	end
end
Check("read-only tabs tried", readOnlySends >= 1, true)
ns.ResetChatTabs()

-- Channel tabs menu: Leave for each channel you are in, Join for the others.
local left = {}
GetChannelList = function() return 1, "General", false end
EnumerateServerChannels = function() return "General", "Trade", "Chromie Time", "Chromie Time", "Trade", "Meeting Stone" end
LeaveChannelByName = function(name) left[#left + 1] = name end
ns.FocusChatBox()
Type("")
Click("Back")
local function PickRow(text)
	local index
	for i, item in ipairs(menu.rows) do
		if item:IsShown() and item.text.text and item.text.text:find(text, 1, true) then index = i end
	end
	if not index then return false end
	for _ = 1, 30 do
		if menu.rows[index].bg:IsShown() then
			Click("Send")
			return true
		end
		Click("Down")
	end
	return false
end
Click("Tabs")
Check("square menu: Channel tabs", PickRow("Channel tabs"), true)
Check("channel tabs: Leave General listed and picked", PickRow("Leave|r  1. General"), true)
Check("leave: the game's leave by number", left[1], "1")
Check("channel tabs: no Join for a joined channel", PickRow("Join|r  General"), false)
Check("channel tabs: no Chromie Time", PickRow("Chromie"), false)
local tradeRows = 0
for _, item in ipairs(menu.rows) do
	if item:IsShown() and item.text.text and item.text.text:find("Join|r  Trade", 1, true) then tradeRows = tradeRows + 1 end
end
Check("channel tabs: Join Trade once", tradeRows, 1)
Check("channel tabs: Join Trade picked", PickRow("Join|r  Trade"), true)
Check("join: /join typed for Cross to send", input:GetText(), "/join Trade")
Check("join: typing", input:HasFocus(), true)

-- Each tab's Channels: kinds added to a tab are copied into its conversation as they come.
local added = {}
ns.ChatAPI.AddLine = function(tab, outgoing, text, class, sender, senderClass, kind, language)
	added[#added + 1] = { tab = tab, o = outgoing, m = text, s = sender, k = kind, l = language }
	chats[tab] = chats[tab] or { lines = {}, unread = 0 }
	return chats[tab]
end
ns.ChatAPI.FullName = function(name) return name end
ns.ChatAPI.EventKeys = { CHAT_MSG_SAY = "#SAY", CHAT_MSG_LOOT = "#SYSTEM", CHAT_MSG_SYSTEM = "#SYSTEM", CHAT_MSG_CHANNEL = "channel" }
ns.ResetChatTabs()
Fire("CHAT_MSG_EMOTE", "waves.", "Bob-Realm")
Check("emote: not in Say by default", #added, 0)
ns.SetChatTabShows("#SAY", "emote", true)
Fire("CHAT_MSG_EMOTE", "waves.", "Bob-Realm")
Check("emote added to Say: copied there", added[1] and added[1].tab, "#SAY")
Check("emote line: the name and the emote", added[1] and added[1].m, "Bob waves.")
Check("emote line: its own colour", added[1] and added[1].k, "EMOTE")
added = {}
Fire("CHAT_MSG_SAY", "hi", "Bob-Realm", "Common")
Check("a Say line isn't copied into Say", #added, 0)
Fire("CHAT_MSG_COMBAT_XP_GAIN", "You gain 120 experience.")
Check("XP: System and loot shows progress by default", added[1] and added[1].tab, "#SYSTEM")
added = {}
Fire("CHAT_MSG_LOOT", "You receive loot: [Linen Cloth].")
Check("loot: kept in System and loot already, not copied", #added, 0)
Check("System and loot takes loot by default", ns.ChatTabTakes("#SYSTEM", "CHAT_MSG_LOOT"), true)
ns.SetChatTabShows("#SYSTEM", "loot", false)
Check("loot turned off in System and loot", ns.ChatTabTakes("#SYSTEM", "CHAT_MSG_LOOT"), false)
Check("system lines still taken", ns.ChatTabTakes("#SYSTEM", "CHAT_MSG_SYSTEM"), true)
ns.SetChatTabShows("#SAY", "say", false)
Check("a tab's own channel stays on", ns.ChatTabShows("#SAY", "say"), true)
ns.SetChatTabShows("#CH:Trade", "channel:General", true)
Fire("CHAT_MSG_CHANNEL", "anyone?", "Ann-Realm", "Common", "1. General - Town", "", "", 0, 1, "General")
Check("General added to Trade", added[1] and added[1].tab, "#CH:Trade")
Check("General line: the player", added[1] and added[1].s, "Ann-Realm")
Check("General line: the channel's colour", added[1] and added[1].k, "CHANNEL1")
added = {}
Fire("CHAT_MSG_CHANNEL", "WTS", "Ann-Realm", "Common", "2. Trade - City", "", "", 0, 2, "Trade")
Check("a Trade line isn't copied into Trade", #added, 0)
ns.ResetChatTabs()
Check("reset: Say without emotes", ns.ChatTabShows("#SAY", "emote"), false)
Check("reset: loot back in System and loot", ns.ChatTabShows("#SYSTEM", "loot"), true)
Check("reset: All shows everything", ns.ChatTabShows("all", "channel:Trade"), true)

-- The Square menu has Messages for the tab you are on.
ns.FocusChatBox()
Type("")
for _ = 1, 20 do
	if GamepadXIVChatFeed:IsShown() then break end
	Click("Next")
end
Click("Back")
Click("Tabs")
Check("square menu: Channels in this tab", PickRow("Channels in this tab"), true)
Check("messages menu: for All", menu.title.text:find("Channels in All", 1, true) ~= nil, true)
Check("messages menu: Say listed first", menu.rows[1].text.text:find("Say", 1, true) ~= nil, true)
Click("Send")
Check("Cross: Say off in All", ns.ChatTabShows("all", "say"), false)
Click("Send")
Check("Cross again: back on", ns.ChatTabShows("all", "say"), true)

-- A tab showing more channels you can write to: the triggers pick where its messages go.

Click("Back")
ns.SetChatTabShows("#SAY", "channel:General", true)
ns.FocusChatBox()
Type("")
for _ = 1, 20 do
	if ns.ChatBoxActiveKey() == "#SAY" then break end
	Click("Next")
end
Check("on Say", ns.ChatBoxActiveKey(), "#SAY")
Check("R2 bound on Say with General added", Key("PADRTRIGGER"), "CLICK GamepadXIVChatBoxChannelNext:LeftButton")
Click("ChannelNext")
Check("R2 on Say with General added: to General", ns.ChatBoxActiveKey(), "#CH:General")
Type("hello general")
Click("Send")
Check("sent to General from the Say tab", sentTo[#sentTo], "#CH:General:hello general")
ns.FocusChatBox()
Click("ChannelPrev")
Check("L2: back to Say", ns.ChatBoxActiveKey(), "#SAY")
ns.ResetChatTabs()
ns.FocusChatBox()
for _ = 1, 20 do
	if ns.ChatBoxActiveKey() == "#SAY" then break end
	Click("Next")
end
Click("ChannelNext")
Check("plain Say tab: the triggers do nothing", ns.ChatBoxActiveKey(), "#SAY")

-- Channel names: however the game spells one, it's the same channel.
ns.ResetChatTabs()
ns.SetChatTabShows("all", "channel:TradeLocal", false)
filters.CHAT_MSG_CHANNEL(ChatFrame1, "CHAT_MSG_CHANNEL", "WTS", "Seller", "", "5. Trade (Local) - City", "", "", 0, 5, "Trade (Local) - City")
local feedBefore = #GamepadXIVChatFeed.lines
ns.ChatBoxFeed("[5. Trade (Local)] [Seller]: WTS", 1, 0.75, 0.75)
Check("Trade (Local) is TradeLocal", #GamepadXIVChatFeed.lines, feedBefore)
Check("a channel tab's own kind, from its key", ns.ChatTabShows("#CH:Trade (Local) - City", "channel:TradeLocal"), true)

-- Lines copied into System and loot read as the game's chat words them.
ns.ResetChatTabs()
added = {}
Fire("CHAT_MSG_CHANNEL_NOTICE", "YOU_CHANGED", "", "", "1. General - Town", "", "", 0, 1, "General")
Check("channel notices are not copied", #added, 0)
Fire("CHAT_MSG_ACHIEVEMENT", "%s has earned the achievement [Level 10]!", "Bob-Realm")
Check("achievement: the name filled in", added[1] and added[1].m, "Bob has earned the achievement [Level 10]!")
ns.SetChatTabShows("#SYSTEM", "loot", true)

-- Your own tabs: a name, the channels picked, on / off, rename and delete.
ns.ResetChatTabs()
Click("Back")
local stopsBefore = CountStops()
local crafting = ns.NewChatTab("  Crafting  ")
Check("new tab: a key", crafting, "#TAB:1")
Check("new tab: the name trimmed", ns.ChatCustomTabInfo(crafting).name, "Crafting")
Check("new tab: on", ns.ChatTabShown(crafting), true)
Check("new tab: a stop", CountStops(), stopsBefore + 1)
Check("new tab: shows nothing at first", ns.ChatTabShows(crafting, "say"), false)
Check("no name, no tab", ns.NewChatTab("   "), nil)
added = {}
ns.SetChatTabShows(crafting, "loot", true)
Fire("CHAT_MSG_LOOT", "You receive loot: [Copper Ore].")
Check("loot picked: copied into the tab", added[1] and added[1].tab, crafting)
-- Typing there goes to the one channel it shows you can write to; R2 picks among several.
IsInGuild = function() return true end
ns.SetChatTabShows(crafting, "guild", true)
ns.SetChatTabShows(crafting, "channel:General", true)
ns.FocusChatBox()
Type("")
local onCrafting = false
for _ = 1, 20 do
	Click("Next")
	if ns.ChatBoxActiveKey() == "#GUILD" then onCrafting = true break end
end
Check("on your tab: typing goes to Guild, the first it shows", onCrafting, true)
Check("your tab: R2 bound", Key("PADRTRIGGER"), "CLICK GamepadXIVChatBoxChannelNext:LeftButton")
Click("ChannelNext")
Check("your tab: R2 to General", ns.ChatBoxActiveKey(), "#CH:General")
Type("")
Click("Back")
ns.ResetChatTabs()
Check("reset: your tab stays", ns.ChatCustomTabInfo(crafting) ~= nil, true)
Check("reset: its channels stay", ns.ChatTabShows(crafting, "loot"), true)
Check("rename", ns.RenameChatTab(crafting, "Mats"), true)
Check("renamed", ns.ChatCustomTabInfo(crafting).name, "Mats")
Check("rename to nothing: kept", ns.RenameChatTab(crafting, ""), false)
ns.SetChatTab(crafting, false)
Check("turned off: no stop", CountStops(), stopsBefore)
ns.SetChatTab(crafting, true)
Check("delete", ns.DeleteChatTab(crafting), true)
Check("deleted: gone", ns.ChatCustomTabInfo(crafting), nil)
Check("deleted: its channels gone", ns.db.chatTabKinds[crafting], nil)
Check("deleted: no stop", CountStops(), stopsBefore)

-- Emotes, /reload and /roll run from Enter, as the game does it for them.
ns.FocusChatBox()
Type("/dance")
input.scripts.OnEnterPressed(input)
Check("Enter runs an emote", performed[#performed], "DANCE:nil")
Check("emote: typing stopped", input:HasFocus(), false)
ns.FocusChatBox()
Type("/DANCE Bob")
input.scripts.OnEnterPressed(input)
Check("emote at a name", performed[#performed], "DANCE:Bob")
ns.FocusChatBox()
Type("/roll")
input.scripts.OnEnterPressed(input)
Check("/roll", rolled, "1-100")
ns.FocusChatBox()
Type("/roll 50")
input.scripts.OnEnterPressed(input)
Check("/roll 50", rolled, "1-50")
ns.FocusChatBox()
Type("/roll 10-20")
input.scripts.OnEnterPressed(input)
Check("/roll 10-20", rolled, "10-20")
ns.FocusChatBox()
Type("/reload")
input.scripts.OnEnterPressed(input)
Check("Enter runs /reload", reloaded, 1)
Check("an emote in combat runs too", (function()
	local was = InCombatLockdown
	InCombatLockdown = function() return true end
	ns.FocusChatBox()
	Type("/dance")
	input.scripts.OnEnterPressed(input)
	InCombatLockdown = was
	return #performed
end)(), 3)

-- Cross (the Send button) runs them the same as Enter.
ns.FocusChatBox()
Type("/dance")
Click("Send")
Check("Cross runs an emote", performed[#performed], "DANCE:nil")
ns.FocusChatBox()
Type("/roll 7")
Click("Send")
Check("Cross runs /roll", rolled, "1-7")
ns.FocusChatBox()
Type("/reload")
Click("Send")
Check("Cross runs /reload", reloaded, 2)
ns.FocusChatBox()
Type("/gxiv pad")
Click("Send")
Check("Cross runs an addon command", _G.gxivRan, "pad")
ns.FocusChatBox()
Type("hi from the pad")
Click("Send")
Check("Cross sends a message", sentTo[#sentTo], "#SAY:hi from the pad")

if fails > 0 then
	print("chatbox: " .. fails .. " FAILED")
	os.exit(1)
end
print("chatbox: all checks passed")
