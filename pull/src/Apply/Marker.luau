--!strict
-- The marker: `ServerStorage.RbxmPull`, a Configuration holding the shared sync settings and
-- what was last applied (spec §3, §6.2). Everything here is covered by PROTOCOL (spec §6.5).

local Marker = {}

-- Bump whenever anything read or written on the marker changes meaning: its attributes, the
-- lease format or the active-owner rule. Plugins with a lower PROTOCOL than the marker's
-- `Protocol` never write to it.
Marker.PROTOCOL = 1

Marker.NAME = "RbxmPull"
Marker.DEFAULT_INTERVAL_SECONDS = 180

export type State = {
	-- Shared settings.
	repo: string?,
	channel: string?,
	allowedRef: string?,
	owners: { number },
	intervalSeconds: number,
	-- What was last applied.
	commit: string?,
	schemaVersion: number?,
	appliedAt: string?,
	appliedBy: number?,
	protocol: number,
	containers: { string },
	syncLease: string?,
}

export type Settings = {
	repo: string,
	channel: string,
	allowedRef: string,
}

export type Applied = {
	commit: string,
	schemaVersion: number,
	appliedAt: string,
	appliedBy: number,
	containers: { string },
}

local function serverStorage(dataModel: Instance): Instance
	return (dataModel :: any):GetService("ServerStorage")
end

local function splitList(value: any): { string }
	local items = {}
	if typeof(value) == "string" then
		for _, item in string.split(value, ",") do
			item = string.match(item, "^%s*(.-)%s*$") :: string
			if item ~= "" then
				table.insert(items, item)
			end
		end
	end
	return items
end

local function optionalString(value: any): string?
	return if typeof(value) == "string" and value ~= "" then value else nil
end

function Marker.find(dataModel: Instance): Configuration?
	local marker = serverStorage(dataModel):FindFirstChild(Marker.NAME)
	return if marker and marker:IsA("Configuration") then marker else nil
end

function Marker.findOrCreate(dataModel: Instance): Configuration
	local marker = Marker.find(dataModel)
	if marker then
		return marker
	end
	local created = Instance.new("Configuration")
	created.Name = Marker.NAME
	created.Parent = serverStorage(dataModel)
	return created
end

function Marker.read(marker: Configuration): State
	local owners = {}
	for _, item in splitList(marker:GetAttribute("Owners")) do
		local id = tonumber(item)
		if id then
			table.insert(owners, id)
		end
	end
	local interval = marker:GetAttribute("IntervalSeconds")
	local protocol = marker:GetAttribute("Protocol")
	local schemaVersion = marker:GetAttribute("SchemaVersion")
	local appliedBy = marker:GetAttribute("AppliedBy")
	return {
		repo = optionalString(marker:GetAttribute("Repo")),
		channel = optionalString(marker:GetAttribute("Channel")),
		allowedRef = optionalString(marker:GetAttribute("AllowedRef")),
		owners = owners,
		intervalSeconds = if typeof(interval) == "number" and interval > 0
			then interval
			else Marker.DEFAULT_INTERVAL_SECONDS,
		commit = optionalString(marker:GetAttribute("Commit")),
		schemaVersion = if typeof(schemaVersion) == "number" then schemaVersion else nil,
		appliedAt = optionalString(marker:GetAttribute("AppliedAt")),
		appliedBy = if typeof(appliedBy) == "number" then appliedBy else nil,
		protocol = if typeof(protocol) == "number" then protocol else 0,
		containers = splitList(marker:GetAttribute("Containers")),
		syncLease = optionalString(marker:GetAttribute("SyncLease")),
	}
end

-- Whether this plugin may write to a marker in `state` (spec §6.5).
function Marker.canWrite(state: State): boolean
	return state.protocol <= Marker.PROTOCOL
end

function Marker.configure(marker: Configuration, settings: Settings)
	marker:SetAttribute("Repo", settings.repo)
	marker:SetAttribute("Channel", settings.channel)
	marker:SetAttribute("AllowedRef", settings.allowedRef)
	if marker:GetAttribute("IntervalSeconds") == nil then
		marker:SetAttribute("IntervalSeconds", Marker.DEFAULT_INTERVAL_SECONDS)
	end
	if marker:GetAttribute("Owners") == nil then
		marker:SetAttribute("Owners", "")
	end
end

function Marker.writeApplied(marker: Configuration, applied: Applied)
	marker:SetAttribute("Commit", applied.commit)
	marker:SetAttribute("SchemaVersion", applied.schemaVersion)
	marker:SetAttribute("AppliedAt", applied.appliedAt)
	marker:SetAttribute("AppliedBy", applied.appliedBy)
	marker:SetAttribute("Protocol", Marker.PROTOCOL)
	marker:SetAttribute("Containers", table.concat(applied.containers, ","))
end

return Marker
