import Foundation

// End-to-end pairing test for the Rimote Mac agent.
//
// A black-box WebSocket client that drives the *running* agent through the full
// PROTOCOL.md handshake and asserts the contract end to end:
//   1. pair_request → pair_challenge
//   2. pair_verify  → pair_result (token issued)
//   3. authenticated status read  → status push
//   4. a real, self-restoring command (mute toggled twice) → ack + state push
//   5. a command with a bad token → "unauthorized" (auth enforced every message)
//
// Run via Tests/run-e2e.sh, which builds the app, launches it with the test
// environment (fixed PIN, isolated home), waits for the port, then runs this.
//
//   ws host/port : RIMOTE_TEST_HOST (default 127.0.0.1:8765)
//   pairing PIN  : RIMOTE_TEST_PIN  (must match the agent's; default 1357)

let host = ProcessInfo.processInfo.environment["RIMOTE_TEST_HOST"] ?? "127.0.0.1:8765"
let pin = ProcessInfo.processInfo.environment["RIMOTE_TEST_PIN"] ?? "1357"
let url = URL(string: "ws://\(host)/")!

enum TestError: Error, CustomStringConvertible {
    case timeout
    case badJSON(String)
    var description: String {
        switch self {
        case .timeout: return "timed out waiting for a message"
        case .badJSON(let s): return "expected a JSON object, got: \(s)"
        }
    }
}

/// Collects pass/fail results so the whole contract is checked in one run rather
/// than aborting on the first mismatch.
final class Checker {
    private(set) var failures = 0
    func check(_ condition: Bool, _ label: String) {
        print(condition ? "  ✓ \(label)" : "  ✗ \(label)")
        if !condition { failures += 1 }
    }
}

func send(_ task: URLSessionWebSocketTask, _ object: [String: Any]) async throws {
    let data = try JSONSerialization.data(withJSONObject: object)
    try await task.send(.string(String(decoding: data, as: UTF8.self)))
}

/// Receive one JSON frame, failing if none arrives within `timeout` seconds.
func receive(_ task: URLSessionWebSocketTask, timeout: TimeInterval = 5) async throws -> [String: Any] {
    try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
        group.addTask { try await task.receive() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            throw TestError.timeout
        }
        defer { group.cancelAll() }
        let message = try await group.next()!
        switch message {
        case .string(let text):
            guard let data = text.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { throw TestError.badJSON(text) }
            return object
        case .data(let data):
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { throw TestError.badJSON("<\(data.count) bytes>") }
            return object
        @unknown default:
            throw TestError.badJSON("unknown frame")
        }
    }
}

func runAll() async -> Int32 {
    let checker = Checker()
    print("Rimote end-to-end pairing test → \(url.absoluteString)")

    do {
        // ── Connection A: full pairing + authenticated commands ──────────────
        let a = URLSession(configuration: .ephemeral).webSocketTask(with: url)
        a.resume()

        print("\n[1] Pairing handshake")
        try await send(a, ["type": "pair_request"])
        let challenge = try await receive(a)
        checker.check(challenge["type"] as? String == "pair_challenge", "pair_request → pair_challenge")
        checker.check((challenge["deviceName"] as? String)?.isEmpty == false, "challenge carries deviceName")

        try await send(a, ["type": "pair_verify", "pin": pin])
        let result = try await receive(a)
        checker.check(result["type"] as? String == "pair_result", "pair_verify → pair_result")
        checker.check(result["status"] as? String == "ok", "pairing succeeded with the test PIN")
        let token = result["token"] as? String ?? ""
        checker.check(token.count == 64, "issued a 64-hex token")

        let pushAfterPair = try await receive(a)
        checker.check(pushAfterPair["type"] as? String == "status", "status pushed right after pairing")

        print("\n[2] Authenticated status read")
        try await send(a, ["action": "status", "token": token])
        let status = try await receive(a)
        checker.check(status["type"] as? String == "status", "authenticated status request → status push")
        checker.check(status["volume"] is Int, "status carries a volume level")

        print("\n[3] Real command round-trip (mute toggled twice, net-zero)")
        try await send(a, ["action": "mute", "token": token])
        let ack1 = try await receive(a)
        checker.check(ack1["status"] as? String == "ok" && ack1["action"] as? String == "mute", "mute acked ok")
        let afterMute1 = try await receive(a)
        let muted1 = afterMute1["muted"] as? Bool
        checker.check(afterMute1["type"] as? String == "status" && muted1 != nil, "mute pushed updated state")

        try await send(a, ["action": "mute", "token": token])
        let ack2 = try await receive(a)
        checker.check(ack2["status"] as? String == "ok", "second mute acked ok")
        let afterMute2 = try await receive(a)
        let muted2 = afterMute2["muted"] as? Bool
        checker.check(muted2 != nil && muted2 != muted1, "second toggle flipped mute back (state restored)")

        a.cancel(with: .normalClosure, reason: nil)

        // ── Connection B: a bad token must be rejected ───────────────────────
        print("\n[4] Auth enforcement")
        let b = URLSession(configuration: .ephemeral).webSocketTask(with: url)
        b.resume()
        try await send(b, ["action": "mute", "token": String(repeating: "0", count: 64)])
        let denied = try await receive(b)
        checker.check(denied["status"] as? String == "error", "command with bad token → error")
        checker.check(denied["message"] as? String == "unauthorized", "rejection message is 'unauthorized'")
        b.cancel(with: .normalClosure, reason: nil)
    } catch {
        print("  ✗ aborted: \(error)")
        return 1
    }

    print("")
    if checker.failures == 0 {
        print("PASS — end-to-end pairing verified over the wire")
        return 0
    } else {
        print("FAIL — \(checker.failures) check(s) failed")
        return 1
    }
}

let semaphore = DispatchSemaphore(value: 0)
var exitCode: Int32 = 0
Task {
    exitCode = await runAll()
    semaphore.signal()
}
semaphore.wait()
exit(exitCode)
