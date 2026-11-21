local _, ns = ...

-- The player's mounts and macros are actions too, so a button or combination can summon a mount or
-- run a macro. Keys "mount-<spell ID>" and "macro-<name>", before "Nothing". Rebuilt out of combat
-- when a mount is learned or a macro changes, so new ones show up in the settings.
local customButtons = {} -- action key -> button name
local customCount = 0

local function CustomButton(key, attributes)
	local name = customButtons[key]
	if not name then
		customCount = customCount + 1
		name = "GamepadXIVAction" .. customCount
		customButtons[key] = name
		local button = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
		button:RegisterForClicks("AnyDown", "AnyUp")
		button:SetAttribute("useOnKeyDown", true)
		button:Hide()
	end
	local button = _G[name]
	for attribute, value in pairs(attributes) do
		button:SetAttribute(attribute, value)
	end
	return "CLICK " .. name .. ":LeftButton"
end

-- Collected mounts this character can use, by name: { { spellID, name, icon } }.
function ns.PlayerMounts()
	local mounts = {}
	local journal = C_MountJournal
	if journal and journal.GetMountIDs and journal.GetMountInfoByID then
		for _, mountID in ipairs(journal.GetMountIDs() or {}) do
			local name, spellID, icon, _, _, _, _, _, _, hideOnChar, isCollected = journal.GetMountInfoByID(mountID)
			if name and spellID and isCollected and not hideOnChar then
				tinsert(mounts, { spellID, name, icon })
			end
		end
	elseif GetNumCompanions and GetCompanionInfo then
		for index = 1, GetNumCompanions("MOUNT") or 0 do
			local _, name, spellID, icon = GetCompanionInfo("MOUNT", index)
			if name and spellID then
				tinsert(mounts, { spellID, name, icon })
			end
		end
	end
	table.sort(mounts, function(a, b) return a[2] < b[2] end)
	return mounts
end

function ns.RefreshCustomActions()
	if InCombatLockdown() then
		return false
	end
	for index = #ns.STICK_ACTIONS, 1, -1 do
		local key = ns.STICK_ACTIONS[index][1]
		if key:match("^mount%-") or key:match("^macro%-") then
			tremove(ns.STICK_ACTIONS, index)
		end
	end
	local function Insert(key, label, command, icon, group)
		tinsert(ns.STICK_ACTIONS, #ns.STICK_ACTIONS, { key, label, command, nil, icon })
		ns.STICK_ACTION_GROUPS[key] = group
	end
	for _, mount in ipairs(ns.PlayerMounts()) do
		local name = mount[2]
		-- Pressed again while mounted, it gets off, but never in the air.
		local command = CustomButton("mount-" .. mount[1], { type = "macro",
			macrotext = "/cast [nomounted] " .. name .. "\n/dismount [mounted,noflying]" })
		Insert("mount-" .. mount[1], name, command, mount[3], "mount")
	end
	for _, macro in ipairs(ns.RingMacroChoices and ns.RingMacroChoices() or {}) do
		local name = macro.data.macro
		local command = CustomButton("macro-" .. name, { type = "macro", macro = name })
		Insert("macro-" .. name, "Macro: " .. name, command, macro.icon, "macro")
	end
	return true
end

do
	local watcher = CreateFrame("Frame")
	local pending = false
	local function Refresh()
		if ns.RefreshCustomActions() then
			pending = false
			ns.Sync()
		else
			pending = true
		end
	end
	for _, event in ipairs({ "PLAYER_LOGIN", "NEW_MOUNT_ADDED", "COMPANION_LEARNED", "UPDATE_MACROS", "PLAYER_REGEN_ENABLED" }) do
		pcall(watcher.RegisterEvent, watcher, event)
	end
	watcher:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_ENABLED" and not pending then
			return
		end
		-- The mount journal can still be empty right at login.
		C_Timer.After(event == "PLAYER_LOGIN" and 2 or 0, Refresh)
	end)
end
