-- Restore phase. Recreates layout from snapshot data with spawn_tab
-- plus directional splits. Extra windows spawn as new OS windows in the
-- same workspace. Shell panes land in their cwd, anything else gets its
-- saved process re-run with Enter.
local wezterm = require("wezterm")
local act = wezterm.action
local platform = require("platform")

local restore = {}

---Re-run a non-shell foreground process, shells are already running.
---@param pane Pane
---@param pane_data SnapshotPaneData
local function restore_process(pane, pane_data)
	local proc = pane_data.process
	if not proc or proc == "" then
		return
	end
	if platform.is_shell(proc) then
		return
	end
	wezterm.log_info("restore: re-running " .. proc)
	pane:send_text(proc .. "\r")
end

---Find pane data sitting right of the given one, the +1 is the cell border.
---@param pdata SnapshotPaneData
---@param tab_data SnapshotTabData
---@return SnapshotPaneData|nil, number|nil
local function find_horizontal_split(pdata, tab_data)
	for j, pane_data in ipairs(tab_data.panes) do
		if pane_data.top == pdata.top and pane_data.left == (pdata.left + pdata.width + 1) then
			return pane_data, j
		end
	end
	return nil, nil
end

---Find pane data sitting below the given one.
---@param pdata SnapshotPaneData
---@param tab_data SnapshotTabData
---@return SnapshotPaneData|nil, number|nil
local function find_vertical_split(pdata, tab_data)
	for j, pane_data in ipairs(tab_data.panes) do
		if pane_data.left == pdata.left and pane_data.top == (pdata.top + pdata.height + 1) then
			return pane_data, j
		end
	end
	return nil, nil
end

---Cell width of the tab, summing top-row panes.
---@param tab_data SnapshotTabData
---@return number
local function get_tab_width(tab_data)
	local width = 0
	for _, pane_data in ipairs(tab_data.panes) do
		if pane_data.top == 0 then
			width = width + pane_data.width
		end
	end
	return width
end

---Cell height of the tab, summing left-column panes.
---@param tab_data SnapshotTabData
---@return number
local function get_tab_height(tab_data)
	local height = 0
	for _, pane_data in ipairs(tab_data.panes) do
		if pane_data.left == 0 then
			height = height + pane_data.height
		end
	end
	return height
end

---Activate a pane, tolerating panes that vanish mid-restore.
---@param p Pane
local function activate_panel(p)
	wezterm.sleep_ms(200)
	pcall(function()
		p:activate()
	end)
	wezterm.sleep_ms(200)
end

---Split right to create hpane next to the active pane.
local function split_horizontally(tab, tab_width, ipane, panes, ipanes, hpane)
	local available = tab_width - ipane.left
	local cwd = platform.normalize_cwd(hpane.cwd)
	local args = {
		direction = "Right",
		size = 1 - ((hpane.left - ipane.left) / available),
	}
	if cwd then
		args.cwd = cwd
	end
	local new_pane = tab:active_pane():split(args)
	table.insert(ipanes, hpane)
	table.insert(panes, new_pane)
	restore_process(new_pane, hpane)
end

---Split downward to create vpane below the active pane.
local function split_vertically(tab, tab_height, ipane, panes, ipanes, vpane)
	local available = tab_height - ipane.top
	local cwd = platform.normalize_cwd(vpane.cwd)
	local args = {
		direction = "Bottom",
		size = 1 - ((vpane.top - ipane.top) / available),
	}
	if cwd then
		args.cwd = cwd
	end
	local new_pane = tab:active_pane():split(args)
	table.insert(ipanes, vpane)
	table.insert(panes, new_pane)
	restore_process(new_pane, vpane)
end

---Recreate every pane of a fresh tab from its saved data.
---@param tab MuxTab
---@param tab_data SnapshotTabData
local function restore_panes(tab, tab_data)
	local ipanes = { tab_data.panes[1] }
	local panes = { tab:active_pane() }
	local tab_width = get_tab_width(tab_data)
	local tab_height = get_tab_height(tab_data)

	for idx, p in ipairs(panes) do
		local ok, err = pcall(function()
			if idx == 1 then
				restore_process(p, tab_data.panes[1])
			end
			activate_panel(p)
			local hpane, hj = find_horizontal_split(ipanes[idx], tab_data)
			local vpane, vj = find_vertical_split(ipanes[idx], tab_data)
			if hpane ~= nil and (vj == nil or vj < hj) then
				split_horizontally(tab, tab_width, ipanes[idx], panes, ipanes, hpane)
				activate_panel(p)
				if vpane ~= nil then
					split_vertically(tab, tab_height, ipanes[idx], panes, ipanes, vpane)
					activate_panel(p)
				end
			elseif vpane ~= nil then
				split_vertically(tab, tab_height, ipanes[idx], panes, ipanes, vpane)
				activate_panel(p)
				if hpane ~= nil then
					split_horizontally(tab, tab_width, ipanes[idx], panes, ipanes, hpane)
				end
			end
		end)
		if not ok then
			wezterm.log_info("restore: pane " .. idx .. " failed: " .. tostring(err))
		end
	end
