import AppKit
import Combine
import Foundation
import Network

struct ShadowrocketNodeOption: Identifiable, Sendable {
    let id: String
    let name: String
    let type: String
    var latencyMS: Int?
    var isTesting = false
    let canTest: Bool
    let canSelect: Bool
    var isCurrent: Bool
    var status: String
    let disabledReason: String?
}

enum ShadowrocketNodeError: LocalizedError, Sendable {
    case unreadable, noSelection, noSubscription, changedSubscription, invalidNode, ambiguousName, appUnavailable, openFailed, notConfirmed
    var errorDescription: String? {
        switch self {
        case .unreadable: return "暂时无法读取 Shadowrocket 节点"
        case .noSelection: return "未识别当前选择的节点"
        case .noSubscription: return "未能确定当前订阅，请在 Shadowrocket 中选择节点"
        case .changedSubscription: return "当前订阅已改变，请刷新节点列表"
        case .invalidNode: return "该节点已改变或不可选择，请刷新列表"
        case .ambiguousName: return "存在同名节点，请先在 Shadowrocket 中改名"
        case .appUnavailable: return "未找到已验证的 Shadowrocket 应用"
        case .openFailed: return "未能将节点选择交给 Shadowrocket"
        case .notConfirmed: return "尚未确认节点已选择，请在 Shadowrocket 中检查"
        }
    }
}

fileprivate struct ShadowrocketNodeEndpoint: Equatable, Sendable {
    let host: String
    let port: UInt16

    static func decode(_ record: [String: Any]) -> Self? {
        let tcpTypes: Set<String> = ["vless", "vmess", "trojan", "trojan-go", "snell", "shadowsocks", "shadowsocksr", "ss", "ssr", "socks", "socks5", "http", "https", "ssh", "anytls"]
        guard let type = record["type"] as? String, tcpTypes.contains(type.lowercased()),
              let host = record["host"] as? String, !host.isEmpty, host.count <= 255,
              !host.contains("://"), !host.contains("/"), !host.contains("@"),
              host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let portText = record["port"] as? String, let port = UInt16(portText), port > 0 else { return nil }
        return Self(host: host, port: port)
    }
}

/// Only display fields and opaque UUIDs escape the archive parser. Credentials
/// and subscription URLs are used neither in the selection URL nor in probes.
struct ShadowrocketNodeCatalog: Sendable {
    let selectedID: String
    let profileName: String
    let sourceKey: String
    let nodes: [ShadowrocketNodeOption]
    fileprivate let endpoints: [String: ShadowrocketNodeEndpoint]

    static func decode(preferences: [String: Any], records: [[String: Any]]) throws -> Self {
        guard records.count <= 20_000,
              let selectedID = identifier(preferences["group.com.liguangming.SelectedServerUUID"]) else { throw ShadowrocketNodeError.noSelection }
        var identifierCounts: [String: Int] = [:]
        var titles: [String] = []
        for record in records {
            if let id = record["uuid"] as? String { identifierCounts[id, default: 0] += 1 }
            // Include every record, including subscription headings and titles
            // that cannot themselves become selectable rows.
            if let name = record["title"] as? String { titles.append(name) }
        }
        // Use the selector's exact Foundation comparison. Sorting once and
        // grouping equal titles avoids both quadratic per-node scans and a
        // lowercasing approximation that could change Unicode name matching.
        titles.sort { $0.caseInsensitiveCompare($1) == .orderedAscending }
        var titleCounts: [String: Int] = [:]
        var start = 0
        while start < titles.count {
            var end = start + 1
            while end < titles.count, titles[start].caseInsensitiveCompare(titles[end]) == .orderedSame { end += 1 }
            for index in start..<end { titleCounts[titles[index]] = end - start }
            start = end
        }
        let selectedMatches = records.filter { $0["uuid"] as? String == selectedID }
        guard selectedMatches.count == 1, let selected = selectedMatches.first,
              selected["type"] as? String != "Subscribe" else { throw ShadowrocketNodeError.noSelection }
        guard let source = selected["data"] as? String, !source.isEmpty else { throw ShadowrocketNodeError.noSubscription }
        let subscriptions = records.filter { $0["type"] as? String == "Subscribe" && $0["host"] as? String == source }
        guard subscriptions.count == 1, let subscription = subscriptions.first,
              let subscriptionID = identifier(subscription["uuid"]),
              identifierCounts[subscriptionID] == 1 else { throw ShadowrocketNodeError.noSubscription }
        let allNodes = records.filter { $0["type"] as? String != "Subscribe" }
        var options: [ShadowrocketNodeOption] = []
        var endpoints: [String: ShadowrocketNodeEndpoint] = [:]
        var seen = Set<String>()
        for record in allNodes where record["data"] as? String == source {
            guard let id = identifier(record["uuid"]), seen.insert(id).inserted,
                  let name = title(record["title"]), !ShadowrocketSelection.isInformationNode(name),
                  let type = title(record["type"]) else { continue }
            let idUnique = identifierCounts[id] == 1
            // The installed application's selector uses caseInsensitiveCompare:.
            let nameUnique = titleCounts[name] == 1
            let endpoint = ShadowrocketNodeEndpoint.decode(record)
            let canSelect = idUnique && nameUnique
            let reason = !idUnique ? "节点标识重复，请在 Shadowrocket 中检查" : (!nameUnique ? "存在同名节点，请先在 Shadowrocket 中改名" : nil)
            if let endpoint, idUnique { endpoints[id] = endpoint }
            options.append(ShadowrocketNodeOption(id: id, name: name, type: type, latencyMS: nil,
                canTest: endpoint != nil && idUnique, canSelect: canSelect, isCurrent: id == selectedID,
                status: endpoint != nil && idUnique ? "待测" : "不支持 TCP 测速", disabledReason: reason))
        }
        return Self(selectedID: selectedID, profileName: title(subscription["title"]) ?? "当前订阅",
                    sourceKey: subscriptionID, nodes: options, endpoints: endpoints)
    }

