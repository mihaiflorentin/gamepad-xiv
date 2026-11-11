-- Smoke test for Tutorial.lua with stubbed frames. From the addon folder: lua tests/tutorial.lua
local function Frame(name)
	local f = { shown = false, scripts = {}, name = name }
	local mt = { __index = function() return function() end end }
	f.Show = function(self) self.shown = true end
	f.Hide = function(self) self.shown = false end
	f.SetShown = function(self, v) self.shown = v and true or false end
	f.IsShown = function(self) return self.shown end
	f.IsVisible = function(self) return self.shown end
	f.SetScript = function(self, n, fn) self.scripts[n] = fn end
	f.HookScript = function(self, n, fn)
		local old = self.scripts[n]
		self.scripts[n] = function(...) if old then old(...) end fn(...) end
	end
	f.GetHeight = function() return 100 end
	f.GetWidth = function() return 1000 end
	f.GetStringHeight = function() return 40 end
	f.GetEffectiveScale = function() return 1 end
	f.GetFrameLevel = function() return 1 end
	f.SetText = function(self, t) self.text = t end
	f.CreateTexture = function() return Frame() end
	f.CreateFontString = function() return Frame() end
	f.CreateAnimationGroup = function()
		local g = Frame()
		g.orders = {}
		g.CreateAnimation = function()
			local a = Frame()
			a.SetDuration = function(_, d) a.d = d end
			a.SetOrder = function(_, o) g.orders[o] = math.max(g.orders[o] or 0, a.d or 0) end
			return a
		end
		g.Play = function()
			local total = 0
			for _, d in pairs(g.orders) do total = total + d end
			table.insert(PLAYED, total)
		end
		return g
	end
	return setmetatable(f, mt)
