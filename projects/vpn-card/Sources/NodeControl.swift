import Combine
import Foundation

struct FlClashNodeOption: Identifiable, Equatable {
    let name: String
    let type: String
    let resolvedNode: String?
    let path: [String]
    let isGroup: Bool
    let canTest: Bool
    var id: String { name }
}

struct FlClashNodeGroup: Identifiable, Equatable {
    let name: String
    let selectedName: String?
    let options: [FlClashNodeOption]
    var id: String { name }
}

struct FlClashNodeLatency: Equatable {
    enum State: Equatable { case idle, testing, success, timeout, failed }
    let state: State
    let milliseconds: Int?
    let checkedAt: Date?
    static let idle = Self(state: .idle, milliseconds: nil, checkedAt: nil)
    static let testing = Self(state: .testing, milliseconds: nil, checkedAt: nil)
}

enum FlClashNodeError: Error, LocalizedError {
    case noProfile, controllerDisabled, invalidAuthentication, identityChanged
    case unavailable, unauthorized, timeout, invalidResponse, invalidSelection, unconfirmed
    var errorDescription: String? {
        switch self {
        case .noProfile: return "当前套餐不可用，请在 FlClash 中检查"
        case .controllerDisabled: return "请先开启 FlClash 本机接口"
        case .invalidAuthentication: return "本机接口认证配置无效"
        case .identityChanged: return "套餐或接口已变化，请刷新节点列表"
        case .unauthorized: return "本机接口认证失败，请刷新后重试"
        case .timeout: return "请求超时，请稍后重试"
        case .invalidSelection: return "节点列表已变化，请刷新后重新选择"
        case .unconfirmed: return "切换结果尚未确认，请刷新查看当前节点"
        case .unavailable: return "FlClash 本机接口暂不可用"
        case .invalidResponse: return "本机接口返回的数据无效"
        }
    }
}

// Injectable transport exists for synthetic tests. Production has one fixed
// loopback origin, an ephemeral session, no system proxy, and no redirects.
@MainActor protocol FlClashNodeTransport: AnyObject {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

private final class FlClashNodeRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor final class FlClashNodeURLTransport: FlClashNodeTransport {
    private let session: URLSession
    init(protocolClasses: [AnyClass]? = nil) {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        config.timeoutIntervalForRequest = 7
        config.timeoutIntervalForResource = 9
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        if let protocolClasses { config.protocolClasses = protocolClasses }
        session = URLSession(configuration: config, delegate: FlClashNodeRedirectBlocker(), delegateQueue: nil)
    }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard request.url?.scheme == "http", request.url?.host == "127.0.0.1", request.url?.port == 9090,
              request.url?.user == nil, request.url?.password == nil else { throw FlClashNodeError.invalidResponse }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw FlClashNodeError.invalidResponse }
        return (data, http)
    }
    deinit { session.invalidateAndCancel() }
}

struct FlClashNodeCatalog {
    let groups: [FlClashNodeGroup]
    let mode: String
    let testURL: String

