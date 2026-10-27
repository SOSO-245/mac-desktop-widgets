import AppKit
import SwiftUI

@main struct ElectricBorderTests {
    @MainActor static func main() throws {
        let output=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        _=NSApplication.shared
        let orange=Color(red:1,green:0.59,blue:0.24)
        for family in CardSize.allCases {
            let size=CGSize(width:family.width,height:family.height)
            let a=ResetElectricBorder.electricPath(size:size,radius:28,time:100)
            let b=ResetElectricBorder.electricPath(size:size,radius:28,time:100.2)
            precondition(a != b,"Electric border must move with time")
            precondition(a == ResetElectricBorder.electricPath(size:size,radius:28,time:100),"Rendering must be deterministic")
            for frame in 0..<60 {
                let path=ResetElectricBorder.electricPath(size:size,radius:28,time:100+Double(frame)/30)
                let bounds=path.boundingRect
                precondition(bounds.minX>1 && bounds.minY>1 && bounds.maxX<size.width-1 && bounds.maxY<size.height-1,"Border clipped by panel")
            }
            let name=family == .small ? "small":family == .medium ? "medium":"large"
            for frame in [0,1] {
                let content=ResetCard(desktopSurface:true,snapshot:.sample,size:family,now:Date())
                    .background(ResetBackground())
                    .overlay {ResetElectricBorder(color:orange,cornerRadius:28,fixedTime:100+Double(frame)*0.2)}
                    .clipShape(RoundedRectangle(cornerRadius:28,style:.continuous))
                    .containerShape(RoundedRectangle(cornerRadius:28,style:.continuous))
                    .frame(width:size.width,height:size.height).environment(\.colorScheme,.dark)
                let window=NSWindow(contentRect:NSRect(origin:.zero,size:size),styleMask:.borderless,backing:.buffered,defer:false)
                window.isReleasedWhenClosed=false;window.backgroundColor = .clear;window.isOpaque=false
                let host=NSHostingView(rootView:content);host.frame=NSRect(origin:.zero,size:size);window.contentView=host
                host.layoutSubtreeIfNeeded();RunLoop.current.run(until:Date().addingTimeInterval(0.1));host.displayIfNeeded()
                let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!
                host.cacheDisplay(in:host.bounds,to:bitmap)
                try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("\(name)-electric-\(frame).png"))
                window.close()
            }
        }
        print("PASS: three sizes, 180 in-bounds frames, deterministic motion, six offline renders")
    }
}
