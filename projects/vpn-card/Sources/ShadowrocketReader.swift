import Foundation

struct ShadowrocketTCPAddress: Equatable, Sendable {
    let host: String
    let port: UInt16
}

/// Only parsed display/selection values leave the file-reading queue. Raw
/// archives and credentials are neither retained nor sent to the main actor.
struct ShadowrocketDiskSnapshot: Sendable {
    let selection: ShadowrocketSelection?
    let endpoint: ShadowrocketTCPAddress?
    let catalog: Result<ShadowrocketNodeCatalog, ShadowrocketNodeError>

    static func decode(preferences: [String: Any], records: [[String: Any]]) -> Self {
        let selection = ShadowrocketSelection.decode(preferences: preferences, records: records)
        let record = records.first { $0["uuid"] as? String == selection?.selectedUUID }
        let address = selection?.nodeName == nil ? nil : record.flatMap(endpoint)
        let catalog: Result<ShadowrocketNodeCatalog, ShadowrocketNodeError>
        do { catalog = .success(try ShadowrocketNodeCatalog.decode(preferences: preferences, records: records)) }
        catch { catalog = .failure(error as? ShadowrocketNodeError ?? .unreadable) }
        return Self(selection: selection, endpoint: address, catalog: catalog)
    }

    private static func endpoint(_ record: [String: Any]) -> ShadowrocketTCPAddress? {
        let type = (record["type"] as? String ?? "").lowercased()
        let supported = ["vless", "vmess", "trojan", "trojan-go", "snell", "shadowsocks", "shadowsocksr", "ss", "ssr", "socks", "socks5", "http", "https", "ssh"]
        guard supported.contains(type), let host = record["host"] as? String,
              !host.isEmpty, host.count <= 255, !host.contains("://"),
              host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let portText = record["port"] as? String, let port = UInt16(portText), port > 0 else { return nil }
        return ShadowrocketTCPAddress(host: host, port: port)
    }
}

enum ShadowrocketReadError: Error, Sendable {
    case waiting
    case file(domain: String, code: Int)

    var message: String {
        switch self {
        case .waiting: return "正在等待读取应用数据"
        case let .file(domain, code):
            let denied = domain == NSCocoaErrorDomain && code == NSFileReadNoPermissionError
                || domain == NSPOSIXErrorDomain && [1, 13].contains(code)
            return denied ? "请允许读取应用数据" : "节点数据读取失败"
        }
    }
}

/// One process-wide physical read serves both monitoring and the node picker.
/// Cancelling or timing out a caller releases only its continuation. A blocked
/// kernel open still owns the gate until it really returns, so polling cannot
/// create an unbounded queue of blocked threads or repeated access prompts.
@MainActor
final class ShadowrocketDiskReader {
    static let shared = ShadowrocketDiskReader()
    private let queue = DispatchQueue(label: "local.homeatlas.shadowrocket-files", qos: .utility)
    private let operation: @Sendable () throws -> ShadowrocketDiskSnapshot
    private var flight: UUID?
    private var flightStartedAt: TimeInterval?
    private struct Waiter {
        let continuation: CheckedContinuation<ShadowrocketDiskSnapshot, Error>
        let timeout: Task<Void, Never>
    }
    private var waiters: [UUID: Waiter] = [:]

    init(operation: (@Sendable () throws -> ShadowrocketDiskSnapshot)? = nil) {
        self.operation = operation ?? { try ShadowrocketDiskReader.readFiles() }
    }

    func read(timeout: TimeInterval = 2, notBefore: TimeInterval = 0) async throws -> ShadowrocketDiskSnapshot {
        try Task.checkCancellation()
        // A timed-out/cancelled physical read must finish before retrying.
        guard flight == nil || !waiters.isEmpty, waiters.count < 4 else { throw ShadowrocketReadError.waiting }
        guard flightStartedAt.map({ $0 >= notBefore }) ?? true else { throw ShadowrocketReadError.waiting }
        let duration = timeout.isFinite ? max(0.01, min(timeout, 30)) : 2
        let id = UUID()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                let timer = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000)) }
                    catch { return }
                    self?.removeWaiter(id, error: ShadowrocketReadError.waiting)
                }
                waiters[id] = Waiter(continuation: continuation, timeout: timer)
                guard flight == nil else { return }
                let token = UUID()
                flight = token
                flightStartedAt = ProcessInfo.processInfo.systemUptime
                let operation = self.operation
                queue.async { [weak self] in
                    let result: Result<ShadowrocketDiskSnapshot, ShadowrocketReadError>
                    do { result = .success(try operation()) }
                    catch {
                        let failure = error as NSError
                        // Keep only error classification, never paths/userInfo.
                        result = .failure(.file(domain: failure.domain, code: failure.code))
                    }
                    Task { @MainActor [weak self] in self?.complete(token, result: result) }
                }
            }
        }, onCancel: { [weak self] in
            Task { @MainActor in self?.removeWaiter(id, error: CancellationError()) }
        })
    }

    private func removeWaiter(_ id: UUID, error: Error) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        waiter.timeout.cancel()
        waiter.continuation.resume(throwing: error)
    }

    private func complete(_ token: UUID, result: Result<ShadowrocketDiskSnapshot, ShadowrocketReadError>) {
        guard flight == token else { return }
        flight = nil
        flightStartedAt = nil
        let completed = Array(waiters.values)
        waiters.removeAll()
        for waiter in completed {
            waiter.timeout.cancel()
            switch result {
            case .success(let value): waiter.continuation.resume(returning: value)
            case .failure(let error): waiter.continuation.resume(throwing: error)
            }
        }
    }

    nonisolated private static func readFiles() throws -> ShadowrocketDiskSnapshot {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.liguangming.Shadowrocket")
        let data = try Data(contentsOf: root.appendingPathComponent("Library/Preferences/group.com.liguangming.Shadowrocket.plist"))
        guard data.count <= 4_000_000,
              let preferences = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let records = try ShadowrocketArchive.decode(Data(contentsOf: root.appendingPathComponent("ServerManager"))) as? [[String: Any]],
              records.count <= 20_000 else { throw CocoaError(.fileReadCorruptFile) }
        return ShadowrocketDiskSnapshot.decode(preferences: preferences, records: records)
    }
}
