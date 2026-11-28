--!strict
-- Applies a build to a place (spec §7). Plain Luau with no plugin dependencies, so both the
-- plugin and a Luau Execution task can require it. This folder is self-contained: its modules
-- only require each other, by path (`@self/...`), so it is also the Lute package `rbxm-apply`
-- (pull/pkg.luau, spec §7.3) that a project uses in its own patch script.
--
--   Apply.apply(dataModel, rbxm, manifest, options) -> Result
--   Apply.record(manifest, result) -> Record   -- what was applied, for a deploy report
--   Apply.rolledBack(message) -> boolean        -- whether a failed apply left the place as it was
--
-- Steps (spec §7.1):
--   1. Verify the artifact's size and SHA-256 against the manifest.
--   2. Deserialize; the root must be the RbxmDeliveryBuild folder holding exactly the
--      manifest's containers.
--   3. Resolve every target parent. Nothing has changed if any of this fails.
--   4. Remove everything at the old and new container paths (with `Parent = nil`), insert
--      the new containers, write the marker and check the result. All or nothing in every
--      host: an error here is rolled back, by cancelling the ChangeHistoryService recording
--      when `changeHistory` is set, otherwise by hand (inserted containers are removed,
--      removed instances go back to their parents and the marker gets its old attributes).
--      Without a recording, removed instances are destroyed only once the apply succeeds.

local SerializationService = game:GetService("SerializationService")

local Manifest = require("@self/Manifest")
local Marker = require("@self/Marker")
local Paths = require("@self/Paths")
local Sha256 = require("@self/Sha256")

export type Manifest = Manifest.Manifest

