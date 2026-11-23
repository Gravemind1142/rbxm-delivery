--!strict
-- lute lint-plugin: lint rbxm-pull with Selene (Roblox std).
local task = require("./_lib/task")

task.must({ "selene", "--config", "pull/selene.toml", "pull/src" })
