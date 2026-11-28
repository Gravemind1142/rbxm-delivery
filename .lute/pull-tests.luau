--!strict
-- lute pull-tests [--cloud] [-t <name pattern>]: run rbxm-pull's Jest tests via studio-run.
--
-- Locally it needs Windows or macOS with Roblox Studio installed and logged in once.
-- With --cloud (or STUDIO_RUN_HOST=cloud) they run as an Open Cloud Luau Execution task, on
-- any OS. That needs ROBLOX_API_KEY, ROBLOX_UNIVERSE_ID and ROBLOX_PLACE_ID; see the README.
local fs = require("@std/fs")
local pathlib = require("@std/path")
local process = require("@std/process")
local task = require("./_lib/task")

local function usage(): never
	print("usage: lute pull-tests [--cloud] [-t <test name pattern>]")
	process.exit(2)
	error("unreachable")
end

local args = task.args(...)
local pattern: string? = nil
local cloud = process.env.STUDIO_RUN_HOST == "cloud"
local i = 1
while i <= #args do
	if args[i] == "--cloud" then
		cloud = true
	elseif args[i] == "-t" and args[i + 1] then
		pattern = args[i + 1]
		i += 1
	else
		usage()
	end
	i += 1
end

local universeId, placeId = process.env.ROBLOX_UNIVERSE_ID, process.env.ROBLOX_PLACE_ID
if cloud then
	local missing = {}
	for _, name in { "ROBLOX_API_KEY", "ROBLOX_UNIVERSE_ID", "ROBLOX_PLACE_ID" } do
		if (process.env[name] or "") == "" then
			table.insert(missing, name)
		end
	end
	if #missing > 0 then
		print(`pull-tests --cloud: set {table.concat(missing, ", ")}`)
		process.exit(2)
	end
end

if not fs.exists(pathlib.join(task.root, "pull", "DevPackages")) then
	task.must({ "wally", "install" }, "pull")
end

local buildDir = pathlib.join(task.root, "build")
if not fs.exists(buildDir) then
	fs.createDirectory(buildDir, { makeParents = true })
end
task.must({ "rojo", "build", "pull/test.project.json", "--output", "build/rbxm-pull-tests.rbxm" })

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
	"--input",
	"tests=build/rbxm-pull-tests.rbxm",
	"--input",
	"managed=build/pull-fixture/managed.rbxm",
	"--input",
	"manifest=build/pull-fixture/build.json",
}
if cloud then
	for _, arg in { "--cloud", "--universe-id", universeId :: string, "--place-id", placeId :: string } do
		table.insert(command, arg)
	end
end
if pattern then
	table.insert(command, "--arg")
	table.insert(command, `testNamePattern={pattern}`)
end
task.must(command)
