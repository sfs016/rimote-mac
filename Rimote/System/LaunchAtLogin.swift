import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService` (macOS 13+) for the "Launch at Login" toggle.
///
/// Rimote registers itself as a login item so the agent is running and
/// discoverable without the user re-opening it after every reboot. Launch at
/// login is on by default; the user can turn it off from the menubar popover.
enum LaunchAtLogin {

    /// Whether the app is currently registered to launch at login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Enables or disables the login item, returning the resulting state.
    /// Failures (e.g. the user revoked the item in System Settings) are swallowed
    /// and reflected by re-reading `isEnabled`.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            // Surface the real state regardless of whether the call threw.
        }
        return isEnabled
    }

    /// Registers the login item the first time the app runs, so the default is
    /// "on" without overriding a choice the user has already made.
    static func enableOnFirstLaunch() {
        if SMAppService.mainApp.status == .notRegistered {
            try? SMAppService.mainApp.register()
        }
    }
}