export type Options = {
	-- Check everything and report what would change, without changing anything.
	dryRun: boolean?,
	-- Wrap the change in a ChangeHistoryService recording (plugins only).
	changeHistory: boolean?,
	-- User ID recorded as the marker's AppliedBy.
	appliedBy: number?,
	-- Called as each step of the change starts ("remove", "insert", "marker", "check"). An
	-- error it raises aborts the apply like any other; tests use this to check rollback.
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

-- What was applied, in a form a deploy report can store as-is. The build fields match
-- `rbxm-publish verify --format json`.
export type Record = {
	applyVersion: string,
	schemaVersion: number,
	commit: string,
	ref: string,
	builtAt: string,
	size: number,
	sha256: string,
	containers: { string },
	replaced: { string },
	added: { string },
	removed: { string },
	dryRun: boolean,
}

local ROOT_NAME = "RbxmDeliveryBuild"

local Apply = {}

-- rbxm-delivery's version, also in pull/pkg.luau. The release workflow refuses a tag that
-- doesn't match it.
Apply.VERSION = "0.1.0"

Apply.PROTOCOL = Marker.PROTOCOL
Apply.Manifest = Manifest
Apply.Marker = Marker
Apply.Paths = Paths
Apply.Sha256 = Sha256

-- Error prefixes, so callers can tell a clean failure from one that left the place changed.
Apply.ROLLED_BACK = "apply failed and was rolled back: "
Apply.NOT_ROLLED_BACK = "apply failed and couldn't be fully rolled back"

-- Whether an error from `Apply.apply` left the place as it was: true for every error except
-- one starting with NOT_ROLLED_BACK. Either way a failed apply's place must not be saved.
function Apply.rolledBack(message: string): boolean
	return string.sub(message, 1, #Apply.NOT_ROLLED_BACK) ~= Apply.NOT_ROLLED_BACK
end

-- What `result` applied from `manifest`, for a deploy report.
function Apply.record(manifest: Manifest, result: Result): Record
	return {
		applyVersion = Apply.VERSION,
		schemaVersion = manifest.schemaVersion,
		commit = manifest.commit,
		ref = manifest.ref,
		builtAt = manifest.builtAt,
		size = manifest.artifact.size,
		sha256 = manifest.artifact.sha256,
		containers = table.clone(manifest.containers),
		replaced = result.replaced,
		added = result.added,
		removed = result.removed,
		dryRun = result.dryRun,
	}
end

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

	-- Refuse to write a marker a newer plugin owns (spec §6.5).
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

	-- Step 4. ChangeHistoryService is only fetched for a recording: hosts without the Plugin
	-- capability (Luau Execution tasks) can't use it.
	local ChangeHistoryService: ChangeHistoryService? = nil
	local recording: string? = nil
	if opts.changeHistory then
		ChangeHistoryService = game:GetService("ChangeHistoryService")
		recording = (ChangeHistoryService :: ChangeHistoryService):TryBeginRecording(
			"rbxm-pull: apply " .. string.sub(manifest.commit, 1, 7)
		)
		if recording == nil then
			error("can't apply: Studio didn't allow a change history recording (another is in progress?)", 0)
		end
	end

	-- What the change did so far, so it can be undone by hand when there's no recording.
	local removed: { { instance: Instance, parent: Instance } } = {}
	local inserted: { Instance } = {}
	local markerBefore = Marker.find(dataModel)
	local markerAttributes = if markerBefore then Marker.snapshotApplied(markerBefore) else nil
	local markerCreated: Instance? = nil

	local ok, err = pcall(function()
		if opts.onStep then
			opts.onStep("remove")
		end
		-- Parent = nil, not Destroy(): a cancelled recording restores instances parented to nil
		-- (as Studio's own Delete does) but not destroyed ones, and the manual rollback needs
		-- them intact too.
		for _, instance in doomed do
			local parent = instance.Parent
			if parent then
				table.insert(removed, { instance = instance, parent = parent })
				instance.Parent = nil
			end
		end

		if opts.onStep then
			opts.onStep("insert")
		end
		for _, path in manifest.containers do
			local container = containers[path]
			container.Name = Paths.leaf(path)
			table.insert(inserted, container)
			container.Parent = parents[path]
		end

		if opts.onStep then
			opts.onStep("marker")
		end
		local marker = Marker.findOrCreate(dataModel)
		if marker ~= markerBefore then
			markerCreated = marker
		end
		Marker.writeApplied(marker, {
			commit = manifest.commit,
			schemaVersion = manifest.schemaVersion,
			appliedAt = DateTime.now():ToIsoDate(),
			appliedBy = opts.appliedBy or 0,
			containers = manifest.containers,
		})

		-- Check the place holds what was asked for before committing to it.
		if opts.onStep then
			opts.onStep("check")
		end
		if Marker.read(marker).commit ~= manifest.commit then
			error(`the marker doesn't record commit {manifest.commit} after writing it`, 0)
		end
		for _, path in manifest.containers do
			local parent = Paths.resolveParent(dataModel, path)
			local found = if parent then Paths.childrenNamed(parent, Paths.leaf(path)) else {}
			if #found ~= 1 or found[1] ~= containers[path] then
				error(`container '{path}' resolves to {#found} instances after inserting it`, 0)
			end
		end
	end)

	if recording then
		(ChangeHistoryService :: ChangeHistoryService):FinishRecording(
			recording,
			if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel
		)
		if not ok then
			error(`{Apply.ROLLED_BACK}{err}`, 0)
		end
		return result
	end

	if ok then
		for _, entry in removed do
			entry.instance:Destroy()
		end
		return result
	end

	-- Roll back by hand, newest change first. Keep going past failures so as much as possible
	-- is restored, and report them.
	local failures: { string } = {}
	local function attempt(what: string, f: () -> ())
		local restored, reason = pcall(f)
		if not restored then
			table.insert(failures, `{what}: {reason}`)
		end
	end
	if markerCreated then
		attempt("removing the marker", function()
			(markerCreated :: Instance):Destroy()
		end)
	elseif markerBefore and markerAttributes then
		attempt("restoring the marker", function()
			Marker.restoreApplied(markerBefore, markerAttributes)
		end)
	end
	for i = #inserted, 1, -1 do
		attempt(`removing '{inserted[i].Name}'`, function()
			inserted[i].Parent = nil
		end)
	end
	for i = #removed, 1, -1 do
		local entry = removed[i]
		attempt(`restoring '{entry.instance.Name}'`, function()
			entry.instance.Parent = entry.parent
		end)
	end
	for _, container in containers do
		pcall(container.Destroy, container)
	end

	if #failures > 0 then
		error(`{Apply.NOT_ROLLED_BACK} ({table.concat(failures, "; ")}); don't save this place: {err}`, 0)
	end
	error(`{Apply.ROLLED_BACK}{err}`, 0)
end

return Apply
