import AppKit

let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        NSColor.clear.setFill(); NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()
        let body = NSBezierPath(roundedRect: NSRect(x: 70, y: 70, width: 884, height: 884), xRadius: 200, yRadius: 200)
        NSGradient(starting: NSColor(srgbRed: 1, green: 0.59, blue: 0.19, alpha: 1), ending: NSColor(srgbRed: 0.91, green: 0.27, blue: 0.05, alpha: 1))!.draw(in: body, angle: -55)
        let screen = NSBezierPath(roundedRect: NSRect(x: 195, y: 290, width: 634, height: 440), xRadius: 70, yRadius: 70)
        NSColor(srgbRed: 0.12, green: 0.13, blue: 0.15, alpha: 1).setFill(); screen.fill()
        let wave = NSBezierPath()
        wave.move(to: NSPoint(x: 260, y: 500)); wave.line(to: NSPoint(x: 350, y: 500))
        wave.line(to: NSPoint(x: 405, y: 595)); wave.line(to: NSPoint(x: 480, y: 405))
        wave.line(to: NSPoint(x: 555, y: 620)); wave.line(to: NSPoint(x: 620, y: 500)); wave.line(to: NSPoint(x: 760, y: 500))
        wave.lineWidth = 35; wave.lineJoinStyle = .round; wave.lineCapStyle = .round
        NSColor(srgbRed: 1, green: 0.69, blue: 0.36, alpha: 1).setStroke(); wave.stroke()
        NSColor.white.withAlphaComponent(0.9).setFill()
        NSBezierPath(ovalIn: NSRect(x: 480, y: 180, width: 64, height: 28)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let output = URL(fileURLWithPath: destination).appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: output)
    }
}
