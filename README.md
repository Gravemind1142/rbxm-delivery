# rbxm-delivery

Rojo builds into Team Create, from GitHub releases. Design: [docs/spec.md](docs/spec.md).

| Folder | Tool | What it is |
|---|---|---|
| [`publish/`](publish) | **rbxm-publish** | Lute CLI (`src/`) and GitHub Action (`action.yml`) that build `managed.rbxm` + `build.json` and update a release channel. |
| [`pull/`](pull) | **rbxm-pull** | Studio plugin (Rojo project) and the `Apply` module that pull a build into a place. |

Status: scaffold only; nothing is implemented yet.

## Development

Tools are pinned in [`foreman.toml`](foreman.toml) (Rojo, Lute, StyLua, Selene):

```sh
foreman install
```

| Task | Command |
|---|---|
| Test the publisher | `lute test publish/tests` |
| Run the publisher | `lute publish/src/main.luau build --config rbxm-publish.json --out build/` |
| Build the plugin | `mkdir -p build && rojo build pull --output build/RbxmPull.rbxm` |
| Format | `stylua publish pull` |
| Lint the plugin | `cd pull && selene src` |

CI (`.github/workflows/ci.yml`) runs the format check, lint, tests and plugin build.
