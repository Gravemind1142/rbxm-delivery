--!strict
-- An example of a project's own patch script for an Open Cloud Luau Execution task (spec
-- §7.3): it applies an rbxm-delivery build with the rbxm-apply package, then runs the
-- project's other steps. Copy it into your project and change it; rbxm-delivery doesn't
-- release a task script of its own, because what a patch does is the project's call.
--
-- A task runs one script source, so bundle this file and the package into one file first:
--
--   darklua process patch.luau build/patch.luau
--
-- with a .darklua.json whose `@rbxmApply` alias points at the vendored package (this example
-- points at the source in this repository instead). `lute apply-e2e` bundles and runs it.
--
-- It returns a function of the task's inputs and args, and never saves: whoever runs the task
-- saves the place only if it returns `ok = true`, so a failed patch never becomes a version.

local Apply = require("@rbxmApply")

export type Context = {
	-- "managed.rbxm" and "build.json", as rbxm-publish built them.
	inputs: { [string]: buffer },
	-- allowedRef: one ref, or several separated by commas, the build's ref must be one of.
	-- dryRun = "true": check everything and change nothing.
	args: { [string]: string }?,
	log: ((string) -> ())?,
}

export type Outcome = {
	ok: boolean,
	summary: string,
	record: { [string]: any }?,
	-- On failure: whether the place is as it was before.
	rolledBack: boolean?,
}

local function list(value: string?): { string }
	local items = {}
	for _, item in string.split(value or "", ",") do
		item = string.match(item, "^%s*(.-)%s*$") :: string
		if item ~= "" then
			table.insert(items, item)
		end
	end
	return items
end

local function input(ctx: Context, name: string): buffer
	local value = ctx.inputs[name]
	if typeof(value) ~= "buffer" then
		error(`missing input '{name}'`, 0)
	end
	return value
end

local function run(ctx: Context, log: (string) -> ()): Outcome
	local args = ctx.args or {}
	local rbxm = input(ctx, "managed.rbxm")
	local manifest = Apply.Manifest.decode(buffer.tostring(input(ctx, "build.json")))

	-- Which refs may ship is this project's rule, not rbxm-apply's.
	local allowed = list(args.allowedRef)
	if #allowed > 0 and not table.find(allowed, manifest.ref) then
		error(`refusing a build of '{manifest.ref}': allowed refs are {table.concat(allowed, ", ")}`, 0)
	end

	local dryRun = args.dryRun == "true"
	log(`patch: applying {manifest.commit} ({manifest.ref}) with rbxm-apply {Apply.VERSION}`)
	local started = os.clock()
	local result = Apply.apply(game, rbxm, manifest, { dryRun = dryRun })
	log(`patch: applied in {string.format("%.2f", os.clock() - started)}s`)

	-- The project's other steps go here (stripping PackageLinks, stamping build info, ...).
	-- Each should check its own result and error if it's wrong.

	return {
		ok = true,
		summary = `{if dryRun then "would apply" else "applied"} {manifest.commit} ({#manifest.containers} containers)`,
		record = Apply.record(manifest, result),
	}
end

return function(ctx: Context): Outcome
	local log = ctx.log or print
	local ok, outcome = pcall(run, ctx, log)
	if ok then
		return outcome
	end
	local message = tostring(outcome)
	log(`patch: {message}`)
	-- Apply rolls itself back on failure. A step after it would leave the place changed, but
	-- the place isn't saved either way.
	return { ok = false, summary = message, rolledBack = Apply.rolledBack(message) }
end
