# Replacing the Blizzard UI with our own: feasibility and plan

Researched on 2026-11-26. Client: WoW Forever 1.60.1, build 71139 (`## Interface: 16001`). `docs/` is left out of the package.

The goal is to replace every Blizzard window with a Gamepad XIV window that a controller navigates the way FFXIV does, and to let players turn off Forever's gamepad mode, which causes many of our bugs.

## Verdict

It can be done, but it is the biggest job this addon has taken on. Expect months of work, done one window at a time.

- **Display is easy.** Every window can be drawn by us: bags, bank, vendor, trainer, gossip, quest dialog, quest log, character, map, minimap, buffs, debuffs and trade. ElvUI already replaces bags, buffs and the minimap on Forever, and skins everything else.
- **Actions are the hard part.** Some actions stay blocked for addon code in combat (see "What addon code can and cannot do"). Those must go through Blizzard's own secure templates or a secure button the player presses.
  - Using an item in combat must go through a secure item button.
  - Cancelling a buff in combat must go through `SecureAuraHeaderTemplate`.
- **The best base is likely the mouse-and-keyboard interface style with the controller still working**, which means `InputDeviceInterfaceStyle = 0`. This is not proven on Forever yet. Phase 0 tests it in game before anything else is built.
  - In that style Forever's SmartNavigation cursor, footers, reticle, temporary soft-target CVars and gamepad binding context are all off (read in the source).
  - What is not known: whether the controller's `PAD*` buttons still reach our bindings with style 0. Retail ConsolePort relies on that (on retail the switch is the `GamePadEnable` CVar; ConsolePort sets it to 0 when it uninstalls). ConsolePort on Forever checks the interface style and changes its behavior, but its code doesn't show that it runs with style 0. `GamePadEnable` appears nowhere in Forever's UI source, our code or the player's Config.wtf.
  - If Phase 0 fails, the plan still works with gamepad mode on. Our windows then replace Blizzard's while Forever's mode stays on, and the "gamepad mode off" option is dropped.
- **Do it in phases.** Phase 0 tests the mode in game. Phase 1 writes the navigation core and a generic cursor that works on any window we haven't replaced. Then replace one window at a time, highest use first: bags, vendor, gossip and quest, quest log, character. Every window keeps a fallback to Blizzard's window until ours is proven.

## What we are aiming for: FFXIV's controller UI

Full research notes are under "Research data: FFXIV". The parts to copy:

- **One cursor, snapping between elements.** The D-pad (or left stick) moves between buttons. Cross confirms, Circle cancels or goes back a level, and Square opens the context menu (FFXIV calls it the sub-command). Triangle is a context extra, such as switching the inventory in a retainer trade.
- **Tabs on the shoulders.** R1 / L1 change tabs or pages inside a window. L2 / R2 do window-specific extras (in item tooltips, L2 shows the HQ version and R2 hides the tooltip).
- **The HUD cycle button**, the Select or Touch Pad (NUM1 on keyboard), moves focus between everything on screen.
  - The order: open menus first, then the Scenario Guide (quest tracker), Chat, Duty List, Map (if open), Minimap, and Status Effects (buffs, then debuffs).
  - The main menu, hotbars, job gauges and the party and enemy lists are left out. Those lists have their own buttons: D-pad up / down for the party, L1 + D-pad for the enemy and alliance lists.
  - Cancel leaves HUD focus but keeps the window open. You can leave a window up and come back to it later with the cycle.
  - Player complaints to fix in ours: the order is fixed, it goes one way only (going too far means a full lap), and reaching buffs in combat takes 3 or 4 presses. Players asked for a configurable order, maybe a different one with the weapon drawn.
- **Inventory flows built for a pad.** With a retainer or saddlebag open, Triangle switches between it and your inventory, and Cross moves the item across at once with no menu. Turning in quest items, Square filters the list to items that fit.
- **Map.** The right stick moves a map cursor and L1 + right stick zooms. The D-pad picks a region or zone, Triangle steps zone / region / world, R1 changes the floor and R3 recentres.
- **Buffs.** Your buffs are reached through the HUD cycle, the D-pad steps between them and Cross removes one.
- **Chat.** You reach it through the HUD cycle, and Cross starts typing. We already built this (ChatBox.lua).

## The Back button: every window, with priorities

The user asked that Back reach every window on screen, ordered by priority, and that the trade window be included. FFXIV's cycle order is the base, with its complaints fixed.

### How Back works today

`Snippets.lua:236-251` and `Input.lua:866-872` set it up.

