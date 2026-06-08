import Foundation

/// Wire-format helpers for the Rimote protocol (`PROTOCOL.md` §3–§5).
///
/// Every WebSocket text frame is exactly one JSON object. Messages are routed by
/// shape: a `"type"` key marks a control/handshake/status message, an `"action"`
/// key marks a command, and a `"status"` key marks an ack.
///
/// Inbound JSON is parsed leniently (clients may add fields we ignore), while
/// outbound JSON is produced from small, explicit encoders so the exact wire
/// shape is easy to audit against the protocol document.
enum WireMessage {

    // MARK: - Inbound

    /// A parsed inbound message, discriminated by the keys present.
    enum Inbound {
        case pairRequest
        case pairVerify(pin: String)
        case command(action: String, token: String?)
        case statusRequest(token: String?)
        case unknown

        /// Parses a single UTF-8 JSON frame into a typed inbound message.
        /// Returns `nil` only when the bytes are not a JSON object at all.
        static func parse(_ data: Data) -> Inbound? {
            guard
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }

            if let type = object["type"] as? String {
                switch type {
                case "pair_request":
                    return .pairRequest
                case "pair_verify":
                    return .pairVerify(pin: (object["pin"] as? String) ?? "")
                default:
                    return .unknown
                }
            }

            let token = object["token"] as? String
            if let action = object["action"] as? String {
                return action == "status"
                    ? .statusRequest(token: token)
                    : .command(action: action, token: token)
            }

            return .unknown
        }
    }

    // MARK: - Outbound

    /// `{"type":"pair_challenge","deviceName":"…"}`
    static func pairChallenge(deviceName: String) -> Data {
        encode([
            "type": "pair_challenge",
            "deviceName": deviceName,
        ])
    }

    /// `{"type":"pair_result","status":"ok","token":"…","deviceName":"…"}`
    static func pairSuccess(token: String, deviceName: String) -> Data {
        encode([
            "type": "pair_result",
            "status": "ok",
            "token": token,
            "deviceName": deviceName,
        ])
    }

    /// `{"type":"pair_result","status":"error","message":"…"}`
    static func pairFailure(message: String) -> Data {
        encode([
            "type": "pair_result",
            "status": "error",
            "message": message,
        ])
    }

    /// `{"status":"ok"|"error","action":"…","message":"…"}`
    static func ack(action: String, ok: Bool, message: String) -> Data {
        encode([
            "status": ok ? "ok" : "error",
            "action": action,
            "message": message,
        ])
    }

    /// `{"type":"status","volume":…,"muted":…,"battery":…,"charging":…,"deviceName":"…"}`
    static func status(_ state: SystemState, deviceName: String) -> Data {
        encode([
            "type": "status",
            "volume": state.volume,
            "muted": state.muted,
            "battery": state.battery,
            "charging": state.charging,
            "deviceName": deviceName,
        ])
    }

    // MARK: - Encoding

    private static func encode(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
    }
}
