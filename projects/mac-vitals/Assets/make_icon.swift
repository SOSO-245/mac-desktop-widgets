import AppKit
let out=CommandLine.arguments[1]
let image=NSImage(size:NSSize(width:1024,height:1024),flipped:false){_ in
 let rect=NSRect(x:38,y:38,width:948,height:948);let shape=NSBezierPath(roundedRect:rect,xRadius:215,yRadius:215)
 NSGradient(colors:[NSColor(srgbRed:0.18,green:0.20,blue:0.40,alpha:1),NSColor(srgbRed:0.07,green:0.08,blue:0.18,alpha:1)])!.draw(in:shape,angle:-65)
 NSColor.white.withAlphaComponent(0.25).setStroke();shape.lineWidth=9;shape.stroke()
 let screen=NSBezierPath(roundedRect:NSRect(x:188,y:300,width:648,height:445),xRadius:56,yRadius:56);NSColor.white.withAlphaComponent(0.85).setStroke();screen.lineWidth=35;screen.stroke()
 let stand=NSBezierPath();stand.move(to:NSPoint(x:512,y:290));stand.line(to:NSPoint(x:512,y:205));stand.move(to:NSPoint(x:375,y:205));stand.line(to:NSPoint(x:649,y:205));stand.lineWidth=34;stand.lineCapStyle = .round;stand.stroke()
 NSColor(srgbRed:0.4,green:1,blue:0.7,alpha:1).setStroke();let wave=NSBezierPath();wave.move(to:NSPoint(x:262,y:500));for p in [NSPoint(x:362,y:500),NSPoint(x:420,y:608),NSPoint(x:492,y:414),NSPoint(x:566,y:564),NSPoint(x:620,y:500),NSPoint(x:758,y:500)]{wave.line(to:p)};wave.lineWidth=34;wave.lineCapStyle = .round;wave.lineJoinStyle = .round;wave.stroke();return true
}
let dir=URL(fileURLWithPath:out);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
for n in [16,32,128,256,512]{for scale in [1,2]{let px=n*scale;let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:px,pixelsHigh:px,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!;NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap);image.draw(in:NSRect(x:0,y:0,width:px,height:px));NSGraphicsContext.restoreGraphicsState();try bitmap.representation(using:.png,properties:[:])!.write(to:dir.appendingPathComponent("icon_\(n)x\(n)\(scale==2 ? "@2x":"").png"))}}
