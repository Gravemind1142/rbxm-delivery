--!strict
-- Applies a build to a place. Plain Luau so both the plugin and Luau Execution tasks can use it.
-- See docs/spec.md §7.

export type Manifest = {
	schemaVersion: number,
	commit: string,
	ref: string,
	builtAt: string,
	artifact: { size: number, sha256: string },
	containers: { string },
}

export type Options = {
	dryRun: boolean?,
}

export type Result = {
	replaced: { string },
	added: { string },
	removed: { string },
}

local Apply = {}

function Apply.apply(_dataModel: DataModel, _rbxm: buffer, _manifest: Manifest, _options: Options?): Result
	error("Apply.apply: not implemented yet")
end

return Apply
