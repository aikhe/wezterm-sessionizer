-- Snapshot phase. Reads mux windows/tabs/panes for the active workspace
-- and returns plain data for store.save. Read-only against the terminal,
-- the only write is the JSON file done by the caller.
local wezterm = require("wezterm")

---@class SnapshotPaneData
---@field pane_id string
---@field index number
---@field is_active boolean
---@field is_zoomed boolean
---@field left number
---@field top number
---@field width number
---@field height number
---@field pixel_width number
---@field pixel_height number
---@field cwd string raw cwd URI, "" when unknown
---@field domain string
---@field process string foreground process name, "" when unknown
---@field pid number|nil foreground pid when available, used for Win32 lookup later

---@class SnapshotTabData
---@field tab_id string
---@field title string
---@field is_active boolean
---@field panes SnapshotPaneData[]

---@class SnapshotWindowData
---@field title string
---@field tabs SnapshotTabData[]

---@class SnapshotData
---@field name string
---@field last_modified number
---@field windows SnapshotWindowData[]

local snapshot = {}

---Collect one pane. Never throws, returns nil for panes that fail.
---@param pane_info table entry from panes_with_info
---@return SnapshotPaneData|nil
local function collect_pane(pane_info)
	local ok, data = pcall(function()
		local pane = pane_info.pane
		local process = pane:get_foreground_process_name() or ""
		local pid = nil
		local pok, pinfo = pcall(function()
			return pane:get_foreground_process_info()
		end)
		if pok and pinfo and pinfo.pid then
			pid = pinfo.pid
		end
		---@type SnapshotPaneData
		return {
			pane_id = tostring(pane:pane_id()),
			index = pane_info.index,
			is_active = pane_info.is_active,
			is_zoomed = pane_info.is_zoomed,
			left = pane_info.left,
			top = pane_info.top,
			width = pane_info.width,
			height = pane_info.height,
			pixel_width = pane_info.pixel_width,
			pixel_height = pane_info.pixel_height,
			cwd = tostring(pane:get_current_working_dir() or ""),
			domain = tostring(pane:get_domain_name() or ""),
			process = tostring(process or ""),
			pid = pid,
		}
	end)
	if ok then
		return data
	end
	wezterm.log_info("snapshot: skipping pane: " .. tostring(data))
	return nil
end

---Collect one tab. Tabs with zero readable panes are dropped by the caller.
---@param tab MuxTab
---@param is_active boolean
---@return SnapshotTabData|nil
local function collect_tab(tab, is_active)
	local ok, data = pcall(function()
		---@type SnapshotPaneData[]
		local panes = {}
		for _, pane_info in ipairs(tab:panes_with_info()) do
			local pane_data = collect_pane(pane_info)
			if pane_data then
				table.insert(panes, pane_data)
			end
		end
		---@type SnapshotTabData
		return {
			tab_id = tostring(tab:tab_id()),
			title = tostring(tab:get_title() or ""),
			is_active = is_active,
			panes = panes,
		}
	end)
	if ok then
		return data
	end
	wezterm.log_info("snapshot: skipping tab: " .. tostring(data))
	return nil
end

---Collect one mux window. Windows with zero readable tabs are dropped.
---@param mux_win MuxWindow
---@return SnapshotWindowData|nil
local function collect_window(mux_win)
	local ok, data = pcall(function()
		---@type SnapshotTabData[]
		local tabs = {}
		for _, t in ipairs(mux_win:tabs_with_info()) do
			local tab_data = collect_tab(t.tab, t.is_active)
			if tab_data and #tab_data.panes > 0 then
				table.insert(tabs, tab_data)
			end
		end
		---@type SnapshotWindowData
		return {
			title = tostring(mux_win:get_title() or ""),
			tabs = tabs,
		}
	end)
	if ok then
		return data
	end
	wezterm.log_info("snapshot: skipping window: " .. tostring(data))
	return nil
end

---Collect the active workspace. Skips windows without a GUI handle,
---so headless mux windows never break a snapshot.
---@param window Window
---@return SnapshotData
function snapshot.collect(window)
	local name = window:active_workspace()
	---@type SnapshotData
	local data = {
		name = name,
		last_modified = os.time(),
		windows = {},
	}
	for _, mux_win in ipairs(wezterm.mux.all_windows()) do
		if mux_win:get_workspace() == name and mux_win:gui_window() then
			local win_data = collect_window(mux_win)
			if win_data and #win_data.tabs > 0 then
				table.insert(data.windows, win_data)
			end
		end
	end
	return data
end

---One-line human summary for toasts and logs.
---@param data SnapshotData
---@return string
function snapshot.summarize(data)
	local tabs = 0
	for _, w in ipairs(data.windows) do
		tabs = tabs + #w.tabs
	end
	local nw = #data.windows
	local windows = nw == 1 and "window" or "windows"
	local tabword = tabs == 1 and "tab" or "tabs"
	return string.format("%d %s, %d %s", nw, windows, tabs, tabword)
end

return snapshot
