#!/bin/bash
set -euo pipefail
root=/Users/weiyuhang/code/myCode/winway
evidence_root="$(cd "$(dirname "$0")" && pwd)"
probe_root=$(mktemp -d /tmp/winway-review-build-XXXXXX)
trap 'rm -rf "$probe_root"' EXIT
xcrun swiftc -O -swift-version 6 -emit-library -emit-module -module-name WinwayCore "$root"/Sources/WinwayCore/*/*.swift -emit-module-path "$probe_root/WinwayCore.swiftmodule" -o "$probe_root/libWinwayCore.dylib"
cat > "$probe_root/BundleAccessor.swift" <<'SWIFT'
import Foundation
extension Bundle {
 static var module: Bundle { Bundle(path: "/Users/weiyuhang/code/myCode/winway/dist/Winway.app/Contents/Resources/Winway_WinwayApp.bundle")! }
}
SWIFT
xcrun swiftc -O -swift-version 6 -parse-as-library -I "$probe_root" -L "$probe_root" -lWinwayCore -Xlinker -rpath -Xlinker "$probe_root" "$probe_root/BundleAccessor.swift" "$root"/Sources/WinwayApp/Explorer/*.swift "$root"/Sources/WinwayApp/Settings/*.swift "$root"/Sources/WinwayApp/Platform/*.swift "$root"/Sources/WinwayApp/Application/AppModel.swift "$evidence_root/ReviewProbe.swift" -o "$probe_root/probe"
"$probe_root/probe"
