import Foundation
import Network

/// The WebSocket server at the heart of the agent.
///
/// Responsibilities (`PROTOCOL.md` §1–§2):
///  - listen on TCP `8765` speaking WebSocket via `NWProtocolWebSocket`,
///  - advertise `_rimote._tcp` over Bonjour using the Mac's display name,
///  - hand each accepted socket to a `ClientConnection`, and
///  - collapse per-connection activity into a single menubar icon state.
///
/// The server is `@MainActor`-isolated. `NWListener` callbacks fire on a
/// background queue and hop to the main actor before mutating any state, so the
/// server, its connections, and the pairing/token authority are all touched on
/// one actor — no locks, no data races.
@MainActor
final class RimoteServer {

    static let port: NWEndpoint.Port = 8765
    static let serviceType = "_rimote._tcp"

    /// Reported listener lifecycle, surfaced to the menubar icon.
    enum Status {
        case idle
        case connected
        case error(String)
    }

    private let queue = DispatchQueue(label: "app.rimote.mac.server")
    private var listener: NWListener?
    private var connections: Set<ClientConnection> = []

    private unowned let authority: ClientConnection.Authority
    private let onStatusChange: (Status) -> Void

    /// - Parameters:
    ///   - authority: owner of pairing + token state (the app's `AppState`).
    ///   - onStatusChange: invoked with listener/connection status changes.
    init(authority: ClientConnection.Authority, onStatusChange: @escaping (Status) -> Void) {
        self.authority = authority
        self.onStatusChange = onStatusChange
    }

    // MARK: - Lifecycle

    /// Starts the listener and Bonjour advertisement. Reports `.error` if the
    /// port is taken or the listener otherwise fails.
    func start() {
        let parameters = NWParameters(tls: nil, tcp: .init())
        parameters.allowLocalEndpointReuse = true

        let websocket = NWProtocolWebSocket.Options()
        websocket.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)

        do {
            let listener = try NWListener(using: parameters, on: Self.port)
            listener.service = NWListener.Service(name: authority.deviceName, type: Self.serviceType)

            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.onStatusChange(.idle)
                    case .failed(let error):
                        self?.onStatusChange(.error(error.localizedDescription))
                    default:
                        break
                    }
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }

            listener.start(queue: queue)
            self.listener = listener
        } catch {
            onStatusChange(.error(error.localizedDescription))
        }
    }

    func stop() {
        connections.forEach { $0.cancel() }
        connections.removeAll()
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connections

    private func accept(_ nwConnection: NWConnection) {
        let client = ClientConnection(
            connection: nwConnection,
            queue: queue,
            authority: authority,
            onActiveChange: { [weak self] _ in self?.refreshStatus() },
            onClosed: { [weak self] client in self?.remove(client) }
        )
        connections.insert(client)
        client.start()
    }

    private func remove(_ client: ClientConnection) {
        connections.remove(client)
        refreshStatus()
    }

    /// Connected if any session exists, otherwise idle.
    private func refreshStatus() {
        onStatusChange(connections.isEmpty ? .idle : .connected)
    }
}

extension ClientConnection: Hashable {
    nonisolated static func == (lhs: ClientConnection, rhs: ClientConnection) -> Bool {
        lhs === rhs
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}
