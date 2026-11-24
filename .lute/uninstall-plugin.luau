--!strict
-- lute uninstall-plugin: remove rbxm-pull from Studio's local plugins folder. Restart Studio
-- to unload it. Places keep their settings (ServerStorage.RbxmPull) and synced code.
local fs = require("@std/fs")
local plugins = require("./_lib/plugins")

local target = plugins.path()
if fs.exists(target) then
	fs.remove(target)
	print(`Removed {target}. Restart Studio to unload it.`)
else
	print(`Not installed ({target} doesn't exist).`)
end
