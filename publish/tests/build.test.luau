-- End-to-end tests for `rbxm-publish build`. Needs `rojo` on PATH; run from the repository root.

local crypto = require("@lute/crypto")
local fs = require("@std/fs")
local json = require("@std/json")
local test = require("@std/test")

local build = require("../src/build")
local config = require("../src/config")
local manifest = require("../src/manifest")
local paths = require("../src/paths")

local FIXTURE = "publish/tests/fixtures/game"
local CONFIG = `{FIXTURE}/rbxm-publish.json`
local OUT = "build/test-out"
local COMMIT = "3f2c0000000000000000000000000000000000e1"
local REF = "refs/heads/main"

local function generate(): (json.Object, string, config.Config, { { string } })
	local cfg = config.load(CONFIG)
	local containers = paths.checkContainers(cfg.containers)
	local generated, projectDir = build.generateProject(cfg, containers)
	return generated, projectDir, cfg, containers
end

test.case("generates a wrapper project with one child per container", function(check)
	local generated = generate()
	check.eq(generated.name, "RbxmDeliveryBuild")
	local tree = json.asObject(generated.tree) :: json.Object
	check.eq(tree["$className"], "Folder")
	check.eq((json.asObject(tree["ReplicatedStorage/Systems"]) :: json.Object)["$path"], "src/shared/Systems")
	check.eq((json.asObject(tree["ServerScriptService/Systems"]) :: json.Object)["$path"], "src/server/Systems")
	check.eq((json.asObject(tree["ReplicatedStorage/Contract"]) :: json.Object)["$path"], "src/contract")
end)

test.case("injects BuildInfo and ignores the committed placeholder", function(check)
	local generated, projectDir, cfg, containers = generate()
	build.addBuildInfo(generated, projectDir, containers, cfg.buildInfoModule :: string, "/abs/BuildInfo.luau")
	local tree = json.asObject(generated.tree) :: json.Object
	local contract = json.asObject(tree["ReplicatedStorage/Contract"]) :: json.Object
	check.eq((json.asObject(contract.BuildInfo) :: json.Object)["$path"], "/abs/BuildInfo.luau")
	local ignores = json.asArray(generated.globIgnorePaths) :: json.Array
	check.eq(ignores[1], "src/contract/BuildInfo.luau")
end)

test.case("rejects a BuildInfo module outside the containers", function(check)
	local generated, projectDir, _, containers = generate()
	local ok, err = pcall(build.addBuildInfo, generated, projectDir, containers, "ReplicatedStorage/BuildInfo", "x")
	check.eq(ok, false)
	check.eq(string.find(tostring(err), "must be inside one of the containers", 1, true) ~= nil, true)
end)

test.case("rejects a BuildInfo module below a folder found only on disk", function(check)
	local generated, projectDir, _, containers = generate()
	local ok, err =
		pcall(build.addBuildInfo, generated, projectDir, containers, "ReplicatedStorage/Systems/Sub/BuildInfo", "x")
	check.eq(ok, false)
	check.eq(string.find(tostring(err), "must be an explicit node", 1, true) ~= nil, true)
end)

test.case("validates commit and ref", function(check)
	local function fails(commit: string, ref: string)
		local ok = pcall(build.sourceInfo, { configPath = CONFIG, outDir = OUT, commit = commit, ref = ref }, ".")
		check.eq(ok, false)
	end
	fails("abc123", REF)
	fails(COMMIT, "main")
	local commit, ref =
		build.sourceInfo({ configPath = CONFIG, outDir = OUT, commit = string.upper(COMMIT), ref = REF }, ".")
	check.eq(commit, COMMIT)
	check.eq(ref, REF)
end)

test.case("builds managed.rbxm and build.json", function(check)
	local m = build.run({ configPath = CONFIG, outDir = OUT, commit = COMMIT, ref = REF })

	local artifact = fs.readFileToString(`{OUT}/managed.rbxm`)
	check.eq(string.sub(artifact, 1, 14), "<roblox!\137\255\r\n\26\n")
	check.eq(m.artifact.size, #artifact)
	check.eq(m.artifact.sha256, manifest.hex(crypto.digest(crypto.hash.sha256, artifact)))

	local decoded = json.asObject(json.deserialize(fs.readFileToString(`{OUT}/build.json`))) :: json.Object
	check.eq(decoded.schemaVersion, 1)
	check.eq(decoded.commit, COMMIT)
	check.eq(decoded.ref, REF)
	check.eq(string.match(decoded.builtAt :: string, "^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ$") ~= nil, true)
	check.eq((json.asObject(decoded.artifact) :: json.Object).sha256, m.artifact.sha256)
	check.eq(#(json.asArray(decoded.containers) :: json.Array), 4)

	-- Temporary files are cleaned up.
	check.eq(fs.exists(`{FIXTURE}/.rbxm-publish.tmp.project.json`), false)
	check.eq(fs.exists(`{OUT}/.rbxm-publish.tmp.BuildInfo.luau`), false)
end)
