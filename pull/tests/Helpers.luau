--!strict
-- Shared test helpers (not a spec).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SerializationService = game:GetService("SerializationService")
local ServerStorage = game:GetService("ServerStorage")

local Apply = require(ReplicatedStorage.RbxmPull.Apply)
local Paths = require(ReplicatedStorage.RbxmPull.Apply.Paths)

local Helpers = {}

Helpers.COMMIT = string.rep("a", 40)

-- Builds an artifact like rbxm-publish's: a RbxmDeliveryBuild folder whose children are named
-- by container path. `containers` maps each path to a function that fills a fresh Folder.
function Helpers.build(
	containers: { { path: string, fill: ((Folder) -> ())? } },
	commit: string?
): (buffer, Apply.Manifest)
	local root = Instance.new("Folder")
	root.Name = "RbxmDeliveryBuild"
	local paths = {}
	for _, container in containers do
		local folder = Instance.new("Folder")
		folder.Name = container.path
		if container.fill then
			container.fill(folder)
		end
		folder.Parent = root
		table.insert(paths, container.path)
	end
	local rbxm = SerializationService:SerializeInstancesAsync({ root })
	root:Destroy()
	return rbxm,
		{
			schemaVersion = 1,
			commit = commit or Helpers.COMMIT,
			ref = "refs/heads/main",
			builtAt = "2026-11-22T10:15:00Z",
			artifact = { size = buffer.len(rbxm), sha256 = Apply.Sha256.hex(rbxm) },
			containers = paths,
		}
end

function Helpers.module(parent: Instance, name: string, source: string): ModuleScript
	local module = Instance.new("ModuleScript")
	module.Name = name
	module.Source = source
	module.Parent = parent
	return module
end

-- Instances tests create in services; removed after each test.
local created: { Instance } = {}

function Helpers.track<T>(instance: T & Instance): T
	table.insert(created, instance)
	return instance
end

function Helpers.folder(parent: Instance, name: string): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return Helpers.track(folder)
end

-- Removes the marker and everything at the given paths, plus tracked instances.
function Helpers.cleanup(paths: { string }?)
	local marker = ServerStorage:FindFirstChild("RbxmPull")
	if marker then
		marker:Destroy()
	end
	for _, path in paths or {} do
		local ok, parent = pcall(Paths.resolveParent, game, path)
		if ok and parent then
			for _, child in Paths.childrenNamed(parent, Paths.leaf(path)) do
				child:Destroy()
			end
		end
	end
	for _, instance in created do
		instance:Destroy()
	end
	table.clear(created)
end

return Helpers
