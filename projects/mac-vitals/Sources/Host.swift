import AppKit
import SwiftUI
import WidgetKit
import ServiceManagement
final class VitalsPanel:NSPanel {
    var locked=false
    override var canBecomeKey:Bool{true}
    override func sendEvent(_ event:NSEvent){
        if event.type == .leftMouseDown,event.window === self {
            let p=event.locationInWindow
            if !(p.y>frame.height-48 && p.x>frame.width-95) {
                if !locked{performDrag(with:event);saveFrame(usingName:"VitalsFrame")};return
            }
        };super.sendEvent(event)
    }
}
@MainActor final class VitalsDelegate:NSObject,NSApplicationDelegate,NSMenuDelegate {
    let collector=Collector(),broker=VitalsBroker()
    var panel:VitalsPanel!,host:NSHostingView<VitalsCard>!,status:NSStatusItem!,timer:Timer?
    var size=UserDefaults.standard.string(forKey:"cardSize") ?? "medium"
    var hidden=UserDefaults.standard.bool(forKey:"cardHidden"),locked=UserDefaults.standard.bool(forKey:"locked"),top=UserDefaults.standard.bool(forKey:"top")
    var snapshot=Metrics()
    let statusPopover=StatusPopover()
    var dimensions:NSSize{switch size{case "small":return NSSize(width:180,height:180);case "large":return NSSize(width:350,height:450);default:return NSSize(width:350,height:285)}}
    func applicationDidFinishLaunching(_ notification:Notification){
        WidgetSelfRepair.shared.start()
        NSApp.setActivationPolicy(.accessory)
        status=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        panel=VitalsPanel(contentRect:NSRect(origin:.zero,size:dimensions),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.title="Mac 实时监测";panel.backgroundColor = .clear;panel.isOpaque=false;panel.hasShadow=true;panel.isReleasedWhenClosed=false;panel.hidesOnDeactivate=false
        panel.collectionBehavior=[.canJoinAllSpaces,.stationary,.fullScreenAuxiliary,.ignoresCycle]
        panel.locked=locked;panel.isMovable = !locked
        if !panel.setFrameUsingName("VitalsFrame"){panel.center()}
        host=NSHostingView(rootView:card());panel.contentView=host
        resize();updateLevel();makeMenu();updateStatus();if !hidden{panel.orderFrontRegardless()}
        collector.onUpdate={[weak self] m in guard let self else{return};self.snapshot=m;self.broker.value=m;if !self.hidden{self.host.rootView=self.card()};self.updateStatus()}
        broker.start();collector.start()
        timer=Timer.scheduledTimer(withTimeInterval:60,repeats:true){[weak self] _ in Task{@MainActor in self?.broker.start();WidgetCenter.shared.reloadTimelines(ofKind:Metrics.kind)}}
        WidgetCenter.shared.reloadTimelines(ofKind:Metrics.kind)
    }
    func card()->VitalsCard {VitalsCard(data:snapshot,size:size,locked:locked,onLock:{[weak self] in self?.toggleLock()},onMenu:{[weak self] in self?.popup()})}
    func makeMenu(){
        let m=NSMenu();m.delegate=self
        func add(_ t:String,_ a:Selector,_ on:Bool=false){let i=NSMenuItem(title:t,action:a,keyEquivalent:"");i.target=self;i.state=on ? .on:.off;m.addItem(i)}
        add("显示卡片",#selector(showCard),!hidden);add("隐藏卡片",#selector(hideCard),hidden)
        let sizes=NSMenuItem(title:"卡片尺寸",action:nil,keyEquivalent:"");sizes.submenu=NSMenu()
        for (id,title) in [("small","小号"),("medium","中号"),("large","大号")]{let i=NSMenuItem(title:title,action:#selector(selectSize(_:)),keyEquivalent:"");i.target=self;i.representedObject=id;i.state=size==id ? .on:.off;sizes.submenu?.addItem(i)};m.addItem(sizes)
        add(locked ? "解锁位置":"锁定位置",#selector(toggleLock),locked);add("置于其他窗口上方",#selector(toggleTop),top);add("卡片移到屏幕中央",#selector(centerCard))
        m.addItem(.separator());add("菜单栏显示、文字与配色…",#selector(customize));add("登录时启动",#selector(toggleLogin),SMAppService.mainApp.status == .enabled)
        m.addItem(.separator());add("数据说明…",#selector(about));add("退出 Mac 实时监测",#selector(quit));statusPopover.menu=m
        if status.button?.target !== statusPopover {
            statusPopover.attach(to:status,menu:m,size:NSSize(width:350,height:450),openTitle:"显示桌面卡片",
                open:{[weak self] in self?.showCard()},content:{[weak self] in
                    guard let self else{return AnyView(EmptyView())}
                    return AnyView(VitalsCard(data:self.snapshot,size:"large",locked:self.locked,onLock:{[weak self] in self?.toggleLock()},onMenu:{[weak self] in self?.statusPopover.showMenu()}))
                })
        }
    }
    func menuWillOpen(_ menu:NSMenu){menu.items.first{$0.action == #selector(hideCard)}?.state=hidden ? .on:.off;menu.items.first{$0.action == #selector(showCard)}?.state=hidden ? .off:.on}
    func popup(){let menu=statusPopover.menu;menu.popUp(positioning:nil,at:NSPoint(x:panel.frame.width-50,y:panel.frame.height-35),in:panel.contentView)}
    func fields()->[MenuField]{
        let ok=snapshot.fresh();let s=snapshot
        return [MenuField(id:"power",title:s.powerLabel,value:Metrics.value(ok ? s.power:nil," W",decimals:1),color:.systemGreen),MenuField(id:"cpu",title:"CPU 占用",value:"CPU "+Metrics.value(ok ? s.cpu:nil,"%"),color:.white),MenuField(id:"memory",title:"内存占用",value:"内存 "+Metrics.value(ok ? s.memoryPercent:nil,"%"),color:MenuCustomization.color("#B296FF")),MenuField(id:"temp",title:"CPU 温度",value:Metrics.value(ok ? s.cpuTemp:nil," °C",decimals:1),color:.cyan,defaultVisible:false),MenuField(id:"download",title:"下载速度",value:"↓ "+Metrics.rate(ok ? s.download:nil),color:.cyan,defaultVisible:false),MenuField(id:"upload",title:"上传速度",value:"↑ "+Metrics.rate(ok ? s.upload:nil),color:MenuCustomization.color("#B296FF"),defaultVisible:false),MenuField(id:"chip",title:"芯片名称",value:s.chip,defaultVisible:false)]
    }
    var menuIcon:NSImage?{NSImage(systemSymbolName:"desktopcomputer",accessibilityDescription:"Mac 实时监测")?.withSymbolConfiguration(.init(paletteColors:[MenuCustomization.color("#66FFAD")]))}
    func updateStatus(){statusPopover.update();guard let b=status.button else{return};let prefs=MenuCustomization.load();if prefs.enabled{MenuCustomizationPanel.apply(b,fields:fields(),icon:menuIcon)}else{let img=prefs.render(fields:fields(),fallback:menuIcon);if b.image?.tiffRepresentation != img.tiffRepresentation{b.image=img};b.title="";b.imagePosition = .imageOnly};b.toolTip="Mac 实时监测 · "+(snapshot.fresh() ? snapshot.powerLabel:"等待采集")}
    @objc func customize(){MenuCustomizationPanel.shared.show(title:"Mac 实时监测",fields:fields(),icon:menuIcon){[weak self] in self?.updateStatus()}}
    @objc func showCard(){hidden=false;UserDefaults.standard.set(false,forKey:"cardHidden");host.rootView=card();panel.orderFrontRegardless();makeMenu()}
    @objc func hideCard(){if hidden{showCard();return};hidden=true;UserDefaults.standard.set(true,forKey:"cardHidden");panel.orderOut(nil);makeMenu()}
    @objc func toggleLock(){locked.toggle();UserDefaults.standard.set(locked,forKey:"locked");panel.locked=locked;panel.isMovable = !locked;host.rootView=card();makeMenu()}
    @objc func toggleTop(){top.toggle();UserDefaults.standard.set(top,forKey:"top");updateLevel();makeMenu()}
    func updateLevel(){panel.level=top ? .floating:NSWindow.Level(rawValue:Int(CGWindowLevelForKey(.desktopIconWindow))+1)}
    @objc func centerCard(){panel.center();panel.saveFrame(usingName:"VitalsFrame");showCard()}
    @objc func selectSize(_ i:NSMenuItem){size=i.representedObject as? String ?? "medium";UserDefaults.standard.set(size,forKey:"cardSize");resize();makeMenu()}
    func resize(){var r=panel.frame;r.origin.y=r.maxY-dimensions.height;r.size=dimensions;if let area=panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame{r.origin.x=max(area.minX,min(r.minX,area.maxX-r.width));r.origin.y=max(area.minY,min(r.minY,area.maxY-r.height))};panel.setFrame(r,display:true);host.rootView=card();panel.saveFrame(usingName:"VitalsFrame")}
    @objc func toggleLogin(){do{if SMAppService.mainApp.status == .enabled{try SMAppService.mainApp.unregister()}else{try SMAppService.mainApp.register()};makeMenu();if SMAppService.mainApp.status == .requiresApproval{SMAppService.openSystemSettingsLoginItems()}}catch{let a=NSAlert();a.messageText="登录启动未设置成功";a.informativeText=error.localizedDescription;a.runModal()}}
    @objc func about(){let a=NSAlert();a.messageText="Mac 实时监测";a.informativeText="系统功率为 SMC 传感器估算，不含外接显示器，也不是插座实测。不可用时显示芯片功率。CPU 为活跃时间占比；网速合计活跃物理网卡，避免 VPN 重复计数。\n\n菜单栏与卡片每秒更新，小组件请求每分钟更新，由 macOS 调度。\n\n采集器：macmon v0.10.0（MIT）\nhttps://github.com/vladkens/macmon";a.runModal()}
    @objc func quit(){NSApp.terminate(nil)}
    func application(_ application:NSApplication,open urls:[URL]){showCard()}
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool{showCard();return false}
    func applicationWillTerminate(_ notification:Notification){collector.stop();broker.stop();timer?.invalidate();panel.saveFrame(usingName:"VitalsFrame")}
}
@main enum VitalsMain {static func main(){let app=NSApplication.shared;let d=VitalsDelegate();app.delegate=d;withExtendedLifetime(d){app.run()}}}
