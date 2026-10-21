#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
ui_check_root="$(mktemp -d "${TMPDIR:-/tmp}/winway-ui-components.XXXXXX")"
trap 'rm -rf "$ui_check_root"' EXIT
resource_bundle="$project_root/dist/Winway.app/Contents/Resources/Winway_WinwayApp.bundle"
[ -d "$resource_bundle" ] || { printf 'Run scripts/build-app.sh before this test.\n' >&2; exit 66; }
xcrun swiftc -swift-version 6 -emit-library -emit-module -module-name WinwayCore \
  "$project_root/Sources/WinwayCore/Models/FileEntry.swift" \
  "$project_root/Sources/WinwayCore/Models/NavigationState.swift" \
  "$project_root/Sources/WinwayCore/Commands/KeyboardCommands.swift" \
  -emit-module-path "$ui_check_root/WinwayCore.swiftmodule" -o "$ui_check_root/libWinwayCore.dylib"
cat > "$ui_check_root/BundleAccessor.swift" <<'SWIFT'
import Foundation
extension Bundle {
    static var module: Bundle { Bundle(path: ProcessInfo.processInfo.environment["WINWAY_TEST_RESOURCE_BUNDLE"]!)! }
}
SWIFT
xcrun swiftc -swift-version 6 -parse-as-library -I "$ui_check_root" -L "$ui_check_root" -lWinwayCore \
  -Xlinker -rpath -Xlinker "$ui_check_root" \
  "$ui_check_root/BundleAccessor.swift" "$project_root"/Sources/WinwayApp/Explorer/*.swift \
  "$project_root/Tests/Standalone/UIComponentRunner.swift" -o "$ui_check_root/ui-components"
WINWAY_TEST_RESOURCE_BUNDLE="$resource_bundle" "$ui_check_root/ui-components"
