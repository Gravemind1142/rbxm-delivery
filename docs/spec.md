# rbxm-delivery: Rojo builds into Team Create, from GitHub releases

Status: rbxm-publish built (CLI and Action); rbxm-pull at v0.1 (manual Sync now). Two tools,
one repo:
- **rbxm-publish**, the producer (§5): builds the `.rbxm` and publishes it to a channel.
- **rbxm-pull**, the consumer (§6, §7): the Studio plugin and apply module that pull a
  build into a place. Changes only ever flow this way, never back.

Used by the template's `main.yml` (architecture §5.2) and Dev sync (architecture §5.3),
and its artifact format is the input to the Stable patch task (architecture §5.4).

## 1. Problem

A team keeps code in git and builds it with Rojo, but the shared place is a Team Create
session that art and level designers own. Getting `main` into that session today means
someone runs `rojo serve` and connects by hand. Saving from outside doesn't work either:
Luau Execution refuses to save a place with an active Team Create session.

rbxm-delivery moves code into the session **from inside it**: a Studio plugin that pulls a
build from a GitHub release and applies it, so Team Create itself replicates the change
to every collaborator.

## 2. Scope

**In scope**
- A **producer**: a CLI and GitHub Action that builds the managed containers with Rojo,
  writes a manifest and updates a rolling GitHub release.
- A **consumer**: a Studio plugin that checks the release, verifies it and applies it to
  the open place.
- A shared **apply module** (plain Luau) that both the plugin and other tools (such as a
  Luau Execution patch task) use, so a build is applied the same way everywhere.

**Out of scope**
- Syncing anything from the place back to git.
- `Content`, Workspace, Lighting, packages, or anything not listed as a container.
- Replacing `rojo serve` for personal User places.
- Hosting other than GitHub releases in v1 (the source is an interface, §6.1).

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

**Why these formats.** `managed.rbxm` is plain Rojo output. `build.json` exists because no
Rojo file records a commit, a ref or hashes. rbxm-publish never adds fields to a Rojo
project file; it reads `default.project.json` as Rojo defines it (§5.1).

### 4.1 `managed.rbxm`

A model file whose root is a single `Folder` named `RbxmDeliveryBuild`. Each child is one
container, **named by its target path** (`ReplicatedStorage/Systems`), because two
containers can share a leaf name (`Systems` under both ReplicatedStorage and
ServerScriptService). The producer creates this wrapper in the project it generates
(§5.2). The apply step renames each child to the leaf name of its path.

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
- `containers` lists every container in the build.
- A consumer **refuses** an unknown `schemaVersion`. Adding optional fields doesn't bump
  it; changing the meaning of a field does.

## 5. Producer: rbxm-publish

### 5.1 Config: `rbxm-publish.json` in the repo

```json
{
  "project": "default.project.json",
  "containers": [
    "ReplicatedStorage/Systems",
    "ReplicatedStorage/Libraries",
    "ReplicatedStorage/ManagedContent",
    "ReplicatedStorage/Generated",
    "ReplicatedStorage/Contract",
    "ServerScriptService/Systems"
  ],
  "buildInfoModule": "ReplicatedStorage/Contract/BuildInfo"
}
```

- `project`: an ordinary Rojo project, unchanged. It stays the only file that maps code
  to source folders, so no separate `managed.project.json` is needed.
- `containers`: instance paths to build. Each is resolved by walking the project tree
  along the path; where a segment isn't an explicit node, the rest of the path is
  appended to the nearest ancestor's `$path`. The resolved node (or folder) is copied into
  the generated project.
- `buildInfoModule` (optional): the producer writes a ModuleScript there returning
  `{ commit, ref, builtAt }`, so game code and smoke tests can read the running build.

Where to publish (`--channel`) and from which refs (`--allowed-ref`) are CLI flags and
Action inputs, not config: they describe the publishing workflow, not the build.

### 5.2 CLI

Written in Lute, installed via Foreman.

```sh
rbxm-publish build   --config rbxm-publish.json --out build/     # managed.rbxm + build.json
rbxm-publish release --dir build/ --repo owner/name --channel dev-latest \
                     --allowed-ref refs/heads/main                # needs GITHUB_TOKEN
```

- `build` generates a temporary Rojo project (the `RbxmDeliveryBuild` wrapper, §4.1, with
  one child per container), runs `rojo build` on it, hashes the output and writes
  `build.json`. It fails if a container path can't be resolved in the
  project or two container paths overlap.
- `release` creates the channel release if missing, otherwise replaces its two assets, and
  sets the release body to the commit and build time. It refuses to release a build whose
  `ref` isn't an `--allowed-ref` (repeatable).

### 5.3 GitHub Action

