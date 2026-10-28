import Foundation
import Combine

@MainActor
final class MonitorCoordinator: ObservableObject {
    @Published var snapshot = MonitorSnapshot()
    @Published var proxies: [String:[String:Any]] = [:]
    @Published var providers: [String:[String:Any]] = [:]
    @Published var switching = false
    @Published var actionMessage = ""
    private(set) var settings = ConnectionSettings.load()
    private(set) var api: NikkiAPI?
    var client: ProxyClient { .nikki }
    @Published var subscriptionRefreshing = false
    @Published var subscriptionRefreshMessage = ""
    @Published private(set) var subscriptionRefreshInterval = SubscriptionRefreshPolicy.interval(UserDefaults.standard.object(forKey: "subscriptionRefreshSeconds") as? Int)
    private var subscriptionTask: Task<Void,Never>?
    func setSubscriptionRefreshInterval(_ seconds: Int) {
        subscriptionRefreshInterval = SubscriptionRefreshPolicy.interval(seconds)
        UserDefaults.standard.set(subscriptionRefreshInterval, forKey: "subscriptionRefreshSeconds")
        subscriptionRefreshMessage = subscriptionRefreshInterval == 0 ? "套餐定时刷新已关闭" : "已设置" + SubscriptionRefreshPolicy.title(subscriptionRefreshInterval)
    }
    func refreshSubscription(manual: Bool = true) {
        guard subscriptionTask == nil, snapshot.isConnected, let api else { return }
        guard let name = NikkiData.matchingProvider(group: settings.group, selected: settings.provider, proxies: proxies, providers: providers),
              let provider = providers[name], (provider["vehicleType"] as? String)?.lowercased() == "http" else {
            if manual { subscriptionRefreshMessage = "当前未匹配到可更新的网络订阅" }; return
        }
        let now = Date(), key = SubscriptionRefreshPolicy.key(endpoint: settings.endpoint, provider: name)
        let attempted = UserDefaults.standard.object(forKey: key) as? Date
        var value = MonitorSnapshot(); NikkiData.subscription(provider, snapshot: &value)
        guard SubscriptionRefreshPolicy.due(now: now, updated: value.subscriptionUpdatedAt, attempted: attempted, interval: subscriptionRefreshInterval, manual: manual) else {
            if manual { subscriptionRefreshMessage = "刚刚已请求刷新，请稍候" }; return
        }
        UserDefaults.standard.set(now, forKey: key)
        let token = generation
        subscriptionRefreshing = true; subscriptionRefreshMessage = "正在更新套餐…"
        subscriptionTask = Task {
            do {
                _ = try await api.json(["providers", "proxies", name], method: "PUT")
                guard generation == token, !Task.isCancelled else { return }
                let fresh = try await api.json(["providers", "proxies", name])
                guard generation == token, !Task.isCancelled else { return }
                providers[name] = fresh; applySubscription()
                subscriptionRefreshMessage = "套餐已刷新 · " + Date().formatted(date: .omitted, time: .shortened)
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                subscriptionRefreshMessage = "套餐刷新失败，保留已有读数；下个周期再试"
            }
            subscriptionRefreshing = false; subscriptionTask = nil
        }
    }
    private var timer: Task<Void,Never>?
    private var polling: Task<Void,Never>?
    private var stream: Task<Void,Never>?
    private var socket: URLSessionWebSocketTask?
    private var lastTraffic: Date?
    private var trafficScope = TrafficScope.load()
    private var proxySampler = ProxyTrafficSampler()
    func setTrafficScope(_ value: TrafficScope) {
        guard value != trafficScope else { return }
        trafficScope = value
        UserDefaults.standard.set(value.rawValue, forKey: "nikkiTrafficScope")
        socket?.cancel(with: .goingAway, reason: nil); stream?.cancel(); socket = nil; stream = nil
        proxySampler = ProxyTrafficSampler()
        snapshot.trafficScope = value
        snapshot.uploadBps = nil; snapshot.downloadBps = nil
        snapshot.speedHistory = []; snapshot.uploadSpeedHistory = []
        if let api, snapshot.isConnected { startTraffic(api, token: generation) }
    }
    private var generation = UUID()
    var groups: [String] { proxies.keys.filter { proxies[$0]?["type"] as? String == "Selector" }.sorted() }
    var subscriptions: [String] { providers.keys.filter { providers[$0]?["subscriptionInfo"] != nil }.sorted() }
    func start() {
        stop()
        snapshot.trafficScope = trafficScope
        api = NikkiAPI(settings: settings, secret: Vault.read(settings.endpoint))
        refresh()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
                guard let self else { return }
                if let last = self.lastTraffic, Date().timeIntervalSince(last) > 8 {
                    self.socket?.cancel(with: .goingAway, reason: nil); self.stream?.cancel(); self.stream = nil; self.socket = nil
                    self.snapshot.uploadBps = nil; self.snapshot.downloadBps = nil
                    self.snapshot.speedHistory = []; self.snapshot.uploadSpeedHistory = []; self.lastTraffic = nil
                }
                self.refresh()
            }
        }
    }
    func stop() {
        generation = UUID(); subscriptionTask?.cancel(); subscriptionTask = nil; subscriptionRefreshing = false; timer?.cancel(); polling?.cancel(); stream?.cancel()
        timer = nil; polling = nil; stream = nil
        socket?.cancel(with: .goingAway, reason: nil); socket = nil; api?.close(); api = nil; lastTraffic = nil
    }
    func save(_ new: ConnectionSettings, secret: String?) throws {
        var new = new; new.endpoint = try ConnectionSettings.normalized(new.endpoint)
        if let secret { try Vault.save(secret, endpoint: new.endpoint) }
        switching = false; actionMessage = ""; settings = new; new.save(); proxies = [:]; providers = [:]; snapshot = MonitorSnapshot(); start()
    }
    func chooseGroup(_ group: String) {
        guard groups.contains(group) else { return }
        settings.group = group; settings.save(); applyProxies(); refresh()
    }
    func chooseProvider(_ name: String) {
        settings.provider = name; settings.save(); applySubscription()
    }
    private func applyProxies() {
        let group = settings.group
        snapshot.groupName = group
        snapshot.nodeName = NikkiData.leaf(group, proxies: proxies)
        snapshot.latencyMS = snapshot.nodeName.flatMap { NikkiData.recentDelay(proxies[$0]) }
        snapshot.latencyKind = "Nikki 最近测速"
        snapshot.routeIdentity = settings.endpoint + "|" + group + "|" + proxies.keys.sorted().compactMap { name in
            (proxies[name]?["now"] as? String).map { name + ":" + $0 }
        }.joined(separator: "|")
        if proxies[group] == nil { snapshot.metadataIssue = "请选择策略组" } else { snapshot.metadataIssue = nil }
        applySubscription()
    }
    private func applySubscription() {
        let chosen = NikkiData.matchingProvider(group:settings.group, selected:settings.provider, proxies:proxies, providers:providers)
        snapshot.profileName = chosen ?? (subscriptions.isEmpty ? "旁路由" : "未匹配套餐")
        NikkiData.subscription(chosen.flatMap { providers[$0] }, snapshot: &snapshot)
    }
    func refresh() {
        guard polling == nil, let api else { return }
        let token = generation
        polling = Task {
            do {
                let data = try await api.json(["proxies"])
                guard generation == token, !Task.isCancelled else { return }
                guard let p = data["proxies"] as? [String:[String:Any]] else { throw URLError(.cannotParseResponse) }
                proxies = p; snapshot.isConnected = true; snapshot.isRunning = true
                snapshot.connectionState = "已连接旁路由"; snapshot.sampledAt = Date()
                if stream == nil { startTraffic(api, token: token) }
                do {
                    let data = try await api.json(["providers","proxies"])
                    guard generation == token, !Task.isCancelled else { return }
                    providers = data["providers"] as? [String:[String:Any]] ?? [:]
                } catch { guard generation == token else { return }; providers = [:] }
                let connections = try? await api.json(["connections"])
                guard generation == token, !Task.isCancelled else { return }
                snapshot.connectionCount = ConnectionMetrics.count(connections)
                proxies = NikkiData.includingProviderNodes(p,providers:providers)
                applyProxies()
                refreshSubscription(manual: false)
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                snapshot.isConnected = false; snapshot.connectionState = (error as? APIError)?.localizedDescription ?? ((error as? URLError)?.code == .notConnectedToInternet ? "请允许本地网络访问" : "旁路由暂时无法连接")
                snapshot.connectionCount = nil; snapshot.nodeName = nil; snapshot.latencyMS = nil; snapshot.uploadBps = nil; snapshot.downloadBps = nil
                snapshot.speedHistory = []; snapshot.uploadSpeedHistory = []
                proxies = [:]; providers = [:]; applySubscription()
                socket?.cancel(with: .goingAway, reason: nil); stream?.cancel(); stream = nil; socket = nil
            }
            guard generation == token else { return }; polling = nil
        }
    }
    private func startTraffic(_ api: NikkiAPI, token: UUID) {
        let scope = trafficScope
        proxySampler = ProxyTrafficSampler()
        guard let request = try? api.request([scope == .all ? "traffic" : "connections"],
                                            query: scope == .all ? [] : [URLQueryItem(name:"interval",value:"1000")], websocket: true) else { return }
        let socket = api.session.webSocketTask(with: request); socket.maximumMessageSize = 8_000_000; self.socket = socket; socket.resume(); lastTraffic = Date()
        stream = Task {
            do {
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    guard generation == token, !Task.isCancelled, self.socket === socket else { return }
                    let data: Data
                    switch message { case .data(let d): data = d; case .string(let s): data = Data(s.utf8); @unknown default: continue }
                    let sample = scope == .all ? TrafficSample.decode(data)
                        : proxySampler.sample(data, proxyTypes: proxies.compactMapValues { $0["type"] as? String })
                    guard let sample else {
                        snapshot.uploadBps = nil; snapshot.downloadBps = nil
                        snapshot.speedHistory = []; snapshot.uploadSpeedHistory = []
                        continue
                    }
                    snapshot.uploadBps = sample.uploadBps; snapshot.downloadBps = sample.downloadBps
                    snapshot.sampledAt = Date()
                    if let down = snapshot.downloadBps { snapshot.speedHistory = Array((snapshot.speedHistory + [down]).suffix(30)) }
                    if let up = snapshot.uploadBps { snapshot.uploadSpeedHistory = Array((snapshot.uploadSpeedHistory + [up]).suffix(30)) }
                    lastTraffic = Date()
                }
            } catch {
                guard generation == token, !Task.isCancelled, self.socket === socket else { return }
                snapshot.uploadBps = nil; snapshot.downloadBps = nil
                snapshot.speedHistory = []; snapshot.uploadSpeedHistory = []
                stream = nil; self.socket = nil
            }
        }
    }
    func select(node: String) {
        guard !switching, let api, snapshot.isConnected else { return }
        let group = settings.group, token = generation
        switching = true; actionMessage = "正在切换…"
        Task {
            do {
                try await api.select(group: group, node: node)
                guard generation == token else { return }
                actionMessage = "已切换到 \(node)"; refresh()
            } catch {
                guard generation == token else { return }
                actionMessage = (error as? APIError)?.localizedDescription ?? "切换失败，请检查连接"
            }
            switching = false
        }
    }
}
