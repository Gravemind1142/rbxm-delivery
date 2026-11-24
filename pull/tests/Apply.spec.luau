local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local describe, it, expect = JestGlobals.describe, JestGlobals.it, JestGlobals.expect
local beforeEach, afterEach = JestGlobals.beforeEach, JestGlobals.afterEach

local Apply = require(ReplicatedStorage.RbxmPull.Apply)
local Helpers = require(ReplicatedStorage.Tests.Helpers)
local Paths = require(ReplicatedStorage.RbxmPull.Apply.Paths)

-- Two containers sharing the leaf name "Systems", one below a nested parent.
local SHARED = "ReplicatedStorage/TestShared/Systems"
local SERVER = "ServerScriptService/Systems"
local DROPPED = "ServerScriptService/Legacy"
local PATHS = { SHARED, SERVER, DROPPED }

local sharedParent: Folder

local function buildBoth(commit: string?, sharedSource: string?)
	return Helpers.build({
		{
			path = SHARED,
			fill = function(folder)
				Helpers.module(folder, "Combat", sharedSource or "return 'combat'")
			end,
		},
		{
			path = SERVER,
			fill = function(folder)
				local script = Instance.new("Script")
				script.Name = "Main"
				script.Source = "print('server')"
				script.Parent = folder
			end,
		},
	}, commit)
end

local function marker(): Configuration
	return ServerStorage:FindFirstChild("RbxmPull") :: Configuration
end

beforeEach(function()
	Helpers.cleanup(PATHS)
	sharedParent = Helpers.folder(ReplicatedStorage, "TestShared")
end)

afterEach(function()
	Helpers.cleanup(PATHS)
end)

