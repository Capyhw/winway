#!/bin/bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  printf 'Usage: %s /path/to/Winway.app\n' "$0" >&2
  exit 64
fi

project_root="$(cd "$(dirname "$0")/.." && pwd)"
input_application="$1"
if [ ! -d "$input_application/Contents" ] || [ ! -f "$input_application/Contents/Info.plist" ]; then
  printf 'Not an application bundle: %s\n' "$input_application" >&2
  exit 66
fi
input_application="$(cd "$input_application" && pwd)"
bundle_check_root="$(mktemp -d "${TMPDIR:-/tmp}/winway-bundle-check.XXXXXX")"
trap 'rm -rf "$bundle_check_root"' EXIT

# Copy the complete application so resource checks cannot pass by finding the
# source checkout, SwiftPM build directory, or the original application bundle.
/usr/bin/ditto "$input_application" "$bundle_check_root/Winway.app"
/usr/bin/xcrun swiftc -swift-version 6 \
  "$project_root/Tests/Standalone/BundleRunner.swift" \
  -o "$bundle_check_root/bundle-runner"
cd "$bundle_check_root"
"$bundle_check_root/bundle-runner" "$bundle_check_root/Winway.app"
# Exercise the production resource accessor as well as inspecting bundle files.
"$bundle_check_root/Winway.app/Contents/MacOS/Winway" --check-resources
