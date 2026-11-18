local ADDON, ns = ...

-- Profiles: named sets of settings kept in the account-wide saved variables. Each character uses one
-- profile (db.profile), at first one named after the character, made at its first login. Characters
-- can share a profile: the settings stay in the character's own saved variables while playing, are
-- saved to its profile at logout and when switching, and are taken from the profile at login, so a
-- change made on one character reaches the others at their next login. A settings string carries
-- the same settings between accounts or players.
--
-- Only the settings in ns.DEFAULTS are copied, without per-character state: the saved CVars, the
-- error log, the ring (its entries are that character's spells and items), the camera consent, the
-- set in use, the minimap icon's place and the form sets (each class has other forms). The abilities
-- on the bars are Forever's own action slots and never come along.

local EXCLUDED = {
	errorLog = true, taintOrigin = true, spellbookDebug = true, petMenuDebug = true, lootLog = true, taintWatchOff = true, savedCVars = true, ringEntries = true, ringPages = true,
	experimentalAccepted = true, experimentalDeclined = true,
	set = true, minimapAngle = true, formSet1 = true, formSet2 = true, formSet3 = true, formSet4 = true,
}

-- Whether a copied value can be used, and the value to use: the right type, a real number, and
-- (ns.ValidSetting, from the settings window's rows) one of the setting's choices or inside its range.
-- trusted skips that last check: at load the lists of choices are not complete yet (the stick actions
-- add the class's spells at login), and the profile holds values that were checked when they came in.
local function Usable(key, value, trusted)
	local default = ns.DEFAULTS[key]
	if EXCLUDED[key] or value == nil or type(value) ~= type(default) or type(value) == "table" then
		return false
	end
	if type(value) == "number" and (value ~= value or value == math.huge or value == -math.huge) then
		return false
	end
	if ns.ValidSetting and not trusted then
		return ns.ValidSetting(key, value)
	end
	return true, value
end

local PREFIX = "GXIV1:"

local function Account()
	GamepadXIVAccountDB = GamepadXIVAccountDB or {}
	local account = GamepadXIVAccountDB
	account.profiles = account.profiles or {}
	-- A test build kept the characters' settings apart from the profiles.
	if account.characters then
		for name, settings in pairs(account.characters) do
			account.profiles[name] = account.profiles[name] or settings
		end
		account.characters = nil
	end
	return account
end

local function CharacterName()
	local name, realm
	if UnitFullName then
		name, realm = UnitFullName("player")
	end
	name = name or (UnitName and UnitName("player")) or "?"
	realm = realm or (GetRealmName and GetRealmName()) or ""
	realm = realm:gsub("%s", "")
	return realm ~= "" and (name .. "-" .. realm) or name
end

-- The copyable settings of a settings table, with the migration they were saved at.
function ns.CopySettings(db)
	local copy = {}
	for key, default in pairs(ns.DEFAULTS) do
		local value = db[key]
		if not EXCLUDED[key] and value ~= nil and type(value) == type(default) and type(value) ~= "table" then
			copy[key] = value
		end
	end
	copy.migration = db.migration
	return copy
end

-- Puts copied settings on this character: older copies first go through the migrations they missed,
-- and values of the wrong type or for unknown settings are left out. Returns how many were set.
-- quiet: at load, from this account's own profile, before anything is drawn, so nothing needs
-- refreshing.
function ns.ApplySettings(source, quiet)
	local copy = {}
	for key, value in pairs(source) do
		copy[key] = value
	end
	-- Without a migration number (a damaged string) the settings are taken as current.
	local migration = tonumber(copy.migration)
	if migration and ns.RunMigrations then
		copy.migration = math.max(0, math.floor(migration))
		ns.RunMigrations(copy)
	end
	local count = 0
	for key in pairs(ns.DEFAULTS) do
		local usable, value = Usable(key, copy[key], quiet)
		if usable then
			ns.db[key] = value
			count = count + 1
		end
	end
	-- Face target needs the experimental camera allowed on this character too, as the setting does.
	if ns.db.autoFace and ns.AllowExperimentalCamera then
		ns.AllowExperimentalCamera()
	end
	if not quiet and ns.AfterSettingsChanged then
		ns.AfterSettingsChanged()
	end
	return count
end

-- Everything that reads the settings once, so a whole set of them shows without a /reload.
function ns.AfterSettingsChanged()
	for _, refresh in ipairs({ "UpdateMinimapButton", "ApplyAlwaysCompare", "RefreshVisuals", "RefreshActiveHighlight",
			"UpdatePartyPrompt", "RefreshLootDetails", "Sync" }) do
		if ns[refresh] then
			pcall(ns[refresh])
		end
	end
end

-- Settings strings: GXIV1: then key=value pairs split by ";". A value starts with its type: s for
-- text, n for a number, t / f for true / false. Characters that would break the string, spaces, and
-- the game's markup character (|) are written as %XX.
local function Escape(text)
	return (text:gsub("[%%;=|:%s%c]", function(char) return format("%%%02X", char:byte()) end))
end

local function Unescape(text)
	return (text:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

function ns.ExportSettings(db)
	local copy = ns.CopySettings(db or ns.db)
	local keys = {}
	for key in pairs(copy) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	local parts = {}
	for _, key in ipairs(keys) do
		local value = copy[key]
		local kind = type(value)
		local text
		if kind == "string" then
			text = "s" .. Escape(value)
		elseif kind == "number" then
			text = "n" .. tostring(value)
		elseif kind == "boolean" then
			text = value and "t" or "f"
		end
		if text then
			parts[#parts + 1] = Escape(key) .. "=" .. text
		end
	end
	return PREFIX .. table.concat(parts, ";")
end

-- The settings in a string, or nil and why not.
function ns.ParseSettings(text)
	text = (text or ""):gsub("%s", "")
	if text:sub(1, #PREFIX) ~= PREFIX then
		return nil, "This is not a Gamepad XIV settings string."
	end
	local settings, count = {}, 0
	for pair in text:sub(#PREFIX + 1):gmatch("[^;]+") do
		local key, kind, value = pair:match("^([^=]+)=(%a)(.*)$")
		if not key then
			return nil, "The settings string is damaged. Copy all of it again."
		end
		key = Unescape(key)
		if kind == "s" then
			settings[key] = Unescape(value)
		elseif kind == "n" then
			settings[key] = tonumber(value)
		elseif kind == "t" or kind == "f" then
			settings[key] = kind == "t"
		end
		count = count + 1
	end
	if count == 0 then
		return nil, "The settings string is empty."
	end
	return settings
end

function ns.ImportSettings(text)
	local settings, problem = ns.ParseSettings(text)
	if not settings then
		return nil, problem
	end
	return ns.ApplySettings(settings)
end

-- The profile list: { name, label } pairs by name, the one in use marked. except leaves one out.
function ns.ProfileChoices(except)
	local names = {}
	for name in pairs(Account().profiles) do
		if name ~= except then
			names[#names + 1] = name
		end
	end
	table.sort(names)
	local list = {}
	for _, name in ipairs(names) do
		list[#list + 1] = { name, name == ns.db.profile and (name .. " |cff8c8c8c(in use)|r") or name }
	end
	return list
end

function ns.ProfileInUse()
	return ns.db.profile
end

-- Keeps the settings in the profile in use.
function ns.SaveCurrentProfile()
	if ns.db and ns.db.profile then
		Account().profiles[ns.db.profile] = ns.CopySettings(ns.db)
	end
end

-- Switches this character to another profile and its settings; the current settings stay in the
-- profile they came from.
function ns.UseProfile(name)
	local settings = name and Account().profiles[name]
	if not settings or name == ns.db.profile then
		return false
	end
	ns.SaveCurrentProfile()
	ns.db.profile = name
	ns.ApplySettings(settings)
	return true
end

-- A new profile with the current settings, which this character then uses. False if the name is taken.
function ns.NewProfile(name)
	local profiles = Account().profiles
	if profiles[name] then
		return false
	end
	ns.SaveCurrentProfile()
	ns.db.profile = name
	profiles[name] = ns.CopySettings(ns.db)
	return true
end

-- Copies another profile's settings into the one in use.
function ns.CopyProfile(name)
	local settings = name and Account().profiles[name]
	return settings and ns.ApplySettings(settings)
end

-- Removes a profile other than the one in use. A character still using it makes it again from its
-- own settings at its next login.
function ns.DeleteProfile(name)
	local profiles = Account().profiles
	if name and name ~= ns.db.profile and profiles[name] then
		profiles[name] = nil
		return true
	end
end

-- At load: the settings of the profile in use, which another character may have changed.
function ns.LoadProfileAtStart()
	local settings = ns.db.profile and Account().profiles[ns.db.profile]
	if settings then
		ns.ApplySettings(settings, true)
	end
end

-- At login: a character without a profile (new, or from before profiles) gets one named after it,
-- and a profile deleted elsewhere is made again from the settings. At logout the settings are saved.
function ns.SaveCharacterSettings()
	if not ns.db then
		return
	end
	if not ns.db.profile then
		ns.db.profile = CharacterName()
	end
	ns.SaveCurrentProfile()
end

do
	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("PLAYER_LOGIN")
	watcher:RegisterEvent("PLAYER_LOGOUT")
	watcher:SetScript("OnEvent", function()
		pcall(ns.SaveCharacterSettings)
	end)
end
