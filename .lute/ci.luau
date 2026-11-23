--!strict
-- lute ci: everything CI checks, in order, stopping at the first failure.
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
}
for _, step in steps do
	task.must(step)
end
print("ci: all checks passed")
