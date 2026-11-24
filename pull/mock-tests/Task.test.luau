-- apply-task.luau, bundled as released, against a mocked engine. Run from the repository root.

local json = require("@std/json")
local test = require("@std/test")

local verify = require("../../publish/src/verify")
local Helpers = require("./Helpers")
local Roblox = require("./Roblox")

local SHARED, SERVER = Helpers.SHARED, Helpers.SERVER

local function inputs(rbxm: buffer, manifestBytes: buffer): { [string]: buffer }
	return { ["managed.rbxm"] = rbxm, ["build.json"] = manifestBytes }
end

local function contains(haystack: string, needle: string): boolean
	return string.find(haystack, needle, 1, true) ~= nil
end

test.case("applies a build and records it", function(check)
	local applyTask, g = Helpers.task()
	Helpers.existing(g.game.ReplicatedStorage, "Systems")
	local rbxm, manifest, manifestBytes = Helpers.buildBoth()
	local logs = {}

	local outcome = applyTask({
		inputs = inputs(rbxm, manifestBytes),
		args = { allowedRef = "refs/heads/dev, refs/heads/main" },
		log = function(line: string)
			table.insert(logs, line)
		end,
	})
	check.eq(outcome.ok, true)
	check.eq(outcome.summary, `applied {Helpers.COMMIT} (2 containers)`)
	check.eq(outcome.rolledBack, nil)
	local record = outcome.record
	check.eq(record.applyVersion, "test")
	check.eq(record.commit, Helpers.COMMIT)
	check.eq(record.sha256, manifest.artifact.sha256)
	check.eq(record.replaced[1], SHARED)
	check.eq(record.added[1], SERVER)
	check.eq(g.game.ServerScriptService.Systems.Module.Source, `return "{SERVER}"`)
	check.eq(g.game.ServerStorage.RbxmPull:GetAttribute("Commit"), Helpers.COMMIT)
	check.eq(contains(logs[1], "applying " .. Helpers.COMMIT), true)
end)

test.case("records the same build fields as rbxm-publish verify", function(check)
	local applyTask = Helpers.task()
	local rbxm, manifest, manifestBytes = Helpers.buildBoth()
	local record = applyTask({ inputs = inputs(rbxm, manifestBytes), log = function() end }).record

	local summary = json.asObject(json.deserialize(verify.summaryJson(manifest))) :: json.Object
	for key, value in summary :: { [any]: any } do
		if typeof(key) ~= "string" then
			continue -- @std/json's own type tag
		elseif key == "containers" then
			check.eq(table.concat(record.containers, ","), table.concat(json.asArray(value) :: { any }, ","))
		else
			check.eq(record[key], value)
		end
	end
end)

test.case("changes nothing in a dry run", function(check)
	local applyTask, g = Helpers.task()
	local before = Helpers.snapshot(g.game)
	local rbxm, _, manifestBytes = Helpers.buildBoth()
	local outcome =
		applyTask({ inputs = inputs(rbxm, manifestBytes), args = { dryRun = "true" }, log = function() end })
	check.eq(outcome.ok, true)
	check.eq(outcome.summary, `would apply {Helpers.COMMIT} (2 containers)`)
	check.eq(outcome.record.dryRun, true)
	check.eq(Helpers.snapshot(g.game), before)
end)

test.case("refuses a bad build and changes nothing", function(check)
	local rbxm, manifest = Helpers.buildBoth()
	local function refuses(name: string, ctx: any, needle: string)
		local applyTask, g = Helpers.task()
		local before = Helpers.snapshot(g.game)
		ctx.log = function() end
		local outcome = applyTask(ctx)
		check.eq(outcome.ok, false)
		check.eq(outcome.rolledBack, true)
		if not contains(outcome.summary, needle) then
			error(`{name}: '{outcome.summary}' doesn't mention '{needle}'`)
		end
		check.eq(Helpers.snapshot(g.game), before)
	end
	local function bytes(changes: { [string]: any }): buffer
		local m = table.clone(manifest)
		for key, value in changes do
			m[key] = value
		end
		return buffer.fromstring(json.serialize(m))
	end

	refuses("schema", { inputs = inputs(rbxm, bytes({ schemaVersion = 2 })) }, "unknown build.json schemaVersion 2")
	refuses(
		"sha256",
		{ inputs = inputs(rbxm, bytes({ artifact = { size = manifest.artifact.size, sha256 = string.rep("0", 64) } })) },
		"has sha256"
	)
	refuses(
		"size",
		{ inputs = inputs(rbxm, bytes({ artifact = { size = 1, sha256 = manifest.artifact.sha256 } })) },
		"bytes but build.json says 1"
	)
	refuses(
		"ref",
		{ inputs = inputs(rbxm, bytes({})), args = { allowedRef = "refs/heads/release" } },
		"refusing a build of 'refs/heads/main'"
	)
	refuses("missing", { inputs = { ["build.json"] = bytes({}) } }, "missing input 'managed.rbxm'")
	refuses("json", { inputs = inputs(rbxm, buffer.fromstring("{")) }, "not valid JSON")
end)

test.case("reports a failed apply that was rolled back", function(check)
	local applyTask, g = Helpers.task()
	local old = Helpers.existing(g.game.ReplicatedStorage, "Systems")
	Roblox.setRejectChildren(g.game.ServerScriptService, true)
	local rbxm, _, manifestBytes = Helpers.buildBoth()
	local outcome = applyTask({ inputs = inputs(rbxm, manifestBytes), log = function() end })
	check.eq(outcome.ok, false)
	check.eq(outcome.rolledBack, true)
	check.eq(contains(outcome.summary, "rolled back"), true)
	check.eq(g.game.ReplicatedStorage.Systems, old)
end)

test.case("reports a failed apply it couldn't roll back", function(check)
	local applyTask, g = Helpers.task()
	Helpers.existing(g.game.ReplicatedStorage, "Systems")
	-- The old container can be removed, but neither the new one nor the old one can go back.
	Roblox.setRejectChildren(g.game.ReplicatedStorage, true)
	local rbxm, _, manifestBytes = Helpers.buildBoth()
	local outcome = applyTask({ inputs = inputs(rbxm, manifestBytes), log = function() end })
	check.eq(outcome.ok, false)
	check.eq(outcome.rolledBack, false)
	check.eq(contains(outcome.summary, "don't save this place"), true)
end)
