-- Apply's source against a mocked engine: applying, and rolling back by hand when
-- there's no ChangeHistoryService recording (spec §7.2). Run from the repository root.

local json = require("@std/json")
local test = require("@std/test")

local verify = require("../../publish/src/verify")

local Helpers = require("./Helpers")
local Roblox = require("./Roblox")

local SHARED, SERVER = Helpers.SHARED, Helpers.SERVER

local function failAt(at: string): { onStep: (string) -> () }
	return {
		onStep = function(step: string)
			if step == at then
				error("injected failure", 0)
			end
		end,
	}
end

test.case("applies a build and destroys what it replaced", function(check)
	local Apply, g = Helpers.apply()
	local game = g.game
	local old = Helpers.existing(game.ReplicatedStorage, "Systems")
	local rbxm, manifest = Helpers.buildBoth()

	local result = Apply.apply(game, rbxm, Apply.Manifest.validate(manifest), {})
	check.eq(result.replaced[1], SHARED)
	check.eq(result.added[1], SERVER)
	check.eq(game.ReplicatedStorage.Systems.Module.Source, `return "{SHARED}"`)
	check.eq(game.ServerScriptService.Systems.Module.Source, `return "{SERVER}"`)
	check.eq(Roblox.isDestroyed(old), true)

	local marker = game.ServerStorage.RbxmPull
	check.eq(marker:GetAttribute("Commit"), Helpers.COMMIT)
	check.eq(marker:GetAttribute("AppliedBy"), 0)
	check.eq(marker:GetAttribute("Containers"), `{SHARED},{SERVER}`)
end)

test.case("never fetches ChangeHistoryService without a recording", function(check)
	local Apply, g = Helpers.apply()
	local rbxm, manifest = Helpers.buildBoth()
	Apply.apply(g.game, rbxm, Apply.Manifest.validate(manifest), {})
	check.eq(table.find(g.servicesRequested, "ChangeHistoryService"), nil)
end)

for _, step in { "remove", "insert", "marker", "check" } do
	test.case(`rolls back by hand when failing at '{step}'`, function(check)
		local Apply, g = Helpers.apply()
		local game = g.game
		local old = Helpers.existing(game.ReplicatedStorage, "Systems")
		local sibling = Helpers.existing(game.ReplicatedStorage, "Other")
		local rbxm, manifest = Helpers.buildBoth()
		-- A previous apply, so the marker's attributes must come back exactly.
		local marker = Roblox.Instance.new("Configuration")
		marker.Name = "RbxmPull"
		marker:SetAttribute("Repo", "owner/repo")
		marker:SetAttribute("Commit", string.rep("a", 40))
		marker:SetAttribute("Protocol", 1)
		marker:SetAttribute("Containers", SHARED)
		marker.Parent = game.ServerStorage
		local before = Helpers.snapshot(game)

		local err = Helpers.errorOf(function()
			Apply.apply(game, rbxm, Apply.Manifest.validate(manifest), failAt(step))
		end)
		check.eq(err, `{Apply.ROLLED_BACK}injected failure`)

		check.eq(Helpers.snapshot(game), before)
		-- The same instances, with their contents and attributes.
		check.eq(game.ReplicatedStorage.Systems, old)
		check.eq(Roblox.isDestroyed(old), false)
		check.eq(old.Old.Source, "return 'old'")
		check.eq(old.Old:GetAttribute("Edited"), true)
		check.eq(sibling.Parent, game.ReplicatedStorage)
		check.eq(game.ServerStorage.RbxmPull, marker)
		check.eq(marker:GetAttribute("Commit"), string.rep("a", 40))
		check.eq(marker:GetAttribute("Containers"), SHARED)
		check.eq(marker:GetAttribute("Repo"), "owner/repo")
		check.eq(marker:GetAttribute("AppliedAt"), nil)
		check.eq(marker:GetAttribute("SchemaVersion"), nil)
	end)
end

