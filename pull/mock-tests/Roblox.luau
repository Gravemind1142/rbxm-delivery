--!strict
-- Just enough of the Roblox engine to run the bundled Apply under Lute, so pull requests can
-- test it without Studio or an Open Cloud task. The real engine runs the same code in
-- pull/tests (Studio locally, and the weekly cloud run).
--
-- Instances support Name, ClassName, Parent, arbitrary properties (e.g. Source), attributes,
-- GetChildren, FindFirstChild, GetDescendants, IsDescendantOf, IsA and Destroy. Setting the
-- Parent of a destroyed instance errors, as in Roblox. Set `rejectChildren` on an instance
-- (Roblox.setRejectChildren) to make adding children to it fail, to inject failures.
--
-- managed.rbxm is mocked as JSON: Roblox.rbxm(tree) encodes { ClassName, Name, Properties?,
-- Attributes?, Children? } and SerializationService:DeserializeInstancesAsync decodes it.

local json = require("@std/json")
local luau = require("@std/luau")

local Roblox = {}

type State = {
	className: string,
	name: string,
	parent: any,
	children: { any },
	attributes: { [string]: any },
	properties: { [string]: any },
	destroyed: boolean,
	rejectChildren: boolean,
}

local states: { [any]: State } = setmetatable({}, { __mode = "k" }) :: any

local IS_A: { [string]: { string } } = {
	Script = { "BaseScript", "LuaSourceContainer" },
	LocalScript = { "Script", "BaseScript", "LuaSourceContainer" },
	ModuleScript = { "LuaSourceContainer" },
}

local Instance = {}
local methods = {}

local function state(instance: any): State
	return assert(states[instance], "not an Instance")
end

local function setParent(instance: any, parent: any)
	local s = state(instance)
	if s.destroyed then
		error(
			`The Parent property of {s.name} is locked, current parent: NULL, new parent {if parent
				then state(parent).name
				else "NULL"}`,
			0
		)
	end
	if parent ~= nil then
		local p = state(parent)
		if p.rejectChildren then
			error(`mock: {p.name} rejects new children`, 0)
		end
		local ancestor = parent
		while ancestor do
			if ancestor == instance then
				error("mock: attempt to set parent to a descendant", 0)
			end
			ancestor = state(ancestor).parent
		end
	end
	if s.parent then
		local siblings = state(s.parent).children
		table.remove(siblings, assert(table.find(siblings, instance)))
	end
	s.parent = parent
	if parent then
		table.insert(state(parent).children, instance)
	end
end

local mt = {
	__index = function(instance: any, key: string): any
		local s = state(instance)
		if key == "Name" then
			return s.name
		elseif key == "ClassName" then
			return s.className
		elseif key == "Parent" then
			return s.parent
		elseif methods[key] then
			return methods[key]
		elseif s.properties[key] ~= nil then
			return s.properties[key]
		end
		for _, child in s.children do
			if state(child).name == key then
				return child
			end
		end
		error(`mock: {key} is not a valid member of {s.className} "{s.name}"`, 2)
	end,
	__newindex = function(instance: any, key: string, value: any)
		local s = state(instance)
		if key == "Name" then
			s.name = value
		elseif key == "Parent" then
			setParent(instance, value)
		elseif key == "ClassName" then
			error("mock: ClassName is read-only", 2)
		else
			s.properties[key] = value
		end
	end,
	__tostring = function(instance: any): string
		return state(instance).name
	end,
}

function Instance.new(className: string, parent: any?): any
	local instance = setmetatable({}, mt)
	states[instance] = {
		className = className,
		name = className,
		parent = nil,
		children = {},
		attributes = {},
		properties = {},
		destroyed = false,
		rejectChildren = false,
	}
	if parent then
		setParent(instance, parent)
	end
	return instance
end

function methods.GetChildren(self: any): { any }
	return table.clone(state(self).children)
end

function methods.GetDescendants(self: any): { any }
	local out = {}
	local function walk(instance: any)
		for _, child in state(instance).children do
			table.insert(out, child)
			walk(child)
		end
	end
	walk(self)
	return out
end

function methods.FindFirstChild(self: any, name: string): any?
	for _, child in state(self).children do
		if state(child).name == name then
			return child
		end
	end
	return nil
