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

sessionizer.apply_to_config(config, {})

-- Show resolved state dir on startup. Proves platform.lua works.
wezterm.on("gui-startup", function()
	wezterm.log_info("sessionizer state dir: " .. sessionizer.get_state_dir())
end)

-- Test keys. Expect toast "not implemented yet (scaffold)".
config.keys = {
	{ key = "s", mods = "CTRL|SHIFT", action = act.EmitEvent("sessionizer.save") },
	{ key = "r", mods = "CTRL|SHIFT", action = act.EmitEvent("sessionizer.restore") },
	{ key = "j", mods = "CTRL|SHIFT", action = act.EmitEvent("sessionizer.jump") },
	{ key = "0", mods = "CTRL", action = act.ShowDebugOverlay },
}

return config
