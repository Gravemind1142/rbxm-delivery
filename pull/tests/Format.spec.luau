local ReplicatedStorage = game:GetService("ReplicatedStorage")
local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local describe, it, expect = JestGlobals.describe, JestGlobals.it, JestGlobals.expect

local Format = require(ReplicatedStorage.RbxmPull.Format)

local NOW = DateTime.fromIsoDate("2026-11-22T12:00:00Z").UnixTimestamp

describe("Format", function()
	it("shortens commits and refs", function()
		expect(Format.short(string.rep("a", 40))).toBe("aaaaaaa")
		expect(Format.short(nil)).toBe("—")
		expect(Format.refName("refs/heads/main")).toBe("main")
		expect(Format.refName("refs/tags/v1")).toBe("refs/tags/v1")
	end)

	it("describes how long ago something happened", function()
		expect(Format.ago("2026-11-22T11:59:30Z", NOW)).toBe("just now")
		expect(Format.ago("2026-11-22T11:58:00Z", NOW)).toBe("2 min ago")
		expect(Format.ago("2026-11-22T09:00:00Z", NOW)).toBe("3 h ago")
		expect(Format.ago("2026-11-20T12:00:00Z", NOW)).toBe("2 d ago")
		expect(Format.ago(nil, NOW)).toBeNil()
		expect(Format.ago("garbage", NOW)).toBeNil()
	end)

	it("builds the status line", function()
		local state = { commit = string.rep("a", 40), appliedAt = "2026-11-22T11:58:00Z" } :: any
		local manifest = { commit = string.rep("b", 40), ref = "refs/heads/main" } :: any
		expect(Format.statusLine(state, manifest, NOW)).toBe("Dev @ aaaaaaa · main @ bbbbbbb · synced 2 min ago")
		expect(Format.statusLine(nil, nil, NOW)).toBe("Dev @ —")
	end)

	it("summarises an apply", function()
		local result = {
			commit = string.rep("c", 40),
			replaced = { "A/B", "C/D" },
			added = {},
			removed = { "E/F" },
			dryRun = false,
		}
		expect(Format.result(result)).toBe("Synced ccccccc: replaced 2, removed 1.")
	end)
end)
