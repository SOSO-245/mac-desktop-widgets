import AppKit
import Combine
import Foundation

final class LoopbackSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        // A local status endpoint must never redirect requests off the machine.
        completionHandler(nil)
    }
}

/// `/traffic` reports bytes per second for traffic handled by the Clash core.
/// It is not a subscription billing counter, and may include DIRECT traffic.
struct TrafficSample {
    let uploadBps: Double
    let downloadBps: Double

    static func decode(_ data: Data) -> TrafficSample? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let up = finiteNumber(object["up"]),
              let down = finiteNumber(object["down"]) else { return nil }
        return TrafficSample(uploadBps: up, downloadBps: down)
    }

    private static func finiteNumber(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue >= 0 else { return nil }
        return number.doubleValue
    }
}

/// Difference each live connection, never difference the sum of a changing list.
/// Short-lived connections between snapshots cannot be observed by this API.
struct ProxyTrafficSampler {
    private struct Counter {
        let up: Double
        let down: Double
        let chains: [String]
    }
    private var previous: [String: Counter] = [:]
    private var previousTime: TimeInterval?
    private var previousDate: Date?

    mutating func sample(_ data: Data, proxyTypes: [String: String],
                         time: TimeInterval = ProcessInfo.processInfo.systemUptime,
                         date: Date = Date()) -> TrafficSample? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["connections"],
              raw is NSNull || raw is [[String: Any]] else { self = Self(); return nil }
        let rows = raw as? [[String: Any]] ?? []
        guard rows.count <= 100_000 else { self = Self(); return nil }
        var current: [String: Counter] = [:]
        var newStarts: [String: Date] = [:]
        for row in rows {
            guard let id = row["id"] as? String, !id.isEmpty, current[id] == nil,
                  let up = number(row["upload"]), let down = number(row["download"]),
                  let chains = row["chains"] as? [String], !chains.isEmpty else {
                self = Self(); return nil
            }
            current[id] = Counter(up: up, down: down, chains: chains)
            if let start = row["start"] as? String { newStarts[id] = Self.parseDate(start) }
        }
        defer { previous = current; previousTime = time; previousDate = date }
        guard let oldTime = previousTime, let oldDate = previousDate,
              time.isFinite, time > oldTime, time - oldTime <= 5 else { return nil }
        var up = 0.0, down = 0.0
        for (id, now) in current {
            guard Self.isProxy(now.chains, types: proxyTypes) else { continue }
            if let old = previous[id] {
                guard now.chains == old.chains else { continue }
                guard now.up >= old.up, now.down >= old.down else { return nil }
                up += now.up - old.up; down += now.down - old.down
            } else if let start = newStarts[id], start >= oldDate, start <= date {
                // Only include a new connection's total if it began in this interval.
                up += now.up; down += now.down
            }
        }
        guard up.isFinite, down.isFinite else { return nil }
        return TrafficSample(uploadBps: up / (time - oldTime), downloadBps: down / (time - oldTime))
    }

    static func isProxy(_ chains: [String], types: [String: String]) -> Bool {
        // Mihomo lists the actual outbound first, followed by policy groups.
        guard let leaf = chains.first, !leaf.isEmpty else { return false }
        let excluded = ["direct", "reject", "reject-drop", "compatible", "pass"]
        return !excluded.contains(leaf.lowercased()) && !excluded.contains((types[leaf] ?? "").lowercased())
    }
    private func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              n.doubleValue.isFinite, n.doubleValue >= 0 else { return nil }
        return n.doubleValue
    }
    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

/// Resolve the selected group to the current leaf from the *running* core.
/// Saved selections alone cannot identify the current node of a URLTest group.
struct ProxySelection {
    let nodeName: String?
    let groupName: String?
    let latencyMS: Int?

