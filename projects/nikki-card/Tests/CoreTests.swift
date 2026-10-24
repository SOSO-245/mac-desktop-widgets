import Foundation
@main struct CoreTests {
    static func main() async throws {
        var passed = 0
        func check(_ ok: @autoclosure () -> Bool, _ label: String) {
            precondition(ok(),label); passed += 1
        }
        for bad in ["file:///etc/passwd","https://u:p@example.com","http://host/ui/","http://host?secret=x","http://host/#x"] {
            check((try? ConnectionSettings.normalized(bad)) == nil,"reject URL")
        }
        check((try? ConnectionSettings.normalized(" http://127.0.0.1:9090/ ")) == "http://127.0.0.1:9090","normalize")
        let nodes: [String:[String:Any]] = ["组":["type":"Selector","now":"下一级"],"下一级":["type":"URLTest","now":"节点"],"节点":["type":"ss"],"环":["now":"环"],"平衡":["all":["节点"],"type":"LoadBalance"]]
        check(NikkiData.leaf("组",proxies:nodes) == "节点","nested leaf")
        check(NikkiData.leaf("环",proxies:nodes) == nil,"cycle")
        check(NikkiData.leaf("平衡",proxies:nodes) == nil,"unknown selection")
        var s = MonitorSnapshot()
        NikkiData.subscription(["subscriptionInfo":["Upload":20,"Download":30,"Total":200,"Expire":0]],snapshot:&s)
        check(s.usedBytes == 50 && s.totalBytes == 200 && s.expiresAt == nil,"provider stats")
        NikkiData.subscription(nil,snapshot:&s)
        check(s.usedBytes == nil && s.totalBytes == nil,"missing clears")
        check(NikkiData.number(true) == nil,"bool rejected")
        check(NikkiData.number(-1) == nil,"negative rejected")
        let f = ISO8601DateFormatter()
        check(NikkiData.recentDelay(["history":[["time":f.string(from:Date()),"delay":125]]]) == 125,"recent delay")
        check(NikkiData.recentDelay(["history":[["time":f.string(from:Date().addingTimeInterval(-601)),"delay":125]]]) == nil,"stale delay")
        check(NikkiData.recentDelay(["history":[["time":f.string(from:Date()),"delay":0]]]) == nil,"failed delay")
        check(MenuBarDisplay.remaining(used:50,total:200) == 0.75,"remaining quota")
        check(MenuBarDisplay.isSlow(milliseconds:2001),"slow threshold")
        guard CommandLine.arguments.count == 2, let port = Int(CommandLine.arguments[1]) else { fatalError("mock port required") }
        var options = MenuBarOptions()
        check(!options.isEmpty,"default menu visible")
        options.icon=false;options.site=false;options.latency=false;options.profile=false;options.quotaRing=false;options.quotaText=false
        check(options.isEmpty,"all hidden fallback")
        let roundtrip = try JSONDecoder().decode(MenuBarOptions.self,from:JSONEncoder().encode(options))
        check(roundtrip == options,"menu preference roundtrip")
        check(MenuBarDisplay.rate(2048) == "2 KB/s","rate format")
        let api = NikkiAPI(settings:ConnectionSettings(endpoint:"http://127.0.0.1:\(port)"),secret:"mock-only")
        defer { api.close() }
        let r = try api.request(["proxies","组 / # ?"])
        check(r.value(forHTTPHeaderField:"Authorization") == "Bearer mock-only","auth header")
        check(r.url?.query == nil && r.url!.absoluteString.contains("%2F"),"safe path")
        let ws = try api.request(["traffic"],websocket:true)
        check(ws.url?.scheme == "ws" && ws.value(forHTTPHeaderField:"Authorization") != nil,"ws auth")
        do { _ = try await api.json(["redirect"]); fatalError("followed redirect") } catch APIError.status(let code) { check(code == 302,"reject redirect") }
        do { try await api.select(group:"组 / # ?",node:"invalid"); fatalError("invalid node accepted") } catch APIError.message { passed += 1 }
        try await api.select(group:"组 / # ?",node:"目标 🇯🇵 / #")
        let result = try await api.json(["stats"])
        check(result["writes"] as? Int == 1,"exactly one switch")
        try await api.select(group:"组 / # ?",node:"目标 🇯🇵 / #")
        let again = try await api.json(["stats"])
        check(again["writes"] as? Int == 1,"already current no write")
        check(again["redirected"] as? Int == 0,"no redirect leak")
        print("PASS \(passed) checks; all writes restricted to loopback fixture")
    }
}
