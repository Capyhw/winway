#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
version=0.2.1
architecture="$(uname -m)"
destination="$project_root/.build/fsearch/$version/$architecture"
mkdir -p "$destination"
if [[ "$architecture" == x86_64 ]]; then
  # Use the verified Intel build tracked with the source, even if a stale local
  # build exists. Verify before copying so a damaged binary cannot be packaged.
  prebuilt="$project_root/ThirdParty/FSearch/bin/$version/$architecture"
  (cd "$prebuilt" && shasum -a 256 -c fsearch.sha256) >&2
  cp "$prebuilt/fsearch" "$destination/fsearch"
  chmod +x "$destination/fsearch"
elif [[ ! -x "$destination/fsearch" ]]; then
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
  else
    printf 'Unsupported FSearch architecture: %s\n' "$architecture" >&2
    exit 69
  fi
  chmod +x "$destination/fsearch"
fi
lipo "$destination/fsearch" -verify_arch "$architecture"
printf '%s\n' "$destination/fsearch"