    static func resolve(proxies: [String: Any], mode: String?, currentGroup: String?,
                        selected: [String: String] = [:]) -> ProxySelection? {
        guard let mode, ["direct", "global", "rule"].contains(mode.lowercased()) else { return nil }
        if mode.lowercased() == "direct" {
            return ProxySelection(nodeName: "DIRECT", groupName: "直连模式", latencyMS: nil)
        }
        let entries = proxies.compactMapValues { $0 as? [String: Any] }
        let root: String
        if mode.lowercased() == "global" {
            guard entries["GLOBAL"] != nil else { return nil }
            root = "GLOBAL"
        } else if let currentGroup, let group = entries[currentGroup],
                  currentGroup != "GLOBAL", isGroup(group) {
            root = currentGroup
        } else {
            // In rule mode several policy groups may be active simultaneously.
            // Only infer a group when its role is unambiguous; do not pretend
            // an arbitrary first proxy is the user's current node.
            let groups = entries.filter { $0.key != "GLOBAL" && isGroup($0.value) }
            let savedGroups = groups.filter { selected[$0.key] != nil }
            let candidates = savedGroups.isEmpty ? groups : savedGroups
            let ranked = candidates.map { (name: $0.key, rank: primaryGroupRank($0.key)) }
            let bestRank = ranked.map(\.rank).max() ?? 0
            let best = ranked.filter { $0.rank == bestRank && bestRank > 0 }
            if best.count == 1 {
                root = best[0].name
            } else if groups.count == 1, let only = groups.keys.first {
                root = only
            } else {
                return ProxySelection(nodeName: nil, groupName: "多个策略组", latencyMS: nil)
            }
        }

        var name = root
        var visited = Set<String>()
        for _ in 0..<32 {
            guard visited.insert(name).inserted, let proxy = entries[name] else {
                return ProxySelection(nodeName: nil, groupName: root, latencyMS: nil)
            }
            if let next = proxy["now"] as? String, !next.isEmpty {
                name = next
                continue
            }
            if isGroup(proxy) {
                // LoadBalance groups do not have a single selected leaf.
                return ProxySelection(nodeName: nil, groupName: root, latencyMS: nil)
            }
            return ProxySelection(nodeName: name, groupName: root, latencyMS: latestLatency(proxy))
        }
        return ProxySelection(nodeName: nil, groupName: root, latencyMS: nil)
    }

    private static func isGroup(_ value: [String: Any]) -> Bool {
        let type = (value["type"] as? String ?? "").lowercased()
        return ["selector", "urltest", "fallback", "loadbalance", "relay"].contains(type)
            || value["all"] is [String]
    }

    private static func primaryGroupRank(_ name: String) -> Int {
        let lower = name.lowercased()
        if lower.contains("手动") || lower.contains("manual") { return 3 }
        if lower.contains("节点选择") || lower.contains("代理选择") || lower == "proxy" || lower == "proxies" { return 2 }
        if lower.contains("自动选择") || lower.contains("自动切换") { return 1 }
        return 0
    }

    private static func latestLatency(_ proxy: [String: Any]) -> Int? {
        guard let history = proxy["history"] as? [[String: Any]], let last = history.last,
              let value = last["delay"] as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue.isFinite, value.intValue > 0, value.intValue <= 65535 else { return nil }
        return value.intValue
    }
}

/// Build one leaf-node delay request. This endpoint never changes a selection.
struct ClashLatencyProbe {
    static let fallbackURL = "https://www.gstatic.com/generate_204"

    static func testURL(configuration: [String: Any]) -> String {
        for key in ["test-url", "testUrl", "url-test-url", "url-test"] {
            guard let value = configuration[key] as? String,
                  let components = URLComponents(string: value),
                  ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
                  let host = components.host, !host.isEmpty,
                  components.user == nil, components.password == nil else { continue }
            return value
        }
        return fallbackURL
    }

