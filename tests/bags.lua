-- Offline checks of the bags window (Bags.lua) with the navigation core (Nav.lua): when it stands
-- aside, the layout, following the game's open / close / toggle, and what the keys press.
-- Not loaded by the game. Run from the addon folder with: lua5.1 tests/bags.lua

-- Frames: every method is a no-op unless defined here.
local frames = {}
local function Frame(kind, name, parent, template)
	local frame = { kind = kind, name = name, parent = parent, template = template, scripts = {}, shown = true, points = {} }
	setmetatable(frame, { __index = function(_, key) if type(key) == "string" and key:match("^%u") then return function() end end end })
	function frame:SetScript(script, fn) self.scripts[script] = fn end
	function frame:GetScript(script) return self.scripts[script] end
	function frame:Show()
		if not self.shown then self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
	end
	function frame:Hide()
		if self.shown then self.shown = false; if self.scripts.OnHide then self.scripts.OnHide(self) end end
	end
	function frame:IsShown() return self.shown end
	function frame:IsVisible() return self.shown end
	function frame:GetName() return self.name end
	function frame:SetParent(p) self.parent = p end
	function frame:GetParent() return self.parent end
	function frame:SetID(id) self.id = id end
	function frame:GetID() return self.id end
	function frame:GetFrameLevel() return 1 end
	function frame:SetPoint(point, rel, relPoint, x, y)
		if type(rel) == "table" and x then self.x, self.y = x, y end
	end
	function frame:GetRect()
		if not self.x then return nil end
		return self.x, self.y, 37, 37
	end
	function frame:CreateTexture() return Frame("Texture") end
	function frame:CreateFontString()
		local text = Frame("FontString")
		function text:SetText(t) self.text = t end
		return text
	end
	if name then _G[name] = frame end
	table.insert(frames, frame)
	return frame
end
function CreateFrame(kind, name, parent, template) return Frame(kind, name, parent, template) end
UIParent = Frame("Frame", "UIParent")
GameTooltip = Frame("GameTooltip", "GameTooltip")
function GameTooltip:GetOwner() return self.owner end
function GameTooltip:SetOwner(owner) self.owner = owner end
function GameTooltip:SetBagItem(bag, slot) self.item = bag .. ":" .. slot end

local combat = false
function InCombatLockdown() return combat end
local bindings = {}
function SetOverrideBindingClick(_, _, key, button, mouse) bindings[key] = "CLICK " .. button .. ":" .. (mouse or "LeftButton") end
function SetOverrideBinding(_, _, key, action) bindings[key] = action end
function ClearOverrideBindings() bindings = {} end
function GetBindingAction(key) return bindings[key] or "" end
function geterrorhandler() return function(err) print("error: " .. tostring(err)) end end
local timers = {}
C_Timer = { After = function(_, fn) table.insert(timers, fn) end }
local function RunTimers() local run = timers; timers = {}; for _, fn in ipairs(run) do fn() end end

-- Bags: backpack 16 slots, bag 1 with 4, bag 2 empty slot count 0. Items in a few slots.
local sizes = { [0] = 16, [1] = 4, [2] = 0, [3] = 0, [4] = 0 }
local items = { ["0:1"] = { iconFileID = 1, stackCount = 1 }, ["1:2"] = { iconFileID = 2, stackCount = 5 } }
NUM_BAG_SLOTS = 4
C_Container = {
	GetContainerNumSlots = function(bag) return sizes[bag] or 0 end,
	GetContainerItemInfo = function(bag, slot) return items[bag .. ":" .. slot] end,
	GetContainerItemQuestInfo = function() return {} end,
	SortBags = function() _G.sorted = true end,
}
local hooks = {}
function hooksecurefunc(name, fn) hooks[name] = hooks[name] or {}; table.insert(hooks[name], fn) end
local function GameCalls(name) for _, fn in ipairs(hooks[name] or {}) do fn() end end
local anyOpen = false
for _, name in ipairs({ "ToggleAllBags", "ToggleBackpack", "ToggleBag", "OpenAllBags", "OpenBackpack", "OpenBag", "CloseAllBags", "CloseBackpack" }) do _G[name] = function() end end
function IsAnyBagOpen() return anyOpen end
ContainerFrameCombinedBags = Frame("Frame", "ContainerFrameCombinedBags")
ContainerFrame1 = Frame("Frame", "ContainerFrame1")
ContainerFrame2 = Frame("Frame", "ContainerFrame2")
local loaded = {}
C_AddOns = { IsAddOnLoaded = function(name) return loaded[name] or false end }
local gamepadUI = false
InputUtil = { IsGamepadUIEnabled = function() return gamepadUI end }

