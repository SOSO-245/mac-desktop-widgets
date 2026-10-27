import AppKit

struct ToolModule:Identifiable,Codable {
    let id:String;let name:String;let appName:String;let symbol:String
    static let all:[Self]=[
        .init(id:"local.homeatlas.LunarCalendar",name:"万年历",appName:"万年历",symbol:"calendar"),
        .init(id:"local.homeatlas.HomeEnergy",name:"家庭概览",appName:"家庭概览",symbol:"house.fill"),
        .init(id:"local.homeatlas.CodexResets",name:"重置监测",appName:"Codex 重置",symbol:"arrow.triangle.2.circlepath"),
        .init(id:"local.homeatlas.NikkiMonitor",name:"Nikki",appName:"Nikki 实时卡片",symbol:"wifi.router.fill"),
        .init(id:"local.homeatlas.FlClashMonitor",name:"VPN 监测",appName:"FlClash 实时卡片",symbol:"network"),
        .init(id:"local.homeatlas.MacVitals",name:"Mac 监测",appName:"Mac 实时监测",symbol:"desktopcomputer")]
}
struct CardPlacement:Codable,Equatable {var x:Double;var y:Double;var width:Double;var height:Double
    init(_ r:NSRect){x=r.minX;y=r.minY;width=r.width;height=r.height}
    var rect:NSRect{NSRect(x:x,y:y,width:width,height:height)}
    var valid:Bool{[x,y,width,height].allSatisfy{$0.isFinite} && width>=100 && width<=1000 && height>=100 && height<=1000 && abs(x)<100000 && abs(y)<100000}
}
struct CardPresence:Codable {let id:String;let updated:Date;let visible:Bool;let size:String;let frame:CardPlacement;var glass:Bool?=nil;var brightness:Double?=nil;var transparency:Double?=nil}
struct GridPreferences:Codable {
    var snap=false;var automatic=false;var anchorX:Double?;var anchorTop:Double?;var screenID:UInt32?
    static let folder=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/HomeAtlasToolbox")
    static func read()->Self {(try? JSONDecoder().decode(Self.self,from:Data(contentsOf:folder.appendingPathComponent("grid.json")))) ?? Self()}
    func save(){try? FileManager.default.createDirectory(at:Self.folder,withIntermediateDirectories:true);if let d=try? JSONEncoder().encode(self){try? d.write(to:Self.folder.appendingPathComponent("grid.json"),options:.atomic)}}
}
/// Pack the actual card sizes, preserving order. Two 164 pt cards share a 344 pt lane.
enum CardGrid {
    static func pack(_ sizes:[String:NSSize],order:[String],area:NSRect,anchor:NSPoint,gap:CGFloat=16)->[String:NSRect] {
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
            let r=NSRect(x:x+used,y:y-size.height,width:size.width,height:size.height)
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
