import AppKit
import SwiftUI

private final class MenuCardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// A single borderless card anchored to the status item, sharing the host's data.
@MainActor final class StatusPopover: NSObject {
    var menu = NSMenu() { didSet { if let item { AppUpdater.shared.attach(to:item,menu:menu) } } }
    private weak var item: NSStatusItem?
    private var panel: MenuCardPanel?
    private var host: NSHostingView<AnyView>?
    private var content: (() -> AnyView)?
    var visibilityChanged: (() -> Void)?
    private var cardSize = NSSize(width:344,height:344)
    private var localMonitor: Any?
    private var outsideMonitor: Any?
    private var workspaceObserver: Any?
    var isShown: Bool { panel?.isVisible == true }

    func attach(to item:NSStatusItem, menu:NSMenu, size:NSSize, openTitle:String,
                open:@escaping () -> Void, content:@escaping () -> AnyView) {
        self.item=item;self.menu=menu;
        AppUpdater.shared.beforeShowingUpdate = { [weak self] in self?.close() };self.cardSize=size;self.content=content
        item.menu=nil
        item.button?.target=self;item.button?.action=#selector(clicked(_:))
        item.button?.sendAction(on:[.leftMouseUp,.rightMouseUp])
        item.button?.setAccessibilityHelp("点击展开卡片，再点收起；右键打开设置菜单")
    }
    @objc private func clicked(_ sender:Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {showMenu();return}
        if isShown {close();return}
        guard let button=item?.button,let anchor=button.window else{return}
        let screen=anchor.screen ?? NSScreen.main
        let area=screen?.visibleFrame ?? NSRect(x:0,y:0,width:1280,height:800)
        let height=min(cardSize.height,max(180,area.height-16))
        let buttonRect=anchor.convertToScreen(button.convert(button.bounds,to:nil))
        let x=max(area.minX+8,min(buttonRect.midX-cardSize.width/2,area.maxX-cardSize.width-8))
        let y=max(area.minY+8,buttonRect.minY-height-8)
        if panel == nil {
            let p=MenuCardPanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            p.title="菜单栏卡片";p.identifier=NSUserInterfaceItemIdentifier("StatusCardPreview")
            p.backgroundColor = .clear;p.isOpaque=false;p.hasShadow=true;p.isReleasedWhenClosed=false
            p.hidesOnDeactivate=false;p.isMovable=false;p.level = .popUpMenu
            p.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.transient,.ignoresCycle]
            p.appearance=NSAppearance(named:.darkAqua)
            let h=NSHostingView(rootView:AnyView(EmptyView()));p.contentView=h;panel=p;host=h
        }
        panel?.setFrame(NSRect(x:x,y:y,width:cardSize.width,height:height),display:false)
        render();panel?.makeKeyAndOrderFront(nil)
        installDismissal();visibilityChanged?();update()
    }
    func close() {
        guard isShown else{return}
        panel?.orderOut(nil)
        if let localMonitor{NSEvent.removeMonitor(localMonitor)};localMonitor=nil
        if let outsideMonitor{NSEvent.removeMonitor(outsideMonitor)};outsideMonitor=nil
        if let workspaceObserver{NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)};workspaceObserver=nil
        visibilityChanged?()
    }
    func update() {if isShown{render()}}
    private func render() {
        guard let content,let panel else{return}
        let card=content().frame(width:cardSize.width,height:cardSize.height).preferredColorScheme(.dark)
        if panel.frame.height < cardSize.height {
            host?.rootView=AnyView(ScrollView(.vertical){card}.scrollIndicators(.hidden).frame(width:cardSize.width,height:panel.frame.height))
        } else {host?.rootView=AnyView(card)}
    }
    private func installDismissal() {
        // Observe click location only while open; do not log or store events.
        localMonitor=NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown,.keyDown]) { [weak self] event in
            guard let self else{return event}
            if event.type == .keyDown {
                if event.keyCode == 53 {self.close();return nil}
            } else if event.window !== self.panel && event.window !== self.item?.button?.window {self.close()}
            return event
        }
        outsideMonitor=NSEvent.addGlobalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown]) { [weak self] _ in
            Task {@MainActor in self?.close()}
        }
        workspaceObserver=NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.activeSpaceDidChangeNotification,object:nil,queue:.main) {[weak self] _ in
            Task {@MainActor in self?.close()}
        }
    }
    func showMenu() {
        close();guard let button=item?.button else{return}
        menu.popUp(positioning:nil,at:NSPoint(x:0,y:button.bounds.minY),in:button)
    }
}
