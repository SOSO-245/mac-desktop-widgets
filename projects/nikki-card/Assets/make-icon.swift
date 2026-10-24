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
    let router = NSBezierPath(roundedRect: NSRect(x:220,y:260,width:584,height:240),xRadius:72,yRadius:72)
    NSColor(calibratedWhite:1,alpha:0.95).setFill(); router.fill()
    for x in [CGFloat(310),CGFloat(400),CGFloat(490)] {
        NSColor(calibratedRed:0.21,green:0.6,blue:0.8,alpha:1).setFill()
        NSBezierPath(ovalIn:NSRect(x:x,y:352,width:35,height:35)).fill()
    }
    for (radius, start, end) in [(CGFloat(260),CGFloat(42),CGFloat(138)),(CGFloat(160),CGFloat(42),CGFloat(138))] {
        let arc=NSBezierPath(); arc.appendArc(withCenter:NSPoint(x:512,y:530),radius:radius,startAngle:start,endAngle:end)
        arc.lineWidth=52; arc.lineCapStyle = .round
        NSColor(calibratedRed:0.40,green:1,blue:0.75,alpha:1).setStroke();arc.stroke()
    }
    NSColor(calibratedRed:0.40,green:1,blue:0.75,alpha:1).setFill()
    NSBezierPath(ovalIn:NSRect(x:482,y:540,width:60,height:60)).fill()
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
