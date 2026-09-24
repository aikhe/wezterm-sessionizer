-- Throwaway test config. Does not touch C:/Users/aikhe/.wezterm.lua.
-- Run it with:
-- & "C:\Program Files\WezTerm\wezterm.exe" --config-file "C:\Users\aikhe\Desktop\ike\local\wezterm-sessionizer\test-config.lua" start
local wezterm = require("wezterm")
local act = wezterm.action

-- Load local plugin by path so no install step is needed.
package.path = package.path
	.. ";C:/Users/aikhe/Desktop/ike/local/wezterm-sessionizer/plugin/?.lua"

local sessionizer = require("init")

local config = wezterm.config_builder()
config.default_prog = { "powershell.exe", "-NoLogo" }

sessionizer.apply_to_config(config, {
	search_roots = { "C:/Users/aikhe/Desktop/ike/local" },
	search_depth = 1,
})

-- Show resolved state dir on startup. Proves platform.lua works.
wezterm.on("gui-startup", function()
	wezterm.log_info("sessionizer state dir: " .. sessionizer.get_state_dir())
end)

-- Test keys: sessionizer plus personal bindings (mirrors ~/.wezterm.lua).
config.keys = {
	-- Sessionizer
	{ key = "s", mods = "CTRL|SHIFT", action = act.EmitEvent("sessionizer.save") },
	{ key = "r", mods = "CTRL|SHIFT", action = act.EmitEvent("sessionizer.restore") },
	{ key = "f", mods = "CTRL|SHIFT", action = act.EmitEvent("sessionizer.jump") },

	-- Personal
	{
		key = "E",
		mods = "CTRL|SHIFT|ALT",
		action = wezterm.action.EmitEvent("toggle-colorscheme"),
	},
	{
		key = "O",
		mods = "CTRL|ALT",
		action = wezterm.action_callback(function(window, _)
			local overrides = window:get_config_overrides() or {}
			if overrides.window_background_opacity == 1.0 then
				overrides.window_background_opacity = 0.8
			else
				overrides.window_background_opacity = 1.0
			end
			window:set_config_overrides(overrides)
		end),
	},
	{ key = "Tab", mods = "CTRL|ALT", action = act.ActivateTabRelative(1) },
	{
		key = "h",
		mods = "CTRL|ALT|SHIFT",
		action = act.SplitPane({ direction = "Right", size = { Percent = 50 } }),
	},
	{
		key = "v",
		mods = "CTRL|ALT|SHIFT",
		action = act.SplitPane({ direction = "Down", size = { Percent = 50 } }),
	},
	{ key = "h", mods = "CTRL|ALT", action = act.ActivatePaneDirection("Left") },
	{ key = "j", mods = "CTRL|ALT", action = act.ActivatePaneDirection("Down") },
	{ key = "k", mods = "CTRL|ALT", action = act.ActivatePaneDirection("Up") },
	{ key = "l", mods = "CTRL|ALT", action = act.ActivatePaneDirection("Right") },
	{ key = "h", mods = "CTRL|SHIFT", action = act.AdjustPaneSize({ "Left", 5 }) },
	{ key = "j", mods = "CTRL|SHIFT", action = act.AdjustPaneSize({ "Down", 5 }) },
	{ key = "i", mods = "CTRL|SHIFT", action = act.AdjustPaneSize({ "Up", 5 }) },
	{ key = "l", mods = "CTRL|SHIFT", action = act.AdjustPaneSize({ "Right", 5 }) },
	{ key = "o", mods = "CTRL", action = act.PaneSelect },
	{ key = "9", mods = "CTRL", action = act.PaneSelect },
	{ key = "q", mods = "CTRL|SHIFT", action = act.CloseCurrentPane({ confirm = true }) },
	{ key = "w", mods = "CTRL|SHIFT", action = act.CloseCurrentPane({ confirm = false }) },
	{ key = "0", mods = "CTRL", action = act.ShowDebugOverlay },
	{ key = "n", mods = "CTRL|ALT", action = act.SwitchWorkspaceRelative(1) },
	{ key = "p", mods = "CTRL|ALT", action = act.SwitchWorkspaceRelative(-1) },
	{
		key = "s",
		mods = "CTRL|ALT",
		action = act.ShowLauncherArgs({ flags = "FUZZY|WORKSPACES" }),
	},
	{
		key = "c",
		mods = "CTRL|ALT",
		action = wezterm.action_callback(function(window, pane)
			local workspace_name = "workspace_" .. os.time()
			window:perform_action(
				act.SwitchToWorkspace({
					name = workspace_name,
				}),
				pane
			)
		end),
	},
	{
		key = "r",
		mods = "CTRL|ALT|SHIFT",
		action = act.PromptInputLine({
			description = "Enter new tab title:",
			action = wezterm.action_callback(function(window, pane, line)
				if line then
					window:active_tab():set_title(line)
				end
			end),
		}),
	},
	{
		key = "r",
		mods = "CTRL|ALT",
		action = act.PromptInputLine({
			description = "Enter new workspace name:",
			action = wezterm.action_callback(function(window, pane, line)
				if line then
					wezterm.mux.rename_workspace(wezterm.mux.get_active_workspace(), line)
				end
			end),
		}),
	},
}

-- Tab activation (Ctrl+Alt+1-9), mirrors ~/.wezterm.lua.
for i = 1, 9 do
	table.insert(config.keys, {
		key = tostring(i),
		mods = "CTRL|ALT",
		action = act.ActivateTab(i - 1),
	})
end

-- Workspace activation (Ctrl+1-9), mirrors ~/.wezterm.lua.
for i = 1, 9 do
	table.insert(config.keys, {
		key = tostring(i),
		mods = "CTRL",
		action = wezterm.action_callback(function(window, pane)
			local workspaces = wezterm.mux.get_workspace_names()
			table.sort(workspaces)
			if #workspaces >= i then
				window:perform_action(
					act.SwitchToWorkspace({
						name = workspaces[i],
					}),
					pane
				)
			end
		end),
	})
end

wezterm.on("toggle-colorscheme", function(window)
	local overrides = window:get_config_overrides() or {}
	if overrides.color_scheme == "Zenburn" then
		overrides.color_scheme = "Cloud (terminal.sexy)"
	else
		overrides.color_scheme = "Zenburn"
	end
	window:set_config_overrides(overrides)
end)

return config
