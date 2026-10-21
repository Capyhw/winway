#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
recorder_test_root="$(mktemp -d "${TMPDIR:-/tmp}/winway-key-recorder.XXXXXX")"
trap 'rm -rf "$recorder_test_root"' EXIT
xcrun swiftc -swift-version 6 -emit-library -emit-module -module-name WinwayCore \
  "$project_root/Sources/WinwayCore/Commands/KeyboardCommands.swift" \
  "$project_root/Sources/WinwayCore/Settings/KeyboardSettings.swift" \
  -emit-module-path "$recorder_test_root/WinwayCore.swiftmodule" -o "$recorder_test_root/libWinwayCore.dylib"
xcrun swiftc -swift-version 6 -parse-as-library -I "$recorder_test_root" -L "$recorder_test_root" -lWinwayCore \
  -Xlinker -rpath -Xlinker "$recorder_test_root" \
  "$project_root/Sources/WinwayApp/Settings/KeyboardEventAdapter.swift" \
  "$project_root/Sources/WinwayApp/Settings/RecorderView.swift" \
  "$project_root/Tests/Standalone/KeyRecorderRunner.swift" -o "$recorder_test_root/key-recorder-tests"
"$recorder_test_root/key-recorder-tests"
