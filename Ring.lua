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
-- The first three pages are Forever's main menu pages with the same entries. Their entries are
-- fixed; the player can fill their free segments and add pages of their own.
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
	menu = { label = Label("RADIAL_LABEL_GAME_MENU", "Game Menu"), atlas = "gamepad-radial-icon-gamemenu", click = "MainMenuMicroButton" },
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
	{ "lfd", "legacy", "store", "guild", "social", false, "tracking", "collections" },
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

-- The built-in entry a default page keeps in this segment, or nil.
function ns.RingLockedEntry(pageIndex, segment)
	local default = DEFAULT_PAGES[pageIndex]
	return default and default[segment] or nil
end

function ns.RingSlotFree(pageIndex, segment)
	return not ns.RingLockedEntry(pageIndex, segment) and not ns.db.ringPages[pageIndex].slots[segment]
end

-- Saved pages: ns.db.ringPages[n].slots[segment] holds the player's entries, either
-- { builtin = "character" } or { label, command, icon }. Pages past the third have a name.
function ns.RingPages()
	local saved = ns.db.ringPages
	for index = 1, #DEFAULT_PAGES do
		saved[index] = saved[index] or {}
		saved[index].slots = saved[index].slots or {}
	end
	for index = #DEFAULT_PAGES + 1, #saved do
		saved[index].slots = saved[index].slots or {}
		saved[index].name = saved[index].name or ("Menu " .. index)
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
	if pageIndex <= #DEFAULT_PAGES then
		return format("%s %d", MAIN_MENU, pageIndex)
	end
	return ns.db.ringPages[pageIndex].name
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
		local entry = { label = builtin.label, atlas = builtin.atlas, icon = builtin.icon, run = builtin.run }
		if builtin.click then
			entry.click = ClickFrame(builtin.click)
			if not entry.click then
				return nil -- this client has no such button
			end
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
local emotePage

