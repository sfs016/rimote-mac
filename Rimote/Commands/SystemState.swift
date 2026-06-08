import Foundation

/// A snapshot of live Mac state that the iPhone mirrors in its UI.
///
/// Every field is read with public, permission-free tools (`osascript` / `pmset`),
/// so reading state never triggers a TCC prompt. Brightness is deliberately absent:
/// the PoC proved brightness read-back is unreliable, so it is never reported.
struct SystemState {
    /// Output volume, 0–100.
    let volume: Int
    /// Whether output is muted.
    let muted: Bool
    /// Battery percentage 0–100, or `-1` on a machine with no battery.
    let battery: Int
    /// Whether the machine is on AC / charging / charged (i.e. not draining).
    let charging: Bool
}

/// Reads the current audio and battery state.
///
/// Cheap enough to call on connect and after every audio command — exactly the
/// event-driven moments at which the protocol pushes a status update.
enum SystemStateReader {

    static func current() -> SystemState {
        let (volume, muted) = readVolume()
        let (battery, charging) = readBattery()
        return SystemState(volume: volume, muted: muted, battery: battery, charging: charging)
    }

    /// One `osascript` call returns `"volume|muted"`, e.g. `"70|false"`.
    private static func readVolume() -> (volume: Int, muted: Bool) {
        let out = Shell.run("/usr/bin/osascript", [
            "-e", "set s to (get volume settings)",
            "-e", "return (output volume of s as string) & \"|\" & (output muted of s as string)",
        ])
        let parts = out.output.split(separator: "|", maxSplits: 1).map(String.init)
        let volume = parts.indices.contains(0) ? (Int(parts[0]) ?? 0) : 0
        let muted = parts.indices.contains(1) ? (parts[1] == "true") : false
        return (volume, muted)
    }

    /// Parses `pmset -g batt` for percentage and charging state.
    private static func readBattery() -> (battery: Int, charging: Bool) {
        let out = Shell.run("/usr/bin/pmset", ["-g", "batt"]).output
        guard !out.isEmpty else { return (-1, true) }

        var percent = -1
        if let range = out.range(of: #"\d+%"#, options: .regularExpression) {
            percent = Int(out[range].dropLast()) ?? -1
        }

        // "AC Power" / "charging" / "charged" all indicate the machine isn't draining.
        let lower = out.lowercased()
        let charging = lower.contains("ac power") || lower.contains("charging") || lower.contains("charged")
        return (percent, charging)
    }
}
