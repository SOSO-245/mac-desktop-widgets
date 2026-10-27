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
    private weak var settingsMenu:NSMenu?
    var changed:(()->Void)?
    var weatherSettings:(()->Void)?
    var weatherLayout:Bool {prefs.string(forKey:"desktopCard.mediumLayout") != "calendar"}
    private let prefs=UserDefaults.standard
    var size:String {prefs.string(forKey:"desktopCard.size") ?? "medium"}
    var locked:Bool {prefs.bool(forKey:"desktopCard.locked")}
    var hidden:Bool {prefs.bool(forKey:"desktopCard.hidden")}
    var top:Bool {prefs.bool(forKey:"desktopCard.top")}
    var visible:Bool {panel?.isVisible == true}
    private var dimensions:NSSize {NSSize(width:size=="small" ? 164:344,height:size=="large" ? 344:164)}
    func start(title:String,menu:NSMenu,refresh:@escaping()->Void,content:@escaping(String,Bool,AnyView)->AnyView) {
        self.content=content;self.refresh=refresh;settingsMenu=menu
        let p=LiveCardPanel(contentRect:NSRect(origin:.zero,size:dimensions),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        p.title=title+" · 桌面卡片";p.identifier=NSUserInterfaceItemIdentifier("LiveDesktopCard")
        p.isMovable = !locked;p.isMovableByWindowBackground=true;p.setFrameAutosaveName("LiveDesktopCard.Frame");p.backgroundColor = .clear;p.isOpaque=false;p.hasShadow=true;p.isReleasedWhenClosed=false;p.hidesOnDeactivate=false
        p.collectionBehavior=[.canJoinAllSpaces,.stationary,.fullScreenAuxiliary,.ignoresCycle]
        if !p.setFrameUsingName("LiveDesktopCard.Frame") {p.center()}
        panel=p;let h=LiveCardHostingView(rootView:AnyView(EmptyView()));p.contentView=h;host=h
        let visibility=NSMenuItem(title:"",action:#selector(toggleVisible),keyEquivalent:"");visibility.target=self;visibility.identifier=NSUserInterfaceItemIdentifier("live-desktop-visibility");menu.insertItem(visibility,at:0)
        resize();updateLevel();refreshMenu()
        if !hidden {p.orderFrontRegardless()}
    }
    private func refreshMenu() {
        guard let item=settingsMenu?.items.first(where:{$0.identifier?.rawValue=="live-desktop-visibility"}) else{return}
        item.title=hidden ? "显示桌面卡片":"隐藏桌面卡片"
    }
    func update() {
        guard dragStart == nil,let content,let host else {return}
        let controls=AnyView(HStack(spacing:6) {
            Button(action:{[weak self] in self?.refresh?()}) {Image(systemName:"arrow.clockwise")}.help("立即刷新")
            Button(action:{[weak self] in self?.toggleLock()}) {Image(systemName:locked ? "lock.fill":"lock.open")}.foregroundStyle(locked ? Color.cyan:Color.mint).help(locked ? "解锁位置":"锁定位置")
        }.font(.system(size:10)).buttonStyle(.plain).focusEffectDisabled())
        host.rootView=AnyView(DesktopCardSurface(original:content(size,false,controls),plain:content(size,true,controls)).clipShape(RoundedRectangle(cornerRadius:28)).containerShape(RoundedRectangle(cornerRadius:28)).environment(\.colorScheme,.dark)
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
    func setLayout(_ value:String) {
        guard ["weather","calendar"].contains(value) else{return}
        guard prefs.string(forKey:"desktopCard.mediumLayout") != value || size != "medium" else{return}
        objectWillChange.send();prefs.set(value,forKey:"desktopCard.mediumLayout");prefs.set("medium",forKey:"desktopCard.size");resize();refreshMenu()
    }
    func setSize(_ value:String) {
        guard ["small","medium","large"].contains(value),size != value else{return}
        objectWillChange.send();prefs.set(value,forKey:"desktopCard.size");resize();refreshMenu()
    }
    func setVisible(_ visible:Bool) {
        guard visible == hidden else{return}
        objectWillChange.send();prefs.set(!visible,forKey:"desktopCard.hidden")
        if visible {update();panel?.orderFrontRegardless()} else {panel?.orderOut(nil)}
        refreshMenu();changed?()
    }
    func setLocked(_ value:Bool) {
        guard locked != value else{return}
        objectWillChange.send();prefs.set(value,forKey:"desktopCard.locked");panel?.isMovable = !locked;update();refreshMenu()
    }
    func setTop(_ value:Bool) {
        guard top != value else{return}
        objectWillChange.send();prefs.set(value,forKey:"desktopCard.top");updateLevel();refreshMenu()
    }
    @objc private func toggleVisible() {setVisible(hidden)}
    @objc private func toggleLock() {setLocked(!locked)}
    private func updateLevel() {panel?.level=top ? .floating:NSWindow.Level(rawValue:Int(CGWindowLevelForKey(.desktopIconWindow))+1)}
    func centerCard() {panel?.center();panel?.saveFrame(usingName:"LiveDesktopCard.Frame")}
    private func showMenu() {AppSettingsController.shared.show("desktop")}
}
