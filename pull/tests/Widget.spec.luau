-- Mounts the widget into a plain Frame (no plugin needed) and drives it, to catch runtime
-- errors in the UI code.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local JestGlobals = require(ReplicatedStorage.DevPackages.JestGlobals)
local describe, it, expect = JestGlobals.describe, JestGlobals.it, JestGlobals.expect

local Widget = require(ReplicatedStorage.RbxmPull.Widget)

local function find(root: Instance, className: string, text: string): any
	for _, d in root:GetDescendants() do
		if d:IsA(className) and string.find((d :: any).Text, text, 1, true) then
			return d
		end
	end
	return nil
end

-- The widget takes its colours from Studio's theme (Enum.StudioStyleGuideColor), which Open
-- Cloud tasks don't have, so this runs only in Studio.
-- selene: allow(global_usage)
local itStudio = if _G.RBXM_PULL_HOST == "cloud" then JestGlobals.it.skip else it

describe("Widget", function()
	itStudio("mounts, updates and reports settings", function()
		local host = Instance.new("Frame")
		local saved = nil
		local view = Widget.mount(host :: any, {
			onCheck = function() end,
			onSync = function() end,
			onResync = function() end,
			onSaveSettings = function(values)
				saved = values
			end,
		})

		view.setStatus("Dev @ aaaaaaa · main @ bbbbbbb", "Dev is behind.", false)
		view.setSyncEnabled(false, "Syncing…")
		view.setResync(true, "Confirm re-sync")
		view.setCommitUrl("https://github.com/o/r/commit/b")
		view.setLastResult("Synced bbbbbbb: replaced 1.")
		view.showSettings(
			true,
			{ repo = "o/r", channel = "dev-latest", allowedRef = "refs/heads/main", hasToken = false }
		)
		view.setSettingsEditable(true)

		expect(find(host, "TextLabel", "Dev is behind.")).never.toBeNil()
		expect(find(host, "TextButton", "Syncing…")).never.toBeNil()
		expect(find(host, "TextButton", "Confirm re-sync").Visible).toBe(true)
		expect(find(host, "TextBox", "https://github.com/o/r/commit/b")).never.toBeNil()
		expect(find(host, "TextLabel", "No token saved")).never.toBeNil()

		local repoBox = nil
		for _, d in host:GetDescendants() do
			if d:IsA("TextBox") and d.Text == "o/r" then
				repoBox = d
			end
		end
		assert(repoBox, "repo box not found")
		repoBox.Text = "other/repo"
		view.submitSettings()
		expect(saved).toEqual({ repo = "other/repo", channel = "dev-latest", allowedRef = "refs/heads/main" })
		host:Destroy()
	end)
end)
