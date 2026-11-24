--!strict
-- rbxm-pull: Studio plugin that pulls a build from a GitHub release channel and applies it.
-- See docs/spec.md §6. Syncs on demand (Sync now); auto-apply is planned (issue #1).

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local RunService = game:GetService("RunService")
local StudioService = game:GetService("StudioService")

local Format = require(script.Format)
local GitHubSource = require(script.GitHubSource)
local Sync = require(script.Sync)
local Widget = require(script.Widget)

local Marker = require(script.Apply.Marker)

local plugin: Plugin = plugin

-- Tokens are per user and per repo, in plugin settings: never stored in the place (spec §8).
local function tokenKey(repo: string): string
	return `token:{repo}`
end

local function getToken(repo: string?): string?
	if repo == nil then
		return nil
	end
	local token = plugin:GetSetting(tokenKey(repo))
	return if typeof(token) == "string" and token ~= "" then token else nil
end

local toolbar = plugin:CreateToolbar("rbxm-pull")
local toggle = toolbar:CreateButton("rbxm-pull", "Pull builds from GitHub into this place", "")
toggle.ClickableWhenViewportHidden = true

local gui = plugin:CreateDockWidgetPluginGui(
	"RbxmPull",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, false, false, 320, 260, 260, 180)
)
gui.Title = "rbxm-pull"
gui.Name = "RbxmPull"

local status: Sync.Status? = nil
local busy = false -- a check or sync is in flight
local syncing = false
-- Re-sync discards Studio edits to managed code, so it takes a second click to confirm.
local confirmingResync = false
local view: Widget.View

local function currentState(): Marker.State?
	local marker = Marker.find(game)
	return if marker then Marker.read(marker) else nil
end

local function sourceFor(state: Marker.State): GitHubSource.Source
	return GitHubSource.new({
		repo = state.repo :: string,
		channel = state.channel :: string,
		token = getToken(state.repo),
	})
end

local function render()
	local state = if status then status.state else currentState()
	local manifest = if status and status.release then status.release.manifest else nil
	local kind = if status then status.kind else nil
	view.setStatus(
		Format.statusLine(state, manifest, os.time()),
		if status then status.message else "Checking…",
		kind == "error" or kind == "refused" or kind == "readOnly"
	)
	view.setSyncEnabled(not busy and status ~= nil and status.canSync, if syncing then "Syncing…" else nil)
	local canResync = status ~= nil and status.canResync == true
	if not canResync then
		confirmingResync = false
	end
	view.setResync(
		canResync and (not busy or syncing),
		if syncing then "Re-syncing…" elseif confirmingResync then "Confirm re-sync" else nil
	)
	view.setCommitUrl(
		if state and state.repo and manifest then `https://github.com/{state.repo}/commit/{manifest.commit}` else nil
	)
	view.setSettingsEditable(state == nil or Marker.canWrite(state))
	if kind == "notSetUp" then
		view.showSettings(true, {
			repo = if state then state.repo or "" else "",
			channel = if state and state.channel then state.channel else "dev-latest",
			allowedRef = if state and state.allowedRef then state.allowedRef else "refs/heads/main",
			hasToken = getToken(state and state.repo) ~= nil,
		})
	end
end

local function check()
	if busy then
		return
	end
	busy = true
	render()
	task.spawn(function()
		local state = currentState()
		local early = Sync.localStatus(state)
		if early then
			status = early
		else
			local ok, source = pcall(sourceFor, state :: Marker.State)
			status = if ok
				then Sync.check(game, source)
				else { kind = "error", message = tostring(source), canSync = false, state = state }
		end
		busy = false
		render()
	end)
end

local function apply(resync: boolean)
	if RunService:IsRunning() then
		view.setLastResult("Stop the playtest first: rbxm-pull never applies during a playtest.")
		return
	end
	busy = true
	syncing = true
	confirmingResync = false
	render()
	task.spawn(function()
		local ok, result = pcall(function()
			local state = currentState() :: Marker.State
			return Sync.syncNow(game, sourceFor(state), status :: Sync.Status, {
				appliedBy = StudioService:GetUserId(),
				resync = resync,
			})
		end)
		local verb = if resync then "Re-sync" else "Sync"
		if not ok then
			view.setLastResult(`{verb} failed: {result}`)
		elseif result == nil then
			view.setLastResult("Already synced by someone else.")
		else
			view.setLastResult(`{if resync then "Re-synced. " else ""}{Format.result(result)}`)
		end
		busy = false
		syncing = false
		status = nil
		check()
	end)
end

local function syncNow()
	if busy or status == nil or not status.canSync then
		return
	end
	apply(false)
end

local function resync()
	if busy or status == nil or not status.canResync then
		return
	end
	if not confirmingResync then
		confirmingResync = true
		local manifest = (status.release :: GitHubSource.Release).manifest
		view.setLastResult(
			`Re-sync replaces every managed container with build {string.sub(manifest.commit, 1, 7)}, `
				.. "discarding Studio edits to them. Click Confirm re-sync to go ahead (Ctrl+Z undoes it)."
		)
		render()
		return
	end
	apply(true)
end

local function saveSettings(values: { repo: string, channel: string, allowedRef: string, token: string? })
	local repo = string.match(values.repo, "^%s*(.-)%s*$") :: string
	local channel = string.match(values.channel, "^%s*(.-)%s*$") :: string
	local allowedRef = string.match(values.allowedRef, "^%s*(.-)%s*$") :: string
	if not string.match(repo, "^[%w%-%._]+/[%w%-%._]+$") then
		view.setLastResult("Repository must look like owner/name.")
		return
	elseif channel == "" or string.sub(allowedRef, 1, 5) ~= "refs/" then
		view.setLastResult("Channel is required, and the allowed ref must be a full ref like refs/heads/main.")
		return
	end

	local state = currentState()
	if state and not Marker.canWrite(state) then
		view.setLastResult("This place's settings belong to a newer rbxm-pull. Update rbxm-pull first.")
		return
	end
	if values.token then
		plugin:SetSetting(tokenKey(repo), values.token)
	end

	local recording = ChangeHistoryService:TryBeginRecording("rbxm-pull: settings")
	Marker.configure(Marker.findOrCreate(game), { repo = repo, channel = channel, allowedRef = allowedRef })
	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end
	view.showSettings(false)
	view.setLastResult("Settings saved.")
	status = nil
	check()
end

view = Widget.mount(gui, {
	onCheck = check,
	onSync = syncNow,
	onResync = resync,
	onSaveSettings = saveSettings,
})

toggle.Click:Connect(function()
	gui.Enabled = not gui.Enabled
end)
gui:GetPropertyChangedSignal("Enabled"):Connect(function()
	toggle:SetActive(gui.Enabled)
	if gui.Enabled then
		check()
	end
end)

-- Another collaborator syncing or changing settings updates this widget without a fetch.
local watched: RBXScriptConnection? = nil
local function watchMarker()
	if watched then
		watched:Disconnect()
		watched = nil
	end
	local marker = Marker.find(game)
	if marker then
		watched = marker.AttributeChanged:Connect(function()
			if status and status.state then
				status.state = Marker.read(marker)
				if status.release and status.kind ~= "readOnly" then
					status = Sync.localStatus(status.state) or Sync.releaseStatus(status.state, status.release)
				end
			end
			render()
		end)
	end
end
game:GetService("ServerStorage").ChildAdded:Connect(function(child)
	if child.Name == Marker.NAME then
		watchMarker()
	end
end)
watchMarker()

toggle:SetActive(gui.Enabled)
render()
if gui.Enabled then
	check()
end