    func selectionURL(for id: String) throws -> URL {
        guard let option = nodes.first(where: { $0.id == id }) else { throw ShadowrocketNodeError.invalidNode }
        guard option.canSelect else { throw ShadowrocketNodeError.ambiguousName }
        var parts = URLComponents()
        parts.scheme = "shadowrocket"
        parts.host = "select"
        parts.queryItems = [URLQueryItem(name: "s", value: option.name)]
        guard let url = parts.url else { throw ShadowrocketNodeError.invalidNode }
        return url
    }

    func selectionURL(for id: String, matching previous: ShadowrocketNodeCatalog) throws -> URL {
        guard sourceKey == previous.sourceKey else { throw ShadowrocketNodeError.changedSubscription }
        guard let old = previous.nodes.first(where: { $0.id == id }),
              let fresh = nodes.first(where: { $0.id == id }), old.name == fresh.name, old.type == fresh.type,
              previous.endpoints[id] == endpoints[id] else { throw ShadowrocketNodeError.invalidNode }
        return try selectionURL(for: id)
    }

    private static func title(_ value: Any?) -> String? {
        guard let text = value as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.count < 200, !text.contains("://"), text.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
        return text
    }
    private static func identifier(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty, text.count <= 128,
              !text.contains("://"), text.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        return text
    }
}

@MainActor
final class ShadowrocketNodeController: ObservableObject {
    @Published private(set) var nodes: [ShadowrocketNodeOption] = []
    @Published private(set) var selectedID: String?
    @Published private(set) var profileName: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isTesting = false
    @Published private(set) var isSelecting = false
    @Published private(set) var message: String?
    var onSelectionChanged: (() -> Void)?

    private var catalog: ShadowrocketNodeCatalog?
    private var sessionActive = false
    private let catalogReader: (() throws -> ShadowrocketNodeCatalog)?
    private let diskReader: ShadowrocketDiskReader
    private var loadTask: Task<Void, Never>?
    private let applicationURLProvider: (() throws -> URL)?
    private let urlOpener: ((URL, URL, @escaping (Bool) -> Void) -> Void)?
    private var generation = UUID()
    private var generationStartedAt = ProcessInfo.processInfo.systemUptime
    private var testTask: Task<Void, Never>?
    private var selectionTask: Task<Void, Never>?
    private var pathMonitor: NWPathMonitor?
    private var interfaceContinuation: CheckedContinuation<NWInterface?, Never>?
    private var interfaceRequestID: UUID?
    private let queue = DispatchQueue(label: "local.shadowrocket.node-tests")
    private struct CachedProbe { let endpoint: ShadowrocketNodeEndpoint; let at: Double; let milliseconds: Int?; let status: String }
    private var cache: [String: CachedProbe] = [:]
    private struct Probe { let connection: NWConnection; let continuation: CheckedContinuation<(Int?, String), Never>; let timeout: DispatchWorkItem }
    private var probes: [UUID: Probe] = [:]

