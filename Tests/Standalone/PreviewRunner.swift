import Foundation
import CoreGraphics
import ImageIO

@main
struct PreviewRunner {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure(description: message) }
    }

    static func requireUnavailable(_ payload: PreviewPayload, containing message: String) throws {
        guard case .unavailable(let explanation) = payload else {
            throw Failure(description: "Expected unavailable: \(message)")
        }
        try require(explanation.contains(message), "Unexpected explanation: \(explanation)")
    }

    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("winway-preview-fixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let chinese = "中文文件预览\nHello Winway 👋\n"
        let textURL = root.appendingPathComponent("中文.txt")
        try Data(chinese.utf8).write(to: textURL)
        guard case .text(let decoded) = await PreviewService.load(textURL) else {
            throw Failure(description: "Chinese UTF-8 text did not produce text")
        }
        try require(decoded == chinese, "Chinese UTF-8 contents changed")
        print("PASS Chinese UTF-8 text")

        let limit = root.appendingPathComponent("limit.txt")
        try Data(repeating: 65, count: 1_048_576).write(to: limit)
        guard case .text(let boundary) = await PreviewService.load(limit) else {
            throw Failure(description: "Exactly 1 MiB text should remain previewable")
        }
        try require(boundary.utf8.count == 1_048_576, "Boundary text was truncated")
        print("PASS exactly 1 MiB text")

        let oversized = root.appendingPathComponent("oversized.txt")
        try Data(repeating: 65, count: 1_048_577).write(to: oversized)
        try requireUnavailable(await PreviewService.load(oversized), containing: "超过 1 MiB")
        print("PASS text over 1 MiB is rejected")

        let invalid = root.appendingPathComponent("invalid.txt")
        try Data([0xff, 0xfe, 0x80]).write(to: invalid)
        try requireUnavailable(await PreviewService.load(invalid), containing: "UTF-8")
        let nul = root.appendingPathComponent("nul.txt")
        try Data([65, 0, 66]).write(to: nul)
        try requireUnavailable(await PreviewService.load(nul), containing: "UTF-8")
        print("PASS invalid UTF-8 and binary NUL are rejected")

        let docx = root.appendingPathComponent("document.docx")
        try Data("This must never be shown as a simulated document".utf8).write(to: docx)
        try requireUnavailable(await PreviewService.load(docx), containing: "此格式暂不支持")
        print("PASS DOCX format fallback")

        let png = root.appendingPathComponent("wide.png")
        try createPNG(png)
        guard case .image(let thumbnail) = await PreviewService.load(png),
              let source = CGImageSourceCreateWithData(thumbnail as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw Failure(description: "PNG preview did not return a decodable image")
        }
        try require(image.width == 800 && image.height == 400, "Unexpected thumbnail size \(image.width)x\(image.height)")
        try require(!thumbnail.isEmpty, "PNG thumbnail is empty")
        print("PASS PNG thumbnail preserves aspect ratio at 800x400")

        let corruptPNG = root.appendingPathComponent("corrupt.png")
        try Data("not an image".utf8).write(to: corruptPNG)
        try requireUnavailable(await PreviewService.load(corruptPNG), containing: "预览限制")
        print("PASS corrupt PNG returns unavailable")

        let html = root.appendingPathComponent("read-only.html")
        let markup = "<script>window.example = 'never execute';</script>"
        try Data(markup.utf8).write(to: html)
        guard case .text(let rawMarkup) = await PreviewService.load(html) else {
            throw Failure(description: "HTML should only return plain text")
        }
        try require(rawMarkup == markup, "HTML text was transformed")
        print("PASS HTML is returned as plain text data")

        try requireUnavailable(await PreviewService.load(root.appendingPathComponent("missing.txt")), containing: "无法预览")
        print("PASS missing file returns an error explanation")
        print("Preview verification: 9 checks passed")
    }

    private static func createPNG(_ url: URL) throws {
        guard let context = CGContext(data: nil, width: 1600, height: 800, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw Failure(description: "Cannot create PNG fixture context")
        }
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1600, height: 800))
        guard let image = context.makeImage(),
              let output = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw Failure(description: "Cannot encode PNG fixture")
        }
        CGImageDestinationAddImage(output, image, nil)
        try require(CGImageDestinationFinalize(output), "PNG fixture encoding failed")
    }
}
