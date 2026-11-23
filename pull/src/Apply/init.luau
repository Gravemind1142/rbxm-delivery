--!strict
-- Applies a build to a place (spec §7). Plain Luau with no plugin dependencies, so both the
-- plugin and a Luau Execution task can require it; this folder is self-contained.
--
--   Apply.apply(dataModel, rbxm, manifest, options) -> Result
--
-- Steps (spec §7.1):
--   1. Verify the artifact's size and SHA-256 against the manifest.
--   2. Deserialize; the root must be the RbxmDeliveryBuild folder holding exactly the
--      manifest's containers.
--   3. Resolve every target parent. Nothing has changed if any of this fails.
--   4. Remove everything at the old and new container paths, insert the new containers and
--      write the marker, inside one ChangeHistoryService recording when `changeHistory` is
--      set. An error here cancels the recording so Studio rolls the partial change back.
--      Inside a recording, removal is `Parent = nil`: a cancelled recording restores those,
--      but not instances removed with Destroy().

local SerializationService = game:GetService("SerializationService")

local Manifest = require(script.Manifest)
local Marker = require(script.Marker)
local Paths = require(script.Paths)
local Sha256 = require(script.Sha256)

export type Manifest = Manifest.Manifest

export type Options = {
	-- Check everything and report what would change, without changing anything.
	dryRun: boolean?,
	-- Wrap the change in a ChangeHistoryService recording (plugins only).
	changeHistory: boolean?,
	-- User ID recorded as the marker's AppliedBy.
	appliedBy: number?,
	-- Called as each step of the change starts ("destroy", "insert", "marker"). An error it
	-- raises aborts the apply like any other; tests use this to check rollback.
	onStep: ((step: string) -> ())?,
}

export type Result = {
	commit: string,
	-- Container paths that existed and were replaced, were new, or were dropped.
	replaced: { string },
	added: { string },
	removed: { string },
	dryRun: boolean,
}

local ROOT_NAME = "RbxmDeliveryBuild"

local Apply = {}

Apply.PROTOCOL = Marker.PROTOCOL
Apply.Manifest = Manifest
Apply.Marker = Marker
Apply.Sha256 = Sha256

-- Step 1. Errors if `rbxm` isn't the artifact the manifest describes.
function Apply.verify(rbxm: buffer, manifest: Manifest)
	if buffer.len(rbxm) ~= manifest.artifact.size then
		error(`managed.rbxm is {buffer.len(rbxm)} bytes but build.json says {manifest.artifact.size}`, 0)
	end
	local sha256 = Sha256.hex(rbxm)
	if sha256 ~= manifest.artifact.sha256 then
		error(`managed.rbxm has sha256 {sha256} but build.json says {manifest.artifact.sha256}`, 0)
	end
end

-- Step 2. Returns the build's containers, keyed by path.
function Apply.deserialize(rbxm: buffer, manifest: Manifest): { [string]: Instance }
	local ok, roots = pcall(function()
		return SerializationService:DeserializeInstancesAsync(rbxm)
	end)
	if not ok then
		error(`managed.rbxm couldn't be read: {roots}`, 0)
	end
	if #roots ~= 1 or roots[1].Name ~= ROOT_NAME or not roots[1]:IsA("Folder") then
		error(`managed.rbxm must hold a single Folder named {ROOT_NAME}`, 0)
	end

	local containers: { [string]: Instance } = {}
	for _, child in roots[1]:GetChildren() do
		if containers[child.Name] then
			error(`managed.rbxm has two containers named '{child.Name}'`, 0)
		end
		containers[child.Name] = child
	end
	for _, path in manifest.containers do
		if containers[path] == nil then
			error(`managed.rbxm is missing container '{path}'`, 0)
		end
	end
	if #roots[1]:GetChildren() ~= #manifest.containers then
		error("managed.rbxm has containers that build.json doesn't list", 0)
	end
	return containers
end

function Apply.apply(dataModel: Instance, rbxm: buffer, manifest: Manifest, options: Options?): Result
	local opts: Options = options or {}

	-- Refuse to write a marker a newer plugin owns (spec §6.6).
	local existingMarker = Marker.find(dataModel)
	local previous = if existingMarker then Marker.read(existingMarker) else nil
	if previous and not Marker.canWrite(previous) then
		error(
			`this place was last synced with protocol {previous.protocol}, but this rbxm-pull `
				.. `supports {Marker.PROTOCOL}; update rbxm-pull`,
			0
		)
	end

	-- Steps 1-3: nothing changes in the place before all of these pass.
	Apply.verify(rbxm, manifest)
	local containers = Apply.deserialize(rbxm, manifest)

	local parents: { [string]: Instance } = {}
	for _, path in manifest.containers do
		local parent = Paths.resolveParent(dataModel, path)
		if parent == nil then
			error(`can't apply: the parent of container '{path}' doesn't exist in this place`, 0)
		end
		parents[path] = parent
	end

	-- Everything at a new path, and at old paths this build dropped, is destroyed.
	local inBuild: { [string]: boolean } = {}
	for _, path in manifest.containers do
		inBuild[path] = true
	end
	local doomed: { Instance } = {}
	local result: Result = {
		commit = manifest.commit,
		replaced = {},
		added = {},
		removed = {},
		dryRun = opts.dryRun == true,
	}
	for _, path in manifest.containers do
		local existing = Paths.childrenNamed(parents[path], Paths.leaf(path))
		table.move(existing, 1, #existing, #doomed + 1, doomed)
		table.insert(if #existing > 0 then result.replaced else result.added, path)
	end
	if previous then
		for _, path in previous.containers do
			if not inBuild[path] then
				local ok, parent = pcall(Paths.resolveParent, dataModel, path)
				local existing = if ok and parent then Paths.childrenNamed(parent, Paths.leaf(path)) else {}
				if #existing > 0 then
					table.move(existing, 1, #existing, #doomed + 1, doomed)
					table.insert(result.removed, path)
				end
			end
		end
	end

	if opts.dryRun then
		for _, container in containers do
			container:Destroy()
		end
		return result
	end

	-- Step 4.
	local ChangeHistoryService = game:GetService("ChangeHistoryService")
	local recording: string? = nil
	if opts.changeHistory then
		recording = ChangeHistoryService:TryBeginRecording("rbxm-pull: apply " .. string.sub(manifest.commit, 1, 7))
		if recording == nil then
			error("can't apply: Studio didn't allow a change history recording (another is in progress?)", 0)
		end
	end

	local ok, err = pcall(function()
		if opts.onStep then
			opts.onStep("destroy")
		end
		for _, instance in doomed do
			-- Cancelling a recording restores instances parented to nil (as Studio's own Delete
			-- does) but not Destroy()ed ones, so only destroy when there's nothing to roll back.
			if recording then
				instance.Parent = nil
			else
				instance:Destroy()
			end
		end

		if opts.onStep then
			opts.onStep("insert")
		end
		for _, path in manifest.containers do
			local container = containers[path]
			container.Name = Paths.leaf(path)
			container.Parent = parents[path]
		end

		if opts.onStep then
			opts.onStep("marker")
		end
		Marker.writeApplied(Marker.findOrCreate(dataModel), {
			commit = manifest.commit,
			schemaVersion = manifest.schemaVersion,
			appliedAt = DateTime.now():ToIsoDate(),
			appliedBy = opts.appliedBy or 0,
			containers = manifest.containers,
		})
	end)

	if recording then
		ChangeHistoryService:FinishRecording(
			recording,
			if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel
		)
	end
	if not ok then
		error(`apply failed{if recording then " and was rolled back" else ""}: {err}`, 0)
	end
	return result
end

return Apply
