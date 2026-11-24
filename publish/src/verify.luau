--!strict
-- `rbxm-publish verify` (spec §5.2): checks a build directory without publishing it. These are
-- the same local checks `release` runs before any network call, so a pipeline that consumes a
-- build some other way (e.g. applies it in a Luau Execution task) can fail fast.
--
-- The failure messages match rbxm-pull's Apply word for word, so a build is refused for the
-- same reason wherever it's checked.

local crypto = require("@lute/crypto")
local fs = require("@std/fs")
local json = require("@std/json")
local pathlib = require("@std/path")

local manifest = require("./manifest")

export type Options = {
	dir: string,
	-- If given (and non-empty), the build's ref must be one of these.
	allowedRefs: { string }?,
}

export type LoadedBuild = { manifest: manifest.Manifest, artifact: string, manifestSource: string }

local verify = {}

-- Reads `dir` and checks managed.rbxm against build.json, and the ref if `allowedRefs` is set.
function verify.run(options: Options): LoadedBuild
	local dir = options.dir
	local manifestPath = pathlib.format(pathlib.join(dir, manifest.MANIFEST_NAME))
	local artifactPath = pathlib.format(pathlib.join(dir, manifest.ARTIFACT_NAME))
	for _, path in { manifestPath, artifactPath } do
		if not fs.exists(path) then
			error(`'{path}' not found; run 'rbxm-publish build' first`, 0)
		end
	end

	local manifestSource = fs.readFileToString(manifestPath)
	local m = manifest.decode(manifestSource)
	local artifact = fs.readFileToString(artifactPath)
	if #artifact ~= m.artifact.size then
		error(`managed.rbxm is {#artifact} bytes but build.json says {m.artifact.size}`, 0)
	end
	local sha256 = manifest.hex(crypto.digest(crypto.hash.sha256, artifact))
	if sha256 ~= m.artifact.sha256 then
		error(`managed.rbxm has sha256 {sha256} but build.json says {m.artifact.sha256}`, 0)
	end

	local allowedRefs = options.allowedRefs
	if allowedRefs and #allowedRefs > 0 and not table.find(allowedRefs, m.ref) then
		error(`refusing a build of '{m.ref}': allowed refs are {table.concat(allowedRefs, ", ")}`, 0)
	end

	return { manifest = m, artifact = artifact, manifestSource = manifestSource }
end

-- What `verify --format json` prints: one line, the same fields apply-task.luau records.
function verify.summaryJson(m: manifest.Manifest): string
	local s = json.serialize
	local containers = {}
	for _, container in m.containers do
		table.insert(containers, s(container))
	end
	return `\{"schemaVersion":{m.schemaVersion},"commit":{s(m.commit)},"ref":{s(m.ref)},`
		.. `"builtAt":{s(m.builtAt)},"size":{m.artifact.size},"sha256":{s(m.artifact.sha256)},`
		.. `"containers":[{table.concat(containers, ",")}]}`
end

return verify
