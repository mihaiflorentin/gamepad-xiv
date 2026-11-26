# Gamepad XIV

## Unreleased

### New

- Added a bags window for the controller, off by default (alpha).

### Fixed

- Button icons now match your controller with Forever's gamepad UI off.

## v0.1.30

### New

- Added a Report option to the chatbox player menu.
- Added Say and Yell languages to the chatbox Square menu.

### Changes

- On the chatbox Whispers tab, the D-pad left / right picks the player and up / down scrolls.

## v0.1.29

### Fixed

- Fixed answering group invites and trades with the controller in combat.

## v0.1.28

### New

- Implemented LFG Filter, a new gamepad friendly group finder.
- Implemented a new gamepad friendly chatbox.
- The quick set swap can now also change the L2 + R2 bars.
- L2 + R2 can now show the top bars.
- Circle now clears your target while swimming or flying.
- Added an option for Cross on an enemy to shoot with your wand.
- Holding the D-pad now keeps moving in menus.

### Fixed

- Fixed picking roles in a group invite with the D-pad.
- Fixed the right stick not scrolling quest, gossip, book and letter text.
- Fixed the mouse wheel changing settings instead of scrolling.

## v0.1.27

### Changes

- Linking items in chat can now be turned off in the Chat settings.

### Fixes

- Lua errors from the game or other addons no longer break the controller UI, such as when looting in dungeons.
- Pressing a trigger again right after using its bar, or after L2 + R2, no longer opens the top bar by mistake.
- Double taps are easier to hit in combat: the double tap window is a bit longer by default and can go higher.

## v0.1.26

### Changes

- Linking items in chat is now a setting, off by default, in the General settings.

### Fixes

- Lua errors from the game or other addons no longer break the controller UI, such as when looting in dungeons.
- Pressing a trigger again right after using its bar, or after L2 + R2, no longer opens the top bar by mistake.
- Double taps are easier to hit in combat: the double tap window is a bit longer by default and can go higher.

## v0.1.25

### New

- Crosshair settings with a live preview: style, color, size, thickness, opacity and outline, in the Appearance settings.
- Warriors, druids and paladins can stop the trigger + shoulder chord from opening the stance, form or aura menu, in the General settings.

## v0.1.24

### New

- The right stick can turn the camera while a window is open.

### Fixes

- Cross places spells and items that need a spot on the ground.

## v0.1.23

### New

- Can now assign buttons in the Input settings to summon mounts or run macros.

## v0.1.22

### Fixes

- Fixed "action blocked" errors after closing chat or a window.
- L1 no longer changes your target. Party selection with a double tap of L1 is now off by default, in the Targeting tab.

## v0.1.21

### New

- D-pad left / right can step through other targets in combat. In the Targeting tab.
- Choose what Cross does on an enemy target: toggle the attack, keep attacking, or nothing. In the Targeting tab.
- Button spacing settings for the button groups, and closer group padding. In the Crossbars tab.
- Hunters and warlocks can hide or disable each pet menu button under the crossbar. In the General tab.
- Put abilities, items and macros on the bars without the spellbook: L2 / R2 + R3, then an empty slot or Replace.
- Square in the spellbook closes it and puts the ability on any set of the crossbar. Can be turned off in the General tab.

### Changes

- Error reports record where an "action blocked" problem starts.

## v0.1.20

### New

- Idle opacity: the bars can fade out of combat while no trigger is held.

### Fixes

- Fixed the quick set swap in a form or stance going to set 1 instead of back to the form's set.
- Fewer "action blocked" errors when opening chat or a window.

### Changes

- Error reports keep more errors.

## v0.1.19

### Fixes

- Fixed an "action blocked" popup when a pet or stance menu closed in combat.
- Fixed an error when resetting the bar positions.

## v0.1.18

### New

- The party frames show D-pad up / down instead of L1. The prompt can be moved above the party or hidden in the Targeting tab.
- Profiles: characters can share settings or copy them from each other, and settings can be shared as text. In the new Profiles tab.
- Return to the bottom bar after using the top bar, like FFXIV. In the Input tab.

### Changes

- Errors save more details, to help with bug reports.

### Fixes

- Fixed walking sometimes not stopping after letting go of the button.

## v0.1.17

### New

- **Combo brightness:** the L2 then R2 / R2 then L2 highlight has its own brightness setting, in the Appearance tab.
- **Button press feedback:** added a visual feedback when pressing an ability. It can be turned off in the Appearance tab.
- **Set change flash:** set how bright the flash is when a bar's set changes, or turn it off with 0.

## v0.1.16

### Changes

- The play log (`/gxiv log`) also records walking and running speed.

## v0.1.15

