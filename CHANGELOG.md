# Changelog

Notable changes to rbxm-publish and rbxm-pull. They share a version number and are released
together.

## Unreleased

## 0.1.0

First release.

- **rbxm-publish** CLI (`build`, `release`) and GitHub Action: builds the configured
  containers of a Rojo project into `managed.rbxm` + `build.json` and publishes them to a
  rolling release channel, skipping builds older than what the channel already has.
- **rbxm-pull** Studio plugin: **Sync now** downloads a channel's build, checks its SHA-256
  and replaces the managed containers in one undoable step; **Re-sync** discards Studio edits
  to managed code; **Check** looks for a newer build. Works with public repos without a token.
- `build.json` schema version 1 and marker protocol 1.
