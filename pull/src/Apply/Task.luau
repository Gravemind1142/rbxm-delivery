--!strict
-- Applies a build inside an Open Cloud Luau Execution task (spec §7.3). Released, bundled with
-- the rest of Apply into the single file apply-task.luau by `lute build-apply-task`, because a
-- task runs one script source and can't require files from a repo.
--
-- The released file returns this function. A task script runs it alongside its own patch
-- scripts and saves the place only when it returns `ok = true`:
--
--   local applyTask = (function() <apply-task.luau> end)()
--   local outcome = applyTask({ inputs = ..., args = { allowedRef = "refs/heads/main" }, log = print })
--
-- It never saves. When it fails, `rolledBack` says whether the place is as it was (nothing
-- changed, or the change was undone); `false` means it was left partly changed.

local Apply = require(script.Parent)

local VERSION = "dev" -- replaced by lute build-apply-task

export type Context = {
	-- "managed.rbxm" and "build.json", as the release assets' bytes.
	inputs: { [string]: buffer },
	-- Optional: dryRun = "true" checks everything and changes nothing; allowedRef is one ref,
	-- or several separated by commas, that the build's ref must be one of.
	args: { [string]: string }?,
	log: ((string) -> ())?,
}

export type Outcome = {
	ok: boolean,
	summary: string,
	-- On success: what was applied. The build fields match `rbxm-publish verify --format json`.
	record: { [string]: any }?,
	-- On failure: true if the place is as it was before.
	rolledBack: boolean?,
}

local function refs(value: string?): { string }
	local list = {}
	for _, item in string.split(value or "", ",") do
		item = string.match(item, "^%s*(.-)%s*$") :: string
		if item ~= "" then
			table.insert(list, item)
		end
	end
	return list
end

local function run(ctx: Context, log: (string) -> ()): Outcome
	local args = ctx.args or {}
	local inputs = ctx.inputs or {}
	local rbxm = inputs["managed.rbxm"]
	local manifestBytes = inputs["build.json"]
	if typeof(rbxm) ~= "buffer" then
		error("missing input 'managed.rbxm'", 0)
	end
	if typeof(manifestBytes) ~= "buffer" then
		error("missing input 'build.json'", 0)
	end

	local manifest = Apply.Manifest.decode(buffer.tostring(manifestBytes))
	local allowedRefs = refs(args.allowedRef)
	if #allowedRefs > 0 and not table.find(allowedRefs, manifest.ref) then
		error(`refusing a build of '{manifest.ref}': allowed refs are {table.concat(allowedRefs, ", ")}`, 0)
	end

	local dryRun = args.dryRun == "true"
	log(`apply-task {VERSION}: applying {manifest.commit} ({manifest.ref}){if dryRun then " (dry run)" else ""}`)
	local started = os.clock()
	local result = Apply.apply(game, rbxm, manifest, { dryRun = dryRun })
	log(`apply-task: done in {string.format("%.2f", os.clock() - started)}s`)

	local verb = if dryRun then "would apply" else "applied"
	return {
		ok = true,
		summary = `{verb} {manifest.commit} ({#manifest.containers} containers)`,
		record = {
			applyVersion = VERSION,
			schemaVersion = manifest.schemaVersion,
			commit = manifest.commit,
			ref = manifest.ref,
			builtAt = manifest.builtAt,
			size = manifest.artifact.size,
			sha256 = manifest.artifact.sha256,
			containers = manifest.containers,
			replaced = result.replaced,
			added = result.added,
			removed = result.removed,
			dryRun = result.dryRun,
		},
	}
end

return function(ctx: Context): Outcome
	local log = ctx.log or print
	local ok, outcome = pcall(run, ctx, log)
	if ok then
		return outcome
	end
	local message = tostring(outcome)
	log(`apply-task: {message}`)
	return {
		ok = false,
		summary = message,
		rolledBack = string.sub(message, 1, #Apply.NOT_ROLLED_BACK) ~= Apply.NOT_ROLLED_BACK,
	}
end
