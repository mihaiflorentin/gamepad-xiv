local _, ns = ...

local button

local function PlaceButton()
	local angle = math.rad(ns.db.minimapAngle)
	local radius = Minimap:GetWidth() / 2 + 5
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

function ns.UpdateMinimapButton()
	if button then
		button:SetShown(ns.db.minimapShown)
	end
end

local function SetSetting(key, value)
	ns.db[key] = value
	ns.Sync()
end

local function SetMinimapShown(shown)
	ns.db.minimapShown = shown
	ns.UpdateMinimapButton()
	if not shown then
		ns.Print("Minimap icon hidden. /fc minimap brings it back.")
	end
end

-- A plain frame on purpose. Blizzard's menu claims Forever's gamepad focus when it opens, and when
-- that happens from addon code, Forever's protected interact call gets blocked.
local ROW_HEIGHT = 20
local MENU_WIDTH = 230
local menu

local function GetMenuRows()
	local function ModeRow(mode, label)
		return {
			text = "L2 / R2: " .. label,
			isChecked = function() return ns.db.triggerMode == mode end,
			onClick = function() SetSetting("triggerMode", mode) end,
		}
	end
	return {
		{ text = "Edit crossbar", onClick = function() ns.ToggleEditor() end, closes = true },
		{ text = "Move bars", onClick = function() ns.ToggleMove() end, closes = true },
		{ text = "Move or remove an ability", onClick = function() ns.StartClear() end, closes = true },
		{ text = "Settings", onClick = function() ns.OpenConfig() end, closes = true },
		{
			text = "Enable layout",
			isChecked = function() return ns.db.enabled end,
			onClick = function() SetSetting("enabled", not ns.db.enabled) end,
		},
		{
			text = "Face target",
			isChecked = function() return ns.db.autoFace end,
			onClick = function()
				ns.AllowExperimentalCamera()
				SetSetting("autoFace", not ns.db.autoFace)
			end,
		},
		ModeRow("hold", "Hold"),
		ModeRow("toggle", "Toggle"),
		ModeRow("mixed", "Mixed"),
		{ text = "Reset bar positions", onClick = function() ns.ResetPositions() end, closes = true },
		{ text = "Hide minimap icon", onClick = function() SetMinimapShown(false) end, closes = true },
	}
end

local function RefreshMenu()
	for _, row in ipairs(menu.rows) do
		row.check:SetShown(row.info.isChecked and row.info.isChecked() or false)
	end
end

local function CreateMenu()
	menu = CreateFrame("Frame", "GamepadXIVMenu", UIParent, "BackdropTemplate")
	menu:SetFrameStrata("DIALOG")
	menu:SetClampedToScreen(true)
	menu:EnableMouse(true)
	menu:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	menu:Hide()

	local title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 12, -10)
	title:SetText(ns.ICON_MARKUP .. " Gamepad XIV")

	menu.rows = {}
	for index, info in ipairs(GetMenuRows()) do
		local row = CreateFrame("Button", nil, menu)
		row:SetSize(MENU_WIDTH - 16, ROW_HEIGHT)
		row:SetPoint("TOPLEFT", 8, -30 - (index - 1) * ROW_HEIGHT)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		row.info = info

		row.check = row:CreateTexture(nil, "ARTWORK")
		row.check:SetSize(16, 16)
		row.check:SetPoint("LEFT", 2, 0)
		row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")

		local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("LEFT", 22, 0)
		label:SetText(info.text)

		row:SetScript("OnClick", function()
			if info.closes then
				menu:Hide()
			end
			info.onClick()
			if menu:IsShown() then
				RefreshMenu()
			end
		end)
		menu.rows[index] = row
	end
	menu:SetSize(MENU_WIDTH, 38 + #menu.rows * ROW_HEIGHT)

	-- Any click elsewhere closes it, and so does combat.
	menu:SetScript("OnShow", function(self)
		self:RegisterEvent("GLOBAL_MOUSE_DOWN")
		self:RegisterEvent("PLAYER_REGEN_DISABLED")
	end)
	menu:SetScript("OnHide", function(self)
		self:UnregisterAllEvents()
	end)
	menu:SetScript("OnEvent", function(self, event)
		if event == "PLAYER_REGEN_DISABLED" or not self:IsMouseOver() then
			self:Hide()
		end
	end)
end

function ns.OpenMenu()
	if not menu then
		CreateMenu()
	end
	if menu:IsShown() then
		menu:Hide()
		return
	end
	local scale = UIParent:GetEffectiveScale()
	local cursorX, cursorY = GetCursorPosition()
	menu:ClearAllPoints()
	menu:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", cursorX / scale, cursorY / scale)
	RefreshMenu()
	menu:Show()
end

local function HandleClick(_, mouseButton)
	if mouseButton == "RightButton" then
		ns.OpenMenu()
	else
		ns.OpenConfig()
	end
end

-- The AddOn compartment's entry, declared in the .toc. Depending on the client, the second
-- argument is the button name or a table holding it.
function GamepadXIV_OnCompartmentClick(_, input)
	if ns.root then
		HandleClick(nil, type(input) == "table" and input.buttonName or input)
	end
end

function ns.CreateMinimapButton()
	if not Minimap then
		return
	end

	button = CreateFrame("Button", "GamepadXIVMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local icon = button:CreateTexture(nil, "BACKGROUND")
	icon:SetSize(20, 20)
	icon:SetPoint("TOPLEFT", 6, -5)
	icon:SetTexture(ns.ICON)

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

	button:SetScript("OnClick", HandleClick)

	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("Gamepad XIV")
		GameTooltip:AddLine("Left click: settings", 1, 1, 1)
		GameTooltip:AddLine("Right click: menu", 1, 1, 1)
		GameTooltip:AddLine("Drag: move this icon", 1, 1, 1)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)

	button:SetScript("OnDragStart", function(self)
		GameTooltip:Hide()
		self:SetScript("OnUpdate", function()
			local cursorX, cursorY = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			local centerX, centerY = Minimap:GetCenter()
			ns.db.minimapAngle = math.deg(math.atan2(cursorY / scale - centerY, cursorX / scale - centerX))
			PlaceButton()
		end)
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)

	PlaceButton()
	ns.UpdateMinimapButton()
end