describe("Apply.apply", function()
	it("inserts each container at its path, named by its leaf", function()
		local rbxm, manifest = buildBoth()
		local result = Apply.apply(game, rbxm, manifest, { appliedBy = 42 })

		local shared = sharedParent:FindFirstChild("Systems")
		expect(shared).never.toBeNil()
		expect((shared :: any).Combat.Source).toBe("return 'combat'")
		expect((ServerScriptService:FindFirstChild("Systems") :: any).Main.Source).toBe("print('server')")
		expect(result.added).toEqual({ SHARED, SERVER })
		expect(result.replaced).toEqual({})
		expect(result.removed).toEqual({})
	end)

	it("writes the marker", function()
		local rbxm, manifest = buildBoth()
		Apply.apply(game, rbxm, manifest, { appliedBy = 42 })

		local state = Apply.Marker.read(marker())
		expect(state.commit).toBe(Helpers.COMMIT)
		expect(state.schemaVersion).toBe(1)
		expect(state.appliedBy).toBe(42)
		expect(state.protocol).toBe(Apply.PROTOCOL)
		expect(state.containers).toEqual({ SHARED, SERVER })
		expect(string.match(state.appliedAt :: string, "^%d+%-%d+%-%d+T")).never.toBeNil()
	end)

	it("replaces every instance at a path, leaving siblings alone", function()
		local stale = Helpers.folder(sharedParent, "Systems")
		local duplicate = Helpers.folder(sharedParent, "Systems")
		local sibling = Helpers.folder(sharedParent, "Levels")

		local rbxm, manifest = buildBoth()
		local result = Apply.apply(game, rbxm, manifest)

		expect(stale.Parent).toBeNil()
		expect(duplicate.Parent).toBeNil()
		expect(sibling.Parent).toBe(sharedParent)
		expect(#Paths.childrenNamed(sharedParent, "Systems")).toBe(1)
		expect(result.replaced).toEqual({ SHARED })
	end)

	it("replaces a previous apply and removes containers the build dropped", function()
		local first, firstManifest = Helpers.build({
			{ path = SHARED },
			{ path = DROPPED },
		}, string.rep("1", 40))
		Apply.apply(game, first, firstManifest)
		expect(ServerScriptService:FindFirstChild("Legacy")).never.toBeNil()

		local rbxm, manifest = buildBoth(string.rep("2", 40), "return 'v2'")
		local result = Apply.apply(game, rbxm, manifest)

		expect(ServerScriptService:FindFirstChild("Legacy")).toBeNil()
		expect((sharedParent:FindFirstChild("Systems") :: any).Combat.Source).toBe("return 'v2'")
		expect(result.replaced).toEqual({ SHARED })
		expect(result.added).toEqual({ SERVER })
		expect(result.removed).toEqual({ DROPPED })
		expect(Apply.Marker.read(marker()).containers).toEqual({ SHARED, SERVER })
	end)

	it("changes nothing in a dry run", function()
		local existing = Helpers.folder(sharedParent, "Systems")
		local rbxm, manifest = buildBoth()
		local result = Apply.apply(game, rbxm, manifest, { dryRun = true })

		expect(result.dryRun).toBe(true)
		expect(result.replaced).toEqual({ SHARED })
		expect(result.added).toEqual({ SERVER })
		expect(existing.Parent).toBe(sharedParent)
		expect(ServerScriptService:FindFirstChild("Systems")).toBeNil()
		expect(ServerStorage:FindFirstChild("RbxmPull")).toBeNil()
	end)

	describe("refuses before changing anything", function()
		local function expectUntouched(existing: Instance)
			expect(existing.Parent).toBe(sharedParent)
			expect(ServerScriptService:FindFirstChild("Systems")).toBeNil()
			expect(ServerStorage:FindFirstChild("RbxmPull")).toBeNil()
		end

		it("when the size or hash is wrong", function()
			local existing = Helpers.folder(sharedParent, "Systems")
			local rbxm, manifest = buildBoth()

			local wrongSize = table.clone(manifest)
			wrongSize.artifact = { size = manifest.artifact.size + 1, sha256 = manifest.artifact.sha256 }
			expect(function()
				Apply.apply(game, rbxm, wrongSize)
			end).toThrow("bytes but build.json says")

			local wrongHash = table.clone(manifest)
			wrongHash.artifact = { size = manifest.artifact.size, sha256 = string.rep("0", 64) }
			expect(function()
				Apply.apply(game, rbxm, wrongHash)
			end).toThrow("has sha256")
			expectUntouched(existing)
		end)

		it("when a target parent is missing", function()
			local existing = Helpers.folder(sharedParent, "Systems")
			local rbxm, manifest = Helpers.build({
				{ path = SHARED },
				{ path = "ReplicatedStorage/Missing/Systems" },
			})
			expect(function()
				Apply.apply(game, rbxm, manifest)
			end).toThrow("parent of container 'ReplicatedStorage/Missing/Systems' doesn't exist")
			expectUntouched(existing)
		end)

		it("when the artifact doesn't match the manifest's containers", function()
			local existing = Helpers.folder(sharedParent, "Systems")
			local rbxm, manifest = Helpers.build({ { path = SHARED } })

			local extra = table.clone(manifest)
			extra.containers = { SHARED, SERVER }
			expect(function()
				Apply.apply(game, rbxm, extra)
			end).toThrow("missing container 'ServerScriptService/Systems'")

			local fewer, fewerManifest = Helpers.build({ { path = SHARED }, { path = SERVER } })
			fewerManifest.containers = { SHARED }
			expect(function()
				Apply.apply(game, fewer, fewerManifest)
			end).toThrow("doesn't list")
			expectUntouched(existing)
		end)

		it("when the artifact isn't a build", function()
			local existing = Helpers.folder(sharedParent, "Systems")
			local folder = Instance.new("Folder")
			folder.Name = "SomethingElse"
			local rbxm = game:GetService("SerializationService"):SerializeInstancesAsync({ folder })
			local manifest = {
				schemaVersion = 1,
				commit = Helpers.COMMIT,
				ref = "refs/heads/main",
				builtAt = "x",
				artifact = { size = buffer.len(rbxm), sha256 = Apply.Sha256.hex(rbxm) },
				containers = { SHARED },
			}
			expect(function()
				Apply.apply(game, rbxm, manifest)
			end).toThrow("single Folder named RbxmDeliveryBuild")
			expectUntouched(existing)
		end)

		it("when the marker was written by a newer protocol", function()
			local newer = Apply.Marker.findOrCreate(game)
			newer:SetAttribute("Protocol", Apply.PROTOCOL + 1)
			local existing = Helpers.folder(sharedParent, "Systems")
			local rbxm, manifest = buildBoth()
			expect(function()
				Apply.apply(game, rbxm, manifest)
			end).toThrow("update rbxm-pull")
			expect(existing.Parent).toBe(sharedParent)
			expect(newer:GetAttribute("Commit")).toBeNil()
		end)
	end)

	-- ChangeHistoryService needs the Plugin capability, which Open Cloud tasks don't have.
	-- selene: allow(global_usage)
	local itStudio = if _G.RBXM_PULL_HOST == "cloud" then it.skip else it
	itStudio("rolls back a failed apply when recording change history", function()
		local existing = Helpers.folder(sharedParent, "Systems")
		Helpers.module(existing, "Old", "return 'old'")
		-- In a real place this is already in history (it's in the place file).
		game:GetService("ChangeHistoryService"):SetWaypoint("test setup")
		local rbxm, manifest = buildBoth()

		local ok, err = pcall(Apply.apply, game, rbxm, manifest, {
			changeHistory = true,
			onStep = function(step)
				if step == "marker" then
					error("injected failure", 0)
				end
			end,
		})
		expect(ok).toBe(false)
		expect(tostring(err)).toBe("apply failed and was rolled back: injected failure")

		-- The removed container is back and nothing new was inserted.
		local restored = Paths.childrenNamed(sharedParent, "Systems")
		expect(#restored).toBe(1)
		expect((restored[1] :: any).Old.Source).toBe("return 'old'")
		expect(ServerScriptService:FindFirstChild("Systems")).toBeNil()
	end)

	-- 40 folders, each holding 5 nested levels of 25 ModuleScripts: 5,000 scripts.
	local function fillLarge(folder: Instance, label: string)
		for f = 1, 40 do
			local parent: Instance = Instance.new("Folder")
			parent.Name = `Group{f}`
			parent.Parent = folder
			for depth = 1, 5 do
				for m = 1, 25 do
					Helpers.module(parent, `M{m}`, `return "{label} {f}.{depth}.{m}"`)
				end
				local nested = Instance.new("Folder")
				nested.Name = "Nested"
				nested.Parent = parent
				parent = nested
			end
		end
	end

	itStudio("rolls back a failed apply of a very large build", function()
		local existing = Helpers.folder(sharedParent, "Systems")
		fillLarge(existing, "old")
		local oldCount = #existing:GetDescendants()
		local oldSample = existing:FindFirstChild("M7", true) :: ModuleScript
		game:GetService("ChangeHistoryService"):SetWaypoint("test setup")

		local rbxm, manifest = Helpers.build({
			{
				path = SHARED,
				fill = function(folder)
					fillLarge(folder, "new")
				end,
			},
			{
				path = SERVER,
				fill = function(folder)
					fillLarge(folder, "new")
				end,
			},
		})

		local started = os.clock()
		local ok, err = pcall(Apply.apply, game, rbxm, manifest, {
			changeHistory = true,
			onStep = function(step)
				if step == "marker" then
					error("injected failure", 0)
				end
			end,
		})
		print(`large rollback: {buffer.len(rbxm)} bytes, {string.format("%.2f", os.clock() - started)}s`)
		expect(ok).toBe(false)
		expect(tostring(err)).toBe("apply failed and was rolled back: injected failure")

		-- The same old instances are back, all of them, and nothing new is left behind.
		local restored = Paths.childrenNamed(sharedParent, "Systems")
		expect(#restored).toBe(1)
		expect(restored[1]).toBe(existing)
		expect(#existing:GetDescendants()).toBe(oldCount)
		expect(oldSample:IsDescendantOf(existing)).toBe(true)
		for _, descendant in existing:GetDescendants() do
			if descendant:IsA("ModuleScript") and string.find(descendant.Source, '"new ', 1, true) then
				error(`new script left behind: {descendant:GetFullName()}`)
			end
		end
		expect(ServerScriptService:FindFirstChild("Systems")).toBeNil()
		expect(marker()).toBeNil()
	end)
end)
