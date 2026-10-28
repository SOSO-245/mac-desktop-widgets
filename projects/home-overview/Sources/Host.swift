import AppKit
import SwiftUI
import WidgetKit
import Security
import Network
import ServiceManagement
import Combine
@preconcurrency import Dispatch

/// Explicit local diagnostics contain only sanitized health and window visibility.
enum HomeDiagnostics {
    static var enabled:Bool { CommandLine.arguments.contains("--diagnostics") }
    static func write(_ name:String, value:Any) {
        guard enabled, let data = try? JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys]) else { return }
        let folder = Settings.file.deletingLastPathComponent().appendingPathComponent("Diagnostics")
        try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let file = folder.appendingPathComponent(name + ".json")
        try? data.write(to:file,options:.atomic)
        try? FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
    }
}

enum TokenStore {
    static let service = "local.homeatlas.HomeEnergy.ha-token"
    static var query: [String:Any] { [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"ha"] }
    static func read() -> String? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result:CFTypeRef?; guard SecItemCopyMatching(q as CFDictionary,&result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data:data,encoding:.utf8)
    }
    static func save(_ token:String) throws {
        let data = Data(token.utf8)
        let update = SecItemUpdate(query as CFDictionary,[kSecValueData as String:data] as CFDictionary)
        if update == errSecItemNotFound {
            var q = query; q[kSecValueData as String] = data; q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(q as CFDictionary,nil) == errSecSuccess else { throw HAError.message("无法将令牌保存到钥匙串。") }; return
        }
        guard update == errSecSuccess else { throw HAError.message("无法更新钥匙串中的令牌。") }
    }
}

@MainActor final class EnergyStore: ObservableObject {
    @Published var settings = Settings.load()
    @Published var snapshot = Snapshot()
    @Published var busy = false
    @Published var message = "填写 HA 地址和长期访问令牌，然后保存并连接。"
    @Published var brokerIssue: String?
    @Published var overviewDetails = OverviewDetails()
    let client = HAClient()
    let overviewClient = OverviewClient()
    private var overviewTask: Task<Void,Never>?
    private var lastOverview = Date.distantPast
    private var lastHistory = Date.distantPast
    var timer: Timer?
    private var powerTimer:Timer?
    private var powerBusy=false
    private var powerIssue:String?
    var lastTotals = Date.distantPast
    var lastExtras = Date.distantPast
    var listener:NWListener?
    private var brokerFailed = false
    private var lastBrokerAttempt = Date.distantPast
    var generation = 0
    var token:String?
    static var cache:URL { Settings.file.deletingLastPathComponent().appendingPathComponent("snapshot.json") }

