import Foundation

/// Owns the one-time PIN bootstrap that gates token issuance (`PROTOCOL.md` §4).
///
/// A pairing attempt produces a 4-digit, cryptographically random PIN with a
/// 60-second time-to-live. The PIN is surfaced in the menubar popover for the
/// user to read off, and is consumed exactly once by a matching `pair_verify`.
///
/// All access is funnelled through `@MainActor` because the active PIN is also
/// published UI state; the networking layer hops to the main actor to drive it.
@MainActor
final class PairingManager {

    /// How long a freshly generated PIN remains valid.
    static let ttl: TimeInterval = 60

    private(set) var activePIN: String?
    private var expiry: Date?
    private var expiryTask: Task<Void, Never>?

    /// Called whenever the active PIN changes (generated, consumed, or expired)
    /// so the UI can show or hide it. Always invoked on the main actor.
    var onPINChange: ((String?) -> Void)?

    /// Begins a pairing attempt: generates a fresh PIN and starts its expiry
    /// timer. Returns the PIN so the caller can display it.
    func beginPairing() -> String {
        let pin = Self.randomPIN()
        activePIN = pin
        expiry = Date().addingTimeInterval(Self.ttl)
        scheduleExpiry()
        onPINChange?(pin)
        return pin
    }

    /// The outcome of verifying a submitted PIN.
    enum VerifyResult {
        case success
        case wrongPIN
        case expired
    }

    /// Verifies a submitted PIN. On success the PIN is consumed so it cannot be
    /// reused. A PIN past its TTL reports `.expired`.
    func verify(_ submitted: String) -> VerifyResult {
        guard let pin = activePIN, let expiry else { return .expired }
        guard Date() < expiry else {
            clear()
            return .expired
        }
        guard submitted == pin else { return .wrongPIN }
        clear()
        return .success
    }

    /// Cancels any in-flight pairing attempt and hides the PIN.
    func clear() {
        activePIN = nil
        expiry = nil
        expiryTask?.cancel()
        expiryTask = nil
        onPINChange?(nil)
    }

    // MARK: - Private

    private func scheduleExpiry() {
        expiryTask?.cancel()
        expiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.ttl * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.clear()
        }
    }

    /// A 4-digit PIN drawn from a cryptographically secure source, zero-padded so
    /// values like `0042` are possible and uniformly likely.
    private static func randomPIN() -> String {
        let value = Int.random(in: 0...9999)
        return String(format: "%04d", value)
    }
}
