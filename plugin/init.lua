local wezterm = require("wezterm")

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

---@class WezTermSessionizer
local pub = {}

pub.version = "0.1.0-dev"

---@class SessionizerConfig
---@field save_state_dir string|nil absolute path, nil means platform default
pub.config = {
	save_state_dir = nil,
}

local state_dir = platform.default_state_dir()
local dir_ready = false

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

---Stub: restore phase comes after snapshot.
---@param window Window
function pub.restore_state(window)
	ensure_dir()
	window:toast_notification("wezterm-sessionizer", "restore not implemented yet (scaffold)", nil, 2000)
	wezterm.log_info("restore_state stub, dir=" .. state_dir)
end

---Stub: jumper phase comes after restore.
---@param window Window
---@param pane Pane
function pub.jump_to_dir(window, pane)
	ensure_dir()
	window:toast_notification("wezterm-sessionizer", "jump not implemented yet (scaffold)", nil, 2000)
	wezterm.log_info("jump_to_dir stub")
	_ = pane
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

return pub
