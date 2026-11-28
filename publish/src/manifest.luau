--!strict
-- build.json, schema version 1 (spec §4.2).

local json = require("@std/json")

export type Manifest = {
	schemaVersion: number,
	commit: string,
	ref: string,
	builtAt: string,
	artifact: { size: number, sha256: string },
	containers: { string },
}

local manifest = {}

manifest.SCHEMA_VERSION = 1
manifest.ARTIFACT_NAME = "managed.rbxm"
manifest.MANIFEST_NAME = "build.json"

function manifest.hex(digest: buffer): string
	local parts = table.create(buffer.len(digest))
	for i = 0, buffer.len(digest) - 1 do
		parts[i + 1] = string.format("%02x", buffer.readu8(digest, i))
	end
	return table.concat(parts)
end

-- Encodes with a fixed key order so build.json is easy to read and diff.
function manifest.encode(m: Manifest): string
	local s = json.serialize
	local containers = {}
	for _, container in m.containers do
		table.insert(containers, `    {s(container)}`)
	end
	return table.concat({
		"{",
		`  "schemaVersion": {m.schemaVersion},`,
		`  "commit": {s(m.commit)},`,
		`  "ref": {s(m.ref)},`,
		`  "builtAt": {s(m.builtAt)},`,
		`  "artifact": \{ "size": {m.artifact.size}, "sha256": {s(m.artifact.sha256)} },`,
		`  "containers": [`,
		table.concat(containers, ",\n"),
		"  ]",
		"}",
		"",
	}, "\n")
end

-- Parses and validates build.json. Refuses schema versions this tool doesn't know.
function manifest.decode(source: string): Manifest
	local ok, decoded = pcall(json.deserialize, source)
	local object = if ok then json.asObject(decoded) else nil
	if object == nil then
		error("build.json is not a JSON object", 0)
	end
	if object.schemaVersion ~= manifest.SCHEMA_VERSION then
		error(`build.json has schemaVersion {object.schemaVersion}; this rbxm-publish supports only 1`, 0)
	end

	local function str(value: json.Value, field: string): string
		if typeof(value) ~= "string" or value == "" then
			error(`build.json '{field}' must be a non-empty string`, 0)
		end
		return value
	end

	local artifact = json.asObject(object.artifact)
	if artifact == nil or typeof(artifact.size) ~= "number" then
		error("build.json 'artifact' must have a numeric 'size' and a 'sha256'", 0)
	end
	local sha256 = str(artifact.sha256, "artifact.sha256")
	if #sha256 ~= 64 or not string.match(sha256, "^%x+$") then
		error("build.json 'artifact.sha256' must be 64 hex digits", 0)
	end

	local containers: { string } = {}
	local seen: { [string]: boolean } = {}
	for i, value in json.asArray(object.containers) or {} do
		local path = str(value, `containers[{i}]`)
		if seen[path] then
			error(`build.json lists container '{path}' twice`, 0)
		end
		seen[path] = true
		table.insert(containers, path)
	end
	if #containers == 0 then
		error("build.json 'containers' must be a non-empty array", 0)
	end
	-- Same checks as rbxm-pull's Apply: a container inside another would be replaced twice.
	for _, outer in containers do
		for _, inner in containers do
			if string.sub(inner, 1, #outer + 1) == outer .. "/" then
				error(`build.json containers '{outer}' and '{inner}' overlap`, 0)
			end
		end
	end

	return {
		schemaVersion = manifest.SCHEMA_VERSION,
		commit = str(object.commit, "commit"),
		ref = str(object.ref, "ref"),
		builtAt = str(object.builtAt, "builtAt"),
		artifact = { size = artifact.size :: number, sha256 = string.lower(sha256) },
		containers = containers,
	}
end

return manifest
