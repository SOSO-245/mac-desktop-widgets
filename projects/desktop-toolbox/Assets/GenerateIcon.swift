import AppKit
let dir=CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath:dir,withIntermediateDirectories:true)
for size in [16,32,64,128,256,512,1024] {
 let image=NSImage(size:NSSize(width:size,height:size));image.lockFocus()
 let rect=NSRect(x:0,y:0,width:size,height:size);let inset=CGFloat(size)*0.04
 let path=NSBezierPath(roundedRect:rect.insetBy(dx:inset,dy:inset),xRadius:CGFloat(size)*0.23,yRadius:CGFloat(size)*0.23)
 NSGradient(starting:NSColor(red:0.10,green:0.23,blue:0.38,alpha:1),ending:NSColor(red:0.25,green:0.12,blue:0.45,alpha:1))!.draw(in:path,angle:45)
 let base=CGFloat(size)*0.21;let gap=CGFloat(size)*0.06;let unit=CGFloat(size)*0.26
 for(row,col)in [(0,0),(0,1),(1,0),(1,1)]{
  let cell=NSRect(x:base+CGFloat(col)*(unit+gap),y:base+CGFloat(row)*(unit+gap),width:unit,height:unit)
  (row==col ? NSColor.systemMint:NSColor.systemCyan).setFill();NSBezierPath(roundedRect:cell,xRadius:unit*0.25,yRadius:unit*0.25).fill()
 }
 image.unlockFocus();let png=NSBitmapImageRep(data:image.tiffRepresentation!)!.representation(using:.png,properties:[:])!
 let names: [String]
 switch size {case 16:names=["icon_16x16.png"];case 32:names=["icon_16x16@2x.png","icon_32x32.png"];case 64:names=["icon_32x32@2x.png"];case 128:names=["icon_128x128.png"];case 256:names=["icon_128x128@2x.png","icon_256x256.png"];case 512:names=["icon_256x256@2x.png","icon_512x512.png"];default:names=["icon_512x512@2x.png"]}
 for n in names{try png.write(to:URL(fileURLWithPath:dir).appendingPathComponent(n))}
}
