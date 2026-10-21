#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
runner_root="$(mktemp -d /tmp/winway-preview-runner-XXXXXX)"
cleanup() {
  python3 - "$runner_root" <<'PY'
import pathlib
import shutil
import sys
path = pathlib.Path(sys.argv[1])
if path.name.startswith('winway-preview-runner-') and path.parent == pathlib.Path('/tmp'):
    shutil.rmtree(path)
PY
}
trap cleanup EXIT
swiftc -swift-version 6 -parse-as-library \
  "$project_root/Sources/WinwayApp/Platform/PreviewService.swift" \
  "$project_root/Tests/Standalone/PreviewRunner.swift" \
  -o "$runner_root/preview-tests"
"$runner_root/preview-tests"
