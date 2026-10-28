#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
version=0.2.1
revision=88e63fdf850cf7749deae8198b187accd21f8ba5
architecture="$(uname -m)"
destination="$project_root/.build/fsearch/$version/$architecture"
mkdir -p "$destination"
if [[ ! -x "$destination/fsearch" ]]; then
  work="$(mktemp -d "${TMPDIR:-/tmp}/winway-fsearch-build.XXXXXX")"
  trap 'rm -rf "$work"' EXIT
  if [[ "$architecture" == arm64 ]]; then
    curl --fail --location --retry 3 \
      "https://github.com/noahdunnagan/fsearch/releases/download/v$version/fsearch-aarch64-apple-darwin.tar.gz" \
      -o "$work/fsearch.tar.gz"
    (cd "$work" && printf '%s  fsearch.tar.gz\n' \
      08f68fe10362732f701be3ddf59cb370920c5a08af63e76b15addf8aca118d2f | shasum -a 256 -c -) >&2
    tar -xzf "$work/fsearch.tar.gz" -C "$work" fsearch
    cp "$work/fsearch" "$destination/fsearch"
  elif [[ "$architecture" == x86_64 ]]; then
    command -v cargo >/dev/null || { printf 'Building FSearch for Intel requires Rust 1.92 or newer (cargo).\n' >&2; exit 69; }
    git init -q "$work/source"
    git -C "$work/source" fetch --depth 1 https://github.com/noahdunnagan/fsearch.git "$revision" >&2
    git -C "$work/source" checkout --detach FETCH_HEAD >&2
    MACOSX_DEPLOYMENT_TARGET=13.0 RUSTFLAGS='-C target-cpu=x86-64' \
      cargo build --manifest-path "$work/source/Cargo.toml" --release --locked --target x86_64-apple-darwin >&2
    cp "$work/source/target/x86_64-apple-darwin/release/fsearch" "$destination/fsearch"
  else
    printf 'Unsupported FSearch architecture: %s\n' "$architecture" >&2
    exit 69
  fi
  chmod +x "$destination/fsearch"
fi
lipo "$destination/fsearch" -verify_arch "$architecture"
printf '%s\n' "$destination/fsearch"