    static func decode(configuration: [String: Any], payload: [String: Any]) throws -> Self {
        guard let mode = (configuration["mode"] as? String)?.lowercased(),
              ["rule", "global", "direct"].contains(mode),
              let raw = payload["proxies"] as? [String: Any], raw.count <= 20_000 else {
            throw FlClashNodeError.invalidResponse
        }
        let entries = raw.compactMapValues { $0 as? [String: Any] }
        func validName(_ name: String) -> Bool {
            !name.isEmpty && name.utf8.count <= 4096 && !name.utf8.contains { $0 < 0x20 || $0 == 0x7f }
        }
        func option(_ name: String) -> FlClashNodeOption? {
            guard validName(name), !ProxyNodeLabels.isInformation(name),
                  let item = entries[name], let type = item["type"] as? String else { return nil }
            let groupTypes = ["selector", "urltest", "fallback", "loadbalance", "relay"]
            let isGroup = groupTypes.contains(type.lowercased()) || item["all"] is [String]
            var path: [String] = []
            var current = name
            var visited = Set<String>()
            var leaf: String?
            for _ in 0..<32 {
                if ProxyNodeLabels.isInformation(current) { return nil }
                guard visited.insert(current).inserted, validName(current), let entry = entries[current] else { break }
                path.append(current)
                if let next = entry["now"] as? String, !next.isEmpty {
                    // A stale `now` outside `all` is not a reliable route.
                    guard let members = entry["all"] as? [String], members.contains(next) else { break }
                    current = next
                    continue
                }
                let entryType = (entry["type"] as? String ?? "").lowercased()
                if !groupTypes.contains(entryType), !(entry["all"] is [String]) { leaf = current }
                break
            }
            let excluded = ["DIRECT", "REJECT", "REJECT-DROP", "PASS", "COMPATIBLE"]
            let leafType = leaf.flatMap { entries[$0]?["type"] as? String }?.uppercased() ?? ""
            return FlClashNodeOption(name: name, type: type, resolvedNode: leaf, path: path,
                                     isGroup: isGroup,
                                     canTest: (leaf.map { !excluded.contains($0.uppercased()) } ?? false)
                                        && !excluded.contains(leafType))
        }
        let groups = entries.compactMap { name, entry -> FlClashNodeGroup? in
            guard validName(name), !ProxyNodeLabels.isInformation(name),
                  (entry["type"] as? String)?.lowercased() == "selector",
                  name != "GLOBAL" || mode == "global",
                  let members = entry["all"] as? [String], members.count <= 10_000 else { return nil }
            var seen = Set<String>()
            let options = members.filter { seen.insert($0).inserted }.compactMap(option)
            guard !options.isEmpty else { return nil }
            return FlClashNodeGroup(name: name, selectedName: entry["now"] as? String, options: options)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return Self(groups: groups, mode: mode, testURL: ClashLatencyProbe.testURL(configuration: configuration))
    }
}

@MainActor final class FlClashNodeController: ObservableObject {
    @Published private(set) var groups: [FlClashNodeGroup] = []
    @Published private(set) var selectedGroupName: String?
    @Published private(set) var latencies: [String: FlClashNodeLatency] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var isTesting = false
    @Published private(set) var selectingName: String?
    @Published private(set) var error: String?
    @Published private(set) var notice: String?
    var onSelectionChanged: (() -> Void)?

    private struct Identity: Equatable, Hashable {
        let profileID: String
        let secret: String
    }
    private struct CacheKey: Hashable {
        let identity: Identity
        let candidate: String
        let path: [String]
        let testURL: String
    }
    private let readPreferences: () throws -> [String: Any]
    private let transport: any FlClashNodeTransport
    private let now: () -> Date
    private var identity: Identity?
    private var catalog: FlClashNodeCatalog?
    private var cache: [CacheKey: FlClashNodeLatency] = [:]
    private var isOpen = false
    private var epoch = UUID()
    private var probeEpoch = UUID()
    private var loadTask: Task<Void, Never>?
    private var identityTask: Task<Void, Never>?
    private var probeTask: Task<Void, Never>?
    private var selectionTask: Task<Void, Never>?
    private var pendingProbes: [FlClashNodeOption] = []

    init(readPreferences: @escaping () throws -> [String: Any] = FlClashPreferences.read,
         transport: (any FlClashNodeTransport)? = nil, now: @escaping () -> Date = Date.init) {
        self.readPreferences = readPreferences
        self.transport = transport ?? FlClashNodeURLTransport()
        self.now = now
    }

