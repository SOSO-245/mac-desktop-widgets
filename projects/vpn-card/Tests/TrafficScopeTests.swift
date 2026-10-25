import Foundation
@main struct TrafficScopeTests {
    static func main() throws {
        var checks = 0
        func check(_ value: Bool, _ message: String) { precondition(value, message); checks += 1 }
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        func row(_ id: String, _ leaf: String, _ up: Double, _ down: Double, _ offset: Double = -10) -> [String: Any] {
            ["id":id, "chains":[leaf,"策略组"], "upload":up,"download":down,
             "start":ISO8601DateFormatter().string(from:start.addingTimeInterval(offset))]
        }
        func data(_ rows: [[String: Any]]) throws -> Data { try JSONSerialization.data(withJSONObject:["connections":rows]) }
        let types = ["本地出口":"Direct","阻止":"Reject","节点":"Shadowsocks"]
        var sampler = ProxyTrafficSampler()
        let first = try data([row("p","节点",100,200),row("d","DIRECT",1_000,2_000),row("a","本地出口",3_000,4_000)])
        check(sampler.sample(first,proxyTypes:types,time:10,date:start) == nil,"initial baseline")
        let second = try data([row("p","节点",120,260),row("d","DIRECT",9_000,20_000),row("a","本地出口",30_000,40_000)])
        let rate = sampler.sample(second,proxyTypes:types,time:12,date:start.addingTimeInterval(2))!
        check(rate.uploadBps == 10 && rate.downloadBps == 30,"exclude direct and custom direct; elapsed time")
        let changed = try data([row("p","节点",140,300), row("new","节点",50,90,3),row("old","节点",9_999_999,9_999_999)])
        let newRate = sampler.sample(changed,proxyTypes:types,time:14,date:start.addingTimeInterval(4))!
        check(newRate.uploadBps == 35 && newRate.downloadBps == 65,"new interval connection; never old cumulative spike")
        let empty = try data([])
        let closed = sampler.sample(empty,proxyTypes:types,time:15,date:start.addingTimeInterval(5))!
        check(closed.uploadBps == 0 && closed.downloadBps == 0,"closing connections never produce negative spikes")
        check(sampler.sample(empty,proxyTypes:types,time:30,date:start.addingTimeInterval(20)) == nil,"stale gap resets")
        check(sampler.sample(empty,proxyTypes:types,time:29,date:start.addingTimeInterval(21)) == nil,"monotonic rollback")
        check(sampler.sample(Data("{}".utf8),proxyTypes:types,time:31,date:start) == nil,"missing array invalid")
        check(sampler.sample(first,proxyTypes:types,time:32,date:start) == nil,"invalid packet resets baseline")
        check(sampler.sample(try data([row("p","节点",1,2)]),proxyTypes:types,time:33,date:start) == nil,"counter reset no spike")
        check(!ProxyTrafficSampler.isProxy(["DIRECT","代理选择"],types:types),"actual leaf direct")
        check(ProxyTrafficSampler.isProxy(["节点","DIRECT"],types:types),"group name is not leaf")
        check(!ProxyTrafficSampler.isProxy(["阻止"],types:types),"custom reject")
        check(!ProxyTrafficSampler.isProxy(["REJECT-DROP"],types:types),"builtin reject drop")
        check(ProxyTrafficSampler.isProxy(["订阅专用节点"],types:types),"provider-only outbound")
        check(!ProxyTrafficSampler.isProxy([],types:types),"empty chain")
        var bad = row("bad","节点",1,2); bad["upload"] = true
        check(sampler.sample(try data([bad]),proxyTypes:types,time:34,date:start) == nil,"boolean rejected")
        check(sampler.sample(try data([row("x","节点",1,2),row("x","节点",3,4)]),proxyTypes:types,time:35,date:start) == nil,"duplicate id rejected")
        var nullSampler = ProxyTrafficSampler()
        let null = Data("{\"connections\":null}".utf8)
        check(nullSampler.sample(null,proxyTypes:types,time:1,date:start) == nil,"null empty baseline")
        check(nullSampler.sample(null,proxyTypes:types,time:2,date:start)?.downloadBps == 0,"null means no active connections")
        var changedSampler = ProxyTrafficSampler()
        _ = changedSampler.sample(first,proxyTypes:types,time:1,date:start)
        check(changedSampler.sample(try data([row("p","新节点",10000,20000)]),proxyTypes:types,time:2,date:start)?.downloadBps == 0,"chain change baseline")
        check(MonitorSnapshot(client:.shadowrocket).trafficLabel == "隧道总流量","Shadowrocket honest scope")
        print("Traffic scope checks: \(checks) passed")
    }
}
