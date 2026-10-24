import AppKit
let output=URL(fileURLWithPath:CommandLine.arguments.last!)
let iconset=output.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at:iconset,withIntermediateDirectories:true)
func draw(_ pixels:Int)->Data {
    let b=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:b)
    let t=NSAffineTransform();t.scale(by:CGFloat(pixels)/1024);t.concat()
    let rect=NSRect(x:65,y:65,width:894,height:894),shape=NSBezierPath(roundedRect:rect,xRadius:198,yRadius:198)
    NSGradient(colors:[NSColor(srgbRed:0.03,green:0.12,blue:0.17,alpha:1),NSColor(srgbRed:0.14,green:0.33,blue:0.34,alpha:1)])!.draw(in:shape,angle:55)
    let page=NSBezierPath(roundedRect:NSRect(x:223,y:220,width:578,height:620),xRadius:70,yRadius:70)
    NSColor(srgbRed:0.91,green:0.98,blue:0.95,alpha:1).setFill();page.fill()
    NSGraphicsContext.saveGraphicsState();page.addClip()
    NSColor(srgbRed:0.99,green:0.43,blue:0.49,alpha:1).setFill();NSRect(x:223,y:675,width:578,height:170).fill();NSGraphicsContext.restoreGraphicsState()
    for x in [360,664] {let hook=NSBezierPath(roundedRect:NSRect(x:x-16,y:765,width:32,height:95),xRadius:16,yRadius:16);NSColor(srgbRed:0.7,green:0.95,blue:0.85,alpha:1).setFill();hook.fill()}
    let text=NSAttributedString(string:"历",attributes:[.font:NSFont.systemFont(ofSize:310,weight:.medium),.foregroundColor:NSColor(srgbRed:0.08,green:0.24,blue:0.26,alpha:1)])
    text.draw(at:NSPoint(x:512-text.size().width/2,y:265))
    NSColor(srgbRed:0.5,green:1,blue:0.77,alpha:1).setFill();NSBezierPath(ovalIn:NSRect(x:732,y:110,width:170,height:170)).fill()
    NSColor(srgbRed:0.1,green:0.3,blue:0.32,alpha:1).setFill();NSBezierPath(ovalIn:NSRect(x:775,y:149,width:125,height:125)).fill()
    NSGraphicsContext.restoreGraphicsState();return b.representation(using:.png,properties:[:])!
}
for point in [16,32,128,256,512] {for scale in [1,2] {try draw(point*scale).write(to:iconset.appendingPathComponent("icon_\(point)x\(point)\(scale==2 ? "@2x" : "").png"))}}
try draw(1024).write(to:output.appendingPathComponent("AppIcon.png"))