end
FRAMES, PLAYED = {}, {}
CreateFrame = function(_, name) local f = Frame(name); if name then _G[name] = f end; table.insert(FRAMES, f); return f end
UIParent = Frame("UIParent")
local combat = false
InCombatLockdown = function() return combat end
local timers = {}
C_Timer = { After = function(_, fn) table.insert(timers, fn) end }
tinsert = table.insert
unpack = unpack or table.unpack
tContains = function(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
local printed, keys, lastFree = {}, {}, nil
local ns = {
	db = { triggerMode = "hold", sideWL = 3, sideLR = 5, showTopLeft = "always", showTopRight = "always", r1Tap = true, r1TapTop = true,
		r1TapBottomA = 1, r1TapTopA = 2, r1TapBottomB = 4, r1TapTopB = 5, dpadTarget = "friend", dpadParty = "raid",
		l1RightStick = "zoom", l1StickUpAction = "autorun", r3Action = "view", holdToWalk = true, showInteractPrompt = true,
		r1R3Action = "ring", l3Action = "sheathe", l1R3Action = "classLeft", r1L3Action = "classRight", l1R1Action = "sheatheSmart" },
	ButtonText = function(t) return t end,
	KEYS = { "PADDLEFT", "PADDUP", "PADDRIGHT", "PADDDOWN", "PAD3", "PAD4", "PAD2", "PAD1" },
	SET_BY_KEY = { 8, 5, 6, 7, 4, 1, 2, 3 },
	DescribeSide = function(side) return math.ceil(side / 2), "L" end,
	IsActive = function() return true end,
	RingFindBuiltin = function(name) if name == "guild" then return 1, 2, 4 end end,
	SetTutorialKeys = function(on, chapters, free) table.insert(keys, on); lastFree = free end,
	Print = function(...) table.insert(printed, table.concat({ ... }, " ")) end,
	STICK_ACTIONS = { { "view", "First / third person" }, { "autorun", "Auto-run" }, { "ring", "Gamepad XIV ring" }, { "bags", "Bags" } },
	L1_RIGHT_STICK = { { "zoom", "Zoom (up zooms in)" } },
	NUM_SETS = 8,
	sideSlots = (function() local t = {} for side = 1, 16 do t[side] = {} for i = 1, 8 do t[side][i] = side * 8 + i end end return t end)(),
	root = { sides = { L = Frame(), R = Frame(), WL = Frame(), WR = Frame() } },
}
for _, side in ipairs({ "L", "R", "WL", "WR" }) do
	for i = 1, 8 do CreateFrame("Button", "GamepadXIVCast" .. side .. i) end
end
CLOCK = 100
GetTime = function() return CLOCK end
DRIVER_ATTR = { ["fc-layer"] = "BASE", ["fc-clear"] = 0 }
GamepadXIVDriver = { GetAttribute = function(_, k) return DRIVER_ATTR[k] end, SetAttribute = function(_, k, v) DRIVER_ATTR[k] = v end }
DRIVER_ATTR["fc-form"], DRIVER_ATTR["fc-formset-0"] = 0, 1
ACTIONS = {}
HasAction = function(slot) return ACTIONS[slot] == true end
SecureHandlerExecute = function() end
JumpOrAscendStart = function() end
hooksecurefunc = function(name, fn)
	local old = _G[name]
	_G[name] = function(...) local r = old(...); fn(...); return r end
end
assert(loadfile(arg[1] or "Tutorial.lua"))("GamepadXIV", ns)

local fails = 0
local function check(name, cond) if cond then print("ok", name) else fails = fails + 1; print("FAIL", name) end end
local events
for _, f in ipairs(FRAMES) do if f.scripts.OnEvent then events = f end end
local function Count() return (GamepadXIVTutorial.count.text:match("(%d+ / %d+)$")) end
local function Total() return tonumber(Count():match("/ (%d+)")) end
local function Title() return GamepadXIVTutorial.title.text end
local function Next() GamepadXIVTutorialNext.scripts.OnClick() end
local function Ticks() return select(2, (GamepadXIVTutorial.how.text or ""):gsub("ReadyCheck", "")) end
local function Tick() CLOCK = CLOCK + 1; GamepadXIVTutorial.scripts.OnUpdate(GamepadXIVTutorial, 0.2) end
-- Jumps through the chapter list, which works on locked pages too.
local function GoToIndex(index)
	GamepadXIVTutorialChapters.scripts.OnClick()
	GamepadXIVTutorialChapterList.pick = index
	Next()
end
local function GoToTitle(title)
	for index = 1, Total() do
		GoToIndex(index)
		if Title() == title then return true end
	end
end
local function Shown(name) _G[name] = { shown = true, IsShown = function(self) return self.shown end }; return _G[name] end

-- First login: starts after the delay and marks the account.
events.scripts.OnEvent(events, "PLAYER_ENTERING_WORLD")
check("auto start queued", #timers == 1)
timers[1]()
check("shown", ns.IsTutorialShown())
check("seen account-wide", GamepadXIVAccountDB.tutorialSeen == true)
check("24 pages with everything on", Count() == "1 / 24")
check("counter names the chapter", GamepadXIVTutorial.count.text:match("^Basics") ~= nil)
Next()
check("next from the welcome page", Count():match("^2 /") ~= nil)
GamepadXIVTutorialBack.scripts.OnClick()
check("back", Count():match("^1 /") ~= nil)

-- Combat pauses, the end of combat resumes at the same page.
GoToIndex(3)
events.scripts.OnEvent(events, "PLAYER_REGEN_DISABLED")
check("combat hides", not ns.IsTutorialShown())
events.scripts.OnEvent(events, "PLAYER_REGEN_ENABLED")
check("resumed at page 3", ns.IsTutorialShown() and Count():match("^3 /") ~= nil)
GamepadXIVTutorialClose.scripts.OnClick()
timers = {}
events.scripts.OnEvent(events, "PLAYER_ENTERING_WORLD")
check("not again on next login", #timers == 0)

-- Settings shape the pages; the last one needs the settings opened and closed.
ns.db.r1Tap, ns.db.r1R3Action = false, "none"
ns.StartTutorial()
check("quick swap and ring left out", Count() == "1 / 22")
GoToIndex(Total())
check("last page", Title() == "You're all set")
Next()
check("last page locked", ns.IsTutorialShown())
local config = Shown("GamepadXIVConfigFrame")
Tick(); config.shown = false; Tick()
Next()
check("finish closes", not ns.IsTutorialShown())
check("finish message", printed[#printed]:find("Tutorial finished") ~= nil)
ns.db.r1Tap, ns.db.r1R3Action = true, "ring"
combat = true
ns.StartTutorial()
check("no start in combat", not ns.IsTutorialShown())
combat = false

-- Every part of a scene, badges included, loops at the same length.
ns.StartTutorial()
local worst = 0
for page = 1, Total() do
	GamepadXIVTutorialChapters.scripts.OnClick()
	GamepadXIVTutorialChapterList.pick = page
	PLAYED = {}
	Next()
	for i = 2, #PLAYED do worst = math.max(worst, math.abs(PLAYED[i] - PLAYED[1])) end
end
check("parts of a scene line up", worst < 0.001)
GamepadXIVTutorialClose.scripts.OnClick()

-- The cross hotbar: intro, filling, then using an ability, which is checked and needs L2 held.
ns.StartTutorial()
check("intro page", GoToTitle("The cross hotbar"))
Next()
check("then Filling your bars", Title() == "Filling your bars")
GoToIndex(tonumber(Count():match("^(%d+)")) + 1)
check("then Using an ability", Title() == "Using an ability")
check("steps numbered", (GamepadXIVTutorial.how.text or ""):find("1.|r  Press and hold {PADLTRIGGER}", 1, true) ~= nil)
GamepadXIVTutorialChapters.scripts.OnClick()
PLAYED = {}
GamepadXIVTutorialBack.scripts.OnClick()
check("step 1 scene: L2 and its badge", #PLAYED == 2)
Next()
check("locked", Title() == "Using an ability")
PLAYED = {}
DRIVER_ATTR["fc-layer"] = "L"; Tick()
check("step 1 ticked", Ticks() == 1)
check("step 2 scene: L2 held, the cross, two badges", #PLAYED == 4)
DRIVER_ATTR["fc-layer"] = "BASE"; Tick()
check("letting go of L2 unticks step 1", Ticks() == 0)
DRIVER_ATTR["fc-layer"] = "L"; Tick()
CLOCK = CLOCK + 1
GamepadXIVCastL8.scripts.OnClick()
Tick()
DRIVER_ATTR["fc-layer"] = "BASE"
Next()
check("unlocked after casting", Title() ~= "Using an ability")
GamepadXIVTutorialClose.scripts.OnClick()

-- Jump frees Y; its hint drops "close" and "next" until the jump.
ns.StartTutorial()
check("Jump page", GoToTitle("Jump"))
check("Jump frees Y", lastFree and tContains(lastFree, "PAD4"))
check("Jump hint has no close", not GamepadXIVTutorial.keys.text:find("close"))
check("Jump locked: no next hint", not GamepadXIVTutorial.keys.text:find("next"))
CLOCK = CLOCK + 1
JumpOrAscendStart()
Tick()
check("jump ticks", Ticks() == 1)
Next()
check("Jump unlocked", Title() ~= "Jump")
GamepadXIVTutorialClose.scripts.OnClick()

-- Quick set swap: two changes of set, from wherever it started.
ns.currentSet = 2
ns.StartTutorial()
GoToTitle("Quick set swap")
ns.currentSet = 1; Tick()
ns.currentSet = 4; Tick()
check("quick swap ticks both", Ticks() == 2)
GamepadXIVTutorialClose.scripts.OnClick()

-- R3 on bags sits in Basics.
ns.db.r3Action = "bags"
ns.StartTutorial()
check("bags page in Basics", GoToTitle("Bags") and GamepadXIVTutorial.count.text:match("^Basics") ~= nil)
GamepadXIVTutorialClose.scripts.OnClick()
ns.db.r3Action = "view"

-- Party members: a party beside the box; D-pad down then up.
ns.StartTutorial()
GoToTitle("Party members")
check("party shown", GamepadXIVTutorialParty.shown)
GamepadXIVTutorialDown.scripts.OnClick(); Tick()
check("down selects you first", GamepadXIVTutorialParty.pick == 1)
GamepadXIVTutorialUp.scripts.OnClick(); Tick(); Tick()
Next()
check("party unlocked", Title() ~= "Party members" and not GamepadXIVTutorialParty.shown)
GamepadXIVTutorialClose.scripts.OnClick()

-- The ring: turn to Communities' page, point at it, open it, close it.
ns.StartTutorial()
GoToTitle("The ring")
local ring = Shown("GamepadXIVRing"); ring.shown = false
local communities = Shown("CommunitiesFrame"); communities.shown = false
local sel = { 2, 0 }
ns.RingSelection = function() if ring.shown then return sel[1], sel[2] end end
check("ring asks for Communities", (GamepadXIVTutorial.how.text or ""):find("Point the right stick up and left, at Communities", 1, true) ~= nil)
DRIVER_ATTR["fc-layer"] = "SET"; Tick()
ring.shown = true; DRIVER_ATTR["fc-layer"] = "BASE"; Tick(); Tick(); Tick()
check("ring open, R1 let go", Ticks() == 3)
sel = { 1, 0 }; Tick()
check("page turn ticks", Ticks() == 4)
ring.shown = false; Tick(); Tick(); Tick()
check("closing the ring early undoes its steps", Ticks() == 0)
DRIVER_ATTR["fc-layer"] = "SET"; Tick()
ring.shown = true; DRIVER_ATTR["fc-layer"] = "BASE"; Tick(); Tick(); Tick(); Tick()
check("reopened and turned again", Ticks() == 4)
sel = { 1, 4 }; Tick()
check("pointing at Communities ticks", Ticks() == 5)
ring.shown = false; communities.shown = true; Tick(); Tick()
check("ticks kept after R1 is let go", Ticks() == 6)
communities.shown = false; Tick()
Next()
check("closing Communities unlocks", Title() ~= "The ring")
GamepadXIVTutorialClose.scripts.OnClick()

-- The chapter list: opens on the current page, the D-pad moves, A opens, B closes the list.
ns.StartTutorial()
GoToIndex(3)
GamepadXIVTutorialChapters.scripts.OnClick()
check("list open", GamepadXIVTutorialChapterList.shown)
check("pick starts at the current page", GamepadXIVTutorialChapterList.pick == 3)
for _ = 1, 4 do GamepadXIVTutorialDown.scripts.OnClick() end
GamepadXIVTutorialUp.scripts.OnClick()
Next()
check("A opens page 6", Count():match("^6 /") ~= nil and not GamepadXIVTutorialChapterList.shown)
GamepadXIVTutorialChapters.scripts.OnClick()
for _ = 1, 40 do GamepadXIVTutorialDown.scripts.OnClick() end
check("pick stops at the last", GamepadXIVTutorialChapterList.pick == Total())
local headers = 0
for _, row in ipairs(GamepadXIVTutorialChapterList.rows) do
	if row.shown and not rawget(row, "step") then headers = headers + 1 end
end
check("seven chapter headers", headers == 7)
GamepadXIVTutorialBack.scripts.OnClick()
check("B closes the list", not GamepadXIVTutorialChapterList.shown and Count():match("^6 /") ~= nil)
GamepadXIVTutorialClose.scripts.OnClick()

-- A window opening moves the box aside; closing it brings it back.
ns.StartTutorial()
ring.shown = true
GamepadXIVTutorial.scripts.OnUpdate(GamepadXIVTutorial, 0.2)
check("ring open: aside", GamepadXIVTutorial.aside == true)
ring.shown = false
GamepadXIVTutorial.scripts.OnUpdate(GamepadXIVTutorial, 0.2)
check("ring closed: back", GamepadXIVTutorial.aside == false)
GamepadXIVTutorialClose.scripts.OnClick()

-- Move or remove: opens on a set with abilities, or starts by putting one on the bars.
ns.StartTutorial()
GoToTitle("Move or remove an ability")
local function Lines() return select(2, (GamepadXIVTutorial.how.text or ""):gsub("\n", "")) + 1 end
check("no abilities: 9 steps", Lines() == 9 and GamepadXIVTutorial.how.text:match("spellbook") ~= nil)
ACTIONS[3 * 16 + 2] = true -- set 3, left side
GoToTitle("Using an ability"); GoToTitle("Move or remove an ability")
check("switches to the set with abilities", DRIVER_ATTR["fc-formset-0"] == 3)
check("with abilities: 5 steps", Lines() == 5)
GoToTitle("Targeting")
check("leaving the page brings back the player's set", DRIVER_ATTR["fc-formset-0"] == 1)
GoToTitle("Move or remove an ability")
check("back on the page: switched again", DRIVER_ATTR["fc-formset-0"] == 3)
GamepadXIVTutorialClose.scripts.OnClick()
check("closing brings back the player's set", DRIVER_ATTR["fc-formset-0"] == 1)
ns.StartTutorial()
combat = false
GamepadXIVTutorialClose.scripts.OnClick()
print(fails == 0 and "ALL PASSED" or fails .. " FAILED")
