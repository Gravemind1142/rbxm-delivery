--!strict
-- Resolves container paths against a Rojo project tree (spec §5.1).
--
-- A path is walked through the project's explicit nodes. Where a segment isn't an explicit
-- node, the rest of the path is looked up on disk under the nearest node's `$path`, using
-- Rojo's file-name rules to map files to instance names.

local fs = require("@std/fs")
local json = require("@std/json")
local pathlib = require("@std/path")

export type Node = json.Object

-- Suffixes Rojo strips to get an instance name, longest first so ".server.luau" wins over
-- ".luau". `.meta.json` files describe a sibling and are not instances.
local NON_INSTANCE_SUFFIXES = { ".meta.json", ".meta.jsonc" }
local INSTANCE_SUFFIXES = {
	".server.luau",
	".client.luau",
	".plugin.luau",
	".local.luau",
	".legacy.luau",
	".server.lua",
	".client.lua",
	".project.jsonc",
	".project.json",
	".model.jsonc",
	".model.json",
	".jsonc",
	".json",
	".rbxmx",
	".rbxm",
	".luau",
	".lua",
	".toml",
	".yaml",
	".yml",
	".txt",
	".csv",
}

local resolve = {}

local function hasSuffix(s: string, suffix: string): boolean
	return #s > #suffix and string.sub(s, -#suffix) == suffix
end

-- The instance name Rojo gives a directory entry, or nil if it doesn't become an instance.
function resolve.instanceName(entryName: string, isDirectory: boolean): string?
	if isDirectory then
		return entryName
	end
	for _, suffix in NON_INSTANCE_SUFFIXES do
		if hasSuffix(entryName, suffix) then
			return nil
		end
	end
	for _, suffix in INSTANCE_SUFFIXES do
		if hasSuffix(entryName, suffix) then
			return string.sub(entryName, 1, -#suffix - 1)
		end
	end
	return nil
end

export type Entry = { name: string, isDirectory: boolean }

-- Every entry in `dir` that Rojo would turn into an instance called `name`.
function resolve.matchingEntries(dir: string, name: string): { Entry }
	local matches: { Entry } = {}
	for _, entry in fs.listDirectory(dir) do
		local isDirectory = entry.type == "dir"
		if resolve.instanceName(entry.name, isDirectory) == name then
			table.insert(matches, { name = entry.name, isDirectory = isDirectory })
		end
	end
	return matches
end

-- The `$path` of a project node, if it has one.
function resolve.nodePath(node: Node): string?
	local value = node["$path"]
	if typeof(value) == "string" then
		return value
	end
	local object = if value == nil then nil else json.asObject(value)
	if object and typeof(object.optional) == "string" then
		return object.optional :: string
	end
	return nil
end

-- Joins a project-relative path and a child name with forward slashes.
function resolve.joinRelative(base: string, name: string): string
	base = string.gsub(base, "[/\\]+$", "")
	return if base == "" or base == "." then name else `{base}/{name}`
end

local function isDirectory(path: string): boolean
	return fs.exists(path) and fs.type(path) == "dir"
end

local function deepCopy(value: any): any
	if typeof(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

-- Resolves one container. `projectDir` is the directory holding the project file and `tree`
-- its root node. Returns a standalone copy of the node to place in the generated project.
function resolve.container(projectDir: string, tree: Node, segments: { string }): Node
	local display = table.concat(segments, "/")
	local node = tree
	for i, segment in segments do
		local child = node[segment]
		local childNode = if child == nil or string.sub(segment, 1, 1) == "$" then nil else json.asObject(child)
		if childNode then
			node = childNode
			continue
		end

		local base = resolve.nodePath(node)
		if base == nil then
			local parent = table.concat(segments, "/", 1, i - 1)
			error(
				`container '{display}': '{segment}' is not a node under '{parent}' in the project, `
					.. "and that node has no $path to look it up on disk",
				0
			)
		end

		-- Walk the rest of the path on disk.
		local relative = base
		for j = i, #segments do
			local dir = pathlib.format(pathlib.join(projectDir, relative))
			if not isDirectory(dir) then
				error(`container '{display}': '{relative}' is not a directory`, 0)
			end
			local matches = resolve.matchingEntries(dir, segments[j])
			if #matches == 0 then
				error(`container '{display}': no file or folder for '{segments[j]}' in '{relative}'`, 0)
			elseif #matches > 1 then
				local names = {}
				for _, match in matches do
					table.insert(names, match.name)
				end
				error(
					`container '{display}': '{segments[j]}' is ambiguous in '{relative}' ({table.concat(names, ", ")})`,
					0
				)
			end
			if j < #segments and not matches[1].isDirectory then
				error(`container '{display}': '{segments[j]}' in '{relative}' is not a folder`, 0)
			end
			relative = resolve.joinRelative(relative, matches[1].name)
		end
		return json.object({ ["$path"] = relative })
	end
	return deepCopy(node)
end

return resolve
