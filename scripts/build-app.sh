#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
configuration="${1:-release}"
if [[ -n "${WINWAY_VERSION:-}" && ! "$WINWAY_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf 'WINWAY_VERSION must be a numeric major.minor.patch version.\n' >&2
  exit 64
fi
if [[ -n "${WINWAY_BUILD_NUMBER:-}" && ! "$WINWAY_BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  printf 'WINWAY_BUILD_NUMBER must be a positive integer.\n' >&2
  exit 64
fi
"$project_root/scripts/build.sh" -c "$configuration"
binary_directory="$("$project_root/scripts/build.sh" -c "$configuration" --show-bin-path)"
# Catch SDK regressions before replacing the runnable application bundle.
expected_sdk="$(xcrun --sdk macosx --show-sdk-version)"
expected_minimum="$(plutil -extract LSMinimumSystemVersion raw Packaging/Info.plist)"
build_versions="$(xcrun vtool -show-build "$binary_directory/Winway")"
actual_sdk="$(awk '$1 == "sdk" { print $2 }' <<< "$build_versions")"
actual_minimum="$(awk '$1 == "minos" { print $2 }' <<< "$build_versions")"
if [[ "$actual_sdk" != "$expected_sdk" || "$actual_minimum" != "$expected_minimum" ]]; then
  printf 'Unexpected build versions: SDK %s (expected %s), minimum macOS %s (expected %s)\n' \
    "$actual_sdk" "$expected_sdk" "$actual_minimum" "$expected_minimum" >&2
  exit 1
fi
printf 'Verified SDK %s, minimum macOS %s\n' "$actual_sdk" "$actual_minimum"
app_directory="$project_root/dist/Winway.app"
mkdir -p "$app_directory/Contents/MacOS" "$app_directory/Contents/Resources"
cp "$binary_directory/Winway" "$app_directory/Contents/MacOS/Winway"
cp Packaging/Info.plist "$app_directory/Contents/Info.plist"
if [[ -n "${WINWAY_VERSION:-}" ]]; then
  plutil -replace CFBundleShortVersionString -string "$WINWAY_VERSION" "$app_directory/Contents/Info.plist"
fi
if [[ -n "${WINWAY_BUILD_NUMBER:-}" ]]; then
  plutil -replace CFBundleVersion -string "$WINWAY_BUILD_NUMBER" "$app_directory/Contents/Info.plist"
fi
for resource_bundle in "$binary_directory"/*.bundle; do
  [ -e "$resource_bundle" ] || continue
  cp -R "$resource_bundle" "$app_directory/Contents/Resources/"
done
if [ -f Packaging/Winway.icns ]; then
  cp Packaging/Winway.icns "$app_directory/Contents/Resources/"
fi
codesign --force --sign - "$app_directory"
codesign --verify --deep --strict "$app_directory"
printf '%s\n' "$app_directory"
