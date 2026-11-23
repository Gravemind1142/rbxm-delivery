local test = require("@std/test")
local config = require("../src/config")

local function parseError(source: string): string
	local ok, err = pcall(config.parse, source, "repo")
	assert(not ok, "expected config.parse to fail")
	return tostring(err)
end

test.case("parses a full config", function(check)
	local cfg = config.parse(
		[[{
			"project": "game.project.json",
			"containers": ["ReplicatedStorage/Systems"],
			"buildInfoModule": "ReplicatedStorage/Systems/BuildInfo"
		}]],
		"repo"
	)
	check.eq(cfg.containers[1], "ReplicatedStorage/Systems")
	check.eq(cfg.buildInfoModule, "ReplicatedStorage/Systems/BuildInfo")
	check.eq(string.match(cfg.project, "game%.project%.json$") ~= nil, true)
	check.eq(string.match(cfg.project, "^repo[/\\]") ~= nil, true)
end)

test.case("defaults project to default.project.json", function(check)
	local cfg = config.parse([[{ "containers": ["ReplicatedStorage/Systems"] }]], "repo")
	check.eq(string.match(cfg.project, "default%.project%.json$") ~= nil, true)
	check.eq(cfg.buildInfoModule, nil)
end)

test.case("rejects bad configs", function(check)
	check.eq(string.find(parseError("{"), "not valid JSON", 1, true) ~= nil, true)
	check.eq(string.find(parseError("[]"), "JSON object", 1, true) ~= nil, true)
	check.eq(string.find(parseError([[{ "containers": [] }]]), "non-empty", 1, true) ~= nil, true)
	check.eq(string.find(parseError([[{ "containers": [1] }]]), "containers[1]", 1, true) ~= nil, true)
	check.eq(
		string.find(parseError([[{ "containers": ["A/B"], "channel": "dev" }]]), "unknown key 'channel'", 1, true)
			~= nil,
		true
	)
end)
