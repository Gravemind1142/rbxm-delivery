local json = require("@std/json")
local test = require("@std/test")
local manifest = require("../src/manifest")

test.case("hex-encodes digests", function(check)
	local b = buffer.create(3)
	buffer.writeu8(b, 0, 0x00)
	buffer.writeu8(b, 1, 0xab)
	buffer.writeu8(b, 2, 0x0f)
	check.eq(manifest.hex(b), "00ab0f")
end)

local VALID = {
	schemaVersion = 1,
	commit = string.rep("a", 40),
	ref = "refs/heads/main",
	builtAt = "2026-11-22T10:15:00Z",
	artifact = { size = 123, sha256 = string.rep("A", 64) },
	containers = { "ReplicatedStorage/Systems" },
}

test.case("decodes what it encodes", function(check)
	local decoded = manifest.decode(manifest.encode(VALID))
	check.eq(decoded.commit, VALID.commit)
	check.eq(decoded.artifact.size, 123)
	check.eq(decoded.artifact.sha256, string.rep("a", 64))
	check.eq(decoded.containers[1], "ReplicatedStorage/Systems")
end)

test.case("decode refuses unknown schema versions and malformed fields", function(check)
	local function fails(source: string, needle: string)
		local ok, err = pcall(manifest.decode, source)
		check.eq(ok, false)
		check.eq(string.find(tostring(err), needle, 1, true) ~= nil, true)
	end
	local encoded = manifest.encode(VALID)
	fails(string.gsub(encoded, '"schemaVersion": 1', '"schemaVersion": 2'), "supports only 1")
	fails(string.gsub(encoded, '"commit": "a+"', '"commit": ""'), "'commit'")
	fails(string.gsub(encoded, '"sha256": "A+"', '"sha256": "xyz"'), "64 hex digits")
	fails(string.gsub(encoded, '"ReplicatedStorage/Systems"', ""), "'containers'")
	fails("[]", "JSON object")
end)

test.case("decode refuses duplicate and overlapping containers", function(check)
	local function containersFail(containers: { string }, needle: string)
		local m = table.clone(VALID)
		m.containers = containers
		local ok, err = pcall(manifest.decode, manifest.encode(m))
		check.eq(ok, false)
		check.eq(string.find(tostring(err), needle, 1, true) ~= nil, true)
	end
	containersFail({ "ReplicatedStorage/Systems", "ReplicatedStorage/Systems" }, "twice")
	containersFail(
		{ "ReplicatedStorage/Systems/Sub", "ReplicatedStorage/Systems" },
		"containers 'ReplicatedStorage/Systems' and 'ReplicatedStorage/Systems/Sub' overlap"
	)

	-- A shared prefix that isn't a parent is fine.
	local m = table.clone(VALID)
	m.containers = { "ReplicatedStorage/Systems", "ReplicatedStorage/SystemsExtra" }
	check.eq(#manifest.decode(manifest.encode(m)).containers, 2)
end)

test.case("encodes valid build.json in a fixed order", function(check)
	local encoded = manifest.encode({
		schemaVersion = 1,
		commit = string.rep("a", 40),
		ref = "refs/heads/main",
		builtAt = "2026-11-22T10:15:00Z",
		artifact = { size = 123, sha256 = string.rep("0", 64) },
		containers = { "ReplicatedStorage/Systems", 'Quoted/"name"' },
	})
	local decoded = json.asObject(json.deserialize(encoded))
	assert(decoded)
	check.eq(decoded.schemaVersion, 1)
	check.eq(decoded.ref, "refs/heads/main")
	local artifact = json.asObject(decoded.artifact) :: json.Object
	check.eq(artifact.size, 123)
	local containers = json.asArray(decoded.containers) :: json.Array
	check.eq(containers[2], 'Quoted/"name"')
	check.eq(string.find(encoded, '"schemaVersion"', 1, true) < string.find(encoded, '"commit"', 1, true), true)
end)
