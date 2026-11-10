local _, ns = ...

-- The addon's own settings window, with the settings grouped on tabs. Every setting is a row:
-- a checkbox, a choice or number with arrows, a dropdown, or a button. The controller works it while it is open:
-- D-pad up / down picks a row, left / right changes it, A toggles or presses, L1 / R1 change tab,
-- and B or Start closes it. It is a plain frame, not one of the game's panels, so opening it does not
-- go through Forever's window focus. The tabs are a column on the left, under a search box that
-- finds settings on every tab by name or description.

local SIDEBAR = 170 -- width of the tab column on the left
local WIDTH, HEIGHT = 580 + SIDEBAR, 740
local ROW_HEIGHT = 32
local TITLE_HEIGHT = 34
local ROWS_TOP = -50
local GOLD = { 1, 0.82, 0 }

-- Labels and tips name buttons as {PADLSHOULDER} and the like: icons of the controller in use on
-- screen, plain names in search. See ns.ButtonText.
local ButtonText = ns.ButtonText

local function HighlightChoices()
	return {
		{ "outline", "Outline" },
		{ "thick", "Thick outline" },
		{ "fill", "Fill" },
		{ "pulse", "Pulse" },
	}
end

local function StickChoices()
	local choices = {}
	for _, action in ipairs(ns.STICK_ACTIONS) do
		local group = action[4] and "spell" or ns.STICK_ACTION_GROUPS and ns.STICK_ACTION_GROUPS[action[1]]
		tinsert(choices, { action[1], action[2], action[5] or (action[1] == "ring" and ns.ICON or nil), group })
	end
	return choices
end

local function L1RightStickChoices()
	local choices = {}
	for _, action in ipairs(ns.L1_RIGHT_STICK) do
		tinsert(choices, { action[1], action[2] })
	end
	return choices
end

local function L1R1Choices()
	local choices = { { "sheatheSmart", "Sheathe, dismount or descend", nil, "character" } }
	for _, choice in ipairs(StickChoices()) do
		tinsert(choices, choice)
	end
	return choices
end

local function ActiveColorChoices()
	local choices = {}
	for _, color in ipairs(ns.HIGHLIGHT_COLORS) do
		tinsert(choices, { color[1], format("|cff%02x%02x%02x%s|r", math.floor(color[3] * 255), math.floor(color[4] * 255), math.floor(color[5] * 255), color[2]) })
	end
	return choices
end

local function SideChoices()
	local choices = {}
	for side = 1, ns.NUM_SETS * 2 do
		local set, letter = ns.DescribeSide(side)
		tinsert(choices, { side, "Set " .. set .. " " .. (letter == "L" and "left" or "right") })
	end
	return choices
end

local function SetChoices()
	local choices = {}
	for set = 1, ns.NUM_SETS do
		tinsert(choices, { set, "Set " .. set })
	end
	return choices
end

-- A form can also use the game's own stance bar (set 0).
local function FormSetChoices()
	local choices = { { 0, "The game's stance bar" } }
	for _, choice in ipairs(SetChoices()) do
		tinsert(choices, choice)
	end
	return choices
end

local function Sync()
	ns.Sync()
end

local function Refresh()
	ns.RefreshVisuals()
end

local function Nothing() end

-- Buttons that show something on the crossbar close the window first so it can be seen.
local function CloseAnd(action)
	return function()
		ns.CloseConfig()
		action()
	end
end

