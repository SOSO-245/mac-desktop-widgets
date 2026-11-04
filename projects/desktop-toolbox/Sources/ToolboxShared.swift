import AppKit

struct ToolModule:Identifiable,Codable {
    let id:String;let name:String;let appName:String;let symbol:String
    static let all:[Self]=[
        .init(id:"local.homeatlas.LunarCalendar",name:"万年历",appName:"万年历",symbol:"calendar"),
        .init(id:"local.homeatlas.HomeEnergy",name:"家庭概览",appName:"家庭概览",symbol:"house.fill"),
        .init(id:"local.homeatlas.CodexResets",name:"重置监测",appName:"Codex 重置",symbol:"arrow.triangle.2.circlepath"),
        .init(id:"local.homeatlas.NikkiMonitor",name:"Nikki",appName:"Nikki 实时卡片",symbol:"wifi.router.fill"),
        .init(id:"local.homeatlas.FlClashMonitor",name:"VPN 监测",appName:"FlClash 实时卡片",symbol:"network"),
        .init(id:"local.homeatlas.MacVitals",name:"Mac 监测",appName:"Mac 实时监测",symbol:"desktopcomputer"),
        .init(id:"local.homeatlas.APIUsage",name:"API 用量",appName:"API用量卡片",symbol:"chart.bar.xaxis")]
}
struct CardPlacement:Codable,Equatable {var x:Double;var y:Double;var width:Double;var height:Double
    init(_ r:NSRect){x=r.minX;y=r.minY;width=r.width;height=r.height}
    var rect:NSRect{NSRect(x:x,y:y,width:width,height:height)}
    var valid:Bool{[x,y,width,height].allSatisfy{$0.isFinite} && width>=100 && width<=1000 && height>=100 && height<=1000 && abs(x)<100000 && abs(y)<100000}
}
struct CardPresence:Codable {let id:String;let updated:Date;let visible:Bool;let size:String;let frame:CardPlacement;var glass:Bool?=nil;var brightness:Double?=nil;var transparency:Double?=nil;var smallWidth:Double?=nil}
struct GridPreferences:Codable {
    var snap=false;var automatic=false;var anchorX:Double?;var anchorTop:Double?;var screenID:UInt32?
    static let folder=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/HomeAtlasToolbox")
    static func read()->Self {(try? JSONDecoder().decode(Self.self,from:Data(contentsOf:folder.appendingPathComponent("grid.json")))) ?? Self()}
    func save(){try? FileManager.default.createDirectory(at:Self.folder,withIntermediateDirectories:true);if let d=try? JSONEncoder().encode(self){try? d.write(to:Self.folder.appendingPathComponent("grid.json"),options:.atomic)}}
}
/// Pack the actual card sizes, preserving order. Two 164 pt cards share a 344 pt lane.
enum CardGrid {
    static func pack(_ sizes:[String:NSSize],order:[String],area:NSRect,anchor:NSPoint,gap:CGFloat=16,obstacles:[NSRect]=[])->[String:NSRect] {
        let ids=order.filter{sizes[$0] != nil};guard !ids.isEmpty else{return [:]}
        let lane=max(344,ids.compactMap{sizes[$0]?.width}.max() ?? 344)
        var x=max(area.minX,min(anchor.x,area.maxX-lane));let firstX=x
        var columns=[firstX];var cx=firstX+lane+gap
        while cx+lane<=area.maxX {columns.append(cx);cx+=lane+gap}
        cx=firstX-lane-gap
        while cx>=area.minX {columns.append(cx);cx-=lane+gap}
        var columnIndex=0
        let top=max(area.minY,min(anchor.y,area.maxY));var y=top;var used:CGFloat=0;var rowHeight:CGFloat=0
        var result:[String:NSRect]=[:]
        for id in ids {
            guard let size=sizes[id],size.width>0,size.height>0,size.width<=area.width,size.height<=area.height else{continue}
            if used>0 && (used+size.width>lane+0.5) {y-=rowHeight+gap;used=0;rowHeight=0}
            if y-size.height<area.minY {
                columnIndex+=1
                guard columns.indices.contains(columnIndex) else{break}
                x=columns[columnIndex]
                y=area.maxY;used=0;rowHeight=0
            }
            var r=NSRect(x:x+used,y:y-size.height,width:size.width,height:size.height)
            // Unselected visible windows keep their positions and reserve space.
            // Each retry moves below a blocker or advances to the next column.
            while true {
                let blockers=obstacles.filter { r.insetBy(dx:-gap/2,dy:-gap/2).intersects($0.insetBy(dx:-gap/2,dy:-gap/2)) }
                if blockers.isEmpty { break }
                y=min(y,blockers.map(\.minY).min()!-gap);used=0;rowHeight=0
                if y-size.height<area.minY {
                    columnIndex+=1
                    guard columns.indices.contains(columnIndex) else{return result}
                    x=columns[columnIndex];y=area.maxY
                }
                r=NSRect(x:x+used,y:y-size.height,width:size.width,height:size.height)
            }
            result[id]=r;used+=size.width+gap;rowHeight=max(rowHeight,size.height)
        }
        return result
    }
    static func snapped(_ rect:NSRect,area:NSRect,anchor:NSPoint)->NSRect {
        var r=rect;let step:CGFloat=180
        r.origin.x=anchor.x+((r.minX-anchor.x)/step).rounded()*step
        let top=anchor.y+((r.maxY-anchor.y)/step).rounded()*step;r.origin.y=top-r.height
        r.origin.x=max(area.minX,min(r.minX,area.maxX-r.width));r.origin.y=max(area.minY,min(r.minY,area.maxY-r.height));return r
    }
}

