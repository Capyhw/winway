#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
swift_binary="$(xcrun --find swift)"
toolchain_root="$(cd "$(dirname "$swift_binary")/.." && pwd)"
testing_plugins="$toolchain_root/lib/swift/host/plugins/testing"
arguments=(--package-path "$project_root" --disable-xctest)
if [[ -d "$testing_plugins" ]]; then
  arguments+=(-Xswiftc -plugin-path -Xswiftc "$testing_plugins")
fi
exec "$swift_binary" test "${arguments[@]}" "$@"
