import AppKit
import SwiftUI
import Sparkle

struct SuiteProduct: Identifiable {
    let id: String
    let name: String
    let slug: String
    let appName: String
    static let all: [Self] = [
        .init(id:"local.homeatlas.Toolbox",name:"桌面工具箱",slug:"desktop-toolbox",appName:"桌面工具箱"),
        .init(id:"local.homeatlas.LunarCalendar",name:"万年历",slug:"lunar-calendar",appName:"万年历"),
        .init(id:"local.homeatlas.HomeEnergy",name:"家庭概览",slug:"home-overview",appName:"家庭概览"),
        .init(id:"local.homeatlas.CodexResets",name:"重置监测",slug:"codex-resets",appName:"Codex 重置"),
        .init(id:"local.homeatlas.NikkiMonitor",name:"Nikki",slug:"nikki-card",appName:"Nikki 实时卡片"),
        .init(id:"local.homeatlas.FlClashMonitor",name:"VPN 监测",slug:"vpn-card",appName:"FlClash 实时卡片"),
        .init(id:"local.homeatlas.MacVitals",name:"Mac 监测",slug:"mac-vitals",appName:"Mac 实时监测"),
        .init(id:"local.homeatlas.APIUsage",name:"API 用量",slug:"api-usage",appName:"API用量卡片")]
    var installed: Bundle? {
        if id == Bundle.main.bundleIdentifier { return Bundle.main }
        for root in [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"), URL(fileURLWithPath:"/Applications")] {
            if let b=Bundle(url:root.appendingPathComponent(appName+".app")),b.bundleIdentifier == id {return b}
        }
        return nil
    }
}

/// Discovery only. Sparkle independently verifies the signed feed and archive
/// before any installation. Network metadata alone can never install a package.
final class SuiteFeed: NSObject, XMLParserDelegate {
    var build="", version=""
    private var active="", text="", inside=false, finished=false
    func parser(_ p:XMLParser,didStartElement name:String,namespaceURI:String?,qualifiedName:String?,attributes:[String:String]) {
        if name == "item" && !finished {inside=true}
        active=name;text=""
    }
    func parser(_ p:XMLParser,foundCharacters s:String){text+=s}
    func parser(_ p:XMLParser,didEndElement name:String,namespaceURI:String?,qualifiedName:String?) {
        guard inside else{return}
        if name == "sparkle:version" {build=text.trimmingCharacters(in:.whitespacesAndNewlines)}
        if name == "sparkle:shortVersionString" {version=text.trimmingCharacters(in:.whitespacesAndNewlines)}
        if name == "item" {inside=false;finished=true}
    }
    static func newer(_ candidate:String,than current:String)->Bool {
        guard !candidate.isEmpty,!current.isEmpty else{return false}
        return candidate.compare(current,options:.numeric) == .orderedDescending
    }
}

