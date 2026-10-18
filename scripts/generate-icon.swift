import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

func drawIcon(size: Int, file: String) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(size) / 1024
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: scale, y: scale)
    let rect = NSRect(x: 64, y: 64, width: 896, height: 896)
    let shape = NSBezierPath(roundedRect: rect, xRadius: 205, yRadius: 205)
    NSGradient(starting: NSColor(calibratedRed: 0.12, green: 0.20, blue: 0.22, alpha: 1),
               ending: NSColor(calibratedRed: 0.055, green: 0.075, blue: 0.10, alpha: 1))!.draw(in: shape, angle: -70)
    NSColor(calibratedWhite: 1, alpha: 0.12).setStroke()
    shape.lineWidth = 3
    shape.stroke()
    let text: NSString = "文"
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 490, weight: .medium),
        .foregroundColor: NSColor(calibratedRed: 0.46, green: 0.91, blue: 0.77, alpha: 1)
    ]
    let textSize = text.size(withAttributes: attributes)
    text.draw(at: NSPoint(x: (1024 - textSize.width) / 2, y: (1024 - textSize.height) / 2 + 18), withAttributes: attributes)
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 620, y: 235))
    arrow.line(to: NSPoint(x: 810, y: 235))
    arrow.move(to: NSPoint(x: 750, y: 295))
    arrow.line(to: NSPoint(x: 810, y: 235))
    arrow.line(to: NSPoint(x: 750, y: 175))
    arrow.lineWidth = 24
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    NSColor(calibratedWhite: 1, alpha: 0.8).setStroke()
    arrow.stroke()
    NSGraphicsContext.restoreGraphicsState()
    let data = bitmap.representation(using: .png, properties: [:])!
    try data.write(to: directory.appendingPathComponent(file))
}

for points in [16, 32, 128, 256, 512] {
    try drawIcon(size: points, file: "icon_\(points)x\(points).png")
    try drawIcon(size: points * 2, file: "icon_\(points)x\(points)@2x.png")
}
