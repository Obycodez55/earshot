import Foundation
import Network

/// Listens on 127.0.0.1 only. The phone reaches it through `adb reverse`,
/// so nothing is exposed to the network.
/// Protocol: one line in ("toggle" | "start" | "stop" | "status"), one line out.
final class ControlServer {
    static let port: UInt16 = 47800

    private var listener: NWListener?
    private let handler: @MainActor (String) async -> String

    init(handler: @escaping @MainActor (String) async -> String) {
        self.handler = handler
    }

    func start() {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: Self.port)!)
        guard let l = try? NWListener(using: params) else {
            NSLog("Earshot: cannot open control port \(Self.port)")
            return
        }
        l.newConnectionHandler = { [weak self] conn in self?.serve(conn) }
        l.stateUpdateHandler = { state in
            if case .failed(let err) = state { NSLog("Earshot: control listener failed: \(err)") }
        }
        l.start(queue: .global(qos: .userInitiated))
        listener = l
    }

    private func serve(_ conn: NWConnection) {
        conn.start(queue: .global(qos: .userInitiated))
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64) { [weak self] data, _, _, _ in
            guard let self, let data, !data.isEmpty else { conn.cancel(); return }
            let cmd = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            Task {
                let reply = await self.handler(cmd)
                conn.send(content: Data((reply + "\n").utf8), completion: .contentProcessed { _ in
                    conn.cancel()
                })
            }
        }
    }
}
