--!strict
-- Loads rbxm-publish.json (spec §5.1).

local fs = require("@std/fs")
local json = require("@std/json")
local pathlib = require("@std/path")

export type Config = {
	-- Path to the Rojo project, relative to the working directory.
	project: string,
	containers: { string },
	buildInfoModule: string?,
}

local KNOWN_KEYS = {
	["$schema"] = true,
	project = true,
	containers = true,
	buildInfoModule = true,
}

local config = {}

-- Parses config JSON. `dir` is the directory the config file is in; `project` is resolved
-- against it.
function config.parse(source: string, dir: string): Config
	local ok, decoded = pcall(json.deserialize, source)
	if not ok then
		error(`config is not valid JSON: {decoded}`, 0)
	end
	local object = json.asObject(decoded)
	if object == nil then
		error("config must be a JSON object", 0)
	end

	for key in object do
		if typeof(key) == "string" and not KNOWN_KEYS[key] then
			error(`config has unknown key '{key}'`, 0)
		end
	end

	local project = object.project
	if project == nil then
		project = "default.project.json"
	elseif typeof(project) ~= "string" then
		error("config 'project' must be a string", 0)
	end

	local containersValue = object.containers
	local containersArray = if containersValue == nil then nil else json.asArray(containersValue)
	if containersArray == nil or #containersArray == 0 then
		error("config 'containers' must be a non-empty array of instance paths", 0)
	end
	local containers: { string } = {}
	for i, container in containersArray do
		if typeof(container) ~= "string" then
			error(`config 'containers[{i}]' must be a string`, 0)
		end
		table.insert(containers, container)
	end

	local buildInfoModule = object.buildInfoModule
	if buildInfoModule ~= nil and typeof(buildInfoModule) ~= "string" then
		error("config 'buildInfoModule' must be a string", 0)
	end

	return {
		project = pathlib.format(pathlib.join(dir, project :: string)),
		containers = containers,
		buildInfoModule = buildInfoModule :: string?,
	}
end

function config.load(path: string): Config
	if not fs.exists(path) then
		error(`config file '{path}' not found`, 0)
	end
	return config.parse(fs.readFileToString(path), pathlib.dirname(path))
end

return config
