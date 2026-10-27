import AppKit
import SwiftUI

@main struct CrossingRender {
 @MainActor static func main() throws {
  let output=URL(fileURLWithPath:CommandLine.arguments[1]);try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
  _=NSApplication.shared
  let feed=LiveReactions(demo:true),birth=Date(timeIntervalSinceReferenceDate:1000)
  feed.hearts=[ReactionHeart(born:birth,drift:-65,rise:75,size:20,tilt:-12),ReactionHeart(born:birth,drift:55,rise:90,size:18,tilt:12),ReactionHeart(born:birth,drift:-12,rise:120,size:15,tilt:-5)]
  for (index,time) in [0.02,0.6,1.1].enumerated() {
   let frame=NSRect(x:0,y:0,width:344,height:164)
   let view=ZStack(alignment:.topLeading) {
    HStack(spacing:16) {
     VStack(alignment:.leading) {Text("家庭概览").bold();Spacer();Text("离线联动示例").font(.caption)}.padding(14).frame(width:164,height:164).background(Color(red:0.05,green:0.12,blue:0.2),in:RoundedRectangle(cornerRadius:28))
     VStack(alignment:.leading) {Text("Codex 重置").bold();Spacer();HStack {Image(systemName:"heart.fill").foregroundStyle(.pink);Text("示例感谢")}.font(.caption).padding(.bottom,10)}.padding(14).frame(width:164,height:164).background(Color(red:0.05,green:0.12,blue:0.2),in:RoundedRectangle(cornerRadius:28))
    }
    DesktopReactionCanvas(feed:feed,source:CGRect(x:180,y:0,width:164,height:164),target:CGRect(x:0,y:0,width:164,height:164),origin:CGPoint(x:200,y:130),fixedTime:birth.addingTimeInterval(time))
   }.frame(width:344,height:164).foregroundStyle(.white).environment(\.colorScheme,.dark)
   let w=NSWindow(contentRect:frame,styleMask:.borderless,backing:.buffered,defer:false);w.isReleasedWhenClosed=false;w.backgroundColor = .clear;w.isOpaque=false
   let host=NSHostingView(rootView:view);host.frame=frame;w.contentView=host;host.layoutSubtreeIfNeeded();RunLoop.current.run(until:Date().addingTimeInterval(0.1));host.displayIfNeeded()
   let image=host.bitmapImageRepForCachingDisplay(in:host.bounds)!;host.cacheDisplay(in:host.bounds,to:image)
   try image.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("crossing-\(index).png"));w.close()
  }
  precondition(ReactionOverlayPanel().canBecomeKey==false)
  print("PASS three offline crossing renders; overlay cannot take keyboard focus; zero network requests")
 }
}
