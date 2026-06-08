import Foundation

/// A tiny, synchronous wrapper around `Process` for running the fixed set of
/// system binaries Rimote depends on (`osascript`, `pmset`).
///
/// This is **not** a general shell: callers always pass an absolute executable
/// path plus an explicit argument array, so no string is ever interpreted by a
/// shell. The only callers are `CommandRunner` and `SystemStateReader`, both of
/// which build their argument arrays from hardcoded literals.
enum Shell {

    struct Result {
        let exitCode: Int32
        let output: String
        let error: String

        var succeeded: Bool { exitCode == 0 }
    }

    /// Runs `executable` with `arguments` and waits for it to exit.
    static func run(_ executable: String, _ arguments: [String]) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return Result(exitCode: -1, output: "", error: error.localizedDescription)
        }
        process.waitUntilExit()

        return Result(
            exitCode: process.terminationStatus,
            output: read(stdout),
            error: read(stderr)
        )
    }

    private static func read(_ pipe: Pipe) -> String {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
