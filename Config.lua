local _, ns = ...

local category

local function AddSetting(key, label, varType, default, onChange)
	local function GetValue()
		return ns.db[key]
	end
	local function SetValue(value)
		ns.db[key] = value
		onChange()
	end
	return Settings.RegisterProxySetting(category, "GAMEPADXIV_" .. key:upper(), varType, label, default, GetValue, SetValue)
end

local function AddCheckbox(key, label, default, tooltip, onChange)
	local setting = AddSetting(key, label, Settings.VarType.Boolean, default, onChange)
	Settings.CreateCheckbox(category, setting, tooltip)
end

local function AddSlider(key, label, default, min, max, step, tooltip, onChange)
	local setting = AddSetting(key, label, Settings.VarType.Number, default, onChange)
	local options = Settings.CreateSliderOptions(min, max, step)
	options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
		return RoundToSignificantDigits(value, 3)
	end)
	Settings.CreateSlider(category, setting, options, tooltip)
end

local function GetSideOptions()
	local container = Settings.CreateControlTextContainer()
	for side = 1, ns.NUM_SETS * 2 do
		local set, letter = ns.DescribeSide(side)
		container:Add(side, "Set " .. set .. " " .. (letter == "L" and "left" or "right"))
	end
	return container:GetData()
end

local function AddSideDropdown(key, label, default, tooltip)
	local setting = AddSetting(key, label, Settings.VarType.Number, default, ns.Sync)
	Settings.CreateDropdown(category, setting, GetSideOptions, tooltip)
end

function ns.CreateConfig()
	local layout
	category, layout = Settings.RegisterVerticalLayoutCategory("Gamepad XIV")
	local defaults = ns.DEFAULTS

	AddCheckbox("enabled", "Enable layout", defaults.enabled,
		"Replaces Forever's bar with the cross hotbars. Only takes effect in Gamepad UI.", ns.Sync)

	-- Closing the settings from addon code would taint Forever's gamepad focus, so they stay open.
	local function AfterSettings(action)
		return function()
			action()
			ns.Print("Close the settings to see the crossbar.")
		end
	end

	layout:AddInitializer(CreateSettingsButtonInitializer("Slots", "Edit crossbar", AfterSettings(function()
		ns.ToggleEditor()
	end), "Shows any layer on the crossbar so you can drag spells onto it.", false))

	layout:AddInitializer(CreateSettingsButtonInitializer("Position", "Move bars", AfterSettings(function()
		ns.ToggleMove()
	end), "Drag each bar anywhere on the screen.", false))

	AddCheckbox("minimapShown", "Show minimap icon", defaults.minimapShown,
		"Left click: settings. Right click: menu. Drag: move the icon.", function() ns.UpdateMinimapButton() end)

	AddCheckbox("autoFace", "Face target (turn toward the enemy)", defaults.autoFace,
		"Experimental. Locks the camera on the enemy target, so the character turns to it when casting. WoW has no way to turn only the character.", function()
			ns.AllowExperimentalCamera()
			ns.Sync()
		end)

	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Crossbar"))
	AddSlider("scale", "Scale", defaults.scale, 0.5, 1.5, 0.05, nil, ns.Sync)
	AddSlider("x", "Horizontal position", defaults.x, -1500, 1500, 10, nil, ns.Sync)
	AddSlider("y", "Vertical position", defaults.y, -200, 1200, 10, nil, ns.Sync)
	AddSlider("clusterPadding", "Padding between button groups", defaults.clusterPadding, 0, 80, 2,
		"Gap between the D-pad group and the face button group of each bar.", ns.Sync)
	AddSlider("dimAlpha", "Inactive side opacity", defaults.dimAlpha, 0, 1, 0.05,
		"How visible the other bars are while one is selected.", ns.Sync)
	AddCheckbox("showKeyLabels", "Show controller buttons on slots", defaults.showKeyLabels, nil, ns.RefreshVisuals)
	AddSlider("keyIconSize", "Controller button size", defaults.keyIconSize, 16, 60, 2, nil, ns.RefreshVisuals)
	AddCheckbox("rangeIndicator", "Show out of range abilities in red", defaults.rangeIndicator,
		"Tints an ability red while your target is out of its range.", function() end)
	AddCheckbox("showInteractPrompt", "Show interact prompt", defaults.showInteractPrompt,
		"Over the character: the button, the action's icon and the name of what you can loot, talk to, skin, mine or gather.", function() end)
	AddCheckbox("showSetLabels", "Show set labels", defaults.showSetLabels, nil, ns.RefreshVisuals)

	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Layers"))
	AddSideDropdown("sideWL", "Double tap L2 shows", defaults.sideWL)
	AddSideDropdown("sideWR", "Double tap R2 shows", defaults.sideWR)
	AddSideDropdown("sideLR", "L2 then R2 shows", defaults.sideLR)
	AddSideDropdown("sideRL", "R2 then L2 shows", defaults.sideRL)

	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Forms and stances"))
	AddCheckbox("formsChangeBar", "Forms change the bottom row", defaults.formsChangeBar,
		"Each form or stance keeps its own set. R1 + a button changes the set of the current form.", ns.Sync)
	for form = 1, ns.NUM_FORMS do
		local key = "formSet" .. form
		local setting = AddSetting(key, "Form " .. form .. " uses", Settings.VarType.Number, defaults[key], ns.Sync)
		Settings.CreateDropdown(category, setting, function()
			local container = Settings.CreateControlTextContainer()
			for set = 1, ns.NUM_SETS do
				container:Add(set, "Set " .. set)
			end
			return container:GetData()
		end)
	end

	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Input"))
	do
		local setting = AddSetting("triggerMode", "L2 / R2 activation", Settings.VarType.String, defaults.triggerMode, ns.Sync)
		Settings.CreateDropdown(category, setting, function()
			local container = Settings.CreateControlTextContainer()
			container:Add("hold", "Hold")
			container:Add("toggle", "Toggle")
			container:Add("mixed", "Mixed (tap toggles, hold holds)")
			return container:GetData()
		end, "Hold: selected while the trigger is held. Toggle: stays selected until pressed again, also after a double tap.")
	end
	AddCheckbox("wxhbFourSlots", "WXHB swaps face buttons only", defaults.wxhbFourSlots,
		"The D-pad keeps the bottom row while the double tap row is selected.", ns.Sync)
	AddSlider("doubleTapTicks", "Double tap window", defaults.doubleTapTicks, 2, 4, 1,
		"In 0.2 second steps: 2 is about 0.2-0.4 seconds, and it can be shorter in combat.", ns.Sync)
	AddCheckbox("holdToWalk", "Hold B to walk", defaults.holdToWalk, nil, ns.Sync)
	AddCheckbox("priorityBindings", "Priority bindings", defaults.priorityBindings,
		"Turn on only if R2 does not change the bar. Then check that menus can still be navigated.", ns.Sync)

	Settings.RegisterAddOnCategory(category)
end

function ns.OpenConfig()
	if InCombatLockdown() then
		ns.Print("Settings are not available in combat.")
		return
	end
	if ns.editing then
		ns.ToggleEditor()
	end
	-- Goes through the client, which keeps the panel's own code free of this addon's taint.
	Settings.OpenToCategory(category:GetID())
end