    init(catalogReader: (() throws -> ShadowrocketNodeCatalog)? = nil,
         applicationURLProvider: (() throws -> URL)? = nil,
         urlOpener: ((URL, URL, @escaping (Bool) -> Void) -> Void)? = nil,
         reader: ShadowrocketDiskReader? = nil) {
        self.diskReader = reader ?? .shared
        self.catalogReader = catalogReader
        self.applicationURLProvider = applicationURLProvider
        self.urlOpener = urlOpener
    }

    func load(automaticallyTest: Bool = true) {
        guard !isSelecting else { return }
        cancel()
        sessionActive = true
        isLoading = true
        let run = generation
        loadTask = Task { [weak self] in
            guard let self, self.sessionActive, run == self.generation, !Task.isCancelled else { return }
            defer { if run == self.generation { self.isLoading = false; self.loadTask = nil } }
            do {
                let fresh = try await self.readCatalog()
                guard self.sessionActive, run == self.generation, !Task.isCancelled else { return }
                self.install(fresh)
                self.message = fresh.nodes.isEmpty ? "当前订阅没有可显示的节点" : nil
                if automaticallyTest { self.testAll() }
            } catch is CancellationError {
                return
            } catch {
                guard self.sessionActive, run == self.generation, !Task.isCancelled else { return }
                self.catalog = nil; self.nodes = []; self.selectedID = nil; self.profileName = nil
                self.message = self.safeMessage(error)
            }
        }
    }

    func testAll(force: Bool = false) {
        guard sessionActive, !isSelecting, !isTesting, let catalog else { return }
        message = nil
        let now = ProcessInfo.processInfo.systemUptime
        var pending: [(String, ShadowrocketNodeEndpoint)] = []
        for index in nodes.indices where nodes[index].canTest {
            let id = nodes[index].id
            guard let endpoint = catalog.endpoints[id] else { continue }
            if !force, let hit = cache[id], hit.endpoint == endpoint, now >= hit.at, now - hit.at < 30 {
                nodes[index].latencyMS = hit.milliseconds; nodes[index].status = hit.status
            } else {
                nodes[index].latencyMS = nil; nodes[index].isTesting = true; nodes[index].status = "测速中"
                pending.append((id, endpoint))
            }
        }
        guard !pending.isEmpty else { return }
        isTesting = true
        let run = generation
        testTask = Task { [weak self] in
            guard let self else { return }
            guard self.sessionActive, run == self.generation, !Task.isCancelled else { return }
            guard let interface = await self.physicalInterface(generation: run), run == self.generation, !Task.isCancelled else {
                if run == self.generation { self.finishUnavailableTests(); self.isTesting = false }
                return
            }
            // Three workers keep the number of real TCP handshakes bounded.
            await withTaskGroup(of: Void.self) { group in
                for lane in 0..<min(3, pending.count) {
                    group.addTask { [weak self] in
                        for index in stride(from: lane, to: pending.count, by: 3) {
                            guard !Task.isCancelled, let self else { return }
                            await self.runProbe(id: pending[index].0, endpoint: pending[index].1, interface: interface, generation: run)
                        }
                    }
                }
            }
            if run == self.generation { self.isTesting = false; self.testTask = nil }
        }
    }

