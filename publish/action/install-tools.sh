#!/usr/bin/env bash
# Installs the tools the rbxm-publish action needs into $RBXM_PUBLISH_BIN and adds it to PATH:
#   - lute, at the version pinned in this repo's foreman.toml (runs rbxm-publish from source)
#   - rojo, only if the caller doesn't already have one on PATH (so builds use their version)
set -euo pipefail

: "${RBXM_PUBLISH_BIN:?}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
foreman_toml="$repo_root/foreman.toml"

pinned_version() {
  # e.g. lute = { github = "luau-lang/lute", version = "=1.0.1-nightly.20261120" }
  sed -n "s/^$1 *=.*version *= *\"=\{0,1\}\([^\"]*\)\".*/\1/p" "$foreman_toml"
}

case "$RUNNER_OS" in
  Linux) os=linux ;;
  macOS) os=macos ;;
  Windows) os=windows ;;
  *) echo "::error::rbxm-publish: unsupported runner OS $RUNNER_OS"; exit 1 ;;
esac
case "$RUNNER_ARCH" in
  X64) arch=x86_64 ;;
  ARM64) arch=aarch64 ;;
  *) echo "::error::rbxm-publish: unsupported runner architecture $RUNNER_ARCH"; exit 1 ;;
esac

mkdir -p "$RBXM_PUBLISH_BIN"
echo "$RBXM_PUBLISH_BIN" >> "$GITHUB_PATH"
export PATH="$RBXM_PUBLISH_BIN:$PATH"

install_zip() { # name url
  local tmp
  tmp="$(mktemp -d)"
  echo "Installing $1 from $2"
  curl --fail --silent --show-error --location --retry 3 --output "$tmp/tool.zip" "$2"
  unzip -o -q "$tmp/tool.zip" -d "$RBXM_PUBLISH_BIN"
  chmod +x "$RBXM_PUBLISH_BIN/$1"* || true
  rm -rf "$tmp"
}

lute_version="$(pinned_version lute)"
install_zip lute "https://github.com/luau-lang/lute/releases/download/v$lute_version/lute-$os-$arch.zip"
lute --version

if command -v rojo > /dev/null 2>&1 && rojo --version > /dev/null 2>&1; then
  echo "Using the caller's $(rojo --version)"
else
  rojo_version="$(pinned_version rojo)"
  install_zip rojo "https://github.com/rojo-rbx/rojo/releases/download/v$rojo_version/rojo-$rojo_version-$os-$arch.zip"
  rojo --version
fi
