#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/winway-settings.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT
resource_bundle="$project_root/dist/Winway.app/Contents/Resources/Winway_WinwayApp.bundle"
xcrun swiftc -swift-version 6 -emit-library -emit-module -module-name WinwayCore \
  "$project_root"/Sources/WinwayCore/{Models,Commands,FileSystem,Settings}/*.swift \
  -emit-module-path "$test_root/WinwayCore.swiftmodule" -o "$test_root/libWinwayCore.dylib"
cat > "$test_root/BundleAccessor.swift" <<'SWIFT'
import Foundation
extension Bundle {
    static var module: Bundle { Bundle(path: ProcessInfo.processInfo.environment["WINWAY_TEST_RESOURCE_BUNDLE"]!)! }
}
SWIFT
xcrun swiftc -swift-version 6 -parse-as-library -I "$test_root" -L "$test_root" -lWinwayCore \
  -Xlinker -rpath -Xlinker "$test_root" \
  "$test_root/BundleAccessor.swift" \
  "$project_root"/Sources/WinwayApp/{Explorer,Settings,Platform}/*.swift \
  "$project_root/Tests/Standalone/SettingsRunner.swift" -o "$test_root/settings-tests"
WINWAY_TEST_RESOURCE_BUNDLE="$resource_bundle" "$test_root/settings-tests"
