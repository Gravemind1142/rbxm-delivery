-- Tests for `rbxm-publish release` against an in-memory GitHub. Run from the repository root.

local crypto = require("@lute/crypto")
local fs = require("@std/fs")
local test = require("@std/test")

local fakeGithub = require("./fakeGithub")
local manifest = require("../src/manifest")
local release = require("../src/release")

local ROOT = "build/test-release"
local A = string.rep("a", 40)
local B = string.rep("b", 40)
local C = string.rep("c", 40)
local MAIN = "refs/heads/main"
local CHANNEL = "dev-latest"

-- Writes a build directory holding `contents` as managed.rbxm, built from `commit`.
local function writeBuild(name: string, commit: string, ref: string?, contents: string?): string
	local dir = `{ROOT}/{name}`
	if not fs.exists(dir) then
		fs.createDirectory(dir, { makeParents = true })
	end
	local artifact = contents or `rbxm built from {commit}`
	fs.writeStringToFile(`{dir}/managed.rbxm`, artifact)
	fs.writeStringToFile(
		`{dir}/build.json`,
		manifest.encode({
			schemaVersion = 1,
			commit = commit,
			ref = ref or MAIN,
			builtAt = "2026-11-22T10:15:00Z",
			artifact = {
				size = #artifact,
				sha256 = manifest.hex(crypto.digest(crypto.hash.sha256, artifact)),
			},
			containers = { "ReplicatedStorage/Systems" },
		})
	)
	return dir
end

local function publish(gh: fakeGithub.Fake, dir: string): release.Result
	return release.run({ dir = dir, channel = CHANNEL, allowedRefs = { MAIN }, client = gh:client() })
end

local function assetNames(gh: fakeGithub.Fake): string
	local names = {}
	for _, a in (gh:release(CHANNEL) :: fakeGithub.Release).assets do
		table.insert(names, a.name)
	end
	table.sort(names)
	return table.concat(names, ",")
end

local function errorOf(f: () -> ()): string
	local ok, err = pcall(f)
	assert(not ok, "expected an error")
	return tostring(err)
end

test.case("first publish creates the tag, release and both assets", function(check)
	local gh = fakeGithub.new({ A, B })
	local result = publish(gh, writeBuild("first", A))
	check.eq(result.published, true)
	check.eq(gh.refs[CHANNEL], A)
	local rel = gh:release(CHANNEL) :: fakeGithub.Release
	check.eq(rel.makeLatest, "false")
	check.eq(string.find(rel.body, A, 1, true) ~= nil, true)
	check.eq(assetNames(gh), "build.json,managed.rbxm")
	local rbxm = gh:asset(CHANNEL, "managed.rbxm") :: fakeGithub.Asset
	check.eq(rbxm.contents, `rbxm built from {A}`)
	check.eq(rbxm.contentType, "application/octet-stream")
	local manifestAsset = gh:asset(CHANNEL, "build.json") :: fakeGithub.Asset
	check.eq(manifest.decode(manifestAsset.contents).commit, A)
end)

