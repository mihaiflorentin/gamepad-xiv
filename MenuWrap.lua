local _, ns = ...

-- The game's menus (a unit's right-click menu, dropdowns) wrap with the controller: {PADDUP} on the
-- first entry goes to the last, {PADDDOWN} on the last to the first. Forever's navigation stops at the
-- ends. Nothing of Forever's is changed: while the cursor is on an end, the D-pad key is bound to a
-- secure macro button of the addon's that presses Forever's own other D-pad key as often as there are
-- entries ("/click" in a macro runs from the key press, like pressing it by hand). Out of combat only,
-- as bindings can't change in combat.

local UP_KEY, DOWN_KEY = "InputFunctionBindingButton_PADDUP", "InputFunctionBindingButton_PADDDOWN"
local MAX_STEPS = 8 -- the macro text stays under the game's length limit

local owner = CreateFrame("Frame")
local bound -- "top" or "bottom" while a D-pad key is ours
local lastButton, lastSeen -- for the log: where the cursor went, and the entry number
local buttons = {}

local function Log(...)
	if ns.PlayLog then
		ns.PlayLog("menu wrap:", ...)
	end
end

local function MacroButton(name)
	local button = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
	button:SetAttribute("type", "macro")
	button:RegisterForClicks("AnyDown")
	button:Hide()
	return button
end

local function Unbind(why)
	if bound and not InCombatLockdown() then
		ClearOverrideBindings(owner)
		Log("keys given back:", why)
		bound = nil
	end
end

-- The menu frame the cursor is in, if the cursor is in one of the game's menus.
local function MenuOf(button)
	local manager = Menu and Menu.GetManager and Menu.GetManager()
	if not (button and manager and manager.IsAnyMenuOpen and manager:IsAnyMenuOpen()) then
		return nil
	end
	local root = manager.GetOpenMenu and manager:GetOpenMenu()
	local frame = button:GetParent()
	while frame do
		if frame == root or frame.GetMenuDescription then
			return frame
		end
		frame = frame:GetParent()
	end
end

-- The entries the cursor can be on: the cursor's siblings that are shown, enabled buttons.
local function Entries(button)
	local list = {}
	local parent = button:GetParent()
	for _, child in ipairs({ parent:GetChildren() }) do
		if child:IsShown() and child.IsObjectType and child:IsObjectType("Button") and child:IsEnabled()
				and child:IsMouseEnabled() and child:GetTop() then
			list[#list + 1] = child
		end
	end
	return list
end

local function Check()
	if InCombatLockdown() then
		return
	end
	local current = SmartNavigation and SmartNavigation.currentButton
	local menu = current and current.GetParent and MenuOf(current)
	if not menu then
		Unbind("no menu")
		lastButton, lastSeen = nil, nil
		return
	end
	local entries = Entries(current)
	if #entries < 2 then
		Unbind("one entry")
		return
	end
	local top, bottom = current:GetTop(), current:GetTop()
	for _, entry in ipairs(entries) do
		top = math.max(top, entry:GetTop())
		bottom = math.min(bottom, entry:GetTop())
	end
	if current ~= lastButton then
		-- Entry number from the top, for the log.
		local number = 1
		for _, entry in ipairs(entries) do
			if entry:GetTop() > current:GetTop() + 0.5 then
				number = number + 1
			end
		end
		if bound or lastSeen then
			Log("cursor on entry", number, "of", #entries)
		end
		lastButton, lastSeen = current, number
	end
	local at = (current:GetTop() >= top - 0.5 and "top") or (current:GetTop() <= bottom + 0.5 and "bottom") or nil
	if at == bound then
		return
	end
	Unbind("moved off the end")
	if not at then
		return
	end
	-- Only over Forever's own D-pad keys: anything else on them is left alone.
	local key = at == "top" and "PADDUP" or "PADDDOWN"
	local action = GetBindingAction(key, true) or ""
	if not action:find("InputFunctionBindingButton_", 1, true) then
		Log("not bound:", key, "is", action)
		return
	end
	local steps = math.min(#entries - 1, MAX_STEPS)
	local target = at == "top" and DOWN_KEY or UP_KEY
	local name = at == "top" and "GamepadXIVMenuWrapToBottom" or "GamepadXIVMenuWrapToTop"
	buttons[name] = buttons[name] or MacroButton(name)
	buttons[name]:SetAttribute("macrotext", string.rep("/click " .. target .. " LeftButton true\n/click " .. target .. " LeftButton false\n", steps))
	SetOverrideBindingClick(owner, true, key, name, "LeftButton")
	bound = at
	Log("on the", at, "of", #entries, "entries:", key, "goes", steps, "steps the other way")
end

local elapsed = 0
owner:SetScript("OnUpdate", function(_, delta)
	elapsed = elapsed + delta
	if elapsed >= 0.05 then
		elapsed = 0
		local ok, err = pcall(Check)
		if not ok then
			Log("error:", tostring(err))
			Unbind("error")
		end
	end
end)
owner:RegisterEvent("PLAYER_REGEN_DISABLED")
owner:SetScript("OnEvent", function()
	-- Bindings can still change while this event runs.
	Unbind("combat")
end)
