--!strict
-- lute install-plugin: build rbxm-pull and copy it into Studio's local plugins folder,
-- replacing any copy already there. Restart Studio to load it.
local fs = require("@std/fs")
local pathlib = require("@std/path")
local plugins = require("./_lib/plugins")
local task = require("./_lib/task")

task.must({ task.lute, "build-plugin" })

local dir = plugins.dir()
if not fs.exists(dir) then
	-- Studio only creates it when the first local plugin is saved.
	fs.createDirectory(dir, { makeParents = true })
end
local target = plugins.path()
if fs.exists(target) then
	fs.remove(target)
end
fs.copy(pathlib.format(pathlib.join(task.root, "build", plugins.FILE)), target)
print(`Installed {target}. Restart Studio to load it.`)
