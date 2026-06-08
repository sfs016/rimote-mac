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

    init(state: AppState) {
        self.state = state
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        popover.behavior = .transient
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
    }

    @objc private func togglePopover() {
        popover.isShown ? popover.performClose(nil) : showPopover()
    }

    private func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func updateIcon(_ iconState: AppState.IconState) {
        statusItem.button?.image = StatusIcon.image(for: iconState)
    }
}
