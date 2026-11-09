local _, ns = ...

-- The addon's own settings window, with the settings grouped on tabs. Every setting is a row:
-- a checkbox, a choice or number with arrows, or a button. The controller works it while it is open:
-- D-pad up / down picks a row, left / right changes it, A toggles or presses, L1 / R1 change tab,
-- and B or Start closes it. It is a plain frame, not one of the game's panels, so opening it does not
-- go through Forever's window focus. The tabs are a column on the left, under a search box that
-- finds settings on every tab by name or description.

local SIDEBAR = 170 -- width of the tab column on the left
local WIDTH, HEIGHT = 580 + SIDEBAR, 740
local ROW_HEIGHT = 32
local ROWS_TOP = -62
local GOLD = { 1, 0.82, 0 }

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
		tinsert(choices, { action[1], action[2] })
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
		tinsert(formRows, { type = "choice", key = "formSet" .. form, label = "Form " .. form .. " uses", choices = SetChoices })
	end

	local tabs = {
		{
			name = "General",
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
					tip = "The highlight color of the bottom bars, while L2 or R2 is held." },
				{ type = "choice", key = "activeColorTopLeft", label = "Top left bar color", choices = ActiveColorChoices,
					onChange = function() ns.RefreshActiveHighlight() end,
					tip = "The highlight color of the top left bar (double tap L2)." },
				{ type = "choice", key = "activeColorTopRight", label = "Top right bar color", choices = ActiveColorChoices,
					onChange = function() ns.RefreshActiveHighlight() end,
					tip = "The highlight color of the top right bar (double tap R2)." },
				{ type = "choice", key = "activeColorCombo", label = "Combo color", choices = ActiveColorChoices,
					onChange = function() ns.RefreshActiveHighlight() end,
					tip = "The highlight color while L2 then R2, or R2 then L2, is held." },
				{ type = "number", key = "activeStrength", label = "Selected bar brightness", min = 0.1, max = 1, step = 0.05,
					onChange = function() ns.RefreshActiveHighlight() end },
				{ type = "check", key = "activeMarks", label = "Marks in the middle of the selected bar",
					onChange = function() ns.RefreshActiveHighlight() end,
					tip = "The small cross and dots between the slots of the bar you are using." },
			},
		},
		{
			name = "Crossbar",
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
				{ type = "choice", key = "showTopLeft", label = "Top left bar (double tap L2)",
					choices = function() return { { "always", "Always shown" }, { "selected", "Only when selected" } } end,
					tip = "Only when selected: the top left bar is hidden until you double tap L2." },
				{ type = "choice", key = "showTopRight", label = "Top right bar (double tap R2)",
					choices = function() return { { "always", "Always shown" }, { "selected", "Only when selected" } } end,
					tip = "Only when selected: the top right bar is hidden until you double tap R2." },
			},
		},
		{
			name = "Layers and forms",
			rows = {
				{ type = "choice", key = "sideWL", label = "Double tap L2 shows", choices = SideChoices },
				{ type = "choice", key = "sideWR", label = "Double tap R2 shows", choices = SideChoices },
				{ type = "choice", key = "sideLR", label = "L2 then R2 shows", choices = SideChoices },
				{ type = "choice", key = "sideRL", label = "R2 then L2 shows", choices = SideChoices },
				{ type = "check", key = "formsChangeBar", label = "Forms change the bottom row",
					tip = "Each form or stance keeps its own set. R1 + a button changes the set of the current form." },
			},
		},
		{
			name = "Input",
			rows = {
				{ type = "choice", key = "triggerMode", label = "L2 / R2 activation",
					choices = function() return { { "hold", "Hold" }, { "toggle", "Toggle" }, { "mixed", "Mixed" } } end,
					tip = "Hold: selected while the trigger is held. Toggle: stays selected until pressed again, also after a double tap. Mixed: a tap toggles and a hold holds." },
				{ type = "choice", key = "l3Action", label = "L3 (press left stick)", choices = StickChoices,
					tip = "What pressing the left stick in does." },
				{ type = "choice", key = "r3Action", label = "R3 (press right stick)", choices = StickChoices,
					tip = "What pressing the right stick in does. L2 or R2 + R3 still moves or removes an ability." },
				{ type = "check", key = "wxhbFourSlots", label = "WXHB swaps face buttons only",
					tip = "The D-pad keeps the bottom row while the double tap row is selected." },
				{ type = "number", key = "doubleTapTicks", label = "Double tap window", min = 2, max = 4, step = 1,
					tip = "In 0.2 second steps: 2 is about 0.2-0.4 seconds, and it can be shorter in combat." },
				{ type = "check", key = "holdToWalk", label = "Hold B / Circle to walk" },
				{ type = "check", key = "priorityBindings", label = "Priority bindings",
					tip = "Turn on only if R2 does not change the bar. Then check that menus can still be navigated." },
			},
		},
	}
	for _, row in ipairs(formRows) do
		tinsert(tabs[4].rows, row)
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
		if choice[1] == ns.db[row.key] then
			return i, choices
		end
	end
	return 1, choices
