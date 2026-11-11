# Gamepad XIV

An FFXIV-style controller layout for WoW Forever (client 1.60.1, Interface 16001).
It runs on top of Forever's Gamepad UI: action slots, interact, cancel, the radial menu and window navigation stay the game's own.
Its double tap timing is adapted from [CrossHotbar](https://github.com/ChainStratagem/CrossHotbar) by ChainStratagem; see [Credits and licenses](#credits-and-licenses).

**Status: early testing.** Confirmed in game: the two rows, bar selection, the interact prompt, skinning, the flyout picker, the spellbook bind, L1 zoom, auto-run, double tap, D-pad targeting and raid frame movement, death and party invite popups, loot rolls, item links in chat and L1 + R1 map pins. Not yet confirmed: moving and removing an ability, and face target. See the [in-game checklist](#in-game-checklist). Found a bug? [Report it on CurseForge](https://legacy.curseforge.com/wow/addons/gamepad-xiv/issues).

## Features

- **Two row cross hotbar:** 8 slots per side, with the current set at the bottom and the double tap bars on top, always visible.
- **Bar selection:** hold L2 / R2 for a bottom bar, double tap for a top bar, or L2 then R2 / R2 then L2 for Expanded Hold. Hold, Toggle and Mixed modes are available.
- **8 sets:** R1 + a face button or D-pad direction changes the bottom row, with a `CHANGE SET` overlay.
- **Forms and stances:** each form or stance keeps its own set on the bottom row, including in combat.
- **Selection feedback:** the selected bar grows and glows with a short animation, and the others shrink and dim.
- **Range indicator:** an ability turns red while your target is out of its range. Abilities with no range stay as they are.
- **Controller button art:** optional button icons on every slot, in the style of your controller, plus an original addon icon.
- **Targeting:** enemies and friendlies in turn on D-pad left/right, tab target on R1 + L2 and L1 + R2, in either order; a soft target for party and raid members.
- **Party selection:** double tap L1 or use the D-pad, pets included, with the name above the crossbar and a highlight on the member's frame (outline, thick outline, fill or pulse, set separately for party and raid, plus an optional arrow beside party frames).
- **Face target:** an optional, experimental setting that turns your character toward the enemy when casting.
- **Camera and movement:** L3 and R3 set in the settings, L1 + right stick zoom (from a light push, with the camera held still), L1 + left stick forward auto-run (in either order), hold B to walk, Y / B to ascend and descend, first / third person on R3.
- **Interact prompt:** A / Cross in your controller's art, with the action's icon (loot, talk, skinning, mining, herbalism) and the target's name, over your character (movable) and on nameplates.
- **Flyouts:** spells like Aspect open a controller picker, with each choice on a button and B / Circle to cancel, including in combat.
- **Menus:** map, character, spellbook and inventory on L1 + a face button, with context-sensitive X and A.
- **Chat and map:** click item links in chat, Shift-click items to link them even with chat closed, and L1 + R1 to place a map pin.
- **Editing:** drag and drop directly on the crossbar (R1 + a button shows any set on the bottom row), and a controller flow to move or remove an ability.
- **Layout:** drag each bar anywhere, or all of them together, and set the scale, opacity and the padding between button groups.
- **Minimap icon:** left click for settings, right click for a menu, drag to move it around the minimap.
- **Settings panel and slash commands**, saved per character.
- **Hand-over to Forever:** vehicles, possession and Forever's own bar editor get their normal controls back.

## Screenshots

The crossbar, with the two rows and the controller button art:

![The crossbar](docs/screenshots/crossbar.png)

Settings:

![General settings](docs/screenshots/settings-general.png)

![Crossbar settings](docs/screenshots/settings-crossbar.png)

![Layer, form and stance settings](docs/screenshots/settings-layers-forms.png)

![Input settings](docs/screenshots/settings-input.png)

## Installation

Copy the `GamepadXIV` folder to `Interface/AddOns/`. Turn on the Gamepad UI in game, then enable the addon in the AddOns list. Type `/gxiv status` to see what is active. After adding or updating files, restart the game rather than only using `/reload`.

The addon needs Forever's Gamepad UI. Without it, the layout stays off and your normal bars are unchanged.

## Crossbar

Two rows are always visible, as in FFXIV: the current set at the bottom and the two double tap bars at the top. The selected bar grows and glows, with D-pad and face button marks in the middle of its groups. The other bars shrink and dim.

| Input | Effect |
|---|---|
| Hold L2 / R2 | bottom bar, left / right |
| Double tap L2 / R2, holding the second press | top bar, left / right, while held; releasing returns to exploration mode |
| Hold L2, then R2 / hold R2, then L2 | Expanded Hold: that bottom side shows another set |
| Hold R1 + Y, B, A, X | set 1, 2, 3, 4 on the bottom row |
| Hold R1 + D-pad up, right, down, left | set 5, 6, 7, 8 on the bottom row |
| Tap R1 (with Quick set swap on) | swaps between two pairs of sets, bottom and top row together |
| R1 + L2 / L1 + R2 | tab target: next enemy, either way round |
| L2 / R2 + R3 | move or remove an ability |
| L2 / R2 + Back | move the bars |
| L2 / R2 + Start | settings menu |

**Activation modes**, under `L2 / R2 activation`:

- **Hold:** a bar stays selected while you hold the trigger. Releasing returns to exploration mode, where A, X, Y and the D-pad do their normal jobs.
- **Toggle:** a selected bar stays selected without holding the trigger, including after a double tap. The next press of the same trigger deselects it, and the other trigger replaces it.
- **Mixed:** a quick tap keeps the bar selected until the next press, and holding works like Hold. A double tap is held, as in Hold.

**Quick set swap** (`r1Tap`): `S.R1Click` resets `fc-r1Chord` on R1 down. Anything else while R1 is held marks it: a set pick (`S.SetClick`), `ApplyLayer` running in a trigger or L1 layer or with the ring, a class menu or a flyout open (so R1 + R3's ring and R1 + L3's class menu mark it), and R1 + L2, which then goes through `GamepadXIVR1ChordL2`, a button that marks it and runs `/targetenemy`. An R1 + L3 / R3 set to a plain key binding, such as sheathe, is not marked, but is usually slower than the tap window. R1 up with nothing marked, within 2 ticks of the trigger clock (`fc-ticks` / `fc-ready` on `GamepadXIVR1`, about 0.2-0.4 s), runs `S.SwapTapSets`: the bottom row goes to pair B if it shows pair A's set, else to pair A, and with `r1TapTop` the top row's two sides go to both halves of the pair's top set, saved through `OnTapSwap`. A slower release, such as holding R1 to look at the set overlay, swaps nothing. The tap does not move Forever's page, so for the spellbook bind flow pick the set with R1 + a button.

**Forms and stances** change the bottom row, and each one remembers its own set. By default a form shows the game's stance bar (set 0 in `formSet1-4`): bonus bar N is action slots 73 + (N - 1) × 12 onwards, 12 slots that fill the left side and the right side's first four (`ns.sideSlots` 17-24, `fc-stanceSides`); the right side's last four stay the player's own set. R1 + a button in a form picks one of the 8 sets for it instead. Installs from before this keep their sets 5-8. The top row does not change. This can be turned off in the settings. The form number comes from the game's bonus bar (`[bonusbar:1-4]`: cat, prowl, bear and moonkin for druids, stealth for rogues); stealth also counts as form 1 on its own, and warrior stances use their stance number, for when the game gives them no bonus bar. `/gxiv debug` prints what the game reports for the current form.

The keys are the same on every bar. By default, the top row shows set 2 and Expanded Hold shows set 3. Change them in the settings or with `/gxiv wxhb R 4 L` and `/gxiv exhb LR 5 R`.

Holding R1 shows `CHANGE SET` above the top row, with each set's number and its button's icon where that button is. Choosing set 1-3 also moves Forever's own page to the same number.

## Interact prompt

When something can be used with A / Cross, a large prompt appears over your character: the button in your controller's art, the action's icon (loot, talk, skinning, mining, herbalism, quest objects) and the name. It fades when you are out of range. On units with a nameplate, the button and icon also appear there.

Turn it off with `Show interact prompt`, and move it with the `INTERACT PROMPT` handle in move mode.

## Flyouts

Spells that open a list, such as Aspect, show a panel when you press their slot, including in combat. Each choice has its own button, in this order: A / Cross, X / Square, Y / Triangle, then D-pad up, right, down, left. B / Circle cancels, and you can release the trigger before choosing.

The list shows the highest known rank of each spell, up to 7 choices. It is prepared out of combat, so a spell learned during combat appears afterwards. Clicking the slot with the mouse opens Blizzard's own list.

## Moving or removing an ability

Out of combat, hold L2 or R2 and press R3 (FFXIV uses the touchpad here). A panel asks you to choose the ability: hold L2 or R2, or double tap for the top row, and press its button. The panel then shows the ability and offers:

- **A / Cross: Move.** Choose the new slot the same way. R1 + a button changes the set first if needed. An ability already in that slot swaps with it.
- **X / Square: Remove.** The ability leaves the bar right away.
- **B / Circle: Cancel.**

Entering combat cancels it. It is also in `/gxiv clear`.

## Moving the bars

Use `/gxiv move` or the `Move bars` button in the editor and the settings. Each bar gets a blue handle; dragging any of them, or `ALL`, moves the whole crossbar. With `Move bars separately` on (General tab), each bar moves on its own and Shift + drag moves them all. `INTERACT PROMPT` moves the prompt, and `LOOT ROLL` moves Forever's loot roll window. `Reset` or `/gxiv reset` puts everything back. Positions are saved per character. Moving only works out of combat.

The gap between the D-pad group and the face button group is set in the settings, under `Padding between button groups`.

## Editing slots

Directly on the crossbar, out of combat:

- Drag a spell, item or macro onto any visible slot, on either row, at any time. R1 + a button shows any of the 8 sets on the bottom row to fill it; the Expanded Hold bars are halves of a set (set 3 by default).
- Buttons from other addons can go on the crossbar through a macro. In Forever, `/click` needs `1` at the end to press the button, for example `/click PallyPowerAuto LeftButton 1`; with `Down` or nothing there, the button does not act.
- Drag a slot off the bar to move it, even when the bars are locked.
- In the spellbook, the `Bind to Action Bar` button still works and shows this crossbar. Press L2 or R2 + a button. Choosing set 1-3 with R1 also moves Forever's page, so the slot lands on that set. Sets 4-8 are not Forever pages: the slot lands on the page shown at the top, so drag abilities onto those sets instead. The L2+R2 bars of pages 1-3 are sets 4 left, 4 right and 5 left.


In the bind window from the spellbook, the bars do not react to your presses and the chosen slot is not highlighted, because the buttons belong to Forever's window. After a `/reload`, press R1 + the set once before binding, so that Forever's page matches. Forms and stances change the set without moving the page, and the top row is not bound directly: for the default top row, choose set 2 and bind there.

## Settings

The addon has its own settings window, with the settings on tabs in a column on the left: General, Targeting, Appearance, Crossbars, Input and Ring. Each tab is split into sections under gold titles, such as Crossbars: layout, slots, top row and Expanded Hold, quick set swap, forms and stances. A tab longer than the window scrolls, with a scrollbar beside the rows. The search box above the tabs finds settings on every tab by name or description. Open it with `/gxiv config`, L2/R2 + Start, the minimap icon, or the button under Options > AddOns > Gamepad XIV. With the controller, D-pad up / down picks a setting, left / right changes it, A toggles or presses, L1 / R1 change tab, and B or Start closes the window. With the mouse, click the arrows (Shift for bigger steps) or use the mouse wheel; the wheel over a row without a value, or over the scrollbar, scrolls the tab. `Reset to defaults`, under the tabs, restores the defaults of the open tab, or of the search results while searching. The window closes when combat starts.

| Setting | What it does | Default |
|---|---|---|
| Enable layout | turns the crossbar on or off | on |
| Show minimap icon | shows the icon around the minimap | on |
| Move bars | shows a blue handle on each bar to drag it, with Reset positions and Done; also `/gxiv move` and L2/R2 + Back | |
| Move bars separately | each bar moves on its own in Move bars; off, they all move together (Shift + drag moves them all either way) | off |
| Show loot roll item details | the roll item and what you wear in that slot, beside the loot roll window | on |
| Always compare items | WoW's `alwaysCompareItems`: item tooltips compare with what you wear, without Shift | on |
| Face target (turn toward the enemy) | see [Face target](#face-target) | off |
| Group finder message | what A on a group in Looking For Group whispers to its leader; `<level>`, `<class>`, `<name>`, `<leader>`, `<activity>` and `<roles>` (the roles ticked in Looking For Group, such as Healer/DPS; nothing with none ticked) are filled in | Hello! Invite me for \<activity\> - \<level\> \<class\> \<roles\>. |
| Ask before whispering a group | A on a group asks first | on |
| Open bags when needed (experimental) | opens the bags when a spell or scroll waits for an item to be picked, and at the mailbox, if they are still closed a moment later; closes them after the spell if it opened them | off |
| Scale | size of the whole crossbar (0.5-1.5) | 1 |
| Horizontal / Vertical position | position of the whole crossbar | 0 / 90 |
| Padding between button groups | gap between the D-pad and face button groups (0-80) | 16 |
| Controller button size | size of the button art on the slots (16-60) | 32 |
| Show interact prompt | the button, action icon and target name over your character | on |
| Inactive side opacity | how visible the other bars are while one is selected | 0.55 |
| Show controller buttons on slots | your controller's button art on each slot | off |
| Show out of range abilities in red | tints an ability red while your target is out of its range | on |
| Show the set picker | the CHANGE SET box above the crossbar while R1 is held, with the button for each set | on |
| Show set labels | each bar's set, with its trigger (below the bottom bars, above the top bars), and the `SET` label | on |
| Double tap L2 / R2 shows | which set and side each top bar shows | set 2 left / right |
| L2 then R2 / R2 then L2 shows | which set and side Expanded Hold shows | set 3 left / right |
| Forms change the bottom row | gives each form or stance its own set | on |
| Quick set swap (tap R1) | a quick tap of R1 (released within about 0.3 s) with nothing else pressed swaps between pair A and pair B, like FFXIV; works in combat | on |
| Quick set swap: include the top row | the tap also changes the top row to the pair's top set (both halves) | on |
| Pair A / B: bottom row, top row | the sets of the two pairs | A: 1 and 2 (the default layout), B: 4 and 5 |
| Form 1-4 uses | the game's stance bar or one of the 8 sets, for each form or stance | the game's stance bar |
| L2 / R2 activation | Hold, Toggle or Mixed | Hold |
| Skip pets in party targeting | D-pad up / down step through the players only, like FFXIV | off |
| Skip yourself in party targeting | D-pad up / down step through the other party members only (in a party) | off |
| D-pad left / right selection | Enemies only, Friendly only or Both: what D-pad left / right select | Friendly only |
| D-pad party selection | Off, In a raid or Always: when the whole D-pad moves over the party and raid frames | In a raid |
| Party targeting | Soft or Hard: whether party selection sets a temporary target or your real target | Hard |
| Party highlight | Outline, Thick outline, Fill, Pulse or None: how the selected party member's frame is marked | Fill |
| Party marker | Left, Right or Off: a gold arrow outside the selected party frame, pointing at it | Left |
| Raid highlight | the same choices as Party highlight, for raid frames | Thick outline |
| Theme | Classic, Forever, Round, Hex, Sigil, Holo, Ink, Orb or Minimal: how the slots look (their places stay the same). Each theme also picks the four settings below while they follow the theme | Hex |
| Background | the theme's, None, Dark circle, Soft shadow, Vignette, Glass, Highlight glow, Hexagon, Holo glass or Ink wash: what is drawn behind each group of four slots | Vignette |
| Background border | the theme's, None, Thin, Double, Glow, Highlight color, Hexagon, Runes or Holo ring: a border around each group of four slots | None |
| Slot background | the theme's, None, Dark, Smoke, Gradient, Glass, Highlight color, Deep, Frost or Scanlines: the fill inside each slot, under the ability | the theme's |
| Slot border | the theme's, None, Thin, Thick, Double, Glow or Highlight color: a border around each slot, in its shape | the theme's |
| Background opacity | how solid that background is | 0.7 |
| Selected bar highlight | Big glow, Soft glow per group, Ring per group, Glow per slot or None: how the bar you are using is lit up | Big glow |
| Bottom bar color | highlight color of the bottom bars (L2, R2) | Cyan |
| Top left bar color | highlight color of the top left bar (double tap L2) | Blue |
| Top right bar color | highlight color of the top right bar (double tap R2) | Blue |
| Combo color | highlight color while L2 then R2 or R2 then L2 is held | Green |
| Selected bar brightness | how bright that highlight is | 0.7 |
| Marks in the middle of the selected bar | the small cross and dots between its slots | on |
| Top left bar / Top right bar | Always shown, Only when selected (the double tap bars on top stay hidden until you double tap L2 or R2), or Off (hidden, and a double tap selects only the bottom bar) | Always shown |
| Highlight color | Gold, White, Green, Cyan, Blue, Purple, Pink, Red or Orange, for the highlight and the marker | Gold |
| L3 (press left stick) / R3 (press right stick) | dropdowns: Draw / sheathe weapon, First / third person, Auto-run, Walk / run, Sit / stand, Target nearest enemy, Assist target, Follow target, World map, Bags, Screenshot, the game's ping bindings (read from its key binding list: `TOGGLEPINGLISTENER` and the `PING*` commands, with the game's own names), Pet commands / forms menu, Pet spells / stances menu, your class's stance and form spells (highest rank known) or Nothing. Long lists have a search box | Draw / sheathe weapon / First / third person |
| L1 + R3 / R1 + L3 | the same choices as L3 / R3. A class menu the class does not have falls back to the stick's own action | Pet commands / forms menu / Pet spells / stances menu |
| L1 + left stick forward | the same choices as L3 / R3. Pressing L1 while already moving forward also starts auto-run, but only while this is Auto-run | Auto-run |
| L1 + right stick | Zoom (up zooms in), Zoom (up zooms out) or Turn the camera as usual | Zoom (up zooms in) |
| Double tap window | window in 0.2 s steps (2-4) | 2 |
| Hold B / Circle to walk | walks while the button is held | on |
| Force the addon's buttons | a fix for when holding L2 or R2 doesn't show the crossbar: the addon's bindings then win over every other binding (priority override bindings). Menus may stop answering the D-pad and face buttons while it is on | off |

## Gamepad XIV ring

R1 + R3 opens the addon's own ring (`Ring.lua`), drawn with the art of Forever's main menu ring. Forever's ring cannot take addon entries: an addon entry taints it, and closing it then blocks Forever's interact button, so the addon keeps to a frame of its own. The highlight follows the right stick over every segment, empty ones greyed out, and stays when the stick is let go; nothing runs until A is pressed. A uses the highlighted entry, B closes, L1 / R1 and D-pad left / right change page, D-pad up shows the emotes (Forever's eight, then every `EMOTE<n>_TOKEN` the game has, A to Z, as pages in `ring.sub`; past 12 pages the dots become "3 / 15") and D-pad down sits or stands (`SITORSTAND`). The Game Menu entry puts the game's `TOGGLEGAMEMENU` binding on A while it is highlighted (`fc-ringPickBinding`), since Forever's Game Menu button only opens under the mouse. Those keys are bound through the secure driver (`fc-ring`, `ringKey-*`, `ringBind-*`), so they work in combat. Opening the ring from R1 + R3 puts the layer back to the base, so R1 can page.

The first three pages are Forever's main menu pages with its entries in the same places. They open through a secure click on Forever's own buttons (micro menu buttons, the backpack button, the clock and calendar buttons): while the highlight moves, `Ring.lua` sets `type = "click"` and `clickbutton` on `GamepadXIVRingpick`, the button A presses, so the window opens from the hardware press and nothing is tainted. Player entries with a slash command run as a macro the same way. Those attributes can't change in combat, so `ns.RingArmCombat` sets up every segment of every main menu page on `GamepadXIVRingpick` beforehand (when the ring opens, at login and on `PLAYER_REGEN_DISABLED`): `p<page>s<segment>-type`, `-macrotext`, `-macro`, `-spell`, `-item` and `-toy`, with Forever's buttons clicked through `/click`. The open ring always binds the right stick's four direction buttons, so the driver knows which directions are held (`fc-held-*`), and it follows the page (`fc-ringPage`, from `fc-ringStartPage` and `fc-ringPages`) and whether the emotes or toy pages are showing (`fc-ringSub`). In combat `S.RingPickPre` turns the held directions into a segment (right is 1, then counterclockwise) and copies that segment's attributes onto the button, so A uses it. In combat the highlight follows the same held directions (`ns.RingHeldSegment`), and letting go of the stick uses nothing, since a diagonal comes back as two releases one after the other. Entries without a secure action (emotes, PvP, tracking, addon slash commands) are run by the addon itself; the Game Menu, Chat and the Toy Box show greyed out. Combat starting with the Game Menu highlighted takes its binding back off A. Chat puts the game's `OPENCHAT` binding on A the same way, so it opens chat to type in; Forever's own Chat entry focuses chat for the controller, which would taint Forever's focus manager from addon code. Buffs is left out for the same reason.

The settings entry starts on the third page. In the `Ring` tab every segment and page can be changed: Forever's three pages are put into `ringPages` the first time (`ringSeeded`), and `Reset the ring` puts them back. Segments are filled from a searchable list, and pages added, renamed and removed without limit. Sections list the spellbook (`ns.RingSpellChoices`, cast by name for the highest rank), the bag items (`ns.RingItemChoices`), the macros (`ns.RingMacroChoices`, saved by name), the Equipment Manager sets (`ns.RingEquipmentSetChoices`, put on with `/equipset`) and the toys, each in a window of its own over the add window; these use the secure `spell`, `item`, `macro` and `toy` actions on `GamepadXIVRingpick`. The Toy Box entry sets `fc-keep` on that button, so `S.RingPickPre` leaves the ring open out of combat and `Ring.lua` shows the toys as pages of 8 (`ring.sub`). The list has Forever's entries, the loaded addons, the player's toys (`ns.RingToyChoices`, read through the Toy Box filters, which are put back afterwards; used with the secure `toy` action) and the settings, then Advanced: a slash command typed in. `ns.RingAddOnChoices` finds each addon once, by its LibDataBroker launcher (opened with `OnClick` on a hidden anchor frame, in `pcall`), the addon compartment when the client has one, or a slash command it registered: `issecurevariable` leaves out the game's own commands and names the addon that added one. Addon entries are saved as `{ addon, launcher }`, `{ addon, compartment }` or `{ addon, command }`; one whose addon is turned off stays, greyed out. With `ringReleaseToUse` on, the open ring also binds the right stick's four direction buttons (`GamePadStickAxisButtons`) to `GamepadXIVRingreleaseUp` / `Down` / `Left` / `Right`, which act on the release. Each direction has its own button because two releases of one button at the same moment (letting go from a diagonal) reach it only once. `S.RingReleasePre` keeps which directions are held on the driver (`fc-held-*`) and uses the entry only when none is, so moving round the wheel never triggers it, and a release without its press is ignored. In that mode the highlight only moves while a stick direction is down (`IsKeyDown`), so the highlighted entry is always the one letting go uses. `/gxiv ringlog` records highlights, stick presses and uses to `ringLog`. Under the wheel the D-pad's actions show on Forever's band (`gamepad-radial-menu-bottomtext`) with the D-pad icon. They are saved per character in `ringPages`; the older `ringEntries` move into it on first use. R1 + R3 has its own setting, and any other button setting can open the ring too (`Gamepad XIV ring` in their lists). Start cannot: Forever's `OPENRADIAL` binding is in its `GamepadModeInGameCore` binding context, which takes Start (and Back) before any addon binding.

## Looking For Group

`Lfg.lua`, out of combat, while Forever's group finder (`LFGParentFrame`, from the load-on-demand `Blizzard_GroupFinder_VanillaStyle`) has the controller cursor: Triangle refreshes the list, A on a group whispers its leader, and Square opens the group's menu. A hint under the window shows the three. Forever's menu navigation keeps A and B, and the bindings it sets for a focused window (priority overrides on `UIParent`) take the other face buttons, so none of its code is called from addon code, which would taint it:

- Triangle and Square get priority override bindings on a frame of the addon's own, taken back when Forever re-binds. They click `GamepadXIVLfgRefresh` and `GamepadXIVLfgMenu`, secure `click` buttons on `LFGBrowseFrameRefreshButton` and on the entry under `SmartNavigation.currentButton` (right button), so the window's own handlers run from the hardware press. They are cleared when the cursor leaves the window, a menu or popup opens over it, and on `PLAYER_REGEN_DISABLED`.
- A stays Forever's (it selects the entry). The addon reads the controller (`C_GamePad.GetDeviceMappedState`) and, on a group (more than one member, not delisted, not your own), whispers the leader with `SendChatMessage`. With `lfgConfirm` on, a box of the addon's own asks first: A sends, Triangle (bound to `GamepadXIVLfgCancel` meanwhile) cancels, and moving the cursor or closing the window cancels too. The same leader is not whispered twice within 10 seconds.
- A group's menu (`LFGBrowseFrame:CreateSearchEntryMenu`, from Square or a right click) is moved beside the window, level with the entry, instead of where Forever's navigation anchors it.

## Moving items

`Items.lua`, out of combat: with a bank, guild bank, mail being written, opened mail, auction house or trade window open, Square on an item under the controller cursor does what a right click does there. A bag item goes to the bank, guild bank, mail, auction or trade; a bank, bank bag or guild bank item goes to the bags; a mail attachment comes back (opened mail: Square takes it, a left click). The move is named in a Square prompt beside Forever's button prompts (Select, More, Close), or under the window when it has none. Forever's bags give Square a job only when the item can be sold, equipped, used, opened or read, so most items had none there. With a vendor open, or none of these windows, Square stays Forever's (sell, equip, use). An auction house only takes an item that can be sold there; for any other, Square stays Forever's.

Square gets a priority override binding on a frame of the addon's own, taken back when Forever re-binds, on `GamepadXIVItemMove`, a secure `click` button on `SmartNavigation.currentButton`, so the item's own click handler runs from the hardware press. It is cleared when the cursor leaves an item, a menu or popup opens, an item is on the cursor, and on `PLAYER_REGEN_DISABLED`. `/gxiv lfglog` records these moves too.

The experimental **Open bags when needed** setting (`openBagsWhenNeeded`) is a fallback for Forever, which opens the bags itself at the mailbox and for spells where `SpellCanTargetItem()` is true. A player found them closed for a scroll and at the mailbox. 0.25 s after `CURRENT_SPELL_CAST_CHANGED` (also checking `SpellCanTargetItemID()`) or `MAIL_SHOW`, if the bags are still closed, it calls `OpenAllBags`, and `CloseAllBags` when the spell is over if it opened them and no bank, vendor, mail, auction or trade window is open. It logs what it sees to `/gxiv lfglog`.

## Tutorial

`Tutorial.lua`. A tutorial of the buttons, one feature a step, in chapters: Basics (jump, interact, cancel, the map), Movement (walking, auto-run), Camera (zoom, R3), Cross hotbar (the bars, filling them, the top row, Expanded Hold, sets, quick set swap, moving an ability), Targeting (the D-pad, party members, enemy targeting) and Menus and windows (the L1 windows, the ring, moving items) and All set (where the settings are). The box shows the chapter beside the step number. Each step dims the screen around what it is about, with a pulsing outline, and shows a controller (`Media/controller.tga`, a generic shaded gamepad made by `tools/make_controller_art.py`) with the game's button icons for the controller in use. Each step acts out its input as a looping scene: a tap presses a button once, a double tap twice, a hold presses it and keeps it down while another button is tapped, and a stick slides in the direction to push it. The buttons in the scene glow; the others are dimmed. Every button's part is an animation group of Scale and Translation steps padded to the same length, so they stay in step. Steps are built from the settings when shown, so they name the buttons in use, and features that are off (quick set swap, the ring, walking) are left out.

It starts by itself once per account (`GamepadXIVAccountDB.tutorialSeen`, a few seconds after login with the layout active, out of combat), and on demand from the Tutorial button above Reset to defaults, Settings > General (Tutorial), the minimap menu or `/gxiv tutorial`. A / Cross next, B / Circle back, X / Square chapters, Y / Triangle close: the driver binds them (`fc-tutorial`, `tutorial-PAD1/2/3/4`) only in the base layer and out of combat, so a step's buttons can be tried with a trigger or shoulder held. The Chapters button (or X / Square) lists every step under its chapter's name, beside the box, to jump to one: click it, or D-pad up / down and A, with B to go back (the D-pad is bound only while the list is open, `tutorial-PADDUP/PADDDOWN`). Pages whose task can be done anywhere check that the player did it (`checks` per numbered step, or `goal`): the driver's layer and move/remove stage, post-hooks on the cast buttons and `JumpOrAscendStart`, `ACTIONBAR_SLOT_CHANGED`, the current set, the camera zoom and which windows are shown. Each step done gets a tick, and Next stays locked until the page is done; the chapter list still goes anywhere. Pages that need an enemy, a friend, an NPC or a service nearby are not checked. Combat hides it and it comes back at the same step when combat ends.

## Minimap icon

Left click opens the settings, and dragging moves the icon around the minimap. Right click opens a short menu: Settings, Move bars and Tutorial; Enable layout and Face target, ticked while on; [Debug] Log this session (`/gxiv log`, ticked while on) and [Debug] Log UI (`/gxiv debug quiet`); and Hide minimap icon. Everything else is in the settings.

The menu closes on a click elsewhere and when you enter combat. The same entry also appears in the minimap's AddOn compartment. If you hide the icon, `/gxiv minimap` or `Show minimap icon` in the settings brings it back.

## Slash commands

| Command | Effect |
|---|---|
| `/gxiv status` | shows what is active and the current input CVars |
| `/gxiv on`, `/gxiv off` | turns the layout on or off, and `off` restores your input CVars |
| `/gxiv edit` | the same as `/gxiv move` |
| `/gxiv tutorial` | starts the tutorial (also `/gxiv tour`) |
| `/gxiv config` | settings |
| `/gxiv clear` | moves or removes an ability |
| `/gxiv move` | moves the bars |
| `/gxiv reset` | puts the bars back in their default place |
| `/gxiv wxhb <L\|R> <set> <L\|R>` | the side a double tap shows, for example `/gxiv wxhb R 4 L` |
| `/gxiv exhb <LR\|RL> <set> <L\|R>` | the side Expanded Hold shows, for example `/gxiv exhb LR 5 R` |
| `/gxiv tap <2-4>` | double tap window, in 0.2 s steps |
| `/gxiv scale <0.5-1.5>` | crossbar scale |
| `/gxiv priority on\|off` | Force the addon's buttons |
| `/gxiv minimap` | shows or hides the minimap icon |
| `/gxiv debug` | reports bindings, CVars and the sticks for 10 seconds; `/gxiv debug quiet` saves the same report to `debugLog` without printing it |
| `/gxiv log` | turns a quiet play log on or off, saved to `playLog`: combat, casts (spell IDs), red error messages, party selection, targets, Back, loot rolls and a stuck L1 being released. Nothing is printed; `/reload` writes it |
| `/gxiv lfglog` | records what the Looking For Group controls and the item moves see to `lfgLog` (the last 80 lines), until run again |

## Pets

Forever gives hunters and warlocks two round buttons near the bottom of the screen instead of a pet bar, and they stay visible with this addon:

- **L1 + R3** opens the pet commands, and **R1 + L3** opens the pet spells. Forever's own L1 + L2 and R1 + R2 still work too.
- The menu stays open after letting go. Tilt the right stick toward a slot and let it go back to the middle to use it. Circle closes the menu without doing anything else; any other button closes it and does its own action, as in Forever.
- Druids, paladins and warriors open their forms, auras or stances menu with the same buttons. Classes without such a menu keep the stick's own action. Either menu can also go on L3 or R3 alone, and L1 + R3 / R1 + L3 can be given other actions, in the Input tab. The label under each button shows the buttons that open it now: L3 or R3 alone first, then L1 + R3 / R1 + L3, then L1 + left stick forward, and Forever's L1 + L2 / R1 + R2 when nothing else opens it.
- The right stick only picks inside the menu: while one is open, the stick axis buttons are turned off, because Forever closes the menu on any button press.
- For these two classes, L2 + L1 and R2 + R1 no longer change target. L2 + R1 and R2 + L1 still do.

## Face target

FFXIV turns your character toward the target whenever you use an attack. WoW has no way for an addon to do exactly that, so `Face target (turn toward the enemy)` near the top of the settings is the closest option:

- It locks the camera on your enemy target.
- It makes the character turn with the camera while casting, using `GamePadTurnWithCamera`.
- The result is that your character faces the enemy when you cast.

The client asks you to confirm experimental camera features the first time. The addon remembers your answer: after **Accept** it stops the question from coming back, and **Disable** turns face target and lock-on off until you turn one of them on again. If the client asks while the UI is still loading, the question can appear once more; answer it normally.

**Limitations:** unlike in FFXIV, the camera also moves by itself while you have an enemy targeted. The option relies on an experimental CVar (`test_cameraTargetFocusEnemyEnable`), so it may do nothing on some client versions or disappear later. It is off by default.

## Other controls

| Input | Effect |
|---|---|
| Left / right stick | movement / camera |
| A | Confirm: interact or attack (Forever's button); with a temporary target, makes it the real target |
| B | Cancel; hold to walk; while swimming, descend |
| X | Map; with a target, the target menu |
| Y | Jump; while swimming, ascend |
| D-pad left / right | previous / next target (real target); see `D-pad left / right selection` and `D-pad party selection` |
| D-pad up / down | temporary target through the party, starting with yourself; see `D-pad party selection` |
| L2 or R2 + R1 / L1 | next enemy |
| L1 + R3 | hunters and warlocks: Forever's pet commands (attack, follow and so on); druids, paladins: forms or auras |
| R1 + L3 | hunters and warlocks: Forever's pet spells; warriors: stances |
| L1 + left stick forward | auto-run, whichever you press first; set under `L1 + left stick forward` |
| Double tap L1 | party selection: starts with yourself, and the next double tap moves to the next member |
| L1 + right stick up / down | zoom in / zoom out; set under `L1 + right stick` |
| L1 + R1 | draw / sheathe weapon; on a mount, dismount; while flying, descend. Set under `L1 + R1` |
| L1 + D-pad up / down | tab target: previous / next enemy |
| L1 + D-pad left / right | temporary target through the raid (alliance); in a party, through the party |
| L3 | draw / sheathe weapon; set under `L3 (press left stick)` |
| R3 | first / third person; set under `R3 (press right stick)` |
| L2 / R2 + R3 | move or remove an ability |
| Start | Forever's radial (main menu) |
| Back | cycles like FFXIV: focuses the window used last, then each open window in turn (as R2 does), then opens chat to type in; with none open, opens chat. Loot rolls, popups and combat keep Forever's own Back |
| L1 + R1 (world map open) | place or remove a map pin, like L3 |
| L1 + A / B / X / Y | character / spellbook / map / inventory (added by the addon) |

FFXIV reference: [Controls](https://ffxiv.consolegameswiki.com/wiki/Controls) and [W Cross Hotbar](https://ffxiv.consolegameswiki.com/wiki/W_Cross_Hotbar). The exact FFXIV double tap timing is not documented there.

**Party selection:** with no L2/R2 held, a double tap on L1 (or D-pad up/down) starts at the top and steps through the party and raid frames in the order they are drawn on screen, column by column, pets included. Without raid-style frames on screen, it steps through the party list, each member followed by their pet. The name appears above the crossbar, and the member's frame is highlighted in the style chosen under Party highlight and Raid highlight, with the Party marker arrow beside party frames.

**D-pad party selection:** this setting gives the whole D-pad to the party and raid frames on screen, and each direction moves to the frame that way, wrapping at the end of a row or column. The selection is a temporary target. Pressing a direction with no temporary target selects the frame you were last on. `Always` applies everywhere; `In a raid` applies only in a raid, and elsewhere the D-pad works as normal. With no compact frames on screen, it steps through the party list instead. Frames that appear during combat can only be reached after combat. Enemy tab target stays on L1 + D-pad up/down, R1 + L2 and L1 + R2.

**The temporary target (soft target)** is used for party and raid, as in FFXIV: the next ability goes to it, your real target stays unchanged, and after the ability you return to your real target. A confirms it and B cancels it.

**Party targeting:** `Hard` (the default) means party selection (D-pad and double tap L1) changes your real target instead, with no temporary target. The name above the crossbar does not appear, and the frame highlight follows your real target while it is a party or raid member or their pet, and every press moves on from the last frame or member, even if you have targeted something else since.

**Death, resurrection and party invite popups:** this includes the group finder's invite (`LFGInvitePopup`, where A accepts and B declines). Forever does not focus these by itself, so about a second after one appears, the face buttons press its buttons directly, as shown below the popup in your controller's art. For example, A / Cross releases your spirit and Y / Triangle opens the recap. The wait keeps a button press meant for the fight from answering it. Anything that shows up in combat gets this when combat ends.

**Loot rolls:** Forever does not focus the roll window by itself, so press Back with no L2/R2 held, as the prompt below the window shows, then use the buttons it shows, such as A / Cross for Need and B / Circle for Pass. This also works in combat.

L1 on its own does nothing: holding it is a layer, like the triggers. While it is held, the right stick only zooms (unless `L1 + right stick` is set to turn the camera): camera turning drops to 0.1, the lowest the client accepts, and your own speeds come back on release.

**Item links:** left-clicking an item, spell, quest or achievement link in chat opens it (player names are left to Forever); Forever does not pass link clicks to chat, so the addon reads the link from the line you clicked. Shift-click an item with chat open to add its link, even with nothing typed yet. With chat closed, the link is held for 30 seconds and goes into the box when you open chat; the addon does not open chat itself, because that leads to the "blocked from an action" message. In the bags, Y / Triangle then Share in Chat also works.

**Game settings changed by the addon:** while active, the addon sets `GamePadEmulateShift`, `GamePadEmulateCtrl` and `GamePadEmulateAlt` to `none` and `GamePadStickAxisButtons` to `1`, which saves them to `Config.wtf`. Your original values stay in the addon's data and come back with `/gxiv off`, or when Forever takes over, for example in a vehicle. If you disable the addon in the AddOns list without `/gxiv off`, the values stay changed. It also turns off the client's interact icon (`SoftTargetIconInteract`) and the input legend for the session only.

## Differences from FFXIV

- **The double tap window is approximate: normally 0.2-0.4 s, sometimes shorter in combat.** Secure code has no clock and uses a timer that certain events advance. `/gxiv tap 3` widens it.
- **Enemy cycling is WoW's tab target**, with real targets. Objects are picked up with A through soft interact.
- **`Both` takes turns between enemies and friendlies.** WoW has no tab target over both, and addons cannot tell the units around you apart in combat, so each press alternates WoW's enemy and friend tab targets. With only enemies or only friendlies around, every other press does nothing; `Enemies only` and `Friendly only` avoid that.
- **There is no Enmity list.** WoW does not give addons an aggro list, so L1 + D-pad up/down does tab target.
- **The soft target's target circle** is only the name shown above the crossbar, plus the highlight on party and raid frames.
- **Abilities are assigned by drag and drop on the crossbar**, not through an FFXIV-style menu. For sets 1-3, Forever's own editor also works (Spellbook, then Y).
- **Forms without a WoW bonus bar (Travel Form, for example) do not change the set**, and abilities on Forever's stance bar are not copied over. Vehicles and possession hand control back to Forever's bar.
- **The client's world icon for interact is off**, because it cannot show the right button. Objects and units without a nameplate use the prompt over your character.
- **The hidden Forever bar still receives mouse clicks** at the bottom of the screen, even though it is invisible.
- **Holding R1 and pressing R2 cancels set selection** until you press R1 again.
- **Face target also moves the camera**, and it and lock-on use an experimental CVar (`test_cameraTargetFocusEnemyEnable`) that may disappear.

## Where abilities are saved

| Sets | Slots |
|---|---|
| 1-3 | Forever pages 1-3, the L2 and R2 bars |
| 4 and 5 left | Forever's L2+R2 bars |
| 5 right - 8 | regular slots 13-68 (bars 2-6) |

Slots 13-68 are shared with keyboard and mouse mode: whatever you put there also appears on those bars.

## Reporting problems

Report bugs and ideas on the [CurseForge issue tracker](https://legacy.curseforge.com/wow/addons/gamepad-xiv/issues). Include what happened and what you expected, the steps to get there, the addon version, your controller and your other addons.

The addon keeps its latest 40 Lua errors, from any addon, and its own blocked actions, in `errorLog` inside `WTF/Account/<account>/<realm>/<character>/SavedVariables/GamepadXIV.lua`. Run `/reload` to write the file, then attach that part to your report.

If something does not respond, run `/gxiv debug`, follow its message for 10 seconds, and run `/reload`. The results go to `debugLog` in the same file.

If you see "Gamepad XIV has been blocked from an action", choose `Ignore`, and report it with the error log.

**Known issue:** opening the chat with the `/` key can trigger that message, from `SetPreferredGamepadInteractTarget`. One cause, the addon opening chat itself, was found and removed in 0.1.7; others may remain. Each blocked action now records, under `tainted` in the error log, which values on that path addon code has written.

## In-game checklist

1. `/gxiv status` should show `gamepad UI: true` and `active: true`. **If R2 does not change the bar**, run `/gxiv priority on`: how the addon's bindings rank against Forever's cannot be determined from the Lua source. Then make sure menus and the inventory can still be navigated.
2. No errors at login (`/console scriptErrors 1`).
3. Drag abilities directly onto both rows. Try `/gxiv move` and `/gxiv config`.
4. Hold R2 and press A: the ability from set 1 is used.
5. Double tap R2, hold, and use several abilities: the top right bar is selected, with the animation. Releasing returns to normal.
6. **Repeat 4 and 5 in combat.** This is the most important test.
7. Open and close the inventory out of combat, then repeat 4. Window navigation must work, and the bars must stay functional.
8. Press D-pad up, then use a heal: it lands on you and your real target does not change. Try D-pad left/right on enemies and friendlies, and tab target on R1 + L2 and L1 + R2.
   Enter a form or stance, including in combat: the bottom row changes, and R1 + a button changes that form's set.
9. L1 alone does nothing. Try L1 + left stick forward (auto-run), L1 + right stick (zoom), double tap L1 (party) and L1 + R1. If something does not work, run `/gxiv debug` and include its output in your report.
10. Enter combat with Move bars open: the panel closes, slots cast again, and L2 and R2 stop acting as clicks.
11. Hold R2, press L1, and release R2 before L1; then hold R1, press L2, and release R1 before L2. The bars must return to normal. If a bar stays selected, please report it: the client is sending the release to a different key.
12. If a key does nothing, run `/gxiv status` and include the error message in your report.

## Development

- `tests/sim.lua` runs the real secure snippets in a strict offline environment. Run `lua5.1 tests/sim.lua` from the addon folder. It cannot prove in-game behaviour.
- `tools/make_icon.py` draws `Icon.tga` and needs Pillow. Run it from the addon folder.
- Code that opens or closes Blizzard windows, or Blizzard's menu, can taint Forever's gamepad focus and block its protected calls. The addon's own panels avoid this on purpose.

### Releasing

`.github/workflows/release.yml` packages the addon with the [BigWigs packager](https://github.com/BigWigsMods/packager). A push to `main` only builds a test package, attached to the workflow run. Pushing a version tag publishes it:

```bash
git tag v0.1.0
git push origin v0.1.0
```

Before tagging, replace the notes in `CHANGELOG.md` with the new version's: the packager sends that whole file to CurseForge as the changelog, instead of the commit messages.

The repository needs two settings, under Settings > Secrets and variables > Actions:

- Secret `CF_API_TOKEN`: a CurseForge API token.
- Variable `CURSEFORGE_PROJECT_ID`: the project ID from the CurseForge project page.

## Credits and licenses

Gamepad XIV is released under the BSD 3-Clause License; see `LICENSE`.

Gamepad XIV's double tap timing is adapted from [CrossHotbar](https://github.com/ChainStratagem/CrossHotbar) by ChainStratagem, used under the BSD 3-Clause License. The full license is in `LICENSE-CrossHotbar.txt`. If you play the regular version of WoW, [CrossHotbar on CurseForge](https://www.curseforge.com/wow/addons/crosshotbar) is worth a look.

Gamepad XIV is a separate addon, and is not endorsed by CrossHotbar or its author.
