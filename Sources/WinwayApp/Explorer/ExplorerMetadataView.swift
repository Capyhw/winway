import SwiftUI
import WinwayCore

/// A hosted, read-only SwiftUI inspector keeps selectable metadata separate from
/// the AppKit file list's selection and keyboard responder chain.
@MainActor
struct ExplorerMetadataView: View {
    let entry: FileEntry

    private var properties: [(String, String)] {
        [("文件类型", entry.isSymbolicLink ? "符号链接 · \(entry.kind)" : entry.kind),
         ("大小", ExplorerStyle.size(entry)),
         ("修改日期", ExplorerStyle.dateFormatter.string(from: entry.modified)),
         ("路径", entry.url.path)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(properties, id: \.0) { key, value in
                HStack(alignment: .top, spacing: 0) {
                    Text(key).frame(width: 80, alignment: .leading)
                    Text(value)
                        .textSelection(.enabled)
                        .lineLimit(key == "路径" ? 5 : 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(value)
                }
                .frame(minHeight: 20, alignment: .topLeading)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 13))
        .foregroundStyle(Color(nsColor: ExplorerStyle.secondary))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}
