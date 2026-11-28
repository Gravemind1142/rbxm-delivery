--!strict
-- lute tests [lute test options]: run rbxm-publish's tests (needs rojo on PATH) and the mock
-- tests of rbxm-pull's Apply and of the example patch bundled with darklua (pull/mock-tests).
-- rbxm-pull's engine tests need Studio or Open Cloud; see `lute pull-tests`.
local task = require("./_lib/task")

task.must({ task.lute, "build-patch-example" })

local command = { task.lute, "test" }
for _, arg in task.args(...) do
	table.insert(command, arg)
end
table.insert(command, "publish/tests")
table.insert(command, "pull/mock-tests")
task.must(command)
