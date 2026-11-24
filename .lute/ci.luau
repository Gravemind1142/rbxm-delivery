--!strict
-- lute ci: everything CI checks, in order, stopping at the first failure. On Windows and
-- macOS it also runs rbxm-pull's tests in Studio (lute pull-tests); Studio can't run on
-- Linux, so CI's ubuntu runner skips them.
local system = require("@std/system")
local task = require("./_lib/task")

local cli = `build/rbxm-publish{task.exe}`
local steps: { { string } } = {
	{ task.lute, "fmt", "--check" },
	{ task.lute, "lint-plugin" },
	{ task.lute, "typecheck" },
	{ task.lute, "tests" },
	{ task.lute, "build-cli" },
	-- Smoke test the compiled binary against the fixture project.
	{
		cli,
		"build",
		"--config",
		"publish/tests/fixtures/game/rbxm-publish.json",
		"--out",
		"build/smoke",
		"--commit",
		string.rep("0", 40),
		"--ref",
		"refs/heads/main",
	},
	{ task.lute, "build-plugin" },
	{ task.lute, "build-apply-task" },
}
if system.win32 or system.macos then
	table.insert(steps, { task.lute, "pull-tests" })
else
	print("ci: skipping rbxm-pull's Studio tests (needs Windows or macOS)")
end
for _, step in steps do
	task.must(step)
end
print("ci: all checks passed")
