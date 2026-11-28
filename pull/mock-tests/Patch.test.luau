-- The example patch script (examples/patch-task), bundled with the rbxm-apply package by
-- darklua as a project would, against a mocked engine. `lute tests` builds the bundle first
-- (lute build-patch-example). Run from the repository root.

local fs = require("@std/fs")
local json = require("@std/json")
local pathlib = require("@std/path")
local process = require("@std/process")
local test = require("@std/test")

local Helpers = require("./Helpers")
local Roblox = require("./Roblox")

local SHARED, SERVER = Helpers.SHARED, Helpers.SERVER
local BUNDLE = pathlib.format(pathlib.join(process.cwd(), "build", "patch.luau"))

local source: string? = nil

-- A fresh game with the bundled patch's function loaded into it.
local function patch(): ((any) -> any, Roblox.Game)
	if source == nil then
		assert(fs.exists(BUNDLE), "build/patch.luau is missing; run `lute build-patch-example`")
		source = fs.readFileToString(BUNDLE)
	end
	local g = Roblox.newGame()
	return Roblox.run(source :: string, "patch", g.game), g
end

local function inputs(rbxm: buffer, manifestBytes: buffer): { [string]: buffer }
	return { ["managed.rbxm"] = rbxm, ["build.json"] = manifestBytes }
end

local function contains(haystack: string, needle: string): boolean
	return string.find(haystack, needle, 1, true) ~= nil
end

local function quiet() end

test.case("applies a build and records it", function(check)
	local run, g = patch()
	Helpers.existing(g.game.ReplicatedStorage, "Systems")
	local rbxm, manifest, manifestBytes = Helpers.buildBoth()
	local logs = {}

	local outcome = run({
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
	check.eq(record.commit, Helpers.COMMIT)
	check.eq(record.sha256, manifest.artifact.sha256)
	check.eq(record.replaced[1], SHARED)
	check.eq(record.added[1], SERVER)
	check.eq(g.game.ServerScriptService.Systems.Module.Source, `return "{SERVER}"`)
	check.eq(g.game.ServerStorage.RbxmPull:GetAttribute("Commit"), Helpers.COMMIT)
	check.eq(contains(logs[1], "applying " .. Helpers.COMMIT), true)
end)

test.case("changes nothing in a dry run", function(check)
	local run, g = patch()
	local before = Helpers.snapshot(g.game)
	local rbxm, _, manifestBytes = Helpers.buildBoth()
	local outcome = run({ inputs = inputs(rbxm, manifestBytes), args = { dryRun = "true" }, log = quiet })
	check.eq(outcome.ok, true)
	check.eq(outcome.summary, `would apply {Helpers.COMMIT} (2 containers)`)
	check.eq(outcome.record.dryRun, true)
	check.eq(Helpers.snapshot(g.game), before)
end)

test.case("refuses a bad build and changes nothing", function(check)
	local rbxm, manifest = Helpers.buildBoth()
	local function refuses(name: string, ctx: any, needle: string)
		local run, g = patch()
		local before = Helpers.snapshot(g.game)
		ctx.log = quiet
		local outcome = run(ctx)
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
		"ref",
		{ inputs = inputs(rbxm, bytes({})), args = { allowedRef = "refs/heads/release" } },
		"refusing a build of 'refs/heads/main'"
	)
	refuses("missing", { inputs = { ["build.json"] = bytes({}) } }, "missing input 'managed.rbxm'")
	refuses("json", { inputs = inputs(rbxm, buffer.fromstring("{")) }, "not valid JSON")
end)

test.case("reports a failed apply that was rolled back", function(check)
	local run, g = patch()
	local old = Helpers.existing(g.game.ReplicatedStorage, "Systems")
	Roblox.setRejectChildren(g.game.ServerScriptService, true)
	local rbxm, _, manifestBytes = Helpers.buildBoth()
	local outcome = run({ inputs = inputs(rbxm, manifestBytes), log = quiet })
	check.eq(outcome.ok, false)
	check.eq(outcome.rolledBack, true)
	check.eq(contains(outcome.summary, "rolled back"), true)
	check.eq(g.game.ReplicatedStorage.Systems, old)
end)

test.case("reports a failed apply it couldn't roll back", function(check)
	local run, g = patch()
	Helpers.existing(g.game.ReplicatedStorage, "Systems")
	-- The old container can be removed, but neither the new one nor the old one can go back.
	Roblox.setRejectChildren(g.game.ReplicatedStorage, true)
	local rbxm, _, manifestBytes = Helpers.buildBoth()
	local outcome = run({ inputs = inputs(rbxm, manifestBytes), log = quiet })
	check.eq(outcome.ok, false)
	check.eq(outcome.rolledBack, false)
	check.eq(contains(outcome.summary, "don't save this place"), true)
end)