- Back is Forever's own Back, which focuses a window.
- While a window is focused, Back is pointed at Forever's R2 button (`InputFunctionBindingButton_PADRTRIGGER`), which goes to the next window.
- Once every open window was visited, Back opens chat (the ChatBox or the game's Open Chat binding).
- Forever's focus manager is only read, never driven.

So the order is Forever's, not ours.

### What each mode allows

- **Gamepad mode on.** We can't put Blizzard's windows in our own order. Changing focus groups is limited to secure callers (`EnterFocusGroup` in SmartNavigation.lua), so the cycle over Blizzard windows stays Forever's. We can still order our own windows, and put Forever's cycle in one slot of ours: for example our windows first, then Forever's windows, then chat. Full priorities only become possible once a window is ours.
- **Gamepad mode off (the target, decided 2026-11-26).** Forever's Back, its R2 step and SmartNavigation are all gone, so Back follows only our rules. Every window not replaced yet needs the generic cursor (Phase 1). In this mode the full priority order works for every window.

### Design

- **A registry of focus targets.** Each entry has a name, a frame getter, a default priority, an "is it open" test and an "enter focus" function.
  - Our replacement windows register themselves.
  - Blizzard or other addon windows we haven't replaced can register through a small adapter, which gives us a free fallback.
- **A tap of Back steps forward and a hold of Back (or L1 + Back) steps back.** That fixes FFXIV's one-way problem.
- **Priority groups.** The cycle visits open windows in priority order, then the always-on HUD parts.
  1. **Modal popups:** confirm dialogs, roll picker, ready check, group invite, trade request. These take focus by themselves when they open.
  2. **Transaction windows:** trade, vendor, bank, mail, auction, trainer, gossip and quest dialog.
  3. **Player windows:** bags, character, spellbook, quest log, map, LFG, settings.
  4. **HUD:** quest tracker (Questie), chat, minimap, buffs, debuffs, loot.
- **Players can reorder.** A settings page lists every target with its priority. The player can move entries up and down, or turn an entry off so the cycle skips it.
  - An optional second order applies in combat (FFXIV players asked for this). By default it puts buffs and debuffs first.
- **Circle while focused** leaves focus and keeps the window open, like FFXIV. Circle with no focus closes the top window. Pressing Circle twice on one window closes it (setting).
- **Paired windows.** Some windows work as a pair: bags with the vendor, bank, trade or mail. Inside a pair, Triangle switches sides, like FFXIV's retainer flow, and Cross on an item moves it to the other side.
- **The trade window** goes in the transaction group. When a trade opens it takes focus, and bags open beside it as its pair.
  - Cross on a bag item puts it in the trade.
  - Accept can call `AcceptTrade()`. v0.1.29 already does that from the controller, also in combat (`Input.lua:523`).
- **Done when** every open window is reachable with Back, the order follows the settings, and the cycle wraps both ways (`ns.StepWrap`, per AGENTS.md).

## Forever's gamepad mode: what it is

From the Forever UI source (Gethe/wow-ui-source, `forever` branch, commit d9c22e3).

- The mode is the CVar `InputDeviceInterfaceStyle`. `0` is mouse and keyboard (`Enum.InputDeviceInterfaceType.Mkb`) and `1` is Gamepad.
  - The settings checkbox is "Enable Gamepad UI" (`Blizzard_SettingsDefinitions_Shared/Gamepad.lua`, `GAMEPAD_INTERFACE_TOGGLE`).
  - The player's `WTF/Config.wtf` has `InputDeviceInterfaceStyle "1"`.
- A change fires `INPUT_DEVICE_INTERFACE_TRANSITION`, which runs Init / Uninit callbacks (`Blizzard_SharedXML/InputUtil.lua`). In practice Forever needs a UI reload to switch cleanly: their own BlizzCon kiosk addon ("ColdSwap") reloads because the gamepad code is "tightly coupled" to the mode.
- Turning gamepad mode on (`Blizzard_Gamepad/Core.lua`):
  - sets 29 **temporary** CVars with `C_CVar.SetTempCVar`, and removes them again (`RemoveTempCVar`) when the mode is off. The full list:
    - soft targeting:
      - `SoftTargetEnemy 1`, `SoftTargetFriend 0`, `SoftTargetIconEnemy 0`, `SoftTargetIconFriend 0`;
      - `SoftTargetWithLocked 1`, `SoftTargetMatchLocked 1`, `SoftTargetIconInteract 1`;
      - `SoftTargetNameplateEnemy 0`, `SoftTargetNameplateInteract 0`, `SoftTargetTooltipEnemy 0`, `SoftTargetTooltipFriend 0`;
      - `SoftTargetInteract 1`, `SoftTargetInteractRange 20`, `SoftTargetIconGameObject 1`;
      - `SoftTargetEnemyArc 1`, `SoftTargetFriendArc 2`, `SoftTargetInteractArc 1`, `SoftTargetForce 0`, `SoftTargetNameplateSize 20`;
      - `TargetAutoEnemy 1`, `TargetAutoFriend 1`, `TargetEnemyAttacker 1`, `TargetAutoLock 1`;
    - camera: `CameraFollowYawSpeed 1.0`, `CameraFollowPitchSpeed 0.5`, `CameraFollowPitchStrength 1.0`, `CameraFollowPitchDeadZone 0.0`, `CameraReduceUnexpectedMovement 0`, `CameraKeepCharacterCentered 1`;
  - activates the binding context `Enum.BindingContext.GamepadModeInGameCore` (the static gamepad bindings);
  - turns on SmartNavigation (`Blizzard_GamepadSmartNavigation`, about 3000 lines), the soft cursor, the reticle, the radials, the persistent input legend, the gamepad action bars (`Blizzard_GamepadActionBars`, about 6500 lines) and gamepad targeting.
- Turning it off also forces the Edit Mode layout back to the "Modern" preset (`C_EditMode.SetActiveLayout`). Blizzard lists this as a known issue. Players should be warned before switching.
- **SmartNavigation** is Blizzard's window cursor.
  - It scans the open panel's buttons and moves by direction, or by a grid.
  - It has hooks for addons (`Blizzard_GamepadSmartNavigation/Utility.lua`): `SmartNavigation_MarkFrameIgnored`, `MarkFrameFocusable`, `AddJumpNavigationOverride`, `SetDirectionBufferThreshold`, `MarkFrameBlockingSmartNavClick` and others.
  - Changing focus groups is limited to secure callers (`EnterFocusGroup`). Its functions call `EnsureIsSecure()` and warn that insecure callers "may spread taint across half the game". This is why touching it from our code causes "action blocked" errors.
- `UIModeUtil` / `C_Roleset.ApplyRolesetFilters` hides whole groups of HUD parts: "unitFrames", "actionBars", "minimap", "buffs", "objectives", "statusBars" and others.
  - The function is blocked for tainted callers in combat. Out of combat it is a clean way to hide Blizzard HUD groups without touching the frames.
- Windows with Forever-only versions (folders named `Camelot`, the project's internal name, `WOW_PROJECT_CAMELOT`) include: WorldMap, UIPanels_Game (Character, PaperDoll, Merchant and others), UnitFrame, Minimap, MicroMenu, MainMenuBarBagButtons, ObjectiveTracker, PlayerSpells, Professions, StableUI, FriendsFrame, Communities, AuctionHouseUI, Collections, ActionBar and GamepadActionBars.

## Turning off Forever's gamepad mode

### Why

Most of our bug fixes come from Forever's gamepad layer.

- "Action blocked" errors after windows open and close (v0.1.20, v0.1.22).
- The equipment manager anchored wrong in gamepad mode (v0.1.8, `Input.lua:817`).
- The shared controller CVars breaking Forever's pet and aspect menus (v0.1.14).
- Errors when looting in dungeons (v0.1.26).
- The map always focusing the quest log (QuestieForeverGamepad's research).
- Static gamepad bindings that players can't rebind (dev notes, Oct 1).

### How

- **A setting: "Forever's gamepad mode"**, Off or On, with On as the default (new options default off, but this one keeps today's behavior until the replacement is complete).
  - Switching it writes `InputDeviceInterfaceStyle` and asks for a reload through our own popup (never `StaticPopup_Show`).
  - This only ships if Phase 0 shows the controller still works with style 0.
- **What we must supply when it is off** (each item needs a check in game):
  1. **Soft targeting and interact.** Set the same CVars Forever set (`SoftTargetInteract`, `SoftTargetEnemy`, the arcs and ranges) as our own values, restored at logout like v0.1.14's fix.
  2. **Camera follow CVars.** The same treatment. Our right-stick camera code already exists.
  3. **The gamepad binding context.** Without `GamepadModeInGameCore`, the static bindings are gone. Our override bindings already cover the bars and the buttons. ConsolePort activates the context itself when it needs native targeting (`ConsolePort/Controller/NativeGamepad.lua`). We can do the same if we keep native targeting, but that makes the mode partly on again, so test both.
  4. **The reticle.** We have Crosshair.lua.
  5. **Window navigation.** This plan's navigation core replaces SmartNavigation.
  6. **The gamepad action bars.** We have our own crossbar on normal action slots, and `Core.lua:228` warns if one overlaps Forever's gamepad storage. Forms and stances read Forever's stance storage (`C_GamepadUI.GetFirstGamepadActionBarStorageSlotIndexForActiveStance`, `Input.lua:1629`). Phase 0 must check that this still returns slots with the mode off, or the form sets need another source. ConsolePort_Bar reads the same storage (`ConsolePort/Controller/GamepadActions.lua`).
  7. **The virtual keyboard.** Forever still needs a keyboard for chat, and our ChatBox has quick messages. A pad keyboard (like ConsolePort_Keyboard) is a later phase.
- **Code that reads `SmartNavigation` today** must keep working in both modes, or switch to our core: MenuWrap.lua, Items.lua, Lfg.lua, Input.lua:1520, Spellbook.lua.

## Trade-offs of gamepad mode off

Turning the mode off doesn't free us from the addon rules: taint, protected functions and combat lockdown work the same in both modes. What it removes is Forever's gamepad layer, which caused most of our "action blocked" bugs and decides Back's order. The cost is that everything that layer did for free becomes our job.

### What we gain

- **Back follows our order**, with priorities for every window. With the mode on, only secure code may change Forever's focus groups (`EnterFocusGroup`), so Blizzard windows keep Forever's order.
- **Fewer taint bugs.** SmartNavigation rescans windows on open and close (even from inside `CreateFrame`), and touching it from addon code taints it. That caused our "action blocked" errors (v0.1.20, v0.1.22). BagPad's notes say the same.
- **Bindings players can change.** Forever's gamepad bindings are fixed (dev notes, Oct 1), and we no longer fight Forever setting its own Back and R2 after ours (`Snippets.lua:236`).
- **No forced behavior:**
  - the map no longer starts on the quest log (QuestieForeverGamepad's research);
  - the equipment set list anchoring bug goes away (`Input.lua:817`);
  - the shared controller CVars stop breaking the pet and aspect menus (v0.1.14).
- **Our windows behave the same across Forever patches**, instead of depending on a beta UI that changes every week.

### What we lose or must build

- **Controller control of every window we haven't replaced.** This is the biggest cost.
  - Forever's cursor drives all Blizzard windows today: loot, popups, the game menu, social, guild, talents, Blizzard settings, the stable and other addons' windows.
  - With the mode off they all need our generic cursor before the option ships.
- **Addons built for gamepad mode lose controller control.**
  - BagPad: its bags use Forever's cursor, and its catcher only takes gamepad buttons with the gamepad UI on.
  - QuestieForeverGamepad: 25 of its files use `IsGamepadUIEnabled`, SmartNavigation or FrameControlsManager.
  - ForeverGamepadUI_Flightmaster: `TaxiAPI.lua:127` checks the mode.
  - Players who run them must choose between those addons and the mode off.
- **Blizzard's ongoing gamepad work.** Recent builds added gamepad support to trade, guild, chat channels and transmog. With the mode off we get none of that, and every new window is ours to support.
- **Forever's gamepad extras:**
  - class flyouts and radial menus (we have the ring and our class menus);
  - the persistent input legend and the screen footers;
  - its target modifiers (`GamepadMode.RegisterTargetModifierStateChanged`) and raid frame stepping (we have our own targeting);
  - the item pickup cursor (`GamepadItemPickupCursor`);
  - the reticle (we have Crosshair.lua);
  - its gamepad action bars (we have the crossbar).
- **Switching costs.** Every switch needs a reload, and resets the active Edit Mode layout to the default preset (Blizzard known issue, and `C_EditMode.SetActiveLayout` in `Blizzard_Gamepad/Core.lua`).
- **Not proven yet:** that the controller fully works with style 0, that ground spells place with Cross, and that form and stance sets still find their slots (`C_GamepadUI` stance storage). Phase 0 tests these.

### What stays the same either way

- NPC and object interaction (soft targeting and `INTERACTTARGET`).
- Item use and buff cancelling in combat still need Blizzard's secure templates.
- A keyboard is still needed to type in chat (ChatBox quick messages help).
- Our crossbar, targeting, ChatBox, LFG Filter, ring, roll picker and settings work in both modes.

### Decision so far

- Gamepad mode off is the target, because Back then follows our rules.
- It ships as an opt-in on the alpha. The default stays on until our windows and the generic cursor cover the common windows.
- While the mode is on, our windows stand aside for BagPad and QuestieForeverGamepad where they overlap.

## What addon code can and cannot do

The rules this addon follows still apply: no taint, `hooksecurefunc` and `HookScript` only on Blizzard code, and no `ShowUIPanel`, `OpenChat` or StaticPopup calls. Forever uses Midnight's API rules: secret values, and restrictions on tainted callers in combat.

From the Forever API docs (`Blizzard_APIDocumentationGenerated`):

| Function | Marked | What it means for us |
|---|---|---|
| `C_Container.UseContainerItem` | SecretArguments AllowedWhenUntainted | Fine out of combat for selling and moving. Item use that casts a spell must be a secure click: build bag slots from Blizzard's item button templates, as ElvUI does, or a `SecureActionButtonTemplate` with `type=item`. |
| `C_Container.PickupContainerItem`, `SplitContainerItem` | AllowedWhenUntainted | Moving items works from our buttons out of combat. |
| `C_Container.SortBags` | none | Free to call. |
| `C_Container.ShowContainerSellCursor` | AllowedWhenUntainted | Fine. |
| `C_GossipInfo.SelectOption`, `SelectAvailableQuest`, `SelectActiveQuest` | AllowedWhenUntainted | Gossip is free to replace. |
| `C_Item.EquipItemByName` | AllowedWhenUntainted | Equipping from our character window works out of combat. |
| `C_QuestLog.AddQuestWatch` / `RemoveQuestWatch` / `AbandonQuest` | none or AllowedWhenUntainted | Quest log is free to replace. |
| `C_SuperTrack.SetSuperTrackedQuestID` | AllowedWhenUntainted | Fine. |
| `C_Spell.CancelSpellByID` | HasRestrictions | Likely blocked in combat for us. Cancelling auras should go through `SecureAuraHeaderTemplate` (ElvUI `Auras/Auras.lua:704`) and its secure cancel buttons. |
| `C_SecureTransfer.AcceptTrade`, `SendMail` | HasRestrictions | These belong to Blizzard's secure transfer confirm UI, which may not be the normal trade and mail path. The plain global `AcceptTrade()` works from our code in v0.1.29, in combat too (`Input.lua:523`). |
| `C_TradeInfo.AddTradeMoney` | HasRestrictions | Test before relying on it. Blizzard's own gold field is the fallback. |
| `C_Roleset.ApplyRolesetFilters` | HasRestrictions, blocked for tainted callers in combat (its own doc text) | Hide Blizzard HUD groups out of combat only. |

How to read these marks: the docs never say what `HasRestrictions` blocks. The one doc text that does (`ApplyRolesetFilters`) says "blocked for tainted callers while in combat lockdown". No function showed `RequiresHardwareEvent`. The script took the first docs file that named each function, so a row may come from another system with the same function name. Treat every row as a lead to test, not a rule.

The older globals that aren't in the docs, such as `BuyMerchantItem`, `BuyTrainerService`, `AcceptQuest`, `CompleteQuest`, `GetQuestReward`, `TakeInboxItem` and `PickupInventoryItem`, are unrestricted on Classic clients. Each one needs a check in game on Forever before we rely on it.

Rules that always hold:

- In combat, insecure code cannot show, hide, move or resize protected frames, or change their attributes. Our windows must be built out of combat, with a secure state driver for anything that must show or hide in combat.
- Override bindings (`SetOverrideBindingClick`) are the clean way to give the D-pad to a window, which is what ChatBox.lua does. ConsolePort keeps one owner that holds every override binding claim with levels (BASE, OVERRIDE, NAV, MODAL), so two frames never fight over a key (`ConsolePort/CLAUDE.md`). We need the same as the window count grows.

## Reference addons

### ConsolePort (seblindfors/ConsolePort, commit ed3a6b3, 23 Nov 2026)

The closest model, and it supports Forever already.

- **Detects Forever** with `CPAPI.IsCamelotVersion = WOW_PROJECT_ID == WOW_PROJECT_CAMELOT`, and native gamepad UI with `CPAPI.IsNativeNavigationActive()`, which is `InputUtil.IsGamepadUIEnabled()` (`ConsolePort/Utils/Const.lua`).
- **Changes behavior on the mode.**
  - Its interface cursor shows only on demand when the native UI is on, and skips a frame SmartNavigation is already driving (`ConsolePort_Cursor/Controller/Stack.lua`, `isNativelyNavigated`).
  - Its game menu, custom loot frame and aura menus turn off when native navigation is on.
- **Interface cursor.** `ConsolePort_Cursor` is load on demand, with Cursor.lua, Stack.lua, Scroll.lua, Nudge.lua, Hooks.lua and Mods.lua.
  - The stack keeps a registry of named frames and tracks when each becomes visible.
  - It uses `IsAnchoringRestricted`, and rejects anonymous frames whose names hold a pointer.
  - The cursor picks the next node by screen position. That is why bag addons need adapters: ConsolePort's cursor "skips items" in ArkInventory unless an adapter fixes the order.
- **Secure navigation** (`ConsolePort/Controller/Securenav.lua`) runs in a restricted environment. It scans protected children with `IsProtected()` and `nodeignore` / `nodepass` attributes, so it can navigate protected frames in combat.
- **Binding layers.** One controller holds every override binding claim with a level (see above).

### ElvUI (tukui-org/ElvUI)

The model for replacing windows.

- **Has a Forever build** (`ElvUI/Game/load_forever.xml`). It loads the Shared modules (ActionBars, Auras, Bags, Chat, DataBars, Maps, Nameplates, Tooltip, UnitFrames) plus skins for almost every Blizzard window.
- **Two methods.**
  - It **replaces** bags, auras, the minimap layout, unit frames, action bars and chat.
  - It **skins** (restyles Blizzard's own frame) everything else: Merchant, Trainer, Quest, Gossip, Character, WorldMap, Trade, Mail, Auction House and others.
  - Skinning keeps Blizzard's secure logic, which is why ElvUI rarely breaks.
- **Bags** (`Modules/Bags/Bags.lua`).
  - `B:DisableBlizzard()` turns off `BankFrame`, `ContainerFrame1..N` and `ContainerFrameCombinedBags`.
  - It builds its own slots from Blizzard's templates (`ItemButton` with `ItemAnimTemplate` / `BagSlotButtonTemplate` and the bank item templates), so item use stays secure.
  - It hooks the open / close / toggle bag functions to show its frame instead.
- **Auras.** `CreateFrame('Frame', name, E.UIParent, 'SecureAuraHeaderTemplate')`, with cancel buttons set through `SetCancelAuraButtons`.
- **Minimap.** Reparents the minimap parts to a hidden frame (`E.HiddenFrame`) or calls `:Kill()`, and reshapes the Minimap itself.
- **The lesson.** For windows where Blizzard's own buttons do protected work (trade Accept, mail Send, auction buy), restyling or reparenting Blizzard's frame is safer than rebuilding it. Our "replacement" there can be our layout and navigation on top of Blizzard's buttons.

### QuestieForeverGamepad (installed, v0.5.12, 58k lines)

- It reaches Questie through `QuestieLoader._modules` (ZoneDB, QuestieDB, QuestieTracker and others) and guards every call with `pcall` and a safe mode.
- Its research notes (`SIDEBAR-CONTROLLER-RESEARCH.md`) document how Forever's map forces quest log focus. Read them before building our map.
- It already has a controller quest tracker, map waypoints and a radial menu. Our quest log and tracker must not fight it: detect it and either work with it or stand aside.

### Questie (installed, v12.15.0, `Questie_Forever.toc`)

- Modules come from `QuestieLoader:ImportModule("Name")`, or `QuestieLoader._modules` as QuestieForeverGamepad does.
- The useful modules are QuestieDB (quest, NPC, object and item data), QuestieTracker (`GetNumTrackedQuests`, `RemoveQuest`, `UntrackQuestId`), QuestieMap, ZoneDB and QuestieJourney.
- Upstream: github.com/Questie/Questie (its README has an API section).
- Other trackers that coexist with Questie hide its tracker once with the player's OK and avoid the hooks Questie puts on the game's watch functions (EQ Objective Tracker).

### BagPad (installed, v1.5.2)

The player uses it and likes it, so our bags and bank take their features from it.

**How it works.** There are two parts, built two different ways.

- **Bags.** It doesn't replace the bag window. It builds on Blizzard's combined bag frame (`ContainerFrameCombinedBags`) and restyles it (`Core/NativeBags.lua`).
  - Blizzard's own gamepad cursor (SmartNavigation) moves between the item buttons, so use, sell and move stay Blizzard's secure code.
  - BagPad only reads where the cursor is (`SmartNavigation.currentButton` and the `ContainerFrameItemButton.EnterButton` event, `UI/Focus.lua`).
- **Bank.** It replaces the bank with its own window, `BagPadBankWindow` (`UI/BankWindow.lua`).
  - It sets `BankFrame`'s alpha to 0 and puts its window on top.
  - It uses `C_Bank` for the bank tabs, and a `SecureActionButtonTemplate` button to buy tab slots.
- **Its own windows.** The options window, item menu and alternate-character view read the controller through an invisible catcher frame. The frame has `OnGamePadButtonDown` and polls `C_GamePad.GetDeviceMappedState`, consuming only the keys it handles (`Input/Controller.lua`).
- **Combat.** Nothing is consumed in combat. A BagPad window either closes or pauses its input.
- **Its taint rules match ours.** It only post-hooks, never calls Forever's gamepad systems, never writes fields onto Blizzard frames and never creates frames inside the open bag frame (SmartNavigation rescans from inside `CreateFrame`). Its notes call these rules "learned the hard way".

**It needs Forever's gamepad mode on.**

- The bag navigation is Forever's cursor, which is off in mode 0.
- Its input catcher only takes gamepad buttons when the gamepad UI is on: `catcher:EnableGamePadButton(GamepadUIEnabled())`, `Input/Controller.lua:235`.
- So with gamepad mode off, BagPad's bags and windows can't be driven by the controller. That is why our own bags come early in the plan, built in the BagPad style.

**Features to take for our bags and bank:**

- **Detail panel** (`UI/Detail.lua`). It shows the focused item's icon, name, quality and type, and the full tooltip text taken as data (`C_TooltipInfo.GetBagItem`, no GameTooltip scanning). It also shows the count across your bags, the vendor price, where the item sits and what each button does with it now.
- **Compare.** L1 held compares the item with what you wear in its slot (`Input/Shoulders.lua`). R1 flips the panel to the Data Broker: where the item is across your characters and your account.
- **Item menu** on Cross (`UI/ItemMenu.lua`), with a bind picker and confirms.
- **Category groups and bag breaks**: by item type or by bag type (`Data/Categories.lua`), and a category rail layout.
- **Search**, a cleanup button, a lock button, currencies in the header and bag looks and coloring.
- **Header navigation** (`Input/HeaderNav.lua`). Up from the top row reaches the header buttons, left and right move between them, Circle or Down goes back to the items.
- **Alternate view** (`UI/AltView.lua`): another character's bags as a read-only snapshot.
- **The bank** as its own window with a tab list and a fill bar per bag. Bank and mail keys come from the bags (`Input/BankKey.lua`, `MailKey.lua`).
- **Profession data** (`Data/ItemSkills.lua`, `RecipeData.lua`, `Crafts.lua`) and auction prices.
- **Mouse mode**, which switches the hints when the mouse is used (`Input/MouseMode.lua`).
- **Settings sharing** and profiles (`Config/Share.lua`, `UI/ProfilePage.lua`).

**Working with BagPad.** While both addons are installed and gamepad mode is on, ours stands aside and BagPad keeps the bags, like BagPad's own conflict list (`CONFLICTS` in `Core/NativeBags.lua`). With gamepad mode off, our bags take over. Asking BagPad's author (Chris) about a controller path for gamepad mode off is worth doing before we rebuild everything.

### Other local addons worth reading

- **BagPad** (v1.5.2, MIT, about 26,000 lines): the player's bag addon and the model for our bags and bank. See "BagPad" below.
- **ForeverGamepadUI_Flightmaster** (v0.1.18) is a full controller flight map with its own InputDriver.lua and MapView.lua. It is a working example of a pad-driven map on Forever.
- **TomTom** and **HandyNotes** provide waypoints and map pins for our map to show.

## Architecture

### 1. Navigation core (new, about 1500 lines)

- **`ns.Nav`** owns one D-pad cursor.
  - A window registers nodes: a button with optional up / down / left / right overrides, grid hints and a scroll owner.
  - Navigation runs over our own node lists, not a screen scan, so the order is always the visual order. This fixes ConsolePort's ArkInventory problem.
- **The generic cursor** covers every window we haven't replaced: Blizzard's, other addons' and popups.
  - It scans a window's visible, enabled buttons and moves by screen position, like ConsolePort's interface cursor.
  - Cross clicks the real button through an override binding click (`SetOverrideBindingClick` to the button's name, or a secure proxy for nameless ones), so Blizzard's own secure code runs.
  - With gamepad mode off, this is the only navigation those windows have, so it must be finished before the off option ships.
- **`ns.Focus`** is the Back registry and priority cycle described above.
- **`ns.Bindings`** is the single holder of override binding claims, with levels like ConsolePort's.
- **`ns.Hint`** is the footer hint bar. It uses the `{PADxxx}` tokens and `ns.ButtonMarkup`, and redraws when the controller changes.
- **Secure parts** are built out of combat.
  - Item slots inherit Blizzard's item templates.
  - Aura buttons use `SecureAuraHeaderTemplate`.
  - Click proxies use `SecureActionButtonTemplate` for protected buttons.
- **Fallback.** If a replacement window fails to load (error or missing API), Blizzard's window shows instead and the error goes to the error report.

### 2. Window kit (new)

The base for every replacement:

- a window template (themed with Theme.lua) with a title, tabs (L1 / R1), a footer hint and a list or grid body;
- list, grid and scroll widgets that wrap with `ns.StepWrap`;
- a tooltip panel (R3, or a hold) and a context menu (Square), reusing the chatbox menu code;
- a pairing helper for the two-window flows (bags plus vendor, bank, trade or mail).

### 3. Replacements, in order

The order follows what the player uses most, so each alpha can be tested in normal play (decided 2026-11-26). Rows 1 to 7 together are **milestone A**: the set that makes daily play testable with gamepad mode off.

| # | Window | Method | Notes | Size |
|---|---|---|---|---|
| 1 | Bags and bank | Replace (like ElvUI), with BagPad's features | Grid of item templates, so item use stays secure. BagPad's detail panel, compare on L1, item menu, categories, search, cleanup, header navigation and a bank window of our own (see "BagPad"). Tab slot purchase through a secure button, like BagPad. Turn off ContainerFrames like `B:DisableBlizzard`. With gamepad mode on and BagPad installed, ours stands aside. | L |
| 2 | Mail | Our layout, with Blizzard's buttons for sending | Inbox list, open, take items and gold, take all, return, delete behind a confirm. A send page with recipient (recent and friends list), subject, gold and items from the bags, which pair with it. `SendMail` may be restricted, so send through Blizzard's own button if needed. | M |
| 3 | Loot | Replace | Loot list with Cross to take, Square to take all, items going to the bags. Keep master loot and group loot rules. Works with auto loot. | S |
| 4 | Interacting with NPCs | Replace | Gossip and the quest dialog: options as a list, quest text with stick scroll, reward picker, Cross to accept or complete (all APIs are free; check against QuestieForeverGamepad's Gossip.lua and Immersion.lua). Vendor: pairs with bags, Triangle switches sides, Cross sells or buys, Square asks how many, buyback on R1, auto-sell grey items (setting). Trainer: list with filters, Cross to learn, cost shown. Flight master: ForeverGamepadUI_Flightmaster if installed, else a list. Plus the interact CVars and prompt with mode off (see "Playing the game with gamepad mode off"). | L |
| 5 | Map | Replace or heavily restyle | Hardest one. Our own map canvas from `C_Map` data plus Questie, TomTom and HandyNotes pins. Right stick cursor, L1 + stick zoom, D-pad zones, Triangle zone / continent / world. Study ForeverGamepadUI_Flightmaster's MapView.lua. Leatrix_Maps and OpenMap are installed and may conflict. A first version can be the zone map with pins and zoom, with continents and the world after. | XL |
| 6 | Popups | Replace the controls, keep Blizzard's answers | Group invite, LFG invite with the role boxes, role check, ready check, loot rolls, summon, resurrect, duel, guild invite, trade request and the game's confirm dialogs. We already answer several with the controller (`Input.lua:428-580`, `910-966`, RollPicker.lua). With mode off they must take focus by themselves and show button hints. | M |
| 7 | Trade | Our layout, with Blizzard's buttons | Pairs with bags. Cross on a bag item puts it in the trade. Gold field. `AcceptTrade()` works from our code (`Input.lua:523`). Takes focus when it opens. | M |
| 8 | Quest log | Replace | Zone groups, details, track / untrack, abandon behind a confirm, share. Questie data for start / end NPCs and objectives when installed. | M |
| 9 | Character | Replace | Paper doll slots as a grid, stats, equip from a filtered bag list (FFXIV armoury style), equipment sets (fixes the v0.1.8 anchoring issue for good). Reputation and skills tabs on L1 / R1. | L |
| 10 | Buffs and debuffs | Replace with SecureAuraHeader | Back cycle target. D-pad steps through them, Cross cancels (secure). Tooltips. | M |
| 11 | Minimap | Restyle and reparent (like ElvUI) | Back cycle target for its buttons (tracking, calendar, LFG and addon buttons). | M |
| 12 | Spellbook, talents, professions | Later | We already hook the spellbook for placing abilities (Spellbook.lua). | L |
| 13 | Auction house | Later, or support Auctionator | Large, and Auctionator is installed. | XL |
| - | Everything else | The generic cursor | Game menu, social, guild, talents, Blizzard settings, Edit Mode, stable, other addons' windows. Needed from Phase 1 when gamepad mode is off. | L |

Already ours: crossbars, LFG Filter, ChatBox, loot roll picker, ring menu and settings.

### 4. Settings

- A "Windows" page with a toggle per replaced window (off by default during testing) and the Back cycle order editor.
- The Forever gamepad mode switch, with its reload popup and a warning about the Edit Mode layout reset.

## Playing the game with gamepad mode off

Interacting with NPCs, objects and corpses doesn't depend on gamepad mode. It is the game engine's soft targeting, which Forever's mouse-and-keyboard settings also offer ("Enable Interact Key", `Blizzard_SettingsDefinitions_Frame/Controls.lua:71`).

- **Interact.** The `INTERACTTARGET` binding is `C_PlayerInteractionManager.InteractUnit("anyinteract")` (`Bindings_Camelot.xml:1140`).
  - Today Cross clicks Forever's gamepad action button 1. `ForeverButtonBinding` in `Input.lua:227` already falls back to `INTERACTTARGET` when that button doesn't exist, as with mode off.
  - Our interact prompt, the wand / attack choice and loot keep working on top of it.
- **Soft targeting.** The CVar `SoftTargetInteract` takes flags: 0 none, 1 gamepad, 2 keyboard and mouse, 3 any (`SoftTargetConstantsDocumentation.lua`). Forever's mouse-and-keyboard default is 1, so soft interact already follows the controller. Gamepad mode only raised the range to 20 and turned on the icons and arcs. We set the same 29 CVars ourselves (list under "Forever's gamepad mode: what it is"), with our own settings for range and icons, restored at logout.
- **Targeting.** Our L1 / R1 and D-pad targeting use normal bindings and secure buttons (TARGETNEARESTENEMY, party targeting), so they don't need the mode. Forever's own gamepad targeting (its target modifiers, `GamepadMode.RegisterTargetModifierStateChanged`, raid traversal) goes away. ConsolePort turns that context back on by itself when it wants it (`NativeGamepad.lua`). We don't use it today.
- **Ground spells.** Cross places them today through the screen click (`Input.lua:1451`). With mode off, there is no gamepad cursor, so test whether the click still lands under the reticle or the character.
- **Camera and movement** are the engine's gamepad sticks, plus our right stick code. Phase 0 tests them.
- **Mounting, jumping, sheathing and the rest** are plain bindings and keep working.

So yes, interacting can be copied. Phase 0 adds checks for interact, soft target icons and ground spells.

## Alpha releases

The UI rework lives on the `ui-rework` branch. `main` keeps getting normal releases.

- **Tags set the CurseForge release type.** The BigWigs packager reads them.
  - `vX.Y.Z` is a release.
  - `vX.Y.Z-alpha.N` is an alpha, and `vX.Y.Z-beta.N` is a beta.
- **Alphas are opt-in.** Players only get them if they set Gamepad XIV to Alpha in the CurseForge app, or download the file by hand. Everyone else stays on the newest release.
- **The workflow** (`.github/workflows/release.yml`) builds test packages on pushes to `main` and `ui-rework`. Before publishing a tag, it checks the tag:
  - a release tag must be on `main`;
  - any other tag must be `-alpha.N` or `-beta.N`.
  - That way an alpha commit can't go out to every player.
- **The alpha number line is v0.2.0-alpha.1, alpha.2 and so on.** It sits above the v0.1.x releases, and the first full release of the rework is v0.2.0.
- **The version check ignores alpha versions.** Release players are never told to update to an alpha, and alpha players get no release reminders (`VersionCheck.lua`, `Release`).
- **"What's new" handles alphas.** News.lua's version compare now orders alpha < beta < release, so alpha.2 shows what changed since alpha.1.
- **Steps for an alpha**, on `ui-rework`:
  1. rename "## Unreleased" to "## v0.2.0-alpha.N";
  2. run `python3 tools/make_changelog.py`;
  3. commit "v0.2.0-alpha.N: ...", then push `ui-rework`;
  4. check `git ls-remote --tags origin`, then tag and push the tag once.
- **Keep `ui-rework` current.** Merge `main` into it after each release, so alpha players also get the fixes.

## Phases

0. **In-game test of gamepad mode off (gate for phase 2).** No code. The steps are below. If the controller doesn't work with style 0, drop the off option and build the windows with the mode on.
1. **Navigation core, window kit and generic cursor**, plus the Back registry over the windows we have today. With the mode on, Back slots Forever's cycle into ours. No user-visible change except the Back order settings.
2. **Gamepad mode off support**, only if phase 0 passed and the generic cursor works on every common window. The CVar handling, the reload flow, soft targeting and camera CVars, and checks of every existing feature in both modes. Ship it as an experimental option.
3. **Milestone A, in the player's order of use:** bags and bank, mail, loot, interacting with NPCs (gossip, quest dialog, vendor, trainer), map, popups (invites, roles, rolls, confirms), trade. One alpha per window or two, so each can be tested in normal play as it lands.
4. **Quest log with Questie, character, buffs and debuffs, minimap.**
5. **Spellbook, talents, professions, then the auction house.**

Each phase ships on its own with its windows default off, then default on once players confirm they work.

**Testing while milestone A is built.** The player plays with gamepad mode on until milestone A is done, turning each new window on in the settings as it lands. Our windows work in both modes. Then the player switches gamepad mode off for daily play. Until then, windows not built yet keep Forever's navigation.

### Phase 0 steps (for the player)

Switching modes resets the active Edit Mode layout to the default preset, so note any Edit Mode changes first. Keep a keyboard and mouse at hand to switch back.

1. Check the starting values: `/run print(GetCVar("InputDeviceInterfaceStyle"), C_GamePad.IsEnabled())`
2. Switch to the mouse-and-keyboard style: `/run SetCVar("InputDeviceInterfaceStyle", 0)`, then `/reload`.
3. Check the controller: `/run print(C_GamePad.IsEnabled(), C_GamePad.GetActiveDeviceID(), C_GamePad.GetDeviceMappedState() ~= nil)`
4. Test in game:
   - the face buttons, D-pad and shoulders on the crossbar;
   - the triggers and the top bars;
   - both sticks (moving and camera);
   - Back, Start and L3 / R3;
   - interact with an NPC;
   - targeting with L1 / R1 (no soft target is expected yet);
   - a form or stance change (stance storage);
   - Cross on an NPC, a mailbox, a herb and a corpse (interact), and whether the soft target icon shows;
   - a ground spell placed with Cross.
5. Print the stance storage: `/run print(C_GamepadUI.GetFirstGamepadActionBarStorageSlotIndexForActiveStance())`
6. `/gxiv log` on before testing, then `/reload` to save the log for reading.
7. Switch back: `/run SetCVar("InputDeviceInterfaceStyle", 1)`, then `/reload`.

## Risks and open questions

- **Does a controller work fully with `InputDeviceInterfaceStyle = 0`?** It does on retail with `GamePadEnable`. On Forever it is unknown, and Phase 0 answers it on the DualSense under Linux.
- **Our crossbar uses normal action slots**, but form and stance sets read Forever's stance storage. Phase 0 checks that with the mode off.
- **Taint from replacing Blizzard windows.** Every replacement must hide Blizzard frames without tainting them. Use `UIParent` panel attributes, hidden parents and hooks, never `ShowUIPanel` or a write to Blizzard state. ElvUI's `DisableFrame` is the reference.
- **Other addons that expect Blizzard frames** (BagPad, Auctionator, Questie, Leatrix, MovableWindowsForever) may break when a frame is hidden. Each replacement needs a compatibility check with the installed addons.
- **Forever patches.** Forever's UI changes weekly in beta (build 71139 is from 25 Nov 2026). Keep the reference source checked out and diff it on each patch.
- **Size.** The addon is about 28,000 lines today. This plan likely adds 15,000 to 25,000. The 200-locals limit and the load order need a module layout: one folder per window, like ConsolePort's Model / Controller / View.

## Research data

### Sources

- Forever UI source: https://github.com/Gethe/wow-ui-source/tree/forever (commit d9c22e32cb240afb82bb2ecefbb78ef935333f59, "1.60.1 (71139)", 25 Nov 2026). Files read:
  - `Blizzard_Gamepad/Core.lua`: mode init / uninit, temp CVars, binding context.
  - `Blizzard_Gamepad/Blizzard_Gamepad.toc`: the parts (reticle, HUD mode, radials, persistent input legend, item pickup cursor). `AllowLoadGameType: camelot`.
  - `Blizzard_SharedXML/InputUtil.lua`: `INPUT_DEVICE_INTERFACE_TRANSITION` handling, `RegisterGamepadInit` / `Uninit` / `MKBInit`.
  - `Blizzard_SharedXML/Mainline/InputUtil.lua`: `IsGamepadUIEnabled()` is `C_InputInterfaceStyle.GetCurrentStyle() == Enum.InputDeviceInterfaceType.Gamepad`. `IsGamepadUISupported()` only checks that the `InputDeviceInterfaceStyle` CVar exists.
  - `Blizzard_SettingsDefinitions_Shared/Gamepad.lua`: the "Enable Gamepad UI" checkbox and the gamepad settings (camera speeds, invert, face movement, legend, focus opacity, party targeting, swap modifiers, raid hover mode).
  - `Blizzard_Kiosk/BlizzCon2026/ColdSwap.lua`: swapping needs a reload.
  - `Blizzard_UIModes/Blizzard_UIModeManager.lua`, `Blizzard_UIModeUtil.lua`: roleset HUD hiding.
  - `Blizzard_GamepadSmartNavigation/SmartNavigation.lua`, `Utility.lua`, `SecureHelper.lua`: the native cursor and its addon hooks.
  - `Blizzard_APIDocumentationGenerated/*`: InputInterfaceStyle (`GetCurrentStyle`), GamepadUI (action storage slots, possess and stance bar overrides), RolesetSystem, LimitedInput, GamePad (`IsEnabled`, `GetConfig` / `SetConfig`, `SetVibration`, `SetLedColor`, `GetPowerLevel`, `SetAllowHoverEventsWithFreeLook`).
  - A copy of all the Lua and XML is kept in `.reference/wow-ui-source-forever` (git-ignored, see "Local reference copies"). To get it again: `git clone --depth 1 --branch forever --filter=blob:none https://github.com/Gethe/wow-ui-source.git`.
- ConsolePort: https://github.com/seblindfors/ConsolePort (commit ed3a6b3, 23 Nov 2026). Files: `CLAUDE.md`, `ConsolePort/Utils/Const.lua`, `ConsolePort/Controller/NativeGamepad.lua`, `Securenav.lua`, `GamepadActions.lua`, `Slash.lua`, `ConsolePort_Cursor/Controller/Stack.lua`, `View/Cursor.lua`, `ConsolePort_World/View/LootFrame/LootFrame.lua`, `ConsolePort_Menu/Database.lua`, `ConsolePort_Bar/Controller/Blizzard/Mainline.lua`.
- ElvUI: https://github.com/tukui-org/ElvUI. Files: `ElvUI/Game/load_forever.xml`, `Shared/Modules/Bags/Bags.lua` (`DisableBlizzard` at line 404, slot templates at line 2153), `Auras/Auras.lua:704`, `Auras/Containers.lua:406`, `Maps/Minimap.lua`.
- ArkInventory ConsolePort Support (why a position-based cursor skips items): https://www.curseforge.com/wow/addons/arkiventory-consoleport-support
- Questie: https://github.com/Questie/Questie, and the local copy at `Interface/AddOns/Questie` (12.15.0).
- EQ Objective Tracker (coexisting with Questie's tracker): https://www.curseforge.com/wow/addons/eq-objective-tracker
- QuestieForeverGamepad, local: `SIDEBAR-CONTROLLER-RESEARCH.md`, `SAFE-MODE-GUARDS.md`, `UICompatibility.lua`.
- Blizzard: https://news.blizzard.com/en-gb/article/24316974 (Explore WoW: Forever with a Gamepad), https://us.forums.blizzard.com/en/wow/t/wow-forever-beta-development-notes-%E2%80%93-updated-november-2/2360696 (beta development notes).
- https://frvr.com/blog/news/world-of-warcraft-forevers-controller-support-now-covers-all-major-gameplay-and-core-ui-as-blizzard-continues-to-improve-gamepad-controls/ (3 Nov 2026)
- Icy Veins on addons in Forever (blocked automated reads, so only the search summary was available): https://www.icy-veins.com/wow-forever/news/addons-in-wow-forever-blizzard-devs-just-addressed-the-big-question/. It reports that Forever uses the Midnight API restrictions and shares Mainline's UI architecture, with most 12.1.5 APIs.
- FFXIV: https://ffxiv.consolegameswiki.com/wiki/Controller_Guide, https://ffxiv.consolegameswiki.com/wiki/Controls, https://www.akhmorning.com/resources/controller-guide/interacting-with-eorzea/, https://na.finalfantasyxiv.com/uiguide/faq/faq-interface/control_gamepad_btn.html, https://na.finalfantasyxiv.com/uiguide/faq/faq-interface/interface_pad_mouse.html, https://forum.square-enix.com/ffxiv/threads/507955-PS5-UI-Elements-Controller-Help?p=6749496, https://forum.square-enix.com/ffxiv/threads/506228-Controller-Quality-of-life-changes

### Research data: FFXIV

Button names are PlayStation, with Xbox in brackets.

- **Cross (A)** confirms. It can be remapped, and Japanese and Switch 2 layouts swap Confirm and Cancel.
- **Circle (B)** cancels. It goes back a level in sub-lists and closes the map when the map is active.
- **Square (X)** is the sub-command, the context menu. In some dialogs it also confirms.
- **Triangle (Y)** jumps in the world. In dialogs like the Duty Finder it confirms and closes. In the inventory it switches between the retainer or saddlebag and your inventory.
- **Touch Pad (Back / View)** cycles the HUD.
  - On PS5, the share button doesn't cycle. Players use touch pad clicks: with "expanded touch pad controls", the left and right halves can cycle forward and back.
  - Light taps act as a mouse click when the touch pad is set as a mouse.
- **Options (Start)** opens the main menu. Its entries are navigated with the D-pad.
- **D-pad or left stick** moves the cursor in menus.
- **R1 (RB)** goes to the next tab. In chat it is auto-translate, and on the map it changes the floor.
- **L1 (LB)** is a modifier:
  - L1 + D-pad up / down: enmity list;
  - L1 + D-pad left / right: alliance lists;
  - L1 + R1 or L2 / R2: tab targeting;
  - L1 + right stick: map zoom;
  - L1 + R1: paste.
- **L2 / R2** highlight the left or right hotbar. In item tooltips, L2 shows the HQ version and R2 hides the tooltip.
- **L3** draws or sheathes the weapon, or locks on. **R3** is first person by default; guides say to remap it.
- **Virtual mouse:** L1 + R3 toggles it, the right stick moves it, L2 left-clicks and R2 right-clicks. It is used to move and resize windows, since there is no pad-native drag.
- **HUD cycle order** (AkhMorning guide): Scenario Guide, Chat, Duty List, Map (if open), Minimap, open menus (Inventory, Actions and so on), Status Effects.
  - A player in 2024 saw: open menus, Scenario Guide, Chat, Duty List, Minimap, Status Effects.
  - The main menu, hotbars, gauges, party / alliance / enmity lists, the food status bar and the target status bars are not in the cycle.
- **HUD focus.** Inside a HUD element, the D-pad, Confirm, Sub-command, bumpers and triggers control it. Cancel leaves focus and keeps the window open.
- **Map.** It is "active" (with the hint bar and side menu) or only "visible". Moving the stick only makes it visible. Settings: "Close Immediately", "Close When Active", "Restore map when not moving".
  - Square opens it. The right stick moves the cursor, L1 + right stick zooms and R3 recentres.
  - The D-pad picks a region or zone, Cross selects, and L1 or Triangle opens the zone dropdown. Triangle steps zone / region / world, R1 changes the floor and L1 + R1 makes a map link.
- **Inventory with a retainer or saddlebag.** Triangle switches to your inventory or the Armoury Chest. Cross moves the item to the other side with no menu. Withdrawing uses a "Retrieve" sub-menu.
- **Quest hand-ins.** The focus is already on the hand-in box. Square filters to items that fit. Cross opens the whole inventory and may land on the wrong item.
- **Duty List.** Up / down picks a quest, left / right picks its item.
- **Party.** D-pad up / down steps through members (we have this).
- **Buffs.** Reached with the HUD cycle. The D-pad steps through them and Confirm removes one. Other units' buffs need a mouse cursor.
- **Chat.** In gamepad mode, direct chat is on, so a keyboard types right away. Otherwise HUD-cycle to the chat, then Cross. On PS, Triangle opens the virtual keyboard. The chat type icon is reached with D-pad left / right. Cross or Square on a name or link in the log opens the map, the journal or an item menu.
- **Player requests.**
  - A configurable HUD cycle order, maybe a different one with the weapon drawn.
  - Fewer presses to reach buffs in combat.
  - Back-and-forth cycling.
  - A target filter for dead players.
  - Touch pad targeting of hotbar slots.
  - Saving settings to load on other characters (we have profiles).

### Research data: Forever's gamepad mode, from Blizzard's posts

- It is still "a functional beta". Not every screen has a footer yet.
- It supports XInput controllers, with Xbox and PlayStation icons.
- Settings are under Options > Gameplay > Gamepad: Camera, HUD Modifier, Frame Focus Style, Action Bars, Targeting, Raid Targeting Options.
- Bars: 4 bars per set (LT, RT, LT + RT), 3 sets switched with LB + RB and D-pad left / right.
- LB + RB shortcuts: B opens the backpack, Up the quest tracker, Down the chat and Y "Manage Buffs". Menu opens the main menu and View is "Change Focus Frame".
- Sept 24 build: class flyouts (druid forms, hunter and warlock pets, paladin auras, warrior stances), "Use Compact Action Bar", "Fixed Party Targeting", swap options for the target modifiers, map and quest log bindings, hover for POI pins, stable UI.
- Oct 1: gamepad UI bindings are static. Rebinding only changes keyboard and mouse.
- Oct 8: opening the map starts focus on the quest log. The gamepad bar got Edit Mode support, and compact mode moved into Edit Mode.
- Oct 16: the Auto Attack / Auto Shot setting works with the gamepad.
- Later builds, from the summarized end of the page and not checked word for word: gamepad support for trade, guild, chat channels and transmog. Also "Improved Gamepad UI compatibility with user-created add-ons" (Nov 3).
- Known issue: "Switching to or from Gamepad UI mode resets the active edit mode layout to the default preset."
- A keyboard is still needed for chat. Blizzard calls a keyboard-free game a longer-term aim.

### Research data: Forever API and code details

- **Forever's addon hooks for SmartNavigation** (globals in `Blizzard_GamepadSmartNavigation/Utility.lua`):
  - ignoring: `MarkFrameIgnored`, `ClearIgnoreStatus`, `IsFrameIgnored`, `MarkFrameIgnoredContainerFrame`, `IsIgnoredContainerFrame`;
  - focus: `MarkFrameFocusable`, `IsFrameFocusable`, `SetButtonFrame`, `CanFocusFrame`, `ResetData`;
  - sub-sections: `MarkFrameSubSection`, `IsFrameSubSection`;
  - direction buffers: `SetDirectionBufferThreshold`, `GetDirectionBufferThreshold`, `ClearDirectionBufferThresholdInDirection`, `ClearDirectionBufferThresholds`;
  - scroll boxes: `MarkFrameNonCollapsingScrollBoxElement`, `IsFrameNonCollapsingScrollBoxElement`, `SelectScrollBoxCurrentOrTop`, `MarkScrollFrameMaintainPreviousButtonOnScroll`, `ShouldScrollFrameMaintainPreviousButtonOnScroll`;
  - clicks: `MarkFrameBlockingSmartNavClick`, `IsFrameBlockingSmartNavClick`, `IsCurrentButtonClickable`;
  - cursor: `SetCustomCursorAnchorPointForFrame`, `GetCustomCursorAnchorPointForFrame`, `UseVerticalCursorForFrame`;
  - jumps: `AddJumpNavigationOverride`, `AddBidirectionalJumpNavigationOverride`, `ClearJumpNavigationOverridesInDirection`, `ClearJumpNavigationOverrides`, `AddIgnoreInputNavigationOverride`, `GetNavigationOverrideFrame`;
  - callbacks: `RegisterOutgoingDirNavCallback`, `RegisterOutgoingNavCallback_MultiDir`, `ClearOutgoingNavigationCallbacks`, `CallOutgoingDirNavigationCallbacks`.
  - All of them are prefixed `SmartNavigation_`. BagPad warns that writing these flags from addon code taints Blizzard's grid code. Avoid them, even with the mode on.
- **SmartNavigation methods** (`SmartNavigationMixin` in SmartNavigation.lua): `ShowCursor`, `HideCursor`, `SelectButton`, `TrySelectButton`, `Navigate`, `NavigateUp` / `Down` / `Left` / `Right`, `Click`, `RightClick`, `AttemptClose`, `OnGamepadRightStick`, `HandlePanelOpen`, `RefreshButtonGroups`, `SetWrapping`, `SetUseGridNavigation`, `GetActiveFrame`.
  - The fields `currentButton` and `activeInfo.frame` are what our code and BagPad read (read only).
  - Default direction buffer is 45 degrees, and diagonal moves are off (`ALLOW_DIAGONAL_NAVIGATION = false`).
  - It scores the closest button in a direction and has a grid mode.
- **`C_GamePad`:**
  - mapping and config: `AddSDLMapping`, `ApplyConfigs`, `GetConfig`, `SetConfig`, `DeleteConfig`, `GetAllConfigIDs`;
  - index and name lookups: `AxisIndexToConfigName`, `ButtonBindingToIndex`, `ButtonIndexToBinding`, `ButtonIndexToConfigName`, `StickIndexToConfigName`;
  - devices and state: `GetActiveDeviceID`, `GetAllDeviceIDs`, `GetCombinedDeviceID`, `GetDeviceMappedState`, `GetDeviceRawState`, `IsEnabled`, `GetPowerLevel`;
  - LED and vibration: `GetLedColor`, `SetLedColor`, `ClearLedColor`, `SetVibration`, `StopVibration`;
  - hover: `GetAllowHoverEventsWithFreeLook`, `SetAllowHoverEventsWithFreeLook`.
- **`C_GamepadUI`:** `GetFirstGamepadActionBarStorageSlotIndexForActiveStance`, `GetFirstGamepadActionStorageSlotIndex`, `GetFirstGamepadPetActionStorageSlotIndex`, `IsValidGamepadActionStorageSlotIndex`, `IsValidGamepadPossessBarStorageSlotIndex`.
  - Events: `GAMEPAD_POSSESS_BAR_OVERRIDE_CHANGED`, `GAMEPAD_STANCE_BAR_OVERRIDE_CHANGED`.
  - Constants: 4 slots per group and 2 groups per gamepad bar (8 slots).
  - Possess and stance overrides target Page1-3 Top, Left, Right and Bottom bars.
- **`C_GamepadTargeting`** (GamepadTargetingManager): `Enable`, `Disable`, `SetFilter` with filters Hostile, Friendly, All.
- **`C_InputInterfaceStyle.GetCurrentStyle()`** returns `Enum.InputDeviceInterfaceType` (Mkb 0, Gamepad 1).
- **`C_LimitedInput.LimitedInputAllowed(type)`** with types MouseMove, MouseDown, MouseUp, MouseWheel.
- **`Enum.SoftTargetEnableFlags`:** None 0, Gamepad 1, Kbm 2, Any 3. The mouse-and-keyboard "Enable Interact Key" sets `softTargetInteract` to Any (on) or Gamepad (off).
- **`INTERACTTARGET`** (`Blizzard_FrameXML/Bindings_Camelot.xml:1140`) is `C_PlayerInteractionManager.InteractUnit("anyinteract")`.
- **Forever's gamepad settings CVars** (`Blizzard_SettingsDefinitions_Shared/Gamepad.lua`):
  - camera and turning: `GamePadCameraYawSpeed`, `GamePadCameraPitchSpeed`, `gamepadInvertYaw`, `gamepadInvertPitch`, `GamepadCameraFollowOnStick`, `GamepadCameraFollowPitchOffset`, `GamePadTurnWithCamera`;
  - movement: `GamePadFaceMovementMaxAngle`, `GamePadFaceMovementMaxAngleCombat`, `GamePadBackPedalThreshold`, `GamePadRunThreshold`, `GamePadFaceMovementMount`, `GamePadFaceMovementSwimming`, `GamePadFaceMovementFreeFlying`;
  - HUD and focus: `GamepadShowPersistentInputLegend`, `GamepadHudModifierUsesToggle`, `GamepadFocusStateColor`, `GamepadFocusStateOpacity`;
  - bars: `GamepadPossessBarOverride`, `GamepadStanceBarOverride`;
  - targeting: `GamepadUsePartyTargeting`, `GamepadSwapTargetModifiers`, `GamepadSwapFriendlyTargetActions`, `GamepadSwapHostileTargetActions`, `GamepadRaidTargetingHoverMode`;
  - cached by Blizzard_Gamepad: `GamepadActionBarLeftRightDelay`, `GamepadActionBarTopBottomDelay`, `GamepadTargetingModifierVisualDelay`, `GamepadCompassCustomFilterFriendly`, `Enemy`, `Boss`, `Party` and `Critter`.
- **Blizzard_Gamepad's parts:**
  - `Utility/Bindings/HoldBindings.lua`;
  - `UI/ConsoleHUD`, `CinematicMovie`, `Reticle`, `HUDMode`, `Radials`, `PersistentInputLegend`;
  - `FrameReforms/StackSplitFrame.lua`, a pad stack-split dialog;
  - `SmartNavigationInGame/FrameBoltOns/GamepadItemPickupCursor`.
  - Its dependencies are Blizzard_SharedXML, Blizzard_GamepadSmartNavigation, Blizzard_GamepadSharedUtility and Blizzard_MicroMenu.
- **Other gamepad folders:**
  - Blizzard_GamepadSharedUtility (1189 lines): FrameControlsManager, FrameReformUtility, InputBindingStack, InputHandlers, InputPrompts, InputSequence, Page, PromptedBindings, Tab and Templates;
  - Blizzard_GamepadSharedUtilitySecure (SecureBaseDialog);
  - Blizzard_GamepadSoftCursor (190 lines);
  - Blizzard_GamepadTargeting (459 lines: GroupTargeting, TargetLogic, RaidPartyTargeting);
  - Blizzard_HUDInventoryTemplates, Blizzard_ItemBeltFrame.
- **`UIModeUtil`'s standard "hide most" rolesets:** unitFrames, actionBars, minimap, buffs, objectives, statusBars, cooldownViewers, swingTimers, encounterUI, pvp, extraAbilities, widgets, queuestatus.
- **ConsolePort details:**
  - Its `Slash.lua` uninstall sets `GamePadEnable` to 0, disables the addon and clears pad bindings.
  - `CPAPI.IsNativeGamepadUI = C_GamepadUI ~= nil`.
  - On Forever, `ConsolePort_Bar` hides Blizzard's BagsBar and MicroMenu (`Controller/Blizzard/Mainline.lua:91`).
  - The unit menu uses 'surname' in place of 'server' on Forever (`ConsolePort_Menu/View/Popup/UnitMenu.lua:6`).
- **ElvUI details.** `B:DisableFrame(frame)` is the helper that turns off a Blizzard frame. The combined bag frame keeps `BAG_CONTAINER_UPDATE` registered, to avoid a nil item button at vendors.
- **Gamepad XIV today:**
  - Back: `Snippets.lua:222-251`, `Input.lua:866`.
  - Interact: `Input.lua:227` (`ForeverButtonBinding`) and `Input.lua:328`.
  - Ground spells: `Input.lua:1451`.
  - Trade and invite answers: `Input.lua:523` and `910`.
  - Stance storage: `Input.lua:1629`.
  - Storage overlap warning: `Core.lua:228`.
  - Code that reads SmartNavigation: MenuWrap.lua:73, Items.lua:96, Lfg.lua:59, Input.lua:1520, Spellbook.lua:119.

### Local reference copies

Kept in `.reference/`, which is git-ignored and not packaged (the packager builds from git). It is 216 MB.

- `.reference/wow-ui-source-forever`: Forever UI source, commit d9c22e3, build 71139. Lua, XML and toc files only (sparse checkout). To update it on a Forever patch: `git -C .reference/wow-ui-source-forever pull --depth 1`, then diff the gamepad folders.
- `.reference/ConsolePort`: commit ed3a6b3.
- `.reference/ElvUI`: tukui-org/ElvUI at the time of research.
- Installed addons used as references are in `Interface/AddOns`: BagPad, QuestieForeverGamepad, Questie, ForeverGamepadUI_Flightmaster.

### Status (2026-11-26)

- Branch `ui-rework`, made from main at v0.1.30 (e6c79ae). Not pushed.
- Uncommitted on it:
  - this plan;
  - the alpha checks in `.github/workflows/release.yml`;
  - the alpha / beta order in News.lua's version compare (tested on 9 version pairs);
  - `.reference/` in `.gitignore`.
- Committed and pushed: 85f57ec (plan, alpha pipeline, News.lua version order).
- Built, not committed: `Nav.lua`, the navigation core (in the toc after Repeat.lua), with `tests/nav.lua`. It holds:
  - the window registry with priority groups and the player's own order and skips;
  - the Back cycle both ways (`ns.NavCycle`), plus `ns.NavFocus`, `ns.NavOpened` and `ns.NavClosed`;
  - the key bindings of the focused window to `GamepadXIVNav<Key>` buttons (the D-pad repeats while held), bound again when another binding takes a key;
  - focus ends at combat start;
  - the screen-position cursor `ns.NavPick` and the footer hints `ns.NavHint`.
  - No window uses it yet, and Back isn't wired to it yet, so nothing changes in game.
- Committed: 3f22af9, the navigation core.
- Built after that, not committed yet:
  - **Nav.lua additions:** `clicks` keys bound straight to a real button (`ns.NavRebindClicks` after each move). While one of the addon's windows is open out of combat, Back is bound to `GamepadXIVNavBack`, which cycles them.
  - **Bags.lua, the bags window** (setting `bagWindow`, "Bags window (alpha)" under General > BAGS, default off):
    - one grid of all bags, built from Blizzard's `ContainerFrameItemButtonTemplate`, with one parent per bag carrying the bag ID;
    - {PAD1} is the slot's right click (use / equip / sell / bank / mail / trade), {PAD3} its left click (pick up / put down), {PAD4} sorts (`C_Container.SortBags`), L1 / R1 jump between bags, {PAD2} closes;
    - a gold cursor frame, the item tooltip beside the window, money and free slots in the header, a footer hint that names what {PAD1} does there.
    - The game's bag windows are moved under a hidden frame with `SetParent`.
    - Post-hooks on the game's Toggle / Open / Close bag functions are settled once per frame: a toggle flips the window, an open shows it, and a close hides it only if the game has no bag open.
    - It stands aside while BagPad is loaded and Forever's gamepad UI is on.
    - Turning it off needs a reload.
  - **Tests:** `tests/bags.lua` (all pass), and an Unreleased changelog line.
- Known gaps in the bags window:
  - no search, categories, detail panel or compare yet (BagPad's features);
  - no reagent bag check;
  - not movable;
  - Escape doesn't close it (adding it to `UISpecialFrames` would write a Blizzard table);
  - in combat the focus ends, so items are used by mouse or the bars.
  - With gamepad mode on, the game's hidden bag frame stays "open" after Circle closes ours. Check in game whether Forever's cursor tries to focus it.
- Next: test the bags window in game, then the bank (part of row 1), then mail. Phase 0 is still for the player to run.
- Build order agreed with the player: bags and bank, mail, loot, NPC interaction, map, popups, trade (milestone A), then the rest.

### Research data: the player's setup

- `WTF/Config.wtf`: `InputDeviceInterfaceStyle "1"`, `GamePadStickAxisButtons "1"`, `GamePadEmulateShift "none"`, `GamePadEmulateCtrl "none"`, `GamePadOverlapMouseMs "3000"`.
- Installed addons that touch the same windows: BagPad, Auctionator, Questie, QuestieForeverGamepad, ForeverGamepadUI_Flightmaster, Leatrix_Maps, Leatrix_Plus, OpenMap, MovableWindowsForever, TomTom, HandyNotes (plus MapNotes), RareScanner, Details.
