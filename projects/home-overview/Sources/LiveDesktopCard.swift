import AppKit
import SwiftUI

private final class LiveCardPanel:NSPanel {
    override var canBecomeKey:Bool {true}
}
private final class LiveCardHostingView:NSHostingView<AnyView> {
    override var mouseDownCanMoveWindow:Bool {true}
}
@MainActor final class LiveDesktopCard:NSObject,ObservableObject {
    private var panel:LiveCardPanel?
    private var host:NSHostingView<AnyView>?
    private var content:((String,Bool,AnyView)->AnyView)?
    private var refresh:(()->Void)?
    private var dragStart:NSPoint?
    private var dragWindowStart:NSPoint?
    var changed:(()->Void)?
    private let prefs=UserDefaults.standard
    var size:String {prefs.string(forKey:"desktopCard.size") ?? "medium"}
    var locked:Bool {prefs.bool(forKey:"desktopCard.locked")}
    var hidden:Bool {prefs.bool(forKey:"desktopCard.hidden")}
    var top:Bool {prefs.bool(forKey:"desktopCard.top")}
    var visible:Bool {panel?.isVisible == true}
    var skin:String {prefs.string(forKey:"desktopCard.skin") ?? "animated"}
    var character:String {prefs.string(forKey:"desktopCard.character") == "swan" ? "swan":"duck"}
    var waterTheme:String {skin == "native" ? "native":character}
    func setSkin(_ value:String) {
        guard ["native","animated"].contains(value) else{return}
        objectWillChange.send();prefs.set(value,forKey:"desktopCard.skin")
        if value == "native" {try? FileManager.default.removeItem(at:GridPreferences.folder.appendingPathComponent("status/home-water.json"))}
        update()
    }
    func setCharacter(_ value:String) {
        guard ["duck","swan"].contains(value) else{return}
        objectWillChange.send();prefs.set(value,forKey:"desktopCard.character");update()
    }
    var settingsContent:AnyView {AnyView(DesktopCardSettings(model:self))}
    private var dimensions:NSSize {NSSize(width:size=="small" ? 164:344,height:size=="large" ? 344:164)}
    func start(title:String,menu:NSMenu,refresh:@escaping()->Void,content:@escaping(String,Bool,AnyView)->AnyView) {
        self.content=content;self.refresh=refresh
        let p=LiveCardPanel(contentRect:NSRect(origin:.zero,size:dimensions),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        p.title=title+" · 桌面卡片";p.identifier=NSUserInterfaceItemIdentifier("LiveDesktopCard")
        p.isMovable = !locked;p.isMovableByWindowBackground=true;p.setFrameAutosaveName("LiveDesktopCard.Frame");p.backgroundColor = .clear;p.isOpaque=false;p.hasShadow=true;p.isReleasedWhenClosed=false;p.hidesOnDeactivate=false
        p.collectionBehavior=[.canJoinAllSpaces,.stationary,.fullScreenAuxiliary,.ignoresCycle]
        if !p.setFrameUsingName("LiveDesktopCard.Frame") {p.center()}
        panel=p;let h=LiveCardHostingView(rootView:AnyView(EmptyView()));h.sizingOptions=[];p.contentView=h;host=h
        resize();updateLevel()
        if !hidden {p.orderFrontRegardless()}
    }
    func update() {
        guard dragStart == nil,let content,let host else {return}
        let controls=AnyView(HStack(spacing:6) {
            Button(action:{[weak self] in self?.refresh?()}) {Image(systemName:"arrow.clockwise")}.help("立即刷新")
            Button(action:{[weak self] in self?.toggleLock()}) {Image(systemName:locked ? "lock.fill":"lock.open")}.foregroundStyle(locked ? Color.cyan:Color.mint).help(locked ? "解锁位置":"锁定位置")
        }.font(.system(size:10)).buttonStyle(.plain).focusEffectDisabled())
        host.rootView=AnyView(DesktopCardSurface(original:content(size,false,controls),plain:content(size,true,controls)).frame(width:dimensions.width,height:dimensions.height).clipShape(RoundedRectangle(cornerRadius:28)).containerShape(RoundedRectangle(cornerRadius:28)).environment(\.colorScheme,.dark)
            .highPriorityGesture(DragGesture(minimumDistance:4).onChanged { [weak self] _ in
                guard let self,!self.locked,let panel=self.panel else{return}
                let mouse=NSEvent.mouseLocation
                if self.dragStart == nil {self.dragStart=mouse;self.dragWindowStart=panel.frame.origin}
                guard let start=self.dragStart,let origin=self.dragWindowStart else{return}
                panel.setFrameOrigin(NSPoint(x:origin.x+mouse.x-start.x,y:origin.y+mouse.y-start.y))
            }.onEnded { [weak self] _ in
                guard let self else{return};self.dragStart=nil;self.dragWindowStart=nil
                self.panel?.saveFrame(usingName:"LiveDesktopCard.Frame");self.update()
            },including:locked ? .subviews:.all))
    }
    private func resize() {
        guard let panel else {return};var frame=panel.frame;frame.origin.y=frame.maxY-dimensions.height;frame.size=dimensions
        if let area=panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {frame.origin.x=max(area.minX,min(frame.minX,area.maxX-frame.width));frame.origin.y=max(area.minY,min(frame.minY,area.maxY-frame.height))}
        panel.setFrame(frame,display:true);panel.saveFrame(usingName:"LiveDesktopCard.Frame");update()
    }
    func setSize(_ value:String) {
        guard ["small","medium","large"].contains(value),value != size else{return}
        objectWillChange.send();prefs.set(value,forKey:"desktopCard.size");resize()
    }
    func setHidden(_ value:Bool) {
        guard value != hidden else{return}
        objectWillChange.send();prefs.set(value,forKey:"desktopCard.hidden")
        if value {panel?.orderOut(nil)} else {update();panel?.orderFrontRegardless()}
        changed?()
    }
    func setLocked(_ value:Bool) {
        guard value != locked else{return}
        objectWillChange.send();prefs.set(value,forKey:"desktopCard.locked");panel?.isMovable = !value
        if value {dragStart=nil;dragWindowStart=nil}
        update()
    }
    func setTop(_ value:Bool) {
        guard value != top else{return}
        objectWillChange.send();prefs.set(value,forKey:"desktopCard.top");updateLevel()
    }
    private func toggleLock() {setLocked(!locked)}
    private func updateLevel() {panel?.level=top ? .floating:NSWindow.Level(rawValue:Int(CGWindowLevelForKey(.desktopIconWindow))+1)}
    func center() {panel?.center();panel?.saveFrame(usingName:"LiveDesktopCard.Frame")}
}

private struct DesktopCardSettings:View {
    @ObservedObject var model:LiveDesktopCard
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Toggle("显示桌面卡片",isOn:Binding(get:{!model.hidden},set:{model.setHidden(!$0)}))
            Picker("卡片尺寸",selection:Binding(get:{model.size},set:{model.setSize($0)})) {
                Text("小号").tag("small");Text("中号").tag("medium");Text("大号").tag("large")
            }.pickerStyle(.segmented)
            Picker("卡片皮肤",selection:Binding(get:{model.skin},set:{model.setSkin($0)})) {
                Text("原生仪表").tag("native");Text("动画皮肤").tag("animated")
            }.pickerStyle(.segmented)
            if model.skin == "animated" {
                Picker("动画角色",selection:Binding(get:{model.character},set:{model.setCharacter($0)})) {
                    Text("小黄鸭").tag("duck");Text("白天鹅").tag("swan")
                }.pickerStyle(.segmented)
                Text("朋友生日当天切换完整生日造型；雷雨或台风时黄鸭变篮球、白天鹅变足球。").font(.caption).foregroundStyle(.secondary)
            }
            Toggle("锁定位置",isOn:Binding(get:{model.locked},set:{model.setLocked($0)}))
            Toggle("置于其他窗口上方",isOn:Binding(get:{model.top},set:{model.setTop($0)}))
            Button("移到屏幕中央") {model.center()}
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}
