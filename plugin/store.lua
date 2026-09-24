local wezterm = require("wezterm")
local platform = require("platform")

---@class Store
local store = {}

---Escape workspace name for use as a filename.
---Replaces characters illegal on Windows and the path separators.
---@param name string
---@return string
function store.escape_file_name(name)
	return (name:gsub('[\\/:%*%?"<>|%c]', "+"))
end

---Full JSON path for a workspace.
---@param dir string state directory with or without trailing sep
---@param workspace_name string
---@return string
function store.state_file_for(dir, workspace_name)
	dir = platform.ensure_trailing_sep(dir)
	return dir .. "wezterm_state_" .. store.escape_file_name(workspace_name) .. ".json"
end

---Save workspace data as JSON.
---@param data table
---@param file_path string
---@return boolean
function store.save(data, file_path)
	if not data then
		wezterm.log_info("store.save: no data")
		return false
	end
	local file = io.open(file_path, "w")
	if not file then
		wezterm.log_error("store.save: cannot open " .. file_path)
		return false
	end
	file:write(wezterm.json_encode(data))
	file:close()
	return true
end

---Load workspace data from JSON.
---@param file_path string
---@return table|nil
function store.load(file_path)
	local file = io.open(file_path, "r")
	if not file then
		return nil
	end
	local content = file:read("*a")
	file:close()
	local ok, data = pcall(wezterm.json_parse, content)
	if not ok or not data then
		wezterm.log_info("store.load: bad JSON in " .. file_path)
		return nil
	end
	return data
end

---Delete a state file.
---@param file_path string
---@return boolean
function store.delete(file_path)
	return os.remove(file_path) ~= nil
end

---Ensure the state directory exists.
---@param dir string
---@return boolean
function store.ensure_dir(dir)
	local ok, err = platform.mkdir_p(dir)
	if not ok then
		wezterm.log_error("store.ensure_dir failed: " .. (err or dir))
	end
	return ok
end

---@class WorkspaceEntry
---@field id string workspace name
---@field label string display label
---@field file string full JSON path
---@field last_modified number|nil

---List saved workspaces. Uses wezterm.read_dir only, no ls/grep fallback.
---@param dir string
---@return WorkspaceEntry[]
function store.list(dir)
	---@type WorkspaceEntry[]
	local choices = {}
	local ok, files = pcall(wezterm.read_dir, dir)
	if not ok or not files then
		return choices
	end
	for _, full_path in ipairs(files) do
		local filename = platform.basename(full_path)
		if filename:find("wezterm_state_", 1, true) and filename:sub(-5) == ".json" then
			local data = store.load(full_path)
			if data and data.name then
				local label = data.name
				if data.last_modified then
					label = label .. " - " .. os.date("%Y-%m-%d %H:%M", data.last_modified)
				end
				table.insert(choices, {
					id = data.name,
					label = label,
					file = full_path,
					last_modified = data.last_modified,
				})
			end
		end
	end
	table.sort(choices, function(a, b)
		return a.id < b.id
	end)
	return choices
end

return store