local function BuildTabs()
	local formRows = {}
	for form = 1, ns.NUM_FORMS do
		tinsert(formRows, { type = "choice", key = "formSet" .. form, label = "Form " .. form .. " uses", choices = FormSetChoices,
			tip = "Each form or stance swaps both bottom sides to its set; by default form 1 uses set 5, form 2 set 6 and so on. The game's stance bar instead shows the 8 abilities Forever's own gamepad bars keep for the form, on the left side only. Form 1 is stealth for rogues and cat form for druids." })
	end

	local tabs = {
		{
			name = "General",
			icon = "Interface\\Icons\\INV_Misc_Gear_01",
			rows = {
				{ type = "check", key = "enabled", label = "Enable layout",
					tip = "Replaces Forever's bar with the cross hotbars. Only takes effect in Gamepad UI." },
				{ type = "action", label = "Slots", button = "Edit crossbar", run = CloseAnd(function() ns.ToggleEditor() end),
					tip = "Shows any layer on the crossbar so you can drag spells onto it." },
				{ type = "action", label = "Position", button = "Move bars", run = CloseAnd(function() ns.ToggleMove() end),
					tip = "Drag each bar anywhere on the screen." },
				{ type = "check", key = "minimapShown", label = "Show minimap icon", onChange = function() ns.UpdateMinimapButton() end,
					tip = "Left click: settings. Right click: menu. Drag: move the icon." },
				{ type = "check", key = "lootDetails", label = "Show loot roll item details",
					onChange = function() if ns.RefreshLootDetails then ns.RefreshLootDetails() end end,
					tip = "While a loot roll window is open, the item and what you wear in that slot are shown beside it." },
				{ type = "check", key = "alwaysCompareItems", label = "Always compare items",
					onChange = function() ns.ApplyAlwaysCompare() end,
					tip = "Every item tooltip also shows what you wear in that slot, without holding Shift. This is WoW's own setting." },
				{ type = "check", key = "autoFace", label = "Face target (turn toward the enemy)",
					onChange = function()
						ns.AllowExperimentalCamera()
						ns.Sync()
					end,
					tip = "Experimental. Locks the camera on the enemy target, so the character turns to it when casting. WoW has no way to turn only the character." },
			},
		},
		{
			name = "Targeting",
			icon = "Interface\\Icons\\Ability_Hunter_SniperShot",
			rows = {
				{ type = "choice", key = "dpadTarget", label = "D-pad arrow selection",
					choices = function() return { { "enemy", "Enemies only" }, { "friend", "Friendly only" }, { "both", "Both" } } end,
					tip = "What D-pad left and right select. Both takes turns between enemies and friendlies. Not used while D-pad party selection is active." },
				{ type = "choice", key = "dpadParty", label = "D-pad party selection",
					choices = function() return { { "off", "Off" }, { "raid", "In a raid" }, { "always", "Always" } } end,
					tip = "Off: D-pad left and right take turns between enemies and friendlies. In a raid or Always: the whole D-pad moves over the party and raid frames on screen." },
				{ type = "choice", key = "partyTargeting", label = "Party targeting",
					choices = function() return { { "soft", "Soft" }, { "hard", "Hard" } } end,
					tip = "Soft: selecting a party or raid member sets a temporary target for the next ability, and your real target stays. Hard: it changes your real target." },
				{ type = "choice", key = "partyHighlight", label = "Party highlight", choices = HighlightChoices,
					tip = "How the selected party member's frame is marked. Outline: a thin gold border. Thick outline: a wide one. Fill: a gold tint with a border. Pulse: a border that fades in and out." },
				{ type = "choice", key = "partyMarker", label = "Party marker",
					choices = function() return { { "left", "Left" }, { "right", "Right" }, { "off", "Off" } } end,
					tip = "A gold arrow outside the selected party frame, on the side you choose, pointing at it." },
				{ type = "choice", key = "raidHighlight", label = "Raid highlight", choices = HighlightChoices,
					tip = "How the selected raid member's frame is marked, with the same choices as the party highlight." },
				{ type = "choice", key = "highlightColor", label = "Highlight color",
					choices = function()
						local choices = {}
						for _, color in ipairs(ns.HIGHLIGHT_COLORS) do
							tinsert(choices, { color[1], format("|cff%02x%02x%02x%s|r", math.floor(color[3] * 255), math.floor(color[4] * 255), math.floor(color[5] * 255), color[2]) })
						end
						return choices
					end,
					onChange = function() Sync() Refresh() end,
					tip = "The color of the party and raid highlight and of the party marker. The Neon theme and the highlight color backgrounds and borders use it too." },
			},
		},
		{
			name = "Appearance",
			icon = "Interface\\Icons\\INV_Misc_Gem_Variety_01",
			rows = {
				{ type = "choice", key = "theme", label = "Theme",
					choices = function()
						local choices = {}
						for _, theme in ipairs(ns.THEMES) do
							tinsert(choices, { theme[1], theme[2] })
						end
						return choices
					end,
					onChange = Refresh,
					tip = "How the slots look. Each theme also picks the background, background border, slot background and slot border, for those left on the theme's choice. Classic: the standard action buttons. Forever: like Forever's own bar. Round: Forever's round slots. Hex: hexagon icons on dark hexagons. Sigil: round icons in gold rings inside a ring of runes. Holo: icons in cyan corner brackets with a dashed ring. Ink: icons in brushed ink rings on an ink wash. Orb: round icons in a metal bezel. Minimal: flat icons with a thin dark edge." },
				{ type = "choice", key = "background", label = "Background",
					choices = function()
						local choices = { { "theme", "From theme" } }
						for _, background in ipairs(ns.BACKGROUNDS) do
							tinsert(choices, { background[1], background[2] })
						end
						return choices
					end,
					onChange = Refresh,
					tip = "Drawn behind each group of four slots: a dark circle, a soft shadow, a vignette that fades out, a tinted glass circle, a glow of the highlight color, or nothing." },
				{ type = "choice", key = "backgroundBorder", label = "Background border",
					choices = function()
						local choices = { { "theme", "From theme" } }
						for _, border in ipairs(ns.BACKGROUND_BORDERS) do
							tinsert(choices, { border[1], border[2] })
						end
						return choices
					end,
					onChange = Refresh,
					tip = "A ring around each group of four slots: thin, double, a soft glow, or a glow of the highlight color." },
				{ type = "choice", key = "slotFill", label = "Slot background",
					choices = function()
						local choices = { { "theme", "From theme" } }
						for _, fill in ipairs(ns.SLOT_FILLS) do
							tinsert(choices, { fill[1], fill[2] })
						end
						return choices
					end,
					onChange = Refresh,
					tip = "The fill inside each slot, under the ability: Dark, Smoke, Gradient, Glass, the highlight color, Deep (a dark radial) or Frost (frosted glass lit from the top). None leaves empty slots see-through." },
				{ type = "choice", key = "slotBorder", label = "Slot border",
					choices = function()
						local choices = { { "theme", "From theme" } }
						for _, border in ipairs(ns.SLOT_BORDERS) do
							tinsert(choices, { border[1], border[2] })
						end
						return choices
					end,
					onChange = Refresh,
					tip = "A border around each slot, in the slot's own shape: thin, thick, double, a soft glow, or the highlight color." },
				{ type = "number", key = "backgroundAlpha", label = "Background opacity", min = 0.1, max = 1, step = 0.05, onChange = Refresh },
				{ type = "choice", key = "activeHighlight", label = "Selected bar highlight",
					choices = function()
						local choices = {}
						for _, style in ipairs(ns.ACTIVE_STYLES) do
							tinsert(choices, { style[1], style[2] })
						end
						return choices
					end,
					onChange = function() ns.RefreshActiveHighlight() end,
					tip = "How the bar you are using is lit up: one big glow, a soft glow or a ring around each group of four, a glow behind each slot, or nothing." },
				{ type = "choice", key = "activeColorBottom", label = "Bottom bar color", choices = ActiveColorChoices,
					onChange = function() ns.RefreshActiveHighlight() end,
					tip = "The highlight color of the bottom bars, while {PADLTRIGGER} or {PADRTRIGGER} is held." },
				{ type = "choice", key = "activeColorTopLeft", label = "Top left bar color", choices = ActiveColorChoices,
					onChange = function() ns.RefreshActiveHighlight() end,
					tip = "The highlight color of the top left bar (double tap {PADLTRIGGER})." },
				{ type = "choice", key = "activeColorTopRight", label = "Top right bar color", choices = ActiveColorChoices,
					onChange = function() ns.RefreshActiveHighlight() end,
					tip = "The highlight color of the top right bar (double tap {PADRTRIGGER})." },
				{ type = "choice", key = "activeColorCombo", label = "Combo color", choices = ActiveColorChoices,
					onChange = function() ns.RefreshActiveHighlight() end,
					tip = "The highlight color while {PADLTRIGGER} then {PADRTRIGGER}, or {PADRTRIGGER} then {PADLTRIGGER}, is held." },
				{ type = "number", key = "activeStrength", label = "Selected bar brightness", min = 0.1, max = 1, step = 0.05,
					onChange = function() ns.RefreshActiveHighlight() end },
				{ type = "check", key = "activeMarks", label = "Marks in the middle of the selected bar",
					onChange = function() ns.RefreshActiveHighlight() end,
					tip = "The small cross and dots between the slots of the bar you are using." },
			},
		},
		{
			name = "Crossbar",
			icon = "Interface\\Icons\\INV_Misc_Book_09",
			rows = {
				{ type = "number", key = "scale", label = "Scale", min = 0.5, max = 1.5, step = 0.05 },
				{ type = "number", key = "x", label = "Horizontal position", min = -1500, max = 1500, step = 10,
					tip = "Hold Shift with the mouse, or use Move bars on the General tab, for bigger steps." },
				{ type = "number", key = "y", label = "Vertical position", min = -200, max = 1200, step = 10,
					tip = "Hold Shift with the mouse, or use Move bars on the General tab, for bigger steps." },
				{ type = "number", key = "clusterPadding", label = "Padding between button groups", min = 0, max = 80, step = 2,
					tip = "Gap between the D-pad group and the face button group of each bar." },
				{ type = "number", key = "dimAlpha", label = "Inactive side opacity", min = 0, max = 1, step = 0.05,
					tip = "How visible the other bars are while one is selected." },
				{ type = "check", key = "showKeyLabels", label = "Show controller buttons on slots", onChange = Refresh },
				{ type = "number", key = "keyIconSize", label = "Controller button size", min = 16, max = 60, step = 2, onChange = Refresh },
				{ type = "check", key = "rangeIndicator", label = "Show out of range abilities in red", onChange = Nothing,
					tip = "Tints an ability red while your target is out of its range." },
				{ type = "check", key = "showInteractPrompt", label = "Show interact prompt", onChange = Nothing,
					tip = "Over the character: the button, the action's icon and the name of what you can loot, talk to, skin, mine or gather." },
				{ type = "check", key = "showSetLabels", label = "Show set labels", onChange = Refresh },
				{ type = "choice", key = "showTopLeft", label = "Top left bar (double tap {PADLTRIGGER})",
					choices = function() return { { "always", "Always shown" }, { "selected", "Only when selected" } } end,
					tip = "Only when selected: the top left bar is hidden until you double tap {PADLTRIGGER}." },
				{ type = "choice", key = "showTopRight", label = "Top right bar (double tap {PADRTRIGGER})",
					choices = function() return { { "always", "Always shown" }, { "selected", "Only when selected" } } end,
					tip = "Only when selected: the top right bar is hidden until you double tap {PADRTRIGGER}." },
			},
		},
		{
			name = "Layers and forms",
			icon = "Interface\\Icons\\Ability_Druid_CatForm",
			rows = {
				{ type = "choice", key = "sideWL", label = "Double tap {PADLTRIGGER} shows", choices = SideChoices },
				{ type = "choice", key = "sideWR", label = "Double tap {PADRTRIGGER} shows", choices = SideChoices },
				{ type = "choice", key = "sideLR", label = "{PADLTRIGGER} then {PADRTRIGGER} shows", choices = SideChoices },
				{ type = "choice", key = "sideRL", label = "{PADRTRIGGER} then {PADLTRIGGER} shows", choices = SideChoices },
				{ type = "check", key = "formsChangeBar", label = "Forms change the bottom row",
					tip = "Each form or stance keeps its own set. {PADRSHOULDER} + a button changes the set of the current form; the button of your normal set gives the form its own set back (5-8)." },
			},
		},
		{
			name = "Input",
			icon = "Interface\\Icons\\INV_Gizmo_02",
			rows = {
				{ type = "choice", key = "triggerMode", label = "{PADLTRIGGER} / {PADRTRIGGER} activation",
					choices = function() return { { "hold", "Hold" }, { "toggle", "Toggle" }, { "mixed", "Mixed" } } end,
					tip = "Hold: selected while the trigger is held. Toggle: stays selected until pressed again, also after a double tap. Mixed: a tap toggles and a hold holds." },
				{ type = "choice", key = "l3Action", label = "{PADLSTICK} (press left stick)", choices = StickChoices,
					tip = "What pressing the left stick in does." },
				{ type = "choice", key = "r3Action", label = "{PADRSTICK} (press right stick)", choices = StickChoices,
					tip = "What pressing the right stick in does. {PADLTRIGGER} or {PADRTRIGGER} + {PADRSTICK} still moves or removes an ability." },
				{ type = "choice", key = "l1R3Action", label = "{PADLSHOULDER} + {PADRSTICK}", choices = StickChoices,
					tip = "What {PADRSTICK} does while {PADLSHOULDER} is held. A class menu your class does not have falls back to {PADRSTICK}'s own action." },
				{ type = "choice", key = "r1L3Action", label = "{PADRSHOULDER} + {PADLSTICK}", choices = StickChoices,
					tip = "What {PADLSTICK} does while {PADRSHOULDER} is held. A class menu your class does not have falls back to {PADLSTICK}'s own action." },
				{ type = "choice", key = "r1R3Action", label = "{PADRSHOULDER} + {PADRSTICK}", choices = StickChoices,
					tip = "What {PADRSTICK} does while {PADRSHOULDER} is held. The Gamepad XIV ring by default." },
				{ type = "choice", key = "l1R1Action", label = "{PADLSHOULDER} + {PADRSHOULDER}", choices = L1R1Choices,
					tip = "What {PADRSHOULDER} does while {PADLSHOULDER} is held. Sheathe by default, which dismounts when mounted and descends when flying. On the world map {PADLSHOULDER} + {PADRSHOULDER} still places a map pin." },
				{ type = "choice", key = "l1StickUpAction", label = "{PADLSHOULDER} + left stick forward", choices = StickChoices,
					tip = "What pushing the left stick forward does while {PADLSHOULDER} is held. With Auto-run, pressing {PADLSHOULDER} while already moving forward also starts auto-run." },
				{ type = "choice", key = "l1RightStick", label = "{PADLSHOULDER} + right stick", choices = L1RightStickChoices,
					tip = "What the right stick does while {PADLSHOULDER} is held: zoom the camera in and out, or turn the camera as it normally does." },
				{ type = "number", key = "doubleTapTicks", label = "Double tap window", min = 2, max = 4, step = 1,
					tip = "In 0.2 second steps: 2 is about 0.2-0.4 seconds, and it can be shorter in combat." },
				{ type = "check", key = "holdToWalk", label = "Hold {PAD2} to walk" },
				{ type = "check", key = "priorityBindings", label = "Priority bindings",
					tip = "Turn on only if {PADRTRIGGER} does not change the bar. Then check that menus can still be navigated." },
			},
		},
		{
			-- Filled by RebuildRingRows from the saved entries.
			name = "Ring",
			icon = "Interface\\Icons\\INV_Misc_Map_01",
			ring = true,
			rows = {},
		},
	}
	for _, row in ipairs(formRows) do
		tinsert(tabs[4].rows, row)
	end
	for index = #tabs, 1, -1 do
		if tabs[index].hidden then
			tremove(tabs, index)
		end
	end
	-- Every choice is a dropdown list; D-pad left / right on the row still steps through it.
	for _, tab in ipairs(tabs) do
		for _, row in ipairs(tab.rows) do
			if row.type == "choice" then
				row.dropdown = true
			end
		end
	end
	return tabs
end

local window, tabs, rowFrames, tabButtons
local selectedTab, cursor = 1, 1
local searchRows -- the rows matching the search text, or nil when not searching
local searchMore = 0 -- matches left out because they do not fit

-- The rows on screen: the search results while searching, otherwise the selected tab's.
local function CurrentRows()
	return searchRows or tabs[selectedTab].rows
end

local function FormatNumber(value)
	return tostring(RoundToSignificantDigits(value, 3))
end

local function ChoiceIndex(row)
	local choices = row.choices()
	for i, choice in ipairs(choices) do
		if choice[1] == (row.get and row.get() or ns.db[row.key]) then
			return i, choices
		end
	end
	return 1, choices
