import AppKit
@main struct MenuBarTests {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        var p=MenuBarPalette(); p.fast="#12AB34";p.slow="#C254F1"
        let copy=try JSONDecoder().decode(MenuBarPalette.self,from:JSONEncoder().encode(p))
        precondition(copy==p)
        precondition(MenuBarPalette.hex(MenuBarPalette.color(p.fast))==p.fast)
        precondition(MenuBarPalette.hex(MenuBarPalette.color("invalid"))=="#FFFFFF")
        var o=MenuBarOptions();o.icon=false;o.site=false;o.latency=false;o.profile=false;o.quotaRing=false;o.quotaText=false
        precondition(o.isEmpty)
        let fallback=MenuBarDisplay.image(icon:nil,site:"Example",delay:"128 ms",profile:"Demo",remaining:0.5,options:o,palette:p)
        precondition(fallback.size.width>=15)
        o.latency=true
        let short=MenuBarDisplay.image(icon:nil,site:"Example",delay:"1 ms",profile:"Demo",remaining:0.5,options:o,palette:p)
        let long=MenuBarDisplay.image(icon:nil,site:"Example",delay:"9999 ms",profile:"Demo",remaining:0.5,options:o,palette:p)
        precondition(short.size==long.size)
        o.download=true;o.upload=true;o.node=true
        let all=MenuBarDisplay.image(icon:nil,site:"Example",delay:"128 ms",profile:"Demo",remaining:0.5,options:o,node:"Example node",download:"2 MB/s",upload:"1 KB/s",palette:p)
        precondition(all.size.width>short.size.width)
        precondition(MenuBarDisplay.remaining(used:150,total:100)==0)
        precondition(MenuBarDisplay.rate(nil)=="—")
        precondition(!MenuBarDisplay.isSlow(milliseconds:2000) && MenuBarDisplay.isSlow(milliseconds:2001))
        print("PASS 10 menu layout / palette checks; no saved preferences changed")
    }
}
