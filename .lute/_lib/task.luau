--!strict
-- Shared helpers for the repo's `lute <task>` scripts. Lives in `_lib/` (no init.luau) so
-- Lute doesn't list it as a command.

local fs = require("@std/fs")
local io = require("@std/io")
local pathlib = require("@std/path")
local process = require("@std/process")
local system = require("@std/system")

local task = {}

-- The repository root: the nearest ancestor of the working directory with a `.lute` folder,
-- found the same way Lute finds these scripts. Tasks run from here wherever they're invoked.
task.root = (function(): string
	local dir = pathlib.format(process.cwd())
	while true do
		local candidate = pathlib.format(pathlib.join(dir, ".lute"))
		if fs.exists(candidate) and fs.type(candidate) == "dir" then
			return dir
		end
		local parent = pathlib.dirname(dir)
		if parent == dir or parent == "" then
			error("couldn't find the repository root (no .lute folder above the working directory)", 0)
		end
		dir = parent
	end
end)()

task.exe = if system.win32 then ".exe" else ""

-- The lute running this script, so tasks use the pinned version.
task.lute = pathlib.format(process.execPath())

-- The script's arguments, without the script name.
function task.args(...: string): { string }
	local args = { ... }
	table.remove(args, 1)
	return args
end

-- Runs a command with inherited stdio, from the repo root or `dir` (relative to it).
-- Returns whether it succeeded.
function task.run(command: { string }, dir: string?): boolean
	local shown = table.clone(command)
	if shown[1] == task.lute then
		shown[1] = "lute"
	end
	io.write(`> {if dir then `(in {dir}) ` else ""}{table.concat(shown, " ")}\n`)
	local cwd = if dir then pathlib.format(pathlib.join(task.root, dir)) else task.root
	local ok, result = pcall(function()
		return process.run(command, { cwd = cwd, stdio = "inherit" })
	end)
	if not ok then
		io.ewrite(`error: couldn't run '{command[1]}' (is it installed? try 'foreman install'): {result}\n`)
		return false
	end
	return result.ok
end

-- Runs a command and exits with failure if it fails.
function task.must(command: { string }, dir: string?)
	if not task.run(command, dir) then
		process.exit(1)
	end
end

-- Every .luau file under `dir` (relative to the root), as root-relative paths, sorted.
function task.luauFiles(dir: string): { string }
	local files = {}
	local base = pathlib.join(task.root, dir)
	for file in fs.walk(base, { recursive = true }) do
		local relative = pathlib.format(pathlib.relative(task.root, file))
		if string.sub(relative, -5) == ".luau" then
			table.insert(files, (string.gsub(relative, "\\", "/")))
		end
	end
	table.sort(files)
	return files
end

return task
