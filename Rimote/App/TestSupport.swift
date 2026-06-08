import Foundation

/// Environment-gated seams used only by the end-to-end pairing test (`Tests/`).
///
/// Every value here is inert unless its environment variable is explicitly set,
/// so shipping launches behave exactly as if this type did not exist. The agent
/// is otherwise impossible to drive from an automated client because the pairing
/// PIN is shown only in the menubar; these hooks let the test complete the
/// handshake headlessly without ever weakening the real pairing path.
enum TestSupport {

    /// When `RIMOTE_TEST_PIN` holds a 4-digit value, pairing uses it instead of a
    /// cryptographically random PIN, letting an automated client pair without
    /// reading the menubar. Returns `nil` (→ random PIN) for any other value.
    static var fixedPIN: String? {
        guard let value = ProcessInfo.processInfo.environment["RIMOTE_TEST_PIN"],
              value.count == 4, value.allSatisfy(\.isNumber)
        else { return nil }
        return value
    }

    /// When `RIMOTE_TEST_MODE=1`, launch-time side effects that would mutate the
    /// host machine (registering the login item) are skipped.
    static var isActive: Bool {
        ProcessInfo.processInfo.environment["RIMOTE_TEST_MODE"] == "1"
    }
}
