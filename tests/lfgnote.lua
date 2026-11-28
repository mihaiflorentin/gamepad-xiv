-- Offline checks of the listing note (LfgFilter.lua: state.CommentValue, EditComment, ReturnComment).
-- Not loaded by the game. Run from the addon folder with: lua5.1 tests/lfgnote.lua

tinsert, tremove, wipe = table.insert, table.remove, function(t) for k in pairs(t) do t[k] = nil end return t end
date, time = os.date, os.time
function strtrim(text) return (text:gsub("^%s+", ""):gsub("%s+$", "")) end
local frameMethods = setmetatable({}, { __index = function() return function() end end })
function CreateFrame()
	return setmetatable({}, { __index = frameMethods })
end
UIParent = CreateFrame()

local listed = { comment = "LF healer, chill run" }
C_LFGList = {
	HasActiveEntryInfo = function() return listed ~= nil end,
	GetActiveEntryInfo = function() return listed end,
	CopyActiveEntryInfoToCreationFields = function() end,
}
local printed
function IsInGroup() return false end
local ns = { Print = function(text) printed = text end, Trail = function() end }
assert(loadfile("LfgFilter.lua"))("GamepadXIV", ns)
local state = assert(ns.LfgFilterState)

-- The row shows the listed note, shortened; none when there is none.
assert(state.ListedComment() == "LF healer, chill run", "the listed note")
assert(state.CommentValue():find("LF healer, chill run", 1, true), "in the row")
listed.comment = "LF healer and a tank,\nchill run, no rush"
assert(state.CommentValue():find("LF healer and a tank, ...", 1, true), "on one line, shortened in the row")
listed = nil
assert(state.CommentValue():find("None", 1, true), "no listing, no note")

-- Without the Group finder loaded there is no box to type in.
state.EditComment()
assert(printed and printed:find("Group finder"), "asks to open the Group finder once")

-- A typed note not sent yet shows in the row, marked.
local home, parent = {}, nil
local box = { text = "Need a tank", focus = true }
function box:GetText() return self.text end
function box:HasFocus() return self.focus end
function box:ClearFocus() self.focus = false end
function box:IsEnabled() return true end
local points
LFGListingComment = {
	EditBox = box,
	SetParent = function(_, p) parent = p end,
	ClearAllPoints = function() points = {} end,
	SetPoint = function(_, ...) points[#points + 1] = { ... } end,
}
assert(state.CommentValue():find("Need a tank", 1, true), "not listed: what is in the box, as List sends it")
listed = { comment = "Old note" }
assert(state.CommentValue():find("Old note", 1, true), "listed: the listed note")
state.commentEdited = true
assert(state.CommentValue():find("|cffffaa55Need a tank", 1, true), "listed and changed: the typed note, marked")

-- Giving the box back puts it where it was.
state.commentLent, state.commentHome = true, { parent = home, points = { { "BOTTOM", home, "BOTTOM", 0, 19 } } }
state.ReturnComment()
assert(parent == home and points[1][1] == "BOTTOM" and points[1][5] == 19, "back in the Group finder")
assert(not box.focus and not state.commentLent, "no longer typed in")
parent = nil
state.ReturnComment()
assert(parent == nil, "given back once")

-- The last notes: newest first, five kept, the same note (any case) only once.
ns.db = ns.db or {}
ns.db.lfgNotes = nil
assert(state.RecentNotesText():find("once you list", 1, true), "no notes yet")
for _, note in ipairs({ "one", "two", "three", "four", "five", "six" }) do
	state.RememberNote(note)
end
assert(#ns.db.lfgNotes == 5 and ns.db.lfgNotes[1] == "six" and ns.db.lfgNotes[5] == "two", "five kept, newest first")
state.RememberNote("FOUR")
assert(#ns.db.lfgNotes == 5 and ns.db.lfgNotes[1] == "FOUR" and ns.db.lfgNotes[3] == "five", "a note again moves up, once")
state.RememberNote("  ")
state.RememberNote("a\nb")
assert(ns.db.lfgNotes[1] == "a b", "one line; empty notes skipped")
assert(state.RecentNotesText():find("1.", 1, true), "listed")

print("lfgnote: all checks passed")
