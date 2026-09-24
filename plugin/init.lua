local wezterm = require("wezterm")
local act = wezterm.action

-- Make sibling modules (platform, store, ...) requireable both as a
-- wezterm plugin and during local dev via file require. Uses "/" in
-- package.path so no separator escaping bugs on Windows.
local function enable_sub_modules()
	local dirs = {}

	local ok, list = pcall(function()
		return wezterm.plugin.list()
	end)
	if ok and list and list[1] and list[1].plugin_dir then
		local base = list[1].plugin_dir:match("^(.*)[\\/][^\\/]*$")
		if base then
			table.insert(dirs, base .. "/plugin")
		end
	end

	-- Local dev (file require) is covered by the test config setting
	-- package.path explicitly. WezTerm sandbox has no debug library,
	-- so nothing else to discover here.

	for _, d in ipairs(dirs) do
		if not package.path:find(d, 1, true) then
			package.path = package.path .. ";" .. d .. "/?.lua"
		end
	end
end
enable_sub_modules()

local platform = require("platform")
local store = require("store")
local snapshot = require("snapshot")
local restore = require("restore")
local jumper = require("jumper")

---@class WezTermSessionizer
local pub = {}

pub.version = "0.1.0-dev"

---@class SessionizerConfig
---@field save_state_dir string|nil absolute path, nil means platform default
---@field search_roots string[]|nil directories the jumper scans, nil means unconfigured
---@field search_depth number max scan depth below each root
pub.config = {
	save_state_dir = nil,
	search_roots = nil,
	search_depth = 1,
}

local state_dir = platform.default_state_dir()
local dir_ready = false

---Workspace name awaiting post-switch restore. Set by the jumper,
---consumed by the sessionizer.jump.restore event after the switch lands.
local pending_jump_restore = nil

---@return string
function pub.get_state_dir()
	return state_dir
end

local function ensure_dir()
	if dir_ready then
		return
	end
	dir_ready = store.ensure_dir(state_dir)
end

---Collect the active workspace and save it as JSON. Read-only against
---the terminal, the only write is the state file.
---@param window Window
function pub.save_state(window)
	ensure_dir()
	local data = snapshot.collect(window)
	if #data.windows == 0 then
		window:toast_notification("wezterm-sessionizer", "Nothing to save: no GUI windows", nil, 3000)
		return
	end
	local path = store.state_file_for(state_dir, data.name)
	if store.save(data, path) then
		local summary = snapshot.summarize(data)
		window:toast_notification("wezterm-sessionizer", "Saved " .. data.name .. " (" .. summary .. ")", nil, 4000)
		wezterm.log_info("saved " .. data.name .. " to " .. path .. " (" .. summary .. ")")
	else
		window:toast_notification("wezterm-sessionizer", "Save failed for " .. data.name, nil, 4000)
	end
end

---Load the saved state for the active workspace and recreate it.
---Saved tabs spawn as new tabs, the tab you start from is left alone.
---@param window Window
function pub.restore_state(window)
	ensure_dir()
	local name = window:active_workspace()
	local data = store.load(store.state_file_for(state_dir, name))
	if not data or not data.windows or #data.windows == 0 then
		window:toast_notification("wezterm-sessionizer", "No saved state for " .. name, nil, 4000)
		return
	end
	if restore.run(window, name, data) then
		local summary = snapshot.summarize(data)
		window:toast_notification("wezterm-sessionizer", "Restored " .. name .. " (" .. summary .. ")", nil, 4000)
		wezterm.log_info("restored " .. name .. " (" .. summary .. ")")
	else
		window:toast_notification("wezterm-sessionizer", "Restore failed for " .. name, nil, 4000)
	end
end

---Fuzzy-find a project dir and switch to it as a workspace.
---When the workspace has saved state, offers a restore via toast.
---@param window Window
---@param pane Pane
function pub.jump_to_dir(window, pane)
	ensure_dir()
	local roots = pub.config.search_roots
	if not roots or #roots == 0 then
		window:toast_notification("wezterm-sessionizer", "No search roots configured", nil, 3000)
		return
	end
	local dirs = jumper.find_dirs(roots, pub.config.search_depth or 3)
	if #dirs == 0 then
		window:toast_notification("wezterm-sessionizer", "No directories found", nil, 3000)
		return
	end
	local choices = {}
	for _, dir in ipairs(dirs) do
		table.insert(choices, { id = dir, label = platform.basename(dir) .. "  " .. dir })
	end
	window:perform_action(
		act.InputSelector({
			title = "Jump to directory",
			description = "Enter = switch workspace, Esc = cancel, / = filter",
			fuzzy_description = "Filter directories: ",
			choices = choices,
			fuzzy = true,
			action = wezterm.action_callback(function(inner_window, _, id)
				if not id then
					return
				end
				local name = platform.basename(id)
				local data = store.load(store.state_file_for(state_dir, name))
				if data and data.windows and #data.windows > 0 then
					-- Switch first, restore in a later event. The switch
					-- only applies after this callback returns, so an
					-- inline restore would land in the origin workspace.
					pending_jump_restore = name
					inner_window:perform_action(act.SwitchToWorkspace({ name = name }), pane)
					inner_window:perform_action(act.EmitEvent("sessionizer.jump.restore"), pane)
					return
				end
				inner_window:perform_action(
					act.SwitchToWorkspace({ name = name, spawn = { cwd = id } }),
					pane
				)
			end),
		}),
		pane
	)
end

---Wire the plugin into wezterm config. Adds no keys by default in scaffold
---so your existing config keeps working. Pass explicit keys yourself.
---@param config Config wezterm config
---@param user_config table|nil
-- config is unused until the keybindings phase lands.
---@diagnostic disable-next-line: unused-local
function pub.apply_to_config(config, user_config)
	user_config = user_config or {}

	if type(user_config.save_state_dir) == "string" then
		state_dir = platform.ensure_trailing_sep(user_config.save_state_dir)
	else
		state_dir = platform.default_state_dir()
	end
	pub.config.save_state_dir = state_dir
	dir_ready = false

	if type(user_config.search_roots) == "table" then
		pub.config.search_roots = user_config.search_roots
	else
		pub.config.search_roots = nil
	end
	local depth = tonumber(user_config.search_depth) or 1
	if depth < 1 then
		depth = 1
	elseif depth > 8 then
		depth = 8
	end
	pub.config.search_depth = depth
end

wezterm.on("sessionizer.save", function(window)
	pub.save_state(window)
end)
wezterm.on("sessionizer.restore", function(window)
	pub.restore_state(window)
end)
wezterm.on("sessionizer.jump", function(window, pane)
	pub.jump_to_dir(window, pane)
end)
wezterm.on("sessionizer.jump.restore", function(window)
	local name = pending_jump_restore
	pending_jump_restore = nil
	if not name then
		return
	end
	if window:active_workspace() ~= name then
		wezterm.log_info("jump restore skipped, workspace moved on")
		return
	end
	ensure_dir()
	local data = store.load(store.state_file_for(state_dir, name))
	if not data or not data.windows or #data.windows == 0 then
		return
	end
	if restore.run(window, name, data) then
		window:toast_notification(
			"wezterm-sessionizer",
			"Restored " .. name .. " (" .. snapshot.summarize(data) .. ")",
			nil,
			4000
		)
	else
		window:toast_notification("wezterm-sessionizer", "Restore failed for " .. name, nil, 4000)
	end
end)

return pub
