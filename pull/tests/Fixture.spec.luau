-- Applies a real rbxm-publish build of publish/tests/fixtures/game, passed in by
-- `lute pull-tests`, to check a Rojo-built .rbxm round-trips through DeserializeInstancesAsync.
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

	it("keeps RunContext", function()
		local server = ServerScriptService:FindFirstChild("Systems") :: Script
		expect(server.RunContext).toBe(Enum.RunContext.Legacy)
		local worker = server:FindFirstChild("Worker") :: Script
		expect(worker.ClassName).toBe("Script")
		expect(worker.RunContext).toBe(Enum.RunContext.Client)
		expect(worker.Source).toBe('print("client worker")\n')
	end)

	it("keeps attributes of each type", function()
		local libraries = ReplicatedStorage:FindFirstChild("Libraries") :: ModuleScript
		expect(libraries:GetAttribute("Label")).toBe("libraries")
		expect(libraries:GetAttribute("Count")).toBe(3)
		expect(libraries:GetAttribute("Enabled")).toBe(true)
		expect(libraries:GetAttribute("Offset")).toEqual(Vector3.new(1, 2.5, -3))
		expect(libraries:GetAttribute("Tint")).toEqual(Color3.new(1, 0.5, 0))

		local combat = (ReplicatedStorage:FindFirstChild("Systems") :: Instance):FindFirstChild("Combat") :: Instance
		expect(combat:GetAttribute("Damage")).toBe(12.5)
		local contract = ReplicatedStorage:FindFirstChild("Contract") :: Folder
		expect(contract:GetAttribute("Version")).toBe(2)
	end)

	it("keeps tags on containers and nested instances", function()
		local libraries = ReplicatedStorage:FindFirstChild("Libraries") :: Instance
		expect(libraries:HasTag("RbxmFixture")).toBe(true)
		expect(libraries:HasTag("Library")).toBe(true)
		local contract = ReplicatedStorage:FindFirstChild("Contract") :: Instance
		expect(contract:HasTag("Contract")).toBe(true)
		local combat = (ReplicatedStorage:FindFirstChild("Systems") :: Instance):FindFirstChild("Combat") :: Instance
		expect(combat:GetTags()).toEqual({ "RbxmFixture" })
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