    func selectNode(id: String) {
        guard sessionActive, !isLoading, !isSelecting, let catalog else { return }
        let previousSource = catalog.sourceKey
        cancelWork(closeSession: false)
        isSelecting = true; message = "正在交给 Shadowrocket 选择…"
        let run = generation
        selectionTask = Task { [weak self] in
            guard let self, self.sessionActive, run == self.generation, !Task.isCancelled else { return }
            do {
                let fresh = try await self.readCatalog()
                guard self.sessionActive, run == self.generation, !Task.isCancelled else { return }
                _ = try fresh.selectionURL(for: id, matching: catalog)
                self.install(fresh)
                if fresh.selectedID == id {
                    self.isSelecting = false; self.message = "当前已选择该节点"
                    self.onSelectionChanged?()
                    return
                }
                let result = await self.dispatchSelection(id: id, matching: catalog, generation: run)
                guard self.sessionActive, run == self.generation, !Task.isCancelled else { return }
                if case .failure(let error) = result { self.isSelecting = false; self.message = self.safeMessage(error); return }
                for _ in 0..<20 {
                    guard self.sessionActive, run == self.generation, !Task.isCancelled else { return }
                    if let observed = try? await self.readCatalog() {
                        guard self.sessionActive, run == self.generation, !Task.isCancelled else { return }
                        guard observed.sourceKey == previousSource else { self.isSelecting = false; self.message = ShadowrocketNodeError.changedSubscription.localizedDescription; return }
                        if observed.selectedID == id {
                            self.install(observed); self.isSelecting = false
                            self.message = "已选择节点"
                            self.onSelectionChanged?()
                            return
                        }
                    }
                    try await Task.sleep(nanoseconds: 250_000_000)
                }
                if run == self.generation { self.isSelecting = false; self.message = ShadowrocketNodeError.notConfirmed.localizedDescription }
            } catch is CancellationError {
                return
            } catch {
                guard self.sessionActive, run == self.generation, !Task.isCancelled else { return }
                self.isSelecting = false; self.message = self.safeMessage(error)
            }
        }
    }

    func cancel() {
        cancelWork(closeSession: true)
    }
    private func cancelWork(closeSession: Bool) {
        if closeSession { sessionActive = false }
        generation = UUID()
        generationStartedAt = ProcessInfo.processInfo.systemUptime
        loadTask?.cancel(); loadTask = nil
        isLoading = false
        testTask?.cancel(); testTask = nil
        selectionTask?.cancel(); selectionTask = nil
        finishInterface(nil)
        for id in Array(probes.keys) { finishProbe(id: id, milliseconds: nil, status: "已取消") }
        for index in nodes.indices where nodes[index].isTesting { nodes[index].isTesting = false; nodes[index].status = "待测" }
        isTesting = false; isSelecting = false
    }

