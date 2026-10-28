import AppKit
import SwiftUI
import WidgetKit
import ServiceManagement
final class VitalsPanel:NSPanel,DuckWaterWindow {
    var locked=false
    var duckWaterRegion:NSRect?
    override var canBecomeKey:Bool{true}
    override func sendEvent(_ event:NSEvent){
        if event.type == .leftMouseDown,event.window === self {
            let p=event.locationInWindow
            if duckWaterRegion?.contains(p) == true {super.sendEvent(event);return}
            if !(p.y>frame.height-48 && p.x>frame.width-95) {
                if !locked{performDrag(with:event);saveFrame(usingName:"VitalsFrame")};return
            }
        };super.sendEvent(event)
    }
}
@MainActor final class VitalsDelegate:NSObject,NSApplicationDelegate,NSMenuDelegate,ObservableObject {
    let collector=Collector(),broker=VitalsBroker()
    var panel:VitalsPanel!,host:NSHostingView<AnyView>!,status:NSStatusItem!,timer:Timer?
    @Published var size=UserDefaults.standard.string(forKey:"cardSize") ?? "medium"
    @Published var hidden=UserDefaults.standard.bool(forKey:"cardHidden")
    @Published var locked=UserDefaults.standard.bool(forKey:"locked")
    @Published var top=UserDefaults.standard.bool(forKey:"top")
    @Published var loginEnabled=SMAppService.mainApp.status == .enabled
    @Published var loginNote=""
    @Published var skin=VitalsSkin(rawValue:UserDefaults.standard.string(forKey:"desktopSkin") ?? "classic") ?? .classic
    let duckWeather=DuckWeatherStore()
    var snapshot=Metrics()
    let statusPopover=StatusPopover()
    var dimensions:NSSize{switch size{case "small":return NSSize(width:skin.smallWidth,height:164);case "large":return NSSize(width:344,height:344);default:return NSSize(width:344,height:164)}}
    func applicationDidFinishLaunching(_ notification:Notification){
        WidgetSelfRepair.shared.start()
        NSApp.setActivationPolicy(.accessory)
        status=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        panel=VitalsPanel(contentRect:NSRect(origin:.zero,size:dimensions),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.title="Mac 实时监测";panel.identifier=NSUserInterfaceItemIdentifier("MacVitalsCard");panel.backgroundColor = .clear;panel.isOpaque=false;panel.hasShadow=true;panel.isReleasedWhenClosed=false;panel.hidesOnDeactivate=false
        panel.collectionBehavior=[.canJoinAllSpaces,.stationary,.fullScreenAuxiliary,.ignoresCycle]
        panel.locked=locked;panel.isMovable = !locked
        if !panel.setFrameUsingName("VitalsFrame"){panel.center()}
        host=NSHostingView(rootView:desktopCard());panel.contentView=host
        configureSettings();resize();updateLevel();makeMenu();updateStatus();if !hidden{panel.orderFrontRegardless()}
        duckWeather.onUpdate={[weak self] in guard let self,self.skin == .duck,!self.hidden else{return};self.host.rootView=self.desktopCard()}
        collector.onUpdate={[weak self] m in guard let self else{return};self.snapshot=m;self.broker.value=m;if self.skin == .duck{self.duckWeather.refresh()};if !self.hidden{self.host.rootView=self.desktopCard()};self.updateStatus()}
        broker.start();collector.start()
        timer=Timer.scheduledTimer(withTimeInterval:60,repeats:true){[weak self] _ in Task{@MainActor in self?.broker.start();WidgetCenter.shared.reloadTimelines(ofKind:Metrics.kind)}}
        WidgetCenter.shared.reloadTimelines(ofKind:Metrics.kind)
    }
    func card()->VitalsCard {VitalsCard(data:snapshot,size:size,locked:locked,onLock:{[weak self] in self?.toggleLock()},onMenu:{[weak self] in self?.popup()})}
    func desktopCard()->AnyView {
        if skin == .duck {
            let original=VitalsDuckCard(data:snapshot,weather:duckWeather.weather,timezone:duckWeather.timezone,size:size,locked:locked,onLock:{[weak self] in self?.toggleLock()})
            var plain=original;plain.menuSurface=true
            return AnyView(DesktopCardSurface(original:original,plain:plain))
        }
        let original=card();var plain=original;plain.menuSurface=true
        return AnyView(DesktopCardSurface(original:original,plain:plain))
    }
    func setSkin(_ value:VitalsSkin){
        guard skin != value else{return};skin=value;UserDefaults.standard.set(value.rawValue,forKey:"desktopSkin")
        panel.duckWaterRegion=nil
        if value == .duck {duckWeather.refresh()}else{try? FileManager.default.removeItem(at:GridPreferences.folder.appendingPathComponent("status/mac-water.json"))}
        resize();ToolboxBridge.shared.publish()
    }
    func makeMenu(){
        let m=NSMenu();m.delegate=self
        func add(_ t:String,_ a:Selector,_ on:Bool=false){let i=NSMenuItem(title:t,action:a,keyEquivalent:"");i.target=self;i.state=on ? .on:.off;m.addItem(i)}
        add("显示卡片",#selector(showCard),!hidden);add("隐藏卡片",#selector(hideCard),hidden)
        m.addItem(.separator());AppSettingsController.shared.installMenuItem(in:m)
        add("退出 Mac 实时监测",#selector(quit));statusPopover.menu=m
        if status.button?.target !== statusPopover {
            statusPopover.attach(to:status,menu:m,size:NSSize(width:344,height:344),openTitle:"显示桌面卡片",
                open:{[weak self] in self?.showCard()},desktopOptions:true,content:{[weak self] native in
                    guard let self else{return AnyView(EmptyView())}
                    return AnyView(VitalsCard(menuSurface:native,data:self.snapshot,size:"large",locked:self.locked,onLock:{[weak self] in self?.toggleLock()},onMenu:{AppSettingsController.shared.show("desktop")}))
                })
        }
    }
    func menuWillOpen(_ menu:NSMenu){menu.items.first{$0.action == #selector(hideCard)}?.state=hidden ? .on:.off;menu.items.first{$0.action == #selector(showCard)}?.state=hidden ? .off:.on}
    func popup(){AppSettingsController.shared.show("desktop")}
    func fields()->[MenuField]{
        let ok=snapshot.fresh();let s=snapshot
        return [MenuField(id:"power",title:s.powerLabel,value:Metrics.value(ok ? s.power:nil," W",decimals:1),color:.systemGreen),MenuField(id:"cpu",title:"CPU 占用",value:"CPU "+Metrics.value(ok ? s.cpu:nil,"%"),color:.white),MenuField(id:"memory",title:"内存占用",value:"内存 "+Metrics.value(ok ? s.memoryPercent:nil,"%"),color:MenuCustomization.color("#B296FF")),MenuField(id:"temp",title:"CPU 温度",value:Metrics.value(ok ? s.cpuTemp:nil," °C",decimals:1),color:.cyan,defaultVisible:false),MenuField(id:"download",title:"下载速度",value:"↓ "+Metrics.rate(ok ? s.download:nil),color:.cyan,defaultVisible:false),MenuField(id:"upload",title:"上传速度",value:"↑ "+Metrics.rate(ok ? s.upload:nil),color:MenuCustomization.color("#B296FF"),defaultVisible:false),MenuField(id:"fan",title:"风扇转速",value:ok ? s.fanText:"—",color:.cyan,defaultVisible:false),MenuField(id:"chip",title:"芯片名称",value:s.chip,defaultVisible:false)]
    }
    var menuIcon:NSImage?{NSImage(systemSymbolName:"desktopcomputer",accessibilityDescription:"Mac 实时监测")?.withSymbolConfiguration(.init(paletteColors:[MenuCustomization.color("#66FFAD")]))}
    func updateStatus(){statusPopover.update();guard let b=status.button else{return};let prefs=MenuCustomization.load();if prefs.enabled{MenuCustomizationPanel.apply(b,fields:fields(),icon:menuIcon)}else{let img=prefs.render(fields:fields(),fallback:menuIcon);if b.image?.tiffRepresentation != img.tiffRepresentation{b.image=img};b.title="";b.imagePosition = .imageOnly};b.toolTip="Mac 实时监测 · "+(snapshot.fresh() ? snapshot.powerLabel:"等待采集")}
    func configureSettings() {
        ToolboxBridge.shared.start(show:{[weak self] visible in self?.setCardVisible(visible)},size:{[weak self] value in self?.setCardSize(value)},smallWidth:{[weak self] in self?.skin.smallWidth ?? 220})
        AppSettingsController.shared.configure(title:"Mac 实时监测",pages:[
            AppSettingsPage(id:"toolbox",title:"桌面排列",symbol:"square.grid.2x2") {AnyView(ToolboxSettingsLink())},
            AppSettingsPage(id:"general",title:"通用",symbol:"gearshape") {[weak self] in guard let self else{return AnyView(EmptyView())};return AnyView(VitalsGeneralSettings(app:self))},
            AppSettingsPage(id:"desktop",title:"桌面卡片",symbol:"rectangle.on.rectangle") {[weak self] in guard let self else{return AnyView(EmptyView())};return AnyView(VitalsDesktopSettings(app:self))},
            AppSettingsPage(id:"menubar",title:"菜单栏",symbol:"menubar.rectangle") {[weak self] in
                guard let self else{return AnyView(EmptyView())}
                return AnyView(VStack(alignment:.leading,spacing:22) {
                    self.statusPopover.settingsContent
                    Divider()
                    MenuCustomizationView(fields:self.fields(),fallback:self.menuIcon,extraColors:[],onSave:{[weak self] in self?.updateStatus()})
                })
            },
            AppSettingsPage(id:"data",title:"数据与采集",symbol:"chart.xyaxis.line") {AnyView(VitalsDataSettings())},
            AppSettingsPage(id:"updates",title:"软件更新",symbol:"arrow.down.circle") {AppUpdater.shared.settingsContent}
        ],beforeShow:{[weak self] in self?.statusPopover.close();self?.refreshLogin()})
    }
    @objc func customize(){AppSettingsController.shared.show("menubar")}
    func setCardVisible(_ visible:Bool){guard visible == hidden else{return};if visible{showCard()}else{hideCard()}}
    @objc func showCard(){hidden=false;UserDefaults.standard.set(false,forKey:"cardHidden");host.rootView=desktopCard();panel.orderFrontRegardless();makeMenu()}
    @objc func hideCard(){guard !hidden else{return};hidden=true;UserDefaults.standard.set(true,forKey:"cardHidden");panel.orderOut(nil);makeMenu()}
    func setCardLocked(_ value:Bool){guard locked != value else{return};locked=value;UserDefaults.standard.set(locked,forKey:"locked");panel.locked=locked;panel.isMovable = !locked;host.rootView=desktopCard();makeMenu()}
    @objc func toggleLock(){setCardLocked(!locked)}
    func setCardTop(_ value:Bool){guard top != value else{return};top=value;UserDefaults.standard.set(top,forKey:"top");updateLevel();makeMenu()}
    @objc func toggleTop(){setCardTop(!top)}
    func updateLevel(){panel.level=top ? .floating:NSWindow.Level(rawValue:Int(CGWindowLevelForKey(.desktopIconWindow))+1)}
    @objc func centerCard(){panel.center();panel.saveFrame(usingName:"VitalsFrame");showCard()}
    func setCardSize(_ value:String){guard ["small","medium","large"].contains(value),size != value else{return};size=value;UserDefaults.standard.set(size,forKey:"cardSize");resize();makeMenu()}
    @objc func selectSize(_ i:NSMenuItem){if let value=i.representedObject as? String{setCardSize(value)}}
    func resize(){var r=panel.frame;r.origin.y=r.maxY-dimensions.height;r.size=dimensions;if let area=panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame{r.origin.x=max(area.minX,min(r.minX,area.maxX-r.width));r.origin.y=max(area.minY,min(r.minY,area.maxY-r.height))};panel.setFrame(r,display:true);host.rootView=desktopCard();panel.saveFrame(usingName:"VitalsFrame")}
    func refreshLogin(){loginEnabled=SMAppService.mainApp.status == .enabled;loginNote=SMAppService.mainApp.status == .requiresApproval ? "请在系统设置的登录项中允许 Mac 实时监测。":""}
    func setLogin(_ value:Bool){
        do {
            if value {try SMAppService.mainApp.register()} else {try SMAppService.mainApp.unregister()}
            refreshLogin()
            if SMAppService.mainApp.status == .requiresApproval {SMAppService.openSystemSettingsLoginItems()}
        } catch {refreshLogin();loginNote="登录启动未设置成功："+error.localizedDescription}
    }
    @objc func toggleLogin(){setLogin(!loginEnabled)}
    @objc func about(){AppSettingsController.shared.show("data")}
    @objc func quit(){NSApp.terminate(nil)}
    func application(_ application:NSApplication,open urls:[URL]){showCard()}
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool{showCard();return false}
    func applicationWillTerminate(_ notification:Notification){collector.stop();broker.stop();timer?.invalidate();panel.saveFrame(usingName:"VitalsFrame")}
}
@main enum VitalsMain {static func main(){let app=NSApplication.shared;let d=VitalsDelegate();app.delegate=d;withExtendedLifetime(d){app.run()}}}
