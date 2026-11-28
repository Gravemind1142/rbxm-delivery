-- Manifest, Paths and Marker.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local describe, it, expect = JestGlobals.describe, JestGlobals.it, JestGlobals.expect
local afterEach = JestGlobals.afterEach

local Apply = require(ReplicatedStorage.RbxmPull.Apply)
local Paths = require(ReplicatedStorage.RbxmPull.Apply.Paths)
local Helpers = require(ReplicatedStorage.Tests.Helpers)

local Manifest, Marker = Apply.Manifest, Apply.Marker

local VALID = {
	schemaVersion = 1,
	commit = string.rep("a", 40),
	ref = "refs/heads/main",
	builtAt = "2026-11-22T10:15:00Z",
	artifact = { size = 10, sha256 = string.rep("A", 64) },
	containers = { "ReplicatedStorage/Systems" },
}

local function with(changes: { [string]: any }): string
	local copy = table.clone(VALID)
	for k, v in changes do
		copy[k] = v
	end
	return HttpService:JSONEncode(copy)
end

describe("Manifest.decode", function()
	it("decodes a valid build.json", function()
		local m = Manifest.decode(HttpService:JSONEncode(VALID))
		expect(m.commit).toBe(VALID.commit)
		expect(m.artifact.sha256).toBe(string.rep("a", 64))
		expect(m.containers).toEqual({ "ReplicatedStorage/Systems" })
	end)

	it("refuses unknown schema versions and bad fields", function()
		expect(function()
			Manifest.decode(with({ schemaVersion = 2 }))
		end).toThrow(Manifest.UNKNOWN_SCHEMA)
		expect(function()
			Manifest.decode(with({ commit = "" }))
		end).toThrow("'commit'")
		expect(function()
			Manifest.decode(with({ artifact = { size = 1, sha256 = "xyz" } }))
		end).toThrow("64 hex digits")
		expect(function()
			Manifest.decode(with({ containers = { "A/B", "A/B" } }))
		end).toThrow("twice")
		expect(function()
			Manifest.decode(with({ containers = { "A/B", "A/B/C" } }))
		end).toThrow("containers 'A/B' and 'A/B/C' overlap")
		expect(function()
			Manifest.decode("{not json")
		end).toThrow("not valid JSON")
	end)
end)

describe("Paths", function()
	afterEach(function()
		Helpers.cleanup()
	end)

	it("splits and validates paths", function()
		expect(Paths.leaf("ReplicatedStorage/A/B")).toBe("B")
		expect(function()
			Paths.split("ReplicatedStorage")
		end).toThrow("inside a service")
		expect(function()
			Paths.split("ReplicatedStorage//A")
		end).toThrow("invalid")
	end)

	it("resolves parents through services and folders", function()
		local a = Helpers.folder(ReplicatedStorage, "PathsTestA")
		expect(Paths.resolveParent(game, "ReplicatedStorage/X")).toBe(ReplicatedStorage)
		expect(Paths.resolveParent(game, "ReplicatedStorage/PathsTestA/X")).toBe(a)
		expect(Paths.resolveParent(game, "ReplicatedStorage/Nope/X")).toBeNil()
		expect(Paths.resolveParent(game, "NotAService/X")).toBeNil()
	end)

	it("refuses an ambiguous parent", function()
		Helpers.folder(ReplicatedStorage, "PathsTestDup")
		Helpers.folder(ReplicatedStorage, "PathsTestDup")
		expect(function()
			Paths.resolveParent(game, "ReplicatedStorage/PathsTestDup/X")
		end).toThrow("ambiguous")
	end)
end)

describe("Marker", function()
	afterEach(function()
		Helpers.cleanup()
	end)

	it("reads defaults from an empty marker", function()
		local state = Marker.read(Marker.findOrCreate(game))
		expect(state.repo).toBeNil()
		expect(state.owners).toEqual({})
		expect(state.intervalSeconds).toBe(Marker.DEFAULT_INTERVAL_SECONDS)
		expect(state.protocol).toBe(0)
		expect(Marker.canWrite(state)).toBe(true)
	end)

	it("round-trips settings and applied state", function()
		local marker = Marker.findOrCreate(game)
		expect(Marker.findOrCreate(game)).toBe(marker)
		Marker.configure(marker, { repo = "o/r", channel = "dev-latest", allowedRef = "refs/heads/main" })
		marker:SetAttribute("Owners", " 1, 22 ,x, 333 ")
		Marker.writeApplied(marker, {
			commit = "c",
			schemaVersion = 1,
			appliedAt = "now",
			appliedBy = 22,
			containers = { "A/B", "C/D" },
		})

		local state = Marker.read(marker)
		expect(state.repo).toBe("o/r")
		expect(state.channel).toBe("dev-latest")
		expect(state.allowedRef).toBe("refs/heads/main")
		expect(state.owners).toEqual({ 1, 22, 333 })
		expect(state.commit).toBe("c")
		expect(state.protocol).toBe(Marker.PROTOCOL)
		expect(state.containers).toEqual({ "A/B", "C/D" })
	end)

	it("is read-only to plugins with an older protocol", function()
		local marker = Marker.findOrCreate(game)
		marker:SetAttribute("Protocol", Marker.PROTOCOL + 1)
		expect(Marker.canWrite(Marker.read(marker))).toBe(false)
	end)
end)
