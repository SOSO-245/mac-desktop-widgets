import Foundation

private struct Failure: Error, CustomStringConvertible { let description: String }
private func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw Failure(description: message) }
}

@MainActor private final class Fixture {
    var secret = "synthetic-token"
    var profile = "active"
    var controller = "127.0.0.1:9090"
    func preferences() -> [String: Any] {
        ["currentProfileId": profile, "profiles": [["id": profile, "label": "Fixture", "currentGroupName": "Manual"]],
         "patchClashConfig": ["secret": secret, "external-controller": controller]]
    }
}

@MainActor private final class MockTransport: FlClashNodeTransport {
    var mode = "rule"
    var entries: [String: [String: Any]] = [
        "Manual": ["type": "Selector", "now": "A", "all": ["A", "B", "C", "D", "Auto", "DIRECT", "Local", "Denied"]],
        "Auto": ["type": "URLTest", "now": "C", "all": ["C", "D"]],
        "A": ["type": "Shadowsocks"], "B": ["type": "Vmess"], "C": ["type": "Trojan"], "D": ["type": "Hysteria2"],
        "DIRECT": ["type": "Direct"], "Local": ["type": "Direct"], "Denied": ["type": "Reject"]
    ]
    var requests: [URLRequest] = []
    var activeProbes = 0
    var peakProbes = 0
    var probeCalls = 0
    var probeDelay: UInt64 = 30_000_000
    var probeStatus = 200
    var delayValue: Any = 37
    var confirmSelection = true
    var forcedReadStatus: Int?
    var responseOrigin: URL?
    var beforeResponse: ((URLRequest) -> Void)?
    var putCount: Int { requests.filter { $0.httpMethod == "PUT" }.count }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let path = request.url!.path
        var code = 200
        var payload: [String: Any] = [:]
        if path.hasSuffix("/delay") {
            probeCalls += 1; activeProbes += 1; peakProbes = max(peakProbes, activeProbes)
            defer { activeProbes -= 1 }
            try await Task.sleep(nanoseconds: probeDelay)
            beforeResponse?(request)
            code = probeStatus; payload = ["delay": delayValue]
        } else {
            try await Task.sleep(nanoseconds: 1_000_000)
            beforeResponse?(request)
            if request.httpMethod == "PUT" {
                let group = String(path.dropFirst("/proxies/".count))
                let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: String]
                if confirmSelection { entries[group]?["now"] = body["name"] }
                code = 204
            } else if path == "/configs" { payload = ["mode": mode] }
            else if path == "/proxies" { payload = ["proxies": entries] }
            else { code = 404 }
            if let forcedReadStatus, request.httpMethod != "PUT" { code = forcedReadStatus }
        }
        let response = HTTPURLResponse(url: responseOrigin ?? request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (try JSONSerialization.data(withJSONObject: payload), response)
    }
}

// URLProtocol keeps every request in this process. It never forwards to a real
// FlClash endpoint and verifies cancellation of the actual URLSession task.
private final class HangingProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var starts = 0
    private static var stops = 0
    static func counts() -> (Int, Int) { lock.lock(); defer { lock.unlock() }; return (starts, stops) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.lock.lock(); Self.starts += 1; Self.lock.unlock() }
    override func stopLoading() { Self.lock.lock(); Self.stops += 1; Self.lock.unlock() }
}

