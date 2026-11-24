# Security

rbxm-delivery moves code from a GitHub release into a Roblox place, so a flaw can let
someone get their code into your game. Please report security problems privately through
[GitHub's private vulnerability reporting](https://github.com/Gravemind1142/rbxm-delivery/security/advisories/new),
not in a public issue.

Include what you found, how to reproduce it, and what an attacker could do with it.

## Supported versions

Only the latest release gets fixes while rbxm-delivery is pre-1.0.

## Trust model

See [spec §8](docs/spec.md#8-security). In short: whoever can write a channel's release
assets decides what code reaches the place, so keep `contents: write` to one workflow on a
protected branch. `allowed-refs` only catches mistakes. The plugin's GitHub token is stored
per user in Studio's plugin settings, never in the place.
