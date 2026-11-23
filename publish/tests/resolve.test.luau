local json = require("@std/json")
local test = require("@std/test")
local fs = require("@std/fs")
local resolve = require("../src/resolve")

-- Tests run from the repository root.
local FIXTURE = "publish/tests/fixtures/game"

local function loadTree(): json.Object
	local project = json.asObject(json.deserialize(fs.readFileToString(`{FIXTURE}/default.project.json`)))
	assert(project)
	return json.asObject(project.tree) :: json.Object
end

test.case("maps file names to instance names like Rojo", function(check)
	check.eq(resolve.instanceName("Systems", true), "Systems")
	check.eq(resolve.instanceName("Combat.luau", false), "Combat")
	check.eq(resolve.instanceName("Main.server.luau", false), "Main")
	check.eq(resolve.instanceName("Ui.client.lua", false), "Ui")
	check.eq(resolve.instanceName("Map.model.json", false), "Map")
	check.eq(resolve.instanceName("Nested.project.json", false), "Nested")
	check.eq(resolve.instanceName("Data.json", false), "Data")
	check.eq(resolve.instanceName("Asset.rbxm", false), "Asset")
	check.eq(resolve.instanceName("Has.Dots.luau", false), "Has.Dots")
	check.eq(resolve.instanceName("Libraries.meta.json", false), nil)
	check.eq(resolve.instanceName("README.md", false), nil)
end)

test.case("joins relative paths with forward slashes", function(check)
	check.eq(resolve.joinRelative("src/shared", "Systems"), "src/shared/Systems")
	check.eq(resolve.joinRelative("src/shared/", "Systems"), "src/shared/Systems")
	check.eq(resolve.joinRelative(".", "Systems"), "Systems")
end)

test.case("resolves a folder under an ancestor's $path", function(check)
	local node = resolve.container(FIXTURE, loadTree(), { "ReplicatedStorage", "Systems" })
	check.eq(node["$path"], "src/shared/Systems")
end)

test.case("resolves a script file, ignoring its .meta.json", function(check)
	local node = resolve.container(FIXTURE, loadTree(), { "ReplicatedStorage", "Libraries" })
	check.eq(node["$path"], "src/shared/Libraries.luau")
end)

test.case("copies an explicit project node", function(check)
	local tree = loadTree()
	local node = resolve.container(FIXTURE, tree, { "ReplicatedStorage", "Contract" })
	check.eq(node["$path"], "src/contract")
	-- It's a copy: changing it leaves the project tree alone.
	node["$path"] = "changed"
	local original = json.asObject((json.asObject(tree.ReplicatedStorage) :: json.Object).Contract) :: json.Object
	check.eq(original["$path"], "src/contract")
end)

test.case("fails on missing, ambiguous and non-folder paths", function(check)
	local tree = loadTree()
	local function fails(segments: { string }, needle: string)
		local ok, err = pcall(resolve.container, FIXTURE, tree, segments)
		check.eq(ok, false)
		check.eq(string.find(tostring(err), needle, 1, true) ~= nil, true)
	end
	fails({ "ReplicatedStorage", "Missing" }, "no file or folder for 'Missing'")
	fails({ "ReplicatedStorage", "Dup" }, "ambiguous")
	fails({ "ReplicatedStorage", "Libraries", "Inner" }, "not a folder")
	fails({ "Workspace", "Map" }, "is not a node under ''")
end)
