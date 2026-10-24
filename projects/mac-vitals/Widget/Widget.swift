import SwiftUI
import WidgetKit
import AppIntents
struct VitalsEntry:TimelineEntry {let date:Date;let data:Metrics;var preview=false}
enum Feed {
    static func get()async->Metrics {
        let c=URLSessionConfiguration.ephemeral;c.connectionProxyDictionary=["HTTPEnable":0,"HTTPSEnable":0,"SOCKSEnable":0];c.timeoutIntervalForRequest=4;c.timeoutIntervalForResource=5;c.httpCookieStorage=nil;c.urlCredentialStorage=nil
        let session=URLSession(configuration:c);defer{session.invalidateAndCancel()}
        do{let (d,r)=try await session.data(from:URL(string:"http://127.0.0.1:\(Metrics.port)/snapshot")!);guard (r as? HTTPURLResponse)?.statusCode==200,d.count<100_000 else{return Metrics()};let m=try JSONDecoder().decode(Metrics.self,from:d);UserDefaults.standard.set(d,forKey:"snapshot");return m}catch{var m=UserDefaults.standard.data(forKey:"snapshot").flatMap{try? JSONDecoder().decode(Metrics.self,from:$0)} ?? Metrics();m.message="应用未运行";return m}
    }
}
struct RefreshVitals:AppIntent {static var title:LocalizedStringResource="刷新电脑状态";func perform()async throws->some IntentResult{_ = await Feed.get();WidgetCenter.shared.reloadTimelines(ofKind:Metrics.kind);return .result()}}
struct Provider:TimelineProvider {
    func placeholder(in context:Context)->VitalsEntry{VitalsEntry(date:Date(),data:.sample,preview:true)}
    func getSnapshot(in context:Context,completion:@escaping(VitalsEntry)->Void){if context.isPreview{completion(placeholder(in:context))}else{Task{completion(VitalsEntry(date:Date(),data:await Feed.get()))}}}
    func getTimeline(in context:Context,completion:@escaping(Timeline<VitalsEntry>)->Void){Task{let m=await Feed.get(),now=Date();let stale=max(now.addingTimeInterval(1),m.date.addingTimeInterval(91));completion(Timeline(entries:[VitalsEntry(date:now,data:m),VitalsEntry(date:stale,data:m)],policy:.after(now.addingTimeInterval(60))))}}
}
struct WidgetView:View {
    let entry:VitalsEntry
    @Environment(\.widgetFamily)var family
    var s:Metrics{entry.data};var ok:Bool{entry.preview || s.fresh(entry.date)};var small:Bool{family == .systemSmall};var large:Bool{family == .systemLarge}
    func item(_ label:String,_ value:String,_ color:Color)->some View{VStack(alignment:.leading,spacing:3){Text(label).font(.system(size:10)).foregroundStyle(.secondary);Text(value).font(.system(size:small ? 16:19,weight:.semibold,design:.rounded)).monospacedDigit().foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)}.frame(maxWidth:.infinity,alignment:.leading)}
    var body:some View {
        VStack(alignment:.leading,spacing:large ? 13:8){
            HStack{Image(systemName:"desktopcomputer").foregroundStyle(neon);Text("Mac 实时监测").font(.system(size:small ? 11:13,weight:.bold));Spacer(minLength:0);Button(intent:RefreshVitals()){Image(systemName:"arrow.clockwise")}.buttonStyle(.plain)}
            HStack(alignment:.bottom){item(s.powerLabel,Metrics.value(ok ? s.power:nil," W",decimals:1),neon);if !small{item("CPU",Metrics.value(ok ? s.cpu:nil,"%"),.white);item("内存",Metrics.value(ok ? s.memoryPercent:nil,"%"),violet)}}
            if small{HStack{item("CPU",Metrics.value(ok ? s.cpu:nil,"%"),.white);item("内存",Metrics.value(ok ? s.memoryPercent:nil,"%"),violet)}}else{HStack{item("CPU 温度",Metrics.value(ok ? s.cpuTemp:nil," °C",decimals:1),neon);item("↓ 下载",Metrics.rate(ok ? s.download:nil),.cyan);item("↑ 上传",Metrics.rate(ok ? s.upload:nil),violet)}}
            if large {Divider();HStack{item("GPU 温度",Metrics.value(ok ? s.gpuTemp:nil," °C",decimals:1),violet);item("内存已用",Metrics.value(ok ? s.memoryUsed.map{$0/1073741824}:nil," GB",decimals:1),.white);item("芯片功率",Metrics.value(ok ? s.chipPower:nil," W",decimals:1),neon)};VStack(alignment:.leading,spacing:8){Text("最近一分钟 · 功率").font(.system(size:10)).foregroundStyle(.secondary);SmoothLine(values:s.history).stroke(neon,style:StrokeStyle(lineWidth:2,lineCap:.round)).frame(maxHeight:.infinity)}.padding(10).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:12))}
            Spacer(minLength:0)
            HStack{Text(entry.preview ? "示例数据":ok ? "快照":"已过期 · 打开应用更新");Spacer(minLength:0);if s.date != .distantPast{Text(s.date,style:.time)}}.font(.system(size:9)).foregroundStyle(.secondary).lineLimit(1)
        }.padding(12).containerBackground(for:.widget){LinearGradient(colors:[Color(red:0.18,green:0.17,blue:0.34),Color(red:0.055,green:0.075,blue:0.13),Color(red:0.13,green:0.11,blue:0.26)],startPoint:.topLeading,endPoint:.bottomTrailing)}.foregroundStyle(.white).widgetURL(URL(string:"macvitals://card"))
    }
}
@main struct VitalsWidget:Widget {var body:some WidgetConfiguration{StaticConfiguration(kind:Metrics.kind,provider:Provider()){WidgetView(entry:$0)}.configurationDisplayName("Mac 实时监测").description("本机功率、CPU、内存、温度与网速。点击打开实时卡片。").supportedFamilies([.systemSmall,.systemMedium,.systemLarge]).contentMarginsDisabled()}}
