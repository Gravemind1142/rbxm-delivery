--!strict
-- Where Studio loads local plugins from, for `lute install-plugin` / `lute uninstall-plugin`.
local pathlib = require("@std/path")
local process = require("@std/process")
local system = require("@std/system")

local plugins = {}

-- The file name rbxm-pull is installed under.
plugins.FILE = "RbxmPull.rbxm"

-- Studio's local plugins folder: %LOCALAPPDATA%\Roblox\Plugins on Windows,
-- ~/Documents/Roblox/Plugins on macOS. ROBLOX_PLUGINS_DIR overrides it.
function plugins.dir(): string
	local override = process.env.ROBLOX_PLUGINS_DIR
	if override and override ~= "" then
		return override
	elseif system.win32 then
		local localAppData = process.env.LOCALAPPDATA
		assert(localAppData, "LOCALAPPDATA isn't set")
		return pathlib.format(pathlib.join(localAppData, "Roblox", "Plugins"))
	elseif system.macos then
		local home = process.env.HOME
		assert(home, "HOME isn't set")
		return pathlib.format(pathlib.join(home, "Documents", "Roblox", "Plugins"))
	end
	error("Roblox Studio runs on Windows and macOS only; set ROBLOX_PLUGINS_DIR to install elsewhere", 0)
end

function plugins.path(): string
	return pathlib.format(pathlib.join(plugins.dir(), plugins.FILE))
end

return plugins
