import Foundation
import ImageIO

enum PreviewPayload: Sendable { case text(String), image(Data), unavailable(String) }

enum PreviewService {
    static let queue = DispatchQueue(label: "app.winway.preview", qos: .userInitiated)
    static func load(_ url: URL) async -> PreviewPayload {
        await withCheckedContinuation { continuation in
            queue.async {
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                    let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
                    let ext = url.pathExtension.lowercased()
                    if ["png", "jpg", "jpeg"].contains(ext) {
                        guard size <= 32 * 1024 * 1024,
                              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                              let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                              let width = metadata[kCGImagePropertyPixelWidth] as? Int,
                              let height = metadata[kCGImagePropertyPixelHeight] as? Int,
                              Double(width) * Double(height) <= 80_000_000 else {
                            continuation.resume(returning: .unavailable("图片超出预览限制，请使用默认应用打开。")); return
                        }
                        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 800, kCGImageSourceCreateThumbnailWithTransform: true]
                        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
                        let data = NSMutableData()
                        guard let output = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { throw CocoaError(.fileReadCorruptFile) }
                        CGImageDestinationAddImage(output, thumbnail, nil)
                        guard CGImageDestinationFinalize(output) else { throw CocoaError(.fileReadCorruptFile) }
                        continuation.resume(returning: .image(data as Data))
                    } else {
                        let supported = ["txt", "md", "csv", "json", "yaml", "yml", "xml", "log", "swift", "js", "ts", "css", "html", "sh", ""]
                        guard supported.contains(ext) else { continuation.resume(returning: .unavailable("此格式暂不支持内嵌预览，请使用默认应用打开。")); return }
                        guard size <= 1_048_576 else { continuation.resume(returning: .unavailable("文本超过 1 MiB，请使用默认应用打开。")); return }
                        let file = try FileHandle(forReadingFrom: url)
                        defer { try? file.close() }
                        let data = try file.read(upToCount: 1_048_577) ?? Data()
                        guard data.count <= 1_048_576, !data.contains(0), let text = String(data: data, encoding: .utf8) else {
                            continuation.resume(returning: .unavailable("文件不是可预览的 UTF-8 文本。")); return
                        }
                        continuation.resume(returning: .text(text))
                    }
                } catch { continuation.resume(returning: .unavailable("无法预览：\(error.localizedDescription)")) }
            }
        }
    }
}
