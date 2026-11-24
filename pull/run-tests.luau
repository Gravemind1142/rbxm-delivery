-- Runs rbxm-pull's Jest tests, in Studio or as an Open Cloud task. Invoked by `lute pull-tests`:
--   studio-run run pull/run-tests.luau [--cloud --universe-id <id> --place-id <id>] \
--     --input tests=<rbxm-pull-tests.rbxm> \
--     [--input managed=<managed.rbxm> --input manifest=<build.json>] \
--     [--input applyTask=<apply-task.luau>] [--arg testNamePattern=<p>]
-- Returns whether the tests passed, which becomes studio-run's exit code.
--
-- The test tree (DevPackages, RbxmPull, Tests) comes in as a model rather than a place file,
-- because cloud tasks run on the published place and studio-run never uploads one.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SerializationService = game:GetService("SerializationService")

local ctx = ...

-- jest-roblox loads each test file with debug.loadmodule or, failing that, loadstring.
-- Cloud tasks have no debug.loadmodule, and loadstring only with LoadStringEnabled.
if not pcall((debug :: any).loadmodule, Instance.new("ModuleScript")) and not pcall(loadstring, "") then
	error(
		"jest-roblox needs loadstring here: enable ServerScriptService.LoadStringEnabled "
			.. "in the test place and publish it",
		0
	)
end

assert(ctx.inputs.tests, "pass the test model with --input tests=<rbxm-pull-tests.rbxm>")
for _, root in SerializationService:DeserializeInstancesAsync(ctx.inputs.tests) do
	for _, child in root:GetChildren() do
		local existing = ReplicatedStorage:FindFirstChild(child.Name)
		if existing then
			existing:Destroy()
		end
		child.Parent = ReplicatedStorage
	end
end

-- Modules can't see `ctx`, so hand what they need over through _G.
_G.RBXM_PULL_HOST = ctx.host
-- A real rbxm-publish build, for tests that check a Rojo-built artifact round-trips.
if ctx.inputs.managed and ctx.inputs.manifest then
	_G.RBXM_PULL_FIXTURE = {
		rbxm = ctx.inputs.managed,
		manifest = buffer.tostring(ctx.inputs.manifest),
	}
end
-- The bundled apply-task.luau, for ApplyTask.spec.
if ctx.inputs.applyTask then
	_G.RBXM_PULL_APPLY_TASK = buffer.tostring(ctx.inputs.applyTask)
end

local Jest = require(ReplicatedStorage.DevPackages.Jest)
local root = ReplicatedStorage.Tests

local options = { ci = true, verbose = true }
if ctx.args.testNamePattern then
	options.testNamePattern = ctx.args.testNamePattern
end

local status, result = Jest.runCLI(root, options, { root }):awaitStatus()
if status == "Rejected" then
	error(tostring(result))
end
return result.results.success