### Fixes

- Fixed a Lua error when trading.

## v0.1.14

### Fixes

- **Characters without Gamepad XIV:** the controller settings Gamepad XIV changes are shared by the whole account, and they stayed changed on characters where the addon is turned off, which broke Forever's pet and aspect menus there. They now go back to your own at logout and are set again when you log in with the addon.

## v0.1.13

### New

- **Interact prompt layer:** draw the interact prompt above game windows (as before), at their level, under them or in the background, so it doesn't cover a vendor or quest window.

## v0.1.12

### New

- **Exclude pets from party targeting:** an option for D-pad up / down to step through the players only, like FFXIV.
- **Exclude yourself from party targeting:** an option for D-pad up / down to step through the other party members only, so fewer presses reach the one you want.

## v0.1.11

### Fixes

- **Party targeting on Hard:** D-pad up / down steps on from the player you last selected, also after the party frames change, instead of starting over at the top. After targeting an enemy or nothing, the first press goes back to that player and the next ones move on. Out of combat it also steps on from whoever you targeted another way.

## v0.1.10

### New

- **Top bars can be turned off:** set Top left bar or Top right bar to Off and a double tap of that trigger selects only its bottom bar.
- **Set picker option:** the CHANGE SET box shown while R1 is held can be turned off.

### Changes

- **Set picker:** smaller and transparent, and drawn above other windows so nothing covers it.

## v0.1.9

### New

- **Tutorial:** a guided tour of every button, with a controller that shows what to press, chapters, and checks that tick each step as you do it. It starts once; replay it from the settings, the minimap menu or `/gxiv tutorial`.
- **Ring:** your own ring menu on R1 + R3, with Forever's pages to start. Add windows, addons, toys, macros, items, abilities, emotes and equipment sets, use an entry by letting go of the stick, and use it in combat. It has a Chat entry and a Toy Box.
- **Quick set swap:** a tap of R1 swaps between two pairs of sets, like FFXIV.
- **Set labels:** each bar shows its set and trigger, and holding R1 shows the set picker with button icons. Changing sets flashes the bars.
- **Back cycles like FFXIV:** it focuses your windows one after another, then opens chat. With nothing open, it opens chat.
- **Looking For Group:** △ refreshes, ✕ whispers the leader for an invite, □ opens the group's menu. The message can name the activity, your level, class and the roles you ticked (`<roles>`).
- **Moving items:** □ moves an item between your bags and an open bank, guild bank, mail, auction house or trade window.
- **Ping:** the game's ping actions can go on the sticks and button combinations.
- **Party and raid highlight:** a None option.
- **Move bars separately:** the bars now move together; this option moves each one on its own.
- **Debug tools:** a quiet session log for bug reports, from the minimap menu or `/gxiv log`.

### Changes

- Forms and stances change both bottom bars to their own set, so a druid's cat or bear bar no longer needs the left bar rebound.
- New default layout: the top bars sit closer to the bottom bars. Bars you moved stay where they are.
- Shoulder + trigger targets the next enemy in either order.
- The settings have a Crossbars tab, sections and scrolling.
- The group finder's invite popup answers to ✕ and ○.

### Fixes

- L1 no longer gets stuck after opening a window with L1 + a face button, and the camera turns again if it ever does.
- Back with nothing open no longer says "No interface frame to focus".

## v0.1.8

### New

- **Crossbar themes:** Orb (the new default), Hex, Sigil, Holo, Ink, Round, Forever, Minimal and Classic.
- **Appearance settings:** each theme picks a background, background border, slot background and slot border, and you can change any of them on its own.
- **Selected bar highlight:** big glow, soft glow or ring around each group, glow behind each slot, or none.
- **Highlight colors:** a separate color for the bottom bars, each top bar and combos, plus brightness and the center marks.
- **Settings window:** tabs and a search box.
- **Party and raid highlight:** outline, thick outline, fill or pulse, a color of your choice, and an optional arrow beside party frames.
- **Party selection** now includes pets.
- **Top bars** can stay hidden until you select them.
- **L3 and R3** can be set to an action of your choice.
- **Loot rolls:** the roll window can be moved with Move bars, and the item and what you wear in that slot are shown beside it.
- **Always compare items:** item tooltips show your equipped item without holding Shift.

### Changes

- Sharper icons on every theme.
- Cast animations are round on round slots.
- Your character switches once to the new look. Changes you make afterwards are kept.
- L1 + R3 now does the same as R3. The virtual cursor is removed, as Forever does not support it.
- Messages in the game use /gxiv. /fc still works.

### Fixes

- The equipment manager shows your sets again in gamepad mode, with the Equip and Save buttons.
