-- Tests for `rbxm-publish verify`. Run from the repository root.

local crypto = require("@lute/crypto")
local fs = require("@std/fs")
local json = require("@std/json")
local pathlib = require("@std/path")
local process = require("@std/process")
local test = require("@std/test")

local manifest = require("../src/manifest")
local verify = require("../src/verify")

local ROOT = "build/test-verify"
local A = string.rep("a", 40)
local MAIN = "refs/heads/main"
local LUTE = pathlib.format(process.execPath())

local function writeBuild(name: string, ref: string?): string
	local dir = `{ROOT}/{name}`
	if not fs.exists(dir) then
		fs.createDirectory(dir, { makeParents = true })
	end
	local artifact = `rbxm for {name}`
	fs.writeStringToFile(`{dir}/managed.rbxm`, artifact)
	fs.writeStringToFile(
		`{dir}/build.json`,
		manifest.encode({
			schemaVersion = 1,
			commit = A,
			ref = ref or MAIN,
			builtAt = "2026-11-22T10:15:00Z",
			artifact = {
				size = #artifact,
				sha256 = manifest.hex(crypto.digest(crypto.hash.sha256, artifact)),
			},
			containers = { "ReplicatedStorage/Systems", "ServerScriptService/Systems" },
		})
	)
	return dir
end

local function errorOf(f: () -> ()): string
	local ok, err = pcall(f)
	assert(not ok, "expected an error")
	return tostring(err)
end

local function contains(haystack: string, needle: string): boolean
	return string.find(haystack, needle, 1, true) ~= nil
end

test.case("accepts a good build", function(check)
	local build = verify.run({ dir = writeBuild("good") })
	check.eq(build.manifest.commit, A)
	check.eq(#build.manifest.containers, 2)
end)

test.case("checks the ref only when allowed refs are given", function(check)
	local dir = writeBuild("feature", "refs/heads/feature")
	check.eq(verify.run({ dir = dir }).manifest.ref, "refs/heads/feature")
	check.eq(verify.run({ dir = dir, allowedRefs = {} }).manifest.ref, "refs/heads/feature")
	check.eq(
		contains(
			errorOf(function()
				verify.run({ dir = dir, allowedRefs = { MAIN } })
			end),
			"refusing a build of 'refs/heads/feature'"
		),
		true
	)
	check.eq(verify.run({ dir = dir, allowedRefs = { MAIN, "refs/heads/feature" } }).manifest.ref, "refs/heads/feature")
end)

test.case("refuses a bad build with the reason", function(check)
	local dir = writeBuild("size")
	fs.writeStringToFile(`{dir}/managed.rbxm`, "tampered, and a different length")
	check.eq(
		contains(
			errorOf(function()
				verify.run({ dir = dir })
			end),
			"bytes but build.json says"
		),
		true
	)

	dir = writeBuild("hash")
	fs.writeStringToFile(`{dir}/managed.rbxm`, string.upper("rbxm for hash"))
	check.eq(
		contains(
			errorOf(function()
				verify.run({ dir = dir })
			end),
			"has sha256"
		),
		true
	)

	dir = writeBuild("schema")
	local source = string.gsub(fs.readFileToString(`{dir}/build.json`), '"schemaVersion": 1', '"schemaVersion": 2')
	fs.writeStringToFile(`{dir}/build.json`, source)
	check.eq(
		contains(
			errorOf(function()
				verify.run({ dir = dir })
			end),
			"supports only 1"
		),
		true
	)

	check.eq(
		contains(
			errorOf(function()
				verify.run({ dir = `{ROOT}/missing` })
			end),
			"not found"
		),
		true
	)
end)

test.case("summarizes a build as one line of JSON", function(check)
	local m = verify.run({ dir = writeBuild("json") }).manifest
	local line = verify.summaryJson(m)
	check.eq(contains(line, "\n"), false)
	local summary = json.asObject(json.deserialize(line)) :: json.Object
	check.eq(summary.schemaVersion, 1)
	check.eq(summary.commit, A)
	check.eq(summary.ref, MAIN)
	check.eq(summary.sha256, m.artifact.sha256)
	check.eq(summary.size, m.artifact.size)
	check.eq((json.asArray(summary.containers) :: json.Array)[2], "ServerScriptService/Systems")
end)

test.case("summarizes exactly the build fields Apply.record records", function(check)
	-- pull/tests/Apply.spec.luau pins the same list on Apply's side, so a pipeline can compare
	-- the two outputs field by field.
	local expected = { "builtAt", "commit", "containers", "ref", "schemaVersion", "sha256", "size" }
	local m = verify.run({ dir = writeBuild("fields") }).manifest
	local summary = json.asObject(json.deserialize(verify.summaryJson(m))) :: json.Object
	local keys = {}
	for key in summary :: { [any]: any } do
		if typeof(key) == "string" then -- skip @std/json's own type tag
			table.insert(keys, key)
		end
	end
	table.sort(keys)
	check.eq(table.concat(keys, ","), table.concat(expected, ","))
end)

test.case("the CLI exits 0 for a good build and 1 for a bad one", function(check)
	local good = writeBuild("cli-good")
	local result = process.run(
		{ LUTE, "publish/src/main.luau", "verify", "--dir", good, "--format", "json" },
		{ stdio = "default" }
	)
	check.eq(result.exitcode, 0)
	local summary = json.asObject(json.deserialize(result.stdout)) :: json.Object
	check.eq(summary.commit, A)

	result = process.run(
		{ LUTE, "publish/src/main.luau", "verify", "--dir", good, "--allowed-ref", "refs/heads/other" },
		{ stdio = "default" }
	)
	check.eq(result.exitcode, 1)
	check.eq(contains(result.stderr, "refusing a build of"), true)
	check.eq(result.stdout, "")
end)
