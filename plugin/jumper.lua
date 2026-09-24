-- Jumper phase (after restore).
-- Fuzzy-find a directory and SwitchToWorkspace in it.
local jumper = {}

---List candidate directories. Not implemented yet.
---@param roots string[]
---@return string[]
function jumper.find_dirs(roots)
	_ = roots
	return {}
end

return jumper
