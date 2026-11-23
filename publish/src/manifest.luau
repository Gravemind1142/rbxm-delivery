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

return manifest
