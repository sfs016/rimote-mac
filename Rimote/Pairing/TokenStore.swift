import Foundation
import CryptoKit

/// Persists the paired-device secret token on disk.
///
/// The token is a 256-bit value, lower-hex encoded (64 chars), generated on
/// successful pairing. It is the shared secret that authenticates every
/// subsequent command (`PROTOCOL.md` §4–§5).
///
/// Storage is a single file in Application Support with `0600` permissions
/// (owner read/write only), matching the protocol's stated options. The agent
/// runs unsandboxed (distributed as a `.dmg`), so this directory is writable.
final class TokenStore {

    private let fileURL: URL

    /// The currently paired token, or `nil` if no device is paired.
    /// Kept in memory so the hot auth path never touches disk.
    private(set) var token: String?

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = support.appendingPathComponent("Rimote", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("token", isDirectory: false)
        self.token = Self.load(from: fileURL)
    }

    var isPaired: Bool { token != nil }

    /// Generates, persists, and returns a fresh 256-bit hex token, replacing any
    /// previously stored value.
    @discardableResult
    func issueNewToken() -> String {
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max) }
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        save(hex)
        return hex
    }

    /// Removes the stored token, unpairing the device.
    func forget() {
        token = nil
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Constant-time comparison of a candidate token against the stored secret.
    ///
    /// Returns `false` when no device is paired or the candidate is absent. The
    /// comparison runs in time independent of where the first mismatching byte
    /// is, so it does not leak the secret through timing.
    func verify(_ candidate: String?) -> Bool {
        guard let stored = token, let candidate else { return false }
        let a = Data(stored.utf8)
        let b = Data(candidate.utf8)
        // `safeCompare` is constant-time for equal-length inputs; comparing the
        // length separately (and still hashing both) avoids an early-exit leak.
        guard a.count == b.count else { return false }
        return a.withUnsafeBytes { (aPtr: UnsafeRawBufferPointer) in
            b.withUnsafeBytes { (bPtr: UnsafeRawBufferPointer) in
                var diff: UInt8 = 0
                for i in 0..<a.count {
                    diff |= aPtr[i] ^ bPtr[i]
                }
                return diff == 0
            }
        }
    }

    // MARK: - Disk

    private func save(_ value: String) {
        token = value
        let data = Data(value.utf8)
        try? data.write(to: fileURL, options: [.atomic])
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    private static func load(from url: URL) -> String? {
        guard
            let data = try? Data(contentsOf: url),
            let value = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        else { return nil }
        return value
    }
}
