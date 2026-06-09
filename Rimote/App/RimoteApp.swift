import SwiftUI

/// The Rimote menubar agent.
///
/// Rimote is a menubar-only companion: there is no Dock icon and no main window
/// (`LSUIElement` is set in Info.plist). The menu-bar status item and its popover
/// are managed by `StatusItemController` (AppKit) instead of `MenuBarExtra`, so
/// the popover can be opened programmatically when a pairing PIN appears. The
/// `Settings` scene below is an inert placeholder — the agent has no real windows.
///
/// `AppState` is created and the network server started in `AppDelegate`, so the
/// agent begins listening the moment the app launches.
@main
struct RimoteApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

/// Owns the long-lived `AppState`, the menu-bar status item, and kicks off the
/// server at launch.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let state = AppState()
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only agent: run as an accessory app (no Dock icon) and, crucially,
        // keep the main run loop pumping so the server's @MainActor work runs.
        NSApp.setActivationPolicy(.accessory)

        // Skip the login-item registration under the e2e test so it never mutates
        // the host machine; the server still starts so the test can pair.
        if !TestSupport.isActive {
            LaunchAtLogin.enableOnFirstLaunch()
            // Media/brightness keys need Accessibility — prompt up front so the
            // user can grant it before reaching for those controls.
            if !Permissions.isAccessibilityTrusted {
                Permissions.requestAccessibility()
            }
        }
        statusItem = StatusItemController(state: state)
        state.start()
    }
}
