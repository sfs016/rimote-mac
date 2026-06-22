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
            // Before anything else: if we're running from the DMG or a
            // translocated path, permissions won't stick — offer to move to
            // /Applications and relaunch. Everything below assumes a stable home.
            if Relocation.offerMoveIfNeeded() { return }

            LaunchAtLogin.enableOnFirstLaunch()
            // Keep reacting if the grant is given (or revoked) while running.
            state.startAccessibilityWatch()
        }
        statusItem = StatusItemController(state: state)
        state.start()

        // Show our own popover on launch whenever the user still has something to
        // do — grant Accessibility, or pair a phone. We deliberately do NOT fire
        // the bare system Accessibility prompt here: that system dialog steals
        // focus and trips the popover's outside-click monitor, so the agent's own
        // UI appeared to "not open" right when the user needed it. Instead the
        // popover shows the Action-needed state, and its button drives the system
        // grant on the user's terms. Once fully set up (paired + trusted) we stay
        // quiet so it isn't intrusive on every login.
        if !TestSupport.isActive, !state.isPaired || !state.accessibilityTrusted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.statusItem?.showPopover()
            }
        }
    }

    /// Launching the app while it's already running (Finder, Launchpad, Dock,
    /// Spotlight) lands here — open the popover. For a menu-bar-only agent this
    /// is the user saying "show me the app"; doing nothing reads as broken.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        statusItem?.showPopover()
        return false
    }
}
