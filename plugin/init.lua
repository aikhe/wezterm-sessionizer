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

---@class WezTermSessionizer
local pub = {}

pub.version = "0.1.0-dev"

---@class SessionizerConfig
---@field save_state_dir string|nil absolute path, nil means platform default
---@field status_label boolean show workspace name bottom left, off where tabline owns status
pub.config = {
	save_state_dir = nil,
	status_label = false,
}

local state_dir = platform.default_state_dir()
local dir_ready = false

---Workspace name awaiting post-switch restore. Set by the picker,
---consumed by the sessionizer.jump.restore event after the switch lands.
local pending_jump_restore = nil

---True when the pending jump creates a brand new workspace whose single
---tab is disposable. The jumper sets this, the restore event consumes it.
local pending_jump_fresh = false

---Origin workspace the jump left. Cleaned up when it is unsaved scratch.
---Set by the picker, consumed by the sessionizer.jump.restore event.
local pending_jump_origin = nil

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

---Name the session by its dir and save it as JSON. Resaving the same
---dir updates the same file. The default workspace is never saved.
---@param window Window
function pub.save_state(window)
	ensure_dir()
	local pane = window:active_pane()
	if pane then
		local cwd = pane:get_current_working_dir()
		local path = cwd and platform.normalize_cwd(tostring(cwd)) or nil
		if path then
			local base = platform.basename(path)
			local current = window:active_workspace()
			if base ~= "" and base ~= current then
				local ok, err = pcall(wezterm.mux.rename_workspace, current, base)
				if not ok then
					wezterm.log_info("save: keeping workspace name: " .. tostring(err))
				end
			end
		end
	end
	local data = snapshot.collect(window)
	if data.name == "default" then
		window:toast_notification("wezterm-sessionizer", "Cannot save the default workspace", nil, 3000)
		return
	end
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

---True when a workspace with this name already exists.
---@param name string
---@return boolean
local function workspace_exists(name)
	local ok, names = pcall(wezterm.mux.get_workspace_names)
	if not ok or not names then
		return true
	end
	for _, n in ipairs(names) do
		if n == name then
			return true
		end
	end
	return false
end

---Close the origin workspace when it is unsaved scratch: exactly one
---window holding one tab with one shell pane. Live work is never touched.
---@param origin string
local function cleanup_origin_workspace(origin)
	local ok, err = pcall(function()
		for _, mux_win in ipairs(wezterm.mux.all_windows()) do
			if mux_win:get_workspace() == origin then
				local tabs = mux_win:tabs()
				if #tabs ~= 1 then
					return
				end
				local panes = tabs[1]:panes()
				if #panes ~= 1 then
					return
				end
				local proc = panes[1]:get_foreground_process_name() or ""
				if not platform.is_shell(proc) then
					return
				end
				panes[1]:send_text("exit\r")
			end
		end
	end)
	if not ok then
		wezterm.log_info("jump cleanup skipped: " .. tostring(err))
	end
end

---Sentinel row at the bottom of the jump picker. Opens the delete
---picker instead of switching. A real workspace with this exact name
---would be shadowed, accepted as negligible.
local DELETE_SENTINEL = "__sessionizer_delete__"

---Delete one saved session file and toast the outcome.
---@param window Window
---@param id string workspace name
---@return boolean
local function delete_saved_session(window, id)
	ensure_dir()
	local path = store.state_file_for(state_dir, id)
	if store.delete(path) then
		window:toast_notification("wezterm-sessionizer", "Deleted " .. id, nil, 3000)
		wezterm.log_info("deleted " .. id .. " (" .. path .. ")")
		return true
	else
		window:toast_notification("wezterm-sessionizer", "Delete failed for " .. id, nil, 3000)
		return false
	end
end

