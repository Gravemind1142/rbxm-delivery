--!strict
-- lute build-plugin: build rbxm-pull to build/RbxmPull.rbxm.
local fs = require("@std/fs")
local pathlib = require("@std/path")
local task = require("./_lib/task")

local dir = pathlib.join(task.root, "build")
if not fs.exists(dir) then
	fs.createDirectory(dir, { makeParents = true })
end
task.must({ "rojo", "build", "pull", "--output", "build/RbxmPull.rbxm" })
