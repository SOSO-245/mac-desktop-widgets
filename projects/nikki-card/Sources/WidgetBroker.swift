import Foundation
import Network

/// Read-only loopback snapshot. No credentials, subscription URLs or write endpoints.
@MainActor final class NikkiWidgetBroker {
    private var listener: NWListener?
    var value = NikkiWidgetData()
    func start() {
        guard listener == nil else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host:"127.0.0.1",port:NWEndpoint.Port(rawValue:NikkiWidgetData.port)!)
            let listener = try NWListener(using:parameters)
            self.listener = listener
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed = state { Task { @MainActor in self?.listener?.cancel(); self?.listener = nil } }
            }
            listener.newConnectionHandler = { [weak self] connection in
                connection.start(queue:.global(qos:.utility))
                let timeout = DispatchWorkItem { connection.cancel() }
                DispatchQueue.global().asyncAfter(deadline:.now()+4,execute:timeout)
                Self.receive(connection,buffer:Data(),timeout:timeout) { [weak self] in
                    guard let self else { return Data() }
                    var payload = self.value
                    payload.snapshot.routeIdentity = ""
                    return (try? JSONEncoder().encode(payload)) ?? Data()
                }
            }
            listener.start(queue:.global(qos:.utility))
        } catch { listener = nil }
    }
    nonisolated private static func receive(_ connection:NWConnection,buffer:Data,timeout:DispatchWorkItem,read:@escaping @MainActor ()->Data) {
        connection.receive(minimumIncompleteLength:1,maximumLength:4096) { part,_,ended,error in
            let bytes = buffer + (part ?? Data())
            guard error == nil, bytes.count <= 8192 else { timeout.cancel();connection.cancel();return }
            guard let text = String(data:bytes,encoding:.utf8), text.contains("\r\n\r\n") else {
                if ended { timeout.cancel();connection.cancel() } else { receive(connection,buffer:bytes,timeout:timeout,read:read) };return
            }
            Task { @MainActor in
                let valid = text.components(separatedBy:"\r\n").first == "GET /snapshot HTTP/1.1"
                let body = valid ? read() : Data()
                let header = "HTTP/1.1 \(valid ? "200 OK" : "404 Not Found")\r\nContent-Type: application/json\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Length: \(body.count)\r\n\r\n"
                connection.send(content:Data(header.utf8)+body,completion:.contentProcessed { _ in timeout.cancel();connection.cancel() })
            }
        }
    }
    func stop() { listener?.cancel();listener = nil }
}