    private func readCatalog() async throws -> ShadowrocketNodeCatalog {
        // Synchronous fixture-only injection stays on MainActor; production
        // always goes through the shared single-flight background disk reader.
        if let catalogReader { return try catalogReader() }
        return try await diskReader.read(notBefore: generationStartedAt).catalog.get()
    }
    private func install(_ fresh: ShadowrocketNodeCatalog) {
        catalog = fresh; nodes = fresh.nodes; selectedID = fresh.selectedID; profileName = fresh.profileName
        let now = ProcessInfo.processInfo.systemUptime
        for index in nodes.indices {
            if let hit = cache[nodes[index].id], hit.endpoint == fresh.endpoints[nodes[index].id], now >= hit.at, now - hit.at < 30 {
                nodes[index].latencyMS = hit.milliseconds; nodes[index].status = hit.status
            }
        }
    }
    private func applicationURL() throws -> URL {
        if let applicationURLProvider { return try applicationURLProvider() }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.liguangming.Shadowrocket"),
              Bundle(url: url)?.bundleIdentifier == "com.liguangming.Shadowrocket" else { throw ShadowrocketNodeError.appUnavailable }
        return url
    }
    private func dispatchSelection(id: String, matching previous: ShadowrocketNodeCatalog,
                                   generation run: UUID) async -> Result<Void, Error> {
        let fresh: ShadowrocketNodeCatalog
        do { fresh = try await readCatalog() }
        catch { return .failure(error) }
        // The disk await is finished. Cancellation/session and identity checks
        // below, and handing the URL to the verified app, are one MainActor turn.
        return await withCheckedContinuation { continuation in
            guard sessionActive, run == generation, !Task.isCancelled else {
                continuation.resume(returning: .failure(CancellationError())); return
            }
            do {
                let url = try fresh.selectionURL(for: id, matching: previous)
                let application = try applicationURL()
                if fresh.selectedID == id {
                    continuation.resume(returning: .success(())); return
                }
                if let urlOpener {
                    urlOpener(url, application) { opened in
                        continuation.resume(returning: opened ? .success(()) : .failure(ShadowrocketNodeError.openFailed))
                    }
                } else {
                    let configuration = NSWorkspace.OpenConfiguration()
                    NSWorkspace.shared.open([url], withApplicationAt: application, configuration: configuration) { app, error in
                        let opened = app?.bundleIdentifier == "com.liguangming.Shadowrocket" && error == nil
                        continuation.resume(returning: opened ? .success(()) : .failure(ShadowrocketNodeError.openFailed))
                    }
                }
            } catch { continuation.resume(returning: .failure(error)) }
        }
    }
    private func physicalInterface(generation run: UUID) async -> NWInterface? {
        await withCheckedContinuation { continuation in
            guard sessionActive, run == generation, !Task.isCancelled else { continuation.resume(returning: nil); return }
            let requestID = UUID()
            interfaceRequestID = requestID; interfaceContinuation = continuation
            let monitor = NWPathMonitor(); pathMonitor = monitor
            monitor.pathUpdateHandler = { [weak self] path in
                Task { @MainActor in
                    guard let self, self.interfaceRequestID == requestID else { return }
                    let physical = path.availableInterfaces.filter { [.wifi, .wiredEthernet, .cellular].contains($0.type) }
                    let preferred = physical.first { path.usesInterfaceType($0.type) } ?? physical.first
                    self.finishInterface(path.status == .satisfied ? preferred : nil)
                }
            }
            monitor.start(queue: queue)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, self.interfaceRequestID == requestID else { return }
                self.finishInterface(nil)
            }
        }
    }
    private func finishInterface(_ interface: NWInterface?) {
        pathMonitor?.cancel(); pathMonitor = nil; interfaceRequestID = nil
        let continuation = interfaceContinuation; interfaceContinuation = nil
        continuation?.resume(returning: interface)
    }
    private func finishUnavailableTests() {
        for index in nodes.indices where nodes[index].isTesting {
            nodes[index].isTesting = false; nodes[index].latencyMS = nil; nodes[index].status = "无法直接测速"
        }
        message = "未找到可用于 TCP 测速的物理网络连接"
    }
    private func runProbe(id: String, endpoint: ShadowrocketNodeEndpoint, interface: NWInterface, generation run: UUID) async {
        guard run == generation, !Task.isCancelled, let port = NWEndpoint.Port(rawValue: endpoint.port) else { return }
        let start = ProcessInfo.processInfo.systemUptime
        let result: (Int?, String) = await withCheckedContinuation { continuation in
            let probeID = UUID()
            let parameters = NWParameters.tcp
            parameters.requiredInterface = interface
            parameters.prohibitedInterfaceTypes = [.other, .loopback]
            let connection = NWConnection(host: NWEndpoint.Host(endpoint.host), port: port, using: parameters)
            let timeout = DispatchWorkItem { [weak self] in self?.finishProbe(id: probeID, milliseconds: nil, status: "超时") }
            probes[probeID] = Probe(connection: connection, continuation: continuation, timeout: timeout)
            connection.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self, self.probes[probeID] != nil else { return }
                    switch state {
                    case .ready:
                        let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
                        self.finishProbe(id: probeID, milliseconds: max(1, Int(elapsed.rounded())), status: "TCP")
                    case .failed: self.finishProbe(id: probeID, milliseconds: nil, status: "失败")
                    case .cancelled: self.finishProbe(id: probeID, milliseconds: nil, status: "已取消")
                    default: break
                    }
                }
            }
            connection.start(queue: queue)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: timeout)
        }
        guard run == generation, !Task.isCancelled, let index = nodes.firstIndex(where: { $0.id == id }) else { return }
        nodes[index].isTesting = false; nodes[index].latencyMS = result.0; nodes[index].status = result.1
        cache[id] = CachedProbe(endpoint: endpoint, at: ProcessInfo.processInfo.systemUptime, milliseconds: result.0, status: result.1)
    }
    private func finishProbe(id: UUID, milliseconds: Int?, status: String) {
        guard let probe = probes.removeValue(forKey: id) else { return }
        probe.timeout.cancel(); probe.connection.stateUpdateHandler = nil; probe.connection.cancel()
        probe.continuation.resume(returning: (milliseconds, status))
    }
    private func safeMessage(_ error: Error) -> String {
        if let failure = error as? ShadowrocketReadError { return failure.message }
        return (error as? ShadowrocketNodeError)?.localizedDescription ?? ShadowrocketNodeError.unreadable.localizedDescription
    }
}
