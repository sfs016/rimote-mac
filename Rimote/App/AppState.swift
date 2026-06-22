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
    @Published private(set) var accessibilityTrusted: Bool = Permissions.isAccessibilityTrusted
    /// The Mac's LAN IPv4, shown in the popover so users on Bonjour-blocking
    /// networks can pair by IP. Refreshed whenever the popover opens.
    @Published private(set) var localIPAddress: String? = NetworkInfo.primaryIPv4()

    private let tokenStore = TokenStore()
    private let pairing = PairingManager()
    private var server: RimoteServer?
    private var accessibilityPoll: Task<Void, Never>?

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

    /// Re-read the Accessibility grant (it can change outside the app, in Settings).
    func refreshPermissions() {
        let trusted = Permissions.isAccessibilityTrusted
        if trusted != accessibilityTrusted { accessibilityTrusted = trusted }
    }

    /// Re-read the LAN IP (cheap; called when the popover opens, since the
    /// network can change at any time — Wi-Fi hop, hotspot, cable).
    func refreshLocalIP() {
        let ip = NetworkInfo.primaryIPv4()
        if ip != localIPAddress { localIPAddress = ip }
    }

    /// Watch for the Accessibility grant changing *while the app is running*.
    ///
    /// The grant lands in System Settings, not in the app — without this, the
    /// "Action needed" state stays up (and the user stays stuck) after they've
    /// actually granted it. Two things conspired to make it lag the real state:
    ///
    ///  1. A menu-bar-only (`.accessory`) app has distributed notifications
    ///     **suspended by default** — they're coalesced and delivered only when
    ///     the app next becomes active. So `com.apple.accessibility.api` arrived
    ///     late, making the warning look "stuck" until some later interaction.
    ///     `.deliverImmediately` opts out so we hear the flip the moment it lands.
    ///  2. `AXIsProcessTrusted()` updates a beat *after* the notification fires,
    ///     so a single immediate read often still sees the old value. We re-read
    ///     across a short settle window to catch the transition.
    ///
    /// A steady 2s poll backs both up (the notification isn't a documented
    /// contract); one `AXIsProcessTrusted()` call every 2s is negligible.
    func startAccessibilityWatch() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(accessibilityDidChange),
            name: Notification.Name("com.apple.accessibility.api"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        accessibilityPoll?.cancel()
        accessibilityPoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self, !Task.isCancelled else { return }
                self.refreshPermissions()
            }
        }
    }

    @objc private func accessibilityDidChange() {
        // The system posts the notification just before AXIsProcessTrusted()
        // flips, so re-read a few times across the settle window rather than once.
        Task { @MainActor [weak self] in
            guard let self else { return }
            for delay in [0.0, 0.4, 1.2, 3.0] {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                self.refreshPermissions()
            }
        }
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
