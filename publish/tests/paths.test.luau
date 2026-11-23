local test = require("@std/test")
local paths = require("../src/paths")

test.case("splits instance paths", function(check)
	local segments = paths.split("ReplicatedStorage/Systems/Combat")
	check.eq(#segments, 3)
	check.eq(segments[3], "Combat")
end)

test.case("rejects empty segments", function(check)
	check.eq(pcall(paths.split, ""), false)
	check.eq(pcall(paths.split, "ReplicatedStorage//Systems"), false)
	check.eq(pcall(paths.split, "/ReplicatedStorage"), false)
end)

test.case("accepts disjoint containers sharing a leaf name", function(check)
	local split = paths.checkContainers({ "ReplicatedStorage/Systems", "ServerScriptService/Systems" })
	check.eq(#split, 2)
end)

test.case("rejects containers that are services", function(check)
	check.eq(pcall(paths.checkContainers, { "ReplicatedStorage" }), false)
end)

test.case("rejects duplicate and nested containers", function(check)
	check.eq(pcall(paths.checkContainers, { "ReplicatedStorage/A", "ReplicatedStorage/A" }), false)
	check.eq(pcall(paths.checkContainers, { "ReplicatedStorage/A", "ReplicatedStorage/A/B" }), false)
	check.eq(pcall(paths.checkContainers, { "ReplicatedStorage/A/B", "ReplicatedStorage/A" }), false)
	-- A shared name prefix is not nesting.
	check.eq(pcall(paths.checkContainers, { "ReplicatedStorage/A", "ReplicatedStorage/AB" }), true)
end)