test.case("a newer build replaces the assets and moves the tag", function(check)
	local gh = fakeGithub.new({ A, B })
	publish(gh, writeBuild("newer-a", A))
	local oldId = (gh:asset(CHANNEL, "managed.rbxm") :: fakeGithub.Asset).id
	local result = publish(gh, writeBuild("newer-b", B))
	check.eq(result.published, true)
	check.eq(gh.refs[CHANNEL], B)
	check.eq(#gh.releases, 1)
	check.eq(assetNames(gh), "build.json,managed.rbxm")
	local rbxm = gh:asset(CHANNEL, "managed.rbxm") :: fakeGithub.Asset
	check.neq(rbxm.id, oldId)
	check.eq(rbxm.contents, `rbxm built from {B}`)
	check.eq(string.find((gh:release(CHANNEL) :: fakeGithub.Release).body, B, 1, true) ~= nil, true)
end)

test.case("an older build is skipped without touching the release", function(check)
	local gh = fakeGithub.new({ A, B })
	publish(gh, writeBuild("older-b", B))
	local callsBefore = #gh.calls
	local result = publish(gh, writeBuild("older-a", A))
	check.eq(result.published, false)
	check.eq(gh.refs[CHANNEL], B)
	check.eq((gh:asset(CHANNEL, "managed.rbxm") :: fakeGithub.Asset).contents, `rbxm built from {B}`)
	for i = callsBefore + 1, #gh.calls do
		check.eq(string.sub(gh.calls[i], 1, 4), "GET ")
	end
end)

test.case("republishing the same commit replaces assets without moving the tag", function(check)
	local gh = fakeGithub.new({ A })
	publish(gh, writeBuild("same-1", A))
	local result = publish(gh, writeBuild("same-2", A, nil, "rebuilt"))
	check.eq(result.published, true)
	check.eq((gh:asset(CHANNEL, "managed.rbxm") :: fakeGithub.Asset).contents, "rebuilt")
	for _, call in gh.calls do
		check.eq(string.find(call, "PATCH /git/refs", 1, true), nil)
	end
end)

test.case("publishes when GitHub can't compare the commits", function(check)
	local gh = fakeGithub.new({ B })
	gh.refs[CHANNEL] = C -- not in history, e.g. after a force push
	local result = publish(gh, writeBuild("uncomparable", B))
	check.eq(result.published, true)
	check.eq(gh.refs[CHANNEL], B)
end)

test.case("uses an existing tag that has no release yet", function(check)
	local gh = fakeGithub.new({ A, B })
	gh.refs[CHANNEL] = A
	publish(gh, writeBuild("tag-only", B))
	check.eq(gh.refs[CHANNEL], B)
	check.eq(assetNames(gh), "build.json,managed.rbxm")
	for _, call in gh.calls do
		check.eq(call == "POST /git/refs", false)
	end
end)

test.case("recovers from a run interrupted mid-swap", function(check)
	local gh = fakeGithub.new({ A, B, C })
	publish(gh, writeBuild("interrupt-a", A))
	gh.failOn = "^PATCH /releases/assets/"
	check.eq(pcall(publish, gh, writeBuild("interrupt-b", B)), false)
	check.eq(gh.refs[CHANNEL], A) -- the tag only moves once everything is in place

	local result = publish(gh, writeBuild("interrupt-c", C))
	check.eq(result.published, true)
	check.eq(assetNames(gh), "build.json,managed.rbxm")
	check.eq((gh:asset(CHANNEL, "managed.rbxm") :: fakeGithub.Asset).contents, `rbxm built from {C}`)
	check.eq(gh.refs[CHANNEL], C)
end)

test.case("refuses a disallowed ref before any request", function(check)
	local gh = fakeGithub.new({ A })
	local err = errorOf(function()
		publish(gh, writeBuild("bad-ref", A, "refs/heads/feature"))
	end)
	check.eq(string.find(err, "refusing to release", 1, true) ~= nil, true)
	check.eq(#gh.calls, 0)
end)

test.case("refuses an artifact that doesn't match build.json", function(check)
	local gh = fakeGithub.new({ A })
	local dir = writeBuild("tampered", A)
	fs.writeStringToFile(`{dir}/managed.rbxm`, "tampered!!!!!!!!!!!!!!!!!")
	check.eq(string.find(
		errorOf(function()
			publish(gh, dir)
		end),
		"bytes but build.json says",
		1,
		true
	) ~= nil, true)

	local same = `rbxm built from {A}`
	fs.writeStringToFile(`{dir}/managed.rbxm`, string.upper(same))
	check.eq(string.find(
		errorOf(function()
			publish(gh, dir)
		end),
		"has sha256",
		1,
		true
	) ~= nil, true)
	check.eq(#gh.calls, 0)
end)

test.case("refuses a missing build and bad options", function(check)
	local gh = fakeGithub.new({ A })
	check.eq(string.find(
		errorOf(function()
			publish(gh, `{ROOT}/does-not-exist`)
		end),
		"run 'rbxm-publish build' first",
		1,
		true
	) ~= nil, true)

	local dir = writeBuild("options", A)
	check.eq(pcall(release.run, { dir = dir, channel = CHANNEL, allowedRefs = {}, client = gh:client() }), false)
	for _, channel in { "", "refs/tags/x", "a..b", "/x", "has space" } do
		check.eq(pcall(release.validateChannel, channel), false)
	end
	release.validateChannel("dev-latest")
	release.validateChannel("channels/dev")
	check.eq(#gh.calls, 0)
end)

test.case("surfaces GitHub errors", function(check)
	local gh = fakeGithub.new({ A })
	gh.failOn = "^POST /releases$"
	local err = errorOf(function()
		publish(gh, writeBuild("api-error", A))
	end)
	check.eq(string.find(err, "POST /repos/owner/game/releases failed: 500 injected failure", 1, true) ~= nil, true)
end)