    static func request(nodeName: String, testURL: String) throws -> URLRequest {
        // Encode the entire name as exactly one path segment, including slashes,
        // percent signs, dots, Unicode, and query/fragment delimiters.
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_~")
        guard !nodeName.isEmpty, let encoded = nodeName.addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw URLError(.badURL)
        }
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = 9090
        components.percentEncodedPath = "/proxies/\(encoded)/delay"
        components.queryItems = [URLQueryItem(name: "timeout", value: "5000"),
                                 URLQueryItem(name: "url", value: testURL)]
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // Allow the core's five-second probe deadline to return its own result.
        request.timeoutInterval = 7
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    static func decode(data: Data, response: URLResponse) throws -> Int {
        guard let http = response as? HTTPURLResponse,
              response.url?.scheme == "http", response.url?.host == "127.0.0.1",
              response.url?.port == 9090 else { throw URLError(.badServerResponse) }
        if [408, 504].contains(http.statusCode) { throw URLError(.timedOut) }
        guard http.statusCode == 200, data.count <= 65_536,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let delay = json["delay"] as? NSNumber,
              CFGetTypeID(delay) != CFBooleanGetTypeID(),
              delay.doubleValue.isFinite, delay.doubleValue >= 1, delay.doubleValue <= 65535,
              delay.doubleValue.rounded(.towardZero) == delay.doubleValue else {
            throw URLError(.badServerResponse)
        }
        return delay.intValue
    }
}

@MainActor
final class FlClashMonitor: ObservableObject {
    @Published var snapshot = MonitorSnapshot()

    private var trafficScope = TrafficScope.load()
    private var proxySampler = ProxyTrafficSampler()
    private var proxyTypes: [String: String] = [:]

    func setTrafficScope(_ value: TrafficScope) {
        guard value != trafficScope else { return }
        trafficScope = value
        UserDefaults.standard.set(value.rawValue, forKey: "flclashTrafficScope")
        disconnectTraffic()
        snapshot.uploadBps = nil; snapshot.downloadBps = nil; snapshot.sampledAt = nil
        snapshot.speedHistory = []; snapshot.uploadSpeedHistory = []
        snapshot.trafficScope = value
        if running { startTraffic() }
    }

