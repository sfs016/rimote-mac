import Foundation

/// The complete, hardcoded whitelist of actions the agent is willing to execute.
///
/// This enum is the security cornerstone of Rimote: the WebSocket layer maps an
/// incoming `"action"` string to one of these fixed cases and nothing else. No
/// request string ever reaches a shell, so a malformed or hostile payload cannot
/// run arbitrary code — at worst it resolves to `nil` and is rejected.
///
/// The raw values are the wire identifiers defined in `PROTOCOL.md` §5 and must
/// stay in exact sync with the iOS client's mirror enum.
enum RemoteAction: String, CaseIterable {
    case sleep
    case lock
    case mute
    case volumeUp = "volume_up"
    case volumeDown = "volume_down"
    case playPause = "play_pause"
    case nextTrack = "next_track"
    case previousTrack = "previous_track"
    case brightnessUp = "brightness_up"
    case brightnessDown = "brightness_down"
    case restart
    case shutdown

    /// Whether the action mutates audio state, and therefore warrants an
    /// automatic status push after it runs (`PROTOCOL.md` §5).
    var mutatesAudioState: Bool {
        switch self {
        case .mute, .volumeUp, .volumeDown:
            return true
        default:
            return false
        }
    }
}
