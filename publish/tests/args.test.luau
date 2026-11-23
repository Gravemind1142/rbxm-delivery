local test = require("@std/test")
local args = require("../src/args")

test.case("parses build flags", function(check)
	local parsed, err = args.parse({ "build", "--config", "rbxm-publish.json", "--out", "build/" })
	check.eq(err, nil)
	assert(parsed)
	check.eq(parsed.command, "build")
	check.eq(parsed.flags.config[1], "rbxm-publish.json")
	check.eq(parsed.flags.out[1], "build/")
end)

test.case("allows repeated --allowed-ref", function(check)
	local parsed = args.parse({
		"release",
		"--allowed-ref",
		"refs/heads/main",
		"--allowed-ref",
		"refs/heads/dev",
	})
	assert(parsed)
	check.eq(#parsed.flags["allowed-ref"], 2)
end)

test.case("rejects unknown command and flags", function(check)
	local parsed, err = args.parse({ "deploy" })
	check.eq(parsed, nil)
	check.neq(err, nil)

	parsed, err = args.parse({ "build", "--channel", "x" })
	check.eq(parsed, nil)
	check.neq(err, nil)
end)

test.case("rejects a single-valued flag given twice", function(check)
	local parsed = args.parse({ "build", "--out", "a", "--out", "b" })
	check.eq(parsed, nil)
end)
