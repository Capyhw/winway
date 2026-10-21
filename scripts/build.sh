#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
macos_sdk="$(xcrun --sdk macosx --show-sdk-path)"
macos_sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
minimum_macos="$(plutil -extract LSMinimumSystemVersion raw "$project_root/Packaging/Info.plist")"
# Keep the recommended backend. This CLT's swiftbuild link step otherwise
# records the deployment target as the SDK version, enabling legacy controls.
# Pass the actual compile SDK and minimum OS separately to the linker.
exec xcrun swift build --package-path "$project_root" \
  --build-system "${WINWAY_BUILD_SYSTEM:-swiftbuild}" --sdk "$macos_sdk" \
  -Xlinker -platform_version -Xlinker macos \
  -Xlinker "$minimum_macos" -Xlinker "$macos_sdk_version" "$@"
