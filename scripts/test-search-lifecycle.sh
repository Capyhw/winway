#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/winway-search-exit.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT
app="$test_root/Winway.app"
ditto "$project_root/dist/Winway.app" "$app"
plutil -replace CFBundleIdentifier -string app.winway.lifecycle-test "$app/Contents/Info.plist"
rm "$app/Contents/Helpers/fsearch"
xcrun clang "$project_root/Tests/Fixtures/FSearchLifecycleHelper.c" -o "$app/Contents/Helpers/fsearch"
codesign --force --sign - "$app/Contents/Helpers/fsearch"
codesign --force --sign - "$app"
xcrun swiftc -swift-version 6 -parse-as-library \
  "$project_root/Tests/Standalone/SearchLifecycleRunner.swift" -o "$test_root/search-exit-tests"
"$test_root/search-exit-tests" "$app"
