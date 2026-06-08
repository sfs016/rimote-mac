import SwiftUI

/// The Rimote menubar agent.
///
/// Rimote is a menubar-only companion: there is no Dock icon and no main window
/// (`LSUIElement` is set in Info.plist). The single `MenuBarExtra` scene presents
/// a popover with status, pairing PIN, and controls per PRD §11.
///
/// `AppState` is created and the network server started in `AppDelegate`, so the
/// agent begins listening the moment the app launches, before the menubar
/// popover is ever opened.
@main
struct RimoteApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(state: delegate.state)
        } label: {
            MenuBarLabel(state: delegate.state)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Owns the long-lived `AppState` and kicks off the server at launch.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let state = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        LaunchAtLogin.enableOnFirstLaunch()
        state.start()
    }
}
