import Combine
import Foundation

@MainActor
final class MonitorCoordinator: ObservableObject {
    @Published var snapshot = MonitorSnapshot()
    private(set) var client: ProxyClient
    private let flclash = FlClashMonitor()
    private let shadowrocket = ShadowrocketMonitor()
    private var subscriptions = Set<AnyCancellable>()
    private var running = false

    init() {
        client = ProxyClient(rawValue: UserDefaults.standard.string(forKey: "selectedClient") ?? "") ?? .flclash
        snapshot = MonitorSnapshot(client: client)
        flclash.$snapshot.sink { [weak self] value in
            guard let self, self.client == .flclash else { return }
            self.snapshot = value
        }.store(in: &subscriptions)
        shadowrocket.$snapshot.sink { [weak self] value in
            guard let self, self.client == .shadowrocket else { return }
            self.snapshot = value
        }.store(in: &subscriptions)
    }

    func start() {
        guard !running else { return }
        running = true
        if client == .flclash { flclash.start() } else { shadowrocket.start() }
    }

    func stop() {
        running = false
        flclash.stop()
        shadowrocket.stop()
    }

    func setTrafficScope(_ value: TrafficScope) {
        guard client == .flclash else { return }
        flclash.setTrafficScope(value)
    }

    func refresh() {
        if client == .flclash { flclash.refresh() } else { shadowrocket.refresh() }
    }

    func switchClient() {
        client = client.other
        UserDefaults.standard.set(client.rawValue, forKey: "selectedClient")
        snapshot = MonitorSnapshot(client: client, connectionState: "正在读取 \(client.title)")
        if client == .flclash {
            shadowrocket.stop()
            if running { flclash.start() }
        } else {
            flclash.stop()
            if running { shadowrocket.start() }
        }
    }
}
