--!strict
-- lute fmt [--check]: format all Luau with StyLua (--check only reports).
local task = require("./_lib/task")

local command = { "stylua" }
for _, arg in task.args(...) do
	table.insert(command, arg)
end
for _, dir in { ".lute", "publish", "pull" } do
	table.insert(command, dir)
end
task.must(command)
