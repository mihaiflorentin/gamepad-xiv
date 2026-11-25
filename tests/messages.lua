-- Offline checks of the editable ready-made messages (LfgFilter.lua's ns.ChatAPI and MessagesEditor.lua).
-- Not loaded by the game. Run from the addon folder with: lua5.1 tests/messages.lua

tinsert, tremove, wipe = table.insert, table.remove, function(t) for k in pairs(t) do t[k] = nil end return t end
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
date = os.date
local frameMethods = setmetatable({}, { __index = function() return function() end end })
function CreateFrame()
	return setmetatable({}, { __index = frameMethods })
end
UIParent = CreateFrame()
C_LFGList = { GetAvailableCategories = function() return {} end }
GetNormalizedRealmName = function() return "Realm" end
Ambiguate = function(name) return name end
local sent = {}
C_ChatInfo = { SendChatMessage = function(text, kind, _, target) sent[#sent + 1] = { text = text, kind = kind, target = target } end }

local ns = { Trail = function() end, Print = function() end }
ns.LfgMessage = function() return "ASK MESSAGE" end
assert(loadfile("LfgFilter.lua"))("GamepadXIV", ns)
assert(loadfile("MessagesEditor.lua"))("GamepadXIV", ns)

local fails = 0
local function Check(label, actual, expected)
	if actual ~= expected then
		fails = fails + 1
		print("FAIL " .. label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

local api = ns.ChatAPI
local phrases, replies = api.Phrases, api.QuickReplies
local editor = ns.MessagesEditor

-- The Agreeing category is among the defaults.
local agreeing
for _, group in ipairs(phrases) do
	if group.name == "Agreeing" then
		agreeing = group
	end
end
Check("Agreeing category", agreeing and agreeing[1], "Yes.")
Check("Agreeing has 8 messages", agreeing and #agreeing, 8)
local defaultCategories, defaultReplies = #phrases, #replies

-- Saved lists replace the ones in use, in place, without empty text; the reply index is clamped.
ns.db = { lfgFilterReply = 7, lfgFilter = {} }
GamepadXIVAccountDB = {
	chatPhrases = { { name = "Mine", "x", "", 5 }, { name = "", "dropped" }, "junk" },
	chatQuickReplies = { "First", "<ask>", "" },
}
editor.Apply()
Check("same phrases table", api.Phrases, phrases)
Check("same replies table", api.QuickReplies, replies)
Check("one usable category", #phrases, 1)
Check("category name", phrases[1].name, "Mine")
Check("category keeps text only", #phrases[1], 1)
Check("two quick replies", #replies, 2)
Check("reply index clamped", ns.db.lfgFilterReply, 2)
Check("ReplyIndex clamped", api.ReplyIndex(), 2)
Check("ReplyIndex wraps", api.ReplyIndex(1), 1)

-- Ready-made messages go into the message as text: "<ask>" is the group finder message. Nothing is sent.
Check("ask expanded", api.ExpandPhrase("<ask>", "Someone-Realm"), "ASK MESSAGE")
Check("ask expanded without a name", api.ExpandPhrase("<ask>"), "ASK MESSAGE")
Check("other text as it is", api.ExpandPhrase("Hello!", "Someone-Realm"), "Hello!")
Check("expanding sends nothing", #sent, 0)
Check("SendPhrase is gone", api.SendPhrase, nil)

-- The whole message between the markers, once; not in public channels, not with the setting off, and
-- as typed when the markers would take it past 255.
ns.db.chatIcons = true
Check("marked", api.Decorate("Hello! ASK MESSAGE", "Someone-Realm"), "{rt3} Hello! ASK MESSAGE {rt3}")
Check("marked in party", api.Decorate("Pull!", "#PARTY"), "{rt3} Pull! {rt3}")
Check("not in public channels", api.Decorate("WTS", "#CH:Trade"), "WTS")
Check("too long for the markers", api.Decorate(string.rep("x", 250), "Someone-Realm"), string.rep("x", 250))
Check("just fits the markers", api.Decorate(string.rep("x", 243), "Someone-Realm"), "{rt3} " .. string.rep("x", 243) .. " {rt3}")
ns.db.chatIcons = false
Check("setting off: as typed", api.Decorate("Hello!", "Someone-Realm"), "Hello!")

-- An empty saved list of quick replies falls back to the defaults.
GamepadXIVAccountDB.chatQuickReplies = {}
editor.Apply()
Check("empty replies give defaults", #replies, defaultReplies)

-- Editing saves for the account; a list back at the defaults is saved as nil.
GamepadXIVAccountDB = {}
editor.Apply()
Check("defaults back", #phrases, defaultCategories)
editor.Modify(function(p, r)
	r[#r + 1] = "Brb"
	table.remove(p, 1)
end)
Check("replies saved", GamepadXIVAccountDB.chatQuickReplies and GamepadXIVAccountDB.chatQuickReplies[#GamepadXIVAccountDB.chatQuickReplies], "Brb")
Check("phrases saved", GamepadXIVAccountDB.chatPhrases and #GamepadXIVAccountDB.chatPhrases, defaultCategories - 1)
Check("in use too", replies[#replies], "Brb")
Check("saved copy is not the table in use", GamepadXIVAccountDB.chatQuickReplies ~= replies, true)
editor.Modify(function(_, r)
	table.remove(r)
end)
Check("replies at defaults saved as nil", GamepadXIVAccountDB.chatQuickReplies, nil)
editor.Reset()
Check("reset clears phrases", GamepadXIVAccountDB.chatPhrases, nil)
Check("reset restores categories", #phrases, defaultCategories)
Check("same table after reset", api.Phrases, phrases)

-- Shrinking the quick replies clamps the index in use.
ns.db.lfgFilterReply = #replies
editor.Modify(function(_, r)
	for i = #r, 2, -1 do
		table.remove(r, i)
	end
end)
Check("index after shrinking", ns.db.lfgFilterReply, 1)
Check("one reply left", #replies, 1)

if fails > 0 then
	print("messages: " .. fails .. " check(s) failed")
	os.exit(1)
end
print("messages: all checks passed")
