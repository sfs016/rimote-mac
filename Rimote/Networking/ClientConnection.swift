import Foundation
import Network

/// Wraps a single WebSocket client connection and implements the message-level
/// protocol: pairing handshake, token-authenticated commands, status pushes, and
/// heartbeat (`PROTOCOL.md` §4–§6).
///
/// One JSON object per WebSocket text frame; `NWProtocolWebSocket` handles
/// framing, so there is no byte buffering here. The type is `@MainActor`-isolated
/// so all protocol state and the shared pairing/token decisions are touched on a
/// single actor; `NWConnection` callbacks (which fire on a background queue) hop
/// back to the main actor before doing any work.
@MainActor
final class ClientConnection {

    /// Everything the connection needs from the app to make protocol decisions.
    /// Implemented by `AppState`, which owns the pairing and token state.
    @MainActor
    protocol Authority: AnyObject {
        /// Begin a pairing attempt; returns the PIN now shown in the menubar.
        func beginPairing() -> String
        /// Verify a submitted PIN; on success returns a freshly issued token.
        func verifyPIN(_ pin: String) -> Result<String, PairError>
        /// Constant-time check of a command token against the stored secret.
        func isTokenValid(_ token: String?) -> Bool
        /// The Mac's display name, used in challenges and status pushes.
        var deviceName: String { get }
    }

    enum PairError: String, Error {
        case wrongPIN = "wrong_pin"
        case expired
    }

    private let connection: NWConnection
    private let queue: DispatchQueue
    private unowned let authority: Authority
    private let onActiveChange: (Bool) -> Void
    private let onClosed: (ClientConnection) -> Void

    private var heartbeat: Task<Void, Never>?
    private var isAuthenticated = false
    private var didReportActive = false

    init(
        connection: NWConnection,
        queue: DispatchQueue,
        authority: Authority,
        onActiveChange: @escaping (Bool) -> Void,
        onClosed: @escaping (ClientConnection) -> Void
    ) {
        self.connection = connection
        self.queue = queue
        self.authority = authority
        self.onActiveChange = onActiveChange
        self.onClosed = onClosed
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.receiveNext()
                    self?.startHeartbeat()
                case .failed, .cancelled:
                    self?.teardown()
                default:
                    break
                }
            }
        }
        connection.start(queue: queue)
    }

    func cancel() {
        connection.cancel()
    }

    // MARK: - Receive loop

    private func receiveNext() {
        connection.receiveMessage { [weak self] data, context, _, error in
            Task { @MainActor in
                guard let self else { return }
                if let data, !data.isEmpty, self.isTextFrame(context) {
                    self.handle(data)
                }
                if error != nil {
                    self.teardown()
                    return
                }
                self.receiveNext()
            }
        }
    }

    private nonisolated func isTextFrame(_ context: NWConnection.ContentContext?) -> Bool {
        guard let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
            as? NWProtocolWebSocket.Metadata else { return false }
        return metadata.opcode == .text || metadata.opcode == .binary
    }

    private func handle(_ data: Data) {
        guard let message = WireMessage.Inbound.parse(data) else { return }

        switch message {
        case .pairRequest:
            handlePairRequest()
        case .pairVerify(let pin):
            handlePairVerify(pin)
        case .statusRequest(let token):
            handleStatusRequest(token)
        case .command(let action, let token):
            handleCommand(action, token: token)
        case .unknown:
            break
        }
    }

    // MARK: - Protocol handlers

    private func handlePairRequest() {
        _ = authority.beginPairing() // PIN is shown in the menubar, never sent.
        send(WireMessage.pairChallenge(deviceName: authority.deviceName))
    }

    private func handlePairVerify(_ pin: String) {
        switch authority.verifyPIN(pin) {
        case .success(let token):
            isAuthenticated = true
            markActive(true)
            send(WireMessage.pairSuccess(token: token, deviceName: authority.deviceName))
            pushStatus()
        case .failure(let error):
            send(WireMessage.pairFailure(message: error.rawValue))
        }
    }

    private func handleStatusRequest(_ token: String?) {
        guard ensureAuthenticated(token: token, action: "status") else { return }
        pushStatus()
    }

    private func handleCommand(_ actionName: String, token: String?) {
        guard ensureAuthenticated(token: token, action: actionName) else { return }

        guard let action = RemoteAction(rawValue: actionName) else {
            send(WireMessage.ack(action: actionName, ok: false, message: "unknown action"))
            return
        }

        let outcome = CommandRunner.run(action)
        send(WireMessage.ack(action: actionName, ok: outcome.ok, message: outcome.message))

        if action.mutatesAudioState {
            pushStatus()
        }
    }

    /// Authenticates a command. Per `PROTOCOL.md` §5 the token is verified on
    /// **every** message, constant-time, against the stored secret — there is no
    /// "trusted session" shortcut. The first valid token also marks the
    /// connection active so the menubar reflects the live link. On failure, sends
    /// an `unauthorized` ack and closes the connection.
    private func ensureAuthenticated(token: String?, action: String) -> Bool {
        guard authority.isTokenValid(token) else {
            send(WireMessage.ack(action: action, ok: false, message: "unauthorized"))
            cancel()
            return false
        }
        if !isAuthenticated {
            isAuthenticated = true
            markActive(true)
        }
        return true
    }

    private func pushStatus() {
        let state = SystemStateReader.current()
        send(WireMessage.status(state, deviceName: authority.deviceName))
    }

    // MARK: - Heartbeat (PROTOCOL.md §6)

    private func startHeartbeat() {
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10 * 1_000_000_000)
                guard !Task.isCancelled else { return }
                self?.sendPing()
            }
        }
    }

    private func sendPing() {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .ping)
        let context = NWConnection.ContentContext(identifier: "ping", metadata: [metadata])
        connection.send(content: nil, contentContext: context, isComplete: true,
                        completion: .contentProcessed { _ in })
    }

    // MARK: - Send

    private func send(_ data: Data) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "text", metadata: [metadata])
        connection.send(content: data, contentContext: context, isComplete: true,
                        completion: .contentProcessed { _ in })
    }

    // MARK: - Lifecycle

    private func markActive(_ active: Bool) {
        guard active != didReportActive else { return }
        didReportActive = active
        onActiveChange(active)
    }

    private func teardown() {
        heartbeat?.cancel()
        heartbeat = nil
        markActive(false)
        onClosed(self)
    }
}
