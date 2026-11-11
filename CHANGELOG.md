# Gamepad XIV

## v0.1.12

### New

- **Skip pets in party targeting:** an option for D-pad up / down to step through the players only, like FFXIV.
- **Skip yourself in party targeting:** an option for D-pad up / down to step through the other party members only, so fewer presses reach the one you want.

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
