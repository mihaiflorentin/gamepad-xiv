local _, ns = ...

-- Holding a D-pad direction in the addon's own windows keeps moving: one step on the press, as
-- before, then after REPEAT_DELAY one step every REPEAT_INTERVAL until the button is let go.
-- Only for plain (not secure) buttons that a D-pad key clicks through a CLICK binding. Targeting
-- goes through secure buttons and repeats in Snippets.lua (HoldTick) instead.
local REPEAT_DELAY = 0.3
local REPEAT_INTERVAL = 0.09
-- The right stick's up and down count too (the chat box scrolls with them); they are keys while
-- GamePadStickAxisButtons is on, which Input.lua sets.
local DPAD = { "PADDUP", "PADDDOWN", "PADDLEFT", "PADDRIGHT", "PADRSTICKUP", "PADRSTICKDOWN" }
-- How a held key is read: IsKeyDown, or the controller state, whose button indexes start at 0 on
-- some clients and 1 on others. The press finds the one that sees the key down.
local CHECKS = { "key", 1, 0 }

local held -- the press being repeated
local ticker

local function KeyDown(key, check)
	if check == "key" then
		local ok, down = pcall(IsKeyDown, key)
		return ok and down and true or false
	end
	if not (C_GamePad and C_GamePad.GetDeviceMappedState and C_GamePad.ButtonIndexToBinding) then
		return false
	end
	local ok, state = pcall(C_GamePad.GetDeviceMappedState)
	if (not ok or type(state) ~= "table") and C_GamePad.GetActiveDeviceID then
		ok, state = pcall(C_GamePad.GetDeviceMappedState, C_GamePad.GetActiveDeviceID())
	end
	if not ok or type(state) ~= "table" or type(state.buttons) ~= "table" then
		return false
	end
	for i, pressed in ipairs(state.buttons) do
		if pressed then
			local okName, name = pcall(C_GamePad.ButtonIndexToBinding, i - check)
			if okName and name == key then
				return true
			end
		end
	end
	return false
end

-- The D-pad key that clicked the button and is held now, with the binding and the way to read it.
-- Nothing when the press came another way (a mouse, another key) or the key can't be read: then a
-- press is a single step, as before.
local function FindHeldKey(button)
	local name = button:GetName()
	if not name then
		return
	end
	local command = "CLICK " .. name .. ":LeftButton"
	for _, key in ipairs(DPAD) do
		if GetBindingAction(key, true) == command then
			for _, check in ipairs(CHECKS) do
				if KeyDown(key, check) then
					return key, command, check
				end
			end
		end
	end
end

-- What `context` answers; an error in it ends the repeat rather than the press.
local function Ask(context)
	local ok, value = pcall(context)
	return ok and value or false
end

local function Stop()
	held = nil
	if ticker then
		ticker:Hide()
	end
end

local function Tick(_, elapsed)
	local hold = held
	if not hold then
		Stop()
		return
	end
	-- The release only reaches the button while the key is still bound to it, so a window that
	-- closed or took the key mid-hold, or the key read as up, ends the hold too.
	if GetBindingAction(hold.key, true) ~= hold.command or not KeyDown(hold.key, hold.check) then
		Stop()
		return
	end
	hold.wait = hold.wait - elapsed
	if hold.wait > 0 then
		return
	end
	hold.wait = math.max(hold.wait + REPEAT_INTERVAL, 0.01)
	if hold.context and Ask(hold.context) ~= hold.value then
		Stop()
		return
	end
	ns.Repeating = true
	local ok, err = pcall(hold.onClick, hold.button, "LeftButton", true)
	ns.Repeating = nil
	if not ok then
		Stop()
		geterrorhandler()(err)
	end
end

-- Makes `button` repeat `onClick` while a D-pad key that clicks it is held. `onClick` is the whole
-- press, checks included; the button gets it as its OnClick for the press and ignores the release.
-- `context`, if given, is asked before the press: false means this press doesn't repeat (such as
-- a toggle, which would flip back and forth), and the repeat goes on only while it answers the same
-- (it ends once the press moved to another tab, list or window).
function ns.RepeatOnHold(button, onClick, context)
	if not ticker then
		ticker = CreateFrame("Frame")
		ticker:Hide()
		ticker:SetScript("OnUpdate", Tick)
	end
	button:RegisterForClicks("AnyDown", "AnyUp")
	button:SetScript("OnClick", function(_, mouse, down)
		if down == false then
			if held and held.button == button then
				Stop()
			end
			return
		end
		Stop()
		local value = context and Ask(context)
		onClick(button, mouse, down)
		if context and not value then
			return
		end
		local key, command, check = FindHeldKey(button)
		if key then
			held = { button = button, onClick = onClick, context = context, value = value,
				key = key, command = command, check = check, wait = REPEAT_DELAY }
			ticker:Show()
		end
	end)
end

-- A cursor's next place in a list of `count`: past the last goes to the first and before the first to
-- the last, the rule for every list moved with the D-pad. A held D-pad stops at the ends instead, so
-- holding it doesn't run round and round.
function ns.StepWrap(index, delta, count)
	index = (index or 1) + delta
	if not count or count < 1 then
		return index
	elseif index < 1 then
		return ns.Repeating and 1 or count
	elseif index > count then
		return ns.Repeating and count or 1
	end
	return index
end
