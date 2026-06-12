import AppKit

/// Detects launch from a location where TCC grants won't stick and offers to
/// move the app to /Applications.
///
/// Two traps, both fatal to the Accessibility permission surviving a relaunch:
///   - running straight off the mounted `.dmg` (`/Volumes/…`), and
///   - Gatekeeper app translocation (`…/AppTranslocation/…`), where macOS runs a
///     quarantined bundle from a randomized read-only mount. A grant recorded
///     against that randomized path is useless on the next launch — the user
///     sees Rimote toggled ON in System Settings, yet the app stays untrusted.
///
/// The fix is always the same: run from a stable path. We offer to do the move
/// ourselves and relaunch (the approach popularized by LetsMove).
@MainActor
enum Relocation {

    static var isMisplaced: Bool {
        let path = Bundle.main.bundlePath
        return path.hasPrefix("/Volumes/") || path.contains("/AppTranslocation/")
    }

    /// Returns `true` when the app is about to relaunch (or quit) and the caller
    /// should skip the rest of its launch sequence.
    static func offerMoveIfNeeded() -> Bool {
        guard isMisplaced else { return false }
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Move Rimote to Applications?"
        alert.informativeText = """
        Rimote is running from a temporary location, so macOS won't remember \
        its permissions between launches. Rimote can move itself to the \
        Applications folder and reopen from there.
        """
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Quit")

        if alert.runModal() == .alertFirstButtonReturn {
            moveAndRelaunch()
        } else {
            NSApp.terminate(nil)
        }
        return true
    }

    private static func moveAndRelaunch() {
        let fm = FileManager.default
        let source = URL(fileURLWithPath: Bundle.main.bundlePath)
        let dest = URL(fileURLWithPath: "/Applications/\(source.lastPathComponent)")

        do {
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            try fm.copyItem(at: source, to: dest)

            // Clear quarantine on the copy. Without this, Gatekeeper may
            // translocate the new copy too and we'd be back where we started.
            // The user already approved opening the app once — this only stops
            // macOS from treating our own copy as a fresh download.
            let xattr = Process()
            xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattr.arguments = ["-dr", "com.apple.quarantine", dest.path]
            try? xattr.run()
            xattr.waitUntilExit()

            let config = NSWorkspace.OpenConfiguration()
            config.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: dest, configuration: config) { _, _ in
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        } catch {
            let failure = NSAlert()
            failure.messageText = "Couldn't Move Rimote"
            failure.informativeText = """
            Drag Rimote to the Applications folder in Finder, then open it from \
            there. (\(error.localizedDescription))
            """
            failure.addButton(withTitle: "OK")
            failure.runModal()
            NSWorkspace.shared.activateFileViewerSelecting([source])
            NSApp.terminate(nil)
        }
    }
}