---Second picker listing saved sessions for deletion. Confirm with y
---before removing. Reopens the jump picker when launched from there.
---@param window Window
---@param pane Pane
---@param reopen_jump boolean
local function open_delete_picker(window, pane, reopen_jump)
	ensure_dir()
	local entries = store.list(state_dir)
	if #entries == 0 then
		window:toast_notification("wezterm-sessionizer", "No saved sessions", nil, 3000)
		return
	end
	local choices = {}
	for _, entry in ipairs(entries) do
		table.insert(choices, { id = entry.id, label = entry.label })
	end
	window:perform_action(
		act.InputSelector({
			title = "Delete session",
			description = "Enter = delete, Esc = cancel, / = filter",
			fuzzy_description = "Filter sessions: ",
			choices = choices,
			fuzzy = true,
			action = wezterm.action_callback(function(inner_window, inner_pane, id)
				if not id then
					if reopen_jump then
						pub.jump_to_dir(inner_window, inner_pane or pane)
					end
					return
				end
				inner_window:perform_action(
					act.PromptInputLine({
						description = "Delete '" .. id .. "'? Type y to confirm: ",
						action = wezterm.action_callback(function(confirm_window, confirm_pane, line)
							if line and (line:lower() == "y" or line:lower() == "yes") then
								delete_saved_session(confirm_window, id)
							end
							if reopen_jump then
								pub.jump_to_dir(confirm_window, confirm_pane or pane)
							end
						end),
					}),
					inner_pane or pane
				)
			end),
		}),
		pane
	)
end

---Pick a saved session and switch to it, restoring its layout.
---Last row opens the delete picker.
---@param window Window
---@param pane Pane
function pub.jump_to_dir(window, pane)
	ensure_dir()
	local entries = store.list(state_dir)
	if #entries == 0 then
		window:toast_notification("wezterm-sessionizer", "No saved sessions", nil, 3000)
		return
	end
	local choices = {}
	for _, entry in ipairs(entries) do
		table.insert(choices, { id = entry.id, label = entry.label })
	end
	table.insert(choices, { id = DELETE_SENTINEL, label = "Delete a saved session..." })
	window:perform_action(
		act.InputSelector({
			title = "Jump to session",
			description = "Enter = switch, pick Delete to remove, Esc = cancel, / = filter",
			fuzzy_description = "Filter sessions: ",
			choices = choices,
			fuzzy = true,
			action = wezterm.action_callback(function(inner_window, inner_pane, id)
				if not id then
					return
				end
				if id == DELETE_SENTINEL then
					open_delete_picker(inner_window, inner_pane or pane, true)
					return
				end
				-- Switch first, restore in a later event. The switch
				-- only applies after this callback returns, so an
				-- inline restore would land in the origin workspace.
				pending_jump_restore = id
				pending_jump_fresh = not workspace_exists(id)
				local origin = inner_window:active_workspace()
				pending_jump_origin = nil
				if origin ~= id then
					local origin_data = store.load(store.state_file_for(state_dir, origin))
					if not (origin_data and origin_data.windows and #origin_data.windows > 0) then
						pending_jump_origin = origin
					end
				end
				inner_window:perform_action(act.SwitchToWorkspace({ name = id }), pane)
				inner_window:perform_action(act.EmitEvent("sessionizer.jump.restore"), pane)
			end),
		}),
		pane
	)
end

---Pick a saved session and delete its file, with y confirmation.
---@param window Window
---@param pane Pane
function pub.delete_session(window, pane)
	open_delete_picker(window, pane, false)
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
	pub.config.status_label = user_config.status_label == true
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
wezterm.on("sessionizer.delete", function(window, pane)
	pub.delete_session(window, pane)
end)
wezterm.log_info("sessionizer loaded, state dir: " .. state_dir)
wezterm.on("sessionizer.jump.restore", function(window)
	local name = pending_jump_restore
	local fresh = pending_jump_fresh
	local origin = pending_jump_origin
	pending_jump_restore = nil
	pending_jump_fresh = false
	pending_jump_origin = nil
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
	if restore.run(window, name, data, fresh) then
		window:toast_notification(
			"wezterm-sessionizer",
			"Restored " .. name .. " (" .. snapshot.summarize(data) .. ")",
			nil,
			4000
		)
	else
		window:toast_notification("wezterm-sessionizer", "Restore failed for " .. name, nil, 4000)
	end
	if origin and origin ~= name then
		cleanup_origin_workspace(origin)
	end
end)

-- Workspace name at the bottom left, only when enabled. Tabline owns
-- status in full setups, so this stays off unless opted in.
wezterm.on("update-status", function(window, _)
	if not pub.config.status_label then
		return
	end
	window:set_left_status(wezterm.format({
		{ Background = { Color = "#101010" } },
		{ Foreground = { Color = "#939393" } },
		{ Text = "  " .. window:active_workspace() .. "  " },
	}))
end)

return pub
