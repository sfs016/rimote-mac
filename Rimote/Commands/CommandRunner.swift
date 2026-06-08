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
            // Ctrl+Cmd+Q is the standard lock-screen shortcut.
            return runAppleScript(
                #"tell application "System Events" to keystroke "q" using {control down, command down}"#,
                success: "locked"
            )

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

        case .skipForward10:
            // Best-effort (PRD §7): no universal macOS key exists. The native
            // "next" media key advances podcasts/Apple TV; browser-specific keys
            // are out of scope for the agent and handled client-side if at all.
            MediaKey.send(.next)
            return Outcome(ok: true, message: "skip forward (best-effort)")

        case .skipBack10:
            MediaKey.send(.previous)
            return Outcome(ok: true, message: "skip back (best-effort)")

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
