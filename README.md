# rbxm-delivery

Rojo builds into Team Create, from GitHub releases. Design: [docs/spec.md](docs/spec.md).

| Folder | Tool | What it is |
|---|---|---|
| [`publish/`](publish) | **rbxm-publish** | Lute CLI (`src/`) and GitHub Action (`action.yml`) that build `managed.rbxm` + `build.json` and update a release channel. |
| [`pull/`](pull) | **rbxm-pull** | Studio plugin (Rojo project) and the `Apply` module that pull a build into a place. |

Status: `rbxm-publish build` works; `release`, the Action and rbxm-pull are not implemented yet.

## rbxm-publish build

```sh
rbxm-publish build [--config rbxm-publish.json] [--out build/] [--commit <sha>] [--ref <ref>]
```

Writes `managed.rbxm` and `build.json` to `--out`. Needs `rojo` on `PATH`.

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

## Development

Tools are pinned in [`foreman.toml`](foreman.toml) (Rojo, Lute nightly, StyLua, Selene):

```sh
foreman install
```

| Task | Command |
|---|---|
| Test the publisher (from the repo root) | `lute test publish/tests` |
| Type check the publisher | `lute check publish/src/*.luau` |
| Run the publisher | `lute publish/src/main.luau build --config rbxm-publish.json --out build/` |
| Build the plugin | `mkdir -p build && rojo build pull --output build/RbxmPull.rbxm` |
| Format | `stylua publish pull` |
| Lint the plugin | `cd pull && selene src` |

CI (`.github/workflows/ci.yml`) runs the format check, lint, type check, tests and plugin build.

**rbxm-pull has no tests yet, on purpose.** Testing the plugin and `Apply` module needs a real
Studio/engine runtime. That waits on [studio-run](https://github.com/Gravemind1142/studio-run)
supporting more platforms and Open Cloud (Luau Execution); until then, rbxm-pull is only linted and built.
