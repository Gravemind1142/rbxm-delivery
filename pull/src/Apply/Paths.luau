--!strict
-- Container paths such as "ReplicatedStorage/Systems" (spec §3), resolved in a DataModel.

local Paths = {}

function Paths.split(path: string): { string }
	local segments = string.split(path, "/")
	for _, segment in segments do
		if segment == "" then
			error(`invalid container path '{path}'`, 0)
		end
	end
	if #segments < 2 then
		error(`container path '{path}' must be inside a service`, 0)
	end
	return segments
end

function Paths.leaf(path: string): string
	local segments = Paths.split(path)
	return segments[#segments]
end

-- The instance a container path's parent refers to: the service named by the first segment,
-- then one child per segment except the leaf. Returns nil if any of it is missing, and errors
-- if a segment is ambiguous (two children with that name).
function Paths.resolveParent(dataModel: Instance, path: string): Instance?
	local segments = Paths.split(path)
	local current: Instance? = dataModel:FindFirstChild(segments[1])
	if current == nil then
		local ok, service = pcall(function()
			return (dataModel :: any):GetService(segments[1])
		end)
		current = if ok then service else nil
	end

	for i = 2, #segments - 1 do
		if current == nil then
			return nil
		end
		local matches = {}
		for _, child in (current :: Instance):GetChildren() do
			if child.Name == segments[i] then
				table.insert(matches, child)
			end
		end
		if #matches > 1 then
			error(`'{table.concat(segments, "/", 1, i)}' is ambiguous: {#matches} instances have that path`, 0)
		end
		current = matches[1]
	end
	return current
end

-- Every child of `parent` named `name`.
function Paths.childrenNamed(parent: Instance, name: string): { Instance }
	local matches = {}
	for _, child in parent:GetChildren() do
		if child.Name == name then
			table.insert(matches, child)
		end
	end
	return matches
end

return Paths
