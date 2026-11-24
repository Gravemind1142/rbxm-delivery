--!strict
-- Decides what the plugin shows and whether Sync now or Re-sync may run (spec §6.3, §6.6),
-- and runs them.
-- v0.1: syncing is manual. Auto-apply by the active owner and the lease come in v0.2.

local Apply = require(script.Parent.Apply)
local GitHub = require(script.Parent.GitHubSource)

local Marker = require(script.Parent.Apply.Marker)

export type Kind =
	"notSetUp" -- no marker, or it lacks Repo/Channel/AllowedRef
	| "readOnly" -- the marker was written by a newer protocol: update the plugin
	| "error" -- couldn't fetch or read the release
	| "refused" -- the build can't be applied (unknown schema, wrong ref)
	| "upToDate"
	| "behind"

export type Status = {
	kind: Kind,
	message: string,
	canSync: boolean,
	-- Up to date, but the build can be applied again to discard Studio edits to managed code.
	canResync: boolean?,
	state: Marker.State?,
	release: GitHub.Release?,
}

-- Anything with GitHub's getManifest/getArtifact shape.
export type Source = {
	getManifest: (self: any, etag: string?) -> GitHub.ManifestResult,
	getArtifact: (self: any, release: GitHub.Release) -> buffer,
}

local Sync = {}

local function short(commit: string?): string
	return if commit then string.sub(commit, 1, 7) else "nothing"
end

-- Status from the marker alone, before asking the source anything.
function Sync.localStatus(state: Marker.State?): Status?
	if state == nil or state.repo == nil or state.channel == nil or state.allowedRef == nil then
		return {
			kind = "notSetUp",
			message = "rbxm-pull isn't set up in this place.",
			canSync = false,
			state = state,
		}
	end
	if not Marker.canWrite(state) then
		return {
			kind = "readOnly",
			message = `This place was synced by a newer rbxm-pull (protocol {state.protocol}). `
				.. "Update rbxm-pull in Manage Plugins.",
			canSync = false,
			state = state,
		}
	end
	return nil
end

-- Status for a release fetched from the source.
function Sync.releaseStatus(state: Marker.State, release: GitHub.Release): Status
	local manifest = release.manifest
	if manifest.ref ~= state.allowedRef then
		return {
			kind = "refused",
			message = `The channel's build is from {manifest.ref}, but this place only accepts {state.allowedRef}.`,
			canSync = false,
			state = state,
			release = release,
		}
	end
	if manifest.commit == state.commit then
		return {
			kind = "upToDate",
			message = "Up to date.",
			canSync = false,
			canResync = true,
			state = state,
			release = release,
		}
	end
	return {
		kind = "behind",
		message = `Dev is behind: {short(state.commit)} → {short(manifest.commit)}.`,
		canSync = true,
		state = state,
		release = release,
	}
end

-- Full status: marker, then the source. Never errors; failures become `error`/`refused`.
function Sync.check(dataModel: Instance, source: Source): Status
	local marker = Marker.find(dataModel)
	local state = if marker then Marker.read(marker) else nil
	local early = Sync.localStatus(state)
	if early then
		return early
	end
	local known = state :: Marker.State

	local ok, result = pcall(function()
		return source:getManifest(nil)
	end)
	if not ok then
		local message = tostring(result)
		local refused = string.find(message, Apply.Manifest.UNKNOWN_SCHEMA, 1, true) ~= nil
		return {
			kind = if refused then "refused" else "error",
			message = if refused
				then `The channel's build needs a newer rbxm-pull ({message}). Update rbxm-pull in Manage Plugins.`
				else message,
			canSync = false,
			state = known,
		}
	end
	local fetched = result :: any
	return Sync.releaseStatus(known, fetched.release)
end

export type SyncOptions = {
	appliedBy: number?,
	changeHistory: boolean?,
	-- Re-apply the build the place already has (status.canResync), replacing managed
	-- containers to discard Studio edits to them.
	resync: boolean?,
}

-- Downloads, verifies and applies the release `status` describes. Re-checks the marker right
-- before applying, so a sync someone else finished meanwhile isn't applied twice.
-- Returns nil if there was nothing to do.
function Sync.syncNow(dataModel: Instance, source: Source, status: Status, options: SyncOptions?): Apply.Result?
	local opts = options or {}
	local allowed = if opts.resync then status.canResync == true else status.canSync
	if not allowed or status.release == nil then
		error(if opts.resync and status.canSync then "the place is behind: use Sync now" else status.message, 0)
	end
	local release = status.release :: GitHub.Release

	local rbxm = source:getArtifact(release)
	Apply.verify(rbxm, release.manifest)

	local marker = Marker.find(dataModel)
	local current = if marker then Marker.read(marker) else nil
	local blocked = Sync.localStatus(current)
	if blocked then
		error(blocked.message, 0)
	end
	local applied = (current :: Marker.State).commit == release.manifest.commit
	if opts.resync and not applied then
		-- Someone synced another build meanwhile; re-applying this one would roll it back.
		error("the place changed since the last check; check again", 0)
	elseif not opts.resync and applied then
		return nil
	end

	return Apply.apply(dataModel, rbxm, release.manifest, {
		appliedBy = opts.appliedBy,
		changeHistory = if opts.changeHistory == nil then true else opts.changeHistory,
	})
end

return Sync
