local _, ns = ...

-- The addon's own ring, built like Forever's main menu ring and with the same art. Forever's ring
-- cannot take addon entries: an addon entry taints it, and closing it then blocks Forever's interact
-- button. This ring is a plain frame of the addon's own, so nothing of Forever's is touched.
--
-- It opens with R1 + R3, or another button set to it in the Input tab. Start cannot be used:
-- Forever takes Start and Back before any addon binding. The highlight follows the right stick
-- over every segment, empty ones too, and stays where the stick left it. Nothing runs until A
-- is pressed. While the ring is open: A uses the highlighted entry, B closes, L1 / R1 and D-pad
-- left / right change page, D-pad up shows the emotes and D-pad down sits or stands. Those keys
-- are bound through the secure driver (fc-ring), so they also work in combat.
--
-- It starts with Forever's three main menu pages and their entries; every segment and page can be
-- changed, and Reset in the settings brings them back.
--
-- Forever's entries open through a secure click on Forever's own buttons (the micro menu buttons,
-- the bag button, the clock), set on the A button while the highlight moves. Addon code never opens
-- those windows itself, so nothing is tainted. The click can't change in combat, so there those
-- entries are greyed out; entries that are plain addon calls still work.

local SEGMENTS = 8
local SEGMENT_ANGLE = 360 / SEGMENTS
local RADIUS = 150 -- from the middle of the wheel to the middle of a segment, as in Forever's ring
local ICON_INSET = 20 -- icons sit this much closer to the middle than their segment
local SELECT_SQ = 0.11 -- push the stick past this (squared, about a third of the way) to point at a segment
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local MAX_DOTS = 12

local function Label(global, fallback)
	local text = _G[global]
	return type(text) == "string" and text or fallback
end

-- Forever's entries, by the names Forever uses for them. `click` is the frame A clicks; `run` is
-- an ordinary addon call that is safe from addon code.
local BUILTINS = {
	bags = { label = Label("RADIAL_LABEL_BAGS", "Bags"), atlas = "gamepad-radial-icon-bags", click = "MainMenuBarBackpackButton" },
	calendar = { label = Label("RADIAL_LABEL_CALENDAR", "Calendar"), atlas = "gamepad-radial-icon-calendar", click = "GameTimeFrame" },
	character = { label = Label("RADIAL_LABEL_CHARACTER", "Character"), atlas = "gamepad-radial-icon-character", click = "CharacterMicroButton" },
	collections = { label = Label("RADIAL_LABEL_COLLECTIONS", "Collections"), atlas = "gamepad-radial-icon-collections", click = "CollectionsMicroButton" },
	guild = { label = Label("RADIAL_LABEL_GUILD", "Guild & Communities"), atlas = "gamepad-radial-icon-communities", click = "GuildMicroButton" },
	legacy = { label = Label("RADIAL_LABEL_LEGACY", "Legacy"), atlas = "gamepad-radial-icon-legacy", click = "LegacyMicroButton" },
	lfd = { label = Label("RADIAL_LABEL_GROUP_FINDER", "Group Finder"), atlas = "gamepad-radial-icon-groupfinder", click = "LFDMicroButton" },
	map = { label = Label("RADIAL_LABEL_QUEST_MAPS", "Quest & Maps"), atlas = "gamepad-radial-icon-quests", click = "QuestLogMicroButton" },
	-- The Game Menu button only opens under the mouse, so A takes the game's own key binding instead.
	menu = { label = Label("RADIAL_LABEL_GAME_MENU", "Game Menu"), atlas = "gamepad-radial-icon-gamemenu", binding = "TOGGLEGAMEMENU" },
	professions = { label = Label("RADIAL_LABEL_PROFESSIONS", "Professions"), atlas = "gamepad-radial-icon-professions", click = "ProfessionMicroButton" },
	pvp = { label = Label("RADIAL_LABEL_PVP", "PvP"), atlas = "Crosshair_PVP_128", run = function() C_PvP.TogglePVP() end },
	social = { label = Label("RADIAL_LABEL_SOCIAL", "Social"), atlas = "gamepad-radial-icon-social", click = { "QuickJoinToastButton", "FriendsMicroButton" } },
	spellbook = { label = Label("RADIAL_LABEL_SPELLBOOK", "Spellbook"), atlas = "gamepad-radial-icon-spellbook", click = "SpellbookMicroButton" },
	store = { label = Label("RADIAL_LABEL_SHOP", "Shop"), atlas = "gamepad-radial-icon-shop", click = "StoreMicroButton" },
	talents = { label = Label("RADIAL_LABEL_TALENTS", "Talents"), atlas = "gamepad-radial-icon-talents", click = "TalentMicroButton" },
	time = { label = Label("RADIAL_LABEL_CLOCK", "Clock"), atlas = "gamepad-radial-icon-stopwatch", click = "TimeManagerClockButton" },
	tracking = { label = Label("RADIAL_LABEL_TRACKING", "Tracking"), atlas = "gamepad-radial-icon-minimapsettings",
		run = function() MinimapCluster.Tracking.Button:OpenMenu() end },
	gxiv = { label = "Gamepad XIV", icon = ns.ICON, run = function() ns.OpenConfig() end },
}
ns.RING_BUILTINS = BUILTINS

-- The order the built-in entries are offered in when adding one.
ns.RING_BUILTIN_ORDER = {
	"character", "bags", "spellbook", "talents", "professions", "map", "collections", "lfd", "guild", "social",
	"menu", "calendar", "time", "tracking", "pvp", "store", "legacy", "gxiv",
}

-- Forever's three main menu pages, counter-clockwise from east. Forever's Chat and Buffs entries
-- focus a frame for the controller, which addon code can't do without tainting it, so those
-- segments are free here. The settings entry takes a free segment of the third page.
local DEFAULT_PAGES = {
	{ "lfd", "legacy", { toybox = true }, "guild", "social", false, "tracking", "collections" },
	{ "bags", "professions", "character", "talents", "map", false, "menu", "spellbook" },
	{ "time", "calendar", "gxiv", false, "pvp", false, false, false },
}
ns.RING_DEFAULT_PAGES = #DEFAULT_PAGES
local START_PAGE = 2 -- the middle page, as in Forever's ring
local MAIN_MENU = "Main Menu"

local EMOTES = {
	{ "Dance", "RADIAL_LABEL_DANCE" }, { "Point", "RADIAL_LABEL_POINT" }, { "Wave", "RADIAL_LABEL_WAVE" },
	{ "Kneel", "RADIAL_LABEL_KNEEL" }, { "Train", "RADIAL_LABEL_TRAIN" }, { "Chicken", "RADIAL_LABEL_CHICKEN" },
	{ "Angry", "RADIAL_LABEL_ANGRY" }, { "Cheer", "RADIAL_LABEL_CHEER" },
}

local LABEL_OFFSETS = { -- where each segment's label sits from its icon, from Forever's ring
	{ 60, 0 }, { 30, 45 }, { 0, 60 }, { -30, 45 }, { -60, 0 }, { -30, -45 }, { 0, -60 }, { 30, -45 },
}

