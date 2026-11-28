# Contributing

Thanks for helping. Bug reports, fixes and docs are all welcome. For anything bigger than a
fix, please open an issue first so we can agree on the approach. [docs/spec.md](docs/spec.md)
describes how everything works today, and planned features are tracked as
[issues](https://github.com/Gravemind1142/rbxm-delivery/issues?q=is%3Aissue+label%3Aenhancement).
Changes to the artifact format (spec §4) or the marker protocol (spec §6.5) need special
care, because older plugins and builds have to keep working.

## Setup

Tools are pinned in [`foreman.toml`](foreman.toml) (Rojo, Lute nightly, StyLua, Selene, Wally,
studio-run). Install [Foreman](https://github.com/Roblox/foreman), then:

```sh
foreman install
cd pull && wally install
```

## Tasks

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
| `lute install-plugin` | Build rbxm-pull and copy it into Studio's local plugins folder |
| `lute uninstall-plugin` | Remove rbxm-pull from Studio's local plugins folder |
| `lute pull-tests [--cloud] [-t <pattern>]` | Run rbxm-pull's Jest tests in Studio (Windows/macOS) or the cloud |
| `lute apply-e2e [--cloud]` | Apply the fixture build with the released Apply module as a real task, in Studio or the cloud |

- To run the publisher without compiling: `lute publish/src/main.luau build --config rbxm-publish.json`.
- `lute install-plugin` copies the plugin into `%LOCALAPPDATA%\Roblox\Plugins` on Windows or
  `~/Documents/Roblox/Plugins` on macOS (set `ROBLOX_PLUGINS_DIR` to use another folder);
  restart Studio afterwards.
- Task names avoid Lute's built-in commands (`test`, `lint`, `check`, `format`, `compile`,
  ...), which take precedence over `.lute` scripts.

CI ([`ci.yml`](.github/workflows/ci.yml)) runs `lute ci` on Linux x86_64, and rbxm-publish's
tests, compiled binary and the publish Action from this checkout on each platform releases
ship for (Linux x86_64 and aarch64, macOS aarch64, Windows x86_64). Once those pass, it runs
rbxm-pull's engine tests in the cloud (see below).

## Plugin tests

rbxm-pull's tests use [jest-roblox](https://github.com/Roblox/jest-roblox) (installed with
Wally into `pull/DevPackages`) and run through
[studio-run](https://github.com/Gravemind1142/studio-run): `lute pull-tests [-t <pattern>]`.
Locally that's a hidden Studio, so it needs Windows or macOS with Roblox Studio installed and
logged in once; `lute ci` runs them there and skips them on Linux. The test tree goes to the
run as a model (`build/rbxm-pull-tests.rbxm`), not a place file, along with a real
rbxm-publish build of `publish/tests/fixtures/game` for the round-trip tests.

### In the cloud

`lute pull-tests --cloud` runs the same tests as an
[Open Cloud Luau Execution](https://create.roblox.com/docs/cloud/reference/features/luau-execution)
task, on any OS, and `lute apply-e2e --cloud` applies the fixture build with the released
Apply module as a real task. CI's `pull-tests` job runs both on every push to `main`,
every pull request and every manual run. It skips with a warning when these repository secrets aren't available (not set
yet, or a pull request from a fork, which GitHub doesn't give secrets to):

| Secret | What it is |
|---|---|
| `ROBLOX_API_KEY` | An Open Cloud API key restricted to the test experience, with **Luau execution sessions** read and write, and accepted IP `0.0.0.0/0` (GitHub's runners change IPs) |
| `ROBLOX_UNIVERSE_ID` | The test experience's universe ID |
| `ROBLOX_PLACE_ID` | Its place ID |

Use an experience made only for this (an empty Baseplate published from Studio is enough),
since tasks run against its real cloud data. In its place, turn on
**ServerScriptService → LoadStringEnabled** before publishing: jest-roblox loads test files
with `loadstring` when `debug.loadmodule` isn't available, as in cloud tasks. The tests don't
need HTTP enabled. Tasks have no Plugin capability or Studio theme, so the change-history
rollback tests and the widget test are skipped there and run only in Studio. To run in the
cloud locally, set the same three environment variables and run `lute pull-tests --cloud`.

## Before you open a pull request

Run `lute ci`. On Linux the plugin's engine tests are skipped locally; CI runs
them in the cloud on your pull request. If you change Apply, you can also run
`lute pull-tests` on Windows or macOS.

- Add or update tests for behaviour changes (`publish/tests`, `pull/tests`).
- Update the README or spec when you change how something works.
- Add a line to the **Unreleased** section of [CHANGELOG.md](CHANGELOG.md) for user-facing
  changes.
- Keep pull requests focused: one change per PR.

## Releasing

1. Bump the version in `publish/src/version.luau`, `pull/wally.toml`, `pull/pkg.luau` and
   `Apply.VERSION` (`lute tests` checks they match), move the **Unreleased** notes in
   [CHANGELOG.md](CHANGELOG.md) under the new version, and merge.
2. Tag the merge commit `vX.Y.Z` and push the tag. [`release.yml`](.github/workflows/release.yml)
   checks the tag matches every version, compiles rbxm-publish for each platform, builds
   `RbxmPull.rbxm`, and publishes them as a GitHub release.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
