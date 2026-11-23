--!strict
-- lute build-cli [--out <path>]: compile rbxm-publish into a standalone executable
-- (default build/rbxm-publish, plus .exe on Windows).
local fs = require("@std/fs")
local pathlib = require("@std/path")
local process = require("@std/process")
local task = require("./_lib/task")

local args = task.args(...)
local out = `build/rbxm-publish{task.exe}`
if args[1] == "--out" and args[2] then
	out = args[2]
elseif #args > 0 then
	print("usage: lute build-cli [--out <path>]")
	process.exit(2)
end

local dir = pathlib.dirname(pathlib.join(task.root, out))
if not fs.exists(dir) then
	fs.createDirectory(dir, { makeParents = true })
end
task.must({ task.lute, "compile", "publish/src/main.luau", "--output", out })
