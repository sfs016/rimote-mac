import Foundation

/// Executes a whitelisted `RemoteAction` and returns a human-readable outcome.
///
/// This is the only place where the abstract whitelist becomes a concrete system
/// effect. Each case maps to a fixed implementation built from literal arguments;
/// there is no path from an arbitrary string to execution.
enum CommandRunner {

    struct Outcome {
        let ok: Bool
        let message: String
    }

    static func run(_ action: RemoteAction) -> Outcome {
        switch action {
        case .sleep:
            return runProcess("/usr/bin/pmset", ["sleepnow"], success: "sleeping")

        case .lock:
            // Locks immediately with no permission required (vs. a System Events
            // keystroke, which would need Accessibility/Automation).
            return ScreenLock.lock()
                ? Outcome(ok: true, message: "locked")
                : Outcome(ok: false, message: "lock failed")

        case .mute:
            return toggleMute()

        case .volumeUp:
            return runAppleScript(
                "set volume output volume ((output volume of (get volume settings)) + 10)",
                success: "volume up"
            )

        case .volumeDown:
            return runAppleScript(
                "set volume output volume ((output volume of (get volume settings)) - 10)",
                success: "volume down"
            )

        case .playPause:
            MediaKey.send(.playPause)
            return Outcome(ok: true, message: "play/pause")

        case .nextTrack:
            MediaKey.send(.next)
            return Outcome(ok: true, message: "next track")

        case .previousTrack:
            MediaKey.send(.previous)
            return Outcome(ok: true, message: "previous track")

        case .brightnessUp:
            // HID brightness keys drive the panel directly. The current level
            // can't be read back reliably, so this is a blind ± like a TV remote.
            MediaKey.send(.brightnessUp)
            return Outcome(ok: true, message: "brightness up")

        case .brightnessDown:
            MediaKey.send(.brightnessDown)
            return Outcome(ok: true, message: "brightness down")

        case .arrowUp:
            Keyboard.press(.up)
            return Outcome(ok: true, message: "up")

        case .arrowDown:
            Keyboard.press(.down)
            return Outcome(ok: true, message: "down")

        case .arrowLeft:
            Keyboard.press(.left)
            return Outcome(ok: true, message: "left")

        case .arrowRight:
            Keyboard.press(.right)
            return Outcome(ok: true, message: "right")

        case .select:
            Keyboard.press(.return)
            return Outcome(ok: true, message: "select")

        case .restart:
            // The destructive-action confirmation lives in the iOS UI (PRD §7);
            // the agent simply performs the request it receives.
            return runAppleScript(
                #"tell application "System Events" to restart"#,
                success: "restarting"
            )

        case .shutdown:
            return runAppleScript(
                #"tell application "System Events" to shut down"#,
                success: "shutting down"
            )
        }
    }

    // MARK: - Implementations

    /// Toggles output mute relative to the current state so one button works both
    /// ways, and reports the resulting state in the ack message.
    private static func toggleMute() -> Outcome {
        let result = Shell.run("/usr/bin/osascript", [
            "-e", "set isMuted to output muted of (get volume settings)",
            "-e", "set volume output muted (not isMuted)",
            "-e", "return (not isMuted) as string",
        ])
        guard result.succeeded else {
            return Outcome(ok: false, message: failureMessage(result))
        }
        let nowMuted = result.output == "true"
        return Outcome(ok: true, message: nowMuted ? "muted" : "unmuted")
    }

    private static func runAppleScript(_ source: String, success: String) -> Outcome {
        runProcess("/usr/bin/osascript", ["-e", source], success: success)
    }

    private static func runProcess(_ executable: String, _ args: [String], success: String) -> Outcome {
        let result = Shell.run(executable, args)
        guard result.succeeded else {
            return Outcome(ok: false, message: failureMessage(result))
        }
        return Outcome(ok: true, message: result.output.isEmpty ? success : result.output)
    }

    private static func failureMessage(_ result: Shell.Result) -> String {
        result.error.isEmpty ? "exit \(result.exitCode)" : result.error
    }
}
