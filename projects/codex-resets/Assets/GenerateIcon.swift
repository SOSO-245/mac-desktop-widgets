import AppKit

// Original, code-drawn reset glyph. It is not an OpenAI brand mark.
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".", isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
let iconset = outputDirectory.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func point(center: NSPoint, radius: CGFloat, degrees: CGFloat) -> NSPoint {
    let radians = degrees * .pi / 180
    return NSPoint(x: center.x + radius * cos(radians), y: center.y + radius * sin(radians))
}

func drawIcon(pixels: Int) throws -> Data {
    let side = CGFloat(pixels)
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Unable to create icon canvas") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let transform = NSAffineTransform()
    transform.scale(by: side / 1024)
    transform.concat()
    let bounds = NSRect(x: 64, y: 64, width: 896, height: 896)
    let shape = NSBezierPath(roundedRect: bounds, xRadius: 202, yRadius: 202)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowBlurRadius = 22
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor(calibratedRed: 0.045, green: 0.080, blue: 0.13, alpha: 1).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.06, green: 0.11, blue: 0.17, alpha: 1),
        NSColor(calibratedRed: 0.075, green: 0.22, blue: 0.27, alpha: 1),
        NSColor(calibratedRed: 0.12, green: 0.36, blue: 0.40, alpha: 1)
    ])!
    gradient.draw(in: bounds, angle: 52)
    let glow = NSGradient(starting: NSColor(calibratedRed: 0.28, green: 0.95, blue: 0.74, alpha: 0.3), ending: .clear)!
    glow.draw(fromCenter: NSPoint(x: 190, y: 890), radius: 0, toCenter: NSPoint(x: 250, y: 830), radius: 850, options: [.drawsAfterEndingLocation])
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.16).setStroke()
    shape.lineWidth = 2
    shape.stroke()

    let center = NSPoint(x: 512, y: 512)
    let radius: CGFloat = 227
    let start: CGFloat = 37
    let end: CGFloat = 313
    let arrow = NSBezierPath()
    arrow.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
    arrow.lineWidth = 66
    arrow.lineCapStyle = .round
    NSColor(calibratedRed: 0.83, green: 1.0, blue: 0.94, alpha: 1).setStroke()
    arrow.stroke()

    let tip = point(center: center, radius: radius, degrees: end)
    let tangent = (end + 90) * .pi / 180
    let tipForward = NSPoint(x: tip.x + cos(tangent) * 40, y: tip.y + sin(tangent) * 40)
    let wing1 = NSPoint(x: tipForward.x - cos(tangent) * 115 + cos(tangent + .pi / 2) * 81,
                        y: tipForward.y - sin(tangent) * 115 + sin(tangent + .pi / 2) * 81)
    let wing2 = NSPoint(x: tipForward.x - cos(tangent) * 115 - cos(tangent + .pi / 2) * 81,
                        y: tipForward.y - sin(tangent) * 115 - sin(tangent + .pi / 2) * 81)
    let head = NSBezierPath()
    head.move(to: wing1)
    head.line(to: tipForward)
    head.line(to: wing2)
    head.lineWidth = 54
    head.lineJoinStyle = .round
    head.lineCapStyle = .round
    head.stroke()

    // A quiet clock hand links the reset symbol with the widget's time-focused purpose.
    let clock = NSBezierPath()
    clock.move(to: NSPoint(x: 512, y: 623))
    clock.line(to: center)
    clock.line(to: NSPoint(x: 594, y: 471))
    clock.lineWidth = 38
    clock.lineCapStyle = .round
    clock.lineJoinStyle = .round
    NSColor(calibratedRed: 0.47, green: 0.87, blue: 0.80, alpha: 1).setStroke()
    clock.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let suffix = scale == 2 ? "@2x" : ""
        let output = iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
        try drawIcon(pixels: pixels).write(to: output, options: .atomic)
    }
}
try drawIcon(pixels: 1024).write(to: outputDirectory.appendingPathComponent("AppIcon.png"), options: .atomic)
print(iconset.path)
