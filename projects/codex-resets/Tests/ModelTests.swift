import Foundation

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try condition() == false { throw TestFailure(description: message) }
}

private func date(_ value: String) -> Date {
    ISO8601DateFormatter().date(from: value)!
}

/// Every request made by the test session is intercepted. No public API is called.
private final class StubURLProtocol: URLProtocol {
    struct Reply {
        var code = 200
        var headers: [String: String] = [:]
        var data = Data()
        var error: URLError?
    }
    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var replies: [String: [Reply]] = [:]
        private var seen: [URLRequest] = []
        func configure(_ replies: [String: [Reply]]) {
            lock.lock(); defer { lock.unlock() }
            self.replies = replies
            seen = []
        }
        func take(_ request: URLRequest) -> Reply {
            lock.lock(); defer { lock.unlock() }
            seen.append(request)
            let path = request.url!.path
            guard var queue = replies[path], !queue.isEmpty else {
                return Reply(error: URLError(.unsupportedURL))
            }
            let reply = queue.removeFirst()
            replies[path] = queue
            return reply
        }
        var requests: [URLRequest] {
            lock.lock(); defer { lock.unlock() }
            return seen
        }
    }
    static let state = State()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let reply = Self.state.take(request)
        if let error = reply.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.code, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private struct TestCache: Decodable {
    let data: Data
    let etag: String?
    let checkedAt: Date
}

private final class Harness {
    let suite = "local.codexresets.ModelTests." + UUID().uuidString
    let defaults: UserDefaults
    let session: URLSession
    let store: ResetStore
    init() {
        defaults = UserDefaults(suiteName: suite)!
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
        store = ResetStore(session: session, defaults: defaults)
    }
    deinit {
        session.invalidateAndCancel()
        defaults.removePersistentDomain(forName: suite)
    }
    func cache(_ endpoint: String) throws -> TestCache {
        let bytes = defaults.data(forKey: "public-api-v1-" + endpoint)!
        return try JSONDecoder().decode(TestCache.self, from: bytes)
    }
    func rawCache(_ endpoint: String) -> Data? { defaults.data(forKey: "public-api-v1-" + endpoint) }
}

