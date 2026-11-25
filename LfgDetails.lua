local _, ns = ...

-- LFG Filter's details panel: beside the window, the group (or the player looking for a group) that
-- the controller's cursor or the mouse is on in the Group finder list. It shows the members (class
-- icon, name in class colour, level, a crown on the leader, role, zone), what the group still needs,
-- its activities, its comment, how long ago it was listed, and your ratings and notes on its players.
--
-- LfgFilter.lua reads the group finder's data (ReadResult: entry.memberList, from
-- C_LFGList.GetSearchResultPlayerInfo / GetSearchResultLeaderInfo) and calls Details.Draw from its
-- Refresh with the listing to show, or nil to hide the panel. This file only draws: nothing of the
-- game's is called or written. Its locals live here, apart from LfgFilter.lua's, which is at Lua's
-- 200-local limit.

local Details = {}
ns.LfgDetails = Details

local WIDTH = 330
local PAD = 12
local GAP = 6 -- between the window and the panel
local LINE = 18 -- a member's line
local MAX_MEMBERS = 10
local MAX_ACTIVITIES = 8
local LEADER_ICON = "Interface\\GroupFrame\\UI-Group-LeaderIcon"
local CLASS_SHEET = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"

local panel
local atlasKnown = {}

local function HasAtlas(name)
	if atlasKnown[name] == nil then
		local ok, info = false, nil
		if C_Texture and C_Texture.GetAtlasInfo then
			ok, info = pcall(C_Texture.GetAtlasInfo, name)
		end
		atlasKnown[name] = (ok and info ~= nil) and true or false
	end
	return atlasKnown[name]
end

-- The class icon: the game's class atlas when this client has one, else the character creation sheet.
local function SetClassIcon(texture, class)
	texture:SetTexCoord(0, 1, 0, 1)
	if type(class) ~= "string" or class == "" then
		texture:Hide()
		return
	end
	local lower = class:lower()
	for _, atlas in ipairs({ "classicon-" .. lower, "groupfinder-icon-class-" .. lower }) do
		if HasAtlas(atlas) then
			texture:SetAtlas(atlas)
			texture:Show()
			return
		end
	end
	local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
	if coords then
		texture:SetTexture(CLASS_SHEET)
		texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
		texture:Show()
	else
		texture:Hide()
	end
end

-- Right of the window when the panel fits there, else left. With no room either side (a small screen
-- or a large UI scale), left too: kept on screen, it then covers the filters rather than the list.
-- All in the window's coordinates.
function Details.Side(windowLeft, windowRight, screenWidth, width)
	if not (windowLeft and windowRight and screenWidth) then
		return "right"
	end
	if screenWidth - windowRight - GAP >= width then
		return "right"
	end
	return "left"
end

-- The panel's top, as an offset from the window's top: level with the row, moved up so the panel
-- doesn't run past the window's bottom, but never above the window's top.
function Details.Top(rowOffset, panelHeight, windowHeight)
	local offset = rowOffset or 0
	if windowHeight and windowHeight > 0 then
		offset = math.max(offset, panelHeight - windowHeight)
	end
	return math.min(0, offset)
end

local function RoleMarkup(role, size)
	return "|A:" .. ns.LfgFilterKit.ROLE_ATLAS[role] .. ":" .. size .. ":" .. size .. "|a"
end

local function Listed(stamp)
	if not stamp then
		return nil
	end
	local ago = ns.LfgFilterKit.Ago(stamp)
	return ago == "now" and "listed just now" or ("listed " .. ago .. " ago")
end

---------------------------------------------------------------------------------------------------
-- Building and laying out