end

local function SetValue(row, value)
	if row.set then
		row.set(value)
		return
	end
	ns.db[row.key] = value
	;(row.onChange or Sync)()
end

local UpdateRows

-- Changes a row by one step: delta is -1 or 1. Checkboxes flip either way.
local function StepRow(row, delta, big)
	if row.type == "buttons" then
		row.sub = math.max(1, math.min(#row.buttons, (row.sub or 1) + delta))
	elseif row.type == "check" then
		SetValue(row, not ns.db[row.key])
	elseif row.type == "choice" then
		local index, choices = ChoiceIndex(row)
		index = (index - 1 + delta) % #choices + 1
		SetValue(row, choices[index][1])
	elseif row.type == "number" then
		local step = row.step * (big and 10 or 1)
		local value = ns.db[row.key] + delta * step
		value = math.min(row.max, math.max(row.min, value))
		-- Steps like 0.05 drift in floating point; snap back to the step grid.
		value = row.min + math.floor((value - row.min) / row.step + 0.5) * row.step
		SetValue(row, value)
	end
	UpdateRows()
end

-- The open dropdown list: the row it belongs to and the highlighted choice. The list shows the
-- choices matching its search box (listChoices), at most LIST_MAX_ITEMS at a time from listOffset.
local list, listRow, listCursor
local listChoices, listOffset = {}, 0
local dialog -- the window for adding a ring entry or naming a ring page
local LIST_ITEM_HEIGHT = 22
local LIST_MAX_ITEMS = 14
local LIST_SEARCH_HEIGHT = 30
-- Lists longer than this get a search box.
local LIST_SEARCH_MIN = 8

-- A choice's label with its icon in front, when it has one.
local function ChoiceText(choice)
	if choice[3] then
		return "|T" .. choice[3] .. ":16:16:0:0:64:64:5:59:5:59|t " .. choice[2]
	end
	return choice[2]
end

local function CloseList()
	if list then
		list:Hide()
		list.search:ClearFocus()
	end
	listRow = nil
end

-- The choices whose label contains the search text, ignoring case and color codes.
local function FilterList()
	local all = listRow.choices()
	local text = list.search:IsShown() and strtrim(list.search:GetText() or ""):lower() or ""
	wipe(listChoices)
	for _, choice in ipairs(all) do
		local label = choice[2]:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower()
		if text == "" or label:find(text, 1, true) then
			tinsert(listChoices, choice)
		end
	end
end

local function UpdateList()
	if not listRow then
		return
	end
	local count = #listChoices
	listCursor = math.max(1, math.min(listCursor or 1, count))
	-- Keep the highlighted choice in view.
	local shown = math.min(count, LIST_MAX_ITEMS)
	if listCursor <= listOffset then
		listOffset = listCursor - 1
	elseif listCursor > listOffset + shown then
		listOffset = listCursor - shown
	end
	listOffset = math.max(0, math.min(listOffset, count - shown))
	local currentValue = listRow.get and listRow.get() or ns.db[listRow.key]
	local top = list.search:IsShown() and LIST_SEARCH_HEIGHT or 0
	for i = 1, shown do
		local index = listOffset + i
		local choice = listChoices[index]
		local item = list.items[i]
		if not item then
			item = CreateFrame("Button", nil, list)
			item:SetHeight(LIST_ITEM_HEIGHT)
			item.focus = item:CreateTexture(nil, "BACKGROUND")
			item.focus:SetAllPoints()
			item.focus:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.22)
			item.text = item:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			item.text:SetPoint("LEFT", 8, 0)
			item.text:SetPoint("RIGHT", -8, 0)
			item.text:SetJustifyH("LEFT")
			item.text:SetWordWrap(false)
			-- A line above the first choice of a new group.
			item.separator = item:CreateTexture(nil, "ARTWORK")
			item.separator:SetHeight(1)
			item.separator:SetPoint("TOPLEFT", 4, 0)
			item.separator:SetPoint("TOPRIGHT", -4, 0)
			item.separator:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.35)
			item:SetScript("OnEnter", function(self)
				listCursor = listOffset + self.slot
				UpdateList()
			end)
			item:SetScript("OnClick", function(self)
				list.Pick(listOffset + self.slot)
			end)
			list.items[i] = item
		end
		item.slot = i
		item:ClearAllPoints()
		item:SetPoint("TOPLEFT", 5, -5 - top - (i - 1) * LIST_ITEM_HEIGHT)
		item:SetPoint("TOPRIGHT", -5, -5 - top - (i - 1) * LIST_ITEM_HEIGHT)
		item.text:SetText(ChoiceText(choice))
		-- The current value is gold, the highlighted one has the gold bar behind it.
		item.text:SetFontObject(choice[1] == currentValue and "GameFontNormal" or "GameFontHighlight")
		item.focus:SetShown(index == listCursor)
		local previous = listChoices[index - 1]
		item.separator:SetShown(i > 1 and previous ~= nil and choice[4] ~= nil and previous[4] ~= choice[4])
		item:Show()
	end
	for i = shown + 1, #list.items do
		list.items[i]:Hide()
	end
	list.empty:SetShown(count == 0)
	-- Arrows when there are more choices above or below.
	list.more:SetText((listOffset > 0 and "|TInterface\\Buttons\\Arrow-Up-Up:14:14|t" or "")
		.. (listOffset + shown < count and "|TInterface\\Buttons\\Arrow-Down-Up:14:14|t" or ""))
	list.more:SetShown(count > shown)
	list:SetHeight(top + math.max(shown, 1) * LIST_ITEM_HEIGHT + 10 + (count > shown and 14 or 0))
end

local function OpenList(row, anchor)
	listRow = row
	listOffset = 0
	list.search:SetText("")
	list.search:SetShown(#row.choices() > LIST_SEARCH_MIN)
	FilterList()
	listCursor = ChoiceIndex(row)
	list:ClearAllPoints()
	list:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
	list:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
	list:Show()
	UpdateList()
end

local function ToggleList(row, anchor)
	if listRow == row then
		CloseList()
	else
		OpenList(row, anchor)
	end
end

local function ActivateRow(row)
	if row.type == "header" then
		return
	elseif row.type == "buttons" then
		row.buttons[row.sub or 1].run()
	elseif row.type == "action" then
		row.run()
	elseif row.dropdown then
		ToggleList(row, rowFrames[cursor].dropdown)
	else
		StepRow(row, 1)
	end
end

-- The flat look: dark panels with thin borders and the gold accent, built from plain textures so it
-- does not depend on the game's dialog art.
local WHITE = "Interface\\Buttons\\WHITE8X8"
local PANEL = { 0.075, 0.075, 0.09, 0.97 }
local SIDE_PANEL = { 0.05, 0.05, 0.062, 1 }
local CONTROL = { 0.13, 0.13, 0.16, 1 }
local CONTROL_HOVER = { 0.19, 0.19, 0.23, 1 }
local EDGE = { 1, 1, 1, 0.1 }

local function Flat(frame, color, edge)
	frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	frame:SetBackdropColor(unpack(color))
	frame:SetBackdropBorderColor(unpack(edge or EDGE))
end

-- A flat button: a dark box that lightens and takes a gold edge under the mouse.
local function CreateFlatButton(parent, width, height, font)
	local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
	button:SetSize(width, height)
	Flat(button, CONTROL)
	local text = button:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
	text:SetPoint("CENTER")
	button:SetFontString(text)
	button:SetScript("OnEnter", function(self)
		self:SetBackdropColor(unpack(CONTROL_HOVER))
		self:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.7)
	end)
	button:SetScript("OnLeave", function(self)
		self:SetBackdropColor(unpack(CONTROL))
		self:SetBackdropBorderColor(unpack(EDGE))
	end)
	return button
end

local function CreateArrow(parent, direction)
	local button = CreateFlatButton(parent, 22, 22, "GameFontNormal")
	button:SetText(direction < 0 and "<" or ">")
	return button
end

-- An on / off switch in place of a checkbox. It keeps SetChecked, so the rows use it the same way.
local function CreateToggle(parent)
	local toggle = CreateFrame("Button", nil, parent, "BackdropTemplate")
	toggle:SetSize(38, 18)
	Flat(toggle, CONTROL)
	toggle.knob = toggle:CreateTexture(nil, "OVERLAY")
	toggle.knob:SetSize(14, 14)
	toggle.knob:SetTexture(WHITE)
	function toggle:SetChecked(on)
		self.knob:ClearAllPoints()
		if on then
			self:SetBackdropColor(GOLD[1] * 0.85, GOLD[2] * 0.85, GOLD[3], 1)
			self:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
			self.knob:SetPoint("RIGHT", -2, 0)
			self.knob:SetVertexColor(0.08, 0.08, 0.1, 1)
		else
			self:SetBackdropColor(unpack(CONTROL))
			self:SetBackdropBorderColor(1, 1, 1, 0.25)
			self.knob:SetPoint("LEFT", 2, 0)
			self.knob:SetVertexColor(0.55, 0.55, 0.6, 1)
		end
	end
	toggle:SetChecked(false)
	return toggle
end

