# Rules for agents working on Gamepad XIV

## On-screen button hints follow the settings

Any hint that names a controller button must show the button the player's settings use now, not the default. Examples are the labels under the pet menu buttons and prompts like "Back: Roll on loot".

- If a setting can move an action to another button, the hint for that action reads the setting and updates when the setting changes. Call the hint's update function from `ns.Sync()`.
- If more than one button can trigger the action, show one of them in a fixed order: a single button first, then combinations, then the game's own default. `ClassMenuKeys` in `Input.lua` is the example.
- Draw button icons with `ns.ButtonMarkup`, so they match the controller in use. Refresh them when the controller changes, through `InputDeviceIconSetManager`.
- When you add a setting that changes what a button does, look for every hint, tooltip and doc line that names that button and update them too.

## Buttons are shown as icons that work with any controller

The addon has to work with any controller: PlayStation, Xbox, Switch or another gamepad. Never write UI text for one controller type.

- Show a controller button as an icon, never as typed text like "Circle", "B" or "L1". Use `ns.ButtonMarkup(key, fallback, size)`. It draws the art for the plugged-in controller, and the fallback is only used when no icon is available.
- Name buttons by their binding key: `PAD1`, `PAD2`, `PADLSHOULDER`, `PADRTRIGGER`, `PADLSTICK` and so on. Don't name them after one controller's labels.
- Labels and tips in the settings window write buttons as `{PADLSHOULDER}` tokens. `ButtonText` in `Config.lua` turns them into icons on screen and into plain names for search.
- Anything that draws button icons must redraw them when the controller changes, through `InputDeviceIconSetManager:RegisterActiveInputDeviceIconSetUpdatedCallback`.
- Text that can't show icons (chat output, docs, CurseForge) may use names. The docs use the PlayStation names because the player plays on a DualSense.

## Lists go round with the D-pad

Every list or menu of the addon's own that the D-pad moves through must wrap around.

- {PADDUP} on the first entry goes to the last, and {PADDDOWN} on the last entry goes to the first. Skip headers and other entries that can't be picked.
- Use `ns.StepWrap(index, delta, count)` from `Repeat.lua`. While the D-pad is held (`ns.RepeatOnHold`), it stops at the ends instead, so a held press doesn't loop.
- The mouse wheel scrolls and stops at the ends. It never wraps.
- When you add a new list, menu, dropdown or settings page, add the wrap in the same change.

## Both modes go through Mode.lua

The addon runs with Forever's gamepad UI on (the Forever adapter) and off (the Standalone adapter). See `Mode.lua` and `docs/UI-REPLACEMENT-PLAN.md`.

- Never check the gamepad UI, or reach for Forever's gamepad objects (`SmartNavigation`, `GamepadMode.FrameControlsManager`, `GamepadMainActionBarFrame`, `GamepadReticle`, the icon set), from a feature. Ask `ns.Mode()` and call its method, such as `ns.Mode():Navigator()`, `:CursorButton()`, `:BarButton(i)`, `:Reticle()` or `:IconAtlas(key)`.
- `ns.Mode().nativeNav` is true when Forever's cursor drives the game's windows. Features that only help that cursor do nothing without it.
- When a feature needs something the two modes do differently, add a method to both adapters in `Mode.lua`, with the same name and arguments, and a check in `tests/mode.lua`. That test fails when one adapter lacks a method the other has.
