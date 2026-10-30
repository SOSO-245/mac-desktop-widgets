import AppKit
let dir = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for size in [16,32,64,128,256,512,1024] {
    let s = CGFloat(size); let image = NSImage(size: NSSize(width: s, height: s)); image.lockFocus()
    let bg = NSBezierPath(roundedRect: NSRect(x: s*0.04,y: s*0.04,width:s*0.92,height:s*0.92), xRadius:s*0.22,yRadius:s*0.22)
    NSGradient(starting: NSColor(red:0.06,green:0.21,blue:0.32,alpha:1), ending:NSColor(red:0.20,green:0.10,blue:0.38,alpha:1))!.draw(in:bg,angle:30)
    for (i,h) in [0.25,0.43,0.60].enumerated() {
        let r = NSRect(x:s*(0.23+Double(i)*0.19),y:s*0.22,width:s*0.12,height:s*h)
        NSGradient(starting:.systemCyan,ending:NSColor(red:0.4,green:1,blue:0.78,alpha:1))!.draw(in:NSBezierPath(roundedRect:r,xRadius:s*0.04,yRadius:s*0.04),angle:90)
    }
    image.unlockFocus()
    let data = NSBitmapImageRep(data:image.tiffRepresentation!)!.representation(using:.png,properties:[:])!
    let names:[String]
    switch size { case 16:names=["icon_16x16.png"];case 32:names=["icon_16x16@2x.png","icon_32x32.png"];case 64:names=["icon_32x32@2x.png"];case 128:names=["icon_128x128.png"];case 256:names=["icon_128x128@2x.png","icon_256x256.png"];case 512:names=["icon_256x256@2x.png","icon_512x512.png"];default:names=["icon_512x512@2x.png"] }
    for n in names { try data.write(to:URL(fileURLWithPath:dir).appendingPathComponent(n)) }
}
