import Foundation

private final class BlockingFixture: @unchecked Sendable {
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private var reads = 0
    private var ended = 0
    private var blocked = true
    private var mainThread = false
    let blockCall: Int
    let value: ShadowrocketDiskSnapshot
    init(_ value: ShadowrocketDiskSnapshot, blockCall: Int = 1) { self.value = value; self.blockCall = blockCall }
    var counts: (Int, Int, Bool) { lock.lock(); defer { lock.unlock() }; return (reads, ended, mainThread) }
    func run() throws -> ShadowrocketDiskSnapshot {
        lock.lock(); reads += 1; let shouldBlock = blocked && reads == blockCall
        mainThread = mainThread || Thread.isMainThread; lock.unlock()
        if shouldBlock { _ = gate.wait(timeout: .now() + 5) }
        lock.lock(); ended += 1; lock.unlock()
        return value
    }
    func release() { lock.lock(); blocked = false; lock.unlock(); gate.signal() }
}

@main enum ShadowrocketReaderTests {
    @MainActor static func main() async throws {
        var checks = 0
        func expect(_ value: @autoclosure () -> Bool, _ title: String) { precondition(value(), title); checks += 1 }
        func until(_ condition: () -> Bool) async throws {
            for _ in 0..<400 {
                if condition() { return }
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            preconditionFailure("Fixture condition timed out")
        }
        func settle() async throws { try await Task.sleep(nanoseconds: 30_000_000) }
        let source = "https://fixture.invalid/subscription"
        let prefs: [String: Any] = ["group.com.liguangming.SelectedServerUUID": "a"]
        let records: [[String: Any]] = [
            ["uuid": "a", "title": "Fixture A", "type": "VLESS", "host": "fixture.invalid", "port": "443", "data": source],
            ["uuid": "b", "title": "Fixture B", "type": "VLESS", "host": "fixture.invalid", "port": "443", "data": source],
            ["uuid": "subscription", "title": "Fixture package", "type": "Subscribe", "host": source],
        ]
        let payload = ShadowrocketDiskSnapshot.decode(preferences: prefs, records: records)

        let blocked = BlockingFixture(payload)
        let reader = ShadowrocketDiskReader(operation: { try blocked.run() })
        let first = Task { try await reader.read(timeout: 0.06) }
        try await until { blocked.counts.0 == 1 }
        var heartbeat = false
        Task { @MainActor in heartbeat = true }
        try await until { heartbeat }
        expect(!blocked.counts.2 && blocked.counts.1 == 0, "A blocked file reader must run off the main thread while MainActor continues")
        let joined = Task { try await reader.read(timeout: 0.06) }
        do { _ = try await first.value; preconditionFailure("Expected logical timeout") }
        catch ShadowrocketReadError.waiting { checks += 1 }
        do { _ = try await joined.value; preconditionFailure("Expected joined timeout") }
        catch ShadowrocketReadError.waiting { checks += 1 }
        for _ in 0..<100 {
            do { _ = try await reader.read(timeout: 0.01); preconditionFailure("Blocked physical read must keep its gate") }
            catch ShadowrocketReadError.waiting { }
        }
        expect(blocked.counts.0 == 1 && blocked.counts.1 == 0, "Timeouts and repeated refreshes must not queue additional physical reads")
        blocked.release()
        try await until { blocked.counts.1 == 1 }
        try await settle()
        let next = try await reader.read()
        expect(next.selection?.selectedUUID == "a" && blocked.counts.0 == 2, "A fresh physical read becomes available only after the blocked one finishes")

        let cancelledRead = BlockingFixture(payload)
        let cancellationReader = ShadowrocketDiskReader(operation: { try cancelledRead.run() })
        let pending = Task { try await cancellationReader.read() }
        try await until { cancelledRead.counts.0 == 1 }
        pending.cancel()
        do { _ = try await pending.value; preconditionFailure("Expected cancellation") }
        catch is CancellationError { checks += 1 }
        do { _ = try await cancellationReader.read(); preconditionFailure("Cancellation cannot abort a kernel open") }
        catch ShadowrocketReadError.waiting { checks += 1 }
        expect(cancelledRead.counts.0 == 1, "Cancelling the logical caller must not permit another blocked worker")
        cancelledRead.release()
        try await settle()

        let oldFlight = BlockingFixture(payload)
        let epochReader = ShadowrocketDiskReader(operation: { try oldFlight.run() })
        let original = Task { try await epochReader.read() }
        try await until { oldFlight.counts.0 == 1 }
        let newEpoch = ProcessInfo.processInfo.systemUptime
        do { _ = try await epochReader.read(notBefore: newEpoch); preconditionFailure("A new session must not join an old physical read") }
        catch ShadowrocketReadError.waiting { checks += 1 }
        oldFlight.release(); _ = try await original.value

        let monitorFixture = BlockingFixture(payload)
        let monitorReader = ShadowrocketDiskReader(operation: { try monitorFixture.run() })
        let monitor = ShadowrocketMonitor(reader: monitorReader)
        monitor.refreshMetadata()
        try await until { monitorFixture.counts.0 == 1 }
        monitor.stop()
        monitorFixture.release()
        try await settle()
        expect(monitor.snapshot.nodeName == nil && monitor.snapshot.connectionState == "监测已暂停", "A stopped monitor must reject late metadata without touching live system services")
        monitor.refreshMetadata()
        try await until { monitor.snapshot.nodeName == "Fixture A" }
        expect(monitorFixture.counts.0 == 2, "The next monitor generation must read a fresh snapshot")
        monitor.stop()

        let loadFixture = BlockingFixture(payload)
        let loadReader = ShadowrocketDiskReader(operation: { try loadFixture.run() })
        var opens = 0
        let app = URL(fileURLWithPath: "/tmp/FixtureShadowrocket.app")
        let loader = ShadowrocketNodeController(applicationURLProvider: { app }, urlOpener: { _, _, done in opens += 1; done(true) }, reader: loadReader)
        loader.load(automaticallyTest: false)
        try await until { loadFixture.counts.0 == 1 }
        expect(loader.isLoading && loader.nodes.isEmpty, "Opening a node picker must return immediately while its archive is waiting")
        loader.cancel(); loadFixture.release()
        try await settle()
        expect(!loader.isLoading && loader.nodes.isEmpty && opens == 0, "Closing during a blocked catalog load must reject its late results")

        let finalReadFixture = BlockingFixture(payload, blockCall: 3)
        let finalReader = ShadowrocketDiskReader(operation: { try finalReadFixture.run() })
        let picker = ShadowrocketNodeController(applicationURLProvider: { app }, urlOpener: { _, _, done in opens += 1; done(true) }, reader: finalReader)
        picker.load(automaticallyTest: false)
        try await until { !picker.isLoading }
        picker.selectNode(id: "b")
        try await until { finalReadFixture.counts.0 == 3 }
        expect(picker.isSelecting && opens == 0, "The final identity read must finish before URL dispatch")
        picker.cancel(); finalReadFixture.release()
        try await settle()
        expect(opens == 0 && !picker.isSelecting, "Cancelling the final background read must prevent dispatch on resumption")

        let denied = ShadowrocketDiskReader(operation: { throw CocoaError(.fileReadNoPermission) })
        do { _ = try await denied.read(); preconditionFailure("Expected permission error") }
        catch let error as ShadowrocketReadError { expect(error.message == "请允许读取应用数据", "Explicit denial must remain distinguishable from a still-pending open") }
        print("PASS \(checks) background-reader checks; only synthetic fixtures, no containers, system sampling, applications or probes accessed")
    }
}
