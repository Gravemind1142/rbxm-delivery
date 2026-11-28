--!strict
-- lute tests [lute test options]: run rbxm-publish's tests (needs rojo on PATH). rbxm-pull's
-- tests run in the engine (Studio or Open Cloud); see `lute pull-tests`.
local task = require("./_lib/task")

local command = { task.lute, "test" }
for _, arg in task.args(...) do
	table.insert(command, arg)
end
table.insert(command, "publish/tests")
task.must(command)
