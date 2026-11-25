local _, ns = ...

-- Telling you when a newer Gamepad XIV is out. Addons can't reach the internet, so copies tell each
-- other: each one sends its version to your guild and group over the hidden addon channel, and a copy
-- that hears a newer one prints a line in chat, once a session. A copy that hears an older one answers
-- after a few seconds (unless someone else did first), so the older copy learns about the update.
-- Only release versions ("v1.2.3") count. The newest heard is kept for the account, and reminds you at
-- each login for three days or until you update.

local PREFIX = "GamepadXIVVer"
local THROTTLE = 10 -- seconds between sends on one channel
local REMEMBER_FOR = 3 * 24 * 60 * 60
local GROUP_CHANNELS = { GUILD = true, PARTY = true, RAID = true, INSTANCE_CHAT = true }

local sentAt, replyDue = {}, {}
local told = false
local groupSize = 0

local function Release(text)
	if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) or #text > 16 then
		return nil
	end
	return text:match("^v%d+%.%d+%.%d+$") and text or nil
end

local function Mine()
	return Release(ns.AddonVersion and ns.AddonVersion())
end

local function Tell(version)
	if told then
		return
	end
	told = true
	ns.Print("Version " .. version .. " is available (you have " .. (Mine() or "?") .. "). Update on CurseForge.")
end

local function Send(channel)
	local version = Mine()
	if not version then
		return
	end
	local now = GetTime()
	if sentAt[channel] and now - sentAt[channel] < THROTTLE then
		return
	end
	sentAt[channel] = now
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		pcall(C_ChatInfo.SendAddonMessage, PREFIX, version, channel)
	end
end

local function SendAll()
	if IsInGuild() then
		Send("GUILD")
	end
	if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
		Send("INSTANCE_CHAT")
	end
	if IsInRaid(LE_PARTY_CATEGORY_HOME) then
		Send("RAID")
	elseif IsInGroup(LE_PARTY_CATEGORY_HOME) then
		Send("PARTY")
	end
end

local function Heard(text, channel)
	local theirs, mine = Release(text), Mine()
	if not theirs or not mine or theirs == mine then
		replyDue[channel] = nil -- someone already has this version out there
		return
	end
	if ns.VersionNewer(mine, theirs) then
		-- An older copy: answer it, unless another player does first.
		if GROUP_CHANNELS[channel] and not replyDue[channel] then
			replyDue[channel] = true
			C_Timer.After(1 + math.random() * 4, function()
				if replyDue[channel] then
					replyDue[channel] = nil
					Send(channel)
				end
			end)
		end
		return
	end
	replyDue[channel] = nil
	local account = GamepadXIVAccountDB
	if type(account) == "table" then
		if not account.newestVersion or ns.VersionNewer(theirs, account.newestVersion) or theirs == account.newestVersion then
			account.newestVersion, account.newestVersionAt = theirs, time()
		end
	end
	Tell(theirs)
end

local function AtLogin()
	local account = GamepadXIVAccountDB
	local mine = Mine()
	if type(account) == "table" and mine then
		local known, at = account.newestVersion, tonumber(account.newestVersionAt)
		if Release(known) and ns.VersionNewer(known, mine) and at and time() - at < REMEMBER_FOR then
			Tell(known)
		else
			account.newestVersion, account.newestVersionAt = nil, nil
		end
	end
	SendAll()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("CHAT_MSG_ADDON")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:SetScript("OnEvent", function(_, event, prefix, text, channel)
	if event == "CHAT_MSG_ADDON" then
		if prefix == PREFIX then
			pcall(Heard, text, channel)
		end
	elseif event == "PLAYER_LOGIN" then
		if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
			pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
		end
		groupSize = GetNumGroupMembers()
		C_Timer.After(8, function() pcall(AtLogin) end) -- after the loading screen, so the line is seen
	else
		-- Someone joined: they hear your version, and you theirs when they answer.
		local size = GetNumGroupMembers()
		if size > groupSize then
			pcall(SendAll)
		end
		groupSize = size
	end
end)
