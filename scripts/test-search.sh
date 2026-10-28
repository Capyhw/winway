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
fsearch_binary="$project_root/dist/Winway.app/Contents/Helpers/fsearch"
# A cold daemon can answer scoped queries from a cached early index while its
# initial whole-disk scan is still running. File-change tests require the live
# index, where FSEvents updates are applied, rather than that early snapshot.
python3 - "$fsearch_binary" <<'PY'
import json
import subprocess
import sys
import time

deadline = time.monotonic() + 300
while True:
    result = subprocess.run([sys.argv[1], "status"], capture_output=True, text=True,
                            check=True, timeout=15)
    status = json.loads(result.stdout)
    if status.get("ok") is True:
        print("PASS: FSearch live name index is ready", flush=True)
        break
    error = status.get("error", "Unknown FSearch status")
    if not error.startswith("indexing:"):
        raise SystemExit(error)
    if time.monotonic() >= deadline:
        raise SystemExit("FSearch initial index timed out: " + error)
    print("Waiting for FSearch live index: " + error, flush=True)
    time.sleep(2)
PY
WINWAY_FSEARCH_PATH="$fsearch_binary" \
  WINWAY_TEST_RESOURCE_BUNDLE="$resource_bundle" "$search_test_root/search-tests"
