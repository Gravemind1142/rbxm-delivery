--!strict
-- lute build-patch-example: bundle the example patch script (examples/patch-task/patch.luau)
-- and the rbxm-apply package into build/patch.luau with darklua, the way a project builds its
-- own patch script for a Luau Execution task (spec §7.3). Fails if a require is left or the
-- bundle doesn't compile.
local fs = require("@std/fs")
local luau = require("@std/luau")
local pathlib = require("@std/path")
local process = require("@std/process")
local task = require("./_lib/task")

local dir = pathlib.join(task.root, "build")
if not fs.exists(dir) then
	fs.createDirectory(dir, { makeParents = true })
end
task.must({ "darklua", "process", "patch.luau", "../../build/patch.luau" }, "examples/patch-task")

local file = pathlib.format(pathlib.join(dir, "patch.luau"))
local source = fs.readFileToString(file)
for _, line in string.split(source, "\n") do
	local code = string.gsub(line, "%-%-.*$", "")
	if string.find(code, "require%s*%(") then
		print(`build-patch-example: the bundle still requires something: {line}`)
		process.exit(1)
	end
end
local ok, err = pcall(luau.compile, source)
if not ok then
	print(`build-patch-example: the bundle doesn't compile: {err}`)
	process.exit(1)
end
print(`built build/patch.luau ({#source} bytes)`)
