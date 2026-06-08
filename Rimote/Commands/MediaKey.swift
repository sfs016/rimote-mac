import AppKit

/// Posts system-defined media keys — the keys above the number row on Apple
/// keyboards. This is how Play/Pause, Next, and Previous reach whichever app
/// currently owns media playback, with no per-app integration.
///
/// Posting HID events may require Accessibility permission when the agent is
/// shipped as a signed app. If media keys do nothing, grant Rimote access under
/// System Settings → Privacy & Security → Accessibility.
enum MediaKey {

    /// `NX_KEYTYPE_*` constants from `IOKit/hidsystem/ev_keymap.h`.
    enum Key: Int32 {
        case playPause = 16
        case next = 17
        case previous = 18
    }

    /// Sends a key as a down/up pair, the way a physical key press registers.
    static func send(_ key: Key) {
        post(key, keyDown: true)
        post(key, keyDown: false)
    }

    private static func post(_ key: Key, keyDown: Bool) {
        let flags: NSEvent.ModifierFlags = keyDown
            ? NSEvent.ModifierFlags(rawValue: 0xA00)
            : NSEvent.ModifierFlags(rawValue: 0xB00)
        let data1 = Int((key.rawValue << 16) | ((keyDown ? 0xA : 0xB) << 8))

        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ) else { return }

        event.cgEvent?.post(tap: .cghidEventTap)
    }
}
