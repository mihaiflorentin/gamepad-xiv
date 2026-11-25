-- Offline checks of hold-to-repeat for the D-pad in the addon's windows (Repeat.lua). Not loaded by the game.
-- Run from the addon folder with: lua5.1 tests/repeat.lua

local frames = {}
function CreateFrame(_, name)
	local frame = { name = name, scripts = {}, shown = true }
	function frame:SetScript(script, fn) self.scripts[script] = fn end
	function frame:RegisterForClicks(...) self.clicks = { ... } end
	function frame:Show() self.shown = true end
	function frame:Hide() self.shown = false end
	function frame:GetName() return self.name end
	table.insert(frames, frame)
	return frame
end

local bindings, keysDown = {}, {}
function GetBindingAction(key) return bindings[key] or "" end
function IsKeyDown(key) return keysDown[key] == true end
local errors = {}
function geterrorhandler() return function(err) table.insert(errors, err) end end

local ns = {}
assert(loadfile("Repeat.lua"))("GamepadXIV", ns)

local fails = 0
local function Check(label, actual, expected)
	if actual ~= expected then
		fails = fails + 1
		print("FAIL " .. label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

local count = 0
local button = CreateFrame("Button", "TestNavDown")
local contextValue = "list"
ns.RepeatOnHold(button, function() count = count + 1 end, function() return contextValue end)
local ticker = frames[1] ~= button and frames[1] or frames[2]
Check("button hears press and release", table.concat(button.clicks, ","), "AnyDown,AnyUp")

local function Press() keysDown.PADDDOWN = true; button.scripts.OnClick(button, "LeftButton", true) end
local function Release() keysDown.PADDDOWN = nil; button.scripts.OnClick(button, "LeftButton", false) end
local function Wait(seconds)
	-- Frames of 1/100 s, as OnUpdate runs while the ticker is shown.
	for _ = 1, math.floor(seconds * 100 + 0.5) do
		if ticker.shown then
			ticker.scripts.OnUpdate(ticker, 0.01)
		end
	end
end
local function Reset() count = 0; Release(); Wait(1); count = 0 end

bindings.PADDDOWN = "CLICK TestNavDown:LeftButton"

-- A tap moves once.
Press(); Release(); Wait(1)
Check("tap: one step", count, 1)
Reset()

-- A hold moves once, waits, then repeats until let go.
Press()
Check("hold: one step on the press", count, 1)
Wait(0.25)
Check("hold: nothing more before the delay", count, 1)
Wait(0.1)
Check("hold: repeats after the delay", count, 2)
Wait(0.5)
Check("hold: keeps repeating", count >= 6 and count <= 8, true)
local before = count
Release(); Wait(1)
Check("hold: stops on release", count, before)
Reset()

-- The release never reaches the button (the key was rebound mid-hold), but the key is up.
Press(); Wait(0.5)
keysDown.PADDDOWN = nil
before = count
Wait(1)
Check("lost release: stops once the key is up", count, before)
Check("lost release: ticker hidden", ticker.shown, false)
Reset()

-- A window that closed or took the key mid-hold.
Press(); Wait(0.5)
bindings.PADDDOWN = "CLICK SomethingElse:LeftButton"
before = count
Wait(1)
Check("binding gone: stops", count, before)
bindings.PADDDOWN = "CLICK TestNavDown:LeftButton"
Reset()

-- What the press works on changed (another tab or list): the repeat ends.
Press(); Wait(0.5)
contextValue = "other"
before = count
Wait(1)
Check("context changed: stops", count, before)
Reset()

-- Presses that should not repeat, such as on a toggle.
contextValue = false
Press(); Wait(1)
Check("no repeat where the context says so: one step", count, 1)
contextValue = "list"
Reset()

-- A press from a key that isn't the D-pad is a single step.
bindings.PADDDOWN = nil
bindings.PAD1 = "CLICK TestNavDown:LeftButton"
Press(); Wait(1)
Check("not the D-pad: one step", count, 1)
bindings.PADDDOWN, bindings.PAD1 = "CLICK TestNavDown:LeftButton", nil
Reset()

-- The right stick pushed down (the chat box scrolls with it) repeats like the D-pad.
bindings.PADDDOWN = nil
bindings.PADRSTICKDOWN = "CLICK TestNavDown:LeftButton"
keysDown.PADRSTICKDOWN = true
button.scripts.OnClick(button, "LeftButton", true)
Wait(0.5)
Check("right stick: repeats", count > 2, true)
keysDown.PADRSTICKDOWN = nil
before = count
Wait(1)
Check("right stick: stops once let go", count, before)
bindings.PADDDOWN, bindings.PADRSTICKDOWN = "CLICK TestNavDown:LeftButton", nil
Reset()

-- Clients where IsKeyDown doesn't know the controller: its state, with indexes from 0.
IsKeyDown = function() error("not a key") end
local padIndex = { [11] = "PADDDOWN" }
C_GamePad = {
	GetDeviceMappedState = function()
		local buttons = {}
		for i = 1, 16 do buttons[i] = false end
		buttons[12] = keysDown.PADDDOWN == true
		return { buttons = buttons, buttonCount = 16 }
	end,
	ButtonIndexToBinding = function(index) return padIndex[index] end,
}
Press(); Wait(0.5)
Check("controller state: repeats", count > 2, true)
keysDown.PADDDOWN = nil
before = count
Wait(1)
Check("controller state: stops once up", count, before)
Reset()

-- An error in the action ends the hold instead of repeating every frame.
local failing = CreateFrame("Button", "TestNavUp")
local calls = 0
ns.RepeatOnHold(failing, function()
	calls = calls + 1
	if calls > 1 then error("boom") end
end)
bindings.PADDUP = "CLICK TestNavUp:LeftButton"
padIndex[10] = "PADDUP"
local state = C_GamePad.GetDeviceMappedState
C_GamePad.GetDeviceMappedState = function()
	local result = state()
	result.buttons[11] = true
	return result
end
failing.scripts.OnClick(failing, "LeftButton", true)
Wait(1)
Check("error: one repeat tried", calls, 2)
Check("error: reported", #errors, 1)
Check("error: ticker hidden", ticker.shown, false)

if fails > 0 then
	print("repeat: " .. fails .. " FAILED")
	os.exit(1)
end
print("repeat: all checks passed")
