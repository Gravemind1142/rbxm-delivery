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