`<org>/rbxm-delivery/publish@v1` (an action in the repo's `publish/` folder) wraps both
commands. Inputs: `config`, `channel`,
`allowed-refs`, `github-token`. The template's `main.yml` calls it after the checks pass.
Only that workflow has `contents: write`.

## 6. Consumer: rbxm-pull plugin

### 6.1 Source

v1 supports GitHub releases only, behind a small interface (`getManifest`,
`getArtifact`) so other hosts can be added.

- Manifest: `GET https://api.github.com/repos/{owner}/{repo}/releases/tags/{channel}`
  with `If-None-Match`, then the `build.json` asset via
  `GET /repos/{owner}/{repo}/releases/assets/{id}` with `Accept: application/octet-stream`.
- Artifact: same, for `managed.rbxm`. GitHub answers with a redirect to its release asset
  CDN, `release-assets.githubusercontent.com` (checked 2026-11-23). `HttpService` follows
  the redirect and returns the binary body intact. It **does** forward `Authorization`
  across redirects, even to another host, so with a token the CDN receives it too. The CDN
  accepts that (tested by forwarding a token with `curl --location-trusted`), and it's a
  GitHub-owned host, so this is acceptable.
- `HttpService` refuses a `User-Agent` header; it sends its own, which GitHub accepts.
  `Accept`, `Authorization` and `If-None-Match` can be set.

### 6.2 Settings

| Setting | Where | Why |
|---|---|---|
| Repo, channel, allowed ref | Marker attributes (`Repo`, `Channel`, `AllowedRef`) | Shared: every collaborator syncs from the same source |
| Sync owners | Marker attribute `Owners` (comma-separated user IDs, highest priority first) | Shared: who auto-applies, in what order |
| Check interval | Marker attribute `IntervalSeconds` (default 180) | Shared |
| GitHub token | `plugin:SetSetting`, per user | Secret: never stored in the place |

A place without a marker shows a "Set up rbxm-pull" button that creates it. Only users
who can edit the place can do this anyway.

### 6.3 Loop

1. On place open, then every `IntervalSeconds`, skip if `RunService:IsRunning()` (never
   apply during a playtest).
2. Fetch the manifest. If the ETag is unchanged, stop.
3. Refuse if `schemaVersion` is unknown, `ref` isn't `AllowedRef`, or the marker's
   `Protocol` is newer than this plugin's (§6.6).
4. If `commit` equals the marker's `Commit`, stop.
5. Work out the **active owner**: the first user in `Owners` who is in the session. Team
   Create adds every active collaborator to `Players`, so this needs no extra state, and
   every plugin reaches the same answer. If the active owner is this user, apply.
   Otherwise show "Dev is behind" with a **Sync now** button.
6. To apply (automatically or via **Sync now**): download and verify the artifact (§7.1
   step 1), take the lease (§6.4), check the marker's `Commit` again and stop if it
   already matches, then apply (§7) and release the lease.

If the active owner leaves, the next owner in the list takes over on their next check.

### 6.4 Lease

The priority list means only one plugin auto-applies. The lease covers the rest: a
**Sync now** press colliding with the active owner, and the moment the active owner
changes, when two plugins can briefly disagree about who is in `Players`.

The plugin writes `SyncLease = "<userId>:<unix expiry>"` on the marker (expiry 60
seconds), waits for it to replicate, re-reads it, and continues only if it's still its
own. A plugin that sees an unexpired lease from someone else **skips** this check and
tries again on the next. The holder renews the lease while applying, so a long apply
can't outlive it. This is best-effort; Team Create has no real lock. Re-checking `Commit`
after taking the lease (§6.3 step 6) and destroying everything at a container's path
(§7.1) make a double apply harmless. **⚠ verify** attribute replication latency in Team
Create is short enough for this.

### 6.5 UI

A toolbar button and a small widget:
- "Dev @ abc123 · main @ def456 · synced 2 min ago" (or "behind by 3 builds" when the
  release body has that).
- **Sync now**, **Open commit** (copies the GitHub URL), **Settings**.
- The last apply's result.

### 6.6 Plugin versions

Collaborators will run different plugin versions: Studio only updates a plugin when the
user clicks **Update** in Manage Plugins (which reloads it in place). So:

- **Protocol.** Each plugin has a `PROTOCOL` number covering everything it reads and
  writes on the marker: its attributes, the lease format and the active-owner rule. It
  is bumped whenever any of those change meaning. Every apply writes it to the marker's
  `Protocol`.
- **Older plugins never apply.** A plugin whose `PROTOCOL` is lower than the marker's
  `Protocol` is read-only: it never auto-applies, disables **Sync now**, and shows
  "Update rbxm-pull in Manage Plugins". This keeps an old plugin from writing state a
  newer one depends on.
- **Stalls are visible.** If the active owner's plugin can't apply (old protocol or an
  unknown `schemaVersion`), it says so in its widget. Everyone else's widget shows that
  Dev is behind, and anyone with a current plugin can press **Sync now**.
- **Update prompt.** The plugin compares its own build time with its asset's `Updated`
  time from `MarketplaceService:GetProductInfo` and shows "Update available" when the
  asset is newer. **⚠ verify** a plugin can read its own asset's info this way.

### 6.7 Permissions

The plugin needs HTTP access to `api.github.com` and the release asset host (the user
approves Studio's prompt once), and Script Injection to create and edit scripts.

## 7. Apply module (part of rbxm-pull)

Plain Luau, shipped inside the plugin and as a standalone module
(`RbxmPull/Apply.luau`) so a Luau Execution task can require it too.

```luau
Apply.apply(dataModel: DataModel, rbxm: buffer, manifest: Manifest, options: {
    dryRun: boolean?,
}): Result
```

Everything it needs from the last apply is on the marker, so it never needs an earlier
`build.json`.

### 7.1 Steps

1. Verify the SHA-256 of `rbxm` against `manifest.artifact.sha256`. A pure-Luau SHA-256
   hashes 4 MiB in about 1.7 s in Studio, which is fast enough; no second hash is needed.
2. Deserialize with `SerializationService:DeserializeInstancesAsync`. Check the root has
   exactly the containers the manifest lists.
3. Resolve every target parent. If any is missing, stop **before changing anything**.
4. Inside one `ChangeHistoryService` recording (plugin only):
   - **Remove** every container the marker's `Containers` lists, and anything at a path
     this manifest lists. "Anything at a path" means every child of the parent with that
     name, not just the first, so a duplicate left by a race is cleaned up. This also
     removes renamed and deleted containers. Inside a recording, remove with
     `Parent = nil` (as Studio's own Delete does), not `Destroy()`: a cancelled recording
     restores the former but not the latter. Without a recording, `Destroy()`.
   - **Insert** each new container: rename it to its path's leaf name and parent it there.
   - Write the marker: `Commit`, `SchemaVersion`, `AppliedAt`, `AppliedBy`, `Protocol`
     (§6.6), and `Containers` (this manifest's paths, comma-separated).
5. Return a result: containers replaced, added and removed.

Nothing inside a container is matched or kept; every script is a new instance on every
apply, so the place holds exactly what the build contains. Managed code is never edited
in Studio: git owns it, and the next sync discards any such edit without warning. The
costs:
- A collaborator with a managed script open has it closed (or left open on a destroyed
  instance) by every sync.
- References to managed instances from outside the containers (an `ObjectValue`, a
  property pointing at a ModuleScript) break on every sync. Levels must reach code only
  through tags and attributes, which this doesn't affect.

### 7.2 Failure

Any error before step 4 changes nothing. An error inside step 4 cancels the recording
(`ChangeHistoryService:FinishRecording` with `Cancel`) so Studio rolls the partial change
back. Verified locally: cancelling restores containers removed with `Parent = nil` (with
their contents) and removes anything inserted. `Destroy()`ed instances are **not**
restored. **⚠ verify** the same holds in Team Create.

## 8. Security

- **Trust root:** whoever can write the channel's release assets. Keep that to the one
  workflow on a protected branch. `--allowed-ref` and `AllowedRef` only catch mistakes; they
  don't stop someone with release-write access.
- **Token:** fine-grained, read-only `contents: read` on one repo, stored per user in
  plugin settings. A private repo needs one; a public repo works without (60 requests per
  hour per IP).
- The plugin never executes downloaded code itself. It places scripts in the game, which
  run when the game runs, exactly as if `rojo serve` had put them there.

## 9. Open questions

1. ~~`HttpService` behaviour~~: answered in §6.1. `If-None-Match` with the release's ETag
   gets `304` with an empty body.
2. `DeserializeInstancesAsync` round-trips a Rojo-built `.rbxm`: verified for script
   classes and `Source` (rbxm-pull's Fixture test applies a real rbxm-publish build).
   Attributes, tags and `RunContext` aren't covered by that fixture yet.
3. Collaborative Editing: what a collaborator sees when a script they have open is
   destroyed, and whether their unsaved drafts block or survive the replace.
4. Change history: a cancelled recording reverts an apply locally when removal uses
   `Parent = nil` (§7.2). Still open: Team Create, and very large applies.
5. Team Create presence: that `Players` lists every active collaborator with the right
   `UserId` in edit mode, on every collaborator's machine, and how quickly joins and
   leaves show up there.

## 10. Milestones

- **v0.1:** `rbxm-publish build` and `release`; plugin with manual **Sync now** only; whole-container
  replace, including removal of dropped containers; hash check; marker with `Protocol`
  (old plugins can only be kept out if the first version already checks it).
- **v0.2:** auto-apply by the active owner, lease, ETag polling, toolbar status.
- **v1.0:** schema and protocol frozen, Apply module published for Luau Execution use.
