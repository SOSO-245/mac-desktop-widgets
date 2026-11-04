import AppKit

/// Only layout metadata is shared. Never includes API keys, balances, or costs.
@MainActor final class ToolboxBridge: NSObject {
    static let shared = ToolboxBridge()
    let id = "local.homeatlas.APIUsage"
    weak var panel: NSWindow?
    var changed: (() -> Void)?
    var settings: (() -> Void)?
    var timer: Timer?
    var applying = false
    var moveWork: DispatchWorkItem?
    let d = UserDefaults.standard
    func start(panel: NSWindow, changed: @escaping () -> Void, settings: @escaping () -> Void) {
        self.panel = panel; self.changed = changed; self.settings = settings
        guard timer == nil else { return }
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(receive(_:)), name: Notification.Name("local.homeatlas.toolbox.command.v1"), object: nil)
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in Task { @MainActor in self?.publish() } }
        publish()
    }
    @objc func receive(_ n: Notification) {
        guard let u = n.userInfo, u["target"] as? String == id, let action = u["action"] as? String else { return }
        switch action {
        case "settings": settings?()
        case "show", "hide": d.set(action == "show", forKey: "desktopVisible"); changed?()
        case "size":
            guard let s = u["size"] as? String, ["small", "medium", "large"].contains(s) else { return }
            d.set(s, forKey: "size"); changed?()
        case "appearance":
            if let g = u["glass"] as? Bool { d.set(g, forKey: "glass") }
            if let b = u["brightness"] as? Double, b.isFinite { d.set(min(100,max(-100,b)), forKey: "brightness") }
            if let t = u["transparency"] as? Double, t.isFinite { d.set(min(80,max(0,t)), forKey: "transparency") }
            changed?()
        case "place":
            guard let panel, let x = u["x"] as? Double, let y = u["y"] as? Double, x.isFinite, y.isFinite else { return }
            var r = panel.frame; r.origin = NSPoint(x:x,y:y)
            guard NSScreen.screens.contains(where: { $0.visibleFrame.contains(r) }) else { return }
            move(r)
        default: return
        }
        publish()
    }
    func didMove() {
        guard !applying else { return }
        moveWork?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self, let panel = self.panel else { return }
            if NSEvent.pressedMouseButtons != 0 { self.didMove(); return }
            let p = GridPreferences.read()
            if p.snap, let a = panel.screen?.visibleFrame {
                self.move(CardGrid.snapped(panel.frame,area:a,anchor:NSPoint(x:p.anchorX ?? a.minX+20,y:p.anchorTop ?? a.maxY-20)))
            } else { self.publish() }
        }
        moveWork = task; DispatchQueue.main.asyncAfter(deadline: .now()+0.2, execute: task)
    }
    func move(_ r: NSRect) {
        guard let panel else { return }
        applying = true; panel.setFrame(r, display:true); panel.saveFrame(usingName:"APIUsageDesktop")
        DispatchQueue.main.async { self.applying = false }; publish()
    }
    func publish() {
        guard let panel else { return }
        let state = CardPresence(id:id,updated:Date(),visible:panel.isVisible,size:d.string(forKey:"size") ?? "large",frame:CardPlacement(panel.frame),glass:d.bool(forKey:"glass"),brightness:d.double(forKey:"brightness"),transparency:d.double(forKey:"transparency"),smallWidth:164)
        let dir = GridPreferences.folder.appendingPathComponent("status")
        try? FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        if let data = try? JSONEncoder().encode(state) { try? data.write(to:dir.appendingPathComponent(id+".json"),options:.atomic) }
    }
    static func openToolbox() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/桌面工具箱.app")
        NSWorkspace.shared.open(url)
    }
}