local function CreateRowFrame(index)
	local frame = CreateFrame("Button", nil, window)
	frame:SetHeight(ROW_HEIGHT)
	frame:SetPoint("TOPLEFT", window, "TOPLEFT", 16 + SIDEBAR, ROWS_TOP - (index - 1) * ROW_HEIGHT)
	frame:SetPoint("RIGHT", window, "RIGHT", -16, 0)

	frame.focus = frame:CreateTexture(nil, "BACKGROUND")
	frame.focus:SetAllPoints()
	frame.focus:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.08)
	-- A faint line between rows.
	frame.line = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
	frame.line:SetPoint("BOTTOMLEFT", 8, 0)
	frame.line:SetPoint("BOTTOMRIGHT", -8, 0)
	frame.line:SetHeight(1)
	frame.line:SetColorTexture(1, 1, 1, 0.05)
	frame.focusBar = frame:CreateTexture(nil, "ARTWORK")
	frame.focusBar:SetPoint("TOPLEFT")
	frame.focusBar:SetPoint("BOTTOMLEFT")
	frame.focusBar:SetWidth(3)
	frame.focusBar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)

	frame.label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.label:SetPoint("LEFT", 12, 0)
	-- Stops before the widest control (the action button), so long search results are cut, not overlapped.
	frame.label:SetPoint("RIGHT", -240, 0)
	frame.label:SetJustifyH("LEFT")
	frame.label:SetWordWrap(false)

	frame.check = CreateToggle(frame)
	frame.check:SetPoint("RIGHT", -8, 0)

	frame.prev = CreateArrow(frame, -1)
	frame.next = CreateArrow(frame, 1)
	frame.next:SetPoint("RIGHT", -4, 0)
	frame.value = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.value:SetPoint("RIGHT", frame.next, "LEFT", -4, 0)
	frame.value:SetWidth(170)
	frame.prev:SetPoint("RIGHT", frame.value, "LEFT", -4, 0)

	-- A dropdown in place of the arrows, for choices with many options.
	frame.dropdown = CreateFlatButton(frame, 226, 24)
	frame.dropdown:SetPoint("RIGHT", -4, 0)
	frame.dropdown.arrow = frame.dropdown:CreateTexture(nil, "OVERLAY")
	frame.dropdown.arrow:SetSize(14, 14)
	frame.dropdown.arrow:SetPoint("RIGHT", -7, 0)
	frame.dropdown.arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
	frame.dropdown.text = frame.dropdown:GetFontString()
	frame.dropdown.text:ClearAllPoints()
	frame.dropdown.text:SetPoint("LEFT", 10, 0)
	frame.dropdown.text:SetPoint("RIGHT", frame.dropdown.arrow, "LEFT", -4, 0)
	frame.dropdown.text:SetJustifyH("LEFT")
	frame.dropdown.text:SetWordWrap(false)

	frame.action = CreateFlatButton(frame, 226, 24)
	frame.action:SetPoint("RIGHT", -4, 0)

	-- A row of up to three buttons (type "buttons"); D-pad left / right picks one, A presses it.
	frame.multi = {}
	for i = 1, 3 do
		local button = CreateFlatButton(frame, 112, 24)
		if i == 1 then
			button:SetPoint("RIGHT", -4, 0)
		else
			button:SetPoint("RIGHT", frame.multi[i - 1], "LEFT", -6, 0)
		end
		frame.multi[i] = button
	end

	local function Focus()
		-- Section titles can't be selected.
		if frame.row and frame.row.type == "header" then
			return
		end
		cursor = index
		UpdateRows()
	end
	frame:SetScript("OnEnter", Focus)
	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_, delta)
		local row = frame.row
		if row and (row.type == "number" or row.type == "choice") then
			cursor = index
			StepRow(row, delta > 0 and 1 or -1, IsShiftKeyDown())
		end
	end)
	frame:SetScript("OnClick", function()
		if listRow and listRow ~= frame.row then
			CloseList()
		end
		Focus()
	end)
	frame.dropdown:SetScript("OnClick", function()
		cursor = index
		ToggleList(frame.row, frame.dropdown)
		UpdateRows()
	end)
	frame.check:SetScript("OnClick", function()
		cursor = index
		StepRow(frame.row, 1)
	end)
	frame.prev:SetScript("OnClick", function()
		cursor = index
		StepRow(frame.row, -1, IsShiftKeyDown())
	end)
	frame.next:SetScript("OnClick", function()
		cursor = index
		StepRow(frame.row, 1, IsShiftKeyDown())
	end)
	frame.action:SetScript("OnClick", function()
		cursor = index
		frame.row.run()
	end)
	for _, child in ipairs({ frame.check, frame.prev, frame.next, frame.action, frame.dropdown }) do
		child:HookScript("OnEnter", Focus)
	end
	-- The buttons are laid out right to left; row.buttons is left to right.
	for i, button in ipairs(frame.multi) do
		button:SetScript("OnClick", function()
			local row = frame.row
			local n = #row.buttons - i + 1
			cursor = index
			row.sub = n
			row.buttons[n].run()
			UpdateRows()
		end)
		button:HookScript("OnEnter", function()
			if frame.row and frame.row.buttons then
				frame.row.sub = #frame.row.buttons - i + 1
			end
			Focus()
		end)
	end
	return frame
end

