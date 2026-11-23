--!strict
-- rbxm-publish: builds managed containers with Rojo and publishes them to a release channel.
-- See docs/spec.md §5.

local process = require("@lute/process")
local args = require("./args")

local USAGE = [[
Usage:
  rbxm-publish build   --config rbxm-publish.json --out build/
  rbxm-publish release --dir build/ --repo owner/name --channel dev-latest --allowed-ref refs/heads/main
]]

local argv = { ... }
table.remove(argv, 1) -- script name

local parsed, err = args.parse(argv)
if parsed == nil then
	print(`error: {err}\n\n{USAGE}`)
	process.exit(2)
	return
end

print(`rbxm-publish {parsed.command}: not implemented yet`)
process.exit(1)
