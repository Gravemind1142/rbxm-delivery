-- Runs rbxm-pull's Jest tests inside Studio. Invoked by `lute pull-tests`:
--   studio-run run pull/run-tests.luau --place build/rbxm-pull-tests.rbxl \
--     [--input managed=<managed.rbxm> --input manifest=<build.json>] [--arg testNamePattern=<p>]
-- Returns whether the tests passed, which becomes studio-run's exit code.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ctx = ...

-- A real rbxm-publish build, for tests that check a Rojo-built artifact round-trips.
-- Modules can't see `ctx`, so hand it over through _G.
if ctx.inputs.managed and ctx.inputs.manifest then
	_G.RBXM_PULL_FIXTURE = {
		rbxm = ctx.inputs.managed,
		manifest = buffer.tostring(ctx.inputs.manifest),
	}
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
