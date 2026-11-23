# rbxm-delivery

Rojo builds into Team Create, from GitHub releases. Design: [docs/spec.md](docs/spec.md).

| Folder | Tool | What it is |
|---|---|---|
| [`publish/`](publish) | **rbxm-publish** | Lute CLI (`src/`) and GitHub Action (`action.yml`) that build `managed.rbxm` + `build.json` and update a release channel. |
| [`pull/`](pull) | **rbxm-pull** | Studio plugin (Rojo project) and the `Apply` module that pull a build into a place. |

Status: `rbxm-publish build` and `release` work; the Action and rbxm-pull are not implemented yet.

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
rbxm-publish = { github = "<org>/rbxm-delivery", version = "=0.1.0" }
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

## Development

Tools are pinned in [`foreman.toml`](foreman.toml) (Rojo, Lute nightly, StyLua, Selene):

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

To run the publisher without compiling: `lute publish/src/main.luau build --config rbxm-publish.json`.

CI (`.github/workflows/ci.yml`) just runs `lute ci`, so a green local run means a green CI run.
Task names avoid Lute's built-in commands (`test`, `lint`, `check`, `format`, `compile`, ...),
which take precedence over `.lute` scripts.

**rbxm-pull has no tests yet, on purpose.** Testing the plugin and `Apply` module needs a real
Studio/engine runtime. That waits on [studio-run](https://github.com/Gravemind1142/studio-run)
supporting more platforms and Open Cloud (Luau Execution); until then, rbxm-pull is only linted and built.