end

local function SetValue(row, value)
	ns.db[row.key] = value
	;(row.onChange or Sync)()
end

local UpdateRows

-- Changes a row by one step: delta is -1 or 1. Checkboxes flip either way.
local function StepRow(row, delta, big)
	if row.type == "check" then
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

local function ActivateRow(row)
	if row.type == "action" then
		row.run()
	else
		StepRow(row, 1)
	end
end

local function CreateArrow(parent, direction)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(24, 24)
	local suffix = direction < 0 and "PrevPage" or "NextPage"
	button:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. suffix .. "-Up")
	button:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. suffix .. "-Down")
	button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	return button
end

local function CreateRowFrame(index)
	local frame = CreateFrame("Button", nil, window)
	frame:SetHeight(ROW_HEIGHT)
	frame:SetPoint("TOPLEFT", window, "TOPLEFT", 16 + SIDEBAR, ROWS_TOP - (index - 1) * ROW_HEIGHT)
	frame:SetPoint("RIGHT", window, "RIGHT", -16, 0)

	frame.focus = frame:CreateTexture(nil, "BACKGROUND")
	frame.focus:SetAllPoints()
	frame.focus:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.12)
	frame.focusBar = frame:CreateTexture(nil, "ARTWORK")
	frame.focusBar:SetPoint("TOPLEFT")
	frame.focusBar:SetPoint("BOTTOMLEFT")
	frame.focusBar:SetWidth(3)
	frame.focusBar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)

	frame.label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.label:SetPoint("LEFT", 12, 0)
	-- Stops before the widest control (the action button), so long search results are cut, not overlapped.
	frame.label:SetPoint("RIGHT", -214, 0)
	frame.label:SetJustifyH("LEFT")
	frame.label:SetWordWrap(false)

	frame.check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	frame.check:SetSize(28, 28)
	frame.check:SetPoint("RIGHT", -110, 0)

	frame.prev = CreateArrow(frame, -1)
	frame.next = CreateArrow(frame, 1)
	frame.next:SetPoint("RIGHT", -4, 0)
	frame.value = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.value:SetPoint("RIGHT", frame.next, "LEFT", -4, 0)
	frame.value:SetWidth(170)
	frame.prev:SetPoint("RIGHT", frame.value, "LEFT", -4, 0)

	frame.action = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.action:SetSize(178, 24)
	frame.action:SetPoint("RIGHT", -28, 0)

	local function Focus()
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
		Focus()
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
	for _, child in ipairs({ frame.check, frame.prev, frame.next, frame.action }) do
		child:HookScript("OnEnter", Focus)
	end
	return frame
end

