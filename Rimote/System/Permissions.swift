import AppKit
import ApplicationServices

/// Accessibility (TCC) permission, which the agent needs to post system media and
/// brightness keys (`CGEvent` → `.cghidEventTap`). Without it, those commands are
/// silently dropped by the OS while audio (`set volume`) and lock keep working.
///
/// Grants are tied to the app's path/signature, so they persist for the installed
/// `.dmg` app but reset for throwaway Xcode debug builds.
enum Permissions {
    static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system Accessibility prompt (only if not already trusted).
    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Opens System Settings → Privacy & Security → Accessibility.
    static func openAccessibilitySettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
