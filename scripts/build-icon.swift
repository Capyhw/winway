import AppKit
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = root.appendingPathComponent("Sources/WinwayApp/Resources/Figma/folder.svg")
guard let icon = NSImage(contentsOf: source) else { fatalError("Missing Figma folder icon") }
let directory = root.appendingPathComponent(".build/Winway.iconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for points in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels = points * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        icon.draw(in:NSRect(x:0,y:0,width:pixels,height:pixels),from:.zero,operation:.sourceOver,fraction:1)
        NSGraphicsContext.restoreGraphicsState()
        try rep.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent("icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"))
    }
}
