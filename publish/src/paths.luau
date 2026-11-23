--!strict
-- Instance paths such as "ReplicatedStorage/Systems" (spec §3).

local paths = {}

-- Splits an instance path into its segments. Errors if the path is malformed.
function paths.split(path: string): { string }
	if path == "" then
		error("instance path is empty", 0)
	end
	local segments = string.split(path, "/")
	for _, segment in segments do
		if segment == "" then
			error(`invalid instance path '{path}': empty segment`, 0)
		end
	end
	return segments
end

-- True if `prefix` is `path` itself or one of its ancestors.
function paths.isPrefix(prefix: { string }, path: { string }): boolean
	if #prefix > #path then
		return false
	end
	for i, segment in prefix do
		if path[i] ~= segment then
			return false
		end
	end
	return true
end

-- Validates the configured containers: each must sit below a service, and no two may be
-- equal or nested inside one another. Returns the split paths, in order.
function paths.checkContainers(containers: { string }): { { string } }
	local split: { { string } } = {}
	for i, container in containers do
		local segments = paths.split(container)
		if #segments < 2 then
			error(`container '{container}' must be inside a service, e.g. 'ReplicatedStorage/{container}'`, 0)
		end
		for j = 1, i - 1 do
			if paths.isPrefix(split[j], segments) or paths.isPrefix(segments, split[j]) then
				error(`containers '{containers[j]}' and '{container}' overlap`, 0)
			end
		end
		split[i] = segments
	end
	return split
end

return paths
