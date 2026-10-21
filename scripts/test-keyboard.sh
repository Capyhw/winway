#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
test_directory="$(mktemp -d "${TMPDIR:-/tmp}/winway-keyboard.XXXXXX")"
trap 'rm -rf "$test_directory"' EXIT

# Standalone fallback for environments without a usable Swift Testing runtime.
# #expect becomes a Swift precondition; failures terminate with a non-zero status.
python3 - "$project_root" "$test_directory" <<'PY'
from pathlib import Path
import re
import sys
project, temporary = map(Path, sys.argv[1:])
source = (project / 'Tests/WinwayCoreTests/KeyboardTests.swift').read_text()
cases = re.findall(r'@Test func (\w+)\(\)( throws)? \{', source)
if not cases:
    raise SystemExit('No keyboard tests discovered')
source = source.replace('import Testing\n', '').replace('@testable import WinwayCore\n', '')
source = source.replace('@Test ', '').replace('#expect(', 'precondition(')
source += '\n@main struct KeyboardTestRunner { @MainActor static func main() throws {\nlet tests = KeyboardTests()\n'
for name, throwing in cases:
    source += ('try ' if throwing else '') + f'tests.{name}()\nprint("PASS {name}")\n'
source += f'print("Keyboard: {len(cases)} tests passed")\n}}}}\n'
(temporary / 'KeyboardRunner.swift').write_text(source)
PY
swiftc -swift-version 6 -parse-as-library \
  "$project_root/Sources/WinwayCore/Commands/KeyboardCommands.swift" \
  "$project_root/Sources/WinwayCore/Settings/KeyboardSettings.swift" \
  "$test_directory/KeyboardRunner.swift" -o "$test_directory/keyboard-tests"
"$test_directory/keyboard-tests"
