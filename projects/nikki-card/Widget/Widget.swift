import SwiftUI
import WidgetKit
import AppIntents

final class NoWidgetRedirect:NSObject, URLSessionTaskDelegate {
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void) { completionHandler(nil) }
}
enum WidgetFeed {
    static func fetch() async -> NikkiWidgetData {
        let key = "nikki.widget.snapshot"
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = ["HTTPEnable":0,"HTTPSEnable":0,"SOCKSEnable":0]
        config.httpCookieStorage = nil;config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 4;config.timeoutIntervalForResource = 5
        let session = URLSession(configuration:config,delegate:NoWidgetRedirect(),delegateQueue:nil)
        defer { session.invalidateAndCancel() }
        do {
            let (data,response) = try await session.data(from:URL(string:"http://127.0.0.1:\(NikkiWidgetData.port)/snapshot")!)
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 100_000 else { throw URLError(.badServerResponse) }
            let result = try JSONDecoder().decode(NikkiWidgetData.self,from:data)
            UserDefaults.standard.set(data,forKey:key);return result
        } catch {
            var cached = UserDefaults.standard.data(forKey:key).flatMap { try? JSONDecoder().decode(NikkiWidgetData.self,from:$0) } ?? NikkiWidgetData()
            cached.snapshot.isConnected = false;return cached
        }
    }
}
struct RefreshNikki:AppIntent {
    static var title:LocalizedStringResource = "刷新 Nikki 小组件"
    func perform() async throws -> some IntentResult {
        _ = await WidgetFeed.fetch();WidgetCenter.shared.reloadTimelines(ofKind:NikkiWidgetData.kind);return .result()
    }
}
struct NikkiEntry:TimelineEntry { let date:Date;let value:NikkiWidgetData;var preview=false }
struct NikkiProvider:TimelineProvider {
    func placeholder(in context:Context)->NikkiEntry { NikkiEntry(date:Date(),value:.sample,preview:true) }
    func getSnapshot(in context:Context,completion:@escaping(NikkiEntry)->Void) {
        if context.isPreview { completion(placeholder(in:context)) } else { Task { completion(NikkiEntry(date:Date(),value:await WidgetFeed.fetch())) } }
    }
    func getTimeline(in context:Context,completion:@escaping(Timeline<NikkiEntry>)->Void) {
        Task {
            let data = await WidgetFeed.fetch(), now = Date()
            let stale = max(now.addingTimeInterval(1),data.generatedAt.addingTimeInterval(91))
            completion(Timeline(entries:[NikkiEntry(date:now,value:data),NikkiEntry(date:stale,value:data)],policy:.after(now.addingTimeInterval(60))))
        }
    }
}
struct NikkiWidgetView:View {
    let entry:NikkiEntry
    @Environment(\.widgetFamily) var family
    private var s:MonitorSnapshot { entry.value.snapshot }
    private var fresh:Bool { entry.preview || entry.value.isFresh(at:entry.date) }
    private let mint=Color(red:0.4,green:1,blue:0.68)
    private let purple=Color(red:0.72,green:0.62,blue:1)
    private var small:Bool { family == .systemSmall }
    private func bytes(_ value:Double?)->String {
        guard let value, value.isFinite, value>=0, value<Double(Int64.max) else { return "—" }
        return ByteCountFormatter.string(fromByteCount:Int64(value),countStyle:.decimal)
    }
    var body:some View {
        VStack(alignment:.leading,spacing:small ? 7 : 9) {
            HStack(spacing:6) {
                Image(systemName:"wifi.router.fill").foregroundStyle(purple)
                Text("Nikki").font(.system(size:14,weight:.bold))
                if !small { Text("· " + (s.profileName ?? "等待连接")).font(.system(size:12,weight:.semibold)).lineLimit(1) }
                Spacer(minLength:0)
                Button(intent:RefreshNikki()) { Image(systemName:"arrow.clockwise").font(.system(size:12,weight:.semibold)) }.buttonStyle(.plain).accessibilityLabel("刷新 Nikki")
            }
            if small { Text(s.profileName ?? "请打开 Nikki 卡片").font(.system(size:11,weight:.semibold)).lineLimit(1) }
            HStack(alignment:.firstTextBaseline) {
                Text(bytes(s.usedBytes)+" / "+bytes(s.totalBytes)).font(.system(size:small ? 12 : 13,weight:.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength:0)
                if !small { Text(SubscriptionCountdown.text(expiry:s.expiresAt,now:entry.date)).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1) }
            }
            GeometryReader { g in
                Capsule().fill(.white.opacity(0.13)).overlay(alignment:.leading) {
                    if let used=s.usedBytes,let total=s.totalBytes,total>0 {
                        Capsule().fill(LinearGradient(colors:[purple,.cyan],startPoint:.leading,endPoint:.trailing)).frame(width:g.size.width*min(1,max(0,used/total)))
                    }
                }
            }.frame(height:4)
            Link(destination:URL(string:"nikki://nodes")!) {
                HStack(spacing:5) {
                    Image(systemName:"globe").foregroundStyle(purple)
                    Text(s.nodeName ?? "点击选择节点").lineLimit(1)
                    Spacer(minLength:0)
                    Text(fresh ? s.connectionCount.map { "\($0) 连" } ?? "— 连" : "— 连").font(.system(size:9)).fixedSize()
                    if !small { Text(fresh ? s.latencyMS.map { "\($0) ms" } ?? "—" : "—").foregroundStyle(mint).fixedSize() }
                }.font(.system(size:small ? 10 : 11,weight:.semibold)).padding(6).background(.white.opacity(0.06),in:RoundedRectangle(cornerRadius:8))
            }
            HStack {
                speed("↓",s.downloadBps,.cyan)
                Spacer(minLength:4)
                speed("↑",s.uploadBps,purple)
            }
            if family == .systemLarge {
                Spacer(minLength:3)
                Divider().overlay(.white.opacity(0.12))
                LazyVGrid(columns:Array(repeating:GridItem(.flexible()),count:3),spacing:10) {
                    ForEach(["Google","GitHub","YouTube","ChatGPT","Claude","bilibili"],id:\.self) { name in
                        let reading=entry.value.sites.first { $0.name==name }
                        let recent=reading?.checkedAt.map { (0...120).contains(entry.date.timeIntervalSince($0)) } ?? false
                        VStack(spacing:7) {
                            HStack(spacing:4) {
                                if let path=Bundle.main.url(forResource:name,withExtension:"png",subdirectory:"SiteIcons"),let icon=NSImage(contentsOf:path) {
                                    Image(nsImage:icon).resizable().frame(width:13,height:13)
                                }
                                Text(name).font(.system(size:10,weight:.medium)).lineLimit(1).minimumScaleFactor(0.8)
                            }
                            Text(fresh && recent ? reading?.milliseconds.map { "\($0) ms" } ?? "—" : "—")
                                .font(.system(size:14,weight:.semibold,design:.rounded)).monospacedDigit()
                                .foregroundStyle(reading?.status == "响应" ? mint : Color.pink)
                        }.frame(maxWidth:.infinity).padding(.vertical,10).background(.white.opacity(0.055),in:RoundedRectangle(cornerRadius:12))
                    }
                }
                Spacer(minLength:0)
            }
            HStack(spacing:4) {
                Circle().fill(fresh ? mint : .orange).frame(width:4,height:4)
                Text(entry.preview ? "示例数据" : entry.value.generatedAt == .distantPast ? "打开 Nikki 实时卡片以连接" : fresh ? "更新 " + entry.value.generatedAt.formatted(date:.omitted,time:.shortened) : "缓存 · 打开卡片以更新")
                    .font(.system(size:9)).foregroundStyle(.secondary).lineLimit(1)
            }
        }.padding(small ? 12 : 14).foregroundStyle(.white)
        .containerBackground(for:.widget) {
            LinearGradient(colors:[Color(red:0.18,green:0.18,blue:0.33),Color(red:0.04,green:0.065,blue:0.12)],startPoint:.topLeading,endPoint:.bottomTrailing)
        }
        .widgetURL(URL(string:"nikki://card"))
    }
    private func speed(_ label:String,_ value:Double?,_ color:Color)->some View {
        HStack(alignment:.firstTextBaseline,spacing:4) {
            Text(label).foregroundStyle(color)
            Text(fresh ? bytes(value)+"/s" : "—").lineLimit(1).minimumScaleFactor(0.65)
        }.font(.system(size:small ? 13 : 18,weight:.semibold,design:.rounded))
    }
}
@main struct NikkiDesktopWidget:Widget {
    var body:some WidgetConfiguration {
        StaticConfiguration(kind:NikkiWidgetData.kind,provider:NikkiProvider()) { NikkiWidgetView(entry:$0) }
            .configurationDisplayName("Nikki 实时卡片")
            .description("旁路由套餐、节点与流量；大号包含六站点延迟。点击节点打开切换窗口。需保持 Nikki 实时卡片运行。")
            .supportedFamilies([.systemSmall,.systemMedium,.systemLarge]).contentMarginsDisabled().containerBackgroundRemovable(false)
    }
}
