-- rbxm-pull's Apply module as a Lute package (spec §7.3), for projects that use it in
-- their own Luau Execution patch script. Only src/Apply is shipped. This file lives here and
-- not in src/Apply because Rojo would sync it into the plugin.
--
-- A project depends on it straight from this repository, pinned to a release tag:
--
--   rbxmApply = {
--       sourceKind = "github",
--       source = "https://github.com/Gravemind1142/rbxm-delivery",
--       rev = "v0.1.0",
--       target = "pull",
--   }
return {
	package = {
		name = "gravemind1142/rbxm-apply",
		-- The release workflow refuses a tag that doesn't match this.
		version = "0.1.0",
		content_root = "src/Apply",
		files = { "*.luau" },
	},
}
