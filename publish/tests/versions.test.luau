-- rbxm-publish, rbxm-pull and the rbxm-apply package share one version number, released
-- together (the release workflow checks each against the tag). This catches a missed bump on
-- every pull request instead. Run from the repository root.

local fs = require("@std/fs")
local test = require("@std/test")

local version = require("../src/version")
local pkg = require("../../pull/pkg")

local function match(file: string, pattern: string): string?
	return string.match(fs.readFileToString(file), pattern)
end

test.case("every version in the repository matches rbxm-publish's", function(check)
	check.eq(pkg.package.version, version)
	check.eq(match("pull/wally.toml", '\nversion = "([^"]+)"'), version)
	check.eq(match("pull/src/Apply/init.luau", '\nApply%.VERSION = "([^"]+)"'), version)
end)
