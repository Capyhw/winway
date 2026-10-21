#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"

if [[ "$#" -gt 1 ]]; then
  printf 'Usage: %s [vMAJOR.MINOR.PATCH[-prerelease]]\n' "$0" >&2
  exit 64
fi
version="${1:-$(plutil -extract CFBundleShortVersionString raw Packaging/Info.plist)}"
version="${version#v}"
if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$ ]]; then
  printf 'Invalid release version: %s\n' "$version" >&2
  exit 64
fi
architecture="$(uname -m)"
case "$architecture" in
  arm64|x86_64) ;;
  *) printf 'Unsupported architecture: %s\n' "$architecture" >&2; exit 64 ;;
esac

export WINWAY_VERSION="${version%%-*}"
export WINWAY_BUILD_NUMBER="${WINWAY_BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-1}}"
./scripts/build-app.sh release
application="$project_root/dist/Winway.app"
binary_architecture="$(lipo -archs "$application/Contents/MacOS/Winway")"
if [[ "$binary_architecture" != "$architecture" ]]; then
  printf 'Expected %s binary, found %s\n' "$architecture" "$binary_architecture" >&2
  exit 1
fi
./scripts/test-bundle.sh "$application"

package_name="Winway-${version}-macos-${architecture}"
output="$project_root/dist/release"
mkdir -p "$output"
package_root="$(mktemp -d "${TMPDIR:-/tmp}/winway-package.XXXXXX")"
trap 'rm -rf "$package_root"' EXIT

# Package a copy to keep signatures, executable permissions and resource forks.
ditto "$application" "$package_root/Winway.app"
ditto -c -k --sequesterRsrc --keepParent "$package_root/Winway.app" "$output/$package_name.zip"
mkdir "$package_root/unpacked"
ditto -x -k "$output/$package_name.zip" "$package_root/unpacked"
codesign --verify --deep --strict "$package_root/unpacked/Winway.app"
./scripts/test-bundle.sh "$package_root/unpacked/Winway.app"

mkdir "$package_root/dmg"
ditto "$application" "$package_root/dmg/Winway.app"
ln -s /Applications "$package_root/dmg/Applications"
hdiutil create -volname "Winway $version" -srcfolder "$package_root/dmg" \
  -format UDZO -ov "$output/$package_name.dmg"
hdiutil verify "$output/$package_name.dmg"
(
  cd "$output"
  shasum -a 256 "$package_name.zip" "$package_name.dmg" > "$package_name.sha256"
  shasum -a 256 -c "$package_name.sha256"
)
printf 'Release packages: %s/%s.{zip,dmg,sha256}\n' "$output" "$package_name"
