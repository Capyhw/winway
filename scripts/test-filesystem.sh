#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
fixture_root="$(mktemp -d /tmp/winway-filesystem-XXXXXX)"
mounted=0
cleanup() {
  if [ "$mounted" = 1 ]; then hdiutil detach "$fixture_root/mount" >/dev/null || true; fi
  rm -rf "$fixture_root"
}
trap cleanup EXIT
python3 "$project_root/Tests/Standalone/generate-filesystem-runner.py" "$fixture_root/tests.swift"
swiftc -swift-version 6 -parse-as-library \
  "$project_root/Sources/WinwayCore/Models/FileEntry.swift" \
  "$project_root/Sources/WinwayCore/FileSystem/"*.swift \
  "$fixture_root/tests.swift" -o "$fixture_root/tests"
if [ "${1:-}" != "--volumes" ]; then
  "$fixture_root/tests"
  exit 0
fi
# Only this freshly created image is mounted, made read-only, and detached.
hdiutil create -size 128m -fs APFS -volname WinwayFixture "$fixture_root/fixture.dmg"
hdiutil attach "$fixture_root/fixture.dmg" -nobrowse -mountpoint "$fixture_root/mount"
mounted=1
mkdir "$fixture_root/mount/winway-disconnected-fixture"
WINWAY_TEST_VOLUME="$fixture_root/mount" "$fixture_root/tests"
hdiutil detach "$fixture_root/mount"
mounted=0
hdiutil attach "$fixture_root/fixture.dmg" -readonly -nobrowse -mountpoint "$fixture_root/mount"
mounted=1
WINWAY_TEST_READONLY_VOLUME="$fixture_root/mount" "$fixture_root/tests"
hdiutil detach "$fixture_root/mount"
mounted=0
WINWAY_TEST_DISCONNECTED_PATH="$fixture_root/mount/winway-disconnected-fixture" "$fixture_root/tests"