local function Create(window)
	local kit = ns.LfgFilterKit
	local gold = kit.GOLD
	panel = CreateFrame("Frame", nil, window, "BackdropTemplate")
	panel:SetWidth(WIDTH)
	panel:SetFrameLevel(window:GetFrameLevel() + 20)
	panel:SetClampedToScreen(true)
	kit.Flat(panel, { 0.06, 0.06, 0.075, 0.98 }, { gold[1], gold[2], gold[3], 0.6 })
	local accent = panel:CreateTexture(nil, "ARTWORK")
	accent:SetPoint("TOPLEFT", 1, -1)
	accent:SetPoint("TOPRIGHT", -1, -1)
	accent:SetHeight(2)
	accent:SetColorTexture(gold[1], gold[2], gold[3], 0.8)
	panel.texts, panel.lines, panel.dividers = {}, {}, {}
	panel:Hide()
end

local function Begin()
	panel.y = PAD
	panel.textCount, panel.lineCount, panel.dividerCount = 0, 0, 0
end

-- A block of text across the panel. Without wrap it is one line, cut with "..." when too long.
local function AddText(text, font, gap, lines, indent)
	if not text or text == "" then
		return
	end
	panel.textCount = panel.textCount + 1
	local label = panel.texts[panel.textCount]
	if not label then
		label = panel:CreateFontString(nil, "OVERLAY")
		label:SetJustifyH("LEFT")
		label:SetJustifyV("TOP")
		panel.texts[panel.textCount] = label
	end
	label:SetFontObject(_G[font] or GameFontHighlightSmall)
	label:SetWordWrap((lines or 1) > 1)
	if label.SetMaxLines then
		label:SetMaxLines(lines or 1)
	end
	label:SetWidth(WIDTH - 2 * PAD - (indent or 0))
	panel.y = panel.y + (gap or 0)
	label:ClearAllPoints()
	label:SetPoint("TOPLEFT", PAD + (indent or 0), -panel.y)
	label:SetText(text)
	label:Show()
	panel.y = panel.y + math.ceil(label:GetStringHeight() or 12)
end

local function AddDivider()
	panel.dividerCount = panel.dividerCount + 1
	local line = panel.dividers[panel.dividerCount]
	if not line then
		local gold = ns.LfgFilterKit.GOLD
		line = panel:CreateTexture(nil, "ARTWORK")
		line:SetHeight(1)
		line:SetColorTexture(gold[1], gold[2], gold[3], 0.25)
		panel.dividers[panel.dividerCount] = line
	end
	panel.y = panel.y + 7
	line:ClearAllPoints()
	line:SetPoint("TOPLEFT", PAD, -panel.y)
	line:SetPoint("TOPRIGHT", -PAD, -panel.y)
	line:Show()
	panel.y = panel.y + 7
end

-- A member's line, in columns: class icon, name, level, crown (leader), role, zone.
local function NewLine()
	local line = CreateFrame("Frame", nil, panel)
	line:SetSize(WIDTH - 2 * PAD, LINE)
	line.class = line:CreateTexture(nil, "ARTWORK")
	line.class:SetSize(16, 16)
	line.class:SetPoint("LEFT", 0, 0)
	line.name = line:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	line.name:SetWordWrap(false)
	line.name:SetJustifyH("LEFT")
	line.name:SetPoint("LEFT", 20, 0)
	line.name:SetWidth(118)
	line.level = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	line.level:SetJustifyH("LEFT")
	line.level:SetPoint("LEFT", 142, 0)
	line.level:SetWidth(24)
	line.crown = line:CreateTexture(nil, "ARTWORK")
	line.crown:SetSize(14, 14)
	line.crown:SetPoint("LEFT", 168, 0)
	line.crown:SetTexture(LEADER_ICON)
	line.role = line:CreateTexture(nil, "ARTWORK")
	line.role:SetSize(16, 16)
	line.role:SetPoint("LEFT", 186, 0)
	line.zone = line:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	line.zone:SetWordWrap(false)
	line.zone:SetJustifyH("RIGHT")
	line.zone:SetPoint("LEFT", 206, 0)
	line.zone:SetPoint("RIGHT", 0, 0)
	return line
