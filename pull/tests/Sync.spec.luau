local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local describe, it, expect = JestGlobals.describe, JestGlobals.it, JestGlobals.expect
local beforeEach, afterEach = JestGlobals.beforeEach, JestGlobals.afterEach

local Apply = require(ReplicatedStorage.RbxmPull.Apply)
local Sync = require(ReplicatedStorage.RbxmPull.Sync)
local Helpers = require(ReplicatedStorage.Tests.Helpers)

local Marker = Apply.Marker
local PATH = "ServerScriptService/SyncTestSystems"

-- A source serving one build, counting downloads.
local function fakeSource(rbxm: buffer, manifest: Apply.Manifest, failure: string?)
	local source = { downloads = 0 }
	function source.getManifest(_self, _etag)
		if failure then
			error(failure, 0)
		end
		return { unchanged = false, release = { manifest = manifest, artifactAssetId = 1 } }
	end
	function source.getArtifact(self, _release)
		self.downloads += 1
		return rbxm
	end
	return source
end

local function setUp(allowedRef: string?)
	Marker.configure(Marker.findOrCreate(game), {
		repo = "o/r",
		channel = "dev-latest",
		allowedRef = allowedRef or "refs/heads/main",
	})
end

beforeEach(function()
	Helpers.cleanup({ PATH })
end)

afterEach(function()
	Helpers.cleanup({ PATH })
end)

describe("Sync.check", function()
	it("reports a place that isn't set up", function()
		local rbxm, manifest = Helpers.build({ { path = PATH } })
		expect(Sync.check(game, fakeSource(rbxm, manifest)).kind).toBe("notSetUp")
		Marker.findOrCreate(game)
		expect(Sync.check(game, fakeSource(rbxm, manifest)).kind).toBe("notSetUp")
	end)

	it("is behind until the build is applied, then up to date", function()
		setUp()
		local rbxm, manifest = Helpers.build({ { path = PATH } })
		local source = fakeSource(rbxm, manifest)
		local status = Sync.check(game, source)
		expect(status.kind).toBe("behind")
		expect(status.canSync).toBe(true)

		local result = Sync.syncNow(game, source, status, { appliedBy = 7, changeHistory = false })
		expect(result).never.toBeNil()
		expect(ServerScriptService:FindFirstChild("SyncTestSystems")).never.toBeNil()
		expect(Marker.read(Marker.find(game) :: Configuration).appliedBy).toBe(7)
		expect(Sync.check(game, source).kind).toBe("upToDate")
	end)

	it("refuses a build from another ref", function()
		setUp("refs/heads/release")
		local rbxm, manifest = Helpers.build({ { path = PATH } })
		local status = Sync.check(game, fakeSource(rbxm, manifest))
		expect(status.kind).toBe("refused")
		expect(status.canSync).toBe(false)
	end)

	it("refuses a build with an unknown schema version", function()
		setUp()
		local rbxm, manifest = Helpers.build({ { path = PATH } })
		local status = Sync.check(game, fakeSource(rbxm, manifest, `{Apply.Manifest.UNKNOWN_SCHEMA} 2`))
		expect(status.kind).toBe("refused")
		expect(status.message).toMatch("Update rbxm%-pull")
	end)

	it("reports fetch errors", function()
		setUp()
		local rbxm, manifest = Helpers.build({ { path = PATH } })
		local status = Sync.check(game, fakeSource(rbxm, manifest, "GitHub rate limit reached"))
		expect(status.kind).toBe("error")
		expect(status.message).toBe("GitHub rate limit reached")
	end)

	it("is read-only when a newer protocol wrote the marker", function()
		setUp()
		Marker.findOrCreate(game):SetAttribute("Protocol", Marker.PROTOCOL + 1)
		local rbxm, manifest = Helpers.build({ { path = PATH } })
		local status = Sync.check(game, fakeSource(rbxm, manifest))
		expect(status.kind).toBe("readOnly")
		expect(status.canSync).toBe(false)
	end)
end)

describe("Sync.syncNow", function()
	it("does nothing if someone else applied the build meanwhile", function()
		setUp()
		local rbxm, manifest = Helpers.build({ { path = PATH } })
		local source = fakeSource(rbxm, manifest)
		local status = Sync.check(game, source)
		Apply.apply(game, rbxm, manifest)
		local applied = ServerScriptService:FindFirstChild("SyncTestSystems")

		expect(Sync.syncNow(game, source, status, { changeHistory = false })).toBeNil()
		expect(ServerScriptService:FindFirstChild("SyncTestSystems")).toBe(applied)
	end)

	it("refuses a status that can't sync", function()
		setUp("refs/heads/release")
		local rbxm, manifest = Helpers.build({ { path = PATH } })
		local source = fakeSource(rbxm, manifest)
		local status = Sync.check(game, source)
		expect(function()
			Sync.syncNow(game, source, status)
		end).toThrow("only accepts refs/heads/release")
		expect(source.downloads).toBe(0)
	end)

	it("refuses a tampered download before touching the place", function()
		setUp()
		local rbxm, manifest = Helpers.build({ { path = PATH } })
		local tampered = buffer.create(buffer.len(rbxm))
		local source = fakeSource(tampered, manifest)
		expect(function()
			Sync.syncNow(game, source, Sync.check(game, source))
		end).toThrow("has sha256")
		expect(ServerScriptService:FindFirstChild("SyncTestSystems")).toBeNil()
		expect(Marker.read(Marker.find(game) :: Configuration).commit).toBeNil()
	end)
end)
