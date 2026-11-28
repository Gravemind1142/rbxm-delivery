# rbxm-delivery

Rojo builds into Team Create, from GitHub releases.

Your code lives in git and is built by CI; your team builds the rest of the game in Team
Create. rbxm-delivery connects the two: CI builds the code-owned parts of the place
("containers", e.g. `ReplicatedStorage/Systems`) into one `.rbxm` and publishes it to a
GitHub release, and a Studio plugin pulls that build into the Team Create place. Changes only
flow one way, from git into Studio. Design: [docs/spec.md](docs/spec.md).

| Folder | Tool | What it is |
|---|---|---|
| [`publish/`](publish) | **rbxm-publish** | Lute CLI (`src/`) and GitHub Action (`action.yml`) that build `managed.rbxm` + `build.json` and update a release channel. |
| [`pull/`](pull) | **rbxm-pull** | Studio plugin (Rojo project) and the `Apply` module that pull a build into a place. |

## Quickstart

1. **Add `rbxm-publish.json`** next to your Rojo project, listing the containers git owns:

   ```json
   {
     "project": "default.project.json",
     "containers": ["ReplicatedStorage/Systems", "ServerScriptService/Systems"],
     "buildInfoModule": "ReplicatedStorage/Systems/BuildInfo"
   }
   ```

   - `project`: your existing Rojo project, unchanged.
   - `containers`: instance paths to build. Each is replaced as a whole in the place, so
     anything else in Studio is left alone.
   - `buildInfoModule` (optional): a ModuleScript the build adds, returning
     `{ commit, ref, builtAt }`, so game code can tell which build it's running.

