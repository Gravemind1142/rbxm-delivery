--!strict
-- Command-line parsing for rbxm-publish (spec §5.2).

export type Command = "build" | "release"

export type Parsed = {
	command: Command,
	flags: { [string]: { string } },
}

local COMMANDS: { [string]: { [string]: "one" | "many" } } = {
	build = { config = "one", out = "one" },
	release = { dir = "one", repo = "one", channel = "one", ["allowed-ref"] = "many" },
}

local args = {}

-- Parses argv (without the script name). Returns the parsed command or an error message.
function args.parse(argv: { string }): (Parsed?, string?)
	local command = argv[1]
	if command == nil then
		return nil, "missing command (expected one of: build, release)"
	end
	local spec = COMMANDS[command]
	if spec == nil then
		return nil, `unknown command '{command}' (expected one of: build, release)`
	end

	local flags: { [string]: { string } } = {}
	local i = 2
	while i <= #argv do
		local token = argv[i]
		local name = string.match(token, "^%-%-(.+)$")
		if name == nil then
			return nil, `unexpected argument '{token}'`
		end
		local arity = spec[name]
		if arity == nil then
			return nil, `unknown flag '--{name}' for '{command}'`
		end
		local value = argv[i + 1]
		if value == nil or string.sub(value, 1, 2) == "--" then
			return nil, `flag '--{name}' needs a value`
		end
		local values = flags[name]
		if values == nil then
			values = {}
			flags[name] = values
		elseif arity == "one" then
			return nil, `flag '--{name}' given more than once`
		end
		table.insert(values, value)
		i += 2
	end

	return { command = command :: Command, flags = flags }, nil
end

return args
