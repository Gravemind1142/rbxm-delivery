-- Applies a real rbxm-publish build of publish/tests/fixtures/game, passed in by
-- `lute pull-tests` (spec open question §9.2: does a Rojo-built .rbxm round-trip?).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local describe, it, expect = JestGlobals.describe, JestGlobals.it, JestGlobals.expect
local afterAll = JestGlobals.afterAll

local Apply = require(ReplicatedStorage.RbxmPull.Apply)
local Helpers = require(ReplicatedStorage.Tests.Helpers)

-- selene: allow(global_usage)
local fixture = _G.RBXM_PULL_FIXTURE

describe("a real rbxm-publish build", function()
	if fixture == nil then
		it.skip("needs the fixture build (run via `lute pull-tests`)", function() end)
		return
	end

	local manifest = Apply.Manifest.decode(fixture.manifest)

	afterAll(function()
		Helpers.cleanup(manifest.containers)
	end)

	it("verifies and applies", function()
		local result = Apply.apply(game, fixture.rbxm, manifest)
		expect(#result.added + #result.replaced).toBe(4)
	end)

	it("keeps script classes, sources and RunContext-relevant types", function()
		local shared = ReplicatedStorage:FindFirstChild("Systems") :: ModuleScript
		expect(shared.ClassName).toBe("ModuleScript")
		expect(shared.Source).toBe("return {}\n")
		local combat = shared:FindFirstChild("Combat") :: ModuleScript
		expect(combat.Source).toBe('return { name = "Combat" }\n')

		local server = ServerScriptService:FindFirstChild("Systems") :: Script
		expect(server.ClassName).toBe("Script")
		expect(server.Source).toBe('print("server systems")\n')
	end)

	it("includes the generated BuildInfo and not the placeholder", function()
		local contract = ReplicatedStorage:FindFirstChild("Contract") :: Folder
		local buildInfos = {}
		for _, child in contract:GetChildren() do
			if child.Name == "BuildInfo" then
				table.insert(buildInfos, child)
			end
		end
		expect(#buildInfos).toBe(1)
		local source = (buildInfos[1] :: ModuleScript).Source
		expect((string.find(source, manifest.commit, 1, true))).never.toBeNil()
		expect(contract:FindFirstChild("Types")).never.toBeNil()
	end)

	it("names containers by leaf, not by path", function()
		expect(ReplicatedStorage:FindFirstChild("ReplicatedStorage/Systems")).toBeNil()
		expect(ReplicatedStorage:FindFirstChild("Libraries")).never.toBeNil()
	end)
end)
