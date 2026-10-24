import AppKit

struct MenuBarOptions: Codable, Equatable {
    var icon = true
    var site = true
    var latency = true
    var profile = true
    var quotaRing = true
    var quotaText = true
    var node = false
    var download = false
    var upload = false
    static func load() -> Self {
        UserDefaults.standard.data(forKey:"menuBarOptions").flatMap { try? JSONDecoder().decode(Self.self,from:$0) } ?? Self()
    }
    func save() { UserDefaults.standard.set(try? JSONEncoder().encode(self),forKey:"menuBarOptions") }
    var isEmpty: Bool { !icon && !site && !latency && !profile && !quotaRing && !quotaText && !node && !download && !upload }
}

struct MenuBarPalette: Codable, Equatable {
    var name = "#FFFFFF"
    var text = "#FFFFFF"
    var fast = "#66FFAD"
    var slow = "#FF6EC2"
    var ring = "#66FFAD"
    var download = "#66FFAD"
    var upload = "#B89EFF"
    static func load() -> Self {
        UserDefaults.standard.data(forKey:"menuBarPalette").flatMap { try? JSONDecoder().decode(Self.self,from:$0) } ?? Self()
    }
    func save() { UserDefaults.standard.set(try? JSONEncoder().encode(self),forKey:"menuBarPalette") }
    static func color(_ hex: String) -> NSColor {
        let clean = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard clean.count == 6, let number = UInt32(clean,radix:16) else { return .white }
        return NSColor(srgbRed:CGFloat((number>>16)&255)/255,green:CGFloat((number>>8)&255)/255,blue:CGFloat(number&255)/255,alpha:1)
    }
    static func hex(_ color: NSColor) -> String {
        guard let rgb=color.usingColorSpace(.sRGB) else { return "#FFFFFF" }
        return String(format:"#%02X%02X%02X",Int((rgb.redComponent*255).rounded()),Int((rgb.greenComponent*255).rounded()),Int((rgb.blueComponent*255).rounded()))
    }
}

enum MenuBarDisplay {
    static func remaining(used: Double?, total: Double?) -> Double? {
        guard let used, let total, used.isFinite, total.isFinite, used >= 0, total > 0 else { return nil }
        return max(0,min(1,1-used/total))
    }
    static func isSlow(milliseconds: Int?) -> Bool { milliseconds.map { $0 > 2000 } ?? false }
    static func rate(_ bytes: Double?) -> String {
        guard let bytes, bytes.isFinite, bytes >= 0 else { return "—" }
        if bytes < 1024 { return String(format:"%.0f B/s",bytes) }
        if bytes < 1048576 { return String(format:"%.0f KB/s",bytes/1024) }
        return String(format:"%.1f MB/s",bytes/1048576)
    }
    static func image(icon: NSImage?, site: String, delay: String, milliseconds: Int? = nil,
                      profile: String, remaining: Double?, options: MenuBarOptions = MenuBarOptions(),
                      node: String = "—", download: String = "—", upload: String = "—", palette:MenuBarPalette = .load()) -> NSImage {
        let neon = MenuBarPalette.color(palette.fast)
        let pink = MenuBarPalette.color(palette.slow)
        let font = NSFont.monospacedDigitSystemFont(ofSize:11,weight:.semibold)
        struct Part { var text: NSAttributedString?; var width: CGFloat; var kind: Int = 0 }
        var parts: [Part] = []
        func add(_ text: String, color: NSColor? = nil, reserved: String? = nil) {
            let string = NSAttributedString(string:text,attributes:[.font:font,.foregroundColor:color ?? MenuBarPalette.color(palette.text)])
            let minimum = reserved.map { NSAttributedString(string:$0,attributes:[.font:font]).size().width } ?? 0
            parts.append(Part(text:string,width:max(string.size().width,minimum)))
        }
        func separator() { if !parts.isEmpty { add(" · ",color:.secondaryLabelColor) } }
        if options.icon || options.isEmpty { parts.append(Part(width:19,kind:1)) }
        if options.site { add(site,color:MenuBarPalette.color(palette.name)) }
        if options.latency { if options.site { add(" · ",color:MenuBarPalette.color(palette.name)) }; add(delay,color:isSlow(milliseconds:milliseconds) ? pink : neon,reserved:"9999 ms") }
        if options.profile { separator(); add(profile) }
        if options.node { separator(); add(node) }
        if options.quotaRing || options.quotaText {
            separator()
            if options.quotaRing { parts.append(Part(width:16,kind:2)) }
            if options.quotaText { add(remaining.map{String(format:"剩 %.0f%%",$0*100)} ?? "剩 —") }
        }
        if options.download { separator(); add("↓ " + download,color:MenuBarPalette.color(palette.download),reserved:"↓ 999 KB/s") }
        if options.upload { separator(); add("↑ " + upload,color:MenuBarPalette.color(palette.upload),reserved:"↑ 999 KB/s") }
        let result = NSImage(size:NSSize(width:ceil(parts.reduce(0){$0+$1.width}),height:18),flipped:false) { _ in
            var x: CGFloat = 0
            for part in parts {
                switch part.kind {
                case 1:
                    let symbol = icon ?? NSImage(systemSymbolName:"network",accessibilityDescription:"Nikki")
                    symbol?.draw(in:NSRect(x:x,y:1.5,width:15,height:15))
                case 2:
                    let center = NSPoint(x:x+7,y:9)
                    let track = NSBezierPath(ovalIn:NSRect(x:x+1.5,y:3.5,width:11,height:11))
                    track.lineWidth=2.2; NSColor.labelColor.withAlphaComponent(0.25).setStroke(); track.stroke()
                    if let remaining, remaining > 0 {
                        let arc=NSBezierPath(); arc.appendArc(withCenter:center,radius:5.5,startAngle:90,endAngle:90-CGFloat(remaining*360),clockwise:true)
                        arc.lineWidth=2.2;arc.lineCapStyle = .round;MenuBarPalette.color(palette.ring).setStroke();arc.stroke()
                    }
                default: if let text=part.text { text.draw(at:NSPoint(x:x,y:(18-text.size().height)/2)) }
                }
                x += part.width
            }
            return true
        }
        result.isTemplate=false;return result
    }
}
