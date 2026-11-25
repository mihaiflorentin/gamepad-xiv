local _, ns = ...

-- Ready-made messages: a window to change the quick replies (the list the D-pad steps through while
-- typing) and the {PADRSTICK} messages by category. LfgFilter.lua holds the lists in use and their
-- defaults (ns.ChatAPI); the player's own are kept for the account, in GamepadXIVAccountDB:
--   chatPhrases       { { name = "Category", "message", ... }, ... }, nil for the defaults
--   chatQuickReplies  { "message", ... }, nil for the defaults
-- A list that ends up the same as the defaults is saved as nil, so new defaults reach it.
-- "<ask>" in a list is your group finder message.
--
-- Open with /gxiv messages or the settings' Chat tab. The controller works the window while it is
-- open; bindings can't change in combat, so it closes then.

local WHITE = "Interface\\Buttons\\WHITE8X8"
local GOLD = { 1, 0.82, 0 }
local PANEL = { 0.075, 0.075, 0.09, 0.97 }
local CONTROL = { 0.13, 0.13, 0.16, 1 }
local EDGE = { 1, 1, 1, 0.1 }
local SELECTED = { 0.24, 0.2, 0.07, 1 }
local SELECTED_EDGE = { GOLD[1], GOLD[2], GOLD[3], 0.9 }
local SELECTED_DIM = { 0.16, 0.15, 0.1, 1 } -- the other side's selection

local WIDTH, HEIGHT = 860, 560
local TITLE_HEIGHT, FOOTER_HEIGHT = 38, 44
local LEFT_WIDTH = 270
local ROW_HEIGHT = 28
local ROWS = 13
local LIST_TOP = TITLE_HEIGHT + 44
local MAX_MESSAGE, MAX_NAME = 255, 40
local ASK_TEXT = "Your group finder message"

local window
local state = {
	side = "left", -- "left": the lists; "right": the selected list's messages
	left = 1, right = 1, leftScroll = 0, rightScroll = 0,
	confirm = nil, -- a delete or reset waiting for its button again
	editing = nil, -- what the text box is typing: { mode = "edit" | "add" | "rename" | "new", list, index }
	status = nil, -- a short note under the lists
}

local function API()
	return ns.ChatAPI
end

local function Account()
	GamepadXIVAccountDB = GamepadXIVAccountDB or {}
	return GamepadXIVAccountDB
end

---------------------------------------------------------------------------------------------------
-- The lists

-- Whether two message lists (or two lists of categories) are the same.
local function Same(a, b)
	if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b or a.name ~= b.name then
		return false
	end
	for index = 1, #a do
		local x, y = a[index], b[index]
		if type(x) == "table" then
			if not Same(x, y) then
				return false
			end
		elseif x ~= y then
			return false
		end
	end
	return true
end

-- The saved lists into the ones in use.
local function Apply()
	local api = API()
	if api and api.SetMessages then
		local account = Account()
		api.SetMessages(account.chatPhrases, account.chatQuickReplies)
	end
end

-- Changes the lists: `change` gets copies of the categories and the quick replies to change, which
-- are then saved and put in use.
local function Modify(change)
	local api = API()
	local phrases, replies = api.CopyMessages(api.Phrases, api.QuickReplies)
	change(phrases, replies)
	local account = Account()
	account.chatPhrases = not Same(phrases, api.defaultPhrases) and phrases or nil
	account.chatQuickReplies = not Same(replies, api.defaultReplies) and replies or nil
	api.SetMessages(account.chatPhrases, account.chatQuickReplies)
end

local function ResetMessages()
	local account = Account()
	account.chatPhrases, account.chatQuickReplies = nil, nil
	Apply()
end

