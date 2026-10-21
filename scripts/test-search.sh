#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
search_test_root="$(mktemp -d "${TMPDIR:-/tmp}/winway-search.XXXXXX")"
trap 'rm -rf "$search_test_root"' EXIT
resource_bundle="$project_root/dist/Winway.app/Contents/Resources/Winway_WinwayApp.bundle"
[ -d "$resource_bundle" ] || { printf 'Run scripts/build-app.sh before this test.\n' >&2; exit 66; }
xcrun swiftc -swift-version 6 -emit-library -emit-module -module-name WinwayCore \
  "$project_root"/Sources/WinwayCore/{Models,Commands,FileSystem,Settings}/*.swift \
  -emit-module-path "$search_test_root/WinwayCore.swiftmodule" -o "$search_test_root/libWinwayCore.dylib"
cat > "$search_test_root/BundleAccessor.swift" <<'SWIFT'
import Foundation
extension Bundle {
    static var module: Bundle { Bundle(path: ProcessInfo.processInfo.environment["WINWAY_TEST_RESOURCE_BUNDLE"]!)! }
}
SWIFT
xcrun swiftc -swift-version 6 -parse-as-library -I "$search_test_root" -L "$search_test_root" -lWinwayCore \
  -Xlinker -rpath -Xlinker "$search_test_root" \
  "$search_test_root/BundleAccessor.swift" \
  "$project_root/Sources/WinwayApp/Application/AppModel.swift" \
  "$project_root"/Sources/WinwayApp/{Explorer,Settings,Platform}/*.swift \
  "$project_root/Tests/Standalone/SearchRunner.swift" -o "$search_test_root/search-tests"
WINWAY_TEST_RESOURCE_BUNDLE="$resource_bundle" "$search_test_root/search-tests"
