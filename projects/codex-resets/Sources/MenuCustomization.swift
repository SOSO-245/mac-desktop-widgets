import AppKit
import SwiftUI

struct MenuField:Identifiable {
    let id:String
    let title:String
    let value:String
    var color:NSColor = .white
    var defaultVisible=true
    var colorKey:String? = nil
    var ring=false
    var progress:Double? = nil
    var paletteKey:String { colorKey ?? id }
}
struct MenuCustomization:Codable,Equatable {
    var enabled=false
    var visible:[String:Bool]=[:]
    var labels:[String:String]=[:]
    var colors:[String:String]=[:]
    var prefix=""
    var separator=" · "
    var showIcon=true
    var icon="default"
    var emoji="✨"
    var iconColor="#66FFAD"
    var fontSize:Double=12
    static let key="customMenuAppearance.v1"
    static func load(defaults:UserDefaults = .standard)->Self { defaults.data(forKey:key).flatMap { try? JSONDecoder().decode(Self.self,from:$0) } ?? Self() }
    func save(defaults:UserDefaults = .standard) { defaults.set(try? JSONEncoder().encode(self),forKey:Self.key) }
    func shown(_ f:MenuField)->Bool { visible[f.id] ?? f.defaultVisible }
    func text(_ f:MenuField)->String { String((labels[f.id] ?? "{值}").prefix(60)).replacingOccurrences(of:"{值}",with:f.value) }
    static func color(_ hex:String,fallback:NSColor = .white)->NSColor {
        let raw=hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard raw.count==6,let n=UInt32(raw,radix:16) else { return fallback }
        return NSColor(srgbRed:CGFloat((n>>16)&255)/255,green:CGFloat((n>>8)&255)/255,blue:CGFloat(n&255)/255,alpha:1)
    }
    static func hex(_ color:NSColor)->String {
        guard let c=color.usingColorSpace(.sRGB) else { return "#FFFFFF" }
        return String(format:"#%02X%02X%02X",Int((c.redComponent*255).rounded()),Int((c.greenComponent*255).rounded()),Int((c.blueComponent*255).rounded()))
    }
    func render(fields:[MenuField],fallback:NSImage?)->NSImage {
        let font=NSFont.monospacedDigitSystemFont(ofSize:min(18,max(10,fontSize)),weight:.semibold)
        let text=NSMutableAttributedString(string:"")
        func append(_ string:String,_ color:NSColor) { text.append(NSAttributedString(string:string,attributes:[.font:font,.foregroundColor:color])) }
        if !prefix.isEmpty { append(String(prefix.prefix(40)),Self.color(colors["prefix"] ?? "#FFFFFF")) }
        for f in fields where shown(f) {
            if text.length>0 { append(String(separator.prefix(8)),.secondaryLabelColor) }
            let ink=Self.color(colors[f.paletteKey] ?? "",fallback:f.color)
            if f.ring {
                let ring=NSImage(size:NSSize(width:14,height:14),flipped:false) { _ in
                    let track=NSBezierPath(ovalIn:NSRect(x:2,y:2,width:10,height:10));track.lineWidth=2;NSColor.gray.setStroke();track.stroke()
                    if let value=f.progress,value.isFinite,value>0 {
                        let arc=NSBezierPath();arc.appendArc(withCenter:NSPoint(x:7,y:7),radius:5,startAngle:90,endAngle:90-CGFloat(min(1,value)*360),clockwise:true);arc.lineWidth=2;arc.lineCapStyle = .round;ink.setStroke();arc.stroke()
                    };return true
                }
                let attachment=NSTextAttachment();attachment.image=ring;attachment.bounds=NSRect(x:0,y:-2,width:14,height:14)
                text.append(NSAttributedString(attachment:attachment))
            }
            append(self.text(f),ink)
        }
        var symbol:NSImage?=nil
        if showIcon || text.length==0 {
            if icon=="default" { symbol=fallback }
            else if icon != "emoji" { symbol=NSImage(systemSymbolName:icon,accessibilityDescription:nil)?.withSymbolConfiguration(.init(paletteColors:[Self.color(iconColor)])) }
            if symbol==nil && (icon != "emoji" || emoji.isEmpty) { symbol=NSImage(systemSymbolName:"circle.fill",accessibilityDescription:nil) }
        }
        let iconWidth:CGFloat=(symbol != nil || (showIcon && icon=="emoji")) ? 21 : 0
        let width=max(18,ceil(iconWidth+text.size().width+2))
        let result=NSImage(size:NSSize(width:width,height:22),flipped:false) { _ in
            if let symbol { symbol.draw(in:NSRect(x:1,y:3,width:16,height:16)) }
            else if self.showIcon && self.icon=="emoji" {
                let mark=NSAttributedString(string:String(self.emoji.prefix(2)),attributes:[.font:NSFont.systemFont(ofSize:15)])
                mark.draw(at:NSPoint(x:0,y:(22-mark.size().height)/2))
            }
            text.draw(at:NSPoint(x:iconWidth,y:(22-text.size().height)/2));return true
        }
        result.isTemplate=false;return result
    }
}
@MainActor final class MenuCustomizationPanel {
    static let shared=MenuCustomizationPanel()
    func show(title:String,fields:[MenuField],icon:NSImage?,extraColors:[(String,String,NSColor)]=[],onSave:@escaping()->Void) {
        AppSettingsController.shared.show("menubar")
    }
    static func apply(_ button:NSStatusBarButton,fields:[MenuField],icon:NSImage?) {
        let settings=MenuCustomization.load();guard settings.enabled else { return }
        let rendered=settings.render(fields:fields,fallback:icon)
        // Equal pixels keep the existing image in place, avoiding refresh flashes.
        if button.image?.tiffRepresentation != rendered.tiffRepresentation { button.image=rendered }
        button.attributedTitle=NSAttributedString(string:"");button.title="";button.imagePosition = .imageOnly
        button.setAccessibilityLabel(fields.filter { settings.shown($0) }.map { settings.text($0) }.joined(separator:settings.separator))
    }
}
struct MenuCustomizationView:View {
    let fields:[MenuField]
    let fallback:NSImage?
    let extraColors:[(String,String,NSColor)]
    let onSave:()->Void
    private let defaults:UserDefaults
    @State private var draft:MenuCustomization
    init(fields:[MenuField],fallback:NSImage?,extraColors:[(String,String,NSColor)]=[],defaults:UserDefaults = .standard,onSave:@escaping()->Void) {
        self.fields=fields;self.fallback=fallback;self.extraColors=extraColors;self.onSave=onSave;self.defaults=defaults
        _draft=State(initialValue:MenuCustomization.load(defaults:defaults))
    }
    private func color(_ key:String,_ fallback:NSColor)->Binding<Color> {
        Binding(get:{Color(nsColor:MenuCustomization.color(draft.colors[key] ?? "",fallback:fallback))},set:{draft.colors[key]=MenuCustomization.hex(NSColor($0))})
    }
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            Toggle("使用自定义菜单栏",isOn:$draft.enabled).font(.headline)
            Text("更改立即保存。启用后覆盖基础显示；文字中的 {值} 会替换为实时数据。").font(.callout).foregroundStyle(.secondary)
            Group {
                VStack(alignment:.leading,spacing:12) {
                    ForEach(fields) { f in
                        HStack {
                            Toggle(f.title,isOn:Binding(get:{draft.shown(f)},set:{draft.visible[f.id]=$0})).frame(width:125,alignment:.leading)
                            TextField("自定义文字 / {值}",text:Binding(get:{draft.labels[f.id] ?? "{值}"},set:{draft.labels[f.id]=String($0.prefix(60))})).textFieldStyle(.roundedBorder)
                            ColorPicker("颜色",selection:color(f.paletteKey,f.color),supportsOpacity:false).labelsHidden()
                        }
                    }
                    ForEach(extraColors,id:\.0) { item in ColorPicker(item.1,selection:color(item.0,item.2),supportsOpacity:false) }
                    Divider()
                    TextField("固定文字",text:$draft.prefix).textFieldStyle(.roundedBorder)
                    HStack {
                        TextField("分隔符",text:$draft.separator).textFieldStyle(.roundedBorder)
                        ColorPicker("固定文字颜色",selection:color("prefix",.white),supportsOpacity:false)
                    }
                    Toggle("显示图标",isOn:$draft.showIcon)
                    Picker("图标",selection:$draft.icon) {
                        Text("原来的图标").tag("default")
                        ForEach(["wifi.router.fill","network","bolt.fill","house.fill","calendar","clock.arrow.circlepath","star.fill","moon.stars.fill"],id:\.self) { symbol in Label(symbolTitle(symbol),systemImage:symbol).tag(symbol) }
                        Text("彩色表情 / 自定义字符").tag("emoji")
                    }
                    if draft.icon=="emoji" { TextField("图标字符",text:$draft.emoji).textFieldStyle(.roundedBorder) }
                    ColorPicker("图标颜色",selection:Binding(get:{Color(nsColor:MenuCustomization.color(draft.iconColor))},set:{draft.iconColor=MenuCustomization.hex(NSColor($0))}),supportsOpacity:false)
                    Text("图标颜色用于上方选择的系统图标；原图标与表情保留自身配色。").font(.caption).foregroundStyle(.secondary)
                    HStack { Text("字号");Slider(value:$draft.fontSize,in:10...18,step:1);Text("\(Int(draft.fontSize))") }
                }.padding(3)
            }.disabled(!draft.enabled)
            Text("预览").font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal) { Image(nsImage:draft.render(fields:fields,fallback:fallback)).padding(12) }.frame(height:52).background(.black.opacity(0.25),in:RoundedRectangle(cornerRadius:10))
            HStack {
                Button("恢复原来的显示") { draft=MenuCustomization() }
                Spacer()
                Text("自动保存").font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth:.infinity,alignment:.leading).preferredColorScheme(.dark)
            .onChange(of:draft) { _, value in value.save(defaults:defaults);onSave() }
    }
    private func symbolTitle(_ s:String)->String { ["wifi.router.fill":"路由器","network":"网络","bolt.fill":"闪电","house.fill":"房屋","calendar":"日历","clock.arrow.circlepath":"倒计时","star.fill":"星星","moon.stars.fill":"星月"][s] ?? s }
}
