import AppKit
import SwiftUI
@MainActor final class AppSettingsController {static let shared=AppSettingsController();var page:String?;func show(_ p:String?){page=p}}
@MainActor final class DesktopCardAppearance {static let shared=DesktopCardAppearance();var glass=false;var effectiveGlass:Bool{glass};var brightness=0.0;var transparency=0.0}
@main struct BridgeHarness {
 @MainActor static func main(){
  let app=NSApplication.shared;app.setActivationPolicy(.prohibited)
  let area=NSScreen.main!.visibleFrame
  let panel=NSPanel(contentRect:NSRect(x:area.minX+30,y:area.minY+30,width:164,height:164),styleMask:.borderless,backing:.buffered,defer:false)
  panel.identifier=NSUserInterfaceItemIdentifier("LiveDesktopCard")
  var shown=false
  ToolboxBridge.shared.start(show:{shown=$0},size:{_ in panel.setContentSize(NSSize(width:344,height:164))})
  func send(_ action:String,_ values:[String:Any]=[:],target:String="local.homeatlas.ToolboxTest"){
   var u=values;u["target"]=target;u["action"]=action
   DistributedNotificationCenter.default().postNotificationName(ToolboxBridge.command,object:nil,userInfo:u,deliverImmediately:true)
   RunLoop.main.run(until:Date().addingTimeInterval(0.15))
  }
  send("show");precondition(shown)
  send("size",["size":"medium"]);precondition(panel.frame.width==344)
  let x=area.minX+50,y=area.minY+50
  send("place",["x":x,"y":y]);precondition(panel.frame.minX==x && panel.frame.minY==y)
  send("appearance",["glass":true,"brightness":-52.0,"transparency":45.0]);precondition(DesktopCardAppearance.shared.glass && DesktopCardAppearance.shared.brightness == -52 && DesktopCardAppearance.shared.transparency==45)
  send("place",["x":-99999.0,"y":-99999.0]);precondition(panel.frame.minX==x && panel.frame.minY==y)
  send("hide",target:"another.app");precondition(shown)
  send("settings",["page":"desktop"]);precondition(AppSettingsController.shared.page=="desktop")
  send("hide");precondition(!shown)
  precondition(!panel.isVisible)
  let file=GridPreferences.folder.appendingPathComponent("status/local.homeatlas.ToolboxTest.json")
  let s=try! JSONDecoder().decode(CardPresence.self,from:Data(contentsOf:file));precondition(s.frame.rect==panel.frame && s.transparency==45)
  print("BridgeHarness: show, size, placement, appearance, bounds, target isolation, settings and status passed; no visible windows or real app state touched")
 }
}
