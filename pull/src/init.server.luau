--!strict
-- rbxm-pull: Studio plugin that pulls a build from a GitHub release channel and applies it.
-- See docs/spec.md §6.

-- Bumped whenever anything read or written on the marker changes meaning (spec §6.6).
local PROTOCOL = 1

local _Apply = require(script.Apply)

local toolbar = plugin:CreateToolbar("rbxm-pull")
local _button = toolbar:CreateButton("RbxmPull", `rbxm-pull (protocol {PROTOCOL})`, "")
