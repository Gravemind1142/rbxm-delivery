--!strict
-- The rbxm-pull dock widget (spec §6.4), built from plain instances and themed with Studio's
-- colors. It only lays things out; init.server.luau decides what it shows.

local Widget = {}

export type Callbacks = {
	onCheck: () -> (),
	onSync: () -> (),
	onResync: () -> (),
	onSaveSettings: (settings: { repo: string, channel: string, allowedRef: string, token: string? }) -> (),
}

export type View = {
	setStatus: (line: string, message: string, isProblem: boolean) -> (),
	setSyncEnabled: (enabled: boolean, label: string?) -> (),
	-- Shows the Re-sync button (only when up to date), with an optional label.
	setResync: (shown: boolean, label: string?) -> (),
	setCommitUrl: (url: string?) -> (),
	setLastResult: (text: string) -> (),
	showSettings: (
		shown: boolean,
		values: { repo: string, channel: string, allowedRef: string, hasToken: boolean }?
	) -> (),
	setSettingsEditable: (editable: boolean) -> (),
	-- What the Save button does: report the settings fields to onSaveSettings.
	submitSettings: () -> (),
}

local function color(name: Enum.StudioStyleGuideColor, modifier: Enum.StudioStyleGuideModifier?): Color3
	return (settings() :: any).Studio.Theme:GetColor(name, modifier)
end

