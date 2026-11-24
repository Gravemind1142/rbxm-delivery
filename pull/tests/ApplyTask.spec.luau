-- apply-task.luau, bundled as released, in the real engine: applies the real rbxm-publish
-- fixture build passed in by `lute pull-tests` (which also passes the bundle).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local describe, it, expect = JestGlobals.describe, JestGlobals.it, JestGlobals.expect
local afterAll = JestGlobals.afterAll

local Apply = require(ReplicatedStorage.RbxmPull.Apply)
local Helpers = require(ReplicatedStorage.Tests.Helpers)

-- selene: allow(global_usage)
local fixture = _G.RBXM_PULL_FIXTURE
-- selene: allow(global_usage)
local source = _G.RBXM_PULL_APPLY_TASK

-- Loads the bundle the way a task would run it: as a chunk, not a ModuleScript.
local function load(): (any) -> any
	local chunk = if pcall(loadstring, "") then loadstring(source, "=apply-task") else nil
	if chunk == nil then
		local module = Instance.new("ModuleScript")
		module.Source = source
		chunk = (debug :: any).loadmodule(module)
	end
	return (chunk :: any)()
end

describe("apply-task.luau", function()
	if fixture == nil or source == nil then
		it.skip("needs the fixture build and the bundle (run via `lute pull-tests`)", function() end)
		return
	end

	local manifest = Apply.Manifest.decode(fixture.manifest)
	local inputs = { ["managed.rbxm"] = fixture.rbxm, ["build.json"] = buffer.fromstring(fixture.manifest) }
	local logs = {}
	local function log(line: string)
		table.insert(logs, line)
	end

	afterAll(function()
		Helpers.cleanup(manifest.containers)
	end)

	it("is one file with no requires", function()
		expect(string.find(source, "require%(")).toBeNil()
	end)

	it("refuses a disallowed ref without changing anything", function()
		Helpers.cleanup(manifest.containers)
		local outcome = load()({ inputs = inputs, args = { allowedRef = "refs/heads/other" }, log = log })
		expect(outcome.ok).toBe(false)
		expect(outcome.rolledBack).toBe(true)
		expect(ServerStorage:FindFirstChild("RbxmPull")).toBeNil()
	end)

	it("applies the build and records it", function()
		local started = os.clock()
		local outcome = load()({ inputs = inputs, args = { allowedRef = manifest.ref }, log = log })
		print(`apply-task: {buffer.len(fixture.rbxm)} bytes in {string.format("%.2f", os.clock() - started)}s`)
		expect(outcome.ok).toBe(true)
		expect(outcome.summary).toBe(`applied {manifest.commit} ({#manifest.containers} containers)`)
		expect(outcome.record.commit).toBe(manifest.commit)
		expect(outcome.record.sha256).toBe(manifest.artifact.sha256)
		expect(outcome.record.containers).toEqual(manifest.containers)
		local marker = ServerStorage:FindFirstChild("RbxmPull") :: Configuration
		expect(marker:GetAttribute("Commit")).toBe(manifest.commit)
		expect(marker:GetAttribute("AppliedBy")).toBe(0)
		expect((string.find(logs[#logs], "apply-task: done in", 1, true))).never.toBeNil()
	end)
end)