    private var pollingTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var refreshID: UUID?
    private var trafficTask: Task<Void, Never>?
    private var webSocket: URLSessionWebSocketTask?
    private var generation = 0
    private var activeSubscription: ActiveSubscription?
    private var controllerEnabled = false
    private var controllerSecret = ""
    private var controllerIssue: String?
    private var lastTrafficAt: Date?
    private var socketStartedAt: Date?
    private var running = false
    private var preferenceError = false
    private var latencyTask: Task<Void, Never>?
    private var latencyRequestID: UUID?
    private var latencyNodeName: String?
    private var latencyTestURL: String?
    private var lastLatencyAttemptAt: ContinuousClock.Instant?

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 3600
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        // Local status requests must never travel through a configured proxy.
        config.connectionProxyDictionary = [:]
        return URLSession(configuration: config, delegate: LoopbackSessionDelegate(), delegateQueue: nil)
    }()

    func start() {
        guard !running else { return }
        running = true
        snapshot.trafficScope = trafficScope
        generation += 1
        pollingTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                guard let self else { return }
                if tick % 2 == 0 { self.refresh() }
                self.expireTrafficIfNeeded()
                tick += 1
                do { try await Task.sleep(nanoseconds: 1_000_000_000) }
                catch { return }
            }
        }
    }

    func stop() {
        running = false
        generation += 1
        pollingTask?.cancel()
        pollingTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        refreshID = nil
        disconnectTraffic()
        clearLiveValues()
        snapshot.connectionState = "监测已暂停"
    }

    func refresh() {
        readPreferences()
        snapshot.isRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.follow.clash"
                || $0.executableURL?.path == "/Applications/FlClash.app/Contents/MacOS/FlClash"
        }
        guard running, snapshot.isRunning, controllerEnabled else {
            refreshTask?.cancel()
            refreshTask = nil
            refreshID = nil
            disconnectTraffic()
            clearLiveValues()
            updateConnectionState()
            return
        }
        if trafficTask == nil { startTraffic() }
        guard refreshTask == nil else { return }
        let currentGeneration = generation
        let profileID = activeSubscription?.id
        let requestID = UUID()
        refreshID = requestID
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.refreshID == requestID {
                    self.refreshTask = nil
                    self.refreshID = nil
                }
            }
            do {
                let config = try await self.readEndpoint("configs")
                let response = try await self.readEndpoint("proxies")
                guard !Task.isCancelled, self.generation == currentGeneration,
                      self.activeSubscription?.id == profileID else { return }
                self.proxyTypes = (response["proxies"] as? [String: [String: Any]] ?? [:]).compactMapValues { $0["type"] as? String }
                let selection = ProxySelection.resolve(
                    proxies: response["proxies"] as? [String: Any] ?? [:],
                    mode: config["mode"] as? String,
                    currentGroup: self.activeSubscription?.currentGroup,
                    selected: self.activeSubscription?.selected ?? [:]
                )
                self.snapshot.nodeName = selection?.nodeName
                self.snapshot.groupName = selection?.groupName
                self.controllerIssue = nil
                // The two-second status poll must not overwrite a fresh probe
                // (or a timeout) with the core's older history entry.
                self.updateAutomaticLatency(selection: selection, configuration: config)
                let connections = try? await self.readEndpoint("connections")
                guard !Task.isCancelled, self.generation == currentGeneration, self.activeSubscription?.id == profileID else { return }
                self.snapshot.connectionCount = ConnectionMetrics.count(connections)
                self.updateConnectionState()
            } catch {
                guard !Task.isCancelled, self.generation == currentGeneration else { return }
                self.snapshot.connectionCount = nil
                self.snapshot.nodeName = nil
                self.snapshot.groupName = nil
                self.controllerIssue = (error as? URLError)?.code == .userAuthenticationRequired
                    ? "本机接口认证失败" : "本机接口暂不可用"
                self.cancelAutomaticLatency()
                self.updateConnectionState()
            }
        }
    }

    private func readPreferences() {
        do {
            let config = try FlClashPreferences.read()
            preferenceError = false
            snapshot.metadataIssue = nil
            let subscription = ActiveSubscription.decode(configuration: config)
            if activeSubscription?.id != subscription?.id {
                cancelAutomaticLatency()
                disconnectTraffic()
                clearSpeeds()
                snapshot.nodeName = nil
                snapshot.groupName = nil
                snapshot.latencyMS = nil
                snapshot.speedHistory = []
                snapshot.uploadSpeedHistory = []
            }
            activeSubscription = subscription
            snapshot.profileName = subscription?.name
            snapshot.usedBytes = subscription?.usedBytes
            snapshot.totalBytes = subscription?.totalBytes
            snapshot.expiresAt = subscription?.expiresAt
            snapshot.subscriptionUpdatedAt = subscription?.updatedAt
            let patch = config["patchClashConfig"] as? [String: Any]
            controllerEnabled = patch?["external-controller"] as? String == "127.0.0.1:9090"
            let secret = patch?["secret"] as? String ?? ""
            if secret != controllerSecret {
                controllerSecret = secret
                generation += 1
                refreshTask?.cancel(); refreshTask = nil; refreshID = nil
                cancelAutomaticLatency()
                disconnectTraffic()
                clearSpeeds()
                controllerIssue = nil
            }
        } catch {
            preferenceError = true
            snapshot.metadataIssue = "暂时无法读取套餐资料"
            activeSubscription = nil
            controllerEnabled = false
            controllerSecret = ""
            snapshot.profileName = nil
            snapshot.usedBytes = nil
            snapshot.totalBytes = nil
            snapshot.expiresAt = nil
            snapshot.subscriptionUpdatedAt = nil
        }
    }

    private func readEndpoint(_ path: String) async throws -> [String: Any] {
        // All callers use these two read-only paths on a fixed loopback origin.
        guard ["configs", "proxies", "connections"].contains(path),
              let url = URL(string: "http://127.0.0.1:9090/\(path)") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 4
        request = try FlClashAuthorization.apply(to: request, secret: controllerSecret)
        let (data, response) = try await session.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 401 { throw URLError(.userAuthenticationRequired) }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.url?.host == "127.0.0.1", response.url?.port == 9090,
              data.count <= 8_000_000,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.badServerResponse)
        }
        return json
    }

    private func updateAutomaticLatency(selection: ProxySelection?, configuration: [String: Any]) {
        guard running, controllerEnabled, snapshot.isRunning,
              let nodeName = selection?.nodeName, !nodeName.isEmpty,
              !["DIRECT", "REJECT", "REJECT-DROP", "PASS", "COMPATIBLE"].contains(nodeName.uppercased()) else {
            cancelAutomaticLatency()
            return
        }
        let testURL = ClashLatencyProbe.testURL(configuration: configuration)
        if latencyNodeName != nodeName || latencyTestURL != testURL {
            cancelAutomaticLatency()
            latencyNodeName = nodeName
            latencyTestURL = testURL
        }
        guard latencyTask == nil else { return }
        let now = ContinuousClock.now
        if let lastLatencyAttemptAt, now - lastLatencyAttemptAt < .seconds(30) { return }
        lastLatencyAttemptAt = now
        let currentGeneration = generation
        let profileID = activeSubscription?.id
        let requestID = UUID()
        latencyRequestID = requestID
        // Keep the previous result for this same node until the request completes.
        // Node/route changes still clear it in cancelAutomaticLatency().
        if snapshot.latencyMS == nil { snapshot.latencyKind = "自动测速中" }
        latencyTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.latencyRequestID == requestID {
                    self.latencyTask = nil
                    self.latencyRequestID = nil
                }
            }
            do {
                let request = try FlClashAuthorization.apply(
                    to: ClashLatencyProbe.request(nodeName: nodeName, testURL: testURL), secret: self.controllerSecret)
                let (data, response) = try await self.session.data(for: request)
                let delay = try ClashLatencyProbe.decode(data: data, response: response)
                guard !Task.isCancelled, self.generation == currentGeneration,
                      self.latencyRequestID == requestID, self.latencyNodeName == nodeName,
                      self.activeSubscription?.id == profileID else { return }

                // Re-read the running selection before publishing. A node or
                // profile may have changed while this request was in flight.
                let latestConfig = try await self.readEndpoint("configs")
                let latestProxies = try await self.readEndpoint("proxies")
                self.readPreferences()
                guard !Task.isCancelled, self.running, self.controllerEnabled, self.snapshot.isRunning,
                      self.generation == currentGeneration,
                      self.latencyRequestID == requestID, self.latencyNodeName == nodeName,
                      self.activeSubscription?.id == profileID else { return }
                let confirmed = ProxySelection.resolve(
                    proxies: latestProxies["proxies"] as? [String: Any] ?? [:],
                    mode: latestConfig["mode"] as? String,
                    currentGroup: self.activeSubscription?.currentGroup,
                    selected: self.activeSubscription?.selected ?? [:]
                )
                guard confirmed?.nodeName == nodeName,
                      ClashLatencyProbe.testURL(configuration: latestConfig) == testURL else {
                    self.snapshot.nodeName = confirmed?.nodeName
                    self.snapshot.groupName = confirmed?.groupName
                    self.updateAutomaticLatency(selection: confirmed, configuration: latestConfig)
                    return
                }
                self.snapshot.latencyMS = delay
                self.snapshot.latencyIsLive = true
                self.snapshot.latencyKind = "自动测速"
            } catch {
                guard !Task.isCancelled, self.generation == currentGeneration,
                      self.latencyRequestID == requestID, self.latencyNodeName == nodeName,
                      self.activeSubscription?.id == profileID else { return }
                self.snapshot.latencyMS = nil
                self.snapshot.latencyIsLive = false
                self.snapshot.latencyKind = (error as? URLError)?.code == .timedOut ? "自动测速超时" : "自动测速未成功"
            }
        }
    }

    private func cancelAutomaticLatency() {
        latencyTask?.cancel()
        latencyTask = nil
        latencyRequestID = nil
        latencyNodeName = nil
        latencyTestURL = nil
        lastLatencyAttemptAt = nil
        snapshot.latencyMS = nil
        snapshot.latencyIsLive = false
        snapshot.latencyKind = "等待自动测速"
    }

    private func startTraffic() {
        let path = trafficScope == .all ? "traffic" : "connections?interval=1000"
        guard running, controllerEnabled, snapshot.isRunning, trafficTask == nil,
              let url = URL(string: "ws://127.0.0.1:9090/\(path)") else { return }
        let scope = trafficScope
        proxySampler = ProxyTrafficSampler()
        let currentGeneration = generation
        guard let request = try? FlClashAuthorization.apply(to: URLRequest(url: url), secret: controllerSecret) else {
            controllerIssue = "本机接口认证配置无效"
            return
        }
        let socket = session.webSocketTask(with: request)
        socket.maximumMessageSize = scope == .all ? 16_384 : 8_000_000
        webSocket = socket
        socketStartedAt = Date()
        socket.resume()
        trafficTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.webSocket === socket {
                    self.webSocket = nil
                    self.trafficTask = nil
                    self.socketStartedAt = nil
                }
                socket.cancel(with: .goingAway, reason: nil)
            }
            do {
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    guard !Task.isCancelled, self.generation == currentGeneration,
                          self.webSocket === socket else { return }
                    let data: Data
                    switch message {
                    case .data(let bytes): data = bytes
                    case .string(let text): data = Data(text.utf8)
                    @unknown default: continue
                    }
                    let sample = scope == .all ? TrafficSample.decode(data)
                        : self.proxySampler.sample(data, proxyTypes: self.proxyTypes)
                    guard let sample else {
                        self.snapshot.uploadBps = nil; self.snapshot.downloadBps = nil
                        self.snapshot.speedHistory = []; self.snapshot.uploadSpeedHistory = []
                        self.snapshot.sampledAt = nil
                        continue
                    }
                    let now = Date()
                    self.lastTrafficAt = now
                    self.snapshot.sampledAt = now
                    self.snapshot.uploadBps = sample.uploadBps
                    self.snapshot.downloadBps = sample.downloadBps
                    self.snapshot.isConnected = true
                    self.snapshot.speedHistory.append(sample.downloadBps)
                    self.snapshot.uploadSpeedHistory.append(sample.uploadBps)
                    if self.snapshot.speedHistory.count > 30 {
                        self.snapshot.speedHistory.removeFirst(self.snapshot.speedHistory.count - 30)
                    }
                    if self.snapshot.uploadSpeedHistory.count > 30 {
                        self.snapshot.uploadSpeedHistory.removeFirst(self.snapshot.uploadSpeedHistory.count - 30)
                    }
                    self.updateConnectionState()
                }
            } catch {
                guard !Task.isCancelled, self.generation == currentGeneration,
                      self.webSocket === socket else { return }
                self.clearSpeeds()
                self.updateConnectionState()
            }
        }
    }

    private func expireTrafficIfNeeded() {
        let reference = lastTrafficAt ?? socketStartedAt
        if let reference, Date().timeIntervalSince(reference) > 5 {
            disconnectTraffic()
            clearSpeeds()
            updateConnectionState()
        }
    }

    private func disconnectTraffic() {
        proxySampler = ProxyTrafficSampler()
        trafficTask?.cancel()
        trafficTask = nil
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        socketStartedAt = nil
        lastTrafficAt = nil
    }

    private func clearSpeeds() {
        snapshot.uploadBps = nil
        snapshot.downloadBps = nil
        snapshot.sampledAt = nil
        snapshot.isConnected = false
        snapshot.speedHistory = []
        snapshot.uploadSpeedHistory = []
        lastTrafficAt = nil
    }

    private func clearLiveValues() {
        snapshot.connectionCount = nil
        cancelAutomaticLatency()
        clearSpeeds()
        snapshot.nodeName = nil
        snapshot.groupName = nil
        snapshot.latencyMS = nil
    }

    private func updateConnectionState() {
        if preferenceError { snapshot.connectionState = "暂时无法读取 FlClash 配置" }
        else if !snapshot.isRunning { snapshot.connectionState = "FlClash 未运行" }
        else if !controllerEnabled { snapshot.connectionState = "等待开启 FlClash 本机接口" }
        else if let controllerIssue { snapshot.connectionState = controllerIssue }
        else if snapshot.isConnected { snapshot.connectionState = "实时连接" }
        else { snapshot.connectionState = "本机接口连接中" }
    }
}