/// A card's position in the Toolbox layout, relative to the display's top-left.
struct ToolboxPosition: Codable {
    let screen: String
    let left: Double
    let top: Double

    static func file(for id: String) -> URL {
        GridPreferences.folder.appendingPathComponent("positions").appendingPathComponent(id + ".json")
    }

    static func read(_ id: String) -> Self? {
        guard let data = try? Data(contentsOf: file(for: id)),
              let position = try? JSONDecoder().decode(Self.self, from: data),
              position.left.isFinite, position.top.isFinite else { return nil }
        return position
    }

    func origin(size: NSSize, in area: NSRect) -> NSPoint? {
        guard size.width > 0, size.height > 0, size.width <= area.width,
              size.height <= area.height else { return nil }
        return NSPoint(x: min(max(area.minX + left, area.minX), area.maxX - size.width),
                       y: min(max(area.maxY - top - size.height, area.minY), area.maxY - size.height))
    }

    @MainActor static func screenKey(_ screen: NSScreen) -> String? {
        guard let display = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(display.uint32Value) else { return nil }
        return CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String
    }

    @MainActor static func save(_ frame: NSRect, for id: String) throws {
        guard CardPlacement(frame).valid,
              let display = NSScreen.screens.first(where: { $0.visibleFrame.contains(frame) }),
              let key = screenKey(display) else { throw CocoaError(.fileWriteInvalidFileName) }
        let area = display.visibleFrame
        let position = Self(screen: key, left: frame.minX - area.minX, top: area.maxY - frame.maxY)
        let destination = file(for: id)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(position).write(to: destination, options: .atomic)
    }
}

/// Managed cards use the Toolbox record even when its settings window is closed.
@MainActor final class CardPositionController: NSObject {
    static let shared = CardPositionController()
    private weak var panel: NSWindow?
    private var restoreWork: DispatchWorkItem?
    private var observing = false
    private var id: String { Bundle.main.bundleIdentifier ?? "" }
    var managed: Bool { FileManager.default.fileExists(atPath: ToolboxPosition.file(for: id).path) }

    func attach(_ window: NSWindow) {
        panel = window
        if !observing {
            observing = true
            NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                name: NSApplication.didChangeScreenParametersNotification, object: nil)
        }
        if managed {
            window.setFrameAutosaveName("")
            window.alphaValue = 0
            restore(allowOtherDisplay: false)
            screensChanged()
        }
    }

    @objc private func screensChanged() {
        guard managed else { return }
        restoreWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.restore() }
        restoreWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    func restore(allowOtherDisplay: Bool = true) {
        guard let panel, let saved = ToolboxPosition.read(id) else { return }
        panel.setFrameAutosaveName("")
        let screens = NSScreen.screens
        let preferred = screens.first { ToolboxPosition.screenKey($0) == saved.screen }
        let candidates = [preferred].compactMap { $0 } + (allowOtherDisplay ? screens : [])
        for screen in candidates {
            guard let origin = saved.origin(size: panel.frame.size, in: screen.visibleFrame) else { continue }
            if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
            panel.alphaValue = 1
            return
        }
    }

    func saveUserMove(_ window: NSWindow?, legacyName: String, snap: Bool = false) {
        guard let window else { return }
        guard managed else { window.saveFrame(usingName: legacyName); return }
        var frame = window.frame
        let grid = GridPreferences.read()
        if snap, grid.snap, let area = window.screen?.visibleFrame {
            frame = CardGrid.snapped(frame, area: area,
                                     anchor: NSPoint(x: grid.anchorX ?? area.minX + 20, y: grid.anchorTop ?? area.maxY - 20))
        }
        if !place(window, frame: frame) { restore() }
    }

    @discardableResult
    func place(_ window: NSWindow, frame: NSRect) -> Bool {
        do { try ToolboxPosition.save(frame, for: id) }
        catch { return false }
        restoreWork?.cancel()
        window.setFrameAutosaveName("")
        window.setFrame(frame, display: true)
        window.alphaValue = 1
        return true
    }
}
