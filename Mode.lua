local _, ns = ...

-- The two ways the addon runs, as adapters with the same methods (docs/UI-REPLACEMENT-PLAN.md):
--
-- * Forever: Forever's gamepad UI is on. Its cursor (SmartNavigation) drives the game's windows, its
--   focus manager (FrameControlsManager) decides which window has the controller, its gamepad bar
--   has the interact button, its reticle sits in the middle of the screen and the game's icon set
--   follows the controller.
-- * Standalone: Forever's gamepad UI is off. None of that exists; the addon brings its own: the
--   navigation core (Nav.lua) and its windows, the game's interact binding, a crosshair in the
--   middle of the screen, Forever's temporary CVars set by the addon, and the controller's own icons.
--
-- Features ask ns.Mode() and call its methods instead of checking the gamepad UI themselves, so
-- everything works in both. ns.Mode() follows the game's interface style, which only changes with a
-- reload.

local Forever = { name = "forever", nativeNav = true }
local Standalone = { name = "standalone", nativeNav = false }
ns.MODES = { forever = Forever, standalone = Standalone }

function ns.Mode()
	return ns.IsGamepadUI() and Forever or Standalone
end

---------------------------------------------------------------------------------------------------
-- Button icons

local function GameAtlas(key)
	local utility = InputIconTextureSetUtility
	if utility and utility.GetActiveInputIconButtonTextures and utility.GetActiveInputIconButtonTextures(key) then
		return utility.GetNormalActiveInputIconButtonTexture(key)
	end
	return nil
end

function Forever:IconAtlas(key)
	return GameAtlas(key)
end