-- Where a built-in entry is: its page, the page the ring opens on, and its segment (1 is right, then
-- counter-clockwise). Nothing when it isn't on the ring.
function ns.RingFindBuiltin(name)
	local saved = ns.RingPages()
	for index, savedPage in ipairs(saved) do
		for segment = 1, SEGMENTS do
			local entry = savedPage.slots[segment]
			if entry and entry.builtin == name then
				return index, math.min(START_PAGE, #saved), segment
			end
		end
	end
end

function ns.RingSlotFree(pageIndex, segment)
	return not ns.db.ringPages[pageIndex].slots[segment]
end

-- Saved pages: ns.db.ringPages[n].slots[segment] holds every entry, such as { builtin = "character" },
-- { addon, launcher }, { spell }, { item }, { macro }, { toy } or { label, command, icon }. All of it
-- can be changed. The first time, Forever's three main menu pages are put in; pages without a name
-- of their own show as Forever's "Main Menu". There is always at least one page.
function ns.RingPages()
	local saved = ns.db.ringPages
	if not ns.db.ringSeeded then
		for index, default in ipairs(DEFAULT_PAGES) do
			saved[index] = saved[index] or {}
			saved[index].slots = saved[index].slots or {}
			for segment = 1, SEGMENTS do
				local entry = default[segment]
				if entry and saved[index].slots[segment] == nil then
					saved[index].slots[segment] = type(entry) == "table" and CopyTable(entry) or { builtin = entry }
				end
			end
		end
		ns.db.ringSeeded = true
	end
	if #saved == 0 then
		saved[1] = { slots = {} }
	end
	for index = 1, #saved do
		saved[index].slots = saved[index].slots or {}
	end
	-- Entries from before pages: into the free segments, then onto new pages.
	local old = ns.db.ringEntries
	if old and #old > 0 then
		for _, entry in ipairs(old) do
			local copy = { label = entry.label, command = entry.command, icon = entry.icon }
			local placed = false
			for index = 1, #saved do
				for segment = 1, SEGMENTS do
					if not placed and ns.RingSlotFree(index, segment) then
						saved[index].slots[segment] = copy
						placed = true
					end
				end
			end
			if not placed then
				tinsert(saved, { name = "Menu " .. (#saved + 1), slots = { copy } })
			end
		end
		wipe(old)
	end
	return saved
end

function ns.RingPageName(pageIndex)
	return ns.db.ringPages[pageIndex].name or format("%s %d", MAIN_MENU, pageIndex)
end

-- Back to Forever's three pages, as on the first day.
function ns.RingReset()
	wipe(ns.db.ringPages)
	ns.db.ringSeeded = false
	ns.RingPages()
end

local function FindSlashHandler(command)
	command = command:lower()
	for key, handler in pairs(SlashCmdList) do
		local index = 1
		local name = _G["SLASH_" .. key .. index]
		while name do
			if name:lower() == command then
				return handler
			end
			index = index + 1
			name = _G["SLASH_" .. key .. index]
		end
	end
end

-- Runs a slash command the way typing it would, for the commands addons register. The game's own
-- protected commands, such as /cast, cannot be run this way.
function ns.RunSlashCommand(text)
	local command, rest = strtrim(text or ""):match("^(/%S+)%s*(.*)$")
	if not command then
		ns.Print("Not a slash command:", text)
		return
	end
	local handler = FindSlashHandler(command)
	if not handler then
		ns.Print("No addon answers to", command .. ". Check that the addon is enabled.")
		return
	end
	handler(rest, DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox)
end

-- Installed addons and how each opens, for the add window. Built when asked, since addons set up
-- their launchers during login. Each addon appears once, by the first of:
--   a LibDataBroker launcher (what minimap buttons and broker bars click),
--   the game's addon compartment (the addon list button by the minimap), when the client has it,
--   a slash command the addon registered (the game's own, secure, commands are left out).
-- Returns { { label, icon, data = saved entry, detail = text under the name } }, sorted by name.
local function AddOnTitle(name)
	local getInfo = C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo
	local _, title = getInfo(name)
	title = title and title:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	return (title and title ~= "") and title or name
end

local function AddOnIcon(name)
	local getMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
	local icon = getMetadata and getMetadata(name, "IconTexture")
	return icon and icon ~= "" and icon or nil
end

local function LoadedAddOns()
	local count = (C_AddOns and C_AddOns.GetNumAddOns or GetNumAddOns)()
	local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
	local getInfo = C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo
	local list = {}
	for index = 1, count do
		local name = getInfo(index)
		if name and isLoaded(name) and name ~= "GamepadXIV" and not name:match("^Blizzard_") then
			tinsert(list, name)
		end
	end
	return list
end

local function GetBroker()
	return LibStub and LibStub("LibDataBroker-1.1", true)
end

-- Which loaded addon a name belongs to, by matching it against the addon names.
local function MatchAddOn(text, addons)
	text = text:lower():gsub("[^%w]", "")
	if text == "" then
		return nil
	end
	for _, name in ipairs(addons) do
		local simple = name:lower():gsub("[^%w]", "")
		if simple == text or simple:find(text, 1, true) == 1 or text:find(simple, 1, true) == 1 then
			return name
		end
	end
end

function ns.RingAddOnChoices()
	local addons = LoadedAddOns()
	local loaded = {}
	for _, name in ipairs(addons) do
		loaded[name] = true
	end
	local found, choices = {}, {}
	local function Add(addon, label, icon, data, detail)
		if not addon or found[addon] then
			return
		end
		found[addon] = true
		tinsert(choices, { label = label, icon = icon or AddOnIcon(addon), data = data, detail = detail })
	end

	local broker = GetBroker()
	if broker then
		for name, object in broker:DataObjectIterator() do
			if type(object.OnClick) == "function" then
				local addon = loaded[name] and name or MatchAddOn(name, addons) or name
				Add(addon, loaded[addon] and AddOnTitle(addon) or (object.label or name), object.icon,
					{ addon = addon, launcher = name }, "Addon")
			end
		end
	end

	local compartment = AddonCompartmentFrame and AddonCompartmentFrame.registeredAddons
	if type(compartment) == "table" then
		for _, info in ipairs(compartment) do
			local addon = info.addon or (info.text and MatchAddOn(info.text, addons))
			if addon and loaded[addon] and (info.func or info.funcOnEnter) then
				Add(addon, AddOnTitle(addon), info.icon, { addon = addon, compartment = true }, "Addon")
			end
		end
	end

	for key in pairs(SlashCmdList) do
		local command = _G["SLASH_" .. key .. "1"]
		local secure, owner = issecurevariable(SlashCmdList, key)
		if command and not secure then
			local addon = (owner and loaded[owner] and owner) or MatchAddOn(key, addons) or MatchAddOn(command, addons)
			if addon and addon ~= "GamepadXIV" then
				Add(addon, AddOnTitle(addon), nil, { addon = addon, command = command:lower() }, command:lower())
			end
		end
	end

	table.sort(choices, function(a, b) return a.label:lower() < b.label:lower() end)
	return choices
end

-- The toys the player has, for the add window: { { label, icon, data = { toy = itemID } } }, sorted
-- by name. The game only lists toys through the Toy Box's filters, so they are opened up for the
-- count and then put back as the player left them.
local function ToyName(itemID)
	local _, name, icon = C_ToyBox.GetToyInfo(itemID)
	if not name and C_Item and C_Item.GetItemNameByID then
		name = C_Item.GetItemNameByID(itemID)
	end
	return name, icon
end

function ns.RingToyChoices()
	local box = C_ToyBox
	if not (box and box.GetNumFilteredToys and box.GetToyFromIndex and box.GetToyInfo and PlayerHasToy) then
		return {}
	end
	local ok, toys = pcall(function()
		local saved = {
			collected = box.GetCollectedShown and box.GetCollectedShown(),
			uncollected = box.GetUncollectedShown and box.GetUncollectedShown(),
			unusable = box.GetUnusableShown and box.GetUnusableShown(),
			sources = {}, expansions = {},
		}
		local sourceCount = C_PetJournal and C_PetJournal.GetNumPetSources and C_PetJournal.GetNumPetSources() or 0
		local expansionCount = GetNumExpansions and GetNumExpansions() or 0
		if box.IsSourceTypeFilterChecked then
			for i = 1, sourceCount do
				saved.sources[i] = box.IsSourceTypeFilterChecked(i)
			end
		end
		if box.IsExpansionTypeFilterChecked then
			for i = 1, expansionCount do
				saved.expansions[i] = box.IsExpansionTypeFilterChecked(i)
			end
		end
		local function Set(name, ...)
			if box[name] then
				box[name](...)
			end
		end
		Set("SetCollectedShown", true)
		Set("SetUncollectedShown", false)
		Set("SetUnusableShown", true)
		Set("SetAllSourceTypeFilters", true)
		Set("SetAllExpansionTypeFilters", true)
		Set("SetFilterString", "")

		local list = {}
		for index = 1, box.GetNumFilteredToys() do
			local itemID = box.GetToyFromIndex(index)
			if itemID and itemID > 0 and PlayerHasToy(itemID) then
				local name, icon = ToyName(itemID)
				tinsert(list, { label = name or ("Toy " .. itemID), icon = icon, data = { toy = itemID }, detail = "Toy" })
			end
		end

		if saved.collected ~= nil then Set("SetCollectedShown", saved.collected) end
		if saved.uncollected ~= nil then Set("SetUncollectedShown", saved.uncollected) end
		if saved.unusable ~= nil then Set("SetUnusableShown", saved.unusable) end
		for i, checked in pairs(saved.sources) do
			Set("SetSourceTypeFilter", i, checked)
		end
		for i, checked in pairs(saved.expansions) do
			Set("SetExpansionTypeFilter", i, checked)
		end
		Set("SetFilterString", ToyBox and ToyBox.searchString or "")
		return list
	end)
	if not ok then
		return {}
	end
	table.sort(toys, function(a, b) return a.label:lower() < b.label:lower() end)
	return toys
end

-- Every emote: { { token, label } }, Forever's eight first, then the game's list A to Z. The game
-- keeps it as EMOTE<n>_TOKEN with its slash command EMOTE<n>_CMD1, with gaps.
local emoteList, emoteLabels
function ns.RingEmoteList()
	if emoteList then
		return emoteList
	end
	emoteList, emoteLabels = {}, {}
	local seen = {}
	for _, emote in ipairs(EMOTES) do
		tinsert(emoteList, { token = emote[1], label = Label(emote[2], emote[1]) })
		seen[emote[1]:upper()] = true
	end
	local more = {}
	for index = 1, (MAXEMOTEINDEX or 0) + 200 do
		local token = _G["EMOTE" .. index .. "_TOKEN"]
		local command = _G["EMOTE" .. index .. "_CMD1"]
		if type(token) == "string" and type(command) == "string" and not seen[token:upper()] then
			seen[token:upper()] = true
			local name = command:gsub("^/", "")
			tinsert(more, { token = token, label = name:sub(1, 1):upper() .. name:sub(2) })
		end
	end
	table.sort(more, function(a, b) return a.label:lower() < b.label:lower() end)
	for _, emote in ipairs(more) do
		tinsert(emoteList, emote)
	end
	for _, emote in ipairs(emoteList) do
		emoteLabels[emote.token:upper()] = emote.label
	end
	return emoteList
end

-- For the add window: { { label, icon, data = { emote = token } } }.
function ns.RingEmoteChoices()
	local list = {}
	for _, emote in ipairs(ns.RingEmoteList()) do
		tinsert(list, { label = emote.label, icon = 3750314, data = { emote = emote.token }, detail = "Emote" })
	end
	return list
end

-- The character's abilities, in spellbook order: { { label, icon, data = { spell = spellID }, detail =
-- the spellbook tab } }. Passive and not yet learned spells are left out. Cast by name, so always the
-- highest rank known.
function ns.RingSpellChoices()
	local list, seen = {}, {}
	local function Add(spellID, name, icon, tab)
		if spellID and name and not seen[name] then
			seen[name] = true
			tinsert(list, { label = name, icon = icon, data = { spell = spellID }, detail = tab })
		end
	end
	local book = C_SpellBook
	if book and book.GetNumSpellBookSkillLines and book.GetSpellBookItemInfo then
		local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
		for line = 1, book.GetNumSpellBookSkillLines() do
			local info = book.GetSpellBookSkillLineInfo(line)
			if info and not info.shouldHide then
				for index = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
					local item = book.GetSpellBookItemInfo(index, bank)
					if item and not item.isPassive and item.itemType == Enum.SpellBookItemType.Spell then
						Add(item.spellID or item.actionID, item.name, item.iconID, info.name)
					end
				end
			end
		end
	elseif GetNumSpellTabs and GetSpellBookItemInfo then
		for tab = 1, GetNumSpellTabs() do
			local tabName, _, offset, count = GetSpellTabInfo(tab)
			for index = offset + 1, offset + count do
				local kind, spellID = GetSpellBookItemInfo(index, BOOKTYPE_SPELL or "spell")
				if kind == "SPELL" and not (IsPassiveSpell and IsPassiveSpell(index, BOOKTYPE_SPELL or "spell")) then
					local name = GetSpellBookItemName(index, BOOKTYPE_SPELL or "spell")
					Add(spellID, name, GetSpellBookItemTexture(index, BOOKTYPE_SPELL or "spell"), tabName)
				end
			end
		end
	end
	return list
end

local function ItemNameAndIcon(itemID)
	local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID) or (GetItemInfo and GetItemInfo(itemID))
	local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID) or (GetItemIcon and GetItemIcon(itemID))
	return name, icon
end

local function ItemHasUse(itemID)
	local getSpell = C_Item and C_Item.GetItemSpell or GetItemSpell
	return getSpell and getSpell(itemID) and true or false
end

-- The items in the bags, each once: { { label, icon, data = { item = itemID }, detail } }. Items
-- with a use come first; gear is put on, like a click on it in the bags.
function ns.RingItemChoices()
	local list, seen = {}, {}
	local container = C_Container
	local numSlots = container and container.GetContainerNumSlots or GetContainerNumSlots
	local getInfo = container and container.GetContainerItemInfo
	for bag = 0, NUM_BAG_SLOTS or 4 do
		for slot = 1, numSlots(bag) or 0 do
			local itemID, icon, link
			if getInfo then
				local info = getInfo(bag, slot)
				itemID, icon, link = info and info.itemID, info and info.iconFileID, info and info.hyperlink
			elseif GetContainerItemInfo then
				local texture, _, _, _, _, _, itemLink, _, _, id = GetContainerItemInfo(bag, slot)
				itemID, icon, link = id, texture, itemLink
			end
			if itemID and not seen[itemID] then
				seen[itemID] = true
				local name = (link and link:match("%[(.-)%]")) or ItemNameAndIcon(itemID) or ("Item " .. itemID)
				local use = ItemHasUse(itemID)
				tinsert(list, { label = name, icon = icon, data = { item = itemID }, detail = use and "Use" or "Item", use = use })
			end
		end
	end
	table.sort(list, function(a, b)
		if (a.use or false) ~= (b.use or false) then
			return a.use or false
		end
		return a.label:lower() < b.label:lower()
	end)
	return list
end

-- The Equipment Manager's sets: { { label, icon, data = { equipset = name } } }. Saved by name and
-- put on with /equipset, as the Equipment Manager's own button does.
function ns.RingEquipmentSetChoices()
	local list = {}
	local sets = C_EquipmentSet
	if not (sets and sets.GetEquipmentSetIDs and sets.GetEquipmentSetInfo) then
		return list
	end
	for _, setID in ipairs(sets.GetEquipmentSetIDs()) do
		local name, icon, _, isEquipped = sets.GetEquipmentSetInfo(setID)
		if name then
			tinsert(list, { label = name, icon = icon, data = { equipset = name }, detail = isEquipped and "Equipment set, worn now" or "Equipment set" })
		end
	end
	table.sort(list, function(a, b) return a.label:lower() < b.label:lower() end)
	return list
end

-- The player's macros, account-wide first, then this character's: { { label, icon, data = { macro =
-- name } } }. Saved by name, so editing a macro keeps its place on the ring.
function ns.RingMacroChoices()
	local list = {}
	if not (GetNumMacros and GetMacroInfo) then
		return list
	end
	local global, perCharacter = GetNumMacros()
	local perAccount = MAX_ACCOUNT_MACROS or 120
	local function Add(index, detail)
		local name, icon = GetMacroInfo(index)
		if name then
			tinsert(list, { label = name, icon = icon, data = { macro = name }, detail = detail })
		end
	end
	for index = 1, global do
		Add(index, "Account macro")
	end
	for index = perAccount + 1, perAccount + perCharacter do
		Add(index, "Character macro")
	end
	return list
end

-- Opens an addon the way its minimap or compartment button does. Launchers anchor menus and tooltips
-- to the frame they get, so they get a real (hidden) one. A broken addon only prints a line.
local launchAnchor
local function RunAddOn(data)
	launchAnchor = launchAnchor or CreateFrame("Frame", "GamepadXIVRingLaunchAnchor", UIParent)
	launchAnchor:ClearAllPoints()
	launchAnchor:SetPoint("CENTER")
	launchAnchor:SetSize(1, 1)
	local ok, err = true, nil
	if data.launcher then
		local broker = GetBroker()
		local object = broker and broker:GetDataObjectByName(data.launcher)
		if object and object.OnClick then
			ok, err = pcall(object.OnClick, launchAnchor, "LeftButton")
		else
			ok, err = false, "it is not loaded"
		end
	elseif data.compartment then
		local info
		for _, entry in ipairs(AddonCompartmentFrame and AddonCompartmentFrame.registeredAddons or {}) do
			if entry.addon == data.addon then
				info = entry
			end
		end
		if info and info.func then
			ok, err = pcall(info.func, data.addon, "LeftButton", launchAnchor)
		else
			ok, err = false, "it is not loaded"
		end
	end
	if not ok then
		ns.Print("Couldn't open", data.addon .. ":", tostring(err))
	end
end

local function ClickFrame(click)
	if type(click) == "table" then
		for _, name in ipairs(click) do
			if _G[name] then
				return _G[name]
			end
		end
		return nil
	end
	return click and _G[click]
end

-- What a saved or built-in entry does, ready for the ring:
-- { label, icon or atlas, click = frame, macro = text, run = function }.
function ns.RingResolve(data)
	if type(data) == "string" then
		data = { builtin = data }
	end
	if data.builtin then
		local builtin = BUILTINS[data.builtin]
		if not builtin then
			return nil
		end
		local entry = { label = builtin.label, atlas = builtin.atlas, icon = builtin.icon, run = builtin.run, binding = builtin.binding }
		if builtin.click then
			entry.click = ClickFrame(builtin.click)
			if not entry.click then
				return nil -- this client has no such button
			end
		end
		return entry
	end
	-- An ability, a bag item or a macro: through the game's secure actions, like an action button.
	-- One that is gone (an unlearned spell, an item no longer in the bags, a deleted macro) stays,
	-- greyed out.
	if data.spell then
		local name, icon
		if ns.SpellNameAndIcon then
			name, icon = ns.SpellNameAndIcon(data.spell)
		end
		return { label = name or ("Spell " .. data.spell), icon = icon or DEFAULT_ICON, spell = name, missing = not name or nil }
	end
	if data.item then
		local name, icon = ItemNameAndIcon(data.item)
		local count = (C_Item and C_Item.GetItemCount or GetItemCount)(data.item)
		return { label = name or ("Item " .. data.item), icon = icon or DEFAULT_ICON, item = "item:" .. data.item,
			missing = ((count or 0) == 0 and not (C_Item and C_Item.IsEquippedItem or IsEquippedItem or function() end)(data.item)) or nil }
	end
	if data.equipset then
		local setID = C_EquipmentSet and C_EquipmentSet.GetEquipmentSetID and C_EquipmentSet.GetEquipmentSetID(data.equipset)
		local icon = setID and select(2, C_EquipmentSet.GetEquipmentSetInfo(setID))
		return { label = data.equipset, icon = icon or DEFAULT_ICON, macro = "/equipset " .. data.equipset, missing = not setID or nil }
	end
	if data.macro then
		local index = GetMacroIndexByName and GetMacroIndexByName(data.macro) or 0
		local icon = index > 0 and select(2, GetMacroInfo(index)) or nil
		return { label = data.macro, icon = icon or DEFAULT_ICON, macroName = data.macro, missing = index == 0 or nil }
	end
	-- An emote, done like the emote pages do it; it works in combat too.
	if data.emote then
		ns.RingEmoteList()
		local token = data.emote
		return {
			label = emoteLabels[token:upper()] or token,
			icon = 3750314,
			run = function()
				if C_ChatInfo.PerformEmote then
					C_ChatInfo.PerformEmote(token)
				else
					DoEmote(token:upper())
				end
			end,
		}
	end
	-- The Toy Box: opens every toy on the ring, 8 a page. Toys can't be used in combat.
	if data.toybox then
		return { label = Label("TOY_BOX", "Toy Box"), icon = "Interface\\Icons\\INV_Misc_Toy_10", toybox = true }
	end
	-- A toy: used through the game's secure toy action, like a toy button. One the player no longer
	-- has stays, greyed out.
	if data.toy then
		local name, icon
		if C_ToyBox and C_ToyBox.GetToyInfo then
			name, icon = ToyName(data.toy)
		end
		return { label = name or ("Toy " .. data.toy), icon = icon or DEFAULT_ICON, toy = data.toy,
			missing = not (PlayerHasToy and PlayerHasToy(data.toy)) or nil }
	end
	-- An addon picked from the list: its launcher, compartment entry or slash command.
	if data.addon then
		local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
		local broker = data.launcher and GetBroker()
		local object = broker and broker:GetDataObjectByName(data.launcher)
		local addonLoaded = isLoaded(data.addon) and true or false
		-- An addon that was turned off keeps its place, greyed out, until it is back or removed.
		local entry = {
			label = addonLoaded and AddOnTitle(data.addon) or (object and object.label) or data.addon,
			missing = not (addonLoaded or object) or nil,
		}
		entry.icon = (object and object.icon) or (addonLoaded and AddOnIcon(data.addon)) or DEFAULT_ICON
		if data.launcher or data.compartment then
			entry.run = function() RunAddOn(data) end
		elseif data.command then
			entry.macro = data.command
			entry.run = function() ns.RunSlashCommand(data.command) end
		end
		return entry
	end
	local command = data.command
	local icon = tonumber(data.icon) or data.icon
	return {
		label = data.label,
		icon = (icon ~= nil and icon ~= "") and icon or DEFAULT_ICON,
		-- Out of combat the command runs as a macro, so the game's own commands work too.
		macro = command,
		run = function() ns.RunSlashCommand(command) end,
	}
end

-- Draws an entry's icon: Forever's atlases, or a texture or file ID.
function ns.RingSetIcon(texture, entry, size)
	if entry.atlas and C_Texture.GetAtlasInfo(entry.atlas) then
		texture:SetAtlas(entry.atlas)
		texture:SetSize(size * 1.3, size * 1.3)
	else
		texture:SetTexture(entry.icon or DEFAULT_ICON)
		texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		texture:SetSize(size, size)
	end
end

local ring
local pages = {} -- the built pages: { header, entries = { [segment] = entry } }
local page, selected = START_PAGE, 0

-- For the tutorial: the main page shown and the highlighted segment, while the ring is open. Read only.
function ns.RingSelection()
	if ring and ring:IsShown() and not ring.sub then
		return page, selected
	end
end

local emotePages -- every emote, 8 a page: Forever's eight first, then the game's whole list A to Z

local function BuildPages()
	wipe(pages)
	for index, savedPage in ipairs(ns.RingPages()) do
		local entries = {}
		for segment = 1, SEGMENTS do
			local data = savedPage.slots[segment]
			entries[segment] = data and ns.RingResolve(data) or nil
		end
		pages[index] = { header = savedPage.name or MAIN_MENU, entries = entries }
	end
	if not emotePages then
		local list = {}
		for _, emote in ipairs(ns.RingEmoteList()) do
			tinsert(list, ns.RingResolve({ emote = emote.token }))
		end
		emotePages = {}
		for index, emote in ipairs(list) do
			local pageIndex = math.floor((index - 1) / SEGMENTS) + 1
			emotePages[pageIndex] = emotePages[pageIndex] or { header = Label("RADIAL_LABEL_TARGET_EMOTES", "Emotes"), entries = {} }
			emotePages[pageIndex].entries[(index - 1) % SEGMENTS + 1] = emote
		end
	end
end

-- ring.sub: pages shown in place of the main menu (the emotes, the Toy Box): { pages, index }.
local function CurrentPage()
	if ring.sub then
		return ring.sub.pages[ring.sub.index]
	end
	return pages[page]
end

local function OpenToyBox()
	local list = ns.RingToyChoices()
	local toyPages = {}
	for index, toy in ipairs(list) do
		local pageIndex = math.floor((index - 1) / SEGMENTS) + 1
		toyPages[pageIndex] = toyPages[pageIndex] or { header = Label("TOY_BOX", "Toy Box"), entries = {} }
		toyPages[pageIndex].entries[(index - 1) % SEGMENTS + 1] = ns.RingResolve(toy.data)
	end
	if #toyPages == 0 then
		toyPages[1] = { header = Label("TOY_BOX", "Toy Box"), entries = {} }
	end
	ring.sub = { pages = toyPages, index = 1 }
end

-- What A does with an entry in combat, set up beforehand: a secure action, with Forever's buttons
-- clicked through a macro. Nil for what can't be used in combat (the Game Menu, the Toy Box).
local COMBAT_FIELDS = { "type", "macro", "macrotext", "spell", "item", "toy" }
local function CombatAction(entry)
	if not entry or entry.missing or entry.toybox or entry.binding then
		return nil
	elseif entry.click then
		local name = entry.click.GetName and entry.click:GetName()
		return name and { type = "macro", macrotext = "/click " .. name } or nil
	elseif entry.macro then
		return { type = "macro", macrotext = entry.macro }
	elseif entry.macroName then
		return { type = "macro", macro = entry.macroName }
	elseif entry.spell then
		return { type = "spell", spell = entry.spell }
	elseif entry.item then
		return { type = "item", item = entry.item }
	elseif entry.toy then
		return { type = "toy", toy = entry.toy }
	end
	return nil
end

-- In combat A reads which segment from the stick directions the game reports as held, which takes
-- its stick axis buttons setting.
local function StickKeysOn()
	return ns.RingHeldSegment and C_CVar and C_CVar.GetCVarBool and C_CVar.GetCVarBool("GamePadStickAxisButtons") and true or false
end

-- In combat only the main menu pages were set up, not the emotes or the toy pages.
local function Usable(entry)
	if not entry or entry.missing then
		return false
	elseif not InCombatLockdown() or entry.run then
		return true
	end
	return not ring.sub and StickKeysOn() and CombatAction(entry) ~= nil
end

-- A can't be pointed at an entry in combat, so every segment of every page is set up on it before:
-- "p<page>s<segment>-type" and the rest, which the secure side copies over when A is pressed in combat.
local armedPages = 0
function ns.RingArmCombat()
	local pick = ns.ringPickButton
	if not pick or InCombatLockdown() then
		return
	end
	if not (ring and ring:IsShown()) then
		BuildPages()
	end
	for pageIndex = 1, math.max(#pages, armedPages) do
		for segment = 1, SEGMENTS do
			local action = pages[pageIndex] and CombatAction(pages[pageIndex].entries[segment])
			local prefix = "p" .. pageIndex .. "s" .. segment .. "-"
			for _, field in ipairs(COMBAT_FIELDS) do
				pick:SetAttribute(prefix .. field, action and action[field] or nil)
			end
		end
	end
	armedPages = #pages
	if ns.SetRingPages then
		-- An open ring also hands over the page it is on, which may have changed with the pages.
		local current = ring and ring:IsShown() and not ring.sub and page or nil
		ns.SetRingPages(math.max(1, math.min(START_PAGE, #pages)), #pages, current)
	end
end

-- Sets one pick button to the entry: a click on Forever's button, a secure action, or nothing (the
-- addon then runs the entry itself).
local function ArmButton(button, entry, clickOverride)
	-- A macro by name wins over macro text, so only one of the two is ever set.
	button:SetAttribute("macro", nil)
	button:SetAttribute("macrotext", nil)
	if clickOverride then
		button:SetAttribute("fc-keep", 0)
		button:SetAttribute("type", "click")
		button:SetAttribute("clickbutton", clickOverride)
		return
	end
	-- The Toy Box keeps the ring open: A turns to the toy pages instead of closing it. An entry that is
	-- a key binding (the Game Menu) is opened by A itself; letting go of the stick leaves it highlighted.
	button:SetAttribute("fc-keep", entry and (entry.toybox or entry.binding) and 1 or 0)
	if entry and (entry.toybox or entry.binding) then
		button:SetAttribute("type", nil)
	elseif entry and entry.click then
		button:SetAttribute("type", "click")
		button:SetAttribute("clickbutton", entry.click)
	elseif entry and entry.macro then
		button:SetAttribute("type", "macro")
		button:SetAttribute("macrotext", entry.macro)
	elseif entry and entry.macroName then
		button:SetAttribute("type", "macro")
		button:SetAttribute("macro", entry.macroName)
	elseif entry and entry.spell then
		button:SetAttribute("type", "spell")
		button:SetAttribute("spell", entry.spell)
	elseif entry and entry.item then
		button:SetAttribute("type", "item")
		button:SetAttribute("item", entry.item)
	elseif entry and entry.toy then
		button:SetAttribute("type", "toy")
		button:SetAttribute("toy", entry.toy)
	else
		button:SetAttribute("type", nil)
	end
end

-- Letting go of the stick on the Game Menu: Forever's Game Menu button only opens when the mouse is
-- over it, and a key binding can't run on a release. So while the Game Menu is highlighted, that
-- button is moved under the (hidden) mouse cursor, and letting go clicks it like Forever's other
-- buttons. It goes back as soon as the highlight moves on or the ring closes.
local menuButtonPoints
local function RestoreMenuButton()
	local button = MainMenuMicroButton
	if not menuButtonPoints or not button then
		return
	end
	button:ClearAllPoints()
	for _, point in ipairs(menuButtonPoints) do
		button:SetPoint(unpack(point))
	end
	menuButtonPoints = nil
end

local function MoveMenuButtonUnderCursor()
	local button = MainMenuMicroButton
	if not button or not GetCursorPosition then
		return false
	end
	if not menuButtonPoints then
		menuButtonPoints = {}
		for i = 1, button:GetNumPoints() do
			menuButtonPoints[i] = { button:GetPoint(i) }
		end
	end
	local x, y = GetCursorPosition()
	local scale = button:GetEffectiveScale()
	button:ClearAllPoints()
	button:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
	ns.RingLog("game menu button under the cursor:", button:IsMouseOver() and "yes" or "no", "shown:", button:IsVisible() and "yes" or "no")
	return true
end

-- Points A, and the right stick's release when that is on, at the highlighted entry. Out of combat
-- only: protected buttons can't change in combat.
local function ArmPick(entry)
	if InCombatLockdown() then
		return
	end
	if ns.ringPickButton then
		ArmButton(ns.ringPickButton, entry)
	end
	local underCursor = entry and entry.binding == "TOGGLEGAMEMENU" and ns.db.ringReleaseToUse
		and MoveMenuButtonUnderCursor() and MainMenuMicroButton or nil
	if not underCursor then
		RestoreMenuButton()
	end
	ns.menuUnderCursor = underCursor and true or nil
	for _, button in ipairs(ns.ringReleaseButtons or {}) do
		ArmButton(button, entry, underCursor)
	end
	if ns.SetRingPickBinding then
		ns.SetRingPickBinding(entry and entry.binding)
	end
end

local function SegmentPosition(index, distance)
	local radians = math.rad((index - 1) * SEGMENT_ANGLE)
	return distance * math.cos(radians), distance * math.sin(radians)
end

local function Select(index)
	if index == selected then
		return
	end
	selected = index
	local entry = index > 0 and CurrentPage().entries[index] or nil
	ArmPick(entry and not entry.missing and entry or nil)
	if index <= 0 then
		ring.highlight:Hide()
		ring.center:SetText("")
		return
	end
	-- Empty segments are highlighted too, greyed out, so the stick always shows where it points.
	local x, y = SegmentPosition(index, RADIUS)
	ring.highlight:ClearAllPoints()
	ring.highlight:SetPoint("CENTER", ring.background, "CENTER", x, y)
	ring.highlight:SetRotation(math.rad((index - 1) * SEGMENT_ANGLE - 270))
	ring.highlight:SetDesaturated(not Usable(entry))
	ring.highlight:SetAlpha(entry and 1 or 0.5)
	ring.highlight:Show()
	ring.center:SetText(entry and entry.label or "")
	PlaySound(SOUNDKIT.GAMEPAD_RADIAL_MENU_HIGHLIGHT)
end

local function ShowPage()
	selected = -1
	Select(0)
	local current = CurrentPage()
	for i, segment in ipairs(ring.segments) do
		local entry = current.entries[i]
		segment:SetShown(entry ~= nil)
		if entry then
			ns.RingSetIcon(segment.icon, entry, 38)
			local usable = Usable(entry) and not (entry.click and entry.click.IsEnabled and not entry.click:IsEnabled())
			segment.icon:SetDesaturated(not usable)
			segment.label:SetText(entry.label)
			segment.label:SetFontObject(usable and "GameFontNormal" or "GameFontDisable")
		end
	end
	ring.header:SetText(current.header)
	local pageCount = ring.sub and #ring.sub.pages or #pages
	local active = ring.sub and ring.sub.index or page
	local count = math.min(pageCount, MAX_DOTS)
	-- More pages than dots (the emotes): "3 / 40" between L1 and R1 instead.
	local showDots = pageCount > 1
	local useText = pageCount > MAX_DOTS
	ring.pageText:SetShown(useText)
	ring.pageText:SetText(active .. " / " .. pageCount)
	if useText then
		count = 3
	end
	for i = 1, MAX_DOTS do
		local dot = ring.dots[i]
		dot:SetShown(showDots and not useText and i <= count)
		dot:SetAtlas("gamepad-radialgamemenu-cursorbg-" .. (i == active and "neutral" or "inactive"))
		dot:ClearAllPoints()
		dot:SetPoint("CENTER", ring.dotBar, "CENTER", (i - (count + 1) / 2) * 22, 0)
	end
	local edge = (count + 1) / 2 * 22 + 4
	ring.pageLeft:SetShown(showDots)
	ring.pageRight:SetShown(showDots)
	ring.pageLeft:ClearAllPoints()
	ring.pageLeft:SetPoint("RIGHT", ring.dotBar, "CENTER", -edge, 0)
	ring.pageRight:ClearAllPoints()
	ring.pageRight:SetPoint("LEFT", ring.dotBar, "CENTER", edge, 0)
	ring.contextUp:SetText(ring.sub and MAIN_MENU or Label("RADIAL_LABEL_TARGET_EMOTES", "Emotes"))
end

local STICK_KEYS = { "PADRSTICKUP", "PADRSTICKDOWN", "PADRSTICKLEFT", "PADRSTICKRIGHT" }
local stickKeysWork = false

local function StickKeyDown()
	if not IsKeyDown then
		return false
	end
	for _, key in ipairs(STICK_KEYS) do
		if IsKeyDown(key) then
			return true
		end
	end
	return false
end

-- /gxiv ringlog: what the ring sees, saved to ringLog (the last 60 lines) while it is on.
function ns.RingLog(...)
	if not ns.db.ringLogOn then
		return
	end
	local parts = { date("%H:%M:%S") }
	for i = 1, select("#", ...) do
		parts[#parts + 1] = tostring((select(i, ...)))
	end
	ns.db.ringLog = ns.db.ringLog or {}
	tinsert(ns.db.ringLog, table.concat(parts, " "))
	while #ns.db.ringLog > 60 do
		tremove(ns.db.ringLog, 1)
	end
end

-- The stick's presses and releases as the release button gets them (after its secure handler).
local function HookReleaseLog()
	if ns.ringReleaseButtons and not ns.ringLogHooked then
		ns.ringLogHooked = true
		for _, release in ipairs(ns.ringReleaseButtons) do
			release:HookScript("OnClick", function(self, _, down)
				ns.RingLog("stick", self:GetAttribute("fc-dir"), down and "pressed" or "let go", "highlight", selected)
			end)
		end
	end
end

function ns.ToggleRingLog()
	ns.db.ringLogOn = not ns.db.ringLogOn
	if ns.db.ringLogOn then
		ns.db.ringLog = {}
		HookReleaseLog()
	end
	ns.Print("Ring log", ns.db.ringLogOn and "on: use the ring, then /reload and send the log." or "off.")
end

local SetHints
local function CreateRing()
	ring = CreateFrame("Frame", "GamepadXIVRing", UIParent)
	ring:SetSize(400, 640)
	ring:SetPoint("CENTER", 0, 10)
	ring:SetFrameStrata("DIALOG")
	ring:Hide()

	ring.background = ring:CreateTexture(nil, "BACKGROUND")
	ring.background:SetAtlas("gamepad-radial-menu-wheelbg", true)
	ring.background:SetPoint("CENTER", 0, 0)

	ring.highlight = ring:CreateTexture(nil, "BORDER")
	ring.highlight:SetAtlas("gamepad-radial-menu-selected", true)
	ring.highlight:Hide()

	-- The header and the page dots, between L1 and R1, like Forever's.
	ring.header = ring:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	ring.header:SetPoint("BOTTOM", ring.background, "TOP", 0, 78)
	ring.headerBack = ring:CreateTexture(nil, "BACKGROUND")
	ring.headerBack:SetAtlas("gamepad-radial-menu-toptext", true)
	ring.headerBack:SetPoint("TOP", ring.header, "BOTTOM", 0, 4)
	ring.dotBar = CreateFrame("Frame", nil, ring)
	ring.dotBar:SetSize(10, 24)
	ring.dotBar:SetPoint("TOP", ring.header, "BOTTOM", 0, -16)
	ring.dots = {}
	for i = 1, MAX_DOTS do
		local dot = ring.dotBar:CreateTexture(nil, "ARTWORK")
		dot:SetSize(16, 16)
		ring.dots[i] = dot
	end
	ring.pageText = ring.dotBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	ring.pageText:SetPoint("CENTER")
	ring.pageLeft = ring.dotBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	ring.pageRight = ring.dotBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")

	-- The name of the entry the stick points at, in the middle of the wheel.
	ring.center = ring:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	ring.center:SetPoint("CENTER", ring.background, "CENTER")
	ring.center:SetWidth(120)

	-- Under the wheel, like Forever's: a dark band with the D-pad in the middle, D-pad up (the
	-- emotes) above it and D-pad down (sit or stand) below. It sits over the crossbar, so it is
	-- drawn above it. Then A and B.
	ring.context = CreateFrame("Frame", nil, ring)
	ring.context:SetSize(400, 110)
	ring.context:SetPoint("TOP", ring.background, "BOTTOM", 0, 6)
	ring.context:SetFrameStrata("FULLSCREEN_DIALOG")
	ring.context.band = ring.context:CreateTexture(nil, "BACKGROUND")
	ring.context.band:SetAtlas("gamepad-radial-menu-bottomtext", true)
	ring.context.band:SetPoint("CENTER")
	ring.contextKeys = ring.context:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	ring.contextKeys:SetPoint("CENTER")
	ring.contextUp = ring.context:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	ring.contextUp:SetPoint("CENTER", 0, 30)
	ring.contextDown = ring.context:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	ring.contextDown:SetPoint("CENTER", 0, -30)
	ring.contextDown:SetText(Label("RADIAL_LABEL_TOGGLE_SIT", "Sit / Stand"))
	ring.hint = ring.context:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	ring.hint:SetPoint("TOP", ring.context, "BOTTOM", 0, -2)

	ring.segments = {}
	for i = 1, SEGMENTS do
		local segment = CreateFrame("Frame", nil, ring)
		segment:SetSize(60, 60)
		segment:SetPoint("CENTER", ring.background, "CENTER", SegmentPosition(i, RADIUS))
		segment.icon = segment:CreateTexture(nil, "ARTWORK")
		local dx, dy = SegmentPosition(i, -ICON_INSET)
		segment.icon:SetPoint("CENTER", dx, dy)
		segment.label = segment:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		segment.label:SetSize(80, 40)
		segment.label:SetWordWrap(true)
		segment.label:SetPoint("CENTER", segment.icon, "CENTER", LABEL_OFFSETS[i][1], LABEL_OFFSETS[i][2])
		ring.segments[i] = segment
	end

	-- The right stick, read every frame like Forever's ring: past SELECT_SQ it points at a segment.
	-- Letting it go keeps the highlight; A uses the entry.
	ring:SetScript("OnUpdate", function()
		-- In combat the highlight follows the held directions, as A does there: what is highlighted
		-- is what A uses, and letting go of the stick leaves nothing highlighted.
		if InCombatLockdown() and StickKeysOn() then
			local index = ns.RingHeldSegment()
			if index ~= selected then
				ns.RingLog("highlight in combat", index)
				Select(index)
			end
			return
		end
		local x, y = ns.GetRightStick()
		local pushed = x * x + y * y > SELECT_SQ
		-- With "use on letting go", the release only counts once the game takes the stick as a
		-- pressed direction, further out than the highlight. So the highlight waits for that too,
		-- and what is highlighted is always what letting go uses. It only waits once the game has
		-- shown it reports those directions as keys.
		local axisDown = StickKeyDown()
		if axisDown then
			stickKeysWork = true
		end
		if pushed and ns.db.ringReleaseToUse and stickKeysWork and not axisDown then
			pushed = false
		end
		if pushed then
			local degrees = math.deg(math.atan2(y, x))
			if degrees < -SEGMENT_ANGLE / 2 then
				degrees = degrees + 360
			end
			local index = math.floor((degrees + SEGMENT_ANGLE) / SEGMENT_ANGLE + 0.5)
			if index ~= selected then
				ns.RingLog("highlight", index, format("stick %.2f", math.sqrt(x * x + y * y)), "keys", axisDown and "down" or "up")
			end
			Select(index)
		end
	end)

	-- Entering or leaving combat greys Forever's entries out or back in.
	ring:RegisterEvent("PLAYER_REGEN_DISABLED")
	ring:RegisterEvent("PLAYER_REGEN_ENABLED")
	ring:SetScript("OnEvent", function(_, event)
		if ring:IsShown() then
			local keep = selected
			SetHints()
			ShowPage()
			Select(keep)
			-- Combat is starting, and bindings and the pick buttons can still change now. A highlighted
			-- Game Menu would leave A on its key binding for the whole fight, so A goes back to picking.
			if event == "PLAYER_REGEN_DISABLED" then
				if ns.SetRingPickBinding then
					ns.SetRingPickBinding(nil)
				end
				RestoreMenuButton()
				ns.menuUnderCursor = nil
				ns.RingArmCombat()
			end
		end
	end)
end

function SetHints()
	ring.pageLeft:SetText(ns.ButtonText("{PADLSHOULDER}", 22))
	ring.pageRight:SetText(ns.ButtonText("{PADRSHOULDER}", 22))
	-- The whole D-pad, as Forever shows it; the two buttons when the controller has no such icon.
	ring.contextKeys:SetText(ns.ButtonMarkup(GAMEPAD_DPAD or "DIRPAD", nil, 30) or ns.ButtonText("{PADDUP}{PADDDOWN}", 20))
	-- In combat letting go can't tell which segment it was, so A uses the entry there.
	if ns.db.ringReleaseToUse and not InCombatLockdown() then
		ring.hint:SetText(ns.ButtonText("Let go of the stick or {PAD1} to use    {PAD2} close", 20))
	else
		ring.hint:SetText(ns.ButtonText("{PAD1} use    {PAD2} close", 20))
	end
end

local function Close()
	if ring and ring:IsShown() then
		ring:Hide()
		PlaySound(SOUNDKIT.GAMEPAD_RADIAL_MENU_CLOSE)
	end
	ns.ringOpen = false
	ArmPick(nil)
	RestoreMenuButton() -- in combat too, where ArmPick does nothing
end

-- Called by the secure driver: "open", "close", "pick", "prev", "next" or "emotes".
function ns.OnRing(action)
	if action == "open" then
		if not ring then
			CreateRing()
		end
		if ns.db.ringLogOn then
			HookReleaseLog()
			ns.RingLog("open", "release on letting go:", ns.db.ringReleaseToUse and "yes" or "no", "stick keys seen:", stickKeysWork and "yes" or "no")
		end
		BuildPages()
		SetHints()
		page = math.min(START_PAGE, #pages)
		ring.sub = nil
		ShowPage()
		ns.ringOpen = true
		ring:Show()
		ns.RingArmCombat()
		PlaySound(SOUNDKIT.GAMEPAD_RADIAL_MENU_OPEN)
	elseif not (ring and ring:IsShown()) then
		ns.ringOpen = false
	elseif action == "close" then
		Close()
	elseif action == "pick" then
		-- In combat, the segment A used: the held directions, which the highlight may be a frame behind.
		local index = selected
		if InCombatLockdown() and StickKeysOn() then
			index = ns.RingHeldSegment()
		end
		local entry = index > 0 and CurrentPage().entries[index] or nil
		ns.RingLog("use", selected, entry and entry.label or "nothing", InCombatLockdown() and "in combat" or "")
		-- A key binding entry (the Game Menu) opens with A. Letting go of the stick on it clicked
		-- Forever's button under the cursor when that could be set up; otherwise it stays highlighted.
		if entry and entry.binding and not InCombatLockdown() then
			if ns.menuUnderCursor then
				Close()
			end
			return
		end
		-- The Toy Box turns to the toy pages; the secure side left the ring open (fc-keep).
		if entry and entry.toybox and not InCombatLockdown() then
			if ns.SetRingSub then
				ns.SetRingSub(true)
			end
			OpenToyBox()
			ShowPage()
			PlaySound(SOUNDKIT.GAMEPAD_RADIAL_MENU_TAB_OVER)
			return
		end
		-- Out of combat, A's own click already opened Forever's entries and ran the macros.
		-- In combat, A used what was set up for the segment, on the main menu pages.
		local done
		if InCombatLockdown() then
			done = entry and not ring.sub and StickKeysOn() and CombatAction(entry) ~= nil
		else
			done = entry and (entry.click or entry.macro or entry.toy or entry.macroName or entry.spell or entry.item)
		end
		Close()
		if entry and entry.missing then
			ns.Print(entry.label, "is not loaded. Turn it on in the addon list, or take it off the ring.")
		elseif entry and not done then
			if entry.run then
				-- After this frame, so a window it opens is not caught by the press that closed the ring.
				C_Timer.After(0, entry.run)
			else
				ns.Print(entry.label, "can't be opened from the ring in combat.")
			end
		end
	elseif action == "prev" or action == "next" then
		if ring.sub then
			local step = action == "next" and 1 or -1
			ring.sub.index = (ring.sub.index - 1 + step) % #ring.sub.pages + 1
		elseif #pages > 1 then
			local step = action == "next" and 1 or -1
			page = (page - 1 + step) % #pages + 1
		end
		ShowPage()
		PlaySound(SOUNDKIT.GAMEPAD_RADIAL_MENU_TAB_OVER)
	elseif action == "emotes" then
		-- D-pad up opens the emotes, or goes back to the main menu from them or the toy pages.
		if ring.sub then
			ring.sub = nil
		else
			ring.sub = { pages = emotePages, index = 1 }
		end
		ShowPage()
		PlaySound(ring.sub and SOUNDKIT.GAMEPAD_RADIAL_MENU_EMOTES_OPEN or SOUNDKIT.GAMEPAD_RADIAL_MENU_TAB_OVER)
	end
end

-- Kept for compatibility with older calls; the ring reads the entries each time it opens.
function ns.UpdateRing() end

-- Set up for combat just before it starts (protected buttons can still change then), and after
-- logging in.
local armEvents = CreateFrame("Frame")
armEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
armEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
armEvents:SetScript("OnEvent", function()
	ns.RingArmCombat()
end)
