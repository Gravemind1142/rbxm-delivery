--!strict
-- lute build-apply-task: bundle rbxm-pull's Apply into build/apply-task.luau, the single-file
-- script that applies a build in an Open Cloud Luau Execution task (spec §7.3), and
-- build/Apply.luau, the Apply module alone.
local fs = require("@std/fs")
local pathlib = require("@std/path")
local bundle = require("./_lib/bundle")
local task = require("./_lib/task")

local dir = pathlib.join(task.root, "build")
if not fs.exists(dir) then
	fs.createDirectory(dir, { makeParents = true })
end
local version = bundle.version(task.root)
for file, entry in { ["apply-task.luau"] = "Task", ["Apply.luau"] = "Apply" } :: { [string]: bundle.Entry } do
	local source = bundle.build(task.root, entry, version)
	fs.writeStringToFile(pathlib.format(pathlib.join(dir, file)), source)
	print(`built build/{file} ({version}, {#source} bytes)`)
end
