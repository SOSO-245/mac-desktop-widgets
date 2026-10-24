import AppKit
import SwiftUI
import WidgetKit
import Combine
import ServiceManagement

@MainActor final class CalendarModel:ObservableObject {
    @Published var selected=Almanac.clamp(Date())
    @Published var holidays=HolidayStore.cached()
    @Published var busy=false
    @Published var data=CalendarDataStore.load()
    @Published var storageNote=""
    @Published var showBirthdayEditor=false
    @Published var showSettings=false
    @Published var showScheduleEditor=false
    @Published var showAgenda=false
    var editingBirthday:Birthday?
    func addBirthday(_ birthday:Birthday)->Bool {
        var next=data
        next.birthdays.removeAll {$0.id==birthday.id || (birthday.contactID != nil && $0.contactID==birthday.contactID)}
        next.birthdays.append(birthday);return apply(next)
    }
    func addSchedule(_ item:ScheduleItem)->Bool {var next=data;next.schedules.append(item);return apply(next)}
    func removeSchedule(_ id:UUID) {var next=data;next.schedules.removeAll{$0.id==id};_=apply(next)}
    var selectedSchedules:[ScheduleItem] {data.schedules.filter{$0.occurs(on:selected)}.sorted{$0.start<$1.start}}
    func removeBirthday(_ id:UUID) {var next=data;next.birthdays.removeAll{$0.id==id};_=apply(next)}
    func apply(_ next:CalendarUserData)->Bool {
        do {try CalendarDataStore.save(next);data=next;storageNote=""
            do {try CalendarDataStore.mirror(next)} catch {storageNote="已保存，桌面组件等待同步"}
            WidgetCenter.shared.reloadTimelines(ofKind:calendarWidgetKind);return true}
        catch {storageNote="设置未完整保存或组件尚未同步，请重试。";return false}
    }
    func beginBirthday(_ existing:Birthday?=nil) {editingBirthday=existing;showBirthdayEditor=true}
    @Published var autoStart=SMAppService.mainApp.status == .enabled
    @Published var startupNote=""
    func setAutoStart(_ enabled:Bool) {
        do {
            if enabled {try SMAppService.mainApp.register()} else {try SMAppService.mainApp.unregister()}
            autoStart=SMAppService.mainApp.status == .enabled
            UserDefaults.standard.set(true,forKey:"autoStartConfigured")
            startupNote=SMAppService.mainApp.status == .requiresApproval ? "请在系统设置的登录项中允许万年历" : ""
        } catch {startupNote="开机启动未设置成功";autoStart=SMAppService.mainApp.status == .enabled}
    }
    var followsToday=true
    private var browsingDeadline:Date?
    private var browsingTimer:Timer?
    func recordInteraction() {
        guard !followsToday else {return}
        browsingDeadline=Date().addingTimeInterval(60)
        browsingTimer?.invalidate()
        let timer=Timer(fire:browsingDeadline!,interval:0,repeats:false) {[weak self] _ in Task {@MainActor in self?.returnIfIdle()}}
        browsingTimer=timer;RunLoop.main.add(timer,forMode:.common)
    }
    func returnIfIdle() {
        if !followsToday,let deadline=browsingDeadline,Date()>=deadline {select("today")}
    }
    func select(_ key:String) {
        if key=="today" {followsToday=true;browsingTimer?.invalidate();browsingDeadline=nil;selected=Almanac.clamp(Date())}
        else if let d=Almanac.date(key) {followsToday=false;selected=Almanac.clamp(d);recordInteraction()}
    }
    func update(force:Bool=false) async {
        guard !busy else {return};busy=true
        let requestedYear=Almanac.year(selected)
        holidays=await HolidayStore.shared.load(year:requestedYear,force:force)
        busy=false
        if Almanac.year(selected) != requestedYear {await update()}
    }
}
struct CalendarWindow:View {
    @ObservedObject var model:CalendarModel
    @State private var showHelp=false
    let tick=Timer.publish(every:60,on:.main,in:.common).autoconnect()
    var selected:Date {model.selected}
    var body:some View {
        VStack(spacing:22) {
            HStack {
                Image(systemName:"moonphase.waxing.crescent").font(.system(size:22)).foregroundStyle(jade)
                VStack(alignment:.leading,spacing:4) {Text("万年历").font(.system(size:24,weight:.semibold));Text("把日子，看得更清楚").foregroundStyle(muted).font(.system(size:12))}
                Spacer()
                Button {model.select("today")} label:{Label("回到今天",systemImage:"arrow.uturn.backward")}
                Button {Task {await model.update(force:true)}} label:{Label(model.busy ? "更新中" : "更新假期",systemImage:"arrow.clockwise")}.disabled(model.busy)
                Button {model.showSettings=true} label:{Image(systemName:"slider.horizontal.3")}.help("显示与外观")
                Button {showHelp.toggle()} label:{Image(systemName:"info.circle")}.help("添加组件与数据来源")
            }.buttonStyle(.borderless)
            HStack(alignment:.top,spacing:28) {
                VStack(alignment:.leading,spacing:12) {
                    Text(Almanac.weekday(selected)).font(.system(size:16)).foregroundStyle(muted)
                    Text("\(Almanac.day(selected))").font(.system(size:108,weight:.semibold,design:.rounded)).monospacedDigit()
                    Text(Almanac.lunar(selected)).font(.system(size:25,weight:.semibold)).foregroundStyle(jade)
                    Text(Almanac.zodiac(selected)).font(.system(size:13)).foregroundStyle(muted)
                    if Almanac.festival(selected) != nil {annotatedDateText(selected,short:false).font(.system(size:16,weight:.medium)).foregroundStyle(holidayPink)}
                    Divider().overlay(.white.opacity(0.15)).padding(.vertical,8)
                    Text(model.holidays.status(selected)).font(.system(size:16,weight:.semibold)).foregroundStyle(model.holidays.day(selected)?.isOffDay == true ? holidayGreen : model.holidays.day(selected)?.isOffDay == false ? workRed : jade)
                    Text(Almanac.key(selected)).font(.system(size:13)).foregroundStyle(muted)
                    HStack(spacing:14) {
                        Button {model.beginBirthday()} label:{Label("生日",systemImage:"gift")}
                        Button {model.showScheduleEditor=true} label:{Label("日程",systemImage:"calendar.badge.plus")}
                    }.buttonStyle(.borderless).foregroundStyle(jade)
                    if !model.selectedSchedules.isEmpty {
                        Button {model.showAgenda=true} label:{Label("当天日程（\(model.selectedSchedules.count)）",systemImage:"list.bullet")}.buttonStyle(.borderless).foregroundStyle(jade)
                    }
                    ForEach(model.data.birthdays.filter{$0.occurs(on:selected)}.prefix(3)) {birthday in Button {model.beginBirthday(birthday)} label:{Label(birthday.name+"生日",systemImage:"gift.fill")}.buttonStyle(.borderless).foregroundStyle(jade)}
                    Spacer(minLength:0)
                }.frame(width:210,alignment:.leading)
                VStack(spacing:20) {
                    HStack {
                        Button {model.select(Almanac.key(Almanac.moved(selected,months:-1)))} label:{Image(systemName:"chevron.left").frame(width:26,height:28)}.accessibilityLabel("上个月")
                        Spacer()
                        MonthYearButton(selected:selected,action:model.select)
                        Spacer()
                        Button {model.select(Almanac.key(Almanac.moved(selected,months:1)))} label:{Image(systemName:"chevron.right").frame(width:26,height:28)}.accessibilityLabel("下个月")
                    }.buttonStyle(.plain).foregroundStyle(jade)
                    MonthGrid(selected:selected,now:Date(),holidays:model.holidays,spacious:true,action:model.select)
                        .padding(12).background(.white.opacity(0.055),in:RoundedRectangle(cornerRadius:16))
                        .overlay(RoundedRectangle(cornerRadius:16).strokeBorder(.white.opacity(0.09),lineWidth:0.5))
                    HStack {Circle().fill(holidayGreen).frame(width:5,height:5);Text("放假（含调休）").foregroundStyle(muted);Circle().fill(workRed).frame(width:5,height:5);Text("补班").foregroundStyle(muted);Spacer();Text("点选日期查看").foregroundStyle(muted)}.font(.system(size:11))
                }.frame(maxWidth:.infinity)
            }
            Spacer(minLength:0)
            HStack {
                Circle().fill(jade).frame(width:5,height:5)
                Text(model.holidays.note).font(.system(size:11)).foregroundStyle(muted)
                Spacer()
                Text("中国大陆 · 全国安排").font(.system(size:11)).foregroundStyle(muted)
            }
            if showHelp {
                VStack(alignment:.leading,spacing:7) {
                    Toggle("登录时自动启动",isOn:Binding(get:{model.autoStart},set:{model.setAutoStart($0)}))
                    if !model.startupNote.isEmpty {Text(model.startupNote)}
                    Text("添加到桌面：右键桌面 → 编辑小组件 → 搜索“万年历” → 选择小 / 中 / 大。")
                    Text("组件内可翻日、翻月、选择日期；点击主体打开完整日历。回到今天后自动跟随当天。")
                    Text("假期数据来自 holiday-cn，按国务院通知整理，每天检查更新。未收录年份不推算调休；普通周末与法定假日分开显示。")
                    Link("查看节假日数据来源",destination:URL(string:"https://github.com/NateScarlet/holiday-cn")!)
                }.font(.system(size:11)).foregroundStyle(muted).frame(maxWidth:.infinity,alignment:.leading)
            }
        }
        .padding(30).frame(minWidth:800,minHeight:560)
        .background(CalendarBackground()).foregroundStyle(.white).preferredColorScheme(.dark)
        .environment(\.locale,Locale(identifier:"zh_CN"))
        .environment(\.calendarData,model.data)
        .sheet(isPresented:$model.showBirthdayEditor) {BirthdayEditor(model:model,existing:model.editingBirthday)}
        .sheet(isPresented:$model.showSettings) {DisplaySettings(model:model)}
        .sheet(isPresented:$model.showScheduleEditor) {ScheduleEditor(model:model)}
        .sheet(isPresented:$model.showAgenda) {AgendaSheet(model:model)}
        .task(id:Almanac.year(selected)) {await model.update()}
        .onReceive(tick) { _ in
            if model.followsToday {model.selected=Almanac.clamp(Date())}
            Task {await model.update()}
        }
    }
}
struct MonthChooser:View {
    let selected:Date
    var action:(String)->Void
    var close:()->Void
    @State private var yearText:String
    @State private var invalidYear=false
    init(selected:Date,action:@escaping(String)->Void,close:@escaping()->Void) {
        self.selected=selected;self.action=action;self.close=close
        _yearText=State(initialValue:String(Almanac.year(selected)))
    }
    var year:Int? {guard let y=Int(yearText),(1901...2099).contains(y) else {return nil};return y}
    func moveYear(_ delta:Int) {yearText=String(min(2099,max(1901,(year ?? Almanac.year(selected))+delta)));invalidYear=false}
    func choose(_ month:Int) {
        guard let year else {invalidYear=true;return}
        let first=Almanac.gregorian.date(from:DateComponents(year:year,month:month,day:1))!
        let day=min(Almanac.day(selected),Almanac.gregorian.range(of:.day,in:.month,for:first)!.count)
        action(Almanac.key(Almanac.gregorian.date(from:DateComponents(year:year,month:month,day:day))!));close()
    }
    var body:some View {
        VStack(spacing:14) {
            HStack {
                Button {moveYear(-1)} label:{Image(systemName:"chevron.left").frame(width:36,height:36)}.help("上一年")
                Spacer()
                TextField("年份",text:$yearText).textFieldStyle(.plain).font(.system(size:24,weight:.semibold,design:.rounded)).multilineTextAlignment(.center).frame(width:78,height:36).background(.white.opacity(0.09),in:RoundedRectangle(cornerRadius:8)).onSubmit {choose(Almanac.gregorian.component(.month,from:selected))}.accessibilityLabel("输入年份")
                Text("年").foregroundStyle(muted)
                Spacer()
                Button {moveYear(1)} label:{Image(systemName:"chevron.right").frame(width:36,height:36)}.help("下一年")
            }.buttonStyle(.plain).foregroundStyle(jade)
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:8),count:3),spacing:8) {
                ForEach(1...12,id:\.self) {m in
                    let picked=year==Almanac.year(selected) && m==Almanac.gregorian.component(.month,from:selected)
                    Button {choose(m)} label:{Text("\(m)月").font(.system(size:15,weight:.medium)).frame(maxWidth:.infinity).frame(height:38).foregroundStyle(picked ? Color.black : .white).background(picked ? jade : .white.opacity(0.07),in:RoundedRectangle(cornerRadius:9))}.buttonStyle(.plain)
                }
            }
            HStack {
                Text(invalidYear ? "请输入1901–2099年" : "年份可直接输入").font(.system(size:10)).foregroundStyle(invalidYear ? workRed : muted)
                Spacer()
                Button("回到今天") {action("today");close()}.buttonStyle(.borderless).foregroundStyle(jade)
            }
        }.padding(18).frame(width:300).background(CalendarBackground()).preferredColorScheme(.dark)
    }
}
struct MonthYearButton:View {
    let selected:Date
    var action:(String)->Void
    @State private var choosing=false
    var body:some View {
        Button {choosing=true} label:{HStack(spacing:8) {Text(Almanac.monthTitle(selected)).font(.system(size:20,weight:.semibold));Image(systemName:"chevron.down").font(.system(size:11))}.padding(.horizontal,14).frame(height:42).background(.white.opacity(0.07),in:RoundedRectangle(cornerRadius:10))}
            .buttonStyle(.plain).focusEffectDisabled().accessibilityLabel("快速切换年月")
            .popover(isPresented:$choosing,arrowEdge:.bottom) {MonthChooser(selected:selected,action:action,close:{choosing=false})}
    }
}
struct MenuCalendar:View {
    @ObservedObject var model:CalendarModel
    var openWindow:()->Void
    @State private var choosingMonth=false
    var body:some View {
        VStack(spacing:0) {
            CalendarCard(selected:model.selected,now:Date(),holidays:model.holidays,size:.large,action:model.select,openDatePicker:{choosingMonth.toggle()}).frame(width:344,height:344)
                .popover(isPresented:$choosingMonth,arrowEdge:.bottom) {MonthChooser(selected:model.selected,action:model.select,close:{choosingMonth=false})}
            Divider().overlay(.white.opacity(0.12)).padding(.horizontal,15)
            HStack {
                Button("打开万年历",action:openWindow)
                Button {openWindow();model.showScheduleEditor=true} label:{Image(systemName:"calendar.badge.plus")}.help("添加日程")
                Button {openWindow();model.beginBirthday()} label:{Image(systemName:"gift")}.help("添加生日")
                Button {openWindow();model.showSettings=true} label:{Image(systemName:"slider.horizontal.3")}.help("显示与外观")
                Spacer()
                Button {Task {await model.update(force:true)}} label:{Image(systemName:"arrow.clockwise")}.help("更新假期").disabled(model.busy)
                Button {NSApp.terminate(nil)} label:{Image(systemName:"power")}.help("退出万年历")
            }.buttonStyle(.borderless).font(.system(size:11)).foregroundStyle(jade).padding(.horizontal,15).padding(.top,12)
            Toggle("登录时启动",isOn:Binding(get:{model.autoStart},set:{model.setAutoStart($0)})).toggleStyle(.checkbox).font(.system(size:10)).foregroundStyle(muted).frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,15).padding(.vertical,10)
            if !model.startupNote.isEmpty {Text(model.startupNote).font(.system(size:10)).foregroundStyle(muted).padding(.bottom,8)}
        }.background(CalendarBackground()).environment(\.calendarData,model.data).preferredColorScheme(.dark)
         .task(id:Almanac.year(model.selected)) {await model.update()}
    }
}
@MainActor final class CalendarDelegate:NSObject,NSApplicationDelegate {
    let model=CalendarModel()
    var window:NSWindow?
    var status:NSStatusItem?
    let popover=NSPopover()
    var clock:Timer?
    var midnightClock:Timer?
    var wakeObserver:NSObjectProtocol?
    var timeObserver:NSObjectProtocol?
    var preferencesObserver:AnyCancellable?
    var appearanceObserver:NSKeyValueObservation?
    var interactionMonitor:Any?
    func applicationDidFinishLaunching(_ notification:Notification) {
        if let url=Bundle.main.url(forResource:"AppIcon",withExtension:"icns") {NSApp.applicationIconImage=NSImage(contentsOf:url)}
        let menu=NSMenu();let item=NSMenuItem();let appMenu=NSMenu()
        appMenu.addItem(withTitle:"退出万年历",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q");item.submenu=appMenu;menu.addItem(item);NSApp.mainMenu=menu
        interactionMonitor=NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown,.keyDown,.scrollWheel]) {[weak self] event in
            Task {@MainActor in self?.model.recordInteraction()}
            return event
        }
        installStatusItem()
        scheduleMidnightUpdate()
        wakeObserver=NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main) {[weak self] _ in Task {@MainActor in self?.checkMidnightUpdate()}}
        timeObserver=NotificationCenter.default.addObserver(forName:.NSSystemClockDidChange,object:nil,queue:.main) {[weak self] _ in Task {@MainActor in self?.checkMidnightUpdate()}}
        try? CalendarDataStore.mirror(model.data)
        WidgetCenter.shared.reloadTimelines(ofKind:calendarWidgetKind)
        if !UserDefaults.standard.bool(forKey:"autoStartConfigured") {model.setAutoStart(true)}
        show()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {false}
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool {show();return true}
    func installStatusItem() {
        status=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        status?.button?.image=MenuIconRenderer.image(model.data.menuIcon)
        status?.button?.imagePosition = .imageOnly
        status?.button?.target=self;status?.button?.action=#selector(toggleCalendar)
        popover.behavior = .transient
        popover.contentSize=NSSize(width:344,height:414)
        popover.contentViewController=NSHostingController(rootView:MenuCalendar(model:model,openWindow:{[weak self] in self?.popover.performClose(nil);self?.show()}))
        refreshStatus()
        appearanceObserver=status?.button?.observe(\.effectiveAppearance,options:[.new]) {[weak self] _,_ in DispatchQueue.main.async {self?.refreshStatus()}}
        preferencesObserver=model.$data.dropFirst().sink {[weak self] _ in DispatchQueue.main.async {self?.refreshStatus()}}
        clock=Timer.scheduledTimer(withTimeInterval:60,repeats:true) {[weak self] _ in Task {@MainActor in self?.refreshStatus();await self?.model.update()}}
    }
    func scheduleMidnightUpdate() {
        midnightClock?.invalidate()
        let timer=Timer(fire:Almanac.nextMidnight(after:Date()),interval:0,repeats:false) {[weak self] _ in Task {@MainActor in self?.checkMidnightUpdate()}}
        timer.tolerance=1;midnightClock=timer;RunLoop.main.add(timer,forMode:.common)
    }
    func checkMidnightUpdate() {
        scheduleMidnightUpdate()
        Task {
            await model.update()
            refreshStatus()
            WidgetCenter.shared.reloadTimelines(ofKind:calendarWidgetKind)
        }
    }
    func refreshStatus() {
        model.returnIfIdle()
        let now=Date()
        if let button=status?.button {
            let title=model.data.menuTitle(now:now,holidays:model.holidays)
            button.effectiveAppearance.performAsCurrentDrawingAppearance {
                let ink=NSColor.labelColor.usingColorSpace(.deviceRGB) ?? .white
                button.image=MenuIconRenderer.statusImage(model.data.menuIcon,title:title,font:button.font ?? NSFont.menuBarFont(ofSize:0),foreground:ink)
            }
            button.title=""
            button.setAccessibilityLabel("万年历 "+title)
        }
        try? CalendarDataStore.mirror(model.data)
        status?.button?.toolTip="万年历 · \(Almanac.weekday(now)) · 点击查看月历"
        if model.followsToday {model.selected=Almanac.clamp(now)}
    }
    @objc func toggleCalendar() {
        if popover.isShown {popover.performClose(nil)}
        else if let button=status?.button {
            if model.followsToday {model.selected=Almanac.clamp(Date())}
            popover.show(relativeTo:button.bounds,of:button,preferredEdge:.minY)
            Task {await model.update()}
        }
    }
    func application(_ application:NSApplication,open urls:[URL]) {
        if let u=urls.first,u.scheme=="lunarcalendar",u.host=="date",let d=Almanac.date(u.lastPathComponent) {model.select(Almanac.key(d))}
        show()
    }
    func show() {
        if window==nil {
            let w=NSWindow(contentRect:NSRect(x:0,y:0,width:880,height:600),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
            w.title="万年历";w.titlebarAppearsTransparent=true;w.titleVisibility = .hidden;w.minSize=NSSize(width:800,height:560);w.isReleasedWhenClosed=false
            w.contentView=NSHostingView(rootView:CalendarWindow(model:model));w.center();w.setFrameAutosaveName("CalendarWindow");window=w
        }
        window?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
}
@main enum CalendarMain {
    @MainActor static func main() throws {
        let app=NSApplication.shared
        if CommandLine.arguments.contains("--reload-widgets") {WidgetCenter.shared.reloadTimelines(ofKind:calendarWidgetKind);RunLoop.current.run(until:Date().addingTimeInterval(2));return}
        if CommandLine.arguments.contains("--render-previews") {
            let dir=URL(fileURLWithPath:CommandLine.arguments.last!);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
            for size in CalendarSize.allCases {
                let width:CGFloat=size == .small ? 164 : 344,height:CGFloat=size == .large ? 344 : 164
                let view=CalendarCard(selected:Almanac.date("2026-10-01")!,now:Date(),holidays:HolidayStore.cached(),size:size)
                    .frame(width:width,height:height).background(CalendarBackground()).clipShape(RoundedRectangle(cornerRadius:23))
                let renderer=ImageRenderer(content:view);renderer.scale=3
                if let tiff=renderer.nsImage?.tiffRepresentation,let png=NSBitmapImageRep(data:tiff)?.representation(using:.png,properties:[:]) {try png.write(to:dir.appendingPathComponent(size.rawValue+".png"))}
            }
            let menuImage=MenuIconRenderer.statusImage(MenuIconPreferences(mode:"custom"),title:"周日",font:NSFont.systemFont(ofSize:14),foreground:.white)
            let proof=ImageRenderer(content:Image(nsImage:menuImage).padding(12).background(Color.gray.opacity(0.5)));proof.scale=4
            if let tiff=proof.nsImage?.tiffRepresentation,let png=NSBitmapImageRep(data:tiff)?.representation(using:.png,properties:[:]) {try png.write(to:dir.appendingPathComponent("menu-alignment.png"))}
            return
        }
        let delegate=CalendarDelegate();app.delegate=delegate;app.setActivationPolicy(.regular);app.run()
        withExtendedLifetime(delegate) {}
    }
}
