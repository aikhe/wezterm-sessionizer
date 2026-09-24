-- Jumper phase. Finds project dirs under configured roots and lets the
-- user fuzzy-pick one to switch to as a workspace. No external tools,
-- pure wezterm.read_dir with a depth cap. Depth 1 means the folders
-- directly inside each root, which is the normal projects layout.
local wezterm = require("wezterm")
local platform = require("platform")

local jumper = {}

---Hard cap so a misconfigured root cannot flood the picker.
local MAX_RESULTS = 500

---Dependency and build dirs never worth descending into on deeper scans.
local SKIP_DIRS = {
	["node_modules"] = true,
	[".git"] = true,
	["target"] = true,
	["dist"] = true,
	["build"] = true,
	["__pycache__"] = true,
	[".venv"] = true,
}

---Recursively collect directories up to max_depth levels below each root.
---Roots themselves are not included. Hidden entries are skipped.
---Separators are normalized to forward slashes for stable ids and labels.
---@param roots string[]
---@param max_depth number
---@return string[]
function jumper.find_dirs(roots, max_depth)
	---@type string[]
	local out = {}
	local seen = {}
	local function scan(dir, depth)
		if depth > max_depth or #out >= MAX_RESULTS then
			return
		end
		local ok, entries = pcall(wezterm.read_dir, dir)
		if not ok or not entries then
			return
		end
		for _, raw in ipairs(entries) do
			if #out >= MAX_RESULTS then
				return
			end
			local entry = raw:gsub("\\", "/")
			local base = platform.basename(entry)
			if base:sub(1, 1) ~= "." and not (depth >= 2 and SKIP_DIRS[base]) then
				local is_dir = pcall(wezterm.read_dir, entry)
				if is_dir and not seen[entry] then
					seen[entry] = true
					table.insert(out, entry)
					scan(entry, depth + 1)
				end
			end
		end
	end
	for _, root in ipairs(roots) do
		scan(root:gsub("\\", "/"), 1)
	end
	table.sort(out)
	return out
end

return jumper
