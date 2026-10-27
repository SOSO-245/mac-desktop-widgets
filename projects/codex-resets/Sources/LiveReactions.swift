import AppKit
import SwiftUI

struct ReactionHeart:Identifiable {
    let id=UUID()
    let born:Date
    let drift:Double
    let rise:Double
    let size:Double
    let tilt:Double
    let burstAngle:Double
    let burstSpread:Double
    let burstDistance:Double
    init(born:Date=Date(),drift:Double=Double.random(in:-65...65),rise:Double=Double.random(in:65...155),size:Double=Double.random(in:12...21),tilt:Double=Double.random(in:-25...25)) {
        self.born=born;self.drift=drift;self.rise=rise;self.size=size;self.tilt=tilt
        burstAngle=Double.random(in:0..<(2 * .pi))
        burstSpread=Double.random(in:(.pi/3)...(5 * .pi/3))
        burstDistance=Double.random(in:24...44)
    }
}
@MainActor final class LiveReactions:ObservableObject {
    @Published var count:Int?
    @Published var connected=false
    @Published var hearts:[ReactionHeart]=[]
    @Published var since:Date?
    @Published var sending=false
    @Published var sendError=false
    private var ownRequests:Set<String>=[]
    private var active=false
    private var tracker=ReactionTracker()
    private var worker:Task<Void,Never>?
    private var socket:URLSessionWebSocketTask?
    private var pulse:Timer?
    private var pending=0
    private let session:URLSession
    let isDemo:Bool
    init(demo:Bool=false,session:URLSession?=nil) {
        isDemo=demo
        if demo {count=24047;since=Date()}
        if let session {self.session=session;return}
        let c=URLSessionConfiguration.ephemeral;c.timeoutIntervalForRequest=12;c.urlCache=nil;c.httpCookieStorage=nil
        self.session=URLSession(configuration:c)
    }
    func setActive(_ enabled:Bool) {
        guard active != enabled else{return};active=enabled
        if !enabled {worker?.cancel();worker=nil;socket?.cancel(with:.goingAway,reason:nil);socket=nil;pulse?.invalidate();pulse=nil;pending=0;hearts=[];connected=false;return}
        pulse=Timer.scheduledTimer(withTimeInterval:0.1,repeats:true) {[weak self] _ in Task {@MainActor in self?.emit()}}
        if isDemo {connected=true;pending=1;return}
        worker=Task {[weak self] in await self?.listen()}
    }
    private func receive(_ data:Data,animate:Bool,ownID:String?=nil) {
        guard active,data.count<262144,let value=try? JSONDecoder().decode(ReactionCount.self,from:data),value.valid else{return}
        var excluded=0
        if let ownID,ownRequests.remove(ownID) != nil {excluded+=1}
        if let object=try? JSONSerialization.jsonObject(with:data) as? [String:Any] {
            var ids=(object["events"] as? [[String:Any]] ?? []).compactMap {$0["request_id"] as? String}
            if let id=object["request_id"] as? String {ids.append(id)}
            for id in Set(ids) {if ownRequests.remove(id) != nil {excluded+=1}}
        }
        let delta=max(0,tracker.accept(value,animate:animate)-excluded)
        count=tracker.value?.count;since=tracker.value?.date
        // Bounded animation queue; never allocate a particle array from an untrusted counter.
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {pending=min(1000,pending+min(delta,1000))}
    }
    func thank() {
        if isDemo {
            count=(count ?? 24047)+1
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {pending=min(40,pending+1)}
            return
        }
        guard !sending else{return};sending=true;sendError=false
        let id=UUID().uuidString;ownRequests.insert(id)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {pending=min(1000,pending+1)}
        Task {
            do {
                var request=URLRequest(url:URL(string:"https://codex-resets.com/api/reset-requests")!,timeoutInterval:12)
                request.httpMethod="POST";request.setValue("application/json",forHTTPHeaderField:"Content-Type")
                request.setValue("https://codex-resets.com",forHTTPHeaderField:"Origin")
                request.setValue("application/json",forHTTPHeaderField:"Accept")
                request.httpBody=try JSONSerialization.data(withJSONObject:["request_id":id,"n":1])
                let (data,response)=try await session.data(for:request)
                guard let http=response as? HTTPURLResponse,(200..<300).contains(http.statusCode),data.count<262144,
                      let result=try? JSONDecoder().decode(ReactionCount.self,from:data),result.valid else {throw URLError(.badServerResponse)}
                receive(data,animate:true,ownID:id)
            } catch {sendError=true}
            sending=false
            // Leave the ID briefly for a delayed server echo; never retry a failed POST automatically.
            try? await Task.sleep(for:.seconds(30));ownRequests.remove(id)
        }
    }
    private func listen() async {
        var attempt=0
        while active && !Task.isCancelled {
            // Initial load and reconnection replace the baseline without replaying old reactions.
            if let (data,response)=try? await session.data(from:URL(string:"https://codex-resets.com/api/reset-requests")!),let http=response as? HTTPURLResponse,http.statusCode==200,!Task.isCancelled {receive(data,animate:false)}
            guard active,!Task.isCancelled else{return}
            let connection=session.webSocketTask(with:URL(string:"wss://codex-resets.com/api/reset-requests/live")!)
            connection.maximumMessageSize=262144;socket=connection;connection.resume()
            var initial=true
            do {
                while active && !Task.isCancelled {
                    let message=try await connection.receive()
                    guard !Task.isCancelled else{return}
                    let data:Data
                    switch message {case .data(let bytes):data=bytes;case .string(let text):data=Data(text.utf8);@unknown default:continue}
                    guard let object=try? JSONSerialization.jsonObject(with:data) as? [String:Any],object["type"] as? String=="reset-request-count" else {continue}
                    receive(data,animate:!initial);initial=false;connected=true;attempt=0
                }
            } catch {connected=false}
            connection.cancel(with:.goingAway,reason:nil)
            guard !Task.isCancelled else{return}
            attempt=min(attempt+1,4)
            try? await Task.sleep(for:.seconds(min(30,pow(2,Double(attempt)))))
        }
    }
    private func emit() {
        guard active,pending>0,hearts.count<40 else{return}
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {pending=0;return}
        let amount=min(pending,min(40-hearts.count,max(1,pending/20)))
        for _ in 0..<amount {
            let heart=ReactionHeart();hearts.append(heart);pending-=1
            Task {[weak self] in try? await Task.sleep(for:.seconds(3));self?.hearts.removeAll {$0.id==heart.id}}
        }
    }
}
struct ReactionOriginKey:PreferenceKey {
    static var defaultValue:Anchor<CGRect>? = nil
    static func reduce(value:inout Anchor<CGRect>?,nextValue:()->Anchor<CGRect>?) {
        if let next=nextValue() {value=next}
    }
}
struct ReactionBadge:View {
    @ObservedObject var feed:LiveReactions
    var compact=false
    var body:some View {
        HStack(spacing:4) {
            Button(action:feed.thank) {HStack(spacing:4) {
                Image(systemName:"heart.fill").foregroundStyle(.pink)
                    .anchorPreference(key:ReactionOriginKey.self,value:.bounds) {$0}
                Text(feed.since.map{Date().timeIntervalSince($0)<86400}==true ? "感谢":"期待重置")
                Text(feed.count.map{String($0.formatted())} ?? "—").monospacedDigit().contentTransition(.numericText()).animation(.easeOut(duration:0.25),value:feed.count)
            }}.buttonStyle(.plain).focusEffectDisabled().disabled(feed.sending).accessibilityLabel(feed.isDemo ? "演示点赞动画，不发送真实感谢":"发送一次感谢").help(feed.isDemo ? "仅本地演示，不发送真实感谢":"点击向原网站发送一次感谢")
            Spacer(minLength:0)
            Circle().fill(feed.connected ? Color.mint:Color.gray).frame(width:4,height:4)
            if feed.isDemo {Text("演示").foregroundStyle(.secondary)} else {Link(compact ? "来源 ↗":"Codex Resets ↗",destination:URL(string:"https://codex-resets.com/zh-CN")!).foregroundStyle(.secondary)}
        }.font(.system(size:9,weight:.medium)).lineLimit(1).minimumScaleFactor(0.7)
        .alert("感谢未发送",isPresented:$feed.sendError) {Button("知道了",role:.cancel) {}} message:{Text("原网站暂时未确认，请稍后再试。不会自动重复提交。监测到的计数保持真实来源。")}
        .help(feed.connected ? "原网站实时感谢数；爱心表示新增互动":"正在连接原网站，显示最近收到的计数")
    }
}
private struct FlyingReactionHeart:View {
    let particle:ReactionHeart
    let drift:Double
    @State private var flying=false
    var body:some View {
        Image(systemName:"heart.fill").font(.system(size:particle.size)).foregroundStyle(Color(red:1,green:0.35,blue:0.64))
            .rotationEffect(.degrees(flying ? particle.tilt:0)).scaleEffect(flying ? 1.2:0.6)
            .opacity(flying ? 0:0.95).offset(x:flying ? drift:0,y:flying ? -particle.rise:0)
            .onAppear {withAnimation(.easeOut(duration:1.9)) {flying=true}}
    }
}
struct ReactionHearts:View {
    @ObservedObject var feed:LiveReactions
    var origin:Anchor<CGRect>?
    var body:some View {
        GeometryReader { proxy in
            if let origin {
                let bounds=proxy[origin]
                ForEach(feed.hearts) { particle in
                    // Resolve the actual icon center after layout; no guessed card fractions.
                    // Keep sideways drift within the card when the icon sits near its left edge.
                    let margin=particle.size*0.65+3
                    let drift=max(margin-bounds.midX,min(particle.drift,proxy.size.width-margin-bounds.midX))
                    FlyingReactionHeart(particle:particle,drift:drift).position(x:bounds.midX,y:bounds.midY)
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true).clipped()
    }
}
