local _, ns = ...

-- What's new: the changelog (Changelog.lua, made from CHANGELOG.md) in a window of the addon's own.
-- It shows once after each update, with what changed since the version you had, unless "Show the
-- changelog" is set to Never. The settings (General tab) and /gxiv changelog show it any time.
-- The version you last saw is kept for the account (GamepadXIVAccountDB.changelogSeen).

local WHITE = "Interface\\Buttons\\WHITE8X8"
local GOLD = { 1, 0.82, 0 }
local PANEL = { 0.075, 0.075, 0.09, 0.97 }
local CONTROL = { 0.13, 0.13, 0.16, 1 }
local WIDTH, HEIGHT = 640, 540
local SCROLL_STEP = 60

local window
local News = {}

local function Account()
	GamepadXIVAccountDB = GamepadXIVAccountDB or {}
	return GamepadXIVAccountDB
end

-- "v0.1.27" -> { 0, 1, 27 }
local function Parts(version)
	local parts = {}
	-- Only the dotted numbers: "v0.2.0-beta1" and "v0.1.27-5-gab12" are 0.2.0 and 0.1.27.
	local numbers = tostring(version or ""):match("^v?([%d%.]+)") or ""
	for number in numbers:gmatch("%d+") do
		parts[#parts + 1] = tonumber(number)
	end
	return parts
end

local function Newer(a, b)
	local pa, pb = Parts(a), Parts(b)
	for i = 1, math.max(#pa, #pb) do
		local x, y = pa[i] or 0, pb[i] or 0
		if x ~= y then
			return x > y
		end
	end
	return false
end

-- The version running: the .toc's, or the newest in the changelog when the .toc isn't filled in (a
-- copy straight from the repository).
local function CurrentVersion()
	local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	local version = get and get("GamepadXIV", "Version")
	if type(version) == "string" and version:match("^v?%d") then
		return version:sub(1, 1) == "v" and version or ("v" .. version)
	end
	return ns.CHANGELOG and ns.CHANGELOG[1] and ns.CHANGELOG[1].version or nil
end

ns.AddonVersion, ns.VersionNewer = CurrentVersion, Newer

-- The changelog as text: the versions after `since` (all when nil), newest first.
local function ChangelogText(since)
	local out = {}
	for _, entry in ipairs(ns.CHANGELOG or {}) do
		if not since or Newer(entry.version, since) then
			out[#out + 1] = "|cffffd100" .. entry.version .. "|r"
			for _, line in ipairs(entry.lines) do
				local kind, text = line[1], line[2]
				if kind == "h" then
					out[#out + 1] = "\n|cff99ccff" .. text .. "|r"
				elseif kind == "--" then
					out[#out + 1] = "        - " .. text
				else
					out[#out + 1] = "  • " .. text
				end
			end
			out[#out + 1] = "\n"
		end
	end
	if #out == 0 then
		return "Nothing new."
	end
	return table.concat(out, "\n")
end

local function Flat(frame, color, edge)
	frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	frame:SetBackdropColor(unpack(color))
	frame:SetBackdropBorderColor(unpack(edge or { 1, 1, 1, 0.1 }))
end

local function ShowWhenUpdated()
	return ns.db and ns.db.changelogShow ~= "never"
end

local function UpdateFooter()
	if not window then
		return
	end
	local toggle = ShowWhenUpdated() and "Don't show after updates" or "Show after updates"
	window.footer:SetText(ns.ButtonText("{PADDUP}{PADDDOWN} Scroll     {PAD3} " .. toggle .. "     {PAD2} Close", 18))
end

local function Scroll(delta)
	local scroll = window.scroll
	local max = math.max(0, window.text:GetStringHeight() - scroll:GetHeight() + 20)
	scroll:SetVerticalScroll(math.max(0, math.min(max, scroll:GetVerticalScroll() + delta)))
end

local NAV = { PADDUP = "Up", PADDDOWN = "Down", PAD2 = "Close", PAD3 = "Toggle", PAD1 = "Close" }
local ACTIONS = {
	Up = function() Scroll(-SCROLL_STEP) end,
	Down = function() Scroll(SCROLL_STEP) end,
	Close = function() window:Hide() end,
	Toggle = function()
		ns.db.changelogShow = ShowWhenUpdated() and "never" or "update"
		UpdateFooter()
		ns.Print("The changelog " .. (ShowWhenUpdated() and "shows once after each update." or "no longer shows after updates. It's still in the settings, General tab."))
	end,
}

local function CreateWindow()
	window = CreateFrame("Frame", "GamepadXIVNewsFrame", UIParent, "BackdropTemplate")
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
	bar:SetHeight(38)
	bar:SetColorTexture(0.1, 0.1, 0.125, 1)
	local icon = window:CreateTexture(nil, "ARTWORK")
	icon:SetSize(22, 22)
	icon:SetPoint("LEFT", bar, "LEFT", 12, 0)
	icon:SetTexture(ns.ICON)
	window.title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	window.title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
	local close = CreateFrame("Button", nil, window, "BackdropTemplate")
	close:SetSize(26, 26)
	Flat(close, CONTROL)
	close:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
	local closeText = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	closeText:SetPoint("CENTER")
	closeText:SetText("X")
	close:SetScript("OnClick", function() window:Hide() end)

	local scroll = CreateFrame("ScrollFrame", nil, window)
	scroll:SetPoint("TOPLEFT", 20, -52)
	scroll:SetPoint("BOTTOMRIGHT", -20, 52)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(_, delta)
		Scroll(-delta * SCROLL_STEP)
	end)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(WIDTH - 40, 10)
	scroll:SetScrollChild(child)
	window.text = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	window.text:SetPoint("TOPLEFT")
	window.text:SetWidth(WIDTH - 50)
	window.text:SetJustifyH("LEFT")
	window.text:SetSpacing(3)
	window.scroll = scroll
	window.child = child

	local footerBar = window:CreateTexture(nil, "BACKGROUND", nil, 1)
	footerBar:SetPoint("BOTTOMLEFT", 1, 1)
	footerBar:SetPoint("BOTTOMRIGHT", -1, 1)
	footerBar:SetHeight(40)
	footerBar:SetColorTexture(0.1, 0.1, 0.125, 1)
	window.footer = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	window.footer:SetPoint("CENTER", footerBar, "CENTER")

	for name, action in pairs(ACTIONS) do
		local button = CreateFrame("Button", "GamepadXIVNewsNav" .. name, window)
		local function OnClick()
			if window:IsShown() then
				action()
			end
		end
		-- Holding the D-pad keeps scrolling.
		if name == "Up" or name == "Down" then
			ns.RepeatOnHold(button, OnClick)
		else
			button:RegisterForClicks("AnyDown")
			button:SetScript("OnClick", OnClick)
		end
	end
	-- The controller works the window while it is open; bindings can't change in combat, so it closes then.
	window:SetScript("OnShow", function()
		if not InCombatLockdown() then
			for key, name in pairs(NAV) do
				SetOverrideBindingClick(window, true, key, "GamepadXIVNewsNav" .. name, "LeftButton")
			end
		end
	end)
	window:SetScript("OnHide", function()
		if not InCombatLockdown() then
			ClearOverrideBindings(window)
		end
	end)
	window:SetScript("OnEvent", function()
		window:Hide()
	end)
	window:RegisterEvent("PLAYER_REGEN_DISABLED")
	if InputDeviceIconSetManager and InputDeviceIconSetManager.RegisterActiveInputDeviceIconSetUpdatedCallback then
		InputDeviceIconSetManager:RegisterActiveInputDeviceIconSetUpdatedCallback(UpdateFooter, window)
	end
end

-- Shows the changelog: the versions after `since`, or all of them.
function ns.ShowChangelog(since)
	if InCombatLockdown() then
		ns.Print("The changelog is not available in combat.")
		return
	end
	if not window then
		CreateWindow()
	end
	window.title:SetText(since and "What's new in Gamepad XIV" or "Gamepad XIV changelog")
	window.text:SetText(ChangelogText(since))
	window.child:SetHeight(window.text:GetStringHeight() + 20)
	window.scroll:SetVerticalScroll(0)
	UpdateFooter()
	window:Show()
end

-- After an update: once, with what changed since the version you had.
local function CheckForUpdate()
	local current = CurrentVersion()
	if not current or not ns.db then
		return
	end
	local account = Account()
	local seen = account.changelogSeen
	if not seen then
		if not News.playedBefore then
			account.changelogSeen = current -- a new install: the tutorial shows instead
			return
		end
		-- Played before the changelog window existed: show the newest version's changes.
		local list = ns.CHANGELOG or {}
		seen = list[2] and list[2].version or "v0"
	end
	if not Newer(current, seen) then
		return
	end
	if not ShowWhenUpdated() then
		account.changelogSeen = current
		return
	end
	if InCombatLockdown() or (ns.IsTutorialShown and ns.IsTutorialShown()) then
		return -- tried again on the next loading screen
	end
	account.changelogSeen = current
	ns.ShowChangelog(seen)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" then
		-- Whether this account played before, read before this session's tutorial can set it.
		if name == "GamepadXIV" then
			News.playedBefore = GamepadXIVAccountDB and GamepadXIVAccountDB.tutorialSeen and true or false
		end
		return
	end
	C_Timer.After(4, CheckForUpdate)
end)
