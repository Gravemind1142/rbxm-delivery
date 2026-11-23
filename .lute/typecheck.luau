--!strict
-- lute typecheck: type check rbxm-publish and these task scripts.
local task = require("./_lib/task")

local command = { task.lute, "check" }
for _, dir in { "publish/src", ".lute" } do
	for _, file in task.luauFiles(dir) do
		table.insert(command, file)
	end
end
task.must(command)
