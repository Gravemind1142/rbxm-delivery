--!strict
-- lute pull-tests [-t <name pattern>]: run rbxm-pull's Jest tests in a hidden Studio via
-- studio-run. Needs Windows or macOS with Roblox Studio installed and logged in once.
local fs = require("@std/fs")
local pathlib = require("@std/path")
local process = require("@std/process")
local task = require("./_lib/task")

local args = task.args(...)
local pattern: string? = nil
if args[1] == "-t" and args[2] then
	pattern = args[2]
elseif #args > 0 then
	print("usage: lute pull-tests [-t <test name pattern>]")
	process.exit(2)
end

if not fs.exists(pathlib.join(task.root, "pull", "DevPackages")) then
	task.must({ "wally", "install" }, "pull")
end

local buildDir = pathlib.join(task.root, "build")
if not fs.exists(buildDir) then
	fs.createDirectory(buildDir, { makeParents = true })
end
task.must({ "rojo", "build", "pull/test.project.json", "--output", "build/rbxm-pull-tests.rbxl" })

-- A real rbxm-publish build for the round-trip tests (Fixture.spec).
task.must({
	task.lute,
	"publish/src/main.luau",
	"build",
	"--config",
	"publish/tests/fixtures/game/rbxm-publish.json",
	"--out",
	"build/pull-fixture",
	"--commit",
	string.rep("f", 40),
	"--ref",
	"refs/heads/main",
})

local command = {
	"studio-run",
	"run",
	"pull/run-tests.luau",
	"--place",
	"build/rbxm-pull-tests.rbxl",
	"--input",
	"managed=build/pull-fixture/managed.rbxm",
	"--input",
	"manifest=build/pull-fixture/build.json",
}
if pattern then
	table.insert(command, "--arg")
	table.insert(command, `testNamePattern={pattern}`)
end
task.must(command)
