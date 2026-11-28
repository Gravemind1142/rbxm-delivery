--!strict
-- Builds mocked builds and loads Apply's source for the mock tests.

local crypto = require("@lute/crypto")
local json = require("@std/json")
local process = require("@std/process")
local pathlib = require("@std/path")

local Roblox = require("./Roblox")

local Helpers = {}

Helpers.COMMIT = string.rep("c", 40)
Helpers.SHARED = "ReplicatedStorage/Systems"
Helpers.SERVER = "ServerScriptService/Systems"

local APPLY = pathlib.format(pathlib.join(process.cwd(), "pull", "src", "Apply"))

-- A fresh game with Apply loaded into it from pull/src/Apply.
function Helpers.apply(): (any, Roblox.Game)
	local g = Roblox.newGame()
	return Roblox.load(APPLY, g.game), g
end

function Helpers.hex(rbxm: buffer): string
	local digest = crypto.digest(crypto.hash.sha256, buffer.tostring(rbxm))
	local parts = {}
	for i = 0, buffer.len(digest) - 1 do
		table.insert(parts, string.format("%02x", buffer.readu8(digest, i)))
	end
	return table.concat(parts)
end

export type Container = { path: string, children: { Roblox.Tree }? }

-- A mocked managed.rbxm holding `containers`, and its build.json (as a table and as bytes).
function Helpers.build(containers: { Container }, overrides: { [string]: any }?): (buffer, any, buffer)
	local children = {}
	local paths = {}
	for _, container in containers do
		local module =
			{ ClassName = "ModuleScript", Name = "Module", Properties = { Source = `return "{container.path}"` } }
		table.insert(
			children,
			{ ClassName = "Folder", Name = container.path, Children = container.children or { module } }
		)
		table.insert(paths, container.path)
	end
	local rbxm = Roblox.rbxm({ { ClassName = "Folder", Name = "RbxmDeliveryBuild", Children = children } })
	local manifest: { [string]: any } = {
		schemaVersion = 1,
		commit = Helpers.COMMIT,
		ref = "refs/heads/main",
		builtAt = "2026-11-23T10:00:00Z",
		artifact = { size = buffer.len(rbxm), sha256 = Helpers.hex(rbxm) },
		containers = paths,
	}
	for key, value in overrides or {} do
		manifest[key] = value
	end
	return rbxm, manifest, buffer.fromstring(json.serialize(manifest :: any))
end

-- Both containers, the usual build.
function Helpers.buildBoth(): (buffer, any, buffer)
	return Helpers.build({ { path = Helpers.SHARED }, { path = Helpers.SERVER } })
end

-- A folder at `parent`/`name` holding one ModuleScript `Old`.
function Helpers.existing(parent: any, name: string): any
	local folder = Roblox.Instance.new("Folder")
	folder.Name = name
	local old = Roblox.Instance.new("ModuleScript")
	old.Name = "Old"
	old.Source = "return 'old'"
	old:SetAttribute("Edited", true)
	old.Parent = folder
	folder.Parent = parent
	return folder
end

-- Everything under `root` as "path=Class" lines, to compare whole trees.
function Helpers.snapshot(root: any): string
	local lines = {}
	local function walk(instance: any, prefix: string)
		for _, child in instance:GetChildren() do
			local path = `{prefix}/{child.Name}`
			table.insert(lines, `{path}={child.ClassName}`)
			walk(child, path)
		end
	end
	walk(root, "")
	table.sort(lines)
	return table.concat(lines, "\n")
end

-- The error `f` raises, as a string.
function Helpers.errorOf(f: () -> ()): string
	local ok, err = pcall(f)
	assert(not ok, "expected an error")
	return tostring(err)
end

return Helpers
