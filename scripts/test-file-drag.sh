#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
file_drag_test_root="$(mktemp -d "${TMPDIR:-/tmp}/winway-file-drag.XXXXXX")"
trap 'rm -rf "$file_drag_test_root"' EXIT
resource_bundle="$project_root/dist/Winway.app/Contents/Resources/Winway_WinwayApp.bundle"
[ -d "$resource_bundle" ] || { printf 'Run scripts/build-app.sh before this test.\n' >&2; exit 66; }
xcrun swiftc -swift-version 6 -emit-library -emit-module -module-name WinwayCore \
  "$project_root"/Sources/WinwayCore/{Models,Commands,FileSystem,Settings}/*.swift \
  -emit-module-path "$file_drag_test_root/WinwayCore.swiftmodule" -o "$file_drag_test_root/libWinwayCore.dylib"
cat > "$file_drag_test_root/BundleAccessor.swift" <<'SWIFT'
import Foundation
extension Bundle {
    static var module: Bundle { Bundle(path: ProcessInfo.processInfo.environment["WINWAY_TEST_RESOURCE_BUNDLE"]!)! }
}
SWIFT
xcrun swiftc -swift-version 6 -parse-as-library -I "$file_drag_test_root" -L "$file_drag_test_root" -lWinwayCore \
  -Xlinker -rpath -Xlinker "$file_drag_test_root" \
  "$file_drag_test_root/BundleAccessor.swift" \
  "$project_root/Sources/WinwayApp/Application/AppModel.swift" \
  "$project_root"/Sources/WinwayApp/{Explorer,Settings,Platform}/*.swift \
  "$project_root/Tests/Standalone/FileDragRunner.swift" -o "$file_drag_test_root/file-drag-tests"
WINWAY_TEST_RESOURCE_BUNDLE="$resource_bundle" "$file_drag_test_root/file-drag-tests"
