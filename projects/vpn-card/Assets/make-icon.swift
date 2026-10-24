import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let s = CGFloat(size) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: s)
    transform.concat()
    let rect = NSRect(x: 32, y: 32, width: 960, height: 960)
    let shape = NSBezierPath(roundedRect: rect, xRadius: 215, yRadius: 215)
    NSGradient(starting: NSColor(calibratedRed: 0.32, green: 0.27, blue: 0.72, alpha: 1),
               ending: NSColor(calibratedRed: 0.055, green: 0.10, blue: 0.23, alpha: 1))!.draw(in: shape, angle: -65)
    let arc = NSBezierPath()
    arc.appendArc(withCenter: NSPoint(x: 512, y: 480), radius: 270, startAngle: 25, endAngle: 155)
    arc.lineWidth = 66; arc.lineCapStyle = .round
    NSColor(calibratedWhite: 1, alpha: 0.92).setStroke(); arc.stroke()
    let needle = NSBezierPath()
    needle.move(to: NSPoint(x: 512, y: 480)); needle.line(to: NSPoint(x: 680, y: 675))
    needle.lineWidth = 59; needle.lineCapStyle = .round
    NSColor(calibratedRed: 0.35, green: 0.82, blue: 1, alpha: 1).setStroke(); needle.stroke()
    NSColor.white.setFill(); NSBezierPath(ovalIn: NSRect(x: 465, y: 433, width: 94, height: 94)).fill()
    let wave = NSBezierPath()
    for (i, point) in [NSPoint(x: 225, y: 300), NSPoint(x: 360, y: 300), NSPoint(x: 430, y: 360),
                       NSPoint(x: 515, y: 225), NSPoint(x: 595, y: 300), NSPoint(x: 800, y: 300)].enumerated() {
        if i == 0 { wave.move(to: point) } else { wave.line(to: point) }
    }
    wave.lineWidth = 36; wave.lineCapStyle = .round; wave.lineJoinStyle = .round
    NSColor(calibratedRed: 0.65, green: 0.59, blue: 1, alpha: 1).setStroke(); wave.stroke()
    NSGraphicsContext.restoreGraphicsState()
    let data = bitmap.representation(using: .png, properties: [:])!
    let names: [String]
    if size == 16 { names = ["icon_16x16.png"] }
    else if size == 32 { names = ["icon_16x16@2x.png", "icon_32x32.png"] }
    else if size == 64 { names = ["icon_32x32@2x.png"] }
    else if size == 1024 { names = ["icon_512x512@2x.png"] }
    else { names = ["icon_\(size)x\(size).png"] + (size > 128 ? ["icon_\(size/2)x\(size/2)@2x.png"] : []) }
    for name in names { try data.write(to: destination.appendingPathComponent(name)) }
}
