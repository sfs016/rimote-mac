import Foundation
import Combine

/// The single source of truth for the agent's UI and the authority the network
/// layer calls into for pairing and token decisions.
///
/// Lives on the main actor: it publishes the menubar icon state, the active PIN,
/// and the paired / launch-at-login flags, and it owns the `PairingManager` and
/// `TokenStore`. Because the `RimoteServer` and its connections are also
/// `@MainActor`-isolated, every security-relevant decision runs single-threaded
/// here — no locks, no races.
@MainActor
final class AppState: ObservableObject {

    /// Menubar icon state (PRD §11).
    enum IconState {
        case idle
        case connected
        case error
    }

    @Published private(set) var iconState: IconState = .idle
    @Published private(set) var statusText: String = "Idle — waiting for connection"
    @Published private(set) var activePIN: String?
    @Published private(set) var isPaired: Bool
    @Published var launchAtLogin: Bool

    private let tokenStore = TokenStore()
    private let pairing = PairingManager()
    private var server: RimoteServer?

    init() {
        isPaired = tokenStore.isPaired
        launchAtLogin = LaunchAtLogin.isEnabled

        pairing.onPINChange = { [weak self] pin in
            self?.activePIN = pin
        }
    }

    /// Starts the WebSocket server + Bonjour advertisement. Called once at launch.
    func start() {
        let server = RimoteServer(authority: self) { [weak self] status in
            self?.apply(status)
        }
        self.server = server
        server.start()
    }

    // MARK: - User actions (menubar)

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin = LaunchAtLogin.setEnabled(enabled)
    }

    func forgetPairedDevice() {
        tokenStore.forget()
        pairing.clear()
        isPaired = false
    }

    // MARK: - Status mapping

    private func apply(_ status: RimoteServer.Status) {
        switch status {
        case .idle:
            iconState = .idle
            statusText = "Idle — waiting for connection"
        case .connected:
            iconState = .connected
            statusText = "Connected — iPhone"
        case .error(let message):
            iconState = .error
            statusText = "Error — \(message)"
        }
    }
}

// MARK: - ClientConnection.Authority

extension AppState: ClientConnection.Authority {

    var deviceName: String { Host.current().localizedName ?? "Mac" }

    func beginPairing() -> String {
        pairing.beginPairing()
    }

    func verifyPIN(_ pin: String) -> Result<String, ClientConnection.PairError> {
        switch pairing.verify(pin) {
        case .success:
            let token = tokenStore.issueNewToken()
            isPaired = true
            return .success(token)
        case .wrongPIN:
            return .failure(.wrongPIN)
        case .expired:
            return .failure(.expired)
        }
    }

    func isTokenValid(_ token: String?) -> Bool {
        tokenStore.verify(token)
    }
}
