--!strict
-- GitHub Actions integration: step outputs and annotations. Does nothing outside Actions.

local fs = require("@std/fs")
local process = require("@std/process")

local actions = {}

function actions.enabled(): boolean
	return process.env.GITHUB_ACTIONS == "true"
end

-- Appends `name=value` to the step's outputs (values here are always single-line).
function actions.output(name: string, value: string)
	local path = process.env.GITHUB_OUTPUT
	if path == nil or path == "" then
		return
	end
	assert(not string.find(value, "\n", 1, true), "multi-line outputs aren't supported")
	local file = fs.open(path, "a")
	fs.write(file, `{name}={value}\n`)
	fs.close(file)
end

-- Shows `message` as a notice on the workflow run summary.
function actions.notice(message: string)
	if actions.enabled() then
		print(`::notice title=rbxm-publish::{message}`)
	end
end

return actions