local function label(parent: Instance, order: number, text: string, bold: boolean?): TextLabel
	local l = Instance.new("TextLabel")
	l.LayoutOrder = order
	l.Size = UDim2.fromScale(1, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.BackgroundTransparency = 1
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextWrapped = true
	l.Font = if bold then Enum.Font.SourceSansBold else Enum.Font.SourceSans
	l.TextSize = 15
	l.Text = text
	l.TextColor3 = color(Enum.StudioStyleGuideColor.MainText)
	l.Parent = parent
	return l
end

local function button(parent: Instance, order: number, text: string, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.LayoutOrder = order
	b.Size = UDim2.fromOffset(0, 26)
	b.AutomaticSize = Enum.AutomaticSize.X
	b.Font = Enum.Font.SourceSansSemibold
	b.TextSize = 15
	b.Text = `  {text}  `
	b.AutoButtonColor = true
	b.BackgroundColor3 = color(Enum.StudioStyleGuideColor.Button)
	b.TextColor3 = color(Enum.StudioStyleGuideColor.ButtonText)
	b.BorderColor3 = color(Enum.StudioStyleGuideColor.ButtonBorder)
	b.Parent = parent
	b.Activated:Connect(onClick)
	return b
end

local function input(parent: Instance, order: number, caption: string, placeholder: string): TextBox
	label(parent, order, caption)
	local box = Instance.new("TextBox")
	box.LayoutOrder = order + 1
	box.Size = UDim2.new(1, 0, 0, 24)
	box.ClearTextOnFocus = false
	box.Font = Enum.Font.Code
	box.TextSize = 14
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.PlaceholderText = placeholder
	box.Text = ""
	box.BackgroundColor3 = color(Enum.StudioStyleGuideColor.InputFieldBackground)
	box.BorderColor3 = color(Enum.StudioStyleGuideColor.InputFieldBorder)
	box.TextColor3 = color(Enum.StudioStyleGuideColor.MainText)
	box.PlaceholderColor3 = color(Enum.StudioStyleGuideColor.DimmedText)
	box.Parent = parent
	return box
end

local function list(parent: Instance, padding: number): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, padding)
	layout.Parent = parent
	return layout
end

function Widget.mount(gui: DockWidgetPluginGui, callbacks: Callbacks): View
	local root = Instance.new("ScrollingFrame")
	root.Size = UDim2.fromScale(1, 1)
	root.CanvasSize = UDim2.new()
	root.AutomaticCanvasSize = Enum.AutomaticSize.Y
	root.ScrollBarThickness = 6
	root.BorderSizePixel = 0
	root.BackgroundColor3 = color(Enum.StudioStyleGuideColor.MainBackground)
	local padding = Instance.new("UIPadding")
	for _, side in { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" } do
		(padding :: any)[side] = UDim.new(0, 8)
	end
	padding.Parent = root
	list(root, 6)

	local statusLine = label(root, 1, "Dev @ —", true)
	local message = label(root, 2, "")

	local buttons = Instance.new("Frame")
	buttons.LayoutOrder = 3
	buttons.Size = UDim2.new(1, 0, 0, 26)
	buttons.BackgroundTransparency = 1
	buttons.Parent = root
	local row = list(buttons, 6)
	row.FillDirection = Enum.FillDirection.Horizontal

	local syncButton = button(buttons, 1, "Sync now", callbacks.onSync)
	local resyncButton = button(buttons, 2, "Re-sync", callbacks.onResync)
	resyncButton.Visible = false
	button(buttons, 3, "Check", callbacks.onCheck)
	local settingsFrame: Frame
	button(buttons, 4, "Settings", function()
		settingsFrame.Visible = not settingsFrame.Visible
	end)

	-- No clipboard API for plugins, so "Open commit" is a selectable URL.
	local commitUrl = Instance.new("TextBox")
	commitUrl.LayoutOrder = 4
	commitUrl.Size = UDim2.new(1, 0, 0, 22)
	commitUrl.TextEditable = false
	commitUrl.ClearTextOnFocus = false
	commitUrl.Font = Enum.Font.Code
	commitUrl.TextSize = 13
	commitUrl.TextXAlignment = Enum.TextXAlignment.Left
	commitUrl.BackgroundTransparency = 1
	commitUrl.TextColor3 = color(Enum.StudioStyleGuideColor.LinkText)
	commitUrl.Visible = false
	commitUrl.Parent = root

	local lastResult = label(root, 5, "")
	lastResult.TextColor3 = color(Enum.StudioStyleGuideColor.DimmedText)

	-- Settings: Repo/Channel/AllowedRef are shared on the marker; the token is per user.
	settingsFrame = Instance.new("Frame")
	settingsFrame.LayoutOrder = 6
	settingsFrame.Size = UDim2.fromScale(1, 0)
	settingsFrame.AutomaticSize = Enum.AutomaticSize.Y
	settingsFrame.BackgroundTransparency = 1
	settingsFrame.Visible = false
	settingsFrame.Parent = root
	list(settingsFrame, 4)

	label(settingsFrame, 1, "Settings", true)
	local repoBox = input(settingsFrame, 2, "Repository (shared)", "owner/name")
	local channelBox = input(settingsFrame, 4, "Channel (shared)", "dev-latest")
	local refBox = input(settingsFrame, 6, "Allowed ref (shared)", "refs/heads/main")
	local tokenBox = input(settingsFrame, 8, "GitHub token (yours only; never saved in the place)", "github_pat_…")
	local tokenHint = label(settingsFrame, 10, "")
	tokenHint.TextColor3 = color(Enum.StudioStyleGuideColor.DimmedText)
	local function submitSettings()
		callbacks.onSaveSettings({
			repo = repoBox.Text,
			channel = channelBox.Text,
			allowedRef = refBox.Text,
			token = if tokenBox.Text ~= "" then tokenBox.Text else nil,
		})
		tokenBox.Text = ""
	end
	local saveButton = button(settingsFrame, 11, "Save", submitSettings)

	root.Parent = gui

	return {
		setStatus = function(line, text, isProblem)
			statusLine.Text = line
			message.Text = text
			message.TextColor3 =
				color(if isProblem then Enum.StudioStyleGuideColor.ErrorText else Enum.StudioStyleGuideColor.MainText)
		end,
		setSyncEnabled = function(enabled, text)
			syncButton.Active = enabled
			syncButton.AutoButtonColor = enabled
			syncButton.TextTransparency = if enabled then 0 else 0.5
			syncButton.Text = `  {text or "Sync now"}  `
		end,
		setResync = function(shown, text)
			resyncButton.Visible = shown
			resyncButton.Text = `  {text or "Re-sync"}  `
		end,
		setCommitUrl = function(url)
			commitUrl.Text = url or ""
			commitUrl.Visible = url ~= nil
		end,
		setLastResult = function(text)
			lastResult.Text = text
		end,
		showSettings = function(shown, values)
			settingsFrame.Visible = shown
			if values then
				repoBox.Text = values.repo
				channelBox.Text = values.channel
				refBox.Text = values.allowedRef
				tokenHint.Text = if values.hasToken
					then "A token is saved. Enter a new one to replace it."
					else "No token saved: fine for public repos (60 requests/hour)."
			end
		end,
		setSettingsEditable = function(editable)
			for _, box in { repoBox, channelBox, refBox } do
				box.TextEditable = editable
			end
			saveButton.Active = editable
			saveButton.TextTransparency = if editable then 0 else 0.5
		end,
		submitSettings = submitSettings,
	}
end

return Widget