-- The left side: the quick replies, each category, then New category and Reset.
local function LeftItems()
	local items = { { kind = "replies" } }
	for index in ipairs(API().Phrases) do
		items[#items + 1] = { kind = "category", index = index }
	end
	items[#items + 1] = { kind = "new" }
	items[#items + 1] = { kind = "reset" }
	return items
end

-- The messages a left item opens, in the given lists (the ones in use by default).
local function ListOf(item, phrases, replies)
	if not item then
		return nil
	elseif item.kind == "replies" then
		return replies or API().QuickReplies
	elseif item.kind == "category" then
		return (phrases or API().Phrases)[item.index]
	end
end

local function LeftItem()
	local items = LeftItems()
	state.left = math.max(1, math.min(state.left, #items))
	return items[state.left], items
end

-- The right side: the selected list's messages, then Add message; nil when the left item isn't a list.
local function RightItems()
	local list = ListOf((LeftItem()))
	if not list then
		return nil
	end
	local items = {}
	for index, text in ipairs(list) do
		items[#items + 1] = { kind = "message", index = index, text = text }
	end
	items[#items + 1] = { kind = "add" }
	return items
end

local function RightItem()
	local items = RightItems()
	if not items then
		return nil
	end
	state.right = math.max(1, math.min(state.right, #items))
	return items[state.right], items
end

-- A message as the lists show it.
local function MessageText(text)
	if text == "<ask>" then
		return "|cffffd100" .. ASK_TEXT .. "|r  |cff999999<ask>|r"
	end
	return text
end

local function ListName(item)
	if item and item.kind == "replies" then
		return "Quick replies (D-pad)"
	elseif item and item.kind == "category" then
		local group = API().Phrases[item.index]
		return group and group.name or "?"
	end
	return ""
end

---------------------------------------------------------------------------------------------------
-- Typing

local Draw

local function StartTyping(mode, index)
	local item = LeftItem()
	local initial = ""
	local list = ListOf(item)
	if mode == "edit" then
		initial = list and list[index] or ""
	elseif mode == "rename" then
		initial = ListName(item)
	end
	state.editing = { mode = mode, item = item, index = index }
	state.status = nil
	local input = window.input
	input:SetMaxLetters((mode == "rename" or mode == "new") and MAX_NAME or MAX_MESSAGE)
	input:SetText(initial)
	input:Show()
	input:SetFocus()
	input:SetCursorPosition(#initial)
	Draw()
end

-- Text as it can be sent: no "|" (chat refuses broken escape codes), no spaces around it.
local function Clean(text)
	return strtrim((tostring(text or ""):gsub("|", "")))
end

local function FinishTyping(save)
	local edit = state.editing
	if not edit then
		return
	end
	state.editing = nil -- first, so losing focus below doesn't cancel again
	local text = Clean(window.input:GetText())
	window.input:ClearFocus()
	window.input:Hide()
	if save and text ~= "" then
		local item = edit.item
		Modify(function(phrases, replies)
			local list = ListOf(item, phrases, replies)
			if edit.mode == "new" then
				phrases[#phrases + 1] = { name = text }
				state.left = #phrases + 1 -- after the quick replies
				state.side, state.right = "right", 1
			elseif edit.mode == "rename" and item.kind == "category" and list then
				list.name = text
			elseif edit.mode == "edit" and list and list[edit.index] then
				list[edit.index] = text
			elseif edit.mode == "add" and list then
				list[#list + 1] = text
				state.right = #list
			end
		end)
	end
	Draw()
end

---------------------------------------------------------------------------------------------------
-- Actions, for the controller's buttons, the footer's buttons and clicks

local function Fit(cursor, scroll, count)
	if cursor <= scroll then
		scroll = cursor - 1
	elseif cursor > scroll + ROWS then
		scroll = cursor - ROWS
	end
	return math.max(0, math.min(scroll, math.max(0, count - ROWS)))
end

local function Step(delta)
	if state.side == "left" then
		local _, items = LeftItem()
		state.left = (state.left - 1 + delta) % #items + 1
		state.right, state.rightScroll = 1, 0
	else
		local _, items = RightItem()
		if items then
			state.right = (state.right - 1 + delta) % #items + 1
		end
	end
end

-- Moves the selected category or message one place up (-1) or down (1).
local function Move(delta)
	local item = LeftItem()
	if state.side == "left" then
		if item.kind ~= "category" then
			return
		end
		local from, to = item.index, item.index + delta
		if to < 1 or to > #API().Phrases then
			return
		end
		Modify(function(phrases)
			phrases[from], phrases[to] = phrases[to], phrases[from]
		end)
		state.left = state.left + delta
	else
		local message = RightItem()
		local list = ListOf(item)
		if not (message and message.kind == "message" and list) then
			return
		end
		local from, to = message.index, message.index + delta
		if to < 1 or to > #list then
			return
		end
		Modify(function(phrases, replies)
			local copy = ListOf(item, phrases, replies)
			copy[from], copy[to] = copy[to], copy[from]
		end)
		state.right = to
	end
end

-- What Delete would remove now, if anything, and why not when it can't.
local function DeleteTarget()
	local item = LeftItem()
	if state.side == "left" then
		if item.kind == "category" then
			return "category"
		end
		return nil, item.kind == "replies" and "The quick replies stay; delete their messages instead." or nil
	end
	local message = RightItem()
	if message and message.kind == "message" then
		if item.kind == "replies" and #API().QuickReplies <= 1 then
			return nil, "Keep at least one quick reply."
		end
		return "message"
	end
end

local ACTIONS = {}

function ACTIONS.Up()
	Step(-1)
end

function ACTIONS.Down()
	Step(1)
end

function ACTIONS.Left()
	state.side = "left"
end

function ACTIONS.Right()
	if RightItems() then
		state.side = "right"
	end
end

function ACTIONS.Accept(pending)
	local item = LeftItem()
	if state.side == "left" then
		if item.kind == "replies" or item.kind == "category" then
			state.side = "right"
		elseif item.kind == "new" then
			StartTyping("new")
		elseif item.kind == "reset" then
			if pending and pending.action == "reset" then
				ResetMessages()
				state.left, state.right, state.leftScroll, state.rightScroll = 1, 1, 0, 0
				state.status = "The ready-made messages are back to the defaults."
			else
				state.confirm = { action = "reset" }
			end
		end
		return
	end
	local message = RightItem()
	if message and message.kind == "message" then
		StartTyping("edit", message.index)
	elseif message then
		StartTyping("add")
	end
end

function ACTIONS.Delete(pending)
	local target, why = DeleteTarget()
	if not target then
		state.status = why
		return
	end
	local item = LeftItem()
	local index = state.side == "left" and state.left or state.right
	if not (pending and pending.action == "delete" and pending.side == state.side and pending.left == state.left and pending.index == index) then
		state.confirm = { action = "delete", side = state.side, left = state.left, index = index }
		return
	end
	if target == "category" then
		Modify(function(phrases)
			table.remove(phrases, item.index)
		end)
		state.right, state.rightScroll = 1, 0
	else
		local message = RightItem()
		Modify(function(phrases, replies)
			table.remove(ListOf(item, phrases, replies), message.index)
		end)
	end
end

function ACTIONS.Rename()
	local item = LeftItem()
	if item.kind == "category" then
		StartTyping("rename")
	elseif item.kind == "replies" then
		state.status = "Only categories can be renamed."
	end
end

function ACTIONS.MoveUp()
	Move(-1)
end

function ACTIONS.MoveDown()
	Move(1)
end

function ACTIONS.Back()
	if state.side == "right" then
		state.side = "left"
	else
		window:Hide()
	end
end

-- Runs an action from any button. While typing only Save and Cancel do anything. A delete or reset
-- waiting for its button again is dropped by any other action.
local function Run(name)
	if not (window and window:IsShown()) then
		return
	end
	if state.editing then
		if name == "Accept" then
			FinishTyping(true)
		elseif name == "Back" then
			FinishTyping(false)
		end
		return
	end
	local pending = state.confirm
	state.confirm = nil
	if pending and name == "Back" then
		Draw() -- Back only drops the question
		return
	end
	state.status = nil
	ACTIONS[name](pending)
	Draw()
end

---------------------------------------------------------------------------------------------------
-- Drawing

local function Flat(frame, color, edge)
	frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	frame:SetBackdropColor(unpack(color))
	frame:SetBackdropBorderColor(unpack(edge or EDGE))
end

local function Hint(text)
	return ns.ButtonText(text, 16)
end

local function DrawRow(row, text, selected, active)
	row:Show()
	row.text:SetText(text)
	if selected then
		Flat(row, active and SELECTED or SELECTED_DIM, active and SELECTED_EDGE or EDGE)
	else
		Flat(row, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
	end
end

-- The footer: one button per action that can be used now, with its controller button.
local function FooterButtons()
	if state.editing then
		return { { "Accept", "{PAD1} Save" }, { "Back", "{PAD2} Cancel" } }
	end
	local confirm = state.confirm
	local item = LeftItem()
	local buttons = {}
	local accept
	if state.side == "left" then
		accept = (item.kind == "new" and "New category") or (item.kind == "reset" and (confirm and "Yes, reset" or "Reset to defaults")) or "Open"
	else
		local message = RightItem()
		accept = message and message.kind == "message" and "Edit" or "Add"
	end
	buttons[#buttons + 1] = { "Accept", "{PAD1} " .. accept }
	if DeleteTarget() then
		buttons[#buttons + 1] = { "Delete", confirm and confirm.action == "delete" and "{PAD3} |cffff7777Yes, delete|r" or "{PAD3} Delete" }
	end
	local movable = (state.side == "left" and item.kind == "category")
		or (state.side == "right" and (RightItem() or {}).kind == "message")
	if movable then
		buttons[#buttons + 1] = { "MoveUp", "{PADLSHOULDER} Move up" }
		buttons[#buttons + 1] = { "MoveDown", "{PADRSHOULDER} Move down" }
	end
	if item.kind == "category" then
		buttons[#buttons + 1] = { "Rename", "{PAD4} Rename" }
	end
	buttons[#buttons + 1] = { "Back", (confirm and "{PAD2} No") or (state.side == "right" and "{PAD2} Back") or "{PAD2} Close" }
	return buttons
end

local function DrawFooter()
	local specs = FooterButtons()
	local total = 0
	for index, button in ipairs(window.footerButtons) do
		local spec = specs[index]
		button:SetShown(spec ~= nil)
		if spec then
			button.action = spec[1]
			button.text:SetText(Hint(spec[2]))
			button:SetWidth(button.text:GetStringWidth() + 24)
			total = total + button:GetWidth() + (index > 1 and 8 or 0)
		end
	end
	local x = -total / 2
	for index, button in ipairs(window.footerButtons) do
		if specs[index] then
			button:ClearAllPoints()
			button:SetPoint("LEFT", window.footerBar, "CENTER", x, 0)
			x = x + button:GetWidth() + 8
		end
	end
end

function Draw()
	if not (window and window:IsShown()) then
		return
	end
	local item, leftItems = LeftItem()
	local rightItems = RightItems()
	if not rightItems and state.side == "right" then
		state.side = "left"
	end
	state.leftScroll = Fit(state.left, state.leftScroll, #leftItems)
	local phrases, replies = API().Phrases, API().QuickReplies
	for slot, row in ipairs(window.leftRows) do
		local index = state.leftScroll + slot
		local entry = leftItems[index]
		row.index = index
		if not entry then
			row:Hide()
		else
			local text
			if entry.kind == "replies" then
				text = "Quick replies (D-pad)  |cff999999" .. #replies .. "|r"
			elseif entry.kind == "category" then
				text = phrases[entry.index].name .. "  |cff999999" .. #phrases[entry.index] .. "|r"
			elseif entry.kind == "new" then
				text = "|cffffd100+ New category|r"
			else
				text = "|cffff7777Reset to defaults|r"
			end
			DrawRow(row, text, index == state.left, state.side == "left")
		end
	end

	window.rightTitle:SetText(rightItems and ListName(item) or "")
	if item.kind == "replies" then
		window.rightNote:SetText(Hint("While typing: {PADDLEFT} / {PADDRIGHT} picks one, {PADLSTICK} adds it to the message ({PAD1} too while nothing is typed)"))
	elseif item.kind == "category" then
		window.rightNote:SetText(Hint("While typing: {PADRSTICK} lists these, {PAD1} adds one to the message"))
	else
		window.rightNote:SetText("")
	end
	if rightItems then
		RightItem()
		state.rightScroll = Fit(state.right, state.rightScroll, #rightItems)
		window.rightInfo:Hide()
	else
		window.rightInfo:Show()
		window.rightInfo:SetText(item.kind == "new"
			and Hint("A category of your own for the {PADRSTICK} messages. {PAD1} names it, then add its messages.")
			or Hint("Puts back the quick replies and every category as they came with the addon. Your own messages and categories are removed. {PAD1} twice to do it."))
	end
	for slot, row in ipairs(window.rightRows) do
		local index = state.rightScroll + slot
		local entry = rightItems and rightItems[index]
		row.index = index
		if not entry then
			row:Hide()
		else
			local text = entry.kind == "message" and MessageText(entry.text) or "|cffffd100+ Add message|r"
			DrawRow(row, text, index == state.right, state.side == "right")
		end
	end

	-- Under the lists: the text box while typing, otherwise a question or a note.
	local edit = state.editing
	window.inputLabel:SetShown(edit ~= nil)
	if edit then
		local labels = { edit = "Message", add = "New message", rename = "Category name", new = "New category" }
		window.inputLabel:SetText(labels[edit.mode] or "")
		window.status:SetText((edit.mode == "edit" or edit.mode == "add")
			and "|cff999999Enter saves, Escape cancels. <ask> is your group finder message.|r"
			or "|cff999999Enter saves, Escape cancels.|r")
		window.status:ClearAllPoints()
		window.status:SetPoint("BOTTOMLEFT", window.input, "TOPLEFT", -4, 6)
	else
		local confirm = state.confirm
		local text = state.status or ""
		if confirm and confirm.action == "delete" then
			text = Hint("|cffff7777Delete " .. (state.side == "left" and "this category and its messages" or "this message") .. "?|r  {PAD3} again to delete, anything else keeps it.")
		elseif confirm and confirm.action == "reset" then
			text = Hint("|cffff7777Reset every ready-made message to the defaults?|r  {PAD1} again to reset, anything else keeps them.")
		end
		window.status:SetText(text)
		window.status:ClearAllPoints()
		window.status:SetPoint("LEFT", window, "BOTTOMLEFT", 20, FOOTER_HEIGHT + 26)
	end
	DrawFooter()
end

---------------------------------------------------------------------------------------------------
-- The window

local NAV = {
	PADDUP = "Up", PADDDOWN = "Down", PADDLEFT = "Left", PADDRIGHT = "Right",
	PAD1 = "Accept", PAD2 = "Back", PAD3 = "Delete", PAD4 = "Rename",
	PADLSHOULDER = "MoveUp", PADRSHOULDER = "MoveDown", PADFORWARD = "Back",
}

local function Text(parent, font)
	local text = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
	text:SetWordWrap(false)
	text:SetJustifyH("LEFT")
	return text
end

-- A row of a list: a click selects it, a click on the selected row opens or edits it.
local function CreateRow(parent, side, width)
	local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
	row:SetSize(width, ROW_HEIGHT - 2)
	row.text = Text(row)
	row.text:SetPoint("LEFT", 10, 0)
	row.text:SetPoint("RIGHT", -8, 0)
	row:RegisterForClicks("LeftButtonUp")
	row:SetScript("OnClick", function(self)
		if state.editing then
			return
		end
		local same = state.side == side and (side == "left" and state.left or state.right) == self.index
		if same then
			Run("Accept")
			return
		end
		state.confirm, state.status = nil, nil
		if side == "left" and state.left ~= self.index then
			state.right, state.rightScroll = 1, 0
		end
		state.side = side
		if side == "left" then
			state.left = self.index
		else
			state.right = self.index
		end
		Draw()
	end)
	row:SetScript("OnEnter", function(self)
		if self.text:IsTruncated() then
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(self.text:GetText(), 1, 1, 1, 1, true)
			GameTooltip:Show()
		end
	end)
	row:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	return row
end

local function CreatePanel(x, width)
	local panel = CreateFrame("Frame", nil, window, "BackdropTemplate")
	Flat(panel, { 0.05, 0.05, 0.065, 1 })
	panel:SetPoint("TOPLEFT", x, -LIST_TOP + 4)
	panel:SetSize(width, ROWS * ROW_HEIGHT + 8)
	return panel
end

local function CreateWindow()
	window = CreateFrame("Frame", "GamepadXIVMessagesFrame", UIParent, "BackdropTemplate")
	Flat(window, PANEL, { GOLD[1], GOLD[2], GOLD[3], 0.45 })
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

	local bar = window:CreateTexture(nil, "BACKGROUND", nil, 1)
	bar:SetPoint("TOPLEFT", 1, -1)
	bar:SetPoint("TOPRIGHT", -1, -1)
	bar:SetHeight(TITLE_HEIGHT)
	bar:SetColorTexture(0.1, 0.1, 0.125, 1)
	local icon = window:CreateTexture(nil, "ARTWORK")
	icon:SetSize(22, 22)
	icon:SetPoint("LEFT", bar, "LEFT", 12, 0)
	icon:SetTexture(ns.ICON)
	local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
	title:SetText("Ready-made messages")
	local close = CreateFrame("Button", nil, window, "BackdropTemplate")
	close:SetSize(26, 26)
	Flat(close, CONTROL)
	close:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
	local closeText = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	closeText:SetPoint("CENTER")
	closeText:SetText("X")
	close:SetScript("OnClick", function() window:Hide() end)

	-- Left: the lists. Right: the selected list's messages.
	local rightX = 16 + LEFT_WIDTH + 16
	local rightWidth = WIDTH - rightX - 16
	local leftTitle = Text(window, "GameFontNormal")
	leftTitle:SetPoint("BOTTOMLEFT", window, "TOPLEFT", 20, -LIST_TOP + 10)
	leftTitle:SetText("Lists")
	window.rightTitle = Text(window, "GameFontNormal")
	window.rightTitle:SetPoint("BOTTOMLEFT", window, "TOPLEFT", rightX + 4, -LIST_TOP + 10)
	window.rightNote = Text(window, "GameFontHighlightSmall")
	window.rightNote:SetPoint("BOTTOMRIGHT", window, "TOPRIGHT", -20, -LIST_TOP + 10)
	window.rightNote:SetWidth(rightWidth - 220)
	window.rightNote:SetJustifyH("RIGHT")
	window.rightNote:SetTextColor(0.6, 0.6, 0.6)

	local leftPanel = CreatePanel(16, LEFT_WIDTH)
	local rightPanel = CreatePanel(rightX, rightWidth)
	window.leftRows, window.rightRows = {}, {}
	for slot = 1, ROWS do
		local left = CreateRow(leftPanel, "left", LEFT_WIDTH - 8)
		left:SetPoint("TOPLEFT", 4, -4 - (slot - 1) * ROW_HEIGHT)
		window.leftRows[slot] = left
		local right = CreateRow(rightPanel, "right", rightWidth - 8)
		right:SetPoint("TOPLEFT", 4, -4 - (slot - 1) * ROW_HEIGHT)
		window.rightRows[slot] = right
	end
	-- The mouse wheel moves the selection in the list under it.
	for _, pair in ipairs({ { leftPanel, "left" }, { rightPanel, "right" } }) do
		local panel, side = pair[1], pair[2]
		panel:EnableMouseWheel(true)
		panel:SetScript("OnMouseWheel", function(_, delta)
			if state.editing or (side == "right" and not RightItems()) then
				return
			end
			state.side, state.confirm, state.status = side, nil, nil
			Step(-delta)
			Draw()
		end)
	end
	window.rightInfo = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	window.rightInfo:SetPoint("TOPLEFT", 16, -16)
	window.rightInfo:SetPoint("TOPRIGHT", -16, -16)
	window.rightInfo:SetJustifyH("LEFT")
	window.rightInfo:SetSpacing(3)

	-- Under the lists: the text box, or a note.
	window.status = Text(window, "GameFontHighlight")
	window.status:SetWidth(WIDTH - 40)
	window.inputLabel = Text(window, "GameFontNormal")
	window.inputLabel:SetPoint("LEFT", window, "BOTTOMLEFT", 20, FOOTER_HEIGHT + 22)
	window.inputLabel:SetWidth(120)
	local input = CreateFrame("EditBox", "GamepadXIVMessagesInput", window, "InputBoxTemplate")
	input:SetPoint("LEFT", window, "BOTTOMLEFT", 150, FOOTER_HEIGHT + 22)
	input:SetPoint("RIGHT", window, "BOTTOMRIGHT", -20, FOOTER_HEIGHT + 22)
	input:SetHeight(26)
	input:SetAutoFocus(false)
	input:SetMaxLetters(MAX_MESSAGE)
	input:SetMaxBytes(MAX_MESSAGE + 1) -- what chat takes: 255 bytes, so an accented letter is never cut in two
	input:SetScript("OnEnterPressed", function() FinishTyping(true) end)
	input:SetScript("OnEscapePressed", function() FinishTyping(false) end)
	input:SetScript("OnEditFocusLost", function() FinishTyping(false) end)
	input:Hide()
	window.input = input

	window.footerBar = window:CreateTexture(nil, "BACKGROUND", nil, 1)
	window.footerBar:SetPoint("BOTTOMLEFT", 1, 1)
	window.footerBar:SetPoint("BOTTOMRIGHT", -1, 1)
	window.footerBar:SetHeight(FOOTER_HEIGHT)
	window.footerBar:SetColorTexture(0.1, 0.1, 0.125, 1)
	window.footerButtons = {}
	for index = 1, 6 do
		local button = CreateFrame("Button", nil, window, "BackdropTemplate")
		Flat(button, CONTROL)
		button:SetHeight(30)
		button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		button.text:SetPoint("CENTER")
		button:SetScript("OnClick", function(self)
			if self.action then
				Run(self.action)
			end
		end)
		button:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(SELECTED_EDGE)) end)
		button:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(EDGE)) end)
		window.footerButtons[index] = button
	end

	-- The controller's buttons click these while the window is open.
	local made = {}
	for _, name in pairs(NAV) do
		if not made[name] then
			made[name] = true
			local button = CreateFrame("Button", "GamepadXIVMessagesNav" .. name, window)
			local function OnClick()
				Run(name)
			end
			-- Holding the D-pad keeps moving, but not while typing.
			if name == "Up" or name == "Down" then
				ns.RepeatOnHold(button, OnClick, function() return not state.editing and state.side end)
			else
				button:RegisterForClicks("AnyDown")
				button:SetScript("OnClick", OnClick)
			end
		end
	end
	window:SetScript("OnShow", function()
		if not InCombatLockdown() then
			for key, name in pairs(NAV) do
				SetOverrideBindingClick(window, true, key, "GamepadXIVMessagesNav" .. name, "LeftButton")
			end
		end
	end)
	window:SetScript("OnHide", function()
		if state.editing then
			FinishTyping(false)
		end
		state.confirm, state.status = nil, nil
		if not InCombatLockdown() then
			ClearOverrideBindings(window)
		end
	end)
	-- Bindings can still be changed while this event runs, just before combat locks them.
	window:RegisterEvent("PLAYER_REGEN_DISABLED")
	window:SetScript("OnEvent", function()
		window:Hide()
	end)
	if InputDeviceIconSetManager and InputDeviceIconSetManager.RegisterActiveInputDeviceIconSetUpdatedCallback then
		InputDeviceIconSetManager:RegisterActiveInputDeviceIconSetUpdatedCallback(function() Draw() end, window)
	end
end

-- Opens the window, or closes it if it is open.
function ns.OpenMessagesEditor()
	if InCombatLockdown() then
		ns.Print("The ready-made messages can't be edited in combat.")
		return
	end
	if not (API() and API().SetMessages) then
		return
	end
	if not window then
		CreateWindow()
	end
	if window:IsShown() then
		window:Hide()
		return
	end
	-- LFG Filter and the Chat window keep taking the controller back while open, and the settings
	-- bind the same buttons.
	if ns.CloseConfig then
		ns.CloseConfig()
	end
	local lfg = _G.GamepadXIVLfgFilterFrame
	if lfg and lfg:IsShown() then
		lfg:Hide()
	end
	state.side, state.confirm, state.status, state.editing = "left", nil, nil, nil
	window:Show()
	Draw()
end

-- The saved lists go in use as soon as the saved variables are there.
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, _, name)
	if name == "GamepadXIV" then
		self:UnregisterEvent("ADDON_LOADED")
		Apply()
	end
end)

-- For the tests.
ns.MessagesEditor = { Apply = Apply, Modify = Modify, Reset = ResetMessages, Same = Same }