end

local function AddMember(member, solo)
	local kit = ns.LfgFilterKit
	panel.lineCount = panel.lineCount + 1
	local line = panel.lines[panel.lineCount]
	if not line then
		line = NewLine()
		panel.lines[panel.lineCount] = line
	end
	line:ClearAllPoints()
	line:SetPoint("TOPLEFT", PAD, -panel.y)
	SetClassIcon(line.class, member.class)
	line.name:SetText(member.name and kit.ClassColored(member.name, member.class) or "|cff999999Unknown|r")
	line.level:SetText(member.level and ("|cff999999" .. member.level .. "|r") or "")
	line.crown:SetShown(member.leader and not solo)
	local role = not solo and member.role and kit.ROLE_ATLAS[member.role]
	if role then
		line.role:SetAtlas(role)
	end
	line.role:SetShown(role and true or false)
	line.zone:SetText(member.zone or "")
	line:Show()
	panel.y = panel.y + LINE
	-- How often you grouped with them, your rating and notes, under their name, wrapped to the panel's width.
	local rating, note = kit.RatingOf(member.name), kit.NoteOf(member.name)
	local times = ns.LfgGroupCount and ns.LfgGroupCount(member.name) or 0
	if member.name and (rating > 0 or note or times > 0) then
		local parts = {}
		if times > 0 then
			parts[#parts + 1] = "|cff999999Grouped " .. (times == 1 and "once" or (times .. " times")) .. "|r"
		end
		if rating > 0 then
			parts[#parts + 1] = kit.RATINGS[rating].tag
		end
		if note then
			parts[#parts + 1] = "|cffdddddd" .. note .. "|r"
		end
		AddText(table.concat(parts, "  "), "GameFontHighlightSmall", 0, 3, 20)
		panel.y = panel.y + 3
	end
end

local function Finish(window, rowOffset)
	for index = panel.textCount + 1, #panel.texts do
		panel.texts[index]:Hide()
	end
	for index = panel.lineCount + 1, #panel.lines do
		panel.lines[index]:Hide()
	end
	for index = panel.dividerCount + 1, #panel.dividers do
		panel.dividers[index]:Hide()
	end
	local height = panel.y + PAD
	panel:SetHeight(height)
	local screenWidth
	local scale, parentScale = window:GetEffectiveScale(), UIParent:GetEffectiveScale()
	if scale and parentScale and scale > 0 and UIParent:GetWidth() then
		screenWidth = UIParent:GetWidth() * parentScale / scale
	end
	local side = Details.Side(window:GetLeft(), window:GetRight(), screenWidth, WIDTH)
	local top = Details.Top(rowOffset, height, window:GetHeight())
	panel:ClearAllPoints()
	if side == "right" then
		panel:SetPoint("TOPLEFT", window, "TOPRIGHT", GAP, top)
	else
		panel:SetPoint("TOPRIGHT", window, "TOPLEFT", -GAP, top)
	end
	panel:Show()
end

---------------------------------------------------------------------------------------------------
-- Content

-- Logs once per listing shown which of the fields came through, to see what this client sends.
local function LogFields(entry)
	if panel.loggedFor == entry.id then
		return
	end
	panel.loggedFor = entry.id
	local list = entry.memberList or {}
	local have = { name = 0, class = 0, level = 0, role = 0, zone = 0, leader = 0 }
	for _, member in ipairs(list) do
		for key in pairs(have) do
			if member[key] then
				have[key] = have[key] + 1
			end
		end
	end
	ns.LfgFilterKit.Log("details", entry.id, entry.secret and "secret" or entry.solo and "player" or "group",
		"members", #list, "of", entry.members, "with name", have.name, "class", have.class, "level", have.level,
		"role", have.role, "zone", have.zone, "leader", have.leader, "activities", #(entry.activities or {}),
		"comment", entry.comment ~= "" and "yes" or "no")
end

local function DrawEntry(entry)
	local kit = ns.LfgFilterKit
	if entry.secret then
		AddText("Hidden listing", "GameFontNormal")
		AddText("|cff999999The group finder hides this listing right now. Its details come back after combat.|r",
			"GameFontHighlightSmall", 4, 3)
		return
	end
	local solo = entry.solo
	local list = entry.memberList or {}

	-- What, how big, how long ago.
	local title = entry.activityText ~= "" and entry.activityText or entry.title
	AddText(title ~= "" and title or (solo and "Looking for a group" or "Group"), "GameFontNormal")
	local facts = {}
	if not solo then
		facts[#facts + 1] = entry.members .. "/" .. (entry.maxPlayers or 5) .. " members"
	end
	facts[#facts + 1] = Listed(entry.listedAt)
	if entry.newPlayers then
		facts[#facts + 1] = "new players welcome"
	end
	AddText("|cff999999" .. table.concat(facts, "  -  ") .. "|r", "GameFontHighlightSmall", 3)

	-- Roles: what the group still needs, or what the player can fill.
	local roles = {}
	for _, role in ipairs(kit.ROLES) do
		if solo then
			if entry.roles and entry.roles[role] then
				roles[#roles + 1] = RoleMarkup(role, 14) .. " " .. kit.ROLE_NAMES[role]
			end
		elseif entry.counts then
			local left = entry.counts[role .. "Left"] or 0
			if left > 0 then
				roles[#roles + 1] = RoleMarkup(role, 14) .. " " .. kit.ROLE_NAMES[role] .. (left > 1 and (" x" .. left) or "")
			end
		end
	end
	if solo then
		AddText(#roles > 0 and ("|cffffd100Can fill|r   " .. table.concat(roles, "    ")) or "", "GameFontHighlightSmall", 6)
	elseif entry.counts then
		AddText(#roles > 0 and ("|cffffd100Needs|r   " .. table.concat(roles, "    ")) or "|cff999999No roles open|r",
			"GameFontHighlightSmall", 6)
	end

	-- The members, leader first.
	AddDivider()
	for index = 1, math.min(#list, MAX_MEMBERS) do
		AddMember(list[index], solo)
	end
	if #list > MAX_MEMBERS then
		AddText("|cff999999+" .. (#list - MAX_MEMBERS) .. " more|r", "GameFontHighlightSmall", 2)
	elseif #list == 0 then
		AddText("|cff999999The group finder sent no member details.|r", "GameFontHighlightSmall")
	end

	-- Every activity, when there are several.
	local activities = entry.activities or {}
	if #activities > 1 then
		local names = {}
		for index = 1, math.min(#activities, MAX_ACTIVITIES) do
			names[#names + 1] = kit.ActivityName(activities[index])
		end
		if #activities > MAX_ACTIVITIES then
			names[#names + 1] = "|cff999999+" .. (#activities - MAX_ACTIVITIES) .. " more|r"
		end
		AddDivider()
		AddText("|cffffd100" .. (solo and "Looking for" or "Activities") .. "|r", "GameFontNormalSmall")
		AddText(table.concat(names, "\n"), "GameFontHighlightSmall", 3, #names)
	end

	-- The comment.
	if entry.comment ~= "" then
		AddDivider()
		AddText("|cffffd100Comment|r", "GameFontNormalSmall")
		AddText(entry.comment, "GameFontHighlightSmall", 3, 8)
	end
end

-- Shows the panel for a listing (an entry of LfgFilter's state.results) beside the window, level with
-- its row (rowOffset: the row's top below the window's top, negative). nil hides it.
function Details.Draw(window, entry, rowOffset)
	if not entry or not window or not ns.LfgFilterKit then
		if panel then
			panel:Hide()
		end
		return
	end
	if not panel then
		Create(window)
	end
	LogFields(entry)
	Begin()
	DrawEntry(entry)
	Finish(window, rowOffset)
end
