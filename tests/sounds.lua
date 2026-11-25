-- Offline checks of the chat sounds (Sounds.lua). Not loaded by the game.
-- Run from the addon folder with: lua5.1 tests/sounds.lua

local frameMethods = setmetatable({}, { __index = function() return function() end end })
function CreateFrame()
	return setmetatable({}, { __index = frameMethods })
end
local now = 100
function GetTime() return now end
function UnitName() return "Me" end
function UnitGUID() return "Player-1-ME" end
function GetNormalizedRealmName() return "Realm" end
SOUNDKIT = { TELL_MESSAGE = 3081 }
local played = {}
function PlaySound(id, channel) played[#played + 1] = "kit " .. id .. " " .. channel end
function PlaySoundFile(path, channel) played[#played + 1] = path .. " " .. channel end
local shared = { ["CSC Sound 8"] = "Interface\\AddOns\\Chat_Sound_Customizer\\audios\\sound8.mp3" }
local media = {
	Fetch = function(_, _, name) return shared[name] end,
	List = function() return { "CSC Sound 8", "None" } end,
}
function LibStub(name) return name == "LibSharedMedia-3.0" and media or nil end

local ns = {}
assert(loadfile("Sounds.lua"))("GamepadXIV", ns)
local Sounds = ns.ChatSounds

local fails = 0
local function Check(label, actual, expected)
	if actual ~= expected then
		fails = fails + 1
		print("FAIL " .. label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end
local OURS = "Interface\\AddOns\\GamepadXIV\\Sounds\\"

-- Choices resolve to a file or a sound kit; missing ones fall back to the whisper sound.
local how, what = Sounds.Resolve("gxiv:ping")
Check("our sound", what, OURS .. "ping.ogg")
how, what = Sounds.Resolve("kit:TELL_MESSAGE")
Check("game sound", how .. " " .. what, "kit 3081")
how, what = Sounds.Resolve("lsm:CSC Sound 8")
Check("shared sound", what, shared["CSC Sound 8"])
how, what = Sounds.Resolve("lsm:CSC Sound 99")
Check("missing shared sound", what, OURS .. "whisper.ogg")
how, what = Sounds.Resolve("kit:NOT_THERE")
Check("missing game sound", what, OURS .. "whisper.ogg")
Check("none", Sounds.Resolve("none"), nil)

-- The list: game sounds only when the client has them, shared ones without "None", a missing pick kept.
local values = {}
for _, choice in ipairs(Sounds.Choices("lsm:Gone")) do
	values[choice[1]] = true
end
Check("lists ours", values["gxiv:whisper2"], true)
Check("lists a game sound", values["kit:TELL_MESSAGE"], true)
Check("leaves out a missing game sound", values["kit:RAID_WARNING"], nil)
Check("lists a shared sound", values["lsm:CSC Sound 8"], true)
Check("leaves out None", values["lsm:None"], nil)
Check("keeps a missing pick", values["lsm:Gone"], true)

-- Events: your own messages, other people's, the throttle, the switch and the suppress hook.
ns.db = { chatSounds = true, chatSoundOutput = "Master", chatSoundWhisper = "lsm:CSC Sound 8", chatSoundParty = "gxiv:ping",
	chatSoundRaid = "none", chatSoundChannels = "gxiv:bell" }
Check("own whisper", Sounds.OnChat("CHAT_MSG_WHISPER", "hi", "Me-Realm"), nil)
Check("own party line", Sounds.OnChat("CHAT_MSG_PARTY", "hi", "Me"), nil)
Check("own line by guid", Sounds.OnChat("CHAT_MSG_PARTY", "hi", "Other-Realm2", nil, nil, nil, nil, nil, nil, nil, nil, nil, "Player-1-ME"), nil)
Check("whisper", Sounds.OnChat("CHAT_MSG_WHISPER", "hi", "Friend"), "lsm:CSC Sound 8")
Check("whisper sound played", played[#played], shared["CSC Sound 8"] .. " Master")
Check("whisper burst", Sounds.OnChat("CHAT_MSG_WHISPER", "hi", "Friend"), nil)
now = now + 1.1
Check("whisper after a second", Sounds.OnChat("CHAT_MSG_WHISPER", "hi", "Friend") ~= nil, true)
Check("party", Sounds.OnChat("CHAT_MSG_PARTY_LEADER", "hi", "Friend"), "gxiv:ping")
Check("raid set to none", Sounds.OnChat("CHAT_MSG_RAID", "hi", "Friend"), nil)
Check("unknown event", Sounds.OnChat("CHAT_MSG_SYSTEM", "hi", "Friend"), nil)

-- The conversation being typed in stays quiet: whispers by full name, channels by "#CH:<name>".
local active
ns.ChatBoxActiveKey = function() return active end
now = now + 5
active = "Friend-Realm"
Check("typing to the whisperer", Sounds.OnChat("CHAT_MSG_WHISPER", "hi", "Friend"), nil)
active = "Friend"
Check("typing to the whisperer, short name", Sounds.OnChat("CHAT_MSG_WHISPER", "hi", "Friend-Realm"), nil)
active = "#PARTY"
Check("typing in party", Sounds.OnChat("CHAT_MSG_PARTY", "hi", "Friend"), nil)
active = "#CH:Trade"
Check("typing in Trade", Sounds.OnChat("CHAT_MSG_CHANNEL", "wts", "Friend", nil, "2. Trade - City", nil, nil, nil, 2, "Trade"), nil)
Check("other channel plays", Sounds.OnChat("CHAT_MSG_CHANNEL", "hi", "Friend", nil, "1. General - Zone", nil, nil, nil, 1, "General"), "gxiv:bell")
active = nil
Check("whisper when not typing", Sounds.OnChat("CHAT_MSG_WHISPER", "hi", "Friend") ~= nil, true)

-- Secret senders are skipped; the switch turns everything off; SFX is used when chosen.
now = now + 5
issecretvalue = function(value) return value == "SECRET" end
Check("secret sender", Sounds.OnChat("CHAT_MSG_WHISPER", "hi", "SECRET"), nil)
ns.db.chatSounds = false
Check("switched off", Sounds.OnChat("CHAT_MSG_WHISPER", "hi", "Friend"), nil)
ns.db.chatSounds, ns.db.chatSoundOutput = true, "SFX"
Sounds.OnChat("CHAT_MSG_WHISPER", "hi", "Friend")
Check("SFX channel", played[#played], shared["CSC Sound 8"] .. " SFX")

if fails > 0 then
	print("sounds: " .. fails .. " check(s) failed")
	os.exit(1)
end
print("sounds: all checks passed")