local ns = { db = {} }
local printed = {}
function ns.Print(text) table.insert(printed, text) end
function ns.ButtonText(text) return text end
function ns.IsGamepadUI() return gamepadUI end
function ns.ControllerOn() return true end
function GetTime() return 0 end
assert(loadfile("Mode.lua"))("GamepadXIV", ns)
assert(loadfile("Repeat.lua"))("GamepadXIV", ns)
assert(loadfile("Nav.lua"))("GamepadXIV", ns)
assert(loadfile("Bags.lua"))("GamepadXIV", ns)

local fails = 0
local function Check(label, actual, expected)
	if actual ~= expected then
		fails = fails + 1
		print("FAIL " .. label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

local function Login()
	for _, frame in ipairs(frames) do
		if frame.scripts.OnEvent then frame.scripts.OnEvent(frame, "PLAYER_LOGIN") end
	end
end

-- Off by default: nothing changes.
Check("off: stands aside", ns.BagsStandAside(), "it is off in the settings")
Login()
Check("off: game bags untouched", ContainerFrameCombinedBags:GetParent(), nil)

-- It needs Forever's gamepad UI off, and BagPad off.
ns.db.bagWindow = true
gamepadUI = true
Check("gamepad UI on: stands aside", ns.BagsStandAside():find("needs Forever's gamepad UI off") ~= nil, true)
ns.ApplyBagWindow()
Check("gamepad UI on: says why", printed[#printed]:find("^The bags window is not in use: it needs") ~= nil, true)
gamepadUI = false
loaded.BagPad = true
Check("BagPad loaded: stands aside", ns.BagsStandAside(), "BagPad is loaded; turn BagPad off to use it")
loaded.BagPad = nil
Check("gamepad UI off, no BagPad: in use", ns.BagsStandAside(), nil)

-- Turned on: the game's bag windows go under a hidden frame.
ns.ApplyBagWindow()
Check("on: message", printed[#printed], "The bags window is on. Your bags open in it now.")
Check("combined bags hidden", ContainerFrameCombinedBags:GetParent() ~= nil and ContainerFrameCombinedBags:GetParent() ~= UIParent, true)
Check("bag 2 window hidden", ContainerFrame2:GetParent() == ContainerFrameCombinedBags:GetParent(), true)

-- The game opens its bags: ours shows, laid out and focused.
local window = GamepadXIVBags
Check("window made, closed", window.shown, false)
anyOpen = true
GameCalls("OpenAllBags")
RunTimers()
Check("open: shown", window.shown, true)
Check("5 equipped bag buttons and 20 slots", #ns.Bags.order, 25)
Check("free count", window.free.text, "18 / 20 free")
Check("the row starts with the backpack button", ns.Bags.order[1]:GetName(), "GamepadXIVBagsEquip0")
Check("first slot is the backpack's", ns.Bags.order[6]:GetName(), "GamepadXIVBagsB0S1")
Check("cursor starts on the items", ns.Bags.cursor, 6)
Check("slot parent carries the bag ID", ns.Bags.order[22]:GetParent():GetID(), 1)
Check("slot template", ns.Bags.order[6].template, "ContainerFrameItemButtonTemplate")
Check("focused", ns.NavFocused(), "Bags")
Check("Cross right-clicks the slot", bindings.PAD1, "CLICK GamepadXIVBagsB0S1:RightButton")
Check("Square left-clicks the slot", bindings.PAD3, "CLICK GamepadXIVBagsB0S1:LeftButton")
Check("tooltip on the item", GameTooltip.item, "0:1")

-- The D-pad moves the cursor and the click keys follow.
GamepadXIVNavPADDRIGHT.scripts.OnClick(GamepadXIVNavPADDRIGHT, "LeftButton", true)
Check("right: slot 2", ns.Bags.cursor, 7)
Check("Cross follows", bindings.PAD1, "CLICK GamepadXIVBagsB0S2:RightButton")
GamepadXIVNavPADDDOWN.scripts.OnClick(GamepadXIVNavPADDDOWN, "LeftButton", true)
Check("down: next row", ns.Bags.cursor, 17)
GamepadXIVNavPADRSHOULDER.scripts.OnClick(GamepadXIVNavPADRSHOULDER, "LeftButton", true)
Check("R1: first slot of bag 1", ns.Bags.Current():GetName(), "GamepadXIVBagsB1S1")
GamepadXIVNavPADRSHOULDER.scripts.OnClick(GamepadXIVNavPADRSHOULDER, "LeftButton", true)
Check("R1 wraps to the backpack", ns.Bags.cursor, 6)
GamepadXIVNavPAD4.scripts.OnClick(GamepadXIVNavPAD4, "LeftButton", true)
Check("Triangle sorts", _G.sorted, true)

-- Quick filters with L2 / R2: the filter name shows, and they wrap.
GamepadXIVNavPADRTRIGGER.scripts.OnClick(GamepadXIVNavPADRTRIGGER, "LeftButton", true)
Check("R2: next filter", ns.Bags.FILTERS[ns.Bags.filter].name, "Consumables")
Check("filter shown", window.filter.text:find("Consumables") ~= nil, true)
GamepadXIVNavPADLTRIGGER.scripts.OnClick(GamepadXIVNavPADLTRIGGER, "LeftButton", true)
GamepadXIVNavPADLTRIGGER.scripts.OnClick(GamepadXIVNavPADLTRIGGER, "LeftButton", true)
Check("L2 wraps to the last filter", ns.Bags.FILTERS[ns.Bags.filter].name, "Junk")
Check("junk filter: a common item doesn't match", ns.Bags.Matches({ quality = 1 }), false)
Check("junk filter: a grey item matches", ns.Bags.Matches({ quality = 0 }), true)
Check("search hides a match", ns.Bags.Matches({ quality = 0, isFiltered = true }), false)
ns.Bags.filter = 1
Check("all: empty slot matches", ns.Bags.Matches(nil), true)

-- The equipped bags row: Cross on a bag button is the nav key (no slot to click), and jumps to its slots.
ns.Bags.cursor = 2
ns.NavRebindClicks()
Check("on a bag button Cross is the nav key", bindings.PAD1, "CLICK GamepadXIVNavPAD1:LeftButton")
GamepadXIVNavPAD1.scripts.OnClick(GamepadXIVNavPAD1, "LeftButton", true)
Check("Cross on bag 1: to its first slot", ns.Bags.Current():GetName(), "GamepadXIVBagsB1S1")
Check("and Cross clicks slots again", bindings.PAD1, "CLICK GamepadXIVBagsB1S1:RightButton")
ns.Bags.cursor = 6

-- Back is the addon's while the window is open. Back on the last (only) window lets go: the focus
-- ends, the window stays open and Back goes back to the addon's usual Back; Back again later, after
-- the window list changed, is the addon's again.
ns.Nav.UpdateBack()
Check("Back bound", bindings.PADBACK, "CLICK GamepadXIVNavBack:LeftButton")
GamepadXIVNavBack.scripts.OnClick(GamepadXIVNavBack, "LeftButton", true)
Check("Back on the only window: focus ends", ns.NavFocused(), nil)
Check("window stays open", window.shown, true)
Check("Back given back", bindings.PADBACK, nil)
ns.Nav.UpdateBack()
Check("still given back", bindings.PADBACK, nil)
ns.NavFocus("Bags")
ns.Nav.UpdateBack()
Check("focus again: Back is ours again", bindings.PADBACK, "CLICK GamepadXIVNavBack:LeftButton")

-- The chat box holding the keys: the bags don't take the focus, and Back stays the chat box's.
ns.NavFocus(nil)
ns.ChatBoxHoldsKeys = function() return true end
Check("busy: no focus on open", ns.NavOpened("Bags"), false)
ns.Nav.UpdateBack()
Check("busy: Back left alone", bindings.PADBACK, nil)
ns.ChatBoxHoldsKeys = nil
ns.NavFocus("Bags")

-- A toggle that closes and opens inside it (as the game's does) flips the window once.
GameCalls("CloseBackpack")
GameCalls("ToggleAllBags")
RunTimers()
Check("toggle closes", window.shown, false)
Check("closing ends the focus", ns.NavFocused(), nil)
GameCalls("OpenBackpack")
GameCalls("ToggleAllBags")
RunTimers()
Check("toggle opens", window.shown, true)

-- A close that closed nothing (another window opened the bags) keeps it open.
anyOpen = true
GameCalls("CloseAllBags")
RunTimers()
Check("close with bags still open: stays", window.shown, true)
anyOpen = false
GameCalls("CloseAllBags")
RunTimers()
Check("close: hides", window.shown, false)

-- Circle closes it.
GameCalls("OpenAllBags")
RunTimers()
GamepadXIVNavPAD2.scripts.OnClick(GamepadXIVNavPAD2, "LeftButton", true)
Check("Circle closes", window.shown, false)

-- A new bag: more slots next time.
sizes[2] = 6
GameCalls("OpenAllBags")
RunTimers()
Check("new bag laid out", #ns.Bags.order, 31)

-- In combat no new slots are made; the hide of the game's windows waits.
ns.Bags.Close()
sizes[3] = 4
combat = true
GameCalls("OpenAllBags")
RunTimers()
Check("combat: no new slots", #ns.Bags.order, 31)
combat = false

-- Turned off: says a reload gives the game's bags back.
ns.db.bagWindow = false
ns.ApplyBagWindow()
Check("off: message", printed[#printed], "The bags window is off. /reload to get the game's bags back.")
Check("off: closed", window.shown, false)

if fails == 0 then
	print("bags: all checks passed")
else
	print("bags: " .. fails .. " failed")
	os.exit(1)
end