2. **Publish from CI** with the [GitHub Action](#github-action) on pushes to your main branch.
3. **Install the plugin**: download `RbxmPull.rbxm` from this repo's
   [latest release](https://github.com/Gravemind1142/rbxm-delivery/releases/latest) into
   Studio's plugins folder (**Plugins → Plugins Folder**), then restart Studio.
4. **In your place**, open rbxm-pull from the toolbar, set the repository, channel and
   allowed ref under **Settings**, and press **Sync now**.

## GitHub Action

```yaml
# .github/workflows/main.yml
on:
  push:
    branches: [main]

jobs:
  publish:
    runs-on: ubuntu-latest
    permissions:
      contents: write # only this workflow should have it
    concurrency:
      group: rbxm-publish-dev-latest
      cancel-in-progress: false
    steps:
      - uses: actions/checkout@v5
      # ...your checks...
      - uses: Gravemind1142/rbxm-delivery/publish@v0.1.0
        with:
          channel: dev-latest
          allowed-refs: refs/heads/main
```

| Input | Default | |
|---|---|---|
| `config` | `rbxm-publish.json` | Path to the config |
| `channel` | (required) | Release tag to publish to |
| `allowed-refs` | (required) | One per line or comma-separated |
| `github-token` | `github.token` | Needs `contents: write` |
| `release` | `true` | `false` only builds, e.g. to check pull requests |

Outputs: `published` (`false` when skipped as older than the channel), `commit`, `sha256`,
`release-url`.

The action runs rbxm-publish from its own source with the Lute version pinned in this repo.
It uses the `rojo` already on `PATH` if there is one (so the build matches your toolchain,
e.g. after `Roblox/setup-foreman`); otherwise it installs the Rojo pinned here.

## rbxm-publish build

```sh
rbxm-publish build [--config rbxm-publish.json] [--out build/] [--commit <sha>] [--ref <ref>]
```

Writes `managed.rbxm` and `build.json` to `--out`. Needs `rojo` on `PATH`.

Outside the Action, rbxm-publish is a standalone executable for Linux (x86_64, aarch64),
macOS (aarch64) and Windows (x86_64), attached to each
[release](https://github.com/Gravemind1142/rbxm-delivery/releases). It installs with Foreman:

```toml
rbxm-publish = { github = "Gravemind1142/rbxm-delivery", version = "=0.1.0" }
```

- **Commit and ref** come from `--commit`/`--ref`, else `GITHUB_SHA`/`GITHUB_REF`, else git
  (`HEAD` and its branch). A detached HEAD outside Actions needs `--ref`.
- **Containers** are resolved through the project's explicit nodes, then on disk under the
  nearest `$path` using Rojo's file-name rules (`Foo/`, `Foo.luau`, `Foo.server.luau`, ...).
  Two entries mapping to the same name is an error.
- **`buildInfoModule`** must be inside a container, and its parent must be the container
  itself or an explicit node in the project. A file already at that path (for example a
  committed placeholder for type checking) is left out of the build and replaced.
- The generated project is written next to your Rojo project as
  `.rbxm-publish.tmp.project.json` for the duration of the build, so relative `$path`s and
  `globIgnorePaths` keep working.

## rbxm-publish release

```sh
GITHUB_TOKEN=... rbxm-publish release [--dir build/] [--repo owner/name] \
    --channel dev-latest --allowed-ref refs/heads/main [--allowed-ref ...]
```

Publishes `managed.rbxm` + `build.json` from `--dir` to the rolling release `--channel`.
The token needs `contents: write`; `--repo` defaults to `GITHUB_REPOSITORY`.

1. Verifies the build locally (known `schemaVersion`, size and SHA-256 match) and refuses a
   `ref` that isn't an `--allowed-ref`, all before any network call.
2. If the channel's tag already points at a newer commit, it **skips** (exit 0): an older
   workflow run finished late. Unrelated history (a force push) publishes with a warning.
3. Creates the release if needed (never marked Latest), uploads both files under temporary
   names, then for each file deletes the old asset and renames the new one into place. A
   consumer polling mid-publish sees at worst a missing asset or a hash mismatch, both of
   which it refuses safely. A run interrupted here is cleaned up by the next one.
4. Updates the release body (commit, ref, build time), then moves the tag to the commit,
   so the tag always reflects what's published.

Workflows that publish should still use a `concurrency` group per channel.

## rbxm-publish verify

```sh
rbxm-publish verify [--dir build/] [--allowed-ref refs/heads/main ...] [--format text|json]
```

Runs the checks from `release` step 1 without publishing anything: a known `build.json`
`schemaVersion`, `managed.rbxm` size and SHA-256 matching it, and the ref if any
`--allowed-ref` is given. Exits 0 if the build is good and 1 with the reason if not. With
`--format json` it prints `{ schemaVersion, commit, ref, builtAt, size, sha256, containers }`
on one line. Use it in pipelines that consume a build outside the plugin, such as
[applying it in a Luau Execution task](#applying-a-build-in-ci), before uploading anything.

## rbxm-pull (Studio plugin)

A toolbar button opens a widget showing
"Dev @ abc1234 · main @ def5678 · synced 2 min ago", with **Sync now**, **Re-sync**,
**Check** and **Settings**.

- **Settings:** the repository, channel and allowed ref are shared, stored as attributes
  on `ServerStorage.RbxmPull` (the marker). Your GitHub token is yours only, kept in plugin
  settings and never in the place. A public repo works without a token (60 requests/hour).
- **Sync now:** downloads `managed.rbxm`, checks its SHA-256 against `build.json`, then
  replaces every container in one undoable step. If anything fails mid-apply, the step is
  cancelled and Studio restores what was there. It refuses builds from another ref,
  unknown `build.json` schema versions, and places last synced by a newer rbxm-pull. It
  never applies during a playtest.
- **Re-sync:** shown when the place is up to date. It applies the same build again to undo
  accidental Studio edits to managed code (git owns it). Click it, then **Confirm re-sync**;
  Ctrl+Z undoes it like any sync.
- **Team Create:** a sync is undoable only by whoever ran it, and it undoes for everyone.
  Collaborators with a managed script open are kicked from the editor. If they had an
  unsaved draft, they should choose **Discard edit**: **Restore script** leaves a copy in
  Workspace that syncs never remove.
- **HTTP:** Studio asks once to allow `api.github.com` and
  `release-assets.githubusercontent.com`. The plugin also needs Script Injection.

Install it from a [release](https://github.com/Gravemind1142/rbxm-delivery/releases/latest)
(`RbxmPull.rbxm`, see [Quickstart](#quickstart)). Syncing is on demand for now; automatic
syncing by a designated owner is planned
([#1](https://github.com/Gravemind1142/rbxm-delivery/issues/1)).

## Applying a build in CI

To patch a saved place version from CI (for example a Stable copy of Dev) with the same
code the plugin uses, apply the build from your own patch script in an Open Cloud
[Luau Execution](https://create.roblox.com/docs/cloud/reference/features/luau-execution)
task. rbxm-delivery ships the plugin's Apply as the Lute package `rbxm-apply`; depend on it
at the release tag that matches your `rbxm-publish`:

```luau
-- pkg.luau
rbxmApply = {
    sourceKind = "github",
    source = "https://github.com/Gravemind1142/rbxm-delivery",
    rev = "v0.1.0",
    target = "pull",
},
```

Then `lute pkg install --vendor` and require it from your patch script. How the script
becomes the one source a task runs is up to you:

```luau
local Apply = require("@rbxmApply")
local manifest = Apply.Manifest.decode(buffer.tostring(inputs["build.json"]))
local result = Apply.apply(game, inputs["managed.rbxm"], manifest, {})
local record = Apply.record(manifest, result) -- what was applied, for your deploy report
```

The apply is all or nothing: if it errors, the place is as it was unless
`Apply.rolledBack(err)` says otherwise. It never saves; save the place only when your whole
patch succeeded. Run `rbxm-publish verify` on the build first.
[Spec §7.3](docs/spec.md#73-in-a-luau-execution-task-the-rbxm-apply-package) has the details.

## Contributing

Issues and pull requests are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md). To report a
security problem, see [SECURITY.md](SECURITY.md).

## License

MIT; see [LICENSE](LICENSE).