test.case("removes a marker it created when rolling back", function(check)
	local Apply, g = Helpers.apply()
	local rbxm, manifest = Helpers.buildBoth()
	local err = Helpers.errorOf(function()
		Apply.apply(g.game, rbxm, Apply.Manifest.validate(manifest), failAt("check"))
	end)
	check.eq(string.sub(err, 1, #Apply.ROLLED_BACK), Apply.ROLLED_BACK)
	check.eq(g.game.ServerStorage:FindFirstChild("RbxmPull"), nil)
	check.eq(g.game.ReplicatedStorage:FindFirstChild("Systems"), nil)
end)

test.case("rolls back when inserting really fails", function(check)
	local Apply, g = Helpers.apply()
	local game = g.game
	local old = Helpers.existing(game.ReplicatedStorage, "Systems")
	Roblox.setRejectChildren(game.ServerScriptService, true)
	local rbxm, manifest = Helpers.buildBoth()

	local err = Helpers.errorOf(function()
		Apply.apply(game, rbxm, Apply.Manifest.validate(manifest), {})
	end)
	check.eq(err, `{Apply.ROLLED_BACK}mock: ServerScriptService rejects new children`)
	check.eq(Apply.rolledBack(err), true)
	check.eq(game.ReplicatedStorage.Systems, old)
	check.eq(#game.ReplicatedStorage:GetChildren(), 1)
end)

test.case("restores nested removals in order", function(check)
	-- The previous build had a container inside what's now one container (spec allows
	-- renaming containers between builds).
	local Apply, g = Helpers.apply()
	local game = g.game
	local outer = Helpers.existing(game.ReplicatedStorage, "Systems")
	local inner = Helpers.existing(outer, "Sub")
	local marker = Roblox.Instance.new("Configuration")
	marker.Name = "RbxmPull"
	marker:SetAttribute("Protocol", 1)
	marker:SetAttribute("Containers", `{SHARED}/Sub`)
	marker.Parent = game.ServerStorage
	local before = Helpers.snapshot(game)
	local rbxm, manifest = Helpers.build({ { path = SHARED } })

	Helpers.errorOf(function()
		Apply.apply(game, rbxm, Apply.Manifest.validate(manifest), failAt("check"))
	end)
	check.eq(Helpers.snapshot(game), before)
	check.eq(inner.Parent, outer)
	check.eq(outer.Parent, game.ReplicatedStorage)
end)

test.case("says so when it can't roll back", function(check)
	local Apply, g = Helpers.apply()
	local game = g.game
	local old = Helpers.existing(game.ReplicatedStorage, "Systems")
	local rbxm, manifest = Helpers.buildBoth()

	local err = Helpers.errorOf(function()
		Apply.apply(game, rbxm, Apply.Manifest.validate(manifest), {
			onStep = function(step: string)
				if step == "check" then
					-- Nothing can go back into ReplicatedStorage now.
					Roblox.setRejectChildren(game.ReplicatedStorage, true)
					error("injected failure", 0)
				end
			end,
		})
	end)
	check.eq(string.sub(err, 1, #Apply.NOT_ROLLED_BACK), Apply.NOT_ROLLED_BACK)
	check.eq(Apply.rolledBack(err), false)
	check.eq(string.find(err, "restoring 'Systems'", 1, true) ~= nil, true)
	check.eq(string.find(err, "don't save this place: injected failure", 1, true) ~= nil, true)
	-- Everything else was still undone.
	check.eq(old.Parent, nil)
	check.eq(game.ServerScriptService:FindFirstChild("Systems"), nil)
end)

test.case("refuses overlapping containers in build.json", function(check)
	local Apply = Helpers.apply()
	local _, manifest = Helpers.build({ { path = SHARED }, { path = `{SHARED}/Sub` } })
	check.eq(
		Helpers.errorOf(function()
			Apply.Manifest.validate(manifest)
		end),
		`build.json containers '{SHARED}' and '{SHARED}/Sub' overlap`
	)
end)

test.case("its SHA-256 agrees with Lute's", function(check)
	local Apply = Helpers.apply()
	for _, size in { 0, 1, 55, 56, 63, 64, 65, 1000, 100000 } do
		local data = buffer.create(size)
		for i = 0, size - 1 do
			buffer.writeu8(data, i, (i * 7 + 3) % 256)
		end
		check.eq(Apply.Sha256.hex(data), Helpers.hex(data))
	end
end)

test.case("records what it applied, with the same build fields as rbxm-publish verify", function(check)
	local Apply, g = Helpers.apply()
	Helpers.existing(g.game.ReplicatedStorage, "Systems")
	local rbxm, raw = Helpers.buildBoth()
	local manifest = Apply.Manifest.validate(raw)
	local record = Apply.record(manifest, Apply.apply(g.game, rbxm, manifest, {}))

	check.eq(record.applyVersion, Apply.VERSION)
	check.eq(record.replaced[1], SHARED)
	check.eq(record.added[1], SERVER)
	check.eq(#record.removed, 0)
	check.eq(record.dryRun, false)
	local summary = json.asObject(json.deserialize(verify.summaryJson(raw))) :: json.Object
	for key, value in summary :: { [any]: any } do
		if typeof(key) ~= "string" then
			continue -- @std/json's own type tag
		elseif key == "containers" then
			check.eq(table.concat(record.containers, ","), table.concat(json.asArray(value) :: { any }, ","))
		else
			check.eq((record :: any)[key], value)
		end
	end
end)

test.case("records a dry run, which changes nothing", function(check)
	local Apply, g = Helpers.apply()
	local before = Helpers.snapshot(g.game)
	local rbxm, raw = Helpers.buildBoth()
	local manifest = Apply.Manifest.validate(raw)
	local record = Apply.record(manifest, Apply.apply(g.game, rbxm, manifest, { dryRun = true }))
	check.eq(record.dryRun, true)
	check.eq(record.added[2], SERVER)
	check.eq(Helpers.snapshot(g.game), before)
end)

test.case("its version matches the package's", function(check)
	local Apply = Helpers.apply()
	local pkg = require("../pkg")
	check.eq(Apply.VERSION, pkg.package.version)
end)