local function BuildPages()
	wipe(pages)
	for index, savedPage in ipairs(ns.RingPages()) do
		local entries = {}
		for segment = 1, SEGMENTS do
			local data = ns.RingLockedEntry(index, segment) or savedPage.slots[segment]
			entries[segment] = data and ns.RingResolve(data) or nil
		end
		pages[index] = { header = index <= #DEFAULT_PAGES and MAIN_MENU or savedPage.name, entries = entries }
	end
	if not emotePage then
		local entries = {}
		for segment, emote in ipairs(EMOTES) do
			local token = emote[1]
			entries[segment] = {
				label = Label(emote[2], emote[1]),
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
		emotePage = { header = Label("RADIAL_LABEL_TARGET_EMOTES", "Emotes"), entries = entries }
	end
end

local function CurrentPage()
	return ring.showEmotes and emotePage or pages[page]
end

-- Forever's entries need the secure click, which can't be set up in combat.
local function Usable(entry)
	return entry and (entry.run or entry.macro or not InCombatLockdown()) and true or false
end

-- Points A at the highlighted entry: a click on Forever's button, a macro, or nothing (the addon
-- then runs the entry itself).
local function ArmPick(entry)
	local button = ns.ringPickButton
	if not button or InCombatLockdown() then
		return
	end
	if entry and entry.click then
		button:SetAttribute("type", "click")
		button:SetAttribute("clickbutton", entry.click)
	elseif entry and entry.macro then
		button:SetAttribute("type", "macro")
		button:SetAttribute("macrotext", entry.macro)
	else
		button:SetAttribute("type", nil)
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
	ArmPick(entry)
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
	local count = math.min(#pages, MAX_DOTS)
	local showDots = not ring.showEmotes and #pages > 1
	for i = 1, MAX_DOTS do
		local dot = ring.dots[i]
		dot:SetShown(showDots and i <= count)
		dot:SetAtlas("gamepad-radialgamemenu-cursorbg-" .. (i == page and "neutral" or "inactive"))
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
	ring.contextUp:SetText(ring.showEmotes and MAIN_MENU or emotePage.header)
end

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
	ring.pageLeft = ring.dotBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	ring.pageRight = ring.dotBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")

	-- The name of the entry the stick points at, in the middle of the wheel.
	ring.center = ring:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	ring.center:SetPoint("CENTER", ring.background, "CENTER")
	ring.center:SetWidth(120)

	-- Under the wheel: D-pad up for the emotes, D-pad down to sit or stand, then A and B.
	ring.contextUp = ring:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	ring.contextUp:SetPoint("TOP", ring.background, "BOTTOM", 0, -12)
	ring.contextKeys = ring:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	ring.contextKeys:SetPoint("TOP", ring.contextUp, "BOTTOM", 0, -4)
	ring.contextDown = ring:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	ring.contextDown:SetPoint("TOP", ring.contextKeys, "BOTTOM", 0, -4)
	ring.contextDown:SetText(Label("RADIAL_LABEL_TOGGLE_SIT", "Sit / Stand"))
	ring.hint = ring:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	ring.hint:SetPoint("TOP", ring.contextDown, "BOTTOM", 0, -12)

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
		local x, y = ns.GetRightStick()
		if x * x + y * y > SELECT_SQ then
			local degrees = math.deg(math.atan2(y, x))
			if degrees < -SEGMENT_ANGLE / 2 then
				degrees = degrees + 360
			end
			Select(math.floor((degrees + SEGMENT_ANGLE) / SEGMENT_ANGLE + 0.5))
		end
	end)

	-- Entering or leaving combat greys Forever's entries out or back in.
	ring:RegisterEvent("PLAYER_REGEN_DISABLED")
	ring:RegisterEvent("PLAYER_REGEN_ENABLED")
	ring:SetScript("OnEvent", function()
		if ring:IsShown() then
			local keep = selected
			ShowPage()
			Select(keep)
		end
	end)
end

local function SetHints()
	ring.pageLeft:SetText(ns.ButtonText("{PADLSHOULDER}", 22))
	ring.pageRight:SetText(ns.ButtonText("{PADRSHOULDER}", 22))
	ring.contextKeys:SetText(ns.ButtonText("{PADDUP} {PADDDOWN}", 20))
	ring.hint:SetText(ns.ButtonText("{PAD1} use    {PAD2} close", 20))
end

local function Close()
	if ring and ring:IsShown() then
		ring:Hide()
		PlaySound(SOUNDKIT.GAMEPAD_RADIAL_MENU_CLOSE)
	end
	ns.ringOpen = false
	ArmPick(nil)
end

-- Called by the secure driver: "open", "close", "pick", "prev", "next" or "emotes".
function ns.OnRing(action)
	if action == "open" then
		if not ring then
			CreateRing()
		end
		BuildPages()
		SetHints()
		page = math.min(START_PAGE, #pages)
		ring.showEmotes = false
		ShowPage()
		ns.ringOpen = true
		ring:Show()
		PlaySound(SOUNDKIT.GAMEPAD_RADIAL_MENU_OPEN)
	elseif not (ring and ring:IsShown()) then
		ns.ringOpen = false
	elseif action == "close" then
		Close()
	elseif action == "pick" then
		local entry = selected > 0 and CurrentPage().entries[selected] or nil
		-- Out of combat, A's own click already opened Forever's entries and ran the macros.
		local done = entry and (entry.click or entry.macro) and not InCombatLockdown()
		Close()
		if entry and not done then
			if entry.run then
				-- After this frame, so a window it opens is not caught by the press that closed the ring.
				C_Timer.After(0, entry.run)
			else
				ns.Print(entry.label, "can't be opened from the ring in combat.")
			end
		end
	elseif action == "prev" or action == "next" then
		if ring.showEmotes then
			ring.showEmotes = false
		elseif #pages > 1 then
			local step = action == "next" and 1 or -1
			page = (page - 1 + step) % #pages + 1
		end
		ShowPage()
		PlaySound(SOUNDKIT.GAMEPAD_RADIAL_MENU_TAB_OVER)
	elseif action == "emotes" then
		ring.showEmotes = not ring.showEmotes
		ShowPage()
		PlaySound(ring.showEmotes and SOUNDKIT.GAMEPAD_RADIAL_MENU_EMOTES_OPEN or SOUNDKIT.GAMEPAD_RADIAL_MENU_TAB_OVER)
	end
end

-- Kept for compatibility with older calls; the ring reads the entries each time it opens.
function ns.UpdateRing() end