    init() {
        if let data = try? Data(contentsOf: Self.cache), let s = try? JSONDecoder().decode(Snapshot.self,from:data) {
            snapshot = s; snapshot.connectionIssue = "正在连接 HA"
        }
        token = TokenStore.read()
        startBroker()
        if token != nil && !settings.address.isEmpty { Task { await refresh(force:true) } }
        if CommandLine.arguments.contains("--discover-air-quality"), let token {
            let config = settings
            Task { [overviewClient] in
                let candidates = await overviewClient.discoverAirQuality(settings:config,token:token)
                HomeDiagnostics.write("air-quality-candidates",value:candidates)
            }
        }
        powerTimer=Timer(timeInterval:1,repeats:true) {[weak self] _ in Task {@MainActor in await self?.refreshPower()}}
        if let powerTimer {RunLoop.main.add(powerTimer,forMode:.common)}
        timer = Timer(timeInterval:15,repeats:true) { [weak self] _ in
            Task { @MainActor in
                self?.maintainTransientState()
                await self?.refresh()
            }
        }
        if let timer {RunLoop.main.add(timer,forMode:.common)}
    }
    private func maintainTransientState() {
        let now = Date()
        overviewDetails.states = overviewDetails.states.filter {
            OverviewParser.isFresh($0.value.fetchedAt, now:now, maximumAge:1200)
        }
        if !OverviewParser.isFresh(overviewDetails.historyFetchedAt, now:now, maximumAge:1200) {
            overviewDetails.history = []
        }
        // Retry only this app's failed loopback listener, never the system widget host.
        if brokerFailed && now.timeIntervalSince(lastBrokerAttempt) >= 60 {
            listener?.stateUpdateHandler = nil
            listener?.cancel()
            listener = nil
            startBroker()
        }
    }
    func connect(_ enteredToken:String) async -> Bool {
        do {
            try settings.validate()
            let candidate = enteredToken.trimmingCharacters(in:.whitespacesAndNewlines)
            guard !candidate.isEmpty || token != nil else { throw HAError.message("请填写长期访问令牌。") }
            // Do not silently send an old token to a newly typed host.
            if Settings.load().address != settings.address && candidate.isEmpty { throw HAError.message("更换 HA 地址时请重新填写对应令牌。") }
            if !candidate.isEmpty { try TokenStore.save(candidate); token = candidate }
            try settings.save()
            generation += 1
            overviewTask?.cancel(); overviewTask = nil
            overviewDetails = OverviewDetails()
            lastOverview = .distantPast; lastHistory = .distantPast
            snapshot = Snapshot(); snapshot.title = settings.title; snapshot.source = settings.meter.label; snapshot.timezone = settings.timezone
            lastTotals = .distantPast
            lastExtras = .distantPast
            await refresh(force:true)
            return true
        } catch { message = error.localizedDescription; return false }
    }
    func refreshPower() async {
        guard !powerBusy,let token,!settings.address.isEmpty else {return}
        powerBusy=true;defer {powerBusy=false}
        let config=Settings.load(),gen=generation
        let entities=Array(Set([config.entities[0],Meter.home.entities[0],Meter.control.entities[0]]))
        var result:[String:Reading]=[:]
        await withTaskGroup(of:(String,Reading).self) {group in
            for entity in entities {group.addTask {[client] in
                do {return (entity,try Reading.parse(try await client.stateData(settings:config,token:token,entity:entity),index:0))}
                catch {return (entity,Reading(value:nil,fetchedAt:Date(),issue:"功率暂时无法读取"))}
            }}
            for await (entity,reading) in group {result[entity]=reading}
        }
        guard generation==gen else {return}
        var next=snapshot
        if let total=result[config.entities[0]] {next.readings[0]=total;powerIssue=total.issue}
        next.meterPowers=[:]
        for meter in [Meter.home,Meter.control] {next.meterPowers?[meter.rawValue]=result[meter.entities[0]]}
        next.connectionIssue=powerIssue;next.receivedAt=Date();snapshot=next
        saveSnapshot()
    }
    private func saveSnapshot() {
        if let data=try? JSONEncoder().encode(snapshot) {try? data.write(to:Self.cache,options:.atomic);try? FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:Self.cache.path)}
    }
    func refresh(force:Bool = false) async {
        guard !busy, let token, !settings.address.isEmpty else { return }
        busy = true; defer { busy = false }
        let gen = generation; let config = Settings.load()
        if force {await refreshPower()}
        let all = force || Date().timeIntervalSince(lastTotals) >= 300
        let indexes = all ? Array(1..<5) : []
        let extraDue=force || Date().timeIntervalSince(lastExtras) >= 60
        let metrics=ExtraMetric.allCases.enumerated().filter { $0.element.garage ? all : extraDue }
        var issues:[String] = []
        var results:[(Int,Reading)] = []
        await withTaskGroup(of:(Int,Reading?,String?).self) { group in
            for i in indexes { group.addTask { [client] in
                do { return (i,try await client.read(settings:config,token:token,index:i),nil) }
                catch { return (i,nil,(error as? HAError)?.localizedDescription ?? "连接 HA 失败，请检查网络或地址。") }
            } }
            for (i,metric) in metrics { group.addTask { [client] in
                do { return (i+5,try await client.readExtra(settings:config,token:token,metric:metric),nil) }
                catch { return (i+5,Reading(value:nil,fetchedAt:Date(),issue:(error as? HAError)?.localizedDescription ?? "连接 HA 失败"),nil) }
            } }
            for await (i,r,error) in group {
                if let r { results.append((i,r)) }
                if let error { issues.append(error) }
            }
        }
        var cloud:Data?
        var cloudIssue:String?
        if all {
            do { cloud=try await client.stateData(settings:config,token:token,entity:GarageCalculator.cloudEntity) }
            catch { cloudIssue="无法读取特斯拉家充记录" }
        }
        guard generation == gen else { return }
        if snapshot.extras == nil { snapshot.extras=[:] }
        for (i,r) in results {
            if i < 5 { snapshot.readings[i] = r }
            else { snapshot.extras?[ExtraMetric.allCases[i-5].rawValue]=r }
        }
        if all {
            snapshot.extras=GarageCalculator().combine(base:snapshot.extras ?? [:],cloud:cloud,failure:cloudIssue)
            snapshot.garageSource="电瓶车＋特斯拉已记录家充"
        }
        if extraDue { lastExtras=Date() }
        snapshot.title = config.title; snapshot.source = config.meter.label; snapshot.timezone = config.timezone
        snapshot.connectionIssue = powerIssue ?? issues.first
        if !results.isEmpty { snapshot.receivedAt = Date() }
        if all && issues.isEmpty { lastTotals = Date() }
        if !issues.isEmpty { message = issues[0] }
        else if let r = snapshot.readings.first(where: { $0.issue != nil }) { message = r.issue ?? "部分实体不可用" }
        else if let missing=ExtraMetric.allCases.first(where:{snapshot.extras?[$0.rawValue]?.issue != nil}) {
            message="\(missing.label)：\(snapshot.extras?[missing.rawValue]?.issue ?? "不可用")。其他读数正常更新。"
        }
        else { message = "已连接。功率每 1 秒检查，NAS/环境每 60 秒读取；电表有新读数后更新卡片。" }
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to:Self.cache,options:.atomic)
            try? FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:Self.cache.path)
        }
        // macOS applies its own timeline budget; requests are deliberately limited.
        if all || force { WidgetCenter.shared.reloadTimelines(ofKind:"HomeEnergyWidget") }
        refreshOverviewIfNeeded(force:force,settings:config,token:token)
    }
    private func refreshOverviewIfNeeded(force:Bool,settings:Settings,token:String) {
        guard overviewTask == nil, force || Date().timeIntervalSince(lastOverview) >= 60 else { return }
        let gen = generation
        let includeHistory = force || Date().timeIntervalSince(lastHistory) >= 900
        let previous = overviewDetails
        lastOverview = Date()
        // Overview detail/history requests do not delay WidgetKit's bounded refresh.
        overviewTask = Task { [weak self, overviewClient] in
            let details = await overviewClient.load(settings:settings,token:token,previous:previous,includeHistory:includeHistory)
            guard let self, !Task.isCancelled, self.generation == gen else { return }
            self.overviewDetails = details
            let weather = HomeSnapshot.live(core:self.snapshot,details:details)
            var duck = self.snapshot.duckWeather ?? DuckWeather()
            duck.observe(weather.weatherCondition,at:weather.weatherFetchedAt,now:Date())
            self.snapshot.duckWeather = duck
            self.saveSnapshot()
            HomeDiagnostics.write("data-health",value:OverviewParser.diagnostics(details:details,now:Date()))
            if includeHistory { self.lastHistory = Date() }
            self.overviewTask = nil
        }
    }
    func startBroker() {
        lastBrokerAttempt = Date()
        do {
            let p = NWParameters.tcp
            p.requiredLocalEndpoint = .hostPort(host:"127.0.0.1",port:18763)
            let l = try NWListener(using:p)
            l.stateUpdateHandler = { [weak self, weak l] state in
                Task { @MainActor [weak self, weak l] in
                    guard let self, let l, self.listener === l else { return }
                    switch state {
                    case .ready:
                        self.brokerFailed = false
                        self.brokerIssue = nil
                    case .failed:
                        self.brokerFailed = true
                        self.brokerIssue = "本机数据服务暂不可用，将自动重试。"
                    default: break
                    }
                }
            }
            l.newConnectionHandler = { [weak self] connection in
                connection.start(queue:.global(qos:.utility))
                let deadline = DispatchWorkItem { connection.cancel() }
                DispatchQueue.global().asyncAfter(deadline:.now()+20,execute:deadline)
                Self.receive(connection,buffer:Data(),store:self,deadline:deadline)
            }
            l.start(queue:.global(qos:.utility)); listener = l
        } catch { brokerFailed = true; brokerIssue = "本机数据服务无法启动，将自动重试。" }
    }
    nonisolated static func receive(_ c:NWConnection,buffer:Data,store:EnergyStore?,deadline:DispatchWorkItem) {
        c.receive(minimumIncompleteLength:1,maximumLength:4096) { data,_,done,error in
            var buffer = buffer; if let data { buffer.append(data) }
            guard buffer.count <= 8192 else { c.cancel(); return }
            if buffer.range(of:Data("\r\n\r\n".utf8)) == nil {
                if done || error != nil { c.cancel() } else { receive(c,buffer:buffer,store:store,deadline:deadline) }; return
            }
            let line = String(data:buffer,encoding:.utf8)?.components(separatedBy:"\r\n").first ?? ""
            Task { @MainActor in
                guard let store else { c.cancel(); return }
                let weatherRequest = line == "GET /v1/weather HTTP/1.1"
                let allowed = weatherRequest || line == "GET /v1/snapshot HTTP/1.1" || line == "GET /v1/refresh HTTP/1.1"
                if line == "GET /v1/refresh HTTP/1.1" { await store.refresh(force:true) }
                var data = allowed ? ((try? JSONEncoder().encode(store.snapshot)) ?? Data()) : Data()
                if weatherRequest {
                    // Public, weather-only DTO: never forward raw HA attributes, identifiers or configuration.
                    let weather = HomeSnapshot.live(core:store.snapshot,details:store.overviewDetails)
                    let body:[String:Any] = ["temperature":weather.outdoorTemperature as Any? ?? NSNull(),
                        "humidity":weather.outdoorHumidity as Any? ?? NSNull(),
                        "pm25":weather.outdoorPM25 as Any? ?? NSNull(),
                        "symbol":weather.weatherSymbol,"condition":weather.weatherText,
                        "checkedAt":Date().timeIntervalSince1970]
                    data = (try? JSONSerialization.data(withJSONObject:body)) ?? Data()
                }
                let header = "HTTP/1.1 \(allowed ? "200 OK" : "404 Not Found")\r\nContent-Type: application/json\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Length: \(data.count)\r\n\r\n"
                c.send(content:Data(header.utf8)+data,completion:.contentProcessed { _ in deadline.cancel(); c.cancel() })
            }
        }
    }
}

