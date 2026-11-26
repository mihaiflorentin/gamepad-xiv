-- Offline checks of the mode adapters (Mode.lua): which one is in use, and that each answers every
-- method. Not loaded by the game. Run from the addon folder with: lua5.1 tests/mode.lua

local gamepadUI = true
local ns = { db = { enabled = true } }
function ns.IsGamepadUI() return gamepadUI end
function ns.ControllerOn() return true end
local now = 0
function GetTime() return now end
local labelStyle = "Shapes"
C_GamePad = {
	GetActiveDeviceID = function() return 1 end,
	GetDeviceMappedState = function() return { labelStyle = labelStyle } end,
}
InputIconTextureSetUtility = {
	GetActiveInputIconButtonTextures = function(key) return { key } end,
	GetNormalActiveInputIconButtonTexture = function(key) return "game-" .. key end,
}
GamepadReticle = { IsVisible = function() return true end }
SmartNavigation = { currentButton = "forever-button" }
GamepadMode = { FrameControlsManager = { isUIFocused = true } }
assert(loadfile("Mode.lua"))("GamepadXIV", ns)

local fails = 0
local function Check(label, actual, expected)
	if actual ~= expected then
		fails = fails + 1
		print("FAIL " .. label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

-- Every adapter has every method the other has.
for _, a in pairs(ns.MODES) do
	for _, b in pairs(ns.MODES) do
		for name, value in pairs(a) do
			if type(value) == "function" and name ~= "LabelStyle" then
				Check(b.name .. " has " .. name, type(b[name]), "function")
			end
		end
	end
end

-- Gamepad UI on: Forever's.
Check("on: forever", ns.Mode().name, "forever")
Check("on: game icons", ns.Mode():IconAtlas("PAD1"), "game-PAD1")
Check("on: Forever's cursor", ns.Mode():CursorButton(), "forever-button")
Check("on: focus", ns.Mode():UIFocused(), true)
Check("on: reticle", ns.Mode():Reticle(), GamepadReticle)
Check("on: Forever's style kept", ns.Mode():CrosshairStyle("forever"), "forever")
Check("on: no extra CVars", next(ns.Mode():TempCVars()), nil)
Check("on: bags window blocked", ns.Mode():BagsWindowBlocked() ~= nil, true)

-- Gamepad UI off: standalone.
gamepadUI = false
Check("off: standalone", ns.Mode().name, "standalone")
Check("off: PlayStation art for a PlayStation controller", ns.Mode():IconAtlas("PAD1"), "gamepad-ps-buttoncrox-normal")
labelStyle = "Letters"
now = 10
Check("off: an Xbox controller keeps the game's art", ns.Mode():IconAtlas("PAD1"), "game-PAD1")
Check("off: no Forever cursor", ns.Mode():Navigator(), nil)
Check("off: no Forever bar", ns.Mode():BarButton(1), nil)
Check("off: crosshair in the middle", ns.Mode():Reticle(), nil)
Check("off: Forever's style draws the cross", ns.Mode():CrosshairStyle("forever"), "cross")
Check("off: shown while running", ns.Mode():CrosshairShown(), true)
Check("off: Forever's soft target CVars", ns.Mode():TempCVars().SoftTargetInteractRange, "20")
Check("off: bags window allowed", ns.Mode():BagsWindowBlocked(), nil)

if fails == 0 then
	print("mode: all checks passed")
else
	print("mode: " .. fails .. " failed")
	os.exit(1)
end
