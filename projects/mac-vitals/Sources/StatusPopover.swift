import AppKit
import SwiftUI

private final class MenuCardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct SystemFrost: NSViewRepresentable {
    var menu: Bool
    func makeNSView(context:Context)->NSVisualEffectView {
        let view=NSVisualEffectView();view.blendingMode = .behindWindow
        view.state = .active;view.material = menu ? .menu : .hudWindow
        view.appearance=NSAppearance(named:.darkAqua);return view
    }
    func updateNSView(_ view:NSVisualEffectView,context:Context) {view.material = menu ? .menu : .hudWindow}
}

struct FrostedSurface: View {
    var brightness:Double=0, radius:CGFloat=14, menu=false
    var transparency:Double=0
    var body:some View {
        ZStack {
            SystemFrost(menu:menu)
            if brightness < 0 {Color.black.opacity(min(0.88,-brightness*0.0088))}
            else {Color.white.opacity(min(0.28,brightness*0.0028))}
        }.opacity(1-min(0.8,max(0,transparency/100))).clipShape(RoundedRectangle(cornerRadius:radius,style:.continuous))
         .overlay(RoundedRectangle(cornerRadius:radius,style:.continuous).strokeBorder(.white.opacity(0.24),lineWidth:0.65))
         .allowsHitTesting(false)
    }
}

@MainActor final class DesktopCardAppearance:ObservableObject {
    static let shared=DesktopCardAppearance()
    @Published var glass:Bool {didSet{UserDefaults.standard.set(glass,forKey:"desktopCard.glass")}}
    @Published var brightness:Double {didSet{UserDefaults.standard.set(Self.clamp(brightness),forKey:"desktopCard.brightness")}}
    @Published var transparency:Double {didSet{UserDefaults.standard.set(min(80,max(0,transparency)),forKey:"desktopCard.transparency")}}
    @Published private(set) var forcesGlass = false
    var effectiveGlass: Bool { forcesGlass || glass }
    func configure(forceGlass: Bool) { forcesGlass = forceGlass }
    static func clamp(_ value:Double)->Double {value.isFinite ? min(100,max(-100,value)) : 0}
    private init() {transparency=min(80,max(0,UserDefaults.standard.double(forKey:"desktopCard.transparency")));glass=UserDefaults.standard.bool(forKey:"desktopCard.glass");brightness=Self.clamp(UserDefaults.standard.double(forKey:"desktopCard.brightness"))}
    func show() {
        AppSettingsController.shared.show("desktop")
    }
}
struct DesktopAppearanceSettings:View {
    @ObservedObject var model:DesktopCardAppearance
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            Text("卡片背景").font(.headline)
            if model.forcesGlass { Text("系统毛玻璃").foregroundStyle(.secondary) }
            else { Picker("背景",selection:$model.glass) {Text("原有配色").tag(false);Text("毛玻璃").tag(true)}.pickerStyle(.segmented) }
            HStack {Text("明暗");Spacer();Text(String(format:"%+.0f",model.brightness)).monospacedDigit().foregroundStyle(.secondary)}
            Slider(value:$model.brightness,in:-100...100).disabled(!model.effectiveGlass).accessibilityLabel("卡片背景明暗")
            HStack {Text("更暗");Spacer();Text("更亮")}.font(.caption).foregroundStyle(.secondary)
            HStack {Text("背景透明度");Spacer();Text(String(format:"%.0f%%",model.transparency)).monospacedDigit()}
            Slider(value:$model.transparency,in:0...80).disabled(!model.effectiveGlass).accessibilityLabel("卡片背景透明度")
            HStack {
                Button("接近桌面小组件") {model.glass=true;model.brightness = -65}
                Spacer()
                Button("恢复原样") {model.brightness=0;model.transparency=0;model.glass=false}
            }
            Text("立即生效并自动保存。只调整桌面卡片背景，文字与数值保持清晰。").font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth:.infinity,alignment:.leading).preferredColorScheme(.dark)
    }
}
struct DesktopCardSurface<Content:View>:View {
    @ObservedObject private var appearance=DesktopCardAppearance.shared
    let original:Content, plain:Content
    var body:some View {
        Group {if appearance.effectiveGlass {plain} else {original}}.background {if appearance.effectiveGlass {FrostedSurface(brightness:appearance.brightness,radius:28,transparency:appearance.transparency)}}
    }
}
private struct NativeActionRow:View {
    let title:String, symbol:String, action:()->Void
    @State private var hovered=false
    var body:some View {
        Button(action:action) {HStack {Text(title);Spacer();Image(systemName:symbol).font(.system(size:11)).foregroundStyle(.secondary)}
            .font(.system(size:13,weight:.medium)).padding(.horizontal,12).frame(height:29)
            .contentShape(Rectangle()).background(hovered ? Color.accentColor.opacity(0.7):.clear,in:RoundedRectangle(cornerRadius:5))}
            .buttonStyle(.plain).focusEffectDisabled().onHover{hovered=$0}
    }
}