function UpdateRows()
	if not window then
		return
	end
	local rows = CurrentRows()
	cursor = math.max(1, math.min(cursor, #rows))
	-- Never rest on a section title: the next row down, or up at the end.
	while rows[cursor] and rows[cursor].type == "header" and cursor < #rows do
		cursor = cursor + 1
	end
	while rows[cursor] and rows[cursor].type == "header" and cursor > 1 do
		cursor = cursor - 1
	end
	for index, frame in ipairs(rowFrames) do
		local row = rows[index]
		frame.row = row
		frame:SetShown(row ~= nil)
		if row then
			if searchRows then
				frame.label:SetText("|cff8c8c8c" .. row.tabName .. " >|r " .. ButtonText(row.label, 20))
			else
				frame.label:SetText(ButtonText(row.label, 20))
			end
			-- A section title: gold, smaller, with a stronger line under it and no controls.
			local header = row.type == "header"
			frame.label:SetFontObject(header and "GameFontNormalSmall" or "GameFontHighlight")
			frame.line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], header and 0.35 or 0)
			if not header then
				frame.line:SetColorTexture(1, 1, 1, 0.05)
			end
			local buttons = row.type == "buttons" and row.buttons or {}
			row.sub = buttons[1] and math.max(1, math.min(row.sub or 1, #buttons)) or nil
			for i, button in ipairs(frame.multi) do
				local data = buttons[#buttons - i + 1]
				button:SetShown(data ~= nil)
				if data then
					button:SetText(data.danger and ("|cffff7070" .. data.text .. "|r") or data.text)
					local picked = index == cursor and row.sub == #buttons - i + 1
					button:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], picked and 0.9 or 0)
					if not picked then
						button:SetBackdropBorderColor(unpack(EDGE))
					end
				end
			end
			local isFocused = index == cursor and not header
			frame.focus:SetShown(isFocused)
			frame.focusBar:SetShown(isFocused)
			frame.check:SetShown(row.type == "check")
			local dropdown = row.type == "choice" and row.dropdown
			local stepped = (row.type == "choice" or row.type == "number") and not dropdown
			frame.prev:SetShown(stepped)
			frame.next:SetShown(stepped)
			frame.value:SetShown(stepped or row.type == "info")
			frame.dropdown:SetShown(dropdown and true or false)
			frame.action:SetShown(row.type == "action")
			if row.type == "check" then
				frame.check:SetChecked(ns.db[row.key] and true or false)
			elseif row.type == "choice" then
				local choiceIndex, choices = ChoiceIndex(row)
				local text = choices[choiceIndex][2]
				-- "From theme" shows the style the theme picks, marked as coming from the theme.
				if choices[choiceIndex][1] == "theme" and ns.ThemeLook then
					local picked = ns.ThemeLook(row.key)
					for _, choice in ipairs(choices) do
						if choice[1] == picked then
							text = choice[2] .. " |cff8c8c8c(theme)|r"
						end
					end
				end
				frame.value:SetText(text)
				frame.dropdown.text:SetText(choices[choiceIndex][3] and ChoiceText({ nil, text, choices[choiceIndex][3] }) or text)
			elseif row.type == "number" then
				frame.value:SetText(FormatNumber(ns.db[row.key]))
			elseif row.type == "action" then
				frame.action:SetText(row.button)
			elseif row.type == "info" then
				frame.value:SetText(row.value)
			end
		end
	end
	local row = rows[cursor]
	local tip = row and row.tip and ButtonText(row.tip, 15) or ""
	if searchRows and #rows == 0 then
		tip = "No settings match the search."
	elseif searchMore > 0 then
		tip = format("%d more matches are not shown; type more to narrow the search.\n%s", searchMore, tip)
	end
	window.tip:SetText(tip)
	window.defaults:SetText("Reset to defaults")
	for index, button in ipairs(tabButtons) do
		local selected = not searchRows and index == selectedTab
		button.selected:SetShown(selected)
		button.selectedBar:SetShown(selected)
		button.text:SetFontObject(selected and "GameFontHighlight" or "GameFontNormal")
	end
end

-- Finds the rows whose label or description contains every word of the text, on all tabs.
local function Search(text)
	CloseList()
	text = strtrim(text or ""):lower()
	if text == "" then
		searchRows, searchMore = nil, 0
	else
		searchRows, searchMore = {}, 0
		for _, tab in ipairs(tabs) do
			for _, row in ipairs(tab.rows) do
				local haystack = (ButtonText(row.label) .. " " .. ButtonText(row.tip or "") .. " " .. tab.name):lower()
				local matches = true
				for word in text:gmatch("%S+") do
					if not haystack:find(word, 1, true) then
						matches = false
						break
					end
				end
				if matches and row.type ~= "header" then
					row.tabName = tab.name
					if #searchRows < #rowFrames then
						tinsert(searchRows, row)
					else
						searchMore = searchMore + 1
					end
				end
			end
		end
	end
	cursor = 1
	UpdateRows()
end

local function SelectTab(index)
	CloseList()
	if searchRows then
		window.search:SetText("")
		window.search:ClearFocus()
		searchRows, searchMore = nil, 0
	end
	selectedTab = (index - 1) % #tabs + 1
	cursor = 1
	UpdateRows()
	PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
end

local function ResetTab()
	for _, row in ipairs(CurrentRows()) do
		if row.key and ns.DEFAULTS[row.key] ~= nil then
			ns.db[row.key] = ns.DEFAULTS[row.key]
		end
	end
	ns.UpdateMinimapButton()
	ns.RefreshVisuals()
	ns.Sync()
	UpdateRows()
end

-- Controller: these keys work the window while it is open. The bindings belong to the window and are
-- cleared when it closes; bindings cannot change in combat, so the window closes when combat starts.
local NAV_KEYS = {
	PADDUP = "Up", PADDDOWN = "Down", PADDLEFT = "Left", PADDRIGHT = "Right",
	PAD1 = "Accept", PAD2 = "Back", PADFORWARD = "Back",
	PADLSHOULDER = "PrevTab", PADRSHOULDER = "NextTab",
}

local function CreateNavButtons()
	local actions = {
		Up = function()
			if listRow then
				if #listChoices > 0 then
					listCursor = (listCursor - 2) % #listChoices + 1
					UpdateList()
				end
				return
			end
			local rows = CurrentRows() local count = #rows if count == 0 then return end
			repeat cursor = cursor - 1 if cursor < 1 then cursor = count end until rows[cursor].type ~= "header"
			UpdateRows()
		end,
		Down = function()
			if listRow then
				if #listChoices > 0 then
					listCursor = listCursor % #listChoices + 1
					UpdateList()
				end
				return
			end
			local rows = CurrentRows() local count = #rows if count == 0 then return end
			repeat cursor = cursor % count + 1 until rows[cursor].type ~= "header"
			UpdateRows()
		end,
		Left = function() local row = CurrentRows()[cursor] if not listRow and row and row.type ~= "action" then StepRow(row, -1) end end,
		Right = function() local row = CurrentRows()[cursor] if not listRow and row and row.type ~= "action" then StepRow(row, 1) end end,
		Accept = function()
			if listRow then
				if #listChoices > 0 then
					list.Pick(listCursor)
				end
				return
			end
			local row = CurrentRows()[cursor] if row then ActivateRow(row) UpdateRows() end
		end,
		-- B closes an open dropdown first, then the window.
		Back = function()
			if listRow then
				CloseList()
				return
			end
			ns.CloseConfig()
		end,
		PrevTab = function() SelectTab(selectedTab - 1) end,
		NextTab = function() SelectTab(selectedTab + 1) end,
	}
	for name, action in pairs(actions) do
		local button = CreateFrame("Button", "GamepadXIVConfigNav" .. name, window)
		button:RegisterForClicks("AnyDown")
		button:SetScript("OnClick", function()
			-- While the add window is open, the controller works that instead.
			if dialog and dialog:IsShown() then
				dialog.Nav(name)
			else
				action()
			end
		end)
	end
end

local function BindNav()
	if InCombatLockdown() then
		return
	end
	for key, name in pairs(NAV_KEYS) do
		SetOverrideBindingClick(window, true, key, "GamepadXIVConfigNav" .. name, "LeftButton")
	end
end

-- Ring tab: pick a page, then one row per segment. Forever's entries on the first three pages are
-- fixed; free segments take the player's entries. Pages of the player's own can be added, renamed
-- and removed.
local function IconMarkup(entry)
	if entry.atlas and C_Texture.GetAtlasInfo(entry.atlas) then
		return CreateAtlasMarkup(entry.atlas, 22, 22)
	end
	local texture = tonumber(entry.icon) or entry.icon
	if texture == nil or texture == "" then
		texture = "Interface\\Icons\\INV_Misc_QuestionMark"
	end
	return "|T" .. texture .. ":20:20:0:0:64:64:5:59:5:59|t"
end

-- Where each segment sits, counter-clockwise from the right, as the ring draws them. The settings
-- list them clockwise from the top, the way the ring reads.
local SEGMENT_NAMES = { "Right", "Upper right", "Top", "Upper left", "Left", "Lower left", "Bottom", "Lower right" }
local SEGMENT_ORDER = { 3, 2, 1, 8, 7, 6, 5, 4 }

local ringEditPage = 2
local ringResetArmed = false
local RebuildRingRows
local function RefreshRing()
	ns.UpdateRing()
	RebuildRingRows()
	UpdateRows()
end

local OpenEntryDialog, OpenPageDialog

function RebuildRingRows()
	local ringTab
	for _, tab in ipairs(tabs) do
		if tab.ring then
			ringTab = tab
		end
	end
	if not ringTab then
		return
	end
	local pages = ns.RingPages()
	ringEditPage = math.max(1, math.min(ringEditPage, #pages))
	local pageIndex = ringEditPage
	local pageName = ns.RingPageName(pageIndex)
	local rows = {
		{ type = "header", label = "RING SETTINGS" },
		{
			type = "check", key = "ringReleaseToUse", label = "Use an entry by letting go of the stick",
			tip = "On: point the right stick at an entry and let go to use it, like Forever's own ring. Off: pointing only highlights the entry and {PAD1} uses it, so nothing opens by accident. {PAD1} works either way.",
		},
		{ type = "header", label = "RING PAGES" },
		{
			-- Arrows rather than a list, so the page being edited and how many there are always show.
			type = "choice", dropdown = false, label = format("Editing page  |cffffd100%d|r of %d", pageIndex, #pages),
			choices = function()
				local list = {}
				for index = 1, #ns.db.ringPages do
					tinsert(list, { index, ns.RingPageName(index) })
				end
				return list
			end,
			get = function() return ringEditPage end,
			set = function(value)
				ringEditPage = value
				RebuildRingRows()
			end,
			tip = "{PADDLEFT} / {PADDRIGHT} switch the page you are editing. In the ring itself ({PADRSHOULDER} + {PADRSTICK} by default), {PADLSHOULDER} / {PADRSHOULDER} turn the pages.",
		},
	}
	local pageButtons = {
		{ text = "+ New page", run = function() OpenPageDialog(nil) end },
		{ text = "Rename", run = function() OpenPageDialog(pageIndex) end },
	}
	if #pages > 1 then
		tinsert(pageButtons, { text = "Delete", danger = true, run = function()
			tremove(pages, pageIndex)
			ringEditPage = math.max(1, pageIndex - 1)
			RefreshRing()
		end })
	end
	tinsert(rows, {
		type = "buttons", label = "This page", buttons = pageButtons,
		tip = "New page adds an empty page after the others. Rename names the one you are editing; Delete removes it and everything on it. {PADDLEFT} / {PADDRIGHT} pick a button, {PAD1} presses it.",
	})
	tinsert(rows, { type = "header", label = "ON " .. pageName:upper() .. "  |cff8c8c8c(clockwise from the top)|r" })
	for _, segment in ipairs(SEGMENT_ORDER) do
		local data = pages[pageIndex].slots[segment]
		local entry = data and ns.RingResolve(data)
		local where = "|cffb0b0b0" .. SEGMENT_NAMES[segment] .. "|r   "
		local shown = entry and (IconMarkup(entry) .. "  " .. entry.label .. (data.builtin == "gxiv" and " settings" or "")) or "?"
		if data then
			local detail = ""
			if entry and entry.missing then
				detail = "  |cffff6060(not loaded)|r"
			elseif data.command and not data.addon then
				detail = "  |cff8c8c8c" .. data.command .. "|r"
			end
			tinsert(rows, {
				type = "action",
				label = where .. shown .. detail,
				button = "Change...",
				tip = "Pick something else for this segment, or empty it.",
				run = function()
					OpenEntryDialog(pageIndex, segment, entry and entry.label or "this", (data.command and not data.addon) and data or nil)
				end,
			})
		else
			tinsert(rows, {
				type = "action",
				label = where .. "|cff6f6f6fEmpty|r",
				button = "+ Add",
				tip = "Puts one of the game's windows, an installed addon, a toy or this addon's settings in this segment.",
				run = function() OpenEntryDialog(pageIndex, segment) end,
			})
		end
	end
	tinsert(rows, { type = "header", label = "START OVER" })
	tinsert(rows, {
		type = "action", label = "Reset the ring", button = "|cffff7070Reset|r",
		tip = "Puts back Forever's three main menu pages and removes everything you added. Press twice to confirm.",
		run = function()
			if ringResetArmed then
				ringResetArmed = false
				ns.RingReset()
				ringEditPage = 2
				RefreshRing()
			else
				ringResetArmed = true
				ns.Print("Press Reset again to put the ring back to Forever's pages.")
				C_Timer.After(5, function() ringResetArmed = false end)
			end
		end,
	})
	ringTab.rows = rows
end

-- A window over the settings.
--   pick:    what goes in a ring segment, from a list with a search box: the game's windows, the
--            installed addons, this addon's settings and, last, Advanced: a slash command.
--   command: the Advanced form, a name, a slash command and an optional icon.
--   page:    a page's name.
local PICK_ROW_HEIGHT = 36
local PICK_ROWS = 9
local GEAR_ICON = "Interface\\Icons\\INV_Misc_Gear_01"
local EMPTY_ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"

local function CreateDialog()
	dialog = CreateFrame("Frame", nil, window, "BackdropTemplate")
	dialog:SetSize(540, 120 + PICK_ROWS * PICK_ROW_HEIGHT)
	dialog:SetPoint("CENTER")
	dialog:SetFrameStrata("FULLSCREEN_DIALOG")
	dialog:EnableMouse(true)
	Flat(dialog, { 0.08, 0.08, 0.1, 0.99 }, { GOLD[1], GOLD[2], GOLD[3], 0.6 })
	dialog:Hide()

	dialog.title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	dialog.title:SetPoint("TOPLEFT", 16, -14)
	dialog.title:SetPoint("RIGHT", -16, 0)
	dialog.title:SetJustifyH("LEFT")
	dialog.title:SetWordWrap(false)

	-- Pick mode: the search box and the list.
	local picker = CreateFrame("Frame", nil, dialog)
	picker:SetPoint("TOPLEFT", 0, -40)
	picker:SetPoint("BOTTOMRIGHT", 0, 46)

	-- "Select a toy" and the other choices open a window of their own over this one, with its own
	-- search; the list and its search box move into it while it is open.
	local subWindow = CreateFrame("Frame", nil, window, "BackdropTemplate")
	subWindow:SetSize(560, 120 + PICK_ROWS * PICK_ROW_HEIGHT)
	subWindow:SetPoint("CENTER", dialog, "CENTER", 18, -18)
	subWindow:SetFrameStrata("FULLSCREEN_DIALOG")
	subWindow:SetFrameLevel(dialog:GetFrameLevel() + 40)
	subWindow:EnableMouse(true)
	Flat(subWindow, { 0.09, 0.09, 0.11, 1 }, { GOLD[1], GOLD[2], GOLD[3], 0.8 })
	subWindow:Hide()
	subWindow.title = subWindow:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	subWindow.title:SetPoint("TOPLEFT", 16, -14)
	subWindow.title:SetPoint("RIGHT", -16, 0)
	subWindow.title:SetJustifyH("LEFT")
	subWindow.title:SetWordWrap(false)
	subWindow.hint = subWindow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	subWindow.hint:SetPoint("BOTTOMLEFT", 16, 16)
	subWindow.back = CreateFlatButton(subWindow, 90, 24)
	subWindow.back:SetPoint("BOTTOMRIGHT", -16, 12)
	subWindow.back:SetText("Back")
	subWindow.back:SetScript("OnClick", function() dialog.Nav("Back") end)
	local search = CreateFrame("EditBox", "GamepadXIVRingPickSearch", picker, "SearchBoxTemplate")
	search:SetHeight(22)
	search:SetPoint("TOPLEFT", 22, -4)
	search:SetPoint("TOPRIGHT", -16, -4)
	search:SetAutoFocus(false)
	dialog.search = search
	local items, shown, pickCursor, pickOffset = {}, {}, 1, 0
	local folder -- the open section (abilities, bag items, macros, toys), or nil for the main list
	local rows = {}
	local empty = picker:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	empty:SetPoint("TOP", 0, -48)
	empty:SetText("Nothing matches. Advanced: slash command lets you add anything.")
	local more = picker:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	more:SetPoint("BOTTOMRIGHT", -18, -2)

	local function UpdatePicker()
		local count = #shown
		pickCursor = math.max(1, math.min(pickCursor, count))
		local visible = math.min(count, PICK_ROWS)
		if pickCursor <= pickOffset then
			pickOffset = pickCursor - 1
		elseif pickCursor > pickOffset + visible then
			pickOffset = pickCursor - visible
		end
		pickOffset = math.max(0, math.min(pickOffset, count - visible))
		for i = 1, PICK_ROWS do
			local row = rows[i]
			local index = pickOffset + i
			local item = shown[index]
			if item then
				row.icon:SetText(item.markup)
				row.name:SetText(item.label)
				row.name:SetFontObject(item.remove and "GameFontRed" or "GameFontHighlight")
				row.detail:SetText(item.detail or "")
				row.focus:SetShown(index == pickCursor)
				local previous = shown[index - 1]
				row.separator:SetShown(i > 1 and previous ~= nil and previous.group ~= item.group)
				row:Show()
			else
				row:Hide()
			end
		end
		empty:SetShown(count == 0)
		more:SetText((pickOffset > 0 and "|TInterface\\Buttons\\Arrow-Up-Up:14:14|t" or "")
			.. (pickOffset + visible < count and "|TInterface\\Buttons\\Arrow-Down-Up:14:14|t" or ""))
	end

	local function Matches(item, text)
		return text == "" or item.label:lower():find(text, 1, true) or (item.detail and item.detail:lower():find(text, 1, true))
	end

	-- In a section: its entries. In the main list: the entries matching the search, and while
	-- searching, the matching entries inside every section too. Advanced and "empty" always stay,
	-- so there is a way on with any search.
	local function Filter()
		local text = strtrim(search:GetText() or ""):lower()
		wipe(shown)
		if folder then
			for _, item in ipairs(folder.children) do
				if Matches(item, text) then
					tinsert(shown, item)
				end
			end
		else
			local advanced
			for _, item in ipairs(items) do
				if item.advanced then
					advanced = item
				elseif item.remove or Matches(item, text) then
					tinsert(shown, item)
				end
			end
			if text ~= "" then
				for _, item in ipairs(items) do
					for _, child in ipairs(item.children or {}) do
						if Matches(child, text) then
							tinsert(shown, child)
						end
					end
				end
			end
			tinsert(shown, advanced)
		end
		pickCursor, pickOffset = 1, 0
		UpdatePicker()
	end
	search:HookScript("OnTextChanged", Filter)
	search:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
	end)
	search:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)

	local Choose
	for i = 1, PICK_ROWS do
		local row = CreateFrame("Button", nil, picker)
		row:SetHeight(PICK_ROW_HEIGHT)
		row:SetPoint("TOPLEFT", 12, -32 - (i - 1) * PICK_ROW_HEIGHT)
		row:SetPoint("TOPRIGHT", -12, -32 - (i - 1) * PICK_ROW_HEIGHT)
		row.focus = row:CreateTexture(nil, "BACKGROUND")
		row.focus:SetAllPoints()
		row.focus:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.18)
		row.separator = row:CreateTexture(nil, "ARTWORK")
		row.separator:SetHeight(1)
		row.separator:SetPoint("TOPLEFT", 4, 0)
		row.separator:SetPoint("TOPRIGHT", -4, 0)
		row.separator:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.35)
		row.icon = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.icon:SetPoint("LEFT", 8, 0)
		row.icon:SetWidth(32)
		row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.name:SetPoint("TOPLEFT", 48, -4)
		row.name:SetPoint("RIGHT", -8, 0)
		row.name:SetJustifyH("LEFT")
		row.name:SetWordWrap(false)
		row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		row.detail:SetPoint("BOTTOMLEFT", 48, 5)
		row.detail:SetPoint("RIGHT", -8, 0)
		row.detail:SetJustifyH("LEFT")
		row.detail:SetWordWrap(false)
		row:SetScript("OnEnter", function()
			pickCursor = pickOffset + i
			UpdatePicker()
		end)
		row:SetScript("OnClick", function()
			Choose(shown[pickOffset + i])
		end)
		rows[i] = row
	end
	picker:EnableMouseWheel(true)
	picker:SetScript("OnMouseWheel", function(_, delta)
		pickCursor = math.max(1, math.min(#shown, pickCursor - delta * 3))
		UpdatePicker()
	end)

	-- Command mode (Advanced) and page mode: text fields.
	local form = CreateFrame("Frame", nil, dialog)
	form:SetPoint("TOPLEFT", 0, -40)
	form:SetPoint("BOTTOMRIGHT", 0, 46)
	local fields, shownFields = {}, {}
	local function Field(key, label, y)
		local holder = CreateFrame("Frame", nil, form)
		holder:SetSize(508, 44)
		holder:SetPoint("TOPLEFT", 16, y)
		local text = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		text:SetPoint("TOPLEFT")
		text:SetText(label)
		local box = CreateFrame("EditBox", nil, holder, "BackdropTemplate")
		box:SetSize(508, 26)
		box:SetPoint("TOPLEFT", 0, -16)
		Flat(box, CONTROL)
		box:SetFontObject(ChatFontNormal)
		box:SetTextInsets(8, 8, 0, 0)
		box:SetAutoFocus(false)
		box:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.9) end)
		box:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(unpack(EDGE)) end)
		box:SetScript("OnEscapePressed", function() dialog.Nav("Back") end)
		box.holder = holder
		dialog[key] = box
		tinsert(fields, box)
		return box
	end
	Field("name", "Name on the ring", -8)
	Field("command", "Slash command, for example /details or /dbm", -58)
	Field("icon", "Icon (optional): a texture path such as Interface\\Icons\\INV_Misc_Gear_01, or a file ID", -108)
	local formHelp = form:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	formHelp:SetPoint("TOPLEFT", 16, -164)
	formHelp:SetPoint("RIGHT", -16, 0)
	formHelp:SetJustifyH("LEFT")
	formHelp:SetText("Runs the command as if you typed it in chat. Most addons list theirs in their description or with /help.")

	dialog.error = dialog:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
	dialog.error:SetPoint("BOTTOMLEFT", 16, 52)
	dialog.error:SetPoint("RIGHT", -16, 0)
	dialog.error:SetJustifyH("LEFT")

	-- Footer: the controller hint on the left, the buttons on the right.
	local hint = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hint:SetPoint("BOTTOMLEFT", 16, 16)
	local add = CreateFlatButton(dialog, 90, 24)
	add:SetPoint("BOTTOMRIGHT", -16, 12)
	dialog.add = add
	local cancel = CreateFlatButton(dialog, 90, 24)
	cancel:SetPoint("RIGHT", add, "LEFT", -8, 0)
	cancel:SetScript("OnClick", function() dialog.Nav("Back") end)

	local function Place(data)
		local pages = ns.RingPages()
		pages[dialog.pageIndex].slots[dialog.segment] = data
		dialog:Hide()
		RefreshRing()
	end

	local function Layout()
		local mode = dialog.mode
		picker:SetShown(mode == "pick")
		form:SetShown(mode ~= "pick")
		add:SetShown(mode ~= "pick")
		cancel:SetText((mode == "command" or folder) and "Back" or "Cancel")
		cancel:ClearAllPoints()
		if mode == "pick" then
			cancel:SetPoint("BOTTOMRIGHT", -16, 12)
		else
			cancel:SetPoint("RIGHT", add, "LEFT", -8, 0)
		end
		wipe(shownFields)
		for _, box in ipairs(fields) do
			local show = mode == "command" or (mode == "page" and box == dialog.name)
			box.holder:SetShown(show)
			if show then
				tinsert(shownFields, box)
			end
		end
		formHelp:SetShown(mode == "command")
		if mode == "pick" then
			hint:SetText(ButtonText("{PADDUP}{PADDDOWN} choose   {PAD1} select   {PAD2} " .. (folder and "back" or "cancel"), 18))
			for _, box in ipairs(fields) do
				box:ClearFocus()
			end
		else
			hint:SetText(ButtonText("{PAD1} " .. (mode == "page" and "save" or "add") .. "   {PAD2} " .. (mode == "command" and "back" or "cancel"), 18))
			search:ClearFocus()
			if shownFields[1] and not (shownFields[1]:HasFocus() or (shownFields[2] and shownFields[2]:HasFocus()) or (shownFields[3] and shownFields[3]:HasFocus())) then
				shownFields[1]:SetFocus()
			end
		end
		dialog.error:SetText("")
	end

	local function Submit()
		local name = strtrim(dialog.name:GetText()):gsub("|", "")
		if dialog.mode == "page" then
			local pages = ns.RingPages()
			if name == "" then
				dialog.error:SetText("Give the page a name.")
				return
			end
			if dialog.pageIndex then
				pages[dialog.pageIndex].name = name
			else
				tinsert(pages, { name = name, slots = {} })
				ringEditPage = #pages
			end
			dialog:Hide()
			RefreshRing()
			return
		end
		local command = strtrim(dialog.command:GetText())
		local icon = strtrim(dialog.icon:GetText()):gsub("|", "")
		if name == "" then
			dialog.error:SetText("Give the entry a name.")
			return
		end
		if not command:match("^/%S") then
			dialog.error:SetText("The command starts with /, like /details.")
			return
		end
		Place({ label = name, command = command, icon = icon ~= "" and icon or nil })
	end
	dialog.Submit = Submit
	add:SetScript("OnClick", Submit)

	function Choose(item)
		if not item then
			return
		end
		if item.advanced then
			dialog.mode = "command"
			Layout()
			return
		end
		if item.children then
			dialog.OpenFolder(item)
			return
		end
		Place(item.data)
	end
	dialog.Choose = function() Choose(shown[pickCursor]) end

	-- Tab and Enter move through the fields; Enter on the last one submits.
	for _, box in ipairs(fields) do
		box:SetScript("OnTabPressed", function()
			local n = tIndexOf(shownFields, box) or 0
			shownFields[n % #shownFields + 1]:SetFocus()
		end)
		box:SetScript("OnEnterPressed", function()
			local n = tIndexOf(shownFields, box) or #shownFields
			if shownFields[n + 1] then
				shownFields[n + 1]:SetFocus()
			else
				Submit()
			end
		end)
	end

	-- The controller. In the list: up / down choose, left / right jump a screen, A adds, B cancels.
	-- In the fields: up / down move between them, A adds or saves, B goes back to the list or closes.
	dialog.Nav = function(name)
		if dialog.mode == "pick" then
			local count = #shown
			if (name == "Up" or name == "Down") and count > 0 then
				pickCursor = (pickCursor - 1 + (name == "Up" and -1 or 1)) % count + 1
				UpdatePicker()
			elseif (name == "Left" or name == "Right") and count > 0 then
				pickCursor = math.max(1, math.min(count, pickCursor + (name == "Left" and -PICK_ROWS or PICK_ROWS)))
				UpdatePicker()
			elseif name == "Accept" then
				dialog.Choose()
			elseif name == "Back" then
				if folder then
					dialog.CloseFolder()
				else
					dialog:Hide()
				end
			end
			return
		end
		local focused = 1
		for n, box in ipairs(shownFields) do
			if box:HasFocus() then
				focused = n
			end
		end
		if (name == "Up" or name == "Down") and #shownFields > 0 then
			local step = name == "Up" and -2 or 0
			shownFields[(focused + step) % #shownFields + 1]:SetFocus()
		elseif name == "Accept" then
			Submit()
		elseif name == "Back" then
			if dialog.mode == "command" then
				dialog.mode = "pick"
				Layout()
			else
				dialog:Hide()
			end
		end
	end
	local function PlacePicker(parent)
		picker:SetParent(parent)
		picker:ClearAllPoints()
		picker:SetPoint("TOPLEFT", 0, -40)
		picker:SetPoint("BOTTOMRIGHT", 0, 46)
	end
	function dialog.OpenFolder(item)
		folder = item
		PlacePicker(subWindow)
		subWindow.title:SetText(item.name .. "  |cff8c8c8c·  " .. SEGMENT_NAMES[dialog.segment] .. "|r")
		subWindow.hint:SetText(ButtonText("{PADDUP}{PADDDOWN} choose   {PAD1} add   {PAD2} back", 18))
		dialog:SetAlpha(0.45)
		subWindow:Show()
		search:SetText("")
		Filter()
	end
	-- Back to the main list; quiet when the add window itself closes.
	function dialog.CloseFolder(quiet)
		folder = nil
		PlacePicker(dialog)
		subWindow:Hide()
		dialog:SetAlpha(1)
		if not quiet then
			search:SetText("")
			Filter()
			Layout()
		end
	end
	dialog:SetScript("OnHide", function()
		for _, box in ipairs(fields) do
			box:ClearFocus()
		end
		search:ClearFocus()
		if folder then
			dialog.CloseFolder(true)
		end
	end)

	-- Everything that can go in a segment, in groups: the game's windows, the installed addons, this
	-- addon's settings, then Advanced. Changing a filled segment offers to empty it first.
	local function BuildItems(current)
		wipe(items)
		if current then
			tinsert(items, { group = "remove", remove = true, label = "Empty this segment",
				detail = "Takes " .. current .. " off the ring", markup = "|T" .. EMPTY_ICON .. ":26:26|t", data = nil })
		end
		for _, key in ipairs(ns.RING_BUILTIN_ORDER) do
			local entry = key ~= "gxiv" and ns.RingResolve(key)
			if entry then
				tinsert(items, { group = "game", label = entry.label, detail = "Game window", markup = IconMarkup(entry), data = { builtin = key } })
			end
		end
		-- Sections, each opening a list of its own; empty ones are left out.
		local sections = {
			{ "Select a toy", "toys", "Interface\\Icons\\INV_Misc_Toy_10", ns.RingToyChoices, "toys, or the whole Toy Box" },
			{ "Select a macro", "macros", "Interface\\Icons\\INV_Misc_Note_01", ns.RingMacroChoices, "account and character macros" },
			{ "Select an item", "items", "Interface\\Icons\\INV_Misc_Bag_08", ns.RingItemChoices, "items in your bags" },
			{ "Select an ability", "abilities", "Interface\\Icons\\INV_Misc_Book_09", ns.RingSpellChoices, "abilities, at the highest rank you know" },
			{ "Select an emote", "emotes", "Interface\\Icons\\Spell_Shadow_Charm", ns.RingEmoteChoices, "emotes" },
			{ "Select an equipment", "equipment", "Interface\\Icons\\INV_Chest_Chain", ns.RingEquipmentSetChoices, "sets from the Equipment Manager" },
		}
		for _, section in ipairs(sections) do
			local children = {}
			for _, choice in ipairs(section[4]()) do
				tinsert(children, { group = section[2], label = choice.label, detail = choice.detail,
					markup = IconMarkup({ icon = choice.icon }), data = choice.data })
			end
			-- The Toy Box itself comes first: one entry that opens every toy on the ring.
			if section[2] == "toys" and #children > 0 then
				tinsert(children, 1, { group = "toybox", label = "Toy Box", detail = "All your toys on the ring, 8 a page",
					markup = "|TInterface\\Icons\\INV_Misc_Toy_10:26:26:0:0:64:64:5:59:5:59|t", data = { toybox = true } })
			end
			if #children > 0 then
				tinsert(items, { group = "sections", name = section[1], children = children,
					label = section[1] .. "  |TInterface\\ChatFrame\\ChatFrameExpandArrow:14:14|t",
					detail = (section[2] == "toys" and (#children - 1) or #children) .. " " .. section[5], markup = "|T" .. section[3] .. ":26:26:0:0:64:64:5:59:5:59|t" })
			end
		end
		for _, addon in ipairs(ns.RingAddOnChoices()) do
			local markup = IconMarkup({ icon = addon.icon })
			tinsert(items, { group = "addon", label = addon.label, detail = addon.detail, markup = markup, data = addon.data })
		end
		local settings = ns.RingResolve("gxiv")
		tinsert(items, { group = "gxiv", label = settings.label .. " settings", detail = "This window", markup = IconMarkup(settings), data = { builtin = "gxiv" } })
		tinsert(items, { group = "advanced", advanced = true, label = "Advanced: slash command",
			detail = "Type a command yourself, for an addon not listed here", markup = "|T" .. GEAR_ICON .. ":26:26:0:0:64:64:5:59:5:59|t" })
	end

	local function Open(mode, title, button)
		CloseList()
		dialog.mode = mode
		dialog.title:SetText(title)
		add:SetText(button)
		for _, box in ipairs(fields) do
			box:SetText("")
			box:ClearFocus()
		end
		search:SetText("")
		dialog:Show()
		Layout()
	end

	-- current: the label of what the segment holds now, to offer emptying it; custom: a slash
	-- command entry of the player's, to fill the Advanced form with.
	function OpenEntryDialog(pageIndex, segment, current, custom)
		dialog.pageIndex, dialog.segment = pageIndex, segment
		BuildItems(current)
		local verb = current and "Change" or "Add to"
		folder = nil
		dialog.baseTitle = verb .. " " .. ns.RingPageName(pageIndex) .. "  |cff8c8c8c·  " .. SEGMENT_NAMES[segment] .. "|r"
		Open("pick", dialog.baseTitle, "Add")
		Filter()
		if custom then
			dialog.name:SetText(custom.label or "")
			dialog.command:SetText(custom.command or "")
			dialog.icon:SetText(custom.icon and tostring(custom.icon) or "")
		end
	end

	function OpenPageDialog(pageIndex)
		dialog.pageIndex = pageIndex or false
		Open("page", pageIndex and "Rename the page" or "Add a page", pageIndex and "Save" or "Add")
		if pageIndex then
			dialog.name:SetText(ns.RingPageName(pageIndex))
		end
	end
end

local function CreateWindow()
	tabs = BuildTabs()
	window = CreateFrame("Frame", "GamepadXIVConfigFrame", UIParent, "BackdropTemplate")
	Flat(window, PANEL, { GOLD[1], GOLD[2], GOLD[3], 0.35 })
	window:SetSize(WIDTH, HEIGHT)
	window:SetPoint("CENTER")
	window:SetFrameStrata("DIALOG")
	window:SetToplevel(true)
	window:SetClampedToScreen(true)
	window:EnableMouse(true)
	window:SetMovable(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", window.StopMovingOrSizing)
	window:Hide()

	-- The title bar: the addon's icon and name, and a close button.
	local titleBar = window:CreateTexture(nil, "BACKGROUND", nil, 1)
	titleBar:SetPoint("TOPLEFT", 1, -1)
	titleBar:SetPoint("TOPRIGHT", -1, -1)
	titleBar:SetHeight(TITLE_HEIGHT)
	titleBar:SetColorTexture(0.1, 0.1, 0.125, 1)
	local titleLine = window:CreateTexture(nil, "ARTWORK")
	titleLine:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT")
	titleLine:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT")
	titleLine:SetHeight(1)
	titleLine:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.35)
	local titleIcon = window:CreateTexture(nil, "ARTWORK")
	titleIcon:SetSize(20, 20)
	titleIcon:SetPoint("LEFT", titleBar, "LEFT", 12, 0)
	titleIcon:SetTexture(ns.ICON)
	local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("LEFT", titleIcon, "RIGHT", 8, 0)
	title:SetText("Gamepad XIV")
	local close = CreateFlatButton(window, 24, 24, "GameFontNormal")
	close:SetPoint("RIGHT", titleBar, "RIGHT", -6, 0)
	close:SetText("X")
	close:SetScript("OnClick", function() window:Hide() end)

	RebuildRingRows()
	-- The menu ring tab grows with the entries: the settings entry, up to 11 entries and the add row.
	local maxRows = 13
	for _, tab in ipairs(tabs) do
		maxRows = math.max(maxRows, #tab.rows)
	end
	rowFrames = {}
	for index = 1, maxRows do
		rowFrames[index] = CreateRowFrame(index)
	end

	list = CreateFrame("Frame", nil, window, "BackdropTemplate")
	list:SetFrameStrata("FULLSCREEN_DIALOG")
	list:SetClampedToScreen(true)
	list:EnableMouse(true)
	Flat(list, { 0.06, 0.06, 0.075, 0.98 }, { GOLD[1], GOLD[2], GOLD[3], 0.6 })
	list:Hide()
	list.items = {}
	list.Pick = function(i)
		local row, choice = listRow, listChoices[i]
		CloseList()
		if row and choice then
			SetValue(row, choice[1])
		end
		UpdateRows()
	end
	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(_, delta)
		if listRow then
			listCursor = math.max(1, math.min(#listChoices, listCursor - delta * 3))
			UpdateList()
		end
	end)
	-- Typing filters the choices; the controller keeps moving through what is left.
	list.search = CreateFrame("EditBox", "GamepadXIVConfigListSearch", list, "SearchBoxTemplate")
	list.search:SetHeight(22)
	list.search:SetPoint("TOPLEFT", 12, -8)
	list.search:SetPoint("TOPRIGHT", -8, -8)
	list.search:SetAutoFocus(false)
	list.search:HookScript("OnTextChanged", function()
		if listRow then
			FilterList()
			listCursor, listOffset = 1, 0
			UpdateList()
		end
	end)
	list.search:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		if listRow and #listChoices > 0 then
			list.Pick(listCursor)
		end
	end)
	list.search:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
		CloseList()
	end)
	list.empty = list:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	list.empty:SetPoint("TOPLEFT", 13, -5 - LIST_SEARCH_HEIGHT - 4)
	list.empty:SetText("No matches")
	list.more = list:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	list.more:SetPoint("BOTTOM", 0, 4)

	window.tip = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	window.tip:SetPoint("BOTTOMLEFT", 24 + SIDEBAR, 56)
	window.tip:SetPoint("BOTTOMRIGHT", -24, 56)
	window.tip:SetHeight(40)
	window.tip:SetJustifyH("LEFT")
	window.tip:SetJustifyV("TOP")

	window.hint = window:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	window.hint:SetPoint("LEFT", window, "BOTTOMLEFT", 20, 23)
	-- Redrawn on every show and when another controller is plugged in, so the icons match it.
	window.UpdateHint = function()
		-- Each hint is its buttons right next to their word, with a divider before the next one, so
		-- no button reads as belonging to the wrong word.
		local hints = {
			{ "{PADDUP}{PADDDOWN}", "rows" },
			{ "{PADDLEFT}{PADDRIGHT}", "change" },
			{ "{PAD1}", "pick" },
			{ "{PADLSHOULDER}{PADRSHOULDER}", "tabs" },
			{ "{PAD2}", "close" },
		}
		local parts = {}
		for _, hint in ipairs(hints) do
			tinsert(parts, ButtonText(hint[1], 22) .. " |cffd0d0d0" .. hint[2] .. "|r")
		end
		window.hint:SetText(table.concat(parts, "    |cff4d4d4d|||r    "))
	end
	if InputDeviceIconSetManager then
		InputDeviceIconSetManager:RegisterActiveInputDeviceIconSetUpdatedCallback(function()
			if window:IsShown() then
				window.UpdateHint()
				UpdateRows()
			end
		end, window)
	end

	-- At the foot of the tab column, where it reads as part of the tab it resets, clear of the hints.
	local defaults = CreateFlatButton(window, SIDEBAR - 24, 26, "GameFontHighlightSmall")
	window.defaults = defaults
	defaults:SetPoint("BOTTOM", window, "BOTTOMLEFT", SIDEBAR / 2, 60)
	-- Named after what it resets: the open tab, or the search results. UpdateRows sets the text.
	defaults:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(searchRows and "Reset the found settings" or ("Reset the " .. tabs[selectedTab].name .. " tab"))
		GameTooltip:AddLine(searchRows and "Puts the settings found by the search back to their defaults."
			or ("Puts every setting on the " .. tabs[selectedTab].name .. " tab back to its default."), 1, 1, 1, true)
		GameTooltip:Show()
	end)
	defaults:HookScript("OnLeave", function() GameTooltip:Hide() end)
	defaults:SetScript("OnClick", ResetTab)

	-- The column on the left: a search box, then one button per tab.
	local sidebar = window:CreateTexture(nil, "BACKGROUND", nil, 1)
	sidebar:SetPoint("TOPLEFT", 1, -1 - TITLE_HEIGHT - 1)
	sidebar:SetPoint("BOTTOMLEFT", 1, 47)
	sidebar:SetWidth(SIDEBAR - 1)
	sidebar:SetColorTexture(unpack(SIDE_PANEL))
	local divider = window:CreateTexture(nil, "ARTWORK")
	divider:SetPoint("TOPLEFT", SIDEBAR, -TITLE_HEIGHT - 2)
	divider:SetPoint("BOTTOMLEFT", SIDEBAR, 47)
	divider:SetWidth(1)
	divider:SetColorTexture(1, 1, 1, 0.08)
	-- The bottom strip with the controller hint and the reset button.
	local footer = window:CreateTexture(nil, "BACKGROUND", nil, 2)
	footer:SetPoint("BOTTOMLEFT", 1, 1)
	footer:SetPoint("BOTTOMRIGHT", -1, 1)
	footer:SetHeight(45)
	footer:SetColorTexture(0.1, 0.1, 0.125, 1)
	local footerLine = window:CreateTexture(nil, "ARTWORK")
	footerLine:SetPoint("BOTTOMLEFT", 1, 46)
	footerLine:SetPoint("BOTTOMRIGHT", -1, 46)
	footerLine:SetHeight(1)
	footerLine:SetColorTexture(1, 1, 1, 0.08)

	local search = CreateFrame("EditBox", "GamepadXIVConfigSearch", window, "SearchBoxTemplate")
	search:SetSize(SIDEBAR - 34, 22)
	search:SetPoint("TOPLEFT", 20, -TITLE_HEIGHT - 14)
	search:SetAutoFocus(false)
	search:HookScript("OnTextChanged", function(self)
		Search(self:GetText())
	end)
	search:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
	end)
	window.search = search

	tabButtons = {}
	for index, tab in ipairs(tabs) do
		local button = CreateFrame("Button", nil, window)
		button:SetSize(SIDEBAR - 16, 34)
		button:SetPoint("TOPLEFT", window, "TOPLEFT", 8, -TITLE_HEIGHT - 50 - (index - 1) * 38)
		button.selected = button:CreateTexture(nil, "BACKGROUND")
		button.selected:SetAllPoints()
		button.selected:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.13)
		button.selectedBar = button:CreateTexture(nil, "ARTWORK")
		button.selectedBar:SetPoint("TOPLEFT")
		button.selectedBar:SetPoint("BOTTOMLEFT")
		button.selectedBar:SetWidth(3)
		button.selectedBar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
		local hover = button:CreateTexture(nil, "HIGHLIGHT")
		hover:SetAllPoints()
		hover:SetColorTexture(1, 1, 1, 0.06)
		button.icon = button:CreateTexture(nil, "ARTWORK")
		button.icon:SetSize(22, 22)
		button.icon:SetPoint("LEFT", 12, 0)
		button.icon:SetTexture(tab.icon)
		button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		button.text:SetPoint("LEFT", button.icon, "RIGHT", 10, 0)
		button.text:SetPoint("RIGHT", -6, 0)
		button.text:SetJustifyH("LEFT")
		button.text:SetText(tab.name)
		button:SetScript("OnClick", function() SelectTab(index) end)
		tabButtons[index] = button
	end

	CreateNavButtons()
	CreateDialog()
	window:SetScript("OnShow", function()
		RebuildRingRows()
		window.UpdateHint()
		BindNav()
		UpdateRows()
	end)
	window:SetScript("OnHide", function()
		CloseList()
		dialog:Hide()
		if not InCombatLockdown() then
			ClearOverrideBindings(window)
		end
	end)
	-- Bindings can still be changed while this event runs, just before combat locks them.
	window:RegisterEvent("PLAYER_REGEN_DISABLED")
	window:SetScript("OnEvent", function()
		window:Hide()
	end)
end

-- A page in the game's AddOns options that only opens this window.
local function RegisterOptionsPage()
	local page = CreateFrame("Frame")
	local text = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("TOPLEFT", 16, -16)
	text:SetText("Gamepad XIV has its own settings window.")
	local open = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	open:SetSize(200, 26)
	open:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -12)
	open:SetText("Open settings")
	open:SetScript("OnClick", function() ns.OpenConfig() end)
	local category = Settings.RegisterCanvasLayoutCategory(page, "Gamepad XIV")
	Settings.RegisterAddOnCategory(category)
end

function ns.CreateConfig()
	CreateWindow()
	RegisterOptionsPage()
end

function ns.CloseConfig()
	if window then
		window:Hide()
	end
end

-- Opens the window, or closes it if it is open.
function ns.OpenConfig()
	if InCombatLockdown() then
		ns.Print("Settings are not available in combat.")
		return
	end
	if not window then
		return
	end
	if window:IsShown() then
		window:Hide()
		return
	end
	if ns.editing then
		ns.ToggleEditor()
	end
	window:Show()
end