@main
private enum ModelTests {
    static let statusPath = "/api/v1/status"
    static let historyPath = "/api/v1/resets"
    static let historyKey = "resets?limit=3&order=desc"
    static var fixtures: URL { URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true) }
    static func fixture(_ name: String) throws -> Data { try Data(contentsOf: fixtures.appendingPathComponent(name)) }
    static func liveStatus() throws -> ResetStatus {
        try ResetJSON.decoder().decode(APIEnvelope<ResetStatus>.self, from: fixture("status-live.json")).data
    }
    static func mutateStatus(_ mutation: (inout [String: Any]) -> Void) throws -> Data {
        var json = try JSONSerialization.jsonObject(with: fixture("status-live.json")) as! [String: Any]
        mutation(&json)
        return try JSONSerialization.data(withJSONObject: json)
    }
    static func decodeSnapshot(_ bytes: Data) throws -> ResetSnapshot {
        let envelope = try ResetJSON.decoder().decode(APIEnvelope<ResetStatus>.self, from: bytes)
        return ResetSnapshot(status: envelope.data, history: [], checkedAt: nil, generatedAt: envelope.meta.generatedAt, issue: nil)
    }
    static func configure(status: StubURLProtocol.Reply, history: StubURLProtocol.Reply) {
        StubURLProtocol.state.configure([statusPath: [status], historyPath: [history]])
    }
    static func configureGood() throws {
        // Deliberately return history in reverse order to exercise client sorting.
        var history = try JSONSerialization.jsonObject(with: fixture("resets-live.json")) as! [String: Any]
        history["data"] = Array((history["data"] as! [[String: Any]]).reversed())
        configure(status: .init(headers: ["ETag": "\"status-v1\""], data: try fixture("status-live.json")), history: .init(headers: ["ETag": "\"history-v1\""], data: try JSONSerialization.data(withJSONObject: history)))
    }

    static func main() async throws {
        var passed = 0
        func run(_ name: String, _ operation: () async throws -> Void) async throws {
            try await operation()
            passed += 1
            print("PASS \(name)")
        }
        try await run("Live and null fixtures decode; dates preserve their timezone") {
            let live = try liveStatus()
            try check(live.stats.total == 64 && live.stats.avgIntervalDays == 6.3, "Live stats did not decode")
            try check(live.latestReset?.announcedAt == date("2026-10-20T06:33:48Z"), "Fractional UTC timestamp changed")
            let empty = try decodeSnapshot(fixture("status-null.json"))
            try check(empty.status?.latestReset == nil && empty.status?.stats.lastResetAt == nil, "Null values must stay nil")
            try check(empty.phase(at: Date()) == .noSchedule, "An empty valid status should not invent a reset")
            let history = try ResetJSON.decoder().decode(APIEnvelope<[ResetEvent]>.self, from: fixture("resets-empty.json"))
            try check(history.data.isEmpty, "Empty history must decode")
            let offset = Data("{\"api_version\":\"v1\",\"generated_at\":\"2026-10-23T01:00:00+08:00\"}".utf8)
            let decoded = try ResetJSON.decoder().decode(APIMeta.self, from: offset)
            try check(decoded.generatedAt == date("2026-10-22T17:00:00Z"), "UTC offset conversion is wrong")
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
            let local = calendar.dateComponents([.day, .hour], from: live.scheduledReset!.scheduledFor!)
            try check(local.day == 23 && local.hour == 1, "Shanghai schedule should be the next day at 01:00")
        }
        try await run("Scheduled future, exact deadline, overdue and unknown time remain distinct") {
            let snapshot = try decodeSnapshot(fixture("status-live.json"))
            let deadline = date("2026-10-22T17:00:00Z")
            try check(snapshot.phase(at: deadline.addingTimeInterval(-1)) == .scheduled(deadline), "Future schedule is missing")
            try check(snapshot.phase(at: deadline) == .awaitingConfirmation, "Exact deadline must await confirmation")
            try check(snapshot.phase(at: deadline.addingTimeInterval(86400)) == .awaitingConfirmation, "Expired schedule must not be treated as a completed reset")
            try check(snapshot.status?.stats.total == 64, "Elapsed schedule changed total")
            let bytes = try mutateStatus { root in
                var data = root["data"] as! [String: Any]
                var scheduled = data["scheduled_reset"] as! [String: Any]
                scheduled["scheduled_for"] = NSNull(); data["scheduled_reset"] = scheduled; root["data"] = data
            }
            try check(try decodeSnapshot(bytes).phase(at: deadline) == .unscheduledTime, "Unknown schedule time must not look overdue")
        }
        try await run("A watch expires and a confirmed schedule takes precedence") {
            let expiry = date("2026-10-22T18:00:00Z")
            let bytes = try mutateStatus { root in
                var data = root["data"] as! [String: Any]
                data["scheduled_reset"] = NSNull()
                data["active_watch"] = ["level": "elevated", "reset_chance_percent": 65, "forecast_window": "test", "observed_at": "2026-10-22T15:00:00Z", "expires_at": "2026-10-22T18:00:00Z", "text": "test", "source": ["type": "observed"]]
                root["data"] = data
            }
            let snapshot = try decodeSnapshot(bytes)
            try check(snapshot.phase(at: expiry.addingTimeInterval(-1)) == .watching, "Valid watch was ignored")
            try check(snapshot.phase(at: expiry) == .noSchedule, "Watch must expire exactly at expires_at")
            try check(snapshot.phase(at: expiry.addingTimeInterval(3600)) == .noSchedule, "Expired watch remains active")
            let withSchedule = try mutateStatus { root in
                var data = root["data"] as! [String: Any]
                data["active_watch"] = ["expires_at": "2026-10-22T18:00:00Z"]
                root["data"] = data
            }
            let scheduled = try decodeSnapshot(withSchedule)
            try check(scheduled.phase(at: date("2026-10-22T16:00:00Z")) == .scheduled(date("2026-10-22T17:00:00Z")), "Watch overrode an explicit schedule")
        }
        try await run("Observed sources and unknown reset types are forward compatible") {
            let bytes = try mutateStatus { root in
                var data = root["data"] as! [String: Any]
                var latest = data["latest_reset"] as! [String: Any]
                latest["source"] = ["type": "observed"]
                latest["reset_type"] = "future-type"
                latest["new_optional_field"] = true
                data["latest_reset"] = latest; root["data"] = data
            }
            let snapshot = try decodeSnapshot(bytes)
            try check(snapshot.status?.latestReset?.source.url == nil, "Observed source should not require a URL")
            try check(snapshot.status?.latestReset?.typeLabel == "额度重置", "Unknown type must not break the whole status")
        }
        try await run("HTTP 200 saves independent status/history with ETags") {
            let h = Harness(); try configureGood()
            let snapshot = await h.store.load(force: true)
            try check(snapshot.status?.stats.total == 64 && snapshot.history.count == 5 && snapshot.issue == nil, "Valid responses did not produce a healthy snapshot")
            try check(snapshot.history.map(\.announcedAt) == snapshot.history.map(\.announcedAt).sorted(by: >), "History is not newest first")
            try check(try h.cache("status").etag == "\"status-v1\"", "Status ETag not persisted")
            try check(try h.cache(historyKey).etag == "\"history-v1\"", "History ETag not persisted")
            try check(StubURLProtocol.state.requests.count == 2, "Unexpected number of requests")
            for request in StubURLProtocol.state.requests {
                try check(request.cachePolicy == .reloadIgnoringLocalCacheData, "Refresh must bypass the 4-hour local HTTP cache")
                try check(request.value(forHTTPHeaderField: "Accept") == "application/json", "JSON Accept header missing")
            }
            let historyURL = StubURLProtocol.state.requests.first { $0.url?.path == historyPath }!.url!
            let query = URLComponents(url: historyURL, resolvingAgainstBaseURL: false)!.queryItems!
            try check(query.contains(URLQueryItem(name: "limit", value: "3")) && query.contains(URLQueryItem(name: "order", value: "desc")), "History request must stay bounded")
        }
        try await run("HTTP 304 reuses content, sends ETags and advances only checkedAt") {
            let h = Harness(); try configureGood()
            let first = await h.store.load(force: true)
            let original = try h.cache("status")
            configure(status: .init(code: 304), history: .init(code: 304))
            let second = await h.store.load(force: true)
            let saved = try h.cache("status")
            try check(second.status?.stats.total == first.status?.stats.total && second.issue == nil, "304 should remain healthy")
            try check(saved.data == original.data && saved.etag == original.etag, "304 changed payload or lost ETag")
            try check(saved.checkedAt >= original.checkedAt && second.generatedAt == first.generatedAt, "304 must refresh check time, not source generation time")
            let requests = StubURLProtocol.state.requests
            try check(requests.first { $0.url?.path == statusPath }?.value(forHTTPHeaderField: "If-None-Match") == "\"status-v1\"", "Status conditional header missing")
            try check(requests.first { $0.url?.path == historyPath }?.value(forHTTPHeaderField: "If-None-Match") == "\"history-v1\"", "History conditional header missing")
        }
        try await run("Malformed HTTP 200 never overwrites the last valid cache") {
            let h = Harness(); try configureGood(); _ = await h.store.load(force: true)
            let statusCache = h.rawCache("status"), historyCache = h.rawCache(historyKey)
            configure(status: .init(data: Data("{\"data\":".utf8)), history: .init(data: Data("not-json".utf8)))
            let snapshot = await h.store.load(force: true)
            try check(snapshot.status?.stats.total == 64 && snapshot.history.count == 5 && snapshot.issue != nil, "Malformed response did not fall back to cache")
            try check(h.rawCache("status") == statusCache && h.rawCache(historyKey) == historyCache, "Bad JSON overwrote valid cache")
            try check(snapshot.freshness(at: Date()) == "缓存", "Fallback must be visibly cached")
        }
        try await run("Unsupported API versions never overwrite a valid status") {
            let h = Harness(); try configureGood(); _ = await h.store.load(force: true)
            let previous = h.rawCache("status")
            let invalid = try mutateStatus { root in
                var meta = root["meta"] as! [String: Any]; meta["api_version"] = "v999"; root["meta"] = meta
            }
            configure(status: .init(data: invalid), history: .init(code: 304))
            let snapshot = await h.store.load(force: true)
            try check(snapshot.status?.stats.total == 64 && snapshot.issue != nil && h.rawCache("status") == previous, "Unknown API version replaced known-good data")
        }
        try await run("Offline with cache preserves both endpoints; offline without cache stays empty") {
            let h = Harness(); try configureGood(); _ = await h.store.load(force: true)
            let previous = h.rawCache("status")
            configure(status: .init(error: URLError(.notConnectedToInternet)), history: .init(error: URLError(.notConnectedToInternet)))
            let cached = await h.store.load(force: true)
            try check(cached.status?.stats.total == 64 && cached.history.count == 5 && cached.issue != nil, "Offline data disappeared")
            try check(h.rawCache("status") == previous, "Offline refresh altered cache")
            let empty = Harness()
            configure(status: .init(error: URLError(.notConnectedToInternet)), history: .init(error: URLError(.notConnectedToInternet)))
            let unavailable = await empty.store.load(force: true)
            try check(unavailable.status == nil && unavailable.history.isEmpty && unavailable.phase(at: Date()) == .unavailable, "No-cache failure must not display sample data")
            try check(unavailable.freshness(at: Date()) == "连接失败" && !unavailable.isSample, "No-cache failure is mislabeled")
        }
        try await run("304 without cache is unavailable rather than manufactured data") {
            let h = Harness(); configure(status: .init(code: 304), history: .init(code: 304))
            let snapshot = await h.store.load(force: true)
            try check(snapshot.status == nil && snapshot.history.isEmpty && snapshot.issue != nil, "Unusable 304 fabricated a result")
            try check(h.rawCache("status") == nil && h.rawCache(historyKey) == nil, "Unusable 304 wrote a cache")
        }
        try await run("A history failure preserves new status and old history") {
            let h = Harness(); try configureGood(); _ = await h.store.load(force: true)
            let next = try mutateStatus { root in
                var data = root["data"] as! [String: Any]
                var stats = data["stats"] as! [String: Any]; stats["total"] = 65
                data["stats"] = stats; root["data"] = data
            }
            configure(status: .init(data: next), history: .init(code: 503))
            let snapshot = await h.store.load(force: true)
            try check(snapshot.status?.stats.total == 65 && snapshot.history.count == 5, "Partial failure discarded successful status or cached history")
            try check(snapshot.issue == "历史记录暂未更新", "Partial failure is not identified")
        }
        try await run("429 Retry-After blocks even force refresh while preserving cache") {
            let h = Harness(); try configureGood(); _ = await h.store.load(force: true)
            configure(status: .init(code: 429, headers: ["Retry-After": "120"]), history: .init(code: 429, headers: ["Retry-After": "120"]))
            let limited = await h.store.load(force: true)
            try check(limited.status?.stats.total == 64 && limited.issue != nil, "Rate limit discarded cached data")
            let count = StubURLProtocol.state.requests.count
            let retried = await h.store.load(force: true)
            try check(count == 2 && StubURLProtocol.state.requests.count == count, "Force refresh bypassed Retry-After")
            try check(retried.status?.stats.total == 64, "Backoff discarded cached status")
        }
        try await run("429 backoff survives rebuilding ResetStore and clears after expiry") {
            let h = Harness(); try configureGood(); _ = await h.store.load(force: true)
            configure(status: .init(code: 429, headers: ["Retry-After": "120"]), history: .init(code: 429, headers: ["Retry-After": "120"]))
            _ = await h.store.load(force: true)
            let statusKey = "public-api-retry-status"
            let historyRetryKey = "public-api-retry-" + historyKey
            try check((h.defaults.object(forKey: statusKey) as? Date ?? .distantPast) > Date(), "Status backoff deadline is not persisted")
            try check((h.defaults.object(forKey: historyRetryKey) as? Date ?? .distantPast) > Date(), "History backoff deadline is not persisted")
            let restarted = ResetStore(session: h.session, defaults: h.defaults)
            StubURLProtocol.state.configure([:])
            let snapshot = await restarted.load(force: true)
            try check(StubURLProtocol.state.requests.isEmpty && snapshot.status?.stats.total == 64 && snapshot.issue != nil, "Rebuilt store bypassed persistent backoff")
            // Advance persisted deadlines instead of making the suite wait in real time.
            h.defaults.set(Date.distantPast, forKey: statusKey)
            h.defaults.set(Date.distantPast, forKey: historyRetryKey)
            configure(status: .init(code: 304), history: .init(code: 304))
            let recovered = await restarted.load(force: true)
            try check(StubURLProtocol.state.requests.count == 2 && recovered.issue == nil, "Expired backoff blocked recovery")
            try check(h.defaults.object(forKey: statusKey) == nil && h.defaults.object(forKey: historyRetryKey) == nil, "Successful response did not clear persisted backoff")
        }
        try await run("Recent successful cache suppresses redundant automatic network calls") {
            let h = Harness(); try configureGood(); _ = await h.store.load(force: true)
            StubURLProtocol.state.configure([:])
            let snapshot = await h.store.load()
            try check(StubURLProtocol.state.requests.isEmpty && snapshot.issue == nil, "Automatic load ignored the short local throttle")
        }
        try await run("Freshness separates sample, source staleness and network failure") {
            let now = date("2026-10-22T16:00:00Z")
            var snapshot = try decodeSnapshot(fixture("status-live.json"))
            snapshot.checkedAt = now; snapshot.generatedAt = now
            try check(snapshot.freshness(at: now) == "已更新", "Healthy current snapshot is not fresh")
            snapshot.generatedAt = now.addingTimeInterval(-21601)
            try check(snapshot.freshness(at: now) == "缓存", "Old source snapshot should not look current")
            snapshot.isSample = true
            try check(snapshot.freshness(at: now) == "示例", "Preview must always identify sample data")
        }
        try await run("Small widgets omit clock ticks but retain an independent reset deadline") {
            let now = date("2026-10-22T15:59:30Z")
            let deadline = date("2026-10-22T16:00:17Z")
            let emptyDates = ResetTimelineDates.dates(now: now, snapshot: .empty, showClock: false)
            try check(emptyDates == [now, now.addingTimeInterval(3601)], "No-clock widget must not receive per-minute entries")
            let bytes = try mutateStatus { root in
                var data = root["data"] as! [String: Any]
                var scheduled = data["scheduled_reset"] as! [String: Any]
                scheduled["scheduled_for"] = "2026-10-22T16:00:17Z"
                data["scheduled_reset"] = scheduled; root["data"] = data
            }
            let snapshot = try decodeSnapshot(bytes)
            let dates = ResetTimelineDates.dates(now: now, snapshot: snapshot, showClock: false)
            try check(dates.contains(deadline) && dates.count == 3, "Small widget lost the non-minute deadline or added clock ticks")
            try check(snapshot.phase(at: deadline) == .awaitingConfirmation, "Deadline entry must show confirmation rather than a finished reset")
        }
        try await run("Clock timeline crosses local midnight, preserves exact events and deduplicates boundaries") {
            let now = date("2026-10-22T15:59:30Z") // 23:59:30 in Shanghai.
            let midnight = date("2026-10-22T16:00:00Z")
            let deadline = date("2026-10-22T16:00:17Z")
            let ninetySecondsLater = date("2026-10-22T16:01:00Z")
            let bytes = try mutateStatus { root in
                var data = root["data"] as! [String: Any]
                var scheduled = data["scheduled_reset"] as! [String: Any]
                scheduled["scheduled_for"] = "2026-10-22T16:00:17Z"
                data["scheduled_reset"] = scheduled
                // Watch expiry deliberately coincides with a clock minute.
                data["active_watch"] = ["expires_at": "2026-10-22T16:01:00Z"]
                root["data"] = data
            }
            let snapshot = try decodeSnapshot(bytes)
            let dates = ResetTimelineDates.dates(now: now, snapshot: snapshot, showClock: true)
            try check(dates.first == now && dates == dates.sorted() && Set(dates).count == dates.count, "Timeline dates must be sorted and unique")
            try check(dates.contains(midnight) && dates.contains(ninetySecondsLater), "Clock must advance at midnight and still update 90 seconds later")
            try check(dates.contains(deadline), "Minute ticks must not round away an exact scheduled deadline")
            try check(dates.filter { $0 == ninetySecondsLater }.count == 1, "Coincident watch expiry and minute produced duplicate entries")
            try check(dates.contains(date("2026-10-22T16:59:00Z")), "Clock should retain one hour of minute updates when the system postpones network refresh")
            try check(!dates.contains(date("2026-10-22T17:00:00Z")) && dates.count <= 64,
                      "Clock runway must stay bounded so the desktop host can accept the timeline archive")
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
            let displayed = calendar.dateComponents([.day, .hour, .minute], from: ninetySecondsLater)
            try check(displayed.day == 23 && displayed.hour == 0 && displayed.minute == 1, "Clock entry lost the local date transition")
        }
        try await run("Clock runway stays on minute boundaries and within the one-hour archive budget") {
            let minute = date("2026-10-22T16:00:00Z")
            for seconds in [0.0, 30.0, 59.0] {
                let now = minute.addingTimeInterval(seconds)
                let dates = ResetTimelineDates.dates(now: now, snapshot: .empty, showClock: true)
                let ticks = dates.filter {
                    $0 > now && $0 <= minute.addingTimeInterval(3600)
                        && $0.timeIntervalSince1970.truncatingRemainder(dividingBy: 60) == 0
                }
                try check(dates.first == now && Set(dates).count == dates.count && dates == dates.sorted(),
                          "Timeline must start immediately without duplicate or unsorted entries")
                try check(ticks.count == 60 && dates.count <= 62, "Empty clock timeline exceeded its one-hour entry budget")
                try check(ticks.first == minute.addingTimeInterval(60), "First clock tick must be the next full minute")
                try check(ticks.last == minute.addingTimeInterval(3600), "Clock stopped before the final minute of its one-hour runway")
                try check(zip(ticks, ticks.dropFirst()).allSatisfy { pair in pair.1.timeIntervalSince(pair.0) == 60 },
                          "Clock ticks must advance every minute without gaps")
                try check(dates.last == now.addingTimeInterval(3601), "Freshness transition must remain after the clock runway")
            }
        }
        try await run("Clock archive budget retains independent reset, watch and stale transitions") {
            let now = date("2026-10-22T15:59:30Z")
            let deadline = date("2026-10-22T16:00:17Z")
            let watchExpiry = date("2026-10-22T16:01:19Z")
            let staleAt = now.addingTimeInterval(3601)
            let bytes = try mutateStatus { root in
                var data = root["data"] as! [String: Any]
                var scheduled = data["scheduled_reset"] as! [String: Any]
                scheduled["scheduled_for"] = "2026-10-22T16:00:17Z"
                data["scheduled_reset"] = scheduled
                data["active_watch"] = ["expires_at": "2026-10-22T16:01:19Z"]
                root["data"] = data
            }
            var snapshot = try decodeSnapshot(bytes)
            snapshot.checkedAt = now; snapshot.generatedAt = now
            let dates = ResetTimelineDates.dates(now: now, snapshot: snapshot, showClock: true)
            try check(dates.count <= 64, "Clock plus independent events exceeded the desktop archive entry budget")
            try check(dates.contains(deadline) && dates.contains(watchExpiry) && dates.contains(staleAt),
                      "Reducing clock entries must preserve exact reset, watch and freshness transitions")
            try check(snapshot.phase(at: deadline.addingTimeInterval(-1)) == .scheduled(deadline)
                      && snapshot.phase(at: deadline) == .awaitingConfirmation,
                      "Exact reset deadline must change the card to awaiting confirmation")
            try check(!snapshot.isStale(at: now.addingTimeInterval(3600)) && snapshot.isStale(at: staleAt),
                      "Freshness event must mark cached data after its one-hour limit")
        }
        try await run("Widget links support cached timelines without forwarding untrusted destinations") {
            for value in ["codexresets://website", "https://codex-resets.com/zh-CN"] {
                try check(ResetNavigation.websiteDestination(for: URL(string: value)!) == resetsWebsite,
                          "Current or cached widget link no longer opens the website")
            }
            for value in ["codexresets://settings", "codexresets://website?url=https://example.com",
                          "https://codex-resets.com.evil.example/zh-CN", "https://example.com/zh-CN",
                          "file:///etc/hosts", "codexresets://website/unexpected"] {
                try check(ResetNavigation.websiteDestination(for: URL(string: value)!) == nil,
                          "Unexpected URL can launch a browser destination")
            }
        }
        try await run("Corrupt cache repairs itself without conditional requests or deleting unrelated preferences") {
            for corruptEnvelope in [false, true] {
                let h = Harness()
                let key = "public-api-v1-status"
                let corrupt: Data
                if corruptEnvelope {
                    corrupt = try JSONSerialization.data(withJSONObject: [
                        "data": Data("invalid-json".utf8).base64EncodedString(),
                        "etag": "broken-etag", "checkedAt": Date().timeIntervalSinceReferenceDate
                    ])
                } else { corrupt = Data("invalid-cache".utf8) }
                h.defaults.set(corrupt, forKey: key)
                h.defaults.set("keep", forKey: "unrelated-setting")
                h.defaults.set(Date().addingTimeInterval(-60), forKey: "public-api-retry-status")
                StubURLProtocol.state.configure([
                    statusPath: [.init(data: try fixture("status-live.json"))],
                    historyPath: [.init(error: URLError(.notConnectedToInternet))]
                ])
                let result = await h.store.load()
                try check(result.status != nil, "Broken cache prevented a fresh fetch")
                let request = StubURLProtocol.state.requests.first { $0.url?.path == statusPath }
                try check(request?.value(forHTTPHeaderField: "If-None-Match") == nil, "Broken ETag was reused")
                try check(h.defaults.string(forKey: "unrelated-setting") == "keep", "Maintenance changed unrelated state")
                try check(h.defaults.object(forKey: "public-api-retry-status") == nil, "Expired backoff survived")
                try check(h.rawCache("status") != corrupt, "Valid response failed to replace corrupt cache")
            }
        }
        try await run("Status bar counts real seconds and never invents a reset deadline") {
            let now = Date()
            var snapshot = ResetSnapshot.sample
            snapshot.isSample = false
            let deadline = snapshot.status!.scheduledReset!.scheduledFor!
            let first = ResetMenuDisplay.make(snapshot:snapshot,now:deadline.addingTimeInterval(-61))
            let next = ResetMenuDisplay.make(snapshot:snapshot,now:deadline.addingTimeInterval(-60))
            snapshot.checkedAt = deadline.addingTimeInterval(-60)
            snapshot.generatedAt = deadline.addingTimeInterval(-60)
            let fresh = ResetMenuDisplay.make(snapshot:snapshot,now:deadline.addingTimeInterval(-60))
            try check(first.text.hasSuffix("00:01:01") && next.text.hasSuffix("00:01:00"), "Countdown not ticking by seconds")
            try check(fresh.tone == .pink, "Fresh explicit schedule is not pink")
            try check(ResetMenuDisplay.make(snapshot:snapshot,now:deadline).tone == .neutral, "Expired deadline remained green")
            try check(ResetMenuDisplay.make(snapshot:snapshot,now:deadline).text == "重置待确认", "Expired deadline inferred another reset")
            snapshot.issue = "offline"
            try check(ResetMenuDisplay.make(snapshot:snapshot,now:deadline.addingTimeInterval(-30)).tone == .neutral, "Cached schedule falsely confirmed")
            snapshot.status = ResetStatus(latestReset:nil,scheduledReset:ScheduledReset(id:"test",status:"scheduled",resetType:"regular",announcedAt:now,scheduledFor:nil),activeWatch:nil,stats:snapshot.status!.stats)
            try check(ResetMenuDisplay.make(snapshot:snapshot,now:now).text == "重置时间待定", "Unknown date was fabricated")
            try check(ResetMenuDisplay.make(snapshot:.empty,now:now).text == "重置 —", "Empty state must not count down")
        }
        try await run("No schedule shows elapsed days and hours in green, never guesses a reset") {
            let now = Date()
            let last = now.addingTimeInterval(-2 * 86400)
            let stats = ResetStats(total:1,lastResetAt:last,daysSinceLast:99,avgIntervalDays:nil)
            var snapshot = ResetSnapshot(status:ResetStatus(latestReset:nil,scheduledReset:nil,activeWatch:nil,stats:stats),history:[],checkedAt:now,generatedAt:now,issue:nil)
            let display = ResetMenuDisplay.make(snapshot:snapshot,now:now)
            try check(display.text == "已重置 2 天 0 小时" && display.tone == .green,"Elapsed days should use timestamp, not stale API day count")
            try check(ResetMenuDisplay.make(snapshot:snapshot,now:now.addingTimeInterval(-1)).text == "已重置 1 天 23 小时","Whole-day boundary is incorrect")
            try check(ResetMenuDisplay.make(snapshot:snapshot,now:last.addingTimeInterval(3599)).text == "已重置 0 天 0 小时", "Partial hour must not round up")
            try check(ResetMenuDisplay.make(snapshot:snapshot,now:last.addingTimeInterval(3600)).text == "已重置 0 天 1 小时", "Exact hour boundary is incorrect")
            snapshot.status = ResetStatus(latestReset:nil,scheduledReset:nil,activeWatch:ActiveWatch(expiresAt:now.addingTimeInterval(60)),stats:stats)
            try check(ResetMenuDisplay.make(snapshot:snapshot,now:now).text == display.text,"Watch must not invent a schedule")
            snapshot.status = ResetStatus(latestReset:nil,scheduledReset:nil,activeWatch:nil,stats:ResetStats(total:0,lastResetAt:nil,daysSinceLast:nil,avgIntervalDays:nil))
            try check(ResetMenuDisplay.make(snapshot:snapshot,now:now).text == "上次重置时间未知","Missing history invented an elapsed duration")
        }
        print("\n\(passed) model, network and navigation tests passed. All HTTP requests used local URLProtocol stubs.")
    }
}
