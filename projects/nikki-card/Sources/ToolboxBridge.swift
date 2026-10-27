import AppKit
import SwiftUI

/// Each process controls only its own desktop window. No accessibility, credentials or network access.
@MainActor final class ToolboxBridge:NSObject {
    static let shared=ToolboxBridge()
    static let command=Notification.Name("local.homeatlas.toolbox.command.v1")
    private var showAction:((Bool)->Void)?;private var sizeAction:((String)->Void)?
    private var timer:Timer?;private var moveWork:DispatchWorkItem?;private var applying=false
    private var tokens:[NSObjectProtocol]=[]
    private var id:String{Bundle.main.bundleIdentifier ?? ""}
    var panel:NSWindow? {NSApp.windows.first {w in
        ["LiveDesktopCard","FlClashLiveCard","NikkiLiveCard"].contains(w.identifier?.rawValue ?? "") || (id=="local.homeatlas.MacVitals" && w.title=="Mac 实时监测" && w is NSPanel)
    }}
    var size:String{UserDefaults.standard.string(forKey:id=="local.homeatlas.FlClashMonitor" || id=="local.homeatlas.NikkiMonitor" || id=="local.homeatlas.MacVitals" ? "cardSize":"desktopCard.size") ?? "medium"}
    func start(show:@escaping(Bool)->Void,size:@escaping(String)->Void) {
        showAction=show;sizeAction=size;guard timer==nil else{return}
        DistributedNotificationCenter.default().addObserver(self,selector:#selector(receive(_:)),name:Self.command,object:nil)
        tokens.append(NotificationCenter.default.addObserver(forName:NSWindow.didMoveNotification,object:nil,queue:.main) {[weak self] n in
            Task{@MainActor in guard let self,let w=n.object as? NSWindow,w===self.panel,!self.applying else{return};self.scheduleSnap()}
        })
        timer=Timer.scheduledTimer(withTimeInterval:2,repeats:true){[weak self] _ in Task{@MainActor in self?.publish()}}
        DispatchQueue.main.async{self.publish()}
    }
    private func scheduleSnap(){moveWork?.cancel();let job=DispatchWorkItem{[weak self] in
        guard let self else{return};if NSEvent.pressedMouseButtons != 0 {self.scheduleSnap();return}
        let prefs=GridPreferences.read();guard prefs.snap,let p=self.panel,let a=p.screen?.visibleFrame else{self.publish();return}
        self.move(CardGrid.snapped(p.frame,area:a,anchor:NSPoint(x:prefs.anchorX ?? a.minX+20,y:prefs.anchorTop ?? a.maxY-20)))
    };moveWork=job;DispatchQueue.main.asyncAfter(deadline:.now()+0.2,execute:job)}
    @objc private func receive(_ n:Notification) {
        guard let u=n.userInfo,let target=u["target"] as? String,target==id,let action=u["action"] as? String else{return}
        switch action {
        case "settings":AppSettingsController.shared.show(u["page"] as? String)
        case "show":showAction?(true)
        case "hide":showAction?(false)
        case "size":if let s=u["size"] as? String,["small","medium","large"].contains(s){sizeAction?(s)}
        case "place":
            guard let p=panel,let x=u["x"] as? Double,let y=u["y"] as? Double,x.isFinite,y.isFinite,abs(x)<100000,abs(y)<100000 else{return}
            var r=p.frame;r.origin=NSPoint(x:x,y:y)
            if let screen=NSScreen.screens.first(where:{$0.visibleFrame.contains(r)}) {r.origin.x=max(screen.visibleFrame.minX,r.minX);move(r)}
        case "appearance":
            if let v=u["transparency"] as? Double,v.isFinite{DesktopCardAppearance.shared.transparency=min(80,max(0,v))}
            if let glass=u["glass"] as? Bool{DesktopCardAppearance.shared.glass=glass}
            if let b=u["brightness"] as? Double,b.isFinite{DesktopCardAppearance.shared.brightness=min(100,max(-100,b))}
        default:break
        }
        publish()
    }
    private func move(_ frame:NSRect){guard let p=panel else{return};moveWork?.cancel();applying=true;p.setFrame(frame,display:true)
        let key=id=="local.homeatlas.FlClashMonitor" ? "FlClashLiveCardFrame":id=="local.homeatlas.NikkiMonitor" ? "NikkiLiveCardFrame":id=="local.homeatlas.MacVitals" ? "VitalsFrame":"LiveDesktopCard.Frame"
        p.saveFrame(usingName:key);DispatchQueue.main.async{self.applying=false};publish()
    }
    func publish(){guard let p=panel,ToolModule.all.contains(where:{$0.id==id}) else{return}
        let s=CardPresence(id:id,updated:Date(),visible:p.isVisible,size:size,frame:CardPlacement(p.frame),glass:DesktopCardAppearance.shared.effectiveGlass,brightness:DesktopCardAppearance.shared.brightness,transparency:DesktopCardAppearance.shared.transparency)
        let folder=GridPreferences.folder.appendingPathComponent("status");try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        if let data=try? JSONEncoder().encode(s){try? data.write(to:folder.appendingPathComponent(id+".json"),options:.atomic)}
    }
    static func openToolbox(){let app=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/桌面工具箱.app");NSWorkspace.shared.open(app)}
}

struct ToolboxSettingsLink:View {
    var body:some View {
        VStack(alignment:.leading,spacing:18){
            Text("桌面排列").font(.title2.bold())
            Text("在桌面工具箱中选择卡片、尺寸、顺序和屏幕。先查看模拟桌面，确认后再移动真实卡片。")
            Button("打开桌面工具箱…"){ToolboxBridge.openToolbox()}.buttonStyle(.borderedProminent)
            Text("支持混合尺寸、统一间距和恢复上次位置。系统小组件的位置由 macOS 管理。").foregroundStyle(.secondary)
        }.padding(4)
    }
}
