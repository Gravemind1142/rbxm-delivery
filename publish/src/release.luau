--!strict
-- `rbxm-publish release` (spec §5.2): publishes a build to a rolling GitHub release.
--
-- Order of operations, chosen so a consumer polling mid-publish only ever sees something it
-- already refuses safely (a missing asset, or a build.json whose hash doesn't match):
--   1. Verify the build locally and check its ref is allowed. No network before this.
--   2. If the channel's tag already points at a newer commit, skip (an older run finished late).
--   3. Get or create the release; upload both files under temporary names.
--   4. For each file: delete the old asset, rename the new one into place.
--   5. Update the release body, then move the tag, so the tag reflects what's published.

local crypto = require("@lute/crypto")
local fs = require("@std/fs")
local pathlib = require("@std/path")

local github = require("./github")
local manifest = require("./manifest")

export type Options = {
	dir: string,
	channel: string,
	allowedRefs: { string },
	client: github.Client,
	log: ((string) -> ())?,
}

export type Result = {
	published: boolean,
	reason: string?,
	releaseUrl: string?,
	manifest: manifest.Manifest,
}

local UPLOADING_SUFFIX = ".uploading"

local release = {}

export type LoadedBuild = { manifest: manifest.Manifest, artifact: string, manifestSource: string }

-- Reads build/ and checks managed.rbxm against build.json.
function release.loadBuild(dir: string): LoadedBuild
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
	return { manifest = m, artifact = artifact, manifestSource = manifestSource }
end

function release.validateChannel(channel: string)
	if
		channel == ""
		or not string.match(channel, "^[%w%-%._/]+$")
		or string.sub(channel, 1, 5) == "refs/"
		or string.find(channel, "..", 1, true)
		or string.sub(channel, 1, 1) == "/"
		or string.sub(channel, -1) == "/"
	then
		error(`channel '{channel}' is not a valid tag name (e.g. dev-latest)`, 0)
	end
end

function release.body(channel: string, m: manifest.Manifest): string
	return table.concat({
		`Rolling channel \`{channel}\`, published by rbxm-publish. Its assets are replaced on every publish.`,
		"",
		`- Commit: {m.commit}`,
		`- Ref: {m.ref}`,
		`- Built: {m.builtAt}`,
		"",
	}, "\n")
end

function release.run(options: Options): Result
	local log = options.log or function(_: string) end
	release.validateChannel(options.channel)
	if #options.allowedRefs == 0 then
		error("at least one --allowed-ref is required", 0)
	end

	local build = release.loadBuild(options.dir)
	local m = build.manifest
	if not table.find(options.allowedRefs, m.ref) then
		error(`refusing to release a build of '{m.ref}': allowed refs are {table.concat(options.allowedRefs, ", ")}`, 0)
	end

	local client = options.client
	local channel = options.channel

	-- Never move the channel backwards.
	local published = client:getTagCommit(channel)
	if published and published ~= m.commit then
		local relation = client:compare(published, m.commit)
		if relation == "behind" then
			local reason = `{channel} already has {published}, which is newer than {m.commit}`
			log(`skipping: {reason}`)
			return { published = false, reason = reason, manifest = m }
		elseif relation == "diverged" then
			log(`warning: {m.commit} is not a descendant of {published} (history rewritten?); publishing anyway`)
		elseif relation == nil then
			log(`warning: GitHub can't compare {published} with {m.commit}; publishing anyway`)
		end
	end

	local body = release.body(channel, m)
	local target = client:getReleaseByTag(channel)
	if target == nil then
		if published == nil then
			log(`creating tag {channel} at {m.commit}`)
			client:createTag(channel, m.commit)
			published = m.commit
		end
		log(`creating release {channel}`)
		target = client:createRelease(channel, channel, body)
	end
	local rel = target :: github.Release

	local files = {
		{ name = manifest.ARTIFACT_NAME, contents = build.artifact, contentType = "application/octet-stream" },
		{ name = manifest.MANIFEST_NAME, contents = build.manifestSource, contentType = "application/json" },
	}

	-- Clear temporary assets left by an interrupted run.
	for _, asset in rel.assets do
		for _, file in files do
			if asset.name == file.name .. UPLOADING_SUFFIX then
				client:deleteAsset(asset.id)
			end
		end
	end

	local uploaded: { [string]: github.Asset } = {}
	for _, file in files do
		log(`uploading {file.name} ({#file.contents} bytes)`)
		uploaded[file.name] = client:uploadAsset(rel, file.name .. UPLOADING_SUFFIX, file.contents, file.contentType)
	end

	for _, file in files do
		for _, asset in rel.assets do
			if asset.name == file.name then
				client:deleteAsset(asset.id)
			end
		end
		client:renameAsset(uploaded[file.name].id, file.name)
	end

	client:updateRelease(rel.id, channel, body)
	if published ~= m.commit then
		log(`moving tag {channel} to {m.commit}`)
		client:moveTag(channel, m.commit)
	end

	return { published = true, releaseUrl = rel.htmlUrl, manifest = m }
end

return release