end

---Spawn one tab per saved tab. Pristine leftovers are closed by the
---caller after spawning, so failures never destroy the starting tab.
---@param window Window
---@param tab_data SnapshotTabData
---@return MuxTab|nil
local function restore_tab(window, tab_data)
	if not tab_data.panes or #tab_data.panes == 0 then
		return nil
	end
	local ok, new_tab = pcall(function()
		local cwd = platform.normalize_cwd(tab_data.panes[1].cwd)
		local tab
		if cwd then
			tab = window:mux_window():spawn_tab({ cwd = cwd })
		else
			tab = window:mux_window():spawn_tab()
		end
		if tab_data.title ~= "" then
			tab:set_title(tab_data.title)
		end
		tab:activate()
		restore_panes(tab, tab_data)
		return tab
	end)
	if ok then
		return new_tab
	end
	wezterm.log_info("restore: tab failed: " .. tostring(new_tab))
	return nil
end

---The window's single tab when it holds one shell pane and nothing else.
---Fresh switches and empty windows qualify, live work never does.
---@param window Window
---@return MuxTab|nil
local function pristine_tab(window)
	local ok, tab = pcall(function()
		local tabs = window:mux_window():tabs()
		if #tabs ~= 1 then
			return nil
		end
		if #(tabs[1]:panes()) ~= 1 then
			return nil
		end
		local proc = tabs[1]:panes()[1]:get_foreground_process_name() or ""
		if not platform.is_shell(proc) then
			return nil
		end
		return tabs[1]
	end)
	if ok then
		return tab
	end
	return nil
end

---Close a pristine leftover tab. Never throws, litters on failure.
---@param window Window
---@param old_tab MuxTab
local function close_tab(window, old_tab)
	local ok, err = pcall(function()
		old_tab:activate()
		window:perform_action(act.CloseCurrentTab({ confirm = false }), window:active_pane())
	end)
	if not ok then
		wezterm.log_info("restore: keeping leftover tab: " .. tostring(err))
	end
end

---The single tab when the window holds exactly one, no questions asked.
---Used for just-created workspaces whose panes may not report yet.
---@param window Window
---@return MuxTab|nil
local function first_tab(window)
	local ok, tab = pcall(function()
		local tabs = window:mux_window():tabs()
		if #tabs ~= 1 then
			return nil
		end
		return tabs[1]
	end)
	if ok then
		return tab
	end
	return nil
end

---Recreate all saved windows. Pristine starting tabs are replaced, live
---content is kept and the session lands alongside it.
---@param window Window
---@param workspace_name string
---@param data SnapshotData
---@param fresh boolean just-switched workspace, replace its single tab blindly
---@return boolean
function restore.run(window, workspace_name, data, fresh)
	if not data or not data.windows or #data.windows == 0 then
		return false
	end
	local created = 0
	local ok, err = pcall(function()
		for idx, win_data in ipairs(data.windows) do
			local target = window
			if idx > 1 then
				local _, _, w = wezterm.mux.spawn_window({ workspace = workspace_name })
				target = w:gui_window()
			end
			local active_tab = nil
			local old_tab = nil
			if fresh then
				old_tab = first_tab(target)
			else
				old_tab = pristine_tab(target)
			end
			local created_before = created
			for _, tab_data in ipairs(win_data.tabs) do
				local tab = restore_tab(target, tab_data)
				if tab then
					created = created + 1
					if tab_data.is_active then
						active_tab = tab
					end
				end
			end
			if active_tab then
				active_tab:activate()
			end
			if old_tab and created > created_before then
				close_tab(target, old_tab)
			end
		end
	end)
	if not ok then
		wezterm.log_info("restore failed: " .. tostring(err))
		return false
	end
	wezterm.log_info("restore: created " .. created .. " tabs")
	return created > 0
end

return restore