end

function methods.IsDescendantOf(self: any, ancestor: any): boolean
	local current = state(self).parent
	while current do
		if current == ancestor then
			return true
		end
		current = state(current).parent
	end
	return false
end

function methods.IsA(self: any, className: string): boolean
	local s = state(self)
	return s.className == className
		or className == "Instance"
		or (IS_A[s.className] ~= nil and table.find(IS_A[s.className], className) ~= nil)
end

function methods.GetAttribute(self: any, name: string): any
	return state(self).attributes[name]
end

function methods.SetAttribute(self: any, name: string, value: any)
	state(self).attributes[name] = value
end

function methods.Destroy(self: any)
	local s = state(self)
	for _, child in table.clone(s.children) do
		methods.Destroy(child)
	end
	if s.parent then
		setParent(self, nil)
	end
	s.destroyed = true
end

function Roblox.isDestroyed(instance: any): boolean
	return state(instance).destroyed
end

function Roblox.setRejectChildren(instance: any, reject: boolean)
	state(instance).rejectChildren = reject
end

export type Tree = {
	ClassName: string,
	Name: string,
	Properties: { [string]: any }?,
	Attributes: { [string]: any }?,
	Children: { Tree }?,
}

-- A mocked managed.rbxm holding `roots`.
function Roblox.rbxm(roots: { Tree }): buffer
	return buffer.fromstring(json.serialize(roots :: any))
end

-- JSON values as Roblox's JSONDecode returns them: null is nil, arrays are plain tables.
local function plain(value: any): any
	if value == json.null then
		return nil
	elseif typeof(value) == "table" then
		local out = {}
		for k, v in value do
			out[k] = plain(v)
		end
		return out
	end
	return value
end

local function instantiate(tree: Tree, parent: any?): any
	local instance = Instance.new(tree.ClassName)
	instance.Name = tree.Name
	for key, value in tree.Properties or {} do
		instance[key] = value
	end
	for key, value in tree.Attributes or {} do
		instance:SetAttribute(key, value)
	end
	for _, child in tree.Children or {} do
		instantiate(child, instance)
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local SERVICES = {
	"ReplicatedStorage",
	"ServerScriptService",
	"ServerStorage",
	"Workspace",
	"HttpService",
	"SerializationService",
	"ChangeHistoryService",
}

export type Game = {
	game: any,
	-- Every service name GetService was called with, in order.
	servicesRequested: { string },
}

-- A fresh DataModel with the services Apply uses.
function Roblox.newGame(): Game
	local game = Instance.new("DataModel")
	game.Name = "Game"
	local requested: { string } = {}
	local services: { [string]: any } = {}

	local function service(name: string): any
		local instance = Instance.new(name)
		instance.Name = name
		if name == "HttpService" then
			instance.JSONDecode = function(_self: any, source: string): any
				return plain(json.deserialize(source))
			end
		elseif name == "SerializationService" then
			instance.DeserializeInstancesAsync = function(_self: any, rbxm: buffer): { any }
				local roots = {}
				for _, tree in plain(json.deserialize(buffer.tostring(rbxm))) do
					table.insert(roots, instantiate(tree))
				end
				return roots
			end
		end
		instance.Parent = game
		return instance
	end

	game.GetService = function(_self: any, name: string): any
		table.insert(requested, name)
		if services[name] == nil then
			if not table.find(SERVICES, name) then
				error(`'{name}' is not a valid Service name`, 2)
			end
			services[name] = service(name)
		end
		return services[name]
	end
	for _, name in { "ReplicatedStorage", "ServerScriptService", "ServerStorage", "Workspace" } do
		game:GetService(name)
	end
	table.clear(requested)
	return { game = game, servicesRequested = requested }
end

-- Runs `source` as a script in `game`, returning what it returns.
function Roblox.run(source: string, chunkname: string, game: any): any
	local env = setmetatable({
		game = game,
		Instance = Instance,
		DateTime = {
			now = function()
				return {
					ToIsoDate = function(_self: any): string
						return "2026-11-23T12:00:00Z"
					end,
				}
			end,
		},
	}, { __index = _G })
	return luau.load(luau.compile(source), chunkname, env)()
end

Roblox.Instance = Instance

return Roblox
