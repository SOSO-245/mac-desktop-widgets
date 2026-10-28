import SwiftUI
import AppKit
@main struct Tests {
 @MainActor static func main() {
  _=NSApplication.shared
  let panel=NSPanel(contentRect:NSRect(x:0,y:0,width:164,height:164),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
  let reporter=WaterFrameReporter.Reporter(frame:NSRect(x:14,y:30,width:136,height:37))
  panel.contentView=NSView(frame:NSRect(x:0,y:0,width:164,height:164));panel.contentView!.addSubview(reporter)
  reporter.updateTrackingAreas()
  precondition(panel.acceptsMouseMovedEvents)
  precondition(reporter.trackingAreas.count==1)
  let opts=reporter.trackingAreas[0].options
  precondition(opts.contains(.activeAlways) && opts.contains(.cursorUpdate) && opts.contains(.mouseMoved))
  for _ in 0..<20 {reporter.updateTrackingAreas()}
  precondition(reporter.trackingAreas.count==1)
  precondition(reporter.hitTest(NSPoint(x:20,y:40))==nil)
  reporter.removeFromSuperview()
  print("PASS native non-key pointer tracking, no duplicate tracking areas, click passthrough")
 }
}
