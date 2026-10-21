from pathlib import Path
import sys
import re
p=Path(__file__).resolve().parents[1] / 'WinwayCoreTests/FileSystemTests.swift'
s=p.read_text().replace('import Testing\n','').replace('@testable import WinwayCore\n','')
s=re.sub(r'@Test[^\n]*? func ', 'func ', s).replace('#expect(', 'expect(').replace('#require(', 'require(').replace('Issue.record(', 'fail(')
shim = r'''
func expect(_ condition: Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) { if !condition { fatalError("Assertion failed: \(message)", file: file, line: line) } }
func fail(_ message: String, file: StaticString = #file, line: UInt = #line) { fatalError(message, file: file, line: line) }
func require<T>(_ value: T?) throws -> T { guard let value else { throw NSError(domain:"test",code:1) }; return value }
'''
import re
names=re.findall(r'func (test\w+)\(\) async throws', s)
conditional = {
    'testRealCrossVolumeMoveIfFixtureMounted': 'WINWAY_TEST_VOLUME',
    'testReadOnlyVolumeFailurePreservesSourceIfMounted': 'WINWAY_TEST_READONLY_VOLUME',
    'testDisconnectedVolumeIsNotEmptyIfFixtureProvided': 'WINWAY_TEST_DISCONNECTED_PATH',
}
lines = []
for name in names:
    call = f'try await tests.{name}(); print("PASS {name}")'
    if name in conditional:
        call = f'if ProcessInfo.processInfo.environment["{conditional[name]}"] != nil {{ {call} }} else {{ print("SKIP {name}: no disposable volume fixture") }}'
    lines.append(call)
runner = '\n@main struct Runner { static func main() async throws { let tests = FileSystemTests()\n' + '\n'.join(lines) + '\n} }\n'
Path(sys.argv[1]).write_text(s + shim + runner)
