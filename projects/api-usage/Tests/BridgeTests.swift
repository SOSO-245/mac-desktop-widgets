import AppKit
@main struct BridgeTests {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let d = UserDefaults.standard
        d.set("large",forKey:"size"); d.set(true,forKey:"desktopVisible")
        let panel = NSPanel(contentRect:NSRect(x:20,y:50,width:344,height:344),styleMask:.borderless,backing:.buffered,defer:false)
        let bridge = ToolboxBridge(); var settingOpened = false
        bridge.start(panel:panel,changed: {
            let s = d.string(forKey:"size")!
            panel.setContentSize(NSSize(width:s == "small" ? 164:344,height:s == "large" ? 344:164))
            if d.bool(forKey:"desktopVisible") { panel.orderFront(nil) } else { panel.orderOut(nil) }
        },settings:{ settingOpened = true })
        func command(_ action:String,_ args:[String:Any]=[:],target:String="local.homeatlas.APIUsage") {
            var userInfo=args;userInfo["target"]=target;userInfo["action"]=action
            bridge.receive(Notification(name:Notification.Name("test"),userInfo:userInfo))
        }
        command("size",["size":"small"]); precondition(panel.frame.size == NSSize(width:164,height:164))
        command("size",["size":"large"],target:"other.app"); precondition(panel.frame.width == 164)
        command("size",["size":"invalid"]); precondition(panel.frame.width == 164)
        command("hide");precondition(!panel.isVisible)
        command("show");precondition(panel.isVisible)
        command("appearance",["glass":false,"brightness":200.0,"transparency":90.0]);precondition(!d.bool(forKey:"glass") && d.double(forKey:"brightness")==100 && d.double(forKey:"transparency")==80)
        let old=panel.frame;command("place",["x":Double.nan,"y":0.0]);precondition(panel.frame==old)
        command("place",["x":-999999.0,"y":-999999.0]);precondition(panel.frame==old)
        command("settings");precondition(settingOpened)
        let data=try Data(contentsOf:GridPreferences.folder.appendingPathComponent("status/local.homeatlas.APIUsage.json"))
        let state=try JSONDecoder().decode(CardPresence.self,from:data)
        precondition(state.smallWidth==164 && state.size=="small" && state.visible)
        let raw=String(data:data,encoding:.utf8)!;precondition(!raw.contains("cost") && !raw.contains("key") && !raw.contains("balance"))
        print("PASS: 11 isolated toolbox checks")
    }
}
