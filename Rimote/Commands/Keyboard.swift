import CoreGraphics

/// Posts regular keyboard keys (arrows, Return) as synthesized HID events so the
/// iPhone's directional pad can drive whatever app has focus on the Mac.
///
/// Like the media keys, this posts to `.cghidEventTap` and therefore requires
/// Accessibility permission (see `Permissions`).
enum Keyboard {
    /// macOS virtual key codes (`HIToolbox/Events.h`).
    enum Key: CGKeyCode {
        case up = 126
        case down = 125
        case left = 123
        case right = 124
        case `return` = 36
    }

    /// Sends a key as a down/up pair, the way a physical press registers.
    static func press(_ key: Key) {
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(keyboardEventSource: source, virtualKey: key.rawValue, keyDown: true)?
            .post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: source, virtualKey: key.rawValue, keyDown: false)?
            .post(tap: .cghidEventTap)
    }
}
