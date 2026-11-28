# rbxm-delivery: Rojo builds into Team Create, from GitHub releases

How rbxm-delivery works today. Two tools, one repo:
- **rbxm-publish**, the producer (§5): builds the `.rbxm` and publishes it to a channel.
- **rbxm-pull**, the consumer (§6, §7): the Studio plugin and apply module that pull a
  build into a place. Changes only ever flow this way, never back.

Planned work (auto-apply, the sync lease, 1.0 stability) is tracked in
[issues](https://github.com/Gravemind1142/rbxm-delivery/issues?q=is%3Aissue+label%3Aenhancement).

## 1. Problem

A team keeps code in git and builds it with Rojo, but the shared place is a Team Create
session that art and level designers own. Getting `main` into that session means someone
runs `rojo serve` and connects by hand. Saving from outside doesn't work either: Luau
Execution refuses to save a place with an active Team Create session.

rbxm-delivery moves code into the session **from inside it**: a Studio plugin pulls a
build from a GitHub release and applies it, so Team Create itself replicates the change
to every collaborator.

## 2. Scope

**In scope**
- A **producer**: a CLI and GitHub Action that build the managed containers with Rojo,
  write a manifest and update a rolling GitHub release.
- A **consumer**: a Studio plugin that fetches the release, verifies it and applies it to
  the open place.
- An **apply module** (plain Luau, §7) that the plugin uses and other tools, such as a Luau
  Execution task, can require, so a build is applied the same way everywhere.

**Out of scope**
- Syncing anything from the place back to git.
- `Content`, Workspace, Lighting, packages, or anything not listed as a container.
- Replacing `rojo serve` for personal User places.
- Hosting other than GitHub releases (the source is an interface, §6.1).

## 3. Concepts

- **Container:** an instance the build owns completely, named by its path in the place,
  for example `ReplicatedStorage/Systems`. Everything inside a container is replaced by
  the build; nothing outside is touched.
- **Build:** one `managed.rbxm` plus one `build.json`, produced from one commit.
- **Channel:** a rolling release tag, such as `dev-latest`, that always points at the
  newest build for a branch.
- **Marker:** `ServerStorage.RbxmPull`, a `Configuration` instance in the place holding
  the sync settings and what was last applied.

## 4. Artifact format (the contract)

`managed.rbxm` is plain Rojo output. `build.json` exists because no Rojo file records a
commit, a ref or hashes. rbxm-publish never adds fields to a Rojo project file; it reads
`default.project.json` as Rojo defines it (§5.1).

### 4.1 `managed.rbxm`

A model file whose root is a single `Folder` named `RbxmDeliveryBuild`. Each child is one
container, **named by its target path** (`ReplicatedStorage/Systems`), because two
containers can share a leaf name (`Systems` under both ReplicatedStorage and
ServerScriptService). The apply step renames each child to the leaf name of its path.

### 4.2 `build.json` (schema version 1)

```json
{
  "schemaVersion": 1,
  "commit": "3f2c...e1",
  "ref": "refs/heads/main",
  "builtAt": "2026-11-22T10:15:00Z",
  "artifact": { "size": 81234, "sha256": "9b1d...0a" },
  "containers": ["ReplicatedStorage/Systems", "ServerScriptService/Systems"]
}
```

- `artifact` describes `managed.rbxm` (the name is fixed).
- `containers` lists every container in the build, each once. No container is inside
  another (`A/B` and `A/B/C`); consumers refuse a manifest where one is.
- A consumer **refuses** an unknown `schemaVersion`. Adding optional fields doesn't bump
  it; changing the meaning of a field does.

## 5. Producer: rbxm-publish

A Lute program, shipped as a standalone executable (installable with Foreman) and as a
GitHub Action. Usage is in the [README](../README.md#rbxm-publish-build).

### 5.1 Config: `rbxm-publish.json`

```json
{
  "project": "default.project.json",
  "containers": ["ReplicatedStorage/Systems", "ServerScriptService/Systems"],
  "buildInfoModule": "ReplicatedStorage/Systems/BuildInfo"
}
```

- `project`: an ordinary Rojo project, unchanged. It stays the only file that maps code
  to source folders.
- `containers`: instance paths to build. Each is resolved by walking the project tree
  along the path; where a segment isn't an explicit node, the rest of the path is
  resolved on disk under the nearest ancestor's `$path`, using Rojo's file-name rules.
  The resolved node (or file) is copied into the generated project.
- `buildInfoModule` (optional): the producer writes a ModuleScript there returning
  `{ commit, ref, builtAt }`, so game code and smoke tests can read the running build.

Where to publish (`--channel`) and from which refs (`--allowed-ref`) are CLI flags and
Action inputs, not config: they describe the publishing workflow, not the build.

### 5.2 CLI

- `build` generates a temporary Rojo project (the `RbxmDeliveryBuild` wrapper, §4.1, with
  one child per container) next to the real one, runs `rojo build` on it, hashes the
  output and writes `build.json`. It fails if a container path can't be resolved or two
  container paths overlap.
- `release` verifies the build locally, refuses a `ref` that isn't an `--allowed-ref`,
  skips (successfully) if the channel already has a newer commit, then creates the
  channel release if missing, replaces its two assets, updates the release body and moves
  the tag. Assets are uploaded under temporary names and renamed into place, so a
  consumer mid-publish sees at worst a missing asset or a hash mismatch, both of which it
  refuses.
- `verify` runs the same local checks as `release` without publishing: a known
  `schemaVersion`, `managed.rbxm` size and SHA-256 matching `artifact`, and, with
  `--allowed-ref`, the ref. It exits 0 if the build is good and 1 with the reason if not;
  `--format json` prints `{ schemaVersion, commit, ref, builtAt, size, sha256, containers }`
  on one line. Pipelines that consume a build outside the plugin (§7.3) run it before
  uploading anything.

### 5.3 GitHub Action

`Gravemind1142/rbxm-delivery/publish@<tag>` (the repo's `publish/` folder) runs both
commands from source with the pinned Lute. A game's publishing workflow calls it after its
checks pass; only that workflow has `contents: write`.

## 6. Consumer: rbxm-pull plugin

Syncs on demand: a user presses **Sync now**. Nothing applies automatically.

### 6.1 Source

GitHub releases only, behind a small interface (`getManifest`, `getArtifact`) so other
hosts could be added.

- Manifest: `GET https://api.github.com/repos/{owner}/{repo}/releases/tags/{channel}`
  (optionally with `If-None-Match`; an unchanged release gets `304` with an empty body),
  then the `build.json` asset via `GET /repos/{owner}/{repo}/releases/assets/{id}` with
  `Accept: application/octet-stream`.
- Artifact: the same, for `managed.rbxm`. GitHub redirects to its release asset CDN,
  `release-assets.githubusercontent.com`. `HttpService` follows the redirect and returns
  the binary body intact. It forwards `Authorization` across the redirect, so with a token
  the CDN receives it too; that's a GitHub-owned host, so this is acceptable.
- `HttpService` refuses a `User-Agent` header and sends its own, which GitHub accepts.

### 6.2 Settings and the marker

| Setting | Where | Why |
|---|---|---|
| Repo, channel, allowed ref | Marker attributes `Repo`, `Channel`, `AllowedRef` | Shared: every collaborator syncs from the same source |
| GitHub token | `plugin:SetSetting`, per user and repo | Secret: never stored in the place |

Saving settings in a place without a marker creates it. Each apply writes `Commit`,
`SchemaVersion`, `AppliedAt`, `AppliedBy`, `Protocol` (§6.5) and `Containers` (the
applied paths, comma-separated). The marker also holds `Owners` and `IntervalSeconds`,
reserved for automatic syncing; nothing reads them yet.

### 6.3 Sync

**Check** (and opening the widget) fetches the manifest and compares it with the marker:

- **Not set up**: no marker, or no repo/channel.
- **Refused**: an unknown `schemaVersion`, a `ref` that isn't `AllowedRef`, or a marker
  `Protocol` newer than this plugin's (§6.5).
- **Behind**: the manifest's `commit` differs from the marker's `Commit`.
- **Up to date**: they match.

**Sync now** (when behind) downloads and verifies the artifact, checks the marker again
and stops if someone else applied that build meanwhile, then applies it (§7) as one
undoable step. It never applies while `RunService:IsRunning()` (a playtest).

**Re-sync** (when up to date) applies the same build again, discarding Studio edits to
managed code. It takes a second click to confirm and refuses if the marker's `Commit`
changed since the last check, so it can't roll back someone else's newer sync.

### 6.4 UI

A toolbar button opens a widget showing "Dev @ abc1234 · main @ def5678 · synced 2 min
ago", the last result, the commit's GitHub URL (selectable; plugins have no clipboard API),
and **Sync now**, **Re-sync**, **Check** and **Settings**.

### 6.5 Plugin versions

Collaborators may run different plugin versions: Studio only updates a plugin when the
user clicks **Update** in Manage Plugins.

- **Protocol.** Each plugin has a `PROTOCOL` number (currently 1) covering everything it
  reads and writes on the marker. It is bumped whenever any of that changes meaning. Every
  apply writes it to the marker's `Protocol`.
- **Older plugins are read-only.** A plugin whose `PROTOCOL` is lower than the marker's
  `Protocol` can't sync or change settings and says "Update rbxm-pull in Manage Plugins".
  This keeps an old plugin from writing state a newer one depends on.

### 6.6 Permissions

The plugin needs HTTP access to `api.github.com` and `release-assets.githubusercontent.com`
(Studio prompts once), and Script Injection to create and edit scripts.

## 7. Apply module (part of rbxm-pull)

Plain Luau with no plugin dependencies (`pull/src/Apply`). Its modules only require each
other, by path (`require("@self/Manifest")`), so the same source runs in the plugin, under
Lute, and in a project's own Luau Execution patch script, which pulls it in as the Lute
package `rbxm-apply` (§7.3).

```luau
Apply.apply(dataModel: DataModel, rbxm: buffer, manifest: Manifest, options: {
    dryRun: boolean?,        -- check and report, change nothing
    changeHistory: boolean?, -- one ChangeHistoryService recording (plugins only)
    appliedBy: number?,      -- user ID for the marker's AppliedBy
    onStep: ((step: string) -> ())?, -- called as each part of step 4 starts (tests)
}): Result -- { commit, replaced, added, removed, dryRun }

Apply.record(manifest, result): Record -- what was applied, for a deploy report (§7.3)
Apply.rolledBack(message: string): boolean -- whether a failed apply left the place as it was
Apply.Manifest.decode(json: string): Manifest -- refuses an unknown schemaVersion
Apply.VERSION -- the release version, e.g. "0.1.0"
```

Everything it needs from the last apply is on the marker, so it never needs an earlier
`build.json`.

### 7.1 Steps

1. Verify the size and SHA-256 of `rbxm` against `manifest.artifact` (pure-Luau SHA-256;
   about 1.7 s for 4 MiB in Studio).
2. Deserialize with `SerializationService:DeserializeInstancesAsync`. The root must be
   `RbxmDeliveryBuild` holding exactly the manifest's containers. A Rojo-built `.rbxm`
   round-trips script classes, `Source`, `RunContext`, attributes (including `Vector3` and
   `Color3` values) and tags; a Studio test applies a real rbxm-publish build to check this.
3. Resolve every target parent. If any is missing, stop **before changing anything**.
4. Inside the recording, if any:
   - **Remove** every container the marker's `Containers` lists, and everything at a path
     this manifest lists (every child of the parent with that name, not just the first).
     This also removes renamed and dropped containers. Removal is `Parent = nil` (as
     Studio's own Delete does), because a cancelled recording restores those but not
     `Destroy()`ed instances, and the rollback without a recording needs them intact too.
   - **Insert** each new container, renamed to its path's leaf name.
   - Write the marker (§6.2).
   - **Check** the result: the marker's `Commit` is the manifest's, and each container
     path resolves to exactly the inserted container.
5. Without a recording, `Destroy()` what was removed. (With one, it stays parented to nil
   so undo can bring it back.) Return what was replaced, added and removed.

Nothing inside a container is matched or kept; every script is a new instance on every
apply, so the place holds exactly what the build contains. Git owns managed code: the next
sync discards any Studio edit to it without warning. The costs:
- A collaborator with a managed script open is kicked from the script editor by every
  sync (Studio logs "Kicked from Live Scripting Session: Script was deleted"). Reopening
  the script from the Explorer shows the new source.
- A collaborator's unsaved draft of a managed script survives in the Drafts window, marked
  as deleted on the server, with **Restore script** and **Discard edit**. Choose **Discard
  edit** and make the change in git. **Restore script** puts a copy of the script in
  Workspace, outside every container, so syncs never remove it, and a restored `Script`
  runs there alongside the managed one.
- The sync is one undo step only for the collaborator who ran it. Their Ctrl+Z and Ctrl+Y
  undo and redo it for everyone through Team Create; other collaborators' history doesn't
  include it.
- References to managed instances from outside the containers (an `ObjectValue`, a
  property pointing at a ModuleScript) break on every sync. Levels should reach code
  through tags and attributes, which this doesn't affect.

### 7.2 Failure

`apply` is all or nothing in every host. Any error before step 4 changes nothing. An error
inside step 4 is rolled back and rethrown as `apply failed and was rolled back: <reason>`:

- **With a recording** (the plugin), the recording is cancelled
  (`ChangeHistoryService:FinishRecording` with `Cancel`) so Studio rolls the partial change
  back: containers removed with `Parent = nil` come back with their contents, and anything
  inserted is removed. This is tested in Studio, including a build of 5,000 scripts (rolled
  back in about half a second), and in Team Create
  ([#6](https://github.com/Gravemind1142/rbxm-delivery/issues/6)): every collaborator ends
  up with the original containers, the same instances with their Studio edits, and nothing
  inserted. The removal replicates before the rollback, though, so collaborators with a
  managed script open are still kicked from the script editor.
- **Without one** (any other host), Apply undoes the change by hand, newest first: it
  removes what it inserted, puts each removed instance back under its original parent
  (in reverse order, so nested removals come back correctly), and restores the marker's
  previous attributes, or removes the marker if it created it. The result is the same as a
  cancelled recording: the same instances, with their contents, attributes and tags, and
  in both cases a restored container ends up last among its siblings. Tested in Studio
  alongside the recording, including the 5,000-script build (about 0.6 s).

If restoring itself fails, Apply keeps restoring what it can and errors with
`apply failed and couldn't be fully rolled back (<what failed>); don't save this place:
<reason>`. That can't happen through Apply's own steps; it would take something else
changing the place mid-apply (such as a parent that refuses children).

### 7.3 In a Luau Execution task: the `rbxm-apply` package

An Open Cloud [Luau Execution](https://create.roblox.com/docs/cloud/reference/features/luau-execution)
task runs one script source against a saved place version, so CI can patch a place (for
example a Stable copy of Dev) with the same code the plugin uses, then save and publish it.

rbxm-delivery doesn't ship that script, and has no say in how it's built. What a patch
does besides applying the build (stripping PackageLinks, stamping build info, which refs
may ship), in what order, what counts as success, and how it becomes one script source are
the project's call. rbxm-delivery only ships Apply as a library for it: the Lute package `rbxm-apply`
(`pull/pkg.luau`, holding only `pull/src/Apply`). A project depends on it from this
repository, pinned to the release tag that matches its `rbxm-publish`, so the build and the
code applying it always come from the same release:

```luau
-- the project's pkg.luau
return {
    package = {
        dependencies = {
            rbxmApply = {
                sourceKind = "github",
                source = "https://github.com/Gravemind1142/rbxm-delivery",
                rev = "v0.1.0",
                target = "pull",
            },
        },
    },
}
```

`lute pkg install --vendor` copies the package's files into the project's `.lpm/`. From
there the project gets Apply into its task however it likes, as long as the task's one
script source can reach it: bundling the patch script and the package into one file, or
passing Apply as a ModuleScript in a binary input. Apply's modules only require each other
with `@self` paths, which bundlers that follow the Luau require rules and the engine itself
both resolve.

A patch script typically looks like this, in whatever shape the project's task runner
expects:

```luau
local Apply = require("@rbxmApply")

return function(ctx)
    local manifest = Apply.Manifest.decode(buffer.tostring(ctx.inputs["build.json"]))
    -- check manifest.ref against the project's allowed refs
    local result = Apply.apply(game, ctx.inputs["managed.rbxm"], manifest, {})
    -- ...the project's other steps, each checking its own result...
    return { ok = true, summary = `applied {manifest.commit}`, record = Apply.record(manifest, result) }
end
```

with errors caught and reported with `Apply.rolledBack(message)`. `lute apply-e2e` loads
Apply from the plugin model as a ModuleScript and applies the fixture build as a real
task.

What Apply gives the patch script:
- **Checks:** `Apply.Manifest.decode` refuses an unknown `schemaVersion` and a malformed
  `build.json`; `Apply.apply` checks the size and SHA-256, the build's shape and every target
  parent before changing anything, and checks its own result after (§7.1).
- **A record:** `Apply.record(manifest, result)` holds `applyVersion`, the same build fields
  as `rbxm-publish verify --format json` (`schemaVersion`, `commit`, `ref`, `builtAt`,
  `size`, `sha256`, `containers`), and `replaced`, `added`, `removed` and `dryRun`, so a
  pipeline can check that the task applied the build it verified.
- **All or nothing:** a failed apply is rolled back by hand (§7.2). `Apply.rolledBack(err)`
  is false only for an error starting `apply failed and couldn't be fully rolled back`. It
  never saves: the task runner saves only when the script returns `ok = true`, so a partial
  change from a later step isn't saved either.

Differences from the plugin:
- No user: the marker's `AppliedBy` is 0.
- No `ChangeHistoryService`: tasks lack the Plugin capability, so Apply never fetches the
  service without `changeHistory`, and rolls back by hand (§7.2).
- Native code: SHA-256 is much slower without it. `--!native` only applies at the top of a
  task's source, so the task runner, not the patch script, has to set it.
- A task is limited to 5 minutes, shared with the project's other steps. SHA-256 is about
  1.6 s per 4 MiB in Studio, and rollback of 5,000 scripts about 0.6 s.
- Run `rbxm-publish verify` (§5.2) on the build before creating the task, to fail before
  uploading anything.

## 8. Security

- **Trust root:** whoever can write the channel's release assets. Keep that to the one
  workflow on a protected branch. `--allowed-ref` and `AllowedRef` only catch mistakes; they
  don't stop someone with release-write access.
- **Token:** fine-grained, read-only `contents: read` on one repo, stored per user in
  plugin settings. A private repo needs one; a public repo works without (60 requests per
  hour per IP).
- The plugin never executes downloaded code itself. It places scripts in the game, which
  run when the game runs, exactly as if `rojo serve` had put them there.
