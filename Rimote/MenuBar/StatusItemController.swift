import AppKit
import SwiftUI
import Combine

/// Owns the menu-bar status item and its popover.
///
/// This replaces SwiftUI's `MenuBarExtra` for one reason: the popover must open
/// *programmatically*. When a pairing PIN is generated, the popover springs open
/// automatically so the user sees — and can copy — the code without hunting for
/// the menu-bar icon. `MenuBarExtra` offers no way to do that.
@MainActor
final class StatusItemController: NSObject {
    private let state: AppState
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()
    private var outsideClickMonitor: Any?

    init(state: AppState) {
        self.state = state
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        // We control closing ourselves (see `showPopover`): the popover stays open
        // regardless of mouse movement / hover and closes only on a click outside.
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: MenuBarView(state: state))

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
        }
        updateIcon(state.iconState)

        state.$iconState
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.updateIcon($0) }
            .store(in: &cancellables)

        // Auto-present the popover the moment a pairing PIN appears.
        state.$activePIN
            .receive(on: RunLoop.main)
            .sink { [weak self] pin in
                guard pin != nil else { return }
                self?.showPopover()
            }
            .store(in: &cancellables)

        // Auto-present when the Accessibility grant lands: granting happens over
        // in System Settings, so without this the app gives zero feedback at the
        // exact moment the user did what we asked of them.
        state.$accessibilityTrusted
            .removeDuplicates()
            .dropFirst()
            .filter { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.showPopover() }
            .store(in: &cancellables)
    }

    @objc private func togglePopover() {
        popover.isShown ? closePopover() : showPopover()
    }

    func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        state.refreshPermissions()
        state.refreshLocalIP()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        button.highlight(true)

        // Close when the user clicks anywhere outside the popover (clicks inside
        // are local events and don't trigger this global monitor).
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        statusItem.button?.highlight(false)
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    private func updateIcon(_ iconState: AppState.IconState) {
        statusItem.button?.image = StatusIcon.image(for: iconState)
    }
}
