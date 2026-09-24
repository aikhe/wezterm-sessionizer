-- Restore phase (after snapshot).
-- Recreates layout from saved data with spawn_tab + split.
local restore = {}

---Recreate workspace layout. Not implemented yet.
---@param window any
---@param data table
---@return boolean
function restore.run(window, data)
	_ = window
	_ = data
	return false
end

return restore
