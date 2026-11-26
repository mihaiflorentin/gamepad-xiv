local _, ns = ...

-- The navigation core for the addon's own windows (docs/UI-REPLACEMENT-PLAN.md, "Architecture").
--
-- * Windows register with ns.NavRegister: a name, a priority group, an IsOpen test and handlers for
--   the controller keys. ns.NavFocus gives a window the controller; ns.NavCycle steps through the open
--   windows in priority order, both ways, as Back does (FFXIV's HUD cycle).
-- * While a window has the focus, the keys it handles are override bindings to hidden buttons
--   ("GamepadXIVNav<Key>") that call the window's handler, as the chat box does. Bindings only change
--   out of combat, so the focus ends when combat starts (the window stays open, like FFXIV's Cancel)
--   and the keys go back to the bars.
-- * ns.NavPick moves a cursor between buttons by their place on screen, for grids such as the bags.
--
-- Nothing here touches Blizzard's frames or its gamepad systems.

-- Priority groups: popups first, then windows that trade with someone, then the player's own windows,
-- then the HUD. A window's place inside its group is its own `order`. Players can change both in the
-- settings (ns.db.navOrder[name] replaces the number, ns.db.navSkip[name] takes a window out).
ns.NAV_GROUPS = { popup = 100, transaction = 200, player = 300, hud = 400 }

-- The keys a focused window can take. Back and Start stay with the cycle and the game.
ns.NAV_KEYS = {
	"PADDUP", "PADDDOWN", "PADDLEFT", "PADDRIGHT",
	"PAD1", "PAD2", "PAD3", "PAD4",
	"PADLSHOULDER", "PADRSHOULDER", "PADLTRIGGER", "PADRTRIGGER",
	"PADLSTICK", "PADRSTICK",
}
-- These repeat while held (Repeat.lua).
local HELD = { PADDUP = true, PADDDOWN = true, PADDLEFT = true, PADDRIGHT = true }

local Nav = { windows = {}, list = {}, focused = nil, buttons = {} }
ns.Nav = Nav

local owner = CreateFrame("Frame") -- holds the keys of the focused window

function ns.NavLog(...)
	if ns.PlayLog then
		ns.PlayLog("nav:", ...)
	end
end

---------------------------------------------------------------------------------------------------
-- The registry

-- window = {
--   name = "Bags", group = "player", order = 10,
--   IsOpen = function() return frame:IsShown() end,
--   keys = { PADDUP = function() ... end, PAD1 = ..., ... },  -- the keys it takes while focused
--   clicks = { PAD1 = function() return "SlotName", "RightButton" end },
--       -- keys bound straight to a real button (a bag slot), so the game's own secure click runs.
--       -- The window calls ns.NavRebindClicks() when its cursor moves.
--   OnFocus = function() end, OnBlur = function() end,        -- optional
--   Hint = function() return "{PAD1} Use   {PAD2} Back" end,  -- optional footer text
-- }
function ns.NavRegister(window)
	assert(type(window) == "table" and type(window.name) == "string", "NavRegister: a window needs a name")
	assert(type(window.IsOpen) == "function", "NavRegister: " .. window.name .. " needs IsOpen")
	window.keys = window.keys or {}
	window.clicks = window.clicks or {}
	if not Nav.windows[window.name] then
		table.insert(Nav.list, window)
	end
	Nav.windows[window.name] = window
	return window
end

function ns.NavWindow(name)
	return Nav.windows[name]
end

local function Settings(field)
	local db = ns.db
	return db and type(db[field]) == "table" and db[field] or nil
end

-- A window's place in the cycle: its group's number plus its order, or the player's number for it.
function ns.NavPriority(window)
	local custom = Settings("navOrder")
	local value = custom and tonumber(custom[window.name])
	if value then
		return value
	end
	return (ns.NAV_GROUPS[window.group] or ns.NAV_GROUPS.player) + (tonumber(window.order) or 50)
end

local function Skipped(window)
	local skip = Settings("navSkip")
	return skip and skip[window.name] and true or false
end

local function IsOpen(window)
	local ok, open = pcall(window.IsOpen)
	return ok and open and true or false
end

-- The open windows the cycle visits, in priority order (ties keep the order they registered in).
function ns.NavOpenWindows()
	local open = {}
	for index, window in ipairs(Nav.list) do
		if not Skipped(window) and IsOpen(window) then
			table.insert(open, { window = window, priority = ns.NavPriority(window), index = index })
		end
	end
	table.sort(open, function(a, b)
		if a.priority ~= b.priority then
			return a.priority < b.priority
		end
		return a.index < b.index
	end)
	for i, entry in ipairs(open) do
		open[i] = entry.window
	end
	return open
end

---------------------------------------------------------------------------------------------------
-- The keys

local function KeyButton(key)
	local button = Nav.buttons[key]
	if button then
		return button
	end
	button = CreateFrame("Button", "GamepadXIVNav" .. key, UIParent)
	button:Hide()
	local function Press()
		local window = Nav.focused
		local handler = window and window.keys[key]
		if not handler then
			return
		end
		local ok, err = pcall(handler, key)
		if not ok then
			ns.NavLog("error in", window.name, key, tostring(err))
			geterrorhandler()(err)
		end
		ns.NavRebindClicks()
		Nav.Redraw()
	end
	if HELD[key] and ns.RepeatOnHold then
		ns.RepeatOnHold(button, Press, function() return Nav.focused and Nav.focused.name end)
	else
		button:RegisterForClicks("AnyDown")
		button:SetScript("OnClick", Press)
	end
	Nav.buttons[key] = button
	return button
end

-- The real button a click key presses now: its name and mouse button, or nil.
local function ClickTarget(window, key)
	local fn = window and window.clicks[key]
	if not fn then
		return nil
	end
	local ok, name, mouse = pcall(fn)
	if ok and type(name) == "string" and name ~= "" then
		return name, mouse or "LeftButton"
	end
	return nil
end

-- What a key of the focused window should be bound to, as GetBindingAction shows it.
local function Expected(window, key)
	local name, mouse = ClickTarget(window, key)
	if name then
		return "CLICK " .. name .. ":" .. mouse
	elseif window.keys[key] then
		return "CLICK GamepadXIVNav" .. key .. ":LeftButton"
	end
	return nil
end

-- Binds the focused window's keys, or gives them all back. Out of combat only.
function Nav.ApplyBindings()
	if InCombatLockdown() then
		return false
	end
	ClearOverrideBindings(owner)
	local window = Nav.focused
	if window then
		for _, key in ipairs(ns.NAV_KEYS) do
			local name, mouse = ClickTarget(window, key)
			if name then
				SetOverrideBindingClick(owner, true, key, name, mouse)
			elseif window.keys[key] then
				SetOverrideBindingClick(owner, true, key, KeyButton(key):GetName(), "LeftButton")
			end
		end
	end
	return true
end

-- The focused window's cursor moved: its click keys press the button it is on now.
function ns.NavRebindClicks()
	local window = Nav.focused
	if not window or InCombatLockdown() then
		return false
	end
	for _, key in ipairs(ns.NAV_KEYS) do
		if window.clicks[key] then
			local name, mouse = ClickTarget(window, key)
			if name then
				SetOverrideBindingClick(owner, true, key, name, mouse)
			elseif window.keys[key] then
				SetOverrideBindingClick(owner, true, key, KeyButton(key):GetName(), "LeftButton")
			else
				SetOverrideBinding(owner, true, key, nil)
			end
		end
	end
	return true
end

-- Another binding took one of the focused window's keys (the addon's driver sets its own again at
-- times). Bind them again.
function Nav.BindingsLost()
	local window = Nav.focused
	if not window or InCombatLockdown() then
		return false
	end
	for _, key in ipairs(ns.NAV_KEYS) do
		local expected = Expected(window, key)
		if expected and GetBindingAction(key, true) ~= expected then
			return true
		end
	end
	return false
end

---------------------------------------------------------------------------------------------------
-- Back: while one of the addon's windows is open (out of combat), Back steps through them.

local backOwner = CreateFrame("Frame")
local backButton = CreateFrame("Button", "GamepadXIVNavBack", UIParent)
backButton:Hide()
backButton:RegisterForClicks("AnyDown")
backButton:SetScript("OnClick", function()
	ns.NavCycle(1)
	Nav.Redraw()
end)
local backBound = false

function Nav.UpdateBack()
	if InCombatLockdown() then
		return
	end
	local want = #ns.NavOpenWindows() > 0
	if want and (not backBound or GetBindingAction("PADBACK", true) ~= "CLICK GamepadXIVNavBack:LeftButton") then
		SetOverrideBindingClick(backOwner, true, "PADBACK", "GamepadXIVNavBack", "LeftButton")
		backBound = true
	elseif not want and backBound then
		ClearOverrideBindings(backOwner)
		backBound = false
	end
end

function ns.NavBackBound()
	return backBound
end

---------------------------------------------------------------------------------------------------
-- Focus

function Nav.Redraw()
	local window = Nav.focused
	if window and window.Redraw then
		pcall(window.Redraw)
	end
end

local function Call(window, name)
	local fn = window and window[name]
	if fn then
		local ok, err = pcall(fn)
		if not ok then
			geterrorhandler()(err)
		end
	end
end

-- Gives `name` the controller (nil: nobody). False when it can't happen now: in combat, or the window
-- isn't open.
function ns.NavFocus(name)
	local window = name and Nav.windows[name]
	if name and not (window and IsOpen(window)) then
		return false
	end
	if InCombatLockdown() then
		return false
	end
	local old = Nav.focused
	if old == window then
		return true
	end
	Nav.focused = window
	Nav.ApplyBindings()
	Call(old, "OnBlur")
	Call(window, "OnFocus")
	ns.NavLog("focus", old and old.name or "none", "->", window and window.name or "none")
	return true
end

function ns.NavFocused()
	return Nav.focused and Nav.focused.name or nil
end

-- Back: the next open window after the focused one (delta 1), or the one before (-1), round and round.
-- With nothing focused, the first (or last). Returns the window focused, or nil when none is open.
function ns.NavCycle(delta)
	delta = delta or 1
	local open = ns.NavOpenWindows()
	if #open == 0 then
		ns.NavFocus(nil)
		return nil
	end
	local index
	for i, window in ipairs(open) do
		if window == Nav.focused then
			index = i
		end
	end
	if index then
		index = index + delta
		if index > #open then
			index = 1
		elseif index < 1 then
			index = #open
		end
	else
		index = delta < 0 and #open or 1
	end
	local window = open[index]
	ns.NavFocus(window.name)
	return window.name
end

-- A window calls this when it closes, so the focus moves on to the next open one (or ends).
function ns.NavClosed(name)
	if Nav.focused and Nav.focused.name == name then
		local open = ns.NavOpenWindows()
		ns.NavFocus(open[1] and open[1].name or nil)
	end
end

-- A window that should take the controller as it opens (popups, trade) calls this.
function ns.NavOpened(name)
	local window = Nav.windows[name]
	if not window then
		return false
	end
	local current = Nav.focused
	if current and IsOpen(current) and ns.NavPriority(current) <= ns.NavPriority(window) then
		return false -- something at least as important has it
	end
	return ns.NavFocus(name)
end

---------------------------------------------------------------------------------------------------
-- Moving a cursor by screen position

-- `nodes` is a list of buttons (anything with GetRect, or tables with l, b, w, h). From the node at
-- index `from`, returns the index of the nearest node in `direction` ("UP", "DOWN", "LEFT", "RIGHT").
-- With nothing that way it wraps to the far side of the same row or column, or stays (wrap = false,
-- or the D-pad is held, ns.Repeating).
local function Center(node)
	local l, b, w, h
	if type(node) == "table" and node.GetRect then
		l, b, w, h = node:GetRect()
	elseif type(node) == "table" then
		l, b, w, h = node.l, node.b, node.w, node.h
	end
	if not l then
		return nil
	end
	return l + w / 2, b + h / 2, w, h
end

local AXES = {
	RIGHT = { 1, 0 }, LEFT = { -1, 0 }, UP = { 0, 1 }, DOWN = { 0, -1 },
}

function ns.NavPick(nodes, from, direction, wrap)
	local axis = AXES[direction]
	local x0, y0, w0, h0 = Center(nodes[from])
	if not axis or not x0 then
		return from
	end
	local horizontal = axis[1] ~= 0
	local best, bestScore
	local centers = {}
	for i, node in ipairs(nodes) do
		local x, y = Center(node)
		centers[i] = x and { x, y } or false
		if i ~= from and x then
			local along = (x - x0) * axis[1] + (y - y0) * axis[2] -- distance in the direction
			local across = horizontal and math.abs(y - y0) or math.abs(x - x0)
			-- Ahead, and closer to straight ahead than 45 degrees.
			if along > 0.5 and across <= along then
				local score = along + across * 2
				if not bestScore or score < bestScore then
					best, bestScore = i, score
				end
			end
		end
	end
	if best then
		return best
	end
	if wrap == false or ns.Repeating then
		return from
	end
	-- Wrap: the node furthest the other way in the same row (or column).
	local band = (horizontal and h0 or w0) / 2
	local far, farValue
	for i, center in ipairs(centers) do
		if i ~= from and center then
			local across = horizontal and math.abs(center[2] - y0) or math.abs(center[1] - x0)
			if across <= band then
				local value = horizontal and center[1] * -axis[1] or center[2] * -axis[2]
				if not farValue or value > farValue then
					far, farValue = i, value
				end
			end
		end
	end
	return far or from
end

---------------------------------------------------------------------------------------------------
-- Footer hints

-- The focused window's hint, with the buttons drawn as icons of the controller in use.
function ns.NavHint(window, size)
	window = window or Nav.focused
	if not (window and window.Hint) then
		return ""
	end
	local ok, text = pcall(window.Hint)
	if not ok or type(text) ~= "string" then
		return ""
	end
	return ns.ButtonText and ns.ButtonText(text, size or 14) or text
end

---------------------------------------------------------------------------------------------------
-- Combat: the focus ends and the keys go back to the bars before the lockdown starts. Afterwards the
-- keys come back if a window took them again in the meantime (the driver can rebind).

owner:RegisterEvent("PLAYER_REGEN_DISABLED")
owner:RegisterEvent("PLAYER_REGEN_ENABLED")
owner:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_REGEN_DISABLED" then
		if Nav.focused then
			ns.NavLog("combat: focus ends on", Nav.focused.name)
			ns.NavFocus(nil)
		end
		if backBound then
			ClearOverrideBindings(backOwner)
			backBound = false
		end
	end
end)

-- Keeps the keys bound while a window has the focus, and drops the focus of a window that closed
-- without saying so.
local watch = CreateFrame("Frame")
local since = 0
watch:SetScript("OnUpdate", function(_, elapsed)
	since = since + elapsed
	if since < 0.25 then
		return
	end
	since = 0
	if InCombatLockdown() then
		return
	end
	Nav.UpdateBack()
	local window = Nav.focused
	if not window then
		return
	end
	if not IsOpen(window) then
		ns.NavClosed(window.name)
	elseif Nav.BindingsLost() then
		ns.NavLog("keys lost, binding again for", window.name)
		Nav.ApplyBindings()
	end
end)
