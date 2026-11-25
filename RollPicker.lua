local _, ns = ...

-- Loot rolls during a fight. Forever shows its roll window in combat, and its own Back is what focuses
-- it, but Back can't change once a fight has begun, and it is the chat box's then. So Back on a roll in
-- combat opens this picker instead: it reads the controller buttons itself (no bindings, which can't
-- change in combat) and rolls with RollOnLoot, the game's own call, not Forever's code.
-- {PAD1} Need, {PAD3} Greed, {PAD2} Pass (asked twice), as in Forever's roll window; {PADBACK} closes it.

local GOLD = { 1, 0.82, 0 }
local WHITE = "Interface\\Buttons\\WHITE8X8"
local ROLL_FRAMES = { "GamepadGroupLootRollFrame", "GroupLootFrame1", "GroupLootFrame2", "GroupLootFrame3", "GroupLootFrame4" }
local NEED, GREED, PASS = 1, 2, 0

local picker
local pending = {} -- rollID = when it runs out
local pickedRoll
local confirmPass -- {PAD2} pressed once: a second press passes

local function Log(...)
	if ns.PlayLog then
		ns.PlayLog("roll picker:", ...)
	end
end

-- The roll window showing, if any.
local function ShownRollFrame()
	for _, name in ipairs(ROLL_FRAMES) do
		local frame = _G[name]
		if frame and frame.IsVisible and frame:IsVisible() then
			return frame
		end
	end
end

-- The roll to pick for: the one in Forever's window, else the newest still open.
local function CurrentRoll()
	local frame = ShownRollFrame()
	local id = frame and frame.rollID
	if id and GetLootRollItemLink(id) then
		return id
	end
	local best, bestEnds
	local now = GetTime()
	for rollID, ends in pairs(pending) do
		if ends <= now or not GetLootRollItemLink(rollID) then
			pending[rollID] = nil
		elseif not bestEnds or ends > bestEnds then
			best, bestEnds = rollID, ends
		end
	end
	return best
end

function ns.RollPickerShown()
	return picker ~= nil and picker:IsShown()
end

function ns.RollWaiting()
	return ShownRollFrame() ~= nil and CurrentRoll() ~= nil
end

local function Close(why)
	if picker and picker:IsShown() then
		Log("closed", why or "")
		picker:Hide()
	end
	pickedRoll = nil
	confirmPass = nil
end

local function Choice(key, label, allowed)
	local text = ns.ButtonText("{" .. key .. "} " .. label, 18)
	return allowed and text or ("|cff777777" .. text .. "|r")
end

local function Draw()
	local rollID = pickedRoll
	local link = rollID and GetLootRollItemLink(rollID)
	if not link then
		Close("roll gone")
		return
	end
	local _, _, _, _, _, canNeed, canGreed = GetLootRollItemInfo(rollID)
	picker.item:SetText(link)
	if confirmPass then
		picker.keys:SetText("|cffff8080Pass on this item?|r     " .. ns.ButtonText("{PAD2} Yes, pass     {PADBACK} No", 18))
	else
		picker.keys:SetText(Choice("PAD1", "Need", canNeed) .. "     " .. Choice("PAD3", "Greed", canGreed)
			.. "     " .. Choice("PAD2", "Pass", true) .. "     " .. ns.ButtonText("{PADBACK} Close", 18))
	end
	picker:SetWidth(math.max(picker.keys:GetStringWidth() or 0, picker.item:GetStringWidth() or 0, 260) + 32)
end

local function Roll(kind)
	local rollID = pickedRoll
	if not rollID or not GetLootRollItemLink(rollID) then
		Close("roll gone")
		return
	end
	local _, _, _, _, _, canNeed, canGreed = GetLootRollItemInfo(rollID)
	if (kind == NEED and not canNeed) or (kind == GREED and not canGreed) then
		return
	end
	Log("rolled", kind == NEED and "need" or kind == GREED and "greed" or "pass", "on", tostring(rollID))
	local ok, err = pcall(RollOnLoot, rollID, kind)
	if not ok then
		Log("RollOnLoot failed:", tostring(err))
		ns.Print("The roll could not be made from here: press Back on the roll once the fight ends.")
	end
	pending[rollID] = nil
	Close("rolled")
