import Foundation
import WinwayCore
@main struct CaseReview {
 static func main() async throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent("winway-case-review-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  defer { try? FileManager.default.removeItem(at:root) }
  let source=root.appendingPathComponent("report.txt")
  try Data("review fixture".utf8).write(to:source)
  let sensitive=try root.resourceValues(forKeys:[.volumeSupportsCaseSensitiveNamesKey]).volumeSupportsCaseSensitiveNames
  print("CASE_SENSITIVE=\(String(describing:sensitive))")
  do { print("RENAMED=\(try await LocalFileService().rename(source,to:"Report.txt"))") }
  catch { print("RENAME_CASE_ONLY_ERROR=\(error.localizedDescription)") }
 }
}
