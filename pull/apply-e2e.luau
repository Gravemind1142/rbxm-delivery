--!native
-- Applies a real rbxm-publish build in a task with the released Apply module, the way a
-- project's patch script would call it. Invoked by `lute apply-e2e`:
--   studio-run run pull/apply-e2e.luau [--cloud --universe-id <id> --place-id <id>] \
--     --input plugin=<RbxmPull.rbxm> --input managed=<managed.rbxm> --input manifest=<build.json>
-- Returns whether the apply worked, which becomes studio-run's exit code. It never saves.
--
-- Apply comes in as a ModuleScript from the plugin model, so this checks the same source the
-- rbxm-apply package ships, with its `@self` requires resolved by the engine. How a project
-- gets Apply into its one task script (bundling, or a ModuleScript input like this) is up to
-- the project.
local ServerStorage = game:GetService("ServerStorage")
local SerializationService = game:GetService("SerializationService")

local ctx = ...

assert(ctx.inputs.plugin, "pass the plugin model with --input plugin=<RbxmPull.rbxm>")
assert(ctx.inputs.managed and ctx.inputs.manifest, "pass --input managed=<managed.rbxm> --input manifest=<build.json>")

-- The plugin's own Script stays unparented, so it never runs; only Apply joins the place.
local roots = SerializationService:DeserializeInstancesAsync(ctx.inputs.plugin)
local module = roots[1] and roots[1]:FindFirstChild("Apply")
assert(module and module:IsA("ModuleScript"), "the plugin model has no Apply ModuleScript")
module.Parent = ServerStorage
for _, root in roots do
	root:Destroy()
end

local Apply = require(module) :: any
local manifest = Apply.Manifest.decode(buffer.tostring(ctx.inputs.manifest))
print(`apply-e2e: applying {manifest.commit} ({manifest.ref}) with Apply {Apply.VERSION}`)
local started = os.clock()
local ok, result = pcall(Apply.apply, game, ctx.inputs.managed, manifest, {})
module:Destroy()
if not ok then
	print(`apply-e2e: {result} (rolled back: {Apply.rolledBack(tostring(result))})`)
	return false
end
print(`apply-e2e: applied in {string.format("%.2f", os.clock() - started)}s`)

local record = Apply.record(manifest, result)
local marker = ServerStorage:FindFirstChild("RbxmPull")
if marker == nil or marker:GetAttribute("Commit") ~= record.commit then
	print("apply-e2e: the marker doesn't record the applied commit")
	return false
end
if record.sha256 ~= manifest.artifact.sha256 or #record.containers ~= #manifest.containers then
	print("apply-e2e: the record doesn't describe the build")
	return false
end
print(`apply-e2e: ok, {#record.containers} containers ({#record.replaced} replaced, {#record.added} added)`)
-- A real pipeline would save the place here.
return true