    func open(preferredGroup: String? = nil) {
        close()
        isOpen = true
        selectedGroupName = preferredGroup
        refresh()
        identityTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
                guard let self, self.isOpen else { return }
                guard let expected = self.identity else { continue }
                guard let latest = try? self.readIdentity(), latest.0 == expected else {
                    self.epoch = UUID()
                    self.loadTask?.cancel(); self.loadTask = nil
                    self.selectionTask?.cancel(); self.selectionTask = nil
                    self.cancelProbes()
                    self.identity = nil; self.catalog = nil; self.cache = [:]
                    self.groups = []; self.latencies = [:]; self.selectedGroupName = nil
                    self.isLoading = false; self.selectingName = nil
                    self.notice = nil; self.error = FlClashNodeError.identityChanged.localizedDescription
                    continue
                }
            }
        }
    }

    func close() {
        isOpen = false
        epoch = UUID()
        loadTask?.cancel(); loadTask = nil
        identityTask?.cancel(); identityTask = nil
        selectionTask?.cancel(); selectionTask = nil
        cancelProbes()
        isLoading = false
        selectingName = nil
        groups = []; catalog = nil; latencies = [:]
        selectedGroupName = nil
        error = nil; notice = nil
    }

    func refresh() {
        guard isOpen, selectingName == nil else { return }
        loadTask?.cancel()
        cancelProbes()
        epoch = UUID()
        let token = epoch
        isLoading = true; error = nil; notice = nil
        loadTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.epoch == token { self.isLoading = false; self.loadTask = nil } }
            do {
                let (current, preferred) = try self.readIdentity()
                if self.identity != current { self.cache = [:]; self.latencies = [:] }
                self.identity = current
                let fresh = try await self.fetchCatalog(identity: current, epoch: token)
                try self.validate(current, epoch: token)
                self.publish(fresh, preferred: self.selectedGroupName ?? preferred)
                self.testAll()
            } catch {
                guard self.isCurrent(token), !Task.isCancelled else { return }
                self.groups = []; self.catalog = nil; self.latencies = [:]
                self.error = self.message(error)
            }
        }
    }

    func setGroup(_ name: String) {
        guard isOpen, selectingName == nil, groups.contains(where: { $0.name == name }) else { return }
        selectedGroupName = name
        error = nil
        testAll()
    }

    func testAll(force: Bool = false) {
        guard isOpen, let current = identity, let catalog,
              let group = groups.first(where: { $0.name == selectedGroupName }) else { return }
        cancelProbes()
        let token = epoch
        let probeToken = probeEpoch
        latencies = [:]
        let date = now()
        cache = cache.filter { value in
            guard let at = value.value.checkedAt else { return false }
            return date.timeIntervalSince(at) >= 0 && date.timeIntervalSince(at) < 30
        }
        for option in group.options {
            guard option.canTest else { latencies[option.name] = .idle; continue }
            let key = CacheKey(identity: current, candidate: option.name, path: option.path, testURL: catalog.testURL)
            if !force, let value = cache[key] { latencies[option.name] = value }
            else { latencies[option.name] = .testing; pendingProbes.append(option) }
        }
        guard !pendingProbes.isEmpty else { isTesting = false; return }
        isTesting = true
        probeTask = Task { [weak self] in
            guard let self else { return }
            await withTaskGroup(of: Void.self) { workers in
                for _ in 0..<3 {
                    workers.addTask { [weak self] in
                        await self?.drainProbes(identity: current, token: token, probeToken: probeToken, testURL: catalog.testURL)
                    }
                }
                await workers.waitForAll()
            }
            guard self.isCurrent(token), self.probeEpoch == probeToken else { return }
            self.isTesting = false; self.probeTask = nil
        }
    }

    // This is the sole mutation entry point; UI calls it only for an explicit
    // candidate click. Loading, refreshing, probing and changing visible groups
    // never call it. An uncertain PUT is never automatically retried.
    func select(name: String) {
        guard isOpen, !isLoading, selectingName == nil,
              let current = identity, let visible = catalog,
              let groupName = selectedGroupName,
              let group = groups.first(where: { $0.name == groupName }),
              group.options.contains(where: { $0.name == name }) else { return }
        cancelProbes()
        selectingName = name; error = nil; notice = nil
        let token = epoch
        selectionTask = Task { [weak self] in
            guard let self else { return }
            var sent = false
            defer {
                if self.epoch == token { self.selectingName = nil; self.selectionTask = nil }
            }
            do {
                try self.validate(current, epoch: token)
                let fresh = try await self.fetchCatalog(identity: current, epoch: token)
                guard fresh.mode == visible.mode,
                      let latestGroup = fresh.groups.first(where: { $0.name == groupName }),
                      latestGroup.options.contains(where: { $0.name == name }) else {
                    throw FlClashNodeError.invalidSelection
                }
                // No await between the final identity check and dispatch.
                try self.validate(current, epoch: token)
                if latestGroup.selectedName != name {
                    var request = try self.request(path: "/proxies/" + Self.encode(name: groupName), identity: current)
                    request.httpMethod = "PUT"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: ["name": name])
                    sent = true
                    let (data, response) = try await self.transport.data(for: request)
                    try self.validate(current, epoch: token)
                    if [400, 401, 403, 404, 405, 409, 422].contains(response.statusCode) { sent = false }
                    try self.checkResponse(response, data: data, accepted: [200, 204])
                }
                let confirmed = try await self.fetchCatalog(identity: current, epoch: token)
                try self.validate(current, epoch: token)
                guard confirmed.mode == visible.mode,
                      confirmed.groups.first(where: { $0.name == groupName })?.selectedName == name else {
                    throw FlClashNodeError.unconfirmed
                }
                self.publish(confirmed, preferred: groupName)
                self.notice = "已将「\(groupName)」切换为「\(name)」；重载配置后以 FlClash 的保存设置为准"
                self.onSelectionChanged?()
                self.testAll()
            } catch {
                guard self.isCurrent(token), !Task.isCancelled else { return }
                self.error = sent ? FlClashNodeError.unconfirmed.localizedDescription : self.message(error)
            }
        }
    }

    private func publish(_ fresh: FlClashNodeCatalog, preferred: String?) {
        catalog = fresh; groups = fresh.groups
        selectedGroupName = fresh.groups.first(where: { $0.name == preferred })?.name ?? fresh.groups.first?.name
        notice = fresh.groups.isEmpty ? "当前配置没有可手动选择的节点组"
            : fresh.mode == "direct" ? "当前为直连模式，节点选择不会改变运行模式" : nil
    }

    private func cancelProbes() {
        probeEpoch = UUID()
        probeTask?.cancel(); probeTask = nil
        pendingProbes = []; isTesting = false
        for (name, value) in latencies where value.state == .testing { latencies[name] = .idle }
    }

    private func drainProbes(identity current: Identity, token: UUID, probeToken: UUID, testURL: String) async {
        while isCurrent(token), probeEpoch == probeToken, !Task.isCancelled, !pendingProbes.isEmpty {
            let option = pendingProbes.removeFirst()
            do {
                try validate(current, epoch: token)
                guard let leaf = option.resolvedNode else { continue }
                var request = try ClashLatencyProbe.request(nodeName: leaf, testURL: testURL)
                request = try authorized(request, identity: current)
                let (data, response) = try await transport.data(for: request)
                try validate(current, epoch: token)
                guard probeEpoch == probeToken else { return }
                try checkResponse(response, data: data, accepted: [200])
                let delay = try ClashLatencyProbe.decode(data: data, response: response)
                let result = FlClashNodeLatency(state: .success, milliseconds: delay, checkedAt: now())
                latencies[option.name] = result
                cache[CacheKey(identity: current, candidate: option.name, path: option.path, testURL: testURL)] = result
            } catch {
                guard isCurrent(token), probeEpoch == probeToken, !Task.isCancelled else { return }
                if (error as? FlClashNodeError) == .identityChanged || (error as? FlClashNodeError) == .unauthorized {
                    self.error = message(error)
                    cancelProbes()
                    latencies = [:]
                    return
                }
                let timeout = (error as? URLError)?.code == .timedOut || (error as? FlClashNodeError) == .timeout
                let result = FlClashNodeLatency(state: timeout ? .timeout : .failed, milliseconds: nil, checkedAt: now())
                latencies[option.name] = result
                cache[CacheKey(identity: current, candidate: option.name, path: option.path, testURL: testURL)] = result
            }
        }
    }

    private func readIdentity() throws -> (Identity, String?) {
        let prefs = try readPreferences()
        guard let selected = ActiveSubscription.decode(configuration: prefs) else { throw FlClashNodeError.noProfile }
        let patch = prefs["patchClashConfig"] as? [String: Any] ?? [:]
        guard patch["external-controller"] as? String == "127.0.0.1:9090" else { throw FlClashNodeError.controllerDisabled }
        let secret = patch["secret"] as? String ?? ""
        guard secret.utf8.count <= 4096, !secret.utf8.contains(where: { $0 < 0x20 || $0 == 0x7f }) else {
            throw FlClashNodeError.invalidAuthentication
        }
        return (Identity(profileID: selected.id, secret: secret), selected.currentGroup)
    }

    private func validate(_ expected: Identity, epoch token: UUID) throws {
        try Task.checkCancellation()
        guard isCurrent(token), let latest = try? readIdentity(), latest.0 == expected else {
            throw FlClashNodeError.identityChanged
        }
    }

    private func isCurrent(_ token: UUID) -> Bool { isOpen && epoch == token }

    private func fetchCatalog(identity current: Identity, epoch token: UUID) async throws -> FlClashNodeCatalog {
        let config = try await get("/configs", identity: current, token: token)
        let proxies = try await get("/proxies", identity: current, token: token)
        return try FlClashNodeCatalog.decode(configuration: config, payload: proxies)
    }

    private func get(_ path: String, identity current: Identity, token: UUID) async throws -> [String: Any] {
        try validate(current, epoch: token)
        let request = try request(path: path, identity: current)
        let (data, response) = try await transport.data(for: request)
        try validate(current, epoch: token)
        try checkResponse(response, data: data, accepted: [200])
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw FlClashNodeError.invalidResponse }
        return value
    }

    private func request(path: String, identity: Identity) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = "http"; components.host = "127.0.0.1"; components.port = 9090
        components.percentEncodedPath = path
        guard let url = components.url else { throw FlClashNodeError.invalidSelection }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return try authorized(request, identity: identity)
    }

    private func authorized(_ request: URLRequest, identity: Identity) throws -> URLRequest {
        var result = try FlClashAuthorization.apply(to: request, secret: identity.secret)
        result.setValue(identity.secret.isEmpty ? nil : "Bearer " + identity.secret, forHTTPHeaderField: "Authorization")
        return result
    }

    private func checkResponse(_ response: HTTPURLResponse, data: Data, accepted: Set<Int>) throws {
        guard response.url?.scheme == "http", response.url?.host == "127.0.0.1", response.url?.port == 9090,
              data.count <= 8_000_000 else { throw FlClashNodeError.invalidResponse }
        if [401, 403].contains(response.statusCode) { throw FlClashNodeError.unauthorized }
        if [408, 504].contains(response.statusCode) { throw FlClashNodeError.timeout }
        guard accepted.contains(response.statusCode) else { throw FlClashNodeError.unavailable }
    }

    static func encode(name: String) throws -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_~")
        guard !name.isEmpty, name.utf8.count <= 4096,
              let encoded = name.addingPercentEncoding(withAllowedCharacters: allowed) else { throw FlClashNodeError.invalidSelection }
        return encoded
    }

    private func message(_ error: Error) -> String {
        (error as? FlClashNodeError)?.localizedDescription
            ?? ((error as? URLError)?.code == .timedOut ? FlClashNodeError.timeout.localizedDescription : FlClashNodeError.unavailable.localizedDescription)
    }
}
