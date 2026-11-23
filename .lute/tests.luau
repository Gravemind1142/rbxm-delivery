--!strict
-- lute tests [lute test options]: run rbxm-publish's tests (needs rojo on PATH).
-- rbxm-pull has no tests yet; see the README.
local task = require("./_lib/task")

local command = { task.lute, "test" }
for _, arg in task.args(...) do
	table.insert(command, arg)
end
table.insert(command, "publish/tests")
task.must(command)