/// Independently persisted menu-bar style. Data and desktop appearance are shared only by value.
@MainActor final class StatusPopover:NSObject,ObservableObject {
    enum Style:String,CaseIterable {case glass,native
        var title:String {self == .glass ? "玻璃卡片" : "原生毛玻璃菜单"}
    }
    var menu=NSMenu() {didSet{installOptions();if let item{AppUpdater.shared.attach(to:item,menu:menu)}}}
    var style:Style {Style(rawValue:UserDefaults.standard.string(forKey:"statusPopover.style") ?? "") ?? .glass}
    private weak var item:NSStatusItem?
    private var panel:MenuCardPanel?,host:NSHostingView<AnyView>?
    private var content:((Bool)->AnyView)?
    private var openTitle="打开",openAction:(()->Void)?
    var legacyToggle:(()->Void)?,legacyClose:(()->Void)?,legacyIsShown:(()->Bool)?
    var visibilityChanged:(()->Void)?
    var settingsContent: AnyView { AnyView(StatusPopoverSettingsContent(model:self)) }
    func applyStyle(_ value: Style) {
        close(); objectWillChange.send()
        UserDefaults.standard.set(value.rawValue,forKey:"statusPopover.style")
        refreshChecks()
    }
    private var cardSize=NSSize(width:344,height:344)
    private var desktopOptions=false
    private var localMonitor:Any?,outsideMonitor:Any?,workspaceObserver:Any?
    var isShown:Bool {(panel?.isVisible ?? false) || (legacyIsShown?() ?? false)}
    func attach(to item:NSStatusItem,menu:NSMenu,size:NSSize,openTitle:String,open:@escaping()->Void,
                desktopOptions:Bool=false,content:@escaping(Bool)->AnyView) {
        self.item=item;self.desktopOptions=desktopOptions;self.menu=menu;self.cardSize=size
        self.openTitle=openTitle;openAction=open;self.content=content
        AppUpdater.shared.beforeShowingUpdate = {[weak self] in self?.close()}
        item.menu=nil;item.button?.target=self;item.button?.action=#selector(clicked(_:))
        item.button?.sendAction(on:[.leftMouseUp,.rightMouseUp])
        item.button?.setAccessibilityHelp("点击展开浮窗；右键打开菜单和设置")
    }
    private func installOptions() {
        AppSettingsController.shared.installMenuItem(in:menu)
        refreshChecks()
    }
    private func refreshChecks() {
        for row in menu.items.first(where:{$0.identifier?.rawValue=="popover-style"})?.submenu?.items ?? [] {row.state=(row.representedObject as? String)==style.rawValue ? .on:.off}
    }
    @objc private func selectStyle(_ sender:NSMenuItem) {
        guard let raw=sender.representedObject as? String,Style(rawValue:raw) != nil else{return}
        close();UserDefaults.standard.set(raw,forKey:"statusPopover.style");refreshChecks()
        DispatchQueue.main.async {[weak self] in
            guard let self else{return}
            if self.style == .glass,let legacy=self.legacyToggle {legacy()} else {self.show()}
        }
    }
    @objc private func showDesktopAppearance(){close();DesktopCardAppearance.shared.show()}
    @objc private func clicked(_ sender:Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {showMenu();return}
        if style == .glass,let legacyToggle {legacyToggle();return}
        if isShown {close();return}
        show()
    }
    func show() {
        guard let button=item?.button,let anchor=button.window else{return}
        let area=(anchor.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x:0,y:0,width:1280,height:800)
        let wanted=cardSize.height+(style == .native ? 104:0)
        let height=min(wanted,max(180,area.height-16))
        let rect=anchor.convertToScreen(button.convert(button.bounds,to:nil))
        let x=max(area.minX+8,min(rect.midX-cardSize.width/2,area.maxX-cardSize.width-8))
        let y=max(area.minY+8,rect.minY-height-6)
        if panel==nil {
            let p=MenuCardPanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            p.title="菜单栏卡片";p.identifier=NSUserInterfaceItemIdentifier("StatusCardPreview")
            p.backgroundColor = .clear;p.isOpaque=false;p.hasShadow=true;p.isReleasedWhenClosed=false
            p.hidesOnDeactivate=false;p.isMovable=false;p.level = .popUpMenu
            p.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.transient,.ignoresCycle];p.appearance=NSAppearance(named:.darkAqua)
            let h=NSHostingView(rootView:AnyView(EmptyView()));p.contentView=h;panel=p;host=h
        }
        panel?.setFrame(NSRect(x:x,y:y,width:cardSize.width,height:height),display:false)
        render();panel?.makeKeyAndOrderFront(nil);panel?.invalidateShadow();installDismissal();visibilityChanged?()
    }
    func close() {
        let wasShown=isShown;legacyClose?();panel?.orderOut(nil)
        if let localMonitor{NSEvent.removeMonitor(localMonitor)};localMonitor=nil
        if let outsideMonitor{NSEvent.removeMonitor(outsideMonitor)};outsideMonitor=nil
        if let workspaceObserver{NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)};workspaceObserver=nil
        if wasShown{visibilityChanged?()}
    }
    func update(){if panel?.isVisible == true{render()}}
    private func render() {
        guard let content,let panel else{return}
        let native=style == .native
        let card=content(native).frame(width:cardSize.width,height:cardSize.height).preferredColorScheme(.dark)
        let all=VStack(spacing:0) {
            card
            if native {
                Divider().padding(.horizontal,14)
                VStack(spacing:1) {
                    NativeActionRow(title:openTitle,symbol:"arrow.up.forward") {[weak self] in self?.close();self?.openAction?()}
                    NativeActionRow(title:"浮窗风格",symbol:"chevron.right") {[weak self] in self?.showStyleMenu()}
                    NativeActionRow(title:"更多设置",symbol:"ellipsis") {[weak self] in self?.showMenu()}
                }.padding(.horizontal,6).padding(.vertical,6)
            }
        }.frame(width:cardSize.width).foregroundStyle(.white)
        let wanted=cardSize.height+(native ? 104:0)
        let body:AnyView=panel.frame.height < wanted ? AnyView(ScrollView(.vertical){all}.scrollIndicators(.hidden)) : AnyView(all)
        host?.rootView=AnyView(body.frame(width:cardSize.width,height:panel.frame.height,alignment:.top)
            .background{if native{FrostedSurface(brightness:-28,menu:true)}}
            .clipShape(RoundedRectangle(cornerRadius:native ? 14:0,style:.continuous)).preferredColorScheme(.dark))
    }
    private func installDismissal() {
        localMonitor=NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown,.keyDown]) {[weak self] event in
            guard let self else{return event}
            if event.type == .keyDown {if event.keyCode==53{self.close();return nil}}
            else if event.window !== self.panel && event.window !== self.item?.button?.window {
                // A SwiftUI month chooser or menu can be a child window of this panel.
                if event.window?.parent !== self.panel {self.close()}
            };return event
        }
        outsideMonitor=NSEvent.addGlobalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown]) {[weak self] _ in Task{@MainActor in self?.close()}}
        workspaceObserver=NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.activeSpaceDidChangeNotification,object:nil,queue:.main) {[weak self] _ in Task{@MainActor in self?.close()}}
    }
    func showMenu(){close();refreshChecks();guard let button=item?.button else{return};menu.popUp(positioning:nil,at:NSPoint(x:0,y:button.bounds.minY),in:button)}
    private func showStyleMenu(){close();refreshChecks();guard let button=item?.button,let sub=menu.items.first(where:{$0.identifier?.rawValue=="popover-style"})?.submenu else{return};sub.popUp(positioning:nil,at:.zero,in:button)}
}

private struct StatusPopoverSettingsContent: View {
    @ObservedObject var model: StatusPopover
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            Text("菜单栏浮窗").font(.headline)
            Picker("风格",selection:Binding(get:{model.style},set:{model.applyStyle($0)})) {
                ForEach(StatusPopover.Style.allCases,id:\.self) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            Text("点击菜单栏时展开的信息窗口，和桌面卡片分别设置。").font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}