@MainActor final class SuiteUpdates:NSObject,ObservableObject,SPUUpdaterDelegate {
    static let shared=SuiteUpdates()
    @Published var selected:Set<String>=Set(UserDefaults.standard.stringArray(forKey:"suiteUpdateSelection") ?? SuiteProduct.all.map(\.id))
    @Published var statuses:[String:String]=[:]
    @Published var available:Set<String>=[]
    @Published var checking=false
    @Published var installing=false
    @Published var note="选择需要更新的软件，或全选。"
    @Published var automatic=UserDefaults.standard.object(forKey:"suiteUpdateChecks") as? Bool ?? true
    private var window:NSWindow?
    private var timer:Timer?
    private var updater:SPUUpdater?
    private var driver:SPUStandardUserDriver?
    private var pending:[SuiteProduct]=[]
    private var active:SuiteProduct?
    private var wasRunning=false
    private var checkBusy=false
    func start(){
        guard timer == nil else{return}
        timer=Timer.scheduledTimer(withTimeInterval:3600,repeats:true){[weak self] _ in Task{@MainActor in
            guard let self,self.automatic,!self.installing else{return}
            let last=UserDefaults.standard.object(forKey:"suiteUpdateLastCheck") as? Date ?? .distantPast
            if Date().timeIntervalSince(last)>=86400 {await self.check(selectedOnly:true)}
        }}
        Task { if automatic {let last=UserDefaults.standard.object(forKey:"suiteUpdateLastCheck") as? Date ?? .distantPast;if Date().timeIntervalSince(last)>=86400 {await check(selectedOnly:true)}} }
    }
    func save(){UserDefaults.standard.set(Array(selected),forKey:"suiteUpdateSelection");UserDefaults.standard.set(automatic,forKey:"suiteUpdateChecks")}
    func show(){
        if window == nil {
            let w=NSWindow(contentRect:NSRect(x:0,y:0,width:650,height:720),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
            w.title="桌面工具箱 · 软件更新";w.isReleasedWhenClosed=false
            w.contentView=NSHostingView(rootView:SuiteUpdateView(model:self));w.center();window=w
        }
        NSApp.activate(ignoringOtherApps:true);window?.makeKeyAndOrderFront(nil)
    }
    func check(selectedOnly:Bool=false) async {
        guard !checking,!installing else{return};checking=true;defer{checking=false}
        let config=URLSessionConfiguration.ephemeral;config.httpCookieStorage=nil;config.urlCache=nil;config.timeoutIntervalForRequest=20
        let session=URLSession(configuration:config);defer{session.invalidateAndCancel()}
        for product in SuiteProduct.all where !selectedOnly || selected.contains(product.id) {
            guard let bundle=product.installed else{statuses[product.id]="未安装";available.remove(product.id);continue}
            do {
                let url=URL(string:"https://raw.githubusercontent.com/SOSO-245/mac-desktop-widgets/main/updates/\(product.slug).xml")!
                let (data,response)=try await session.data(from:url)
                guard (response as? HTTPURLResponse)?.statusCode == 200,data.count<524288,response.url?.host == "raw.githubusercontent.com" else {throw NSError(domain:"feed",code:1)}
                let feed=SuiteFeed();let parser=XMLParser(data:data);parser.delegate=feed;parser.shouldResolveExternalEntities=false
                guard parser.parse(),!feed.build.isEmpty else{throw NSError(domain:"feed",code:2)}
                let current=bundle.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? ""
                if SuiteFeed.newer(feed.build,than:current){available.insert(product.id);statuses[product.id]="可更新 → \(feed.version)"}
                else {available.remove(product.id);statuses[product.id]="已是最新 \(bundle.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "")"}
            } catch {available.remove(product.id);statuses[product.id]="检查失败，可重试"}
        }
        UserDefaults.standard.set(Date(),forKey:"suiteUpdateLastCheck")
        note="检查完成，\(available.count) 款软件有更新。安装时仍会由 Sparkle 核验签名。"
    }
    func updateSelected(){
        guard !installing,!checking else{return}
        // Self update runs last so a Toolbox restart cannot interrupt the queue.
        pending=SuiteProduct.all.filter{selected.contains($0.id) && available.contains($0.id) && $0.id != Bundle.main.bundleIdentifier}
        installing=true;next()
    }
    private func next(){
        guard !pending.isEmpty else{
            installing=false
            if selected.contains("local.homeatlas.Toolbox"),available.contains("local.homeatlas.Toolbox"){AppUpdater.shared.check()}
            else {note="所选更新流程已结束。"}
            return
        }
        let product=pending.removeFirst();active=product
        guard let bundle=product.installed,let feed=bundle.object(forInfoDictionaryKey:"SUFeedURL") as? String,
              feed == "https://raw.githubusercontent.com/SOSO-245/mac-desktop-widgets/main/updates/\(product.slug).xml",
              bundle.object(forInfoDictionaryKey:"SURequireSignedFeed") as? Bool == true,
              bundle.object(forInfoDictionaryKey:"SUPublicEDKey") as? String != nil else{
            statuses[product.id]="需先从 GitHub 手动升级一次";next();return
        }
        let apps=NSRunningApplication.runningApplications(withBundleIdentifier:product.id)
        wasRunning = !apps.isEmpty
        // Pause only the selected app's native updater, avoiding concurrent installers.
        for app in apps {app.terminate()}
        note="正在准备 \(product.name)，请在更新窗口确认安装；取消后会恢复运行。"
        Task {
            for _ in 0..<30 {
                if NSRunningApplication.runningApplications(withBundleIdentifier:product.id).isEmpty {break}
                try? await Task.sleep(for:.milliseconds(100))
            }
            guard NSRunningApplication.runningApplications(withBundleIdentifier:product.id).isEmpty else {statuses[product.id]="应用未退出，已跳过";next();return}
            do {
                let driver=SPUStandardUserDriver(hostBundle:bundle,delegate:nil);self.driver=driver
                let updater=SPUUpdater(hostBundle:bundle,applicationBundle:bundle,userDriver:driver,delegate:self);self.updater=updater
                try updater.start();updater.checkForUpdates()
            } catch {finishActive(error:error)}
        }
    }
    private func finishActive(error:Error?){
        if let product=active,let bundle=product.installed {
            statuses[product.id]=error == nil ? "流程结束，重新检查可核验版本":"更新未完成，可重试"
            if wasRunning,NSRunningApplication.runningApplications(withBundleIdentifier:product.id).isEmpty {NSWorkspace.shared.open(bundle.bundleURL)}
        }
        updater=nil;driver=nil;active=nil
        DispatchQueue.main.asyncAfter(deadline:.now()+0.5){self.next()}
    }
    func updater(_ updater:SPUUpdater,didFinishUpdateCycleFor updateCheck:SPUUpdateCheck,error:Error?){guard self.updater === updater else{return};DispatchQueue.main.async{self.finishActive(error:error)}}
    func allowedSystemProfileKeys(for updater:SPUUpdater)->[String]?{[]}
}

private struct SuiteUpdateView:View {
    @ObservedObject var model:SuiteUpdates
    var body:some View {
        ScrollView {VStack(alignment:.leading,spacing:18){
            Text("软件更新").font(.title.bold())
            AppUpdater.shared.settingsContent
            Divider()
            HStack {Text("所有桌面软件").font(.headline);Spacer();Button("全选"){model.selected=Set(SuiteProduct.all.map(\.id))};Button("清空"){model.selected=[]}}
            ForEach(SuiteProduct.all){p in HStack{
                Toggle(p.name,isOn:Binding(get:{model.selected.contains(p.id)},set:{v in if v{model.selected.insert(p.id)}else{model.selected.remove(p.id)}}))
                Spacer();Text(model.statuses[p.id] ?? (p.installed == nil ? "未安装":"待检查")).font(.caption).foregroundStyle(.secondary)
            }}
            Toggle("每天自动检查所选软件",isOn:$model.automatic)
            HStack {Button("检查全部软件"){Task{await model.check()}};Spacer();Button("更新所选软件…"){model.updateSelected()}.buttonStyle(.borderedProminent).disabled(model.available.intersection(model.selected).isEmpty)}
            Text(model.note).font(.callout).foregroundStyle(.secondary)
            Text("更新选择与桌面显示选择独立。更新按顺序进行，当前软件会短暂退出并重新打开；连接和外观继续由各软件保存。").font(.caption).foregroundStyle(.secondary)
        }.padding(24).disabled(model.checking || model.installing)}
        .onChange(of:model.selected){_,_ in model.save()}.onChange(of:model.automatic){_,_ in model.save()}
    }
}
