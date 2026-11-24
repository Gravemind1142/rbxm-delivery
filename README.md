# rbxm-delivery

Rojo builds into Team Create, from GitHub releases. Design: [docs/spec.md](docs/spec.md).

| Folder | Tool | What it is |
|---|---|---|
| [`publish/`](publish) | **rbxm-publish** | Lute CLI (`src/`) and GitHub Action (`action.yml`) that build `managed.rbxm` + `build.json` and update a release channel. |
| [`pull/`](pull) | **rbxm-pull** | Studio plugin (Rojo project) and the `Apply` module that pull a build into a place. |

Status: rbxm-publish (CLI and Action) works; rbxm-pull is at v0.1 (manual Sync now).

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
      - uses: Gravemind1142/rbxm-delivery/publish@v1
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

rbxm-publish ships as a standalone executable built with `lute compile`. Pushing a `v*` tag
runs [`release.yml`](.github/workflows/release.yml), which compiles it for Linux (x86_64,
aarch64), macOS (aarch64) and Windows (x86_64) and attaches the zips to a GitHub release,
so it installs with Foreman:

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

## rbxm-pull (Studio plugin)

v0.1: a toolbar button opens a widget showing
"Dev @ abc1234 · main @ def5678 · synced 2 min ago", with **Sync now**, **Check** and
**Settings**.

- **Settings:** the repository, channel and allowed ref are shared, stored as attributes
  on `ServerStorage.RbxmPull` (the marker). Your GitHub token is yours only, kept in plugin
  settings and never in the place. A public repo works without a token (60 requests/hour).
- **Sync now:** downloads `managed.rbxm`, checks its SHA-256 against `build.json`, then
  replaces every container in one undoable step. If anything fails mid-apply, the step is
  cancelled and Studio restores what was there. It refuses builds from another ref,
  unknown `build.json` schema versions, and places last synced by a newer rbxm-pull. It
  never applies during a playtest.
- **HTTP:** Studio asks once to allow `api.github.com` and
  `release-assets.githubusercontent.com`. The plugin also needs Script Injection.

Build it with `lute build-plugin`, then drop `build/RbxmPull.rbxm` into Studio's plugins
folder. Auto-apply by a sync owner, the lease and polling are v0.2 (spec §10).

`pull/src/Apply` is self-contained, so a Luau Execution task can require it too:
`Apply.apply(game, rbxm, manifest, { dryRun = true })`.

## Development

Tools are pinned in [`foreman.toml`](foreman.toml) (Rojo, Lute nightly, StyLua, Selene, Wally,
studio-run):

```sh
foreman install
```

Common tasks are Lute scripts in [`.lute/`](.lute), runnable from anywhere in the repo
(`lute run --list` shows them):

| Command | What it does |
|---|---|
| `lute ci` | Everything below, in order, as CI runs it |
| `lute fmt [--check]` | Format all Luau with StyLua |
| `lute lint-plugin` | Lint rbxm-pull with Selene |
| `lute typecheck` | Type check rbxm-publish and the task scripts |
| `lute tests [-c <case>]` | Run rbxm-publish's tests (needs `rojo`) |
| `lute build-cli [--out <path>]` | Compile rbxm-publish to `build/rbxm-publish` |
| `lute build-plugin` | Build rbxm-pull to `build/RbxmPull.rbxm` |
| `lute pull-tests [--cloud] [-t <pattern>]` | Run rbxm-pull's Jest tests in Studio (Windows/macOS) or the cloud |

To run the publisher without compiling: `lute publish/src/main.luau build --config rbxm-publish.json`.

CI (`.github/workflows/ci.yml`) runs `lute ci`, and rbxm-pull's tests in the cloud.
Task names avoid Lute's built-in commands (`test`, `lint`, `check`, `format`, `compile`, ...),
which take precedence over `.lute` scripts.

**rbxm-pull's tests** use [jest-roblox](https://github.com/Roblox/jest-roblox) (installed with
Wally into `pull/DevPackages`) and run through
[studio-run](https://github.com/Gravemind1142/studio-run): `lute pull-tests [-t <pattern>]`.
Locally that's a hidden Studio, so it needs Windows or macOS with Roblox Studio installed and
logged in once; `lute ci` runs them there and skips them on Linux. The test tree goes to the
run as a model (`build/rbxm-pull-tests.rbxm`), not a place file, along with a real
rbxm-publish build of `publish/tests/fixtures/game` for the round-trip tests.

### Plugin tests in the cloud

`lute pull-tests --cloud` runs the same tests as an
[Open Cloud Luau Execution](https://create.roblox.com/docs/cloud/reference/features/luau-execution)
task, on any OS. CI's `pull-tests` job does this, and skips with a warning until these
repository secrets are set:

| Secret | What it is |
|---|---|
| `ROBLOX_API_KEY` | An Open Cloud API key restricted to the test experience, with **Luau execution sessions** read and write, and accepted IP `0.0.0.0/0` (GitHub's runners change IPs) |
| `ROBLOX_UNIVERSE_ID` | The test experience's universe ID |
| `ROBLOX_PLACE_ID` | Its place ID |

Use an experience made only for this (an empty Baseplate published from Studio is enough),
since tasks run against its real cloud data. In its place, turn on
**ServerScriptService → LoadStringEnabled** before publishing: jest-roblox loads test files with
`loadstring` when `debug.loadmodule` isn't available, as in cloud tasks. The tests don't need HTTP enabled. Tasks have no
Plugin capability, so the change-history rollback test is skipped there and runs only in
Studio. To run in the cloud locally, set the same three environment variables and run
`lute pull-tests --cloud`.

## License

MIT; see [LICENSE](LICENSE).