struct SettingsView:View {
    @ObservedObject var store:EnergyStore
    @State private var token = ""
    @State private var size:CardSize = .medium
    @State private var showDemo = false
    var body:some View {
        VStack(alignment:.leading,spacing:20) {
            Text("同一个 Home Assistant 连接，为概览窗口与桌面组件提供数据。").foregroundStyle(.secondary)
            GroupBox("Home Assistant") {
                VStack(alignment:.leading,spacing:12) {
                    LabeledContent("HA 地址") {
                        TextField("http://homeassistant.local:8123",text:$store.settings.address)
                    }
                    LabeledContent("访问令牌") {
                        SecureField(store.token == nil ? "长期访问令牌" : "令牌已保存（留空沿用）",text:$token)
                    }
                    Text("令牌只保存在本机钥匙串。HTTP 仅建议用于可信局域网；远程请使用 HTTPS。").font(.system(size:10)).foregroundStyle(.secondary)
                    Link("访问令牌创建说明",destination:URL(string:"https://www.home-assistant.io/docs/authentication/#your-account-profile")!).font(.callout)
                }.textFieldStyle(.roundedBorder).padding(8)
            }
            GroupBox("监测内容") {
                VStack(alignment:.leading,spacing:14) {
                    Picker("电表",selection:$store.settings.meter) { ForEach(Meter.allCases) { Text($0.label).tag($0) } }
                        .onChange(of:store.settings.meter) { _,meter in if meter != .custom { store.settings.entities = meter.entities } }
                    LabeledContent("组件标题") {TextField("组件标题",text:$store.settings.title)}
                    DisclosureGroup("实体映射（可修改）") {
                        ForEach(0..<5,id:\.self) { i in TextField(["实时功率","今日用电","今日电费","本月用电","本月电费"][i],text:$store.settings.entities[i]).font(.system(size:10,design:.monospaced)) }
                    }
                    DisclosureGroup("大号：NAS、室内、净化器与车库") {
                        ForEach(ExtraMetric.allCases) { metric in
                            TextField(metric.label,text:Binding(get:{store.settings.extraEntity(metric)},set:{value in
                                if store.settings.extraEntities == nil { store.settings.extraEntities=[:] }
                                store.settings.extraEntities?[metric.rawValue]=value
                            })).font(.system(size:10,design:.monospaced))
                        }
                    }
                    DisclosureGroup("室外 PM2.5（天气区）") {
                        TextField("室外传感器",text:Binding(get:{store.settings.outdoorPM25Entity ?? ""},set:{store.settings.outdoorPM25Entity=$0.trimmingCharacters(in:.whitespacesAndNewlines)}),prompt:Text("sensor.室外空气质量实体"))
                            .font(.system(size:10,design:.monospaced))
                        Text("选择室外 PM2.5 浓度，单位 μg/m³；室内净化器与 AQI 指数不适用于此处。").font(.system(size:10)).foregroundStyle(.secondary)
                    }
                }.textFieldStyle(.roundedBorder).padding(8)
            }
            HStack {
                Button(store.busy ? "读取中…" : "保存并连接") {
                    let entered = token
                    Task { if await store.connect(entered) { token = "" } }
                }.buttonStyle(.borderedProminent).disabled(store.busy)
                Button("刷新全部") { Task { await store.refresh(force:true) } }.disabled(store.busy || store.token == nil)
            }
            Text(store.brokerIssue ?? store.message).font(.callout).foregroundStyle(store.brokerIssue == nil ? Color.secondary : .orange).fixedSize(horizontal:false,vertical:true)
            DisclosureGroup("系统小组件预览与添加方法") {
                VStack(alignment:.leading,spacing:16) {
                    Picker("尺寸",selection:$size) { ForEach(CardSize.allCases,id:\.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                    Toggle("预览示例数据",isOn:$showDemo)
                    EnergyCard(snapshot:showDemo ? .sample : store.snapshot,size:size)
                        .background(EnergyBackground()).clipShape(RoundedRectangle(cornerRadius:23,style:.continuous))
                        .frame(width:size == .small ? 164 : 344,height:size == .large ? 344 : 164)
                        .containerShape(RoundedRectangle(cornerRadius:23,style:.continuous))
                    if showDemo { Text("当前为示例，仅用于查看样式。").font(.callout).foregroundStyle(.orange) }
                    Text("右键桌面 → 编辑小组件 → 搜索「家庭概览」，选择小／中／大。关闭窗口后应用继续供数；退出应用后组件显示缓存状态。")
                    Text("小号显示功率与今日摘要；中号增加本月摘要；大号增加车库、NAS 与室内环境。")
                    Text("系统小组件自动刷新由 macOS 决定。右上角刷新按钮可主动读取；读数时间来自 HA，不代表秒级监测。")
                    Text("点击组件主体打开家庭概览；左上标题打开 HA 网页；胶囊文字打开本连接设置页。")
                }.font(.callout).foregroundStyle(.secondary).padding(.top,12)
            }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}

private struct HomeGeneralSettings:View {
    let setLoginEnabled:(Bool)->Void
    let showOverview:()->Void
    let openWebsite:()->Void
    @State private var loginStatus=SMAppService.mainApp.status
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            Toggle("登录时启动",isOn:Binding(get:{loginStatus == .enabled || loginStatus == .requiresApproval},set:{value in
                setLoginEnabled(value)
                loginStatus=SMAppService.mainApp.status
            }))
            if loginStatus == .requiresApproval {
                Text("请在系统设置中允许家庭概览登录时启动。").foregroundStyle(.secondary)
                Button("打开系统登录项设置") {SMAppService.openSystemSettingsLoginItems()}
            }
            Text("关闭窗口后应用继续为桌面卡片和小组件提供数据。").foregroundStyle(.secondary)
            HStack {
                Button("打开家庭概览",action:showOverview)
                Button("打开 HA 网页",action:openWebsite)
            }
        }.onAppear {loginStatus=SMAppService.mainApp.status}
        .onReceive(NotificationCenter.default.publisher(for:NSApplication.didBecomeActiveNotification)) { _ in loginStatus=SMAppService.mainApp.status }
    }
}

@MainActor final class AppDelegate:NSObject,NSApplicationDelegate {
    lazy var store = EnergyStore()
    private var overviewWindow:NSWindow?
    private var statusItem:NSStatusItem?
    private let statusPopover=StatusPopover()
    private let desktopCard=LiveDesktopCard()
    private var powerObservation:AnyCancellable?
    private var statusTimer:Timer?
    private var powerMenuItem:NSMenuItem?
    private var navigationTrace:[[String:Any]] = []
    private func recordNavigation(_ action:String) {
        guard HomeDiagnostics.enabled else { return }
        navigationTrace.append(["action":action,"overviewVisible":overviewWindow?.isVisible == true,"settingsVisible":AppSettingsController.shared.isVisible])
        navigationTrace = Array(navigationTrace.suffix(30))
        HomeDiagnostics.write("navigation",value:navigationTrace)
    }

    func applicationWillFinishLaunching(_ notification:Notification) {
        NSAppleEventManager.shared().setEventHandler(self,andSelector:#selector(handleURL(_:withReplyEvent:)),forEventClass:AEEventClass(kInternetEventClass),andEventID:AEEventID(kAEGetURL))
    }
    @objc private func handleURL(_ event:NSAppleEventDescriptor,withReplyEvent reply:NSAppleEventDescriptor) {
        guard let value = event.paramDescriptor(forKeyword:AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string:value) else { return }
        application(NSApp,open:[url])
    }
    func applicationDidFinishLaunching(_ notification:Notification) {
        NSApp.setActivationPolicy(.accessory)
        WidgetSelfRepair.shared.start()
        if let url = Bundle.main.url(forResource:"AppIcon",withExtension:"icns"),
           let icon = NSImage(contentsOf:url), icon.isValid { NSApp.applicationIconImage = icon }
        _ = store
        installPowerStatusItem()
        configureSettings()
        let defaultLaunch = (notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? NSNumber)?.boolValue == true
        recordNavigation(defaultLaunch ? "default-launch" : "url-or-restored-launch")
        let loginLaunch = NSAppleEventManager.shared().currentAppleEvent?
            .paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
        if defaultLaunch && !loginLaunch && !CommandLine.arguments.contains("--background") { showOverview() }
    }
    private func installPowerStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName:"bolt.fill",accessibilityDescription:"家庭概览")
        item.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        let reading = NSMenuItem(title:"功率：— W",action:nil,keyEquivalent:"")
        menu.addItem(reading); powerMenuItem = reading; menu.addItem(.separator())
        for (title,action) in [("打开家庭概览",#selector(statusOpenOverview)),("打开 HA 网页",#selector(statusOpenWebsite)),("立即刷新",#selector(statusRefresh))] {
            let entry = NSMenuItem(title:title,action:action,keyEquivalent:""); entry.target = self; menu.addItem(entry)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle:"退出家庭概览",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"")
        AppSettingsController.shared.installMenuItem(in:menu)
        statusItem = item
        statusPopover.attach(to:item,menu:menu,size:NSSize(width:344,height:344),openTitle:"打开完整概览",
            open:{[weak self] in self?.showOverview()},desktopOptions:true,content:{[weak self] native in
                guard let self else{return AnyView(EmptyView())}
                return AnyView(EnergyCard(menuSurface:native,interactiveWater:true,animatePower:UserDefaults.standard.object(forKey:"powerArc.enabled") as? Bool ?? true,snapshot:self.store.snapshot,size:.large,
                    refresh:AnyView(Button(action:{[weak self] in self?.statusRefresh()}){Image(systemName:"arrow.clockwise")}.buttonStyle(.plain)))
                    .background{if !native{EnergyBackground()}}.clipShape(RoundedRectangle(cornerRadius:23)).containerShape(RoundedRectangle(cornerRadius:23,style:.continuous)).environment(\.colorScheme,.dark))
            })
        desktopCard.start(title:"家庭概览",menu:menu,refresh:{[weak self] in self?.statusRefresh()}) {[weak self] size,plain,controls in
            guard let self else {return AnyView(EmptyView())}
            let family:CardSize = size=="small" ? .small:size=="large" ? .large:.medium
            return AnyView(EnergyCard(waterTheme:self.desktopCard.waterTheme,menuSurface:plain,interactiveWater:true,animatePower:UserDefaults.standard.object(forKey:"powerArc.enabled") as? Bool ?? true,snapshot:self.store.snapshot,size:family,refresh:controls,websiteURL:URL(string:"homeenergy://website"),overviewURL:URL(string:"homeenergy://overview"))
                .background {if !plain {EnergyBackground()}})
        }
        powerObservation = store.$snapshot.sink { [weak self] snapshot in self?.updatePowerStatusItem(snapshot) }
        let timer = Timer(timeInterval:15,repeats:true) { [weak self] _ in
            Task { @MainActor in guard let self else { return }; self.updatePowerStatusItem(self.store.snapshot) }
        }
        statusTimer = timer; RunLoop.main.add(timer,forMode:.common)
        updatePowerStatusItem(store.snapshot)
    }
    private func updatePowerStatusItem(_ snapshot:Snapshot) {
        DispatchQueue.main.async { [weak self] in self?.statusPopover.update();self?.desktopCard.update() }
        guard let button = statusItem?.button else { return }
        let now = Date(), text = snapshot.menuPower(at:now)
        let color:NSColor
        switch snapshot.menuPowerTone(at:now) {
        case .green: color = NSColor(srgbRed:0.40,green:1,blue:0.68,alpha:1)
        case .pink: color = NSColor(srgbRed:1,green:0.43,blue:0.76,alpha:1)
        case .purple: color = NSColor(srgbRed:0.84,green:0.48,blue:1,alpha:1)
        case .unavailable: color = .white
        }
        button.attributedTitle = NSAttributedString(string:" " + text,attributes:[
            .font:NSFont.monospacedDigitSystemFont(ofSize:13,weight:.semibold),.foregroundColor:color])
        button.toolTip = "家庭概览 · " + snapshot.source + " · " + snapshot.status(at:now) + "\n功率每 1 秒检查"
        button.setAccessibilityLabel("家庭概览 " + text)
        powerMenuItem?.title = "功率：" + text
        button.image=NSImage(systemSymbolName:"bolt.fill",accessibilityDescription:nil);button.imagePosition = .imageLeading
        MenuCustomizationPanel.apply(button,fields:customMenuFields(snapshot),icon:button.image)
    }
    private func customMenuFields(_ snapshot:Snapshot)->[MenuField] {
        let tone=snapshot.menuPowerTone(at:Date())
        let key:String
        switch tone { case .green:key="normal";case .pink:key="high";case .purple:key="peak";case .unavailable:key="unknown" }
        let color=MenuCustomization.color(["normal":"#66FFAD","high":"#FF6EC2","peak":"#D67AFF","unknown":"#FFFFFF"][key]!)
        return [MenuField(id:"power",title:"实时功率",value:snapshot.menuPower(at:Date()),color:color,colorKey:key),
                MenuField(id:"source",title:"电表名称",value:snapshot.source,defaultVisible:false),
                MenuField(id:"today",title:"今日用电",value:snapshot.number(1)+" 度",defaultVisible:false),
                MenuField(id:"todayCost",title:"今日电费估算",value:"¥"+snapshot.number(2),defaultVisible:false),
                MenuField(id:"month",title:"本月用电",value:snapshot.number(3)+" 度",defaultVisible:false),
                MenuField(id:"monthCost",title:"本月电费估算",value:"¥"+snapshot.number(4),defaultVisible:false)]
    }
    private func configureSettings() {
        ToolboxBridge.shared.start(show:{[weak self] visible in self?.desktopCard.setHidden(!visible)},size:{[weak self] value in self?.desktopCard.setSize(value)})
        AppSettingsController.shared.configure(title:"家庭概览",pages:[
            AppSettingsPage(id:"toolbox",title:"桌面排列",symbol:"square.grid.2x2") {AnyView(ToolboxSettingsLink())},
            AppSettingsPage(id:"general",title:"通用",symbol:"gearshape") { [weak self] in
                AnyView(HomeGeneralSettings(setLoginEnabled:{self?.setLoginEnabled($0)},showOverview:{self?.showOverview()},openWebsite:{self?.openWebsite()}))
            },
            AppSettingsPage(id:"desktop",title:"桌面卡片",symbol:"rectangle.on.rectangle") { [weak self] in
                guard let self else {return AnyView(EmptyView())}
                return AnyView(VStack(alignment:.leading,spacing:24) {
                    self.desktopCard.settingsContent
                    PowerArcSettings()
                    Divider()
                    DesktopAppearanceSettings(model:.shared)
                })
            },
            AppSettingsPage(id:"menubar",title:"菜单栏",symbol:"menubar.rectangle") { [weak self] in
                guard let self else {return AnyView(EmptyView())}
                return AnyView(VStack(alignment:.leading,spacing:24) {
                    self.statusPopover.settingsContent
                    Divider()
                    MenuCustomizationView(fields:self.customMenuFields(self.store.snapshot),fallback:NSImage(systemSymbolName:"bolt.fill",accessibilityDescription:nil),extraColors:[("normal","功率 ≤ 1000 W",MenuCustomization.color("#66FFAD")),("high","功率 > 1000 W",MenuCustomization.color("#FF6EC2")),("peak","功率 > 3000 W",MenuCustomization.color("#D67AFF"))]) { [weak self] in
                        guard let self else {return};self.updatePowerStatusItem(self.store.snapshot)
                    }
                })
            },
            AppSettingsPage(id:"connection",title:"连接与数据",symbol:"network") { [weak self] in
                guard let self else {return AnyView(EmptyView())}
                return AnyView(SettingsView(store:self.store))
            },
            AppSettingsPage(id:"updates",title:"更新与版本",symbol:"arrow.down.circle") {AppUpdater.shared.settingsContent}
        ],beforeShow:{[weak self] in self?.statusPopover.close()})
    }
    @objc private func statusOpenOverview() { showOverview() }
    @objc private func statusOpenWebsite() { openWebsite() }
    @objc private func statusRefresh() { Task { await store.refresh(force:true) } }
    private func setLoginEnabled(_ enabled:Bool) {
        do {
            let status=SMAppService.mainApp.status
            if enabled && status != .enabled && status != .requiresApproval { try SMAppService.mainApp.register() }
            else if !enabled && (status == .enabled || status == .requiresApproval) { try SMAppService.mainApp.unregister() }
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch { NSAlert(error:error).runModal() }
    }
    func applicationWillTerminate(_ notification:Notification) { statusTimer?.invalidate(); powerObservation?.cancel() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool) -> Bool {
        // Dock activation is a normal reopen; URL delivery has its own explicit route.
        if !flag { showOverview() }
        return false
    }
    func showOverview() {
        statusPopover.close()
        AppSettingsController.shared.close()
        if overviewWindow == nil {
            let window = NSWindow(contentRect:NSRect(x:0,y:0,width:1280,height:790),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
            window.title = "家庭概览"
            window.identifier = NSUserInterfaceItemIdentifier("overview")
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.minSize = NSSize(width:720,height:480)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView:OverviewWindowView(store:store,showSettings:showSettings,openWebsite:openWebsite))
            window.center()
            window.setFrameAutosaveName("HomeAtlasOverview")
            overviewWindow = window
        }
        overviewWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps:true)
        recordNavigation("overview")
    }
    func showSettings() {
        AppSettingsController.shared.show("connection")
        recordNavigation("settings")
    }
    func openWebsite() {
        statusPopover.close()
        do {
            let destination = try Settings.load().baseURL()
            AppSettingsController.shared.close()
            overviewWindow?.orderOut(nil)
            guard NSWorkspace.shared.open(destination) else {
                throw HAError.message("无法打开浏览器，请检查默认浏览器设置。")
            }
            recordNavigation("website")
        } catch {
            NSApp.activate(ignoringOtherApps:true)
            NSAlert(error:error).runModal()
        }
    }
    func application(_ application:NSApplication,open urls:[URL]) {
        guard let url = urls.first(where: { ["homeenergy","homeatlas"].contains($0.scheme ?? "") }) else { return }
        DispatchQueue.main.async {
            switch url.host {
            case "website": self.openWebsite()
            case "settings": self.showSettings()
            // Pre-merge desktop timelines used open-ha as their whole-card URL.
            // Keep those installed widgets opening the merged app after upgrades.
            case "overview","open-ha","energy","environment","nas": self.showOverview()
            default: break
            }
        }
    }
}

@main struct HomeEnergyApp:App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    init() {
        if CommandLine.arguments.contains("--enable-login") {
            do {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
                print("LOGIN_STATUS=\(SMAppService.mainApp.status.rawValue)")
            } catch { print("LOGIN_ERROR=\((error as NSError).code)") }
            exit(0)
        }
        if CommandLine.arguments.contains("--render-previews") {
            Self.renderPreviews(); exit(0)
        }
    }
    var body:some Scene {
        // AppKit owns the status item and explicit windows; no timeline view in a menu label.
        SwiftUI.Settings { EmptyView() }
            .commands {
                CommandGroup(replacing:.appSettings) {
                    Button("设置…") {AppSettingsController.shared.show()}
                        .keyboardShortcut(",",modifiers:.command)
                }
            }
    }
    @MainActor static func renderPreviews() {
        let dir = CommandLine.arguments.last ?? "."
        for size in CardSize.allCases {
            let width:CGFloat = size == .small ? 164 : 344, height:CGFloat = size == .large ? 344 : 164
            let view = EnergyCard(snapshot:.sample,size:size).background(EnergyBackground()).clipShape(RoundedRectangle(cornerRadius:23,style:.continuous)).frame(width:width,height:height).containerShape(RoundedRectangle(cornerRadius:23,style:.continuous))
            let renderer = ImageRenderer(content:view); renderer.scale = 3
            if let image = renderer.nsImage, let tiff = image.tiffRepresentation,let rep = NSBitmapImageRep(data:tiff),let data = rep.representation(using:.png,properties:[:]) {
                try? data.write(to:URL(fileURLWithPath:dir).appendingPathComponent("\(size.rawValue)-示例.png"))
            }
        }
    }
}


private struct PowerArcSettings:View {
    @AppStorage("powerArc.enabled") private var enabled=true
    var body:some View {Toggle("水面动画",isOn:$enabled).help("电表可用时显示；减少动态效果开启时静止") }
}