function UpdateRows()
	if not window then
		return
	end
	local rows = CurrentRows()
	cursor = math.max(1, math.min(cursor, #rows))
	for index, frame in ipairs(rowFrames) do
		local row = rows[index]
		frame.row = row
		frame:SetShown(row ~= nil)
		if row then
			if searchRows then
				frame.label:SetText("|cff8c8c8c" .. row.tabName .. " >|r " .. row.label)
			else
				frame.label:SetText(row.label)
			end
			local isFocused = index == cursor
			frame.focus:SetShown(isFocused)
			frame.focusBar:SetShown(isFocused)
			frame.check:SetShown(row.type == "check")
			local stepped = row.type == "choice" or row.type == "number"
			frame.prev:SetShown(stepped)
			frame.next:SetShown(stepped)
			frame.value:SetShown(stepped)
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
			elseif row.type == "number" then
				frame.value:SetText(FormatNumber(ns.db[row.key]))
			elseif row.type == "action" then
				frame.action:SetText(row.button)
			end
		end
	end
	local row = rows[cursor]
	local tip = row and row.tip or ""
	if searchRows and #rows == 0 then
		tip = "No settings match the search."
	elseif searchMore > 0 then
		tip = format("%d more matches are not shown; type more to narrow the search.\n%s", searchMore, tip)
	end
	window.tip:SetText(tip)
	for index, button in ipairs(tabButtons) do
		local selected = not searchRows and index == selectedTab
		button.selected:SetShown(selected)
		button.selectedBar:SetShown(selected)
		button.text:SetFontObject(selected and "GameFontHighlight" or "GameFontNormal")
	end
end

-- Finds the rows whose label or description contains every word of the text, on all tabs.
local function Search(text)
	text = strtrim(text or ""):lower()
	if text == "" then
		searchRows, searchMore = nil, 0
	else
		searchRows, searchMore = {}, 0
		for _, tab in ipairs(tabs) do
			for _, row in ipairs(tab.rows) do
				local haystack = (row.label .. " " .. (row.tip or "") .. " " .. tab.name):lower()
				local matches = true
				for word in text:gmatch("%S+") do
					if not haystack:find(word, 1, true) then
						matches = false
						break
					end
				end
				if matches then
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
		Up = function() local count = #CurrentRows() if count == 0 then return end cursor = cursor - 1 if cursor < 1 then cursor = count end UpdateRows() end,
		Down = function() local count = #CurrentRows() if count == 0 then return end cursor = cursor % count + 1 UpdateRows() end,
		Left = function() local row = CurrentRows()[cursor] if row and row.type ~= "action" then StepRow(row, -1) end end,
		Right = function() local row = CurrentRows()[cursor] if row and row.type ~= "action" then StepRow(row, 1) end end,
		Accept = function() local row = CurrentRows()[cursor] if row then ActivateRow(row) end end,
		Back = function() ns.CloseConfig() end,
		PrevTab = function() SelectTab(selectedTab - 1) end,
		NextTab = function() SelectTab(selectedTab + 1) end,
	}
	for name, action in pairs(actions) do
		local button = CreateFrame("Button", "GamepadXIVConfigNav" .. name, window)
		button:RegisterForClicks("AnyDown")
		button:SetScript("OnClick", action)
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

local function CreateWindow()
	tabs = BuildTabs()
	window = CreateFrame("Frame", "GamepadXIVConfigFrame", UIParent, "BasicFrameTemplateWithInset")
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
	if window.TitleText then
		window.TitleText:SetText("Gamepad XIV")
	end

	local maxRows = 0
	for _, tab in ipairs(tabs) do
		maxRows = math.max(maxRows, #tab.rows)
	end
	rowFrames = {}
	for index = 1, maxRows do
		rowFrames[index] = CreateRowFrame(index)
	end

	window.tip = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	window.tip:SetPoint("BOTTOMLEFT", 24 + SIDEBAR, 44)
	window.tip:SetPoint("BOTTOMRIGHT", -24, 44)
	window.tip:SetHeight(40)
	window.tip:SetJustifyH("LEFT")
	window.tip:SetJustifyV("TOP")

	window.hint = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	window.hint:SetPoint("BOTTOMLEFT", 24, 16)
	window.hint:SetText(format("%s %s rows   %s %s change   %s tabs   %s close",
		ns.ButtonMarkup("PADDUP", "Up", 16), ns.ButtonMarkup("PADDDOWN", "Down", 16),
		ns.ButtonMarkup("PADDLEFT", "Left", 16), ns.ButtonMarkup("PADDRIGHT", "Right", 16),
		ns.ButtonMarkup("PADLSHOULDER", "L1", 16) .. ns.ButtonMarkup("PADRSHOULDER", "R1", 16),
		ns.ButtonMarkup("PAD2", "B", 16)))

	local defaults = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	defaults:SetSize(130, 22)
	defaults:SetPoint("BOTTOMRIGHT", -16, 12)
	defaults:SetText("Reset shown")
	defaults:SetScript("OnClick", ResetTab)

	-- The column on the left: a search box, then one button per tab.
	local divider = window:CreateTexture(nil, "ARTWORK")
	divider:SetPoint("TOPLEFT", SIDEBAR, -30)
	divider:SetPoint("BOTTOMLEFT", SIDEBAR, 44)
	divider:SetWidth(1)
	divider:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.25)

	local search = CreateFrame("EditBox", "GamepadXIVConfigSearch", window, "SearchBoxTemplate")
	search:SetSize(SIDEBAR - 34, 22)
	search:SetPoint("TOPLEFT", 22, -38)
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
		button:SetSize(SIDEBAR - 20, 30)
		button:SetPoint("TOPLEFT", window, "TOPLEFT", 10, -72 - (index - 1) * 34)
		button.selected = button:CreateTexture(nil, "BACKGROUND")
		button.selected:SetAllPoints()
		button.selected:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.18)
		button.selectedBar = button:CreateTexture(nil, "ARTWORK")
		button.selectedBar:SetPoint("TOPLEFT")
		button.selectedBar:SetPoint("BOTTOMLEFT")
		button.selectedBar:SetWidth(3)
		button.selectedBar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
		local hover = button:CreateTexture(nil, "HIGHLIGHT")
		hover:SetAllPoints()
		hover:SetColorTexture(1, 1, 1, 0.08)
		button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		button.text:SetPoint("LEFT", 14, 0)
		button.text:SetPoint("RIGHT", -6, 0)
		button.text:SetJustifyH("LEFT")
		button.text:SetText(tab.name)
		button:SetScript("OnClick", function() SelectTab(index) end)
		tabButtons[index] = button
	end

	CreateNavButtons()
	window:SetScript("OnShow", function()
		BindNav()
		UpdateRows()
	end)
	window:SetScript("OnHide", function()
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
