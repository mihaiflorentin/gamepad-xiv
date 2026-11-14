-- Offline checks of profiles and settings strings (Profiles.lua). Not loaded by the game.
-- Run from the addon folder with: lua5.1 tests/profiles.lua

format = string.format
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function UnitFullName() return "Tester", "Some Realm" end
function CreateFrame()
	return { RegisterEvent = function() end, SetScript = function() end }
end

local ns = {
	DEFAULTS = {
		enabled = true, theme = "hex", scale = 1, lfgMessage = "Hi <class>", errorLog = {}, savedCVars = {},
		ringPages = {}, experimentalDeclined = false, activeStrength = 0.7, activeStrengthCombo = 0.7, set = 1,
	},
}
local refreshed = 0
ns.Sync = function() refreshed = refreshed + 1 end
-- Like Core.lua's last migration: the combo brightness starts at the selected bar brightness.
ns.RunMigrations = function(db)
	if db.migration < 12 and db.activeStrength then
		db.activeStrengthCombo = db.activeStrength
	end
	db.migration = 12
end
assert(loadfile("Profiles.lua"))("GamepadXIV", ns)

local failures = 0
local function Check(label, actual, expected)
	if actual ~= expected then
		failures = failures + 1
		print("FAIL " .. label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

ns.db = {
	enabled = false, theme = "orb", scale = 1.25, lfgMessage = "Hello; 100% |cffff0000red|r = a:b  x",
	errorLog = { { message = "x" } }, savedCVars = { a = 1 }, ringPages = { {} }, experimentalDeclined = true,
	activeStrength = 0.4, activeStrengthCombo = 0.55, migration = 12, stanceStorage = { 5 },
}

-- Round trip.
local text = ns.ExportSettings()
Check("prefix", text:sub(1, 6), "GXIV1:")
Check("no pipes", text:find("|", 1, true), nil)
Check("no spaces", text:find(" ", 1, true), nil)
local parsed = assert(ns.ParseSettings(text))
Check("theme", parsed.theme, "orb")
Check("scale", parsed.scale, 1.25)
Check("enabled", parsed.enabled, false)
Check("message", parsed.lfgMessage, ns.db.lfgMessage)
Check("no ring", parsed.ringPages, nil)
Check("no cvars", parsed.savedCVars, nil)
Check("no consent", parsed.experimentalDeclined, nil)
Check("no stance storage", parsed.stanceStorage, nil)

-- Import onto another character.
local source = ns.db
ns.db = { enabled = true, theme = "hex", scale = 1, lfgMessage = "x", errorLog = {}, savedCVars = { b = 2 }, ringPages = { { mine = true } },
	experimentalDeclined = false, activeStrength = 0.7, activeStrengthCombo = 0.7, migration = 12 }
local count = ns.ImportSettings("  " .. text .. "\n")
Check("imported count", count, 6)
Check("imported theme", ns.db.theme, "orb")
Check("imported message", ns.db.lfgMessage, source.lfgMessage)
Check("kept cvars", ns.db.savedCVars.b, 2)
Check("kept ring", ns.db.ringPages[1].mine, true)
Check("kept consent", ns.db.experimentalDeclined, false)
Check("refreshed", refreshed, 1)

-- Wrong types and unknown keys are left out; bad strings are refused.
ns.db.scale = 1
ns.ImportSettings("GXIV1:scale=sbig;nothing=t;theme=sink")
Check("wrong type", ns.db.scale, 1)
Check("unknown key", ns.db.nothing, nil)
Check("string value", ns.db.theme, "ink")
Check("not a string", select(2, ns.ImportSettings("hello")), "This is not a Gamepad XIV settings string.")
Check("damaged", select(2, ns.ImportSettings("GXIV1:theme")), "The settings string is damaged. Copy all of it again.")
Check("empty", select(2, ns.ImportSettings("GXIV1:")), "The settings string is empty.")

-- Values checked against the settings rows (ns.ValidSetting in Config.lua).
ns.ValidSetting = function(key, value)
	if key == "theme" then return value == "orb" or value == "hex", value end
	if key == "scale" then return true, math.max(0.5, math.min(1.5, value)) end
	return true, value
end
ns.ImportSettings("GXIV1:theme=sbogus;scale=n0;migration=n-5")
Check("bad choice", ns.db.theme, "ink")
Check("clamped number", ns.db.scale, 0.5)
ns.ImportSettings("GXIV1:theme=shex;scale=n1;migration=n1.5")
Check("odd migration", ns.db.theme, "hex")
ns.ImportSettings("GXIV1:theme=sorb")
Check("no migration", ns.db.theme, "orb")
ns.ValidSetting = nil
ns.ImportSettings("GXIV1:set=n3;scale=n1")
Check("set not copied", ns.db.set, nil)

-- An old copy runs the migrations it missed.
ns.ApplySettings({ activeStrength = 0.3, activeStrengthCombo = 0.9, migration = 11 })
Check("migrated combo", ns.db.activeStrengthCombo, 0.3)

-- Profiles. A test build's character list becomes profiles.
GamepadXIVAccountDB = { characters = { ["Alt-Realm"] = { theme = "sigil", migration = 12 } } }
ns.db.theme = "holo"
ns.db.profile = nil

-- First login: a profile named after the character, with its settings.
ns.SaveCharacterSettings()
local profiles = GamepadXIVAccountDB.profiles
Check("characters folded", GamepadXIVAccountDB.characters, nil)
Check("own profile", ns.db.profile, "Tester-SomeRealm")
Check("own profile saved", profiles["Tester-SomeRealm"].theme, "holo")
local choices = ns.ProfileChoices()
Check("choices", #choices, 2)
Check("by name", choices[1][1], "Alt-Realm")
Check("in use marked", choices[2][2]:find("in use", 1, true) ~= nil, true)
Check("others leave out", #ns.ProfileChoices(ns.db.profile), 1)

-- New profile: current settings, then used.
Check("new", ns.NewProfile("Healer"), true)
Check("new taken", ns.NewProfile("Healer"), false)
Check("uses new", ns.db.profile, "Healer")
ns.db.theme = "ink"

-- Switching keeps the settings in the profile left.
Check("switch", ns.UseProfile("Alt-Realm"), true)
Check("switched theme", ns.db.theme, "sigil")
Check("left profile kept", profiles.Healer.theme, "ink")
Check("switch to same", ns.UseProfile("Alt-Realm"), false)
Check("switch to missing", ns.UseProfile("Nobody"), false)

-- Logout saves into the profile in use; another character using it gets the change at load.
ns.db.theme = "orb"
ns.SaveCharacterSettings()
Check("logout saved", profiles["Alt-Realm"].theme, "orb")
local mine = ns.db
ns.db = { theme = "hex", profile = "Alt-Realm", migration = 12 }
local before = refreshed
ns.LoadProfileAtStart()
Check("shared at load", ns.db.theme, "orb")
Check("quiet at load", refreshed, before)
ns.db = mine

-- Copy another profile into the one in use; delete only others.
Check("copy", ns.CopyProfile("Healer") ~= nil, true)
Check("copied", ns.db.theme, "ink")
Check("still in use", ns.db.profile, "Alt-Realm")
Check("delete in use", ns.DeleteProfile("Alt-Realm"), nil)
Check("delete", ns.DeleteProfile("Healer"), true)
Check("deleted", profiles.Healer, nil)

-- A profile deleted elsewhere is made again at login.
profiles["Alt-Realm"] = nil
ns.SaveCharacterSettings()
Check("made again", profiles["Alt-Realm"].theme, "ink")

if failures > 0 then
	print(failures .. " failed")
	os.exit(1)
end
print("profiles: all passed")
