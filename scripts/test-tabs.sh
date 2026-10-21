#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
tabs_test_root="$(mktemp -d "${TMPDIR:-/tmp}/winway-tabs.XXXXXX")"
trap 'rm -rf "$tabs_test_root"' EXIT
resource_bundle="$project_root/dist/Winway.app/Contents/Resources/Winway_WinwayApp.bundle"
[ -d "$resource_bundle" ] || { printf 'Run scripts/build-app.sh before this test.\n' >&2; exit 66; }
xcrun swiftc -swift-version 6 -emit-library -emit-module -module-name WinwayCore \
  "$project_root"/Sources/WinwayCore/{Models,Commands,FileSystem,Settings}/*.swift \
  -emit-module-path "$tabs_test_root/WinwayCore.swiftmodule" -o "$tabs_test_root/libWinwayCore.dylib"
cat > "$tabs_test_root/BundleAccessor.swift" <<'SWIFT'
import Foundation
extension Bundle {
    static var module: Bundle { Bundle(path: ProcessInfo.processInfo.environment["WINWAY_TEST_RESOURCE_BUNDLE"]!)! }
}
SWIFT
xcrun swiftc -swift-version 6 -parse-as-library -I "$tabs_test_root" -L "$tabs_test_root" -lWinwayCore \
  -Xlinker -rpath -Xlinker "$tabs_test_root" \
  "$tabs_test_root/BundleAccessor.swift" \
  "$project_root/Sources/WinwayApp/Application/AppModel.swift" \
  "$project_root"/Sources/WinwayApp/{Explorer,Settings,Platform}/*.swift \
  "$project_root/Tests/Standalone/TabsRunner.swift" -o "$tabs_test_root/tabs-tests"
WINWAY_TEST_RESOURCE_BUNDLE="$resource_bundle" "$tabs_test_root/tabs-tests"
