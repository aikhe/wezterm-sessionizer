-- Snapshot phase (next step).
-- Reads mux windows/tabs/panes for the active workspace and returns
-- plain data for store.save. No restore logic here.
local snapshot = {}

---Collect current workspace data. Not implemented yet.
---@param window any
---@return nil
function snapshot.collect(window)
	_ = window
	return nil
end

return snapshot
