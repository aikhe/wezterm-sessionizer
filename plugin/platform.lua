local wezterm = require("wezterm")

---@class Platform
local platform = {}

-- Robust Windows detection. Reference checked only x86_64, missing ARM.
-- Matching "windows" covers x86_64-pc-windows-msvc and aarch64 variants.
local triple = (wezterm.target_triple or ""):lower()
platform.is_windows = triple:find("windows", 1, true) ~= nil

platform.separator = platform.is_windows and "\\" or "/"

platform.home = wezterm.home_dir

---Join path segments with the platform separator.
---@param ... string
---@return string
function platform.join(...)
	local parts = { ... }
	return table.concat(parts, platform.separator)
end

---Ensure path ends with separator.
---@param path string
---@return string
function platform.ensure_trailing_sep(path)
	if path:sub(-1) ~= "/" and path:sub(-1) ~= "\\" then
		return path .. platform.separator
	end
	return path
end

---Basename of a path, handles both / and \.
---@param path string
---@return string
function platform.basename(path)
	return path:match("([^/\\]+)$") or path
end

---Dirname of a path, handles both / and \. No pattern gsub on separator.
---@param path string
---@return string
function platform.dirname(path)
	return path:match("^(.*)[\\/][^\\/]*$") or "."
end

---Default state dir. Windows goes to %APPDATA%, Unix to ~/.local/share.
---@return string
function platform.default_state_dir()
	if platform.is_windows then
		local appdata = os.getenv("APPDATA")
			or (platform.home .. "\\AppData\\Roaming")
		return appdata .. "\\wezterm-sessionizer\\state\\"
	else
		return platform.home .. "/.local/share/wezterm-sessionizer/state/"
	end
end

---Create directory recursively. No cmd.exe mkdir, no ls fallback.
---@param path string
---@return boolean ok, string|nil err
function platform.mkdir_p(path)
	if platform.is_windows then
		local ok, success, _, stderr = pcall(
			wezterm.run_child_process,
			{ "powershell.exe", "-NoProfile", "-Command", 'New-Item -ItemType Directory -Force -Path "' .. path .. '" | Out-Null' }
		)
		if not ok or not success then
			return false, stderr or "mkdir failed"
		end
		return true, nil
	else
		local ok, success, _, stderr =
			pcall(wezterm.run_child_process, { "mkdir", "-p", path })
		if not ok or not success then
			return false, stderr or "mkdir failed"
		end
		return true, nil
	end
end

-- Shells we support day one on Windows, plus Unix basics for compat.
local known_shells = {
	["powershell.exe"] = true,
	["powershell"] = true,
	["pwsh.exe"] = true,
	["pwsh"] = true,
	["cmd.exe"] = true,
	["cmd"] = true,
	["sh"] = true,
	["bash"] = true,
	["zsh"] = true,
	["fish"] = true,
	["nu"] = true,
}

---Lowercased basename of a process string, or nil.
---@param proc string|nil
---@return string|nil
function platform.shell_name(proc)
	if not proc or proc == "" or proc == "nil" then
		return nil
	end
	local base = platform.basename(proc):lower()
	-- Trim whitespace and login-shell dash prefix.
	base = base:match("^%s*(.-)%s*$") or base
	base = base:gsub("^%-", "")
	return base
end

---True if the process looks like an interactive shell.
---@param proc string|nil
---@return boolean
function platform.is_shell(proc)
	local name = platform.shell_name(proc)
	return name ~= nil and known_shells[name] == true
end

---Percent-decode a URI path.
---@param s string
---@return string
local function url_decode(s)
	return (s:gsub("%%(%x%x)", function(hex)
		return string.char(tonumber(hex, 16))
	end))
end

---Turn a cwd URI into a native path for spawn calls.
---Handles file:///C:/dir/, file:///C:/dir and file://host/dir.
---Returns nil when the cwd is unknown so callers fall back to defaults.
---@param cwd_uri string|nil
---@return string|nil
function platform.normalize_cwd(cwd_uri)
	if not cwd_uri or cwd_uri == "" then
		return nil
	end
	local path = url_decode(cwd_uri)
	path = path:gsub("^file://[^/]*", "")
	if platform.is_windows then
		local drive = path:match("^/([A-Za-z]:.*)$")
		if drive then
			path = drive
		end
	end
	if #path > 1 then
		path = path:gsub("[/\\]+$", "")
	end
	if path == "" then
		return nil
	end
	return path
end

return platform