private final class RedirectProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: "HTTP/1.1",
                                       headerFields: ["Location": "https://example.invalid/never-follow"])!
        client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: URL(string: "https://example.invalid/never-follow")!), redirectResponse: response)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main private enum NodeControlTests {
    @MainActor static func wait(_ condition: () -> Bool, _ message: String, milliseconds: Int = 3000) async throws {
        for _ in 0..<(milliseconds / 10) {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw Failure(description: message)
    }
    @MainActor static func ready(_ controller: FlClashNodeController) async throws {
        try await wait({ !controller.isLoading && !controller.isTesting }, "Controller never finished")
    }
    @MainActor static func main() async throws {
        var passed = 0
        func done(_ name: String) { passed += 1; print("PASS \(name)") }

        do {
            let mock = MockTransport()
            mock.entries["Cycle"] = ["type": "Selector", "now": "Cycle", "all": ["Cycle"]]
            mock.entries["Manual"]?["all"] = ["A", "A", "Auto", "Cycle", "DIRECT", "Local", "Denied", "missing"]
            mock.entries["GLOBAL"] = ["type": "Selector", "now": "A", "all": ["A"]]
            let catalog = try FlClashNodeCatalog.decode(configuration: ["mode": "rule"], payload: ["proxies": mock.entries])
            try check(!catalog.groups.contains { $0.name == "Auto" || $0.name == "GLOBAL" }, "Non-selector or inactive GLOBAL exposed")
            let options = catalog.groups.first { $0.name == "Manual" }!.options
            try check(options.filter { $0.name == "A" }.count == 1 && !options.contains { $0.name == "missing" }, "Duplicate/missing nodes exposed")
            let auto = options.first { $0.name == "Auto" }!
            try check(auto.isGroup && auto.resolvedNode == "C" && auto.path == ["Auto", "C"], "Nested route lost")
            try check(!options.first { $0.name == "Cycle" }!.canTest, "Cyclic group probe allowed")
            try check(options.filter { ["DIRECT", "Local", "Denied"].contains($0.name) }.allSatisfy { !$0.canTest }, "Direct/reject aliases probed")
            done("Only manual groups, nested route, duplicate/cycle and direct-alias filtering")
        }
        do {
            let notices = ["距离下次重置剩余：5 天", "ℹ️ 距 离 下 次 重 置 剩 余 ：５ 天", "距重置还有:5天",
                           "剩余流量：77.4 GB", "套餐到期：2027-07-23", "订阅已过期", "重置倒计时：5天", "77.4GB / 100GB",
                           "Traffic remaining: 77GB", "Expire at: 2027-07-23"]
            for name in notices { try check(ProxyNodeLabels.isInformation(name), "Missed subscription notice") }
            for name in ["香港 01 | 0.5x", "美国｜流量优化｜1x", "重置线路-日本", "法国 5 天试用", "Singapore 1Gbps/10Gbps"] {
                try check(!ProxyNodeLabels.isInformation(name), "Legitimate node falsely excluded")
            }
            let prefs = Fixture(), mock = MockTransport()
            for name in notices { mock.entries[name] = ["type": "Shadowsocks"] }
            mock.entries["Auto"] = ["type": "URLTest", "now": notices[0], "all": [notices[0], "C"]]
            mock.entries["Manual"]?["all"] = ["A", "B", "Auto"] + notices
            let controller = FlClashNodeController(readPreferences: prefs.preferences, transport: mock)
            controller.open(); try await ready(controller)
            try check(controller.groups.first?.options.map(\.name) == ["A", "B"], "Direct or nested notice remained selectable")
            try check(mock.probeCalls == 2, "Subscription notice was probed")
            controller.select(name: notices[0]); controller.select(name: "Auto")
            try check(mock.putCount == 0 && controller.selectingName == nil, "Hidden notice accepted for selection")
            controller.close()
            done("Subscription reset/quota/expiry notices excluded from candidates, nested routes, probes and selection")
        }
        do {
            let prefs = Fixture(), mock = MockTransport()
            var date = Date(timeIntervalSince1970: 1_800_000_000)
            let controller = FlClashNodeController(readPreferences: prefs.preferences, transport: mock, now: { date })
            controller.open()
            try await ready(controller)
            try check(controller.groups.count == 1 && controller.selectedGroupName == "Manual", "Wrong selected group")
            try check(mock.putCount == 0 && mock.peakProbes == 3, "Loading mutated state or concurrency not capped")
            try check(mock.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-token" }, "Unauthenticated request")
            try check(controller.latencies["B"]?.milliseconds == 37, "Missing synthetic result")
            let initial = mock.probeCalls
            controller.testAll(); try await ready(controller)
            try check(mock.probeCalls == initial, "Thirty-second cache missed")
            date = date.addingTimeInterval(31)
            controller.testAll(); try await ready(controller)
            try check(mock.probeCalls == initial * 2, "Expired cache reused")
            controller.close()
            done("No implicit PUT, Bearer on all paths, concurrency three and thirty-second cache")
        }
        do {
            let prefs = Fixture(), mock = MockTransport()
            let controller = FlClashNodeController(readPreferences: prefs.preferences, transport: mock)
            var callbacks = 0
            controller.onSelectionChanged = { callbacks += 1 }
            controller.open(); try await ready(controller)
            controller.select(name: "A")
            try await wait({ controller.selectingName == nil }, "Same-node selection stuck")
            try check(mock.putCount == 0, "Current node caused PUT")
            controller.select(name: "B"); controller.select(name: "D")
            try await wait({ controller.selectingName == nil }, "Selection stuck")
            try check(mock.putCount == 1 && mock.entries["Manual"]?["now"] as? String == "B", "Click was duplicated or not applied")
            try check(controller.groups.first?.selectedName == "B" && callbacks == 2, "Readback confirmation missing")
            try check(controller.notice?.contains("Manual") == true && controller.notice?.contains("B") == true, "Ambiguous success text")
            controller.close()
            done("Same node needs no PUT; explicit click sends one PUT and confirms group/name")
        }
        do {
            let prefs = Fixture(), mock = MockTransport()
            let controller = FlClashNodeController(readPreferences: prefs.preferences, transport: mock)
            controller.open(); try await ready(controller)
            mock.entries["Manual"]?["all"] = ["A"]
            controller.select(name: "B")
            try await wait({ controller.selectingName == nil }, "Membership preflight stuck")
            try check(mock.putCount == 0 && controller.error != nil, "Removed candidate was selected")
            mock.entries["Manual"]?["all"] = ["A", "B"]
            mock.entries["Manual"]?["type"] = "URLTest"
            controller.select(name: "B")
            try await wait({ controller.selectingName == nil }, "Type preflight stuck")
            try check(mock.putCount == 0, "Non-selector received PUT")
            controller.close()
            done("Live membership and Selector type are rechecked before mutation")
        }
        do {
            let prefs = Fixture(), mock = MockTransport()
            let controller = FlClashNodeController(readPreferences: prefs.preferences, transport: mock)
            controller.open(); try await ready(controller)
            mock.beforeResponse = { request in if request.url?.path == "/proxies" { prefs.secret = "changed-token" } }
            controller.select(name: "B")
            try await wait({ controller.selectingName == nil }, "Secret change preflight stuck")
            try check(mock.putCount == 0 && controller.error != nil, "Secret rotation did not prevent PUT")
            controller.close()
            done("Identity/secret rotation during selection preflight blocks PUT")
        }
        do {
            let prefs = Fixture(), mock = MockTransport()
            let controller = FlClashNodeController(readPreferences: prefs.preferences, transport: mock)
            var callbacks = 0
            controller.onSelectionChanged = { callbacks += 1 }
            controller.open(); try await ready(controller)
            mock.confirmSelection = false
            controller.select(name: "B")
            try await wait({ controller.selectingName == nil }, "Unconfirmed selection stuck")
            try check(mock.putCount == 1 && callbacks == 0 && controller.error != nil, "Unconfirmed mutation reported success or retried")
            controller.close()
            done("Unconfirmed PUT is reported honestly, never retried or published as success")
        }
        do {
            let prefs = Fixture(), mock = MockTransport()
            let controller = FlClashNodeController(readPreferences: prefs.preferences, transport: mock)
            var callbacks = 0
            controller.onSelectionChanged = { callbacks += 1 }
            controller.open(); try await ready(controller)
            mock.beforeResponse = { request in if request.httpMethod == "PUT" { prefs.profile = "another" } }
            controller.select(name: "B")
            try await wait({ controller.selectingName == nil }, "Identity change after PUT stuck")
            try check(mock.putCount == 1 && callbacks == 0 && controller.error != nil, "Previous identity mutation published success")
            controller.close()
            done("Identity change after dispatch suppresses stale success and never retries")
        }
        do {
            let prefs = Fixture(), mock = MockTransport()
            mock.probeStatus = 504
            let controller = FlClashNodeController(readPreferences: prefs.preferences, transport: mock)
            controller.open(); try await ready(controller)
            try check(controller.latencies["B"]?.state == .timeout && controller.latencies["B"]?.milliseconds == nil, "Timeout fabricated delay")
            mock.probeStatus = 200; mock.delayValue = -4
            controller.testAll(force: true); try await ready(controller)
            try check(controller.latencies["B"]?.state == .failed, "Invalid delay accepted")
            controller.close()
            done("Timeout and invalid delay never reuse stale numeric latency")
        }
        do {
            let prefs = Fixture(), mock = MockTransport()
            mock.probeDelay = 500_000_000
            let controller = FlClashNodeController(readPreferences: prefs.preferences, transport: mock)
            controller.open()
            try await wait({ mock.activeProbes == 3 }, "Probes did not start")
            prefs.profile = "another"
            try await wait({ !controller.isTesting && controller.error != nil }, "Identity change did not cancel probes")
            try check(controller.latencies.isEmpty && mock.putCount == 0, "Old identity results published")
            controller.close()
            try await wait({ mock.activeProbes == 0 }, "Probes continued after close")
            try check(controller.groups.isEmpty && controller.latencies.isEmpty, "Closed controller retained data")
            done("Identity change and close cancel workers and discard stale results")
        }
        do {
            let prefs = Fixture(), mock = MockTransport()
            mock.forcedReadStatus = 302
            let controller = FlClashNodeController(readPreferences: prefs.preferences, transport: mock)
            controller.open(); try await ready(controller)
            try check(controller.error != nil && mock.requests.count == 1, "Redirect accepted or followed")
            mock.forcedReadStatus = 401
            controller.refresh(); try await ready(controller)
            try check(controller.error?.contains("认证失败") == true, "401 not surfaced")
            mock.forcedReadStatus = nil; mock.responseOrigin = URL(string: "https://example.invalid/elsewhere")!
            controller.refresh(); try await ready(controller)
            try check(controller.groups.isEmpty && controller.error != nil, "Non-loopback response accepted")
            controller.close()
            done("Redirect, unauthenticated response and non-loopback response rejected")
        }
        do {
            let prefs = Fixture(), mock = MockTransport()
            prefs.secret = "header\r\ninjection"
            let controller = FlClashNodeController(readPreferences: prefs.preferences, transport: mock)
            controller.open(); try await ready(controller)
            try check(mock.requests.isEmpty && controller.error != nil, "CRLF secret reached transport")
            let encoded = try FlClashNodeController.encode(name: "组/日本 %.?&#")
            try check(!encoded.contains("/") && !encoded.contains("?") && encoded.contains("%2F") && encoded.contains("%25"), "Unsafe group path")
            controller.close()
            done("CRLF credentials refused and group path strictly escaped")
        }
        do {
            let transport = FlClashNodeURLTransport(protocolClasses: [HangingProtocol.self])
            let request = URLRequest(url: URL(string: "http://127.0.0.1:9090/never-real")!)
            let task = Task { try await transport.data(for: request) }
            try await wait({ HangingProtocol.counts().0 == 1 }, "URL task not started")
            task.cancel()
            _ = try? await task.value
            try await wait({ HangingProtocol.counts().1 == 1 }, "URLSession task was not cancelled")
            done("Cancellation propagates to actual URLSession task with no real network")
        }
        do {
            let transport = FlClashNodeURLTransport(protocolClasses: [RedirectProtocol.self])
            let request = URLRequest(url: URL(string: "http://127.0.0.1:9090/never-real")!)
            let (_, response) = try await transport.data(for: request)
            try check(response.statusCode == 302 && response.url?.host == "127.0.0.1", "URLSession followed external redirect")
            done("Production session delegate refuses redirect without forwarding credentials")
        }
        print("\(passed) node-control checks passed (synthetic only; no real PUT)")
    }
}
