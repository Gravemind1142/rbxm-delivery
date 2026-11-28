--!strict
-- lute apply-e2e [--cloud]: apply a real build in a task with the released Apply module. Builds
-- the plugin model (which holds Apply) and the fixture build, verifies the build as a pipeline
-- would, and runs pull/apply-e2e.luau with studio-run, passing them as task inputs. It applies
-- the fixture build to the test place and never saves it.
--
-- Locally it needs Windows or macOS with Roblox Studio. With --cloud (or
-- STUDIO_RUN_HOST=cloud) it runs as an Open Cloud Luau Execution task, which needs
-- ROBLOX_API_KEY, ROBLOX_UNIVERSE_ID and ROBLOX_PLACE_ID; CI runs it on every run.
local process = require("@std/process")
local task = require("./_lib/task")

local cloud = process.env.STUDIO_RUN_HOST == "cloud"
for _, arg in task.args(...) do
	if arg == "--cloud" then
		cloud = true
	else
		print("usage: lute apply-e2e [--cloud]")
		process.exit(2)
	end
end

task.must({ task.lute, "build-plugin" })
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
-- The same check a pipeline runs before creating the task.
task.must({
	task.lute,
	"publish/src/main.luau",
	"verify",
	"--dir",
	"build/pull-fixture",
	"--allowed-ref",
	"refs/heads/main",
})

local command = {
	"studio-run",
	"run",
	"pull/apply-e2e.luau",
	"--input",
	"plugin=build/RbxmPull.rbxm",
	"--input",
	"managed=build/pull-fixture/managed.rbxm",
	"--input",
	"manifest=build/pull-fixture/build.json",
}
if cloud then
	for _, name in { "ROBLOX_API_KEY", "ROBLOX_UNIVERSE_ID", "ROBLOX_PLACE_ID" } do
		if (process.env[name] or "") == "" then
			print(`apply-e2e --cloud: set {name}`)
			process.exit(2)
		end
	end
	for _, arg in
		{
			"--cloud",
			"--universe-id",
			process.env.ROBLOX_UNIVERSE_ID :: string,
			"--place-id",
			process.env.ROBLOX_PLACE_ID :: string,
		}
	do
		table.insert(command, arg)
	end
end
task.must(command)
