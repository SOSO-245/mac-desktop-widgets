import AppKit
let output = URL(fileURLWithPath:CommandLine.arguments[1])
try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
for (name,mark) in [("Google","G"),("GitHub","GH"),("YouTube","YT"),("ChatGPT","GPT"),("Claude","CL"),("bilibili","B")] {
    let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:96,pixelsHigh:96,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
    NSColor(srgbRed:0.17,green:0.2,blue:0.35,alpha:1).setFill()
    NSBezierPath(roundedRect:NSRect(x:0,y:0,width:96,height:96),xRadius:24,yRadius:24).fill()
    let text=NSAttributedString(string:mark,attributes:[.font:NSFont.systemFont(ofSize:mark.count>2 ? 28:36,weight:.bold),.foregroundColor:NSColor(srgbRed:0.5,green:1,blue:0.8,alpha:1)])
    text.draw(at:NSPoint(x:(96-text.size().width)/2,y:(96-text.size().height)/2))
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name+".png"))
}
