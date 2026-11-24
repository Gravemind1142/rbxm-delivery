--!strict
-- rbxm-publish: builds managed containers with Rojo and publishes them to a release channel.
-- See docs/spec.md §5.

local io = require("@std/io")
local process = require("@std/process")

local actions = require("./actions")
local args = require("./args")
local build = require("./build")
local github = require("./github")
local release = require("./release")
local verify = require("./verify")
local version = require("./version")

local USAGE = [[
Usage:
  rbxm-publish build   [--config rbxm-publish.json] [--out build/] [--commit <sha>] [--ref <ref>]
  rbxm-publish release [--dir build/] [--repo owner/name] --channel dev-latest --allowed-ref refs/heads/main...
  rbxm-publish verify  [--dir build/] [--allowed-ref refs/heads/main...] [--format text|json]
  rbxm-publish --version

release needs GITHUB_TOKEN; --repo defaults to GITHUB_REPOSITORY.
verify checks a build without publishing it, and exits 1 with the reason if it's bad.
]]

local argv = { ... }
table.remove(argv, 1) -- script name

if argv[1] == "--version" or argv[1] == "-V" then
	print(`rbxm-publish {version}`)
	process.exit(0)
	return
elseif argv[1] == "--help" or argv[1] == "-h" or argv[1] == "help" then
	print(`rbxm-publish {version}\n\n{USAGE}`)
	process.exit(0)
	return
end

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
		actions.output("commit", m.commit)
		actions.output("sha256", m.artifact.sha256)
	elseif parsed.command == "verify" then
		local format = flag("format", "text")
		if format ~= "text" and format ~= "json" then
			error(`--format must be 'text' or 'json', not '{format}'`, 0)
		end
		local m = verify.run({
			dir = flag("dir", "build") :: string,
			allowedRefs = parsed.flags["allowed-ref"],
		}).manifest
		if format == "json" then
			print(verify.summaryJson(m))
		else
			print(
				`ok: {m.commit} ({m.ref}): {#m.containers} containers, {m.artifact.size} bytes, sha256 {m.artifact.sha256}`
			)
		end
		actions.output("commit", m.commit)
		actions.output("ref", m.ref)
		actions.output("sha256", m.artifact.sha256)
	else
		local repo = flag("repo", process.env.GITHUB_REPOSITORY)
		if repo == nil then
			error("--repo is required (or set GITHUB_REPOSITORY)", 0)
		end
		local channel = flag("channel")
		if channel == nil then
			error("--channel is required, e.g. --channel dev-latest", 0)
		end
		local token = process.env.GITHUB_TOKEN
		if token == nil or token == "" then
			error("GITHUB_TOKEN must be set to a token with contents:write on the repo", 0)
		end

		local result = release.run({
			dir = flag("dir", "build") :: string,
			channel = channel,
			allowedRefs = parsed.flags["allowed-ref"] or {},
			client = github.new(repo, token, nil, process.env.GITHUB_API_URL),
			log = print,
		})
		actions.output("published", if result.published then "true" else "false")
		if result.published then
			print(`released {result.manifest.commit} to {channel}: {result.releaseUrl}`)
			actions.output("release-url", result.releaseUrl :: string)
		else
			actions.notice(`{channel} not updated: {result.reason}`)
		end
	end
end)

if not ok then
	io.ewrite(`error: {failure}\n`)
	process.exit(1)
end
