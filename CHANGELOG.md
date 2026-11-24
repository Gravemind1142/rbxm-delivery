# Changelog

Notable changes to rbxm-publish and rbxm-pull. They share a version number and are released
together.

## Unreleased

- **`rbxm-publish verify`** checks a build directory without publishing it (schema version,
  size and SHA-256, optionally the ref), with `--format json` for pipelines
  ([#15](https://github.com/Gravemind1142/rbxm-delivery/issues/15)).
- **`apply-task.luau`** release asset: Apply bundled into one script that applies a build
  in an Open Cloud Luau Execution task and reports `{ ok, summary, record, rolledBack }`
  without saving ([#13](https://github.com/Gravemind1142/rbxm-delivery/issues/13)).
- Apply is all or nothing in every host: without a ChangeHistoryService recording it now
  rolls a failed apply back by hand, and it checks the result before finishing
  ([#14](https://github.com/Gravemind1142/rbxm-delivery/issues/14)).
- `build.json` with a container inside another container (or listed twice) is refused by
  rbxm-pull and `rbxm-publish verify`/`release`. rbxm-publish never built one.

## 0.1.0

First release.

- **rbxm-publish** CLI (`build`, `release`) and GitHub Action: builds the configured
  containers of a Rojo project into `managed.rbxm` + `build.json` and publishes them to a
  rolling release channel, skipping builds older than what the channel already has.
- **rbxm-pull** Studio plugin: **Sync now** downloads a channel's build, checks its SHA-256
  and replaces the managed containers in one undoable step; **Re-sync** discards Studio edits
  to managed code; **Check** looks for a newer build. Works with public repos without a token.
- `build.json` schema version 1 and marker protocol 1.