end

local function Create()
	picker = CreateFrame("Frame", "GamepadXIVRollPicker", UIParent, "BackdropTemplate")
	picker:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 2 })
	picker:SetBackdropColor(0.04, 0.04, 0.06, 0.94)
	picker:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 0.95)
	picker:SetFrameStrata("FULLSCREEN_DIALOG")
	picker:SetHeight(64)
	picker:Hide()
	picker.item = picker:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	picker.item:SetPoint("TOP", 0, -10)
	picker.keys = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	picker.keys:SetPoint("BOTTOM", 0, 12)
	-- Forever's roll buttons: {PAD1} Need, {PAD3} Greed, {PAD2} Pass. The rest go on to the game
	-- (moving, the camera) where it lets them; Back closes the picker.
	local ROLL_KEYS = { PAD1 = NEED, PAD3 = GREED, PAD2 = PASS }
	picker:SetScript("OnGamePadButtonDown", function(self, button)
		local kind = ROLL_KEYS[button]
		local mine = kind ~= nil or button == "PADBACK"
		local ok = pcall(self.SetPropagateGamePadInput, self, not mine)
		Log("button", tostring(button), mine and "" or (ok and "passed on" or "kept (can't pass on in combat)"))
		if kind == PASS and not confirmPass then
			-- Passing asks first: the item is gone for good.
			confirmPass = true
			Log("pass asked")
			Draw()
		elseif kind then
			confirmPass = nil
			Roll(kind)
		elseif button == "PADBACK" and confirmPass then
			confirmPass = nil
			Log("pass cancelled")
			Draw()
		elseif button == "PADBACK" then
			Close("by hand")
		end
	end)
	picker:SetScript("OnHide", function()
		pcall(picker.EnableGamePadButton, picker, false)
		-- Typing in the chat box: it reads the buttons again.
		if ns.ChatBoxReadPad then
			ns.ChatBoxReadPad(true)
		end
	end)
end

-- Back on a roll in combat (LfgFilter.lua's chat key button). Returns true when the picker opened.
function ns.OpenRollPicker()
	local frame = ShownRollFrame()
	local rollID = frame and CurrentRoll()
	if not rollID then
		Log("no roll to pick for: window", tostring(frame and frame:GetName()), "pending", tostring(next(pending)))
		return false
	end
	if not picker then
		Create()
	end
	pickedRoll = rollID
	confirmPass = nil
	picker:ClearAllPoints()
	local frame = ShownRollFrame()
	if frame then
		picker:SetPoint("BOTTOM", frame, "TOP", 0, 10)
	else
		picker:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
	end
	-- The picker takes the controller buttons while it shows, before any binding, and the chat box
	-- stops reading them meanwhile.
	if ns.ChatBoxReadPad then
		ns.ChatBoxReadPad(false)
	end
	local ok, err = pcall(picker.EnableGamePadButton, picker, true)
	if not ok then
		Log("can't read the controller:", tostring(err))
		ns.Print("Loot rolls can be picked with Back once the fight ends.")
		return true
	end
	picker:Show()
	Draw()
	Log("opened for", tostring(rollID), "reads buttons", tostring(picker.IsGamePadButtonEnabled and picker:IsGamePadButtonEnabled()),
		"window protected", tostring(frame and frame.IsProtected and frame:IsProtected()))
	return true
end

local events = CreateFrame("Frame")
events:RegisterEvent("START_LOOT_ROLL")
events:RegisterEvent("CANCEL_LOOT_ROLL")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, rollID, rollTime)
	if event == "START_LOOT_ROLL" then
		pending[rollID] = GetTime() + (tonumber(rollTime) or 60000) / 1000
		Log("roll started", tostring(rollID), InCombatLockdown() and "in combat" or "")
	elseif event == "CANCEL_LOOT_ROLL" then
		pending[rollID] = nil
		if rollID == pickedRoll then
			Close("roll ended")
		end
	else
		-- Out of combat Back is Forever's on the roll again.
		Close("fight over")
	end
end)
