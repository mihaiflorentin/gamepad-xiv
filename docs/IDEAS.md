# Possible features

Requests and ideas not built yet, with what was found about them. `docs/` is left out of the package.

## Who to reply to

When a feature ships, reply to these players where they asked (all CurseForge comments unless noted).

| Feature | Asked by |
|---|---|
| Sheathed bar | Zinured |
| Expanded controls select the top bars | BeanRad |
| Brightness of the Expanded Hold highlight and the set-change flash | FranchiFriars, werewolf_liker |
| D-pad left / right "Both" in combat | werewolf_liker |
| Top bar with 4 slots per side (also only A/B/X/Y on the expanded bars) | Manof_mayhem (issue form), Minty_F |
| Bottom bar "Only when selected" | Spiralfruit |
| Press feedback on the slots | bobajay |
| Profiles: copy settings between characters | mighar |
| Expanded Hold as its own bar, always shown | Minty_F |
| Coordinate fields for bar positions | a player (name not noted) |

## Sheathed bar (requested by Zinured, CurseForge)

Like FFXIV: with the weapon put away, the crossbar shows a different set (inventory, character window, mounts and so on); drawing the weapon brings the abilities back.

- WoW has no sheathed bar of its own, and no macro condition for it, so the secure driver can't switch on it.
- `GetSheathState()` tells addon code whether the weapon is out. Poll it (there is no sheathe event) and, out of combat, switch the bottom row's set from addon code.
- Combat draws the weapon. Switch back to the ability set in `PLAYER_REGEN_DISABLED`, while attributes can still change (Back does the same).
- Sheathing or drawing during combat can't switch the bars; the change waits for the end of combat.
- Settings: on/off and which set shows while sheathed. Close to the per-form sets (`formSet<n>`), so the same picker can be reused.
- Size: medium (setting, the sheath watcher, the switch at combat start, tests).

## Expanded controls select the top bars (requested by BeanRad, CurseForge)

FFXIV's Hotbar Settings > Custom option: L2 then R2 selects the top left bar (WXHB) and R2 then L2 the top right one, instead of a double tap. Today L2 then R2 / R2 then L2 are Expanded Hold and show their own sets on the bottom row.

- A setting: "L2 then R2 / R2 then L2 select" Expanded Hold (as now) or the top bars.
- With the top bars, the LR / RL layers would act like WL / WR (`OnTrigger` in `Snippets.lua`), and the double tap could be turned off (Top bar Off already exists).

## Brightness of the Expanded Hold highlight (requested by FranchiFriars, CurseForge)

The L2 then R2 / R2 then L2 bars are lit too brightly, so the abilities in them are hard to see.

- Today one setting, `Selected bar brightness` (`activeStrength`), sets the highlight for every bar; the combos have only their own color (`activeColorCombo`, green).
- Add a brightness slider for the combos (or for each bar kind), next to their color in the Appearance tab.
- Until then, lowering `Selected bar brightness` or picking a darker Combo color helps.
- werewolf_liker (CurseForge) means the gold flash when a set changes (R1 + a button, quick set swap, Expanded Hold): `side.flash` in `Bar.lua`, alpha up to 0.85, with no setting. Add a flash strength slider (0 turns it off).

## D-pad left / right "Both" in combat (reported by werewolf_liker, CurseForge)

"Both" alternates `/targetenemy` and `/targetfriend` on every press (`S.TargetCyclePreClick`), so in combat with no friendlies around every other press does nothing and it takes two taps to reach the next enemy.

- Option: in combat, "Both" acts as "Enemies only" (`[combat]` in the macrotext), or keeps the kind of the current target (`[harm]` / `[help]`) and alternates only without a target.

## Top bar with 4 slots per side (requested by Manof_mayhem)

FFXIV's WXHB option that swaps only 4 slots. It existed as `wxhbFourSlots` ("WXHB swaps only the face buttons") from the first release and was removed in `c4389b6` (a double tap always uses all 8 slots). Bringing it back means the old behavior plus the current layouts and themes.

## Bottom bar "Only when selected" (requested by Spiralfruit, CurseForge)

The top bars' "Only when selected" (`showTopLeft` / `showTopRight`, `fc-hide-W*`) for the bottom row too: hidden with no trigger held, holding L2 / R2 shows that side.

- A "Bottom bar" choice next to the top bar ones: Always shown / Only when selected. Default Always shown.
- The secure driver already hides the top bars this way; the bottom sides would follow the same attributes.
- With Expanded Hold or Back's window focus, decide what shows (probably the side in use only).

## Press feedback on the slots (requested by bobajay, CurseForge)

Like FFXIV: the slot flashes or shrinks for a moment when its button is pressed, so you can see the press was registered.

- The press goes through the hidden `GamepadXIVCast<n>` buttons (`SetBindingClick`), so the visible slot's `PushedTexture` never shows.
- `HookScript("OnClick")` on those buttons (the addon's own, so no taint) can play a short animation on the slot shown for that key: a quick scale down and back, or the theme's pushed art.
- Setting: on / off, maybe a style. Works in combat, since it is only visual.

## Profiles: copy settings between characters (requested by mighar, CurseForge)

Settings are saved per character (`GamepadXIVDB`), so an alt starts from the defaults.

- Smallest version: "Copy settings from" a character, in the General tab. Each character's settings would also be kept in the account-wide `GamepadXIVAccountDB` (written at logout), so any alt can copy them.
- Fuller version: named profiles shared by characters, plus an import / export string.
- Copy the settings only, not per-character state such as `savedCVars`, `errorLog`, `playLog`, ring pages or migrations. The abilities on the bars are Forever's own action slots, so they don't come along.

## Expanded Hold as its own bar, always shown (requested by Minty_F, CurseForge)

Like Forever's L2 + R2 bar: one bar of its own, visible all the time, instead of a set that replaces a bottom side while the triggers are held.

- One bar already works: set both "L2 then R2 shows" and "R2 then L2 shows" to the same side.
- New: a third bar (in the middle, above or below the crossbar), with its own position in move mode and a show setting like the top bars (Always / Only when selected).

## Coordinate fields for bar positions (suggested by a player)

Type exact X / Y positions for the bars and the interact prompt instead of only dragging them in move mode.
