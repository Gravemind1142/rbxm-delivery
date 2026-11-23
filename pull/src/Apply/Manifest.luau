--!strict
-- build.json, schema version 1 (spec §4.2): decoding and validation.

local HttpService = game:GetService("HttpService")

export type Manifest = {
	schemaVersion: number,
	commit: string,
	ref: string,
	builtAt: string,
	artifact: { size: number, sha256: string },
	containers: { string },
}

local Manifest = {}

Manifest.SCHEMA_VERSION = 1

-- The error prefix used when a build needs a newer plugin, so callers can tell it apart.
Manifest.UNKNOWN_SCHEMA = "unknown build.json schemaVersion"

local function str(value: any, field: string): string
	if typeof(value) ~= "string" or value == "" then
		error(`build.json '{field}' must be a non-empty string`, 0)
	end
	return value
end

-- Validates an already-decoded build.json table.
function Manifest.validate(object: any): Manifest
	if typeof(object) ~= "table" then
		error("build.json is not a JSON object", 0)
	end
	if object.schemaVersion ~= Manifest.SCHEMA_VERSION then
		error(`{Manifest.UNKNOWN_SCHEMA} {object.schemaVersion}; this plugin supports 1`, 0)
	end

	local artifact = object.artifact
	if typeof(artifact) ~= "table" or typeof(artifact.size) ~= "number" then
		error("build.json 'artifact' must have a numeric 'size' and a 'sha256'", 0)
	end
	local sha256 = string.lower(str(artifact.sha256, "artifact.sha256"))
	if #sha256 ~= 64 or not string.match(sha256, "^%x+$") then
		error("build.json 'artifact.sha256' must be 64 hex digits", 0)
	end

	if typeof(object.containers) ~= "table" or #object.containers == 0 then
		error("build.json 'containers' must be a non-empty array", 0)
	end
	local containers = {}
	local seen = {}
	for i, container in object.containers do
		local path = str(container, `containers[{i}]`)
		if seen[path] then
			error(`build.json lists container '{path}' twice`, 0)
		end
		seen[path] = true
		table.insert(containers, path)
	end

	return {
		schemaVersion = Manifest.SCHEMA_VERSION,
		commit = str(object.commit, "commit"),
		ref = str(object.ref, "ref"),
		builtAt = str(object.builtAt, "builtAt"),
		artifact = { size = artifact.size, sha256 = sha256 },
		containers = containers,
	}
end

function Manifest.decode(json: string): Manifest
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, json)
	if not ok then
		error("build.json is not valid JSON", 0)
	end
	return Manifest.validate(decoded)
end

return Manifest
