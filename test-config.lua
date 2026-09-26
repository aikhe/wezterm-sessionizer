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

-- Look and feel mirrors ~/.wezterm.lua (tabline excluded for fast launches).
config.prefer_egl = true
config.term = "xterm-256color"

config.font = wezterm.font("JetBrainsMono Nerd Font")
config.font_size = 9
config.line_height = 1
config.use_cap_height_to_scale_fallback_fonts = true

config.default_cursor_style = "BlinkingBlock"

config.window_padding = {
	left = 8,
	right = 0,
	top = 8,
	bottom = 2,
}

config.window_decorations = "RESIZE"
config.window_background_opacity = 1.0

config.window_frame = {
	font = wezterm.font({ family = "JetBrainsMono Nerd Font", weight = "Regular" }),
	font_size = 9.0,
	active_titlebar_bg = "rgba(0, 0, 0, 80%)",
	inactive_titlebar_bg = "rgba(0, 0, 0, 80%)",

	border_left_width = "1.2cell",
	border_right_width = "0.34cell",
	border_bottom_height = "0.8cell",
	border_top_height = "0.4cell",
	border_left_color = "#101010",
	border_right_color = "#101010",
	border_bottom_color = "#101010",
	border_top_color = "#101010",
}

config.use_fancy_tab_bar = false
config.hide_tab_bar_if_only_one_tab = true
config.tab_bar_at_bottom = true
config.show_new_tab_button_in_tab_bar = false
config.show_close_tab_button_in_tabs = false

config.colors = {
	foreground = "#B7B7B7",
	background = "#101010",

	cursor_bg = "#ededed",
	cursor_fg = "#101010",
	cursor_border = "#ededed",

	selection_fg = "#b7b7b7",
	selection_bg = "#3d3d3d",

	scrollbar_thumb = "#222222",
	split = "#191919",

	ansi = {
		"#101010",
		"#FFBA9D",
		"#8ABE8A",
		"#ffffff",
		"#485571",
		"#6D89A7",
		"#708090",
		"#939393",
	},

	brights = {
		"#b7b7b7",
		"#C9D9D8",
		"#FFBA9D",
		"#6D89A7",
		"#485571",
		"#FF8080",
		"#8ABE8A",
		"#ffffff",
	},

	tab_bar = {
		background = "#101010",
		inactive_tab_edge = "#101010",

		active_tab = {
			fg_color = "#939393",
			bg_color = "#101010",
			intensity = "Normal",
			underline = "None",
			italic = false,
			strikethrough = false,
		},
		inactive_tab = {
			fg_color = "#525252",
			bg_color = "#101010",
			intensity = "Normal",
			underline = "None",
			italic = false,
			strikethrough = false,
		},

		inactive_tab_hover = {
			fg_color = "#939393",
			bg_color = "#101010",
		},

		new_tab = {
			fg_color = "#3d3d3d",
			bg_color = "#101010",
		},

		new_tab_hover = {
			fg_color = "#b7b7b7",
			bg_color = "#101010",
			intensity = "Bold",
			underline = "None",
			italic = false,
			strikethrough = false,
		},
	},
}

config.inactive_pane_hsb = {
	saturation = 1.0,
	brightness = 1.0,
}

sessionizer.apply_to_config(config, {
	-- No tabline here, so the plugin draws the workspace label itself.
	status_label = true,
})

-- Show resolved state dir on startup. Proves platform.lua works.
wezterm.on("gui-startup", function()
	wezterm.log_info("sessionizer state dir: " .. sessionizer.get_state_dir())
	wezterm.mux.spawn_window({
		width = 150,
		height = 40,
	})
end)

-- Test keys: sessionizer plus personal bindings (mirrors ~/.wezterm.lua).
config.keys = {
	-- Sessionizer
	{ key = "s", mods = "CTRL|SHIFT", action = act.EmitEvent("sessionizer.save") },
	{ key = "r", mods = "CTRL|SHIFT", action = act.EmitEvent("sessionizer.restore") },
	{ key = "f", mods = "CTRL|SHIFT", action = act.EmitEvent("sessionizer.jump") },
	{ key = "d", mods = "CTRL|SHIFT", action = act.EmitEvent("sessionizer.delete") },

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
			table.sort(workspaces, function(a, b)
				local al, bl = a:lower(), b:lower()
				if al == bl then
					return a < b
				end
				return al < bl
			end)
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

-- Format tab title to show custom titles, mirrors ~/.wezterm.lua.
wezterm.on("format-tab-title", function(tab, tabs, panes, config, hover, max_width)
	local title = tab.tab_title
	if not title or #title == 0 then
		title = tab.active_pane.title
	end

	return {
		{ Text = "" },
		{ Text = title },
		{ Text = "  " },
	}
end)

return config
