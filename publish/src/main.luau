--!strict
-- rbxm-publish: builds managed containers with Rojo and publishes them to a release channel.
-- See docs/spec.md §5.

local io = require("@std/io")
local process = require("@std/process")

local args = require("./args")
local build = require("./build")

local USAGE = [[
Usage:
  rbxm-publish build   [--config rbxm-publish.json] [--out build/] [--commit <sha>] [--ref <ref>]
  rbxm-publish release --dir build/ --repo owner/name --channel dev-latest --allowed-ref refs/heads/main
]]

local argv = { ... }
table.remove(argv, 1) -- script name

local parsed, err = args.parse(argv)
if parsed == nil then
	io.ewrite(`error: {err}\n\n{USAGE}`)
	process.exit(2)
	return
end

local function flag(name: string, default: string?): string?
	local values = parsed.flags[name]
	return if values then values[1] else default
end

local ok, failure = pcall(function()
	if parsed.command == "build" then
		local m = build.run({
			configPath = flag("config", "rbxm-publish.json") :: string,
			outDir = flag("out", "build") :: string,
			commit = flag("commit"),
			ref = flag("ref"),
		})
		print(
			`built {m.commit} ({m.ref}): {#m.containers} containers, {m.artifact.size} bytes, sha256 {m.artifact.sha256}`
		)
	else
		error(`'{parsed.command}' is not implemented yet`, 0)
	end
end)

if not ok then
	io.ewrite(`error: {failure}\n`)
	process.exit(1)
end