-- Without the gamepad UI the game's icon set is always "Generic" (the Xbox art), whatever controller
-- is plugged in (InputDeviceIconSetManager.lua). The controller still says which art it wants (its
-- mapped state's labelStyle): a PlayStation controller gets the PlayStation art.
local PS_ATLAS = {
	PAD1 = "gamepad-ps-buttoncrox-normal", PAD2 = "gamepad-ps-buttoncircle-normal",
	PAD3 = "gamepad-ps-buttonsquare-normal", PAD4 = "gamepad-ps-buttontriangle-normal",
	PADDUP = "gamepad-ps-dpadup-normal", PADDDOWN = "gamepad-ps-dpaddown-normal",
	PADDLEFT = "gamepad-ps-dpadleft-normal", PADDRIGHT = "gamepad-ps-dpadright-normal",
	PADLSHOULDER = "gamepad-ps-triggerl1-normal", PADRSHOULDER = "gamepad-ps-triggerr1-normal",
	PADLTRIGGER = "gamepad-ps-triggerl2-normal", PADRTRIGGER = "gamepad-ps-triggerr2-normal",
	PADLSTICK = "gamepad-ps-stickl3-normal", PADRSTICK = "gamepad-ps-stickr3-normal",
	PADBACK = "gamepad-ps-touchpad-normal", PADFORWARD = "gamepad-ps-menu-normal",
	PADLSTICKUP = "gamepad-ps-stickl-normal", PADLSTICKAXIS = "gamepad-ps-stickl-normal",
	PADRSTICKAXIS = "gamepad-ps-stickr-normal",
}
ns.PS_BUTTON_ATLAS = PS_ATLAS

-- The controller's own label style, read at most every 2 s.
function Standalone:LabelStyle()
	local now = GetTime()
	if self.labelStyleAt and now - self.labelStyleAt < 2 then
		return self.labelStyle
	end
	self.labelStyleAt = now
	local ok, state = pcall(C_GamePad.GetDeviceMappedState, C_GamePad.GetActiveDeviceID())
	self.labelStyle = ok and type(state) == "table" and state.labelStyle or nil
	return self.labelStyle
end

function Standalone:IconAtlas(key)
	if self:LabelStyle() == "Shapes" and PS_ATLAS[key] then
		return PS_ATLAS[key]
	end
	return GameAtlas(key)
end

---------------------------------------------------------------------------------------------------
-- Forever's gamepad bar, cursor and focus manager

-- Forever's gamepad bar button `index` of its top right group (button 1 is its interact button).
function Forever:BarButton(index)
	local main = GamepadMainActionBarFrame
	local topBar = main and main.PageUnit and main.PageUnit.actionBars and main.PageUnit.actionBars.topBar
	return topBar and topBar.Right and topBar.Right["ActionButton" .. index] or nil
end

function Standalone:BarButton()
	return nil
end

-- Forever's window cursor and focus manager. Standalone has neither: features that only help them
-- (reading the button under Forever's cursor and so on) do nothing there.
function Forever:Navigator()
	return SmartNavigation
end

function Standalone:Navigator()
	return nil
end

function Forever:FocusManager()
	return GamepadMode and GamepadMode.FrameControlsManager or nil
end

function Standalone:FocusManager()
	return nil
end

-- The button under the window cursor: Forever's, or the addon's own window's.
function Forever:CursorButton()
	return SmartNavigation and SmartNavigation.currentButton or nil
end

function Standalone:CursorButton()
	local window = ns.Nav and ns.Nav.focused
	return window and window.Current and window.Current() or nil
end

-- Whether a window has the controller (Forever's focus, or one of the addon's windows).
function Forever:UIFocused()
	local manager = self:FocusManager()
	return manager ~= nil and manager.isUIFocused == true
end

function Standalone:UIFocused()
	return ns.NavFocused and ns.NavFocused() ~= nil or false
end

---------------------------------------------------------------------------------------------------
-- The crosshair

function Forever:Reticle()
	return GamepadReticle
end

function Standalone:Reticle()
	return nil -- the middle of the screen
end

-- The crosshair shows with Forever's reticle; standalone, while the addon runs.
function Forever:CrosshairShown()
	local reticle = GamepadReticle
	return reticle ~= nil and reticle:IsVisible() and true or false
end

function Standalone:CrosshairShown()
	return ns.db ~= nil and ns.db.enabled and ns.ControllerOn() and true or false
end

-- "Forever's" crosshair style is Forever's own reticle; without it the addon draws its cross.
function Forever:CrosshairStyle(style)
	return style
end

function Standalone:CrosshairStyle(style)
	return style == "forever" and "cross" or style
end

---------------------------------------------------------------------------------------------------
-- CVars

-- The temporary CVars Forever's gamepad mode sets (Blizzard_Gamepad Core.lua,
-- SetupCVarsForInputMode), set by the addon when that mode is off so soft targeting, interact and the
-- camera behave the same. SoftTargetIconInteract is left to the addon's own value (Input.lua).
local FOREVER_TEMP_CVARS = {
	SoftTargetEnemy = "1", SoftTargetFriend = "0", SoftTargetIconEnemy = "0", SoftTargetIconFriend = "0",
	SoftTargetWithLocked = "1", SoftTargetMatchLocked = "1",
	SoftTargetNameplateEnemy = "0", SoftTargetNameplateInteract = "0", SoftTargetTooltipEnemy = "0",
	SoftTargetTooltipFriend = "0", SoftTargetInteract = "1", SoftTargetInteractRange = "20",
	SoftTargetIconGameObject = "1", SoftTargetEnemyArc = "1", SoftTargetFriendArc = "2", SoftTargetInteractArc = "1",
	SoftTargetForce = "0", SoftTargetNameplateSize = "20", TargetAutoEnemy = "1", TargetAutoFriend = "1",
	TargetEnemyAttacker = "1", TargetAutoLock = "1",
	CameraFollowYawSpeed = "1.0", CameraFollowPitchSpeed = "0.5", CameraFollowPitchStrength = "1.0",
	CameraFollowPitchDeadZone = "0.0", CameraReduceUnexpectedMovement = "0", CameraKeepCharacterCentered = "1",
}

-- Extra temporary CVars the addon sets in this mode.
function Forever:TempCVars()
	return {}
end

function Standalone:TempCVars()
	return FOREVER_TEMP_CVARS
end

---------------------------------------------------------------------------------------------------
-- The addon's own windows

-- Why the bags window can't take over in this mode, or nil. With the gamepad UI on, Forever's focus
-- manager takes the game's bag window as focused whenever a bag opens ("ContainerFrame.OpenBag"),
-- even out of sight, and would fight the window for the controller.
function Forever:BagsWindowBlocked()
	return "it needs Forever's gamepad UI off (Options > Gameplay > Gamepad > Enable Gamepad UI, then /reload)"
end

function Standalone:BagsWindowBlocked()
	return nil
end
