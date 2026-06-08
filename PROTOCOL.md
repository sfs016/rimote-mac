# Rimote — Wire Protocol v2 (production)

**Canonical shared contract.** The Mac agent (`mac/`) and the iOS app (`ios/`)
are built in separate repos by separate people/agents. They MUST both implement
this document exactly, or the apps will not interoperate. This file is the
single source of truth; a copy lives in each repo as `PROTOCOL.md`. Any change
here must be mirrored in both implementations.

Supersedes `proto/PROTOCOL.md` (PoC: raw TCP + newline JSON, no auth). v2 changes:
WebSocket transport, PIN pairing, token auth on every message, heartbeat.

## 1. Transport

- **WebSocket** (RFC 6455) over the local network only. No TLS (LAN, trusted).
- **Port:** `8765`. URL: `ws://<host>:8765/`
- **Mac server:** `NWListener` with `NWProtocolWebSocket.Options` (Network.framework).
- **iOS client:** `URLSessionWebSocketTask`.
- **Message unit:** one WebSocket **text** frame = exactly one JSON object (UTF-8).
  No newline framing (WS frames are already discrete). Never split/coalesce JSON
  across frames.

## 2. Discovery (Bonjour / mDNS)

- Service type: `_rimote._tcp`, domain `local.`, port `8765`.
- Mac advertises via `NWListener.service`. The service `name` is the Mac's
  display name (e.g. "Steve's MacBook Pro") and is what the iOS device picker shows.
- iOS discovers via `NWBrowser`. Verify in Terminal: `dns-sd -B _rimote._tcp`.

## 3. Message envelope

Every JSON object has a discriminator. Two top-level kinds:

- **Discriminated by `"type"`** — control/handshake/state-push messages.
- **Commands** — carry `"action"` (and, post-pairing, `"token"`); the Mac
  replies with an **ack** carrying `"status"`.

A receiver routes on: `type` present → control/status; else `action` present →
command; else `status` present → ack.

## 4. Pairing handshake (one-time, unauthenticated connection)

When the iOS app has no stored token for a Mac it connects and runs this:

```
iOS  → {"type":"pair_request"}
Mac  → {"type":"pair_challenge","deviceName":"Steve's MacBook Pro"}
        # Mac generates a 4-digit PIN, shows it in the menubar popover,
        # starts a 60-second expiry timer.
iOS  → {"type":"pair_verify","pin":"4829"}
Mac  → {"type":"pair_result","status":"ok","token":"<64-hex>",
        "deviceName":"Steve's MacBook Pro"}
        # on success: Mac persists the token; iOS stores it in Keychain.
   or → {"type":"pair_result","status":"error","message":"wrong_pin"}
   or → {"type":"pair_result","status":"error","message":"expired"}
```

- **PIN:** 4 digits, cryptographically random, **60s** TTL. Regenerated on expiry.
- **Token:** 32 random bytes, lower-hex (64 chars). This IS the shared secret.
  Mac persists it (Application Support, file perms 0600 / or Keychain); iOS
  persists it in the iOS Keychain inside the `PairedDevice` record.
- After a successful `pair_result`, the same connection is considered
  authenticated for the rest of its lifetime; subsequent messages still carry
  the token per §5.

## 5. Authenticated session

Every command from iOS carries the token:

```json
{"action":"mute","token":"<64-hex>"}
```

- The Mac verifies the token on **every** message using a **constant-time**
  comparison against the stored secret. Missing/incorrect token →
  `{"status":"error","action":"<action>","message":"unauthorized"}` and the Mac
  closes the connection.
- A connection that sends a command before pairing (no known token) is rejected
  the same way.

### Commands (iOS → Mac) — the whitelist

The Mac executes ONLY these fixed cases (Swift enum). No string ever reaches a
shell. Unknown action → `{"status":"error","action":...,"message":"unknown action"}`.

| action            | Mac effect                                              |
|-------------------|---------------------------------------------------------|
| `sleep`           | `pmset sleepnow`                                        |
| `lock`            | lock screen (Ctrl+Cmd+Q keystroke via osascript)        |
| `mute`            | toggle output mute (osascript), reports new state       |
| `volume_up`       | output volume + 10                                      |
| `volume_down`     | output volume − 10                                      |
| `play_pause`      | system media key (code 16)                              |
| `next_track`      | system media key (code 17)                              |
| `previous_track`  | system media key (code 18)                              |
| `brightness_up`   | display brightness up (HID key) — blind, no level reported |
| `brightness_down` | display brightness down (HID key) — blind, no level reported |
| `restart`         | AppleScript restart (destructive — confirmed in UI)     |
| `shutdown`        | AppleScript shut down (destructive — confirmed in UI)   |
| `status`          | a read, not a command — Mac replies with a status push  |

### Ack (Mac → iOS)

Sent for every command (except `status`, which yields a status push):

```json
{"status":"ok","action":"mute","message":"muted"}
{"status":"error","action":"foo","message":"unknown action"}
```

### State push (Mac → iOS)

```json
{"type":"status","volume":70,"muted":false,"battery":92,"charging":true,
 "deviceName":"Steve's MacBook Pro"}
```

- `volume` 0–100, `muted` bool, `battery` 0–100 (`-1` if none), `charging` bool.
- Pushed automatically (a) immediately after the connection is authenticated,
  and (b) after any `mute` / `volume_up` / `volume_down`.
- **No brightness level** is reported (PoC proved brightness read-back is
  unreliable — see `proto/POC_STATUS.md`). Brightness, if exposed, is blind ±.

## 6. Heartbeat & reconnect

- Use WebSocket-native **ping/pong** every **10s** (iOS `sendPing`; the Mac's
  `NWProtocolWebSocket` auto-replies to pings, and should also ping the client).
- If a pong is not received within the interval (≈2 missed → ~20s), the side
  treats the connection as dead, tears down, and the iOS app auto-reconnects via
  the last-known host, then Bonjour. The Mac returns its menubar icon to idle.

## 7. Security summary

- LAN-only, no relay, no internet. No data leaves the local network.
- Command whitelist is a fixed Swift enum — no dynamic/shell execution.
- Token (256-bit secret) required and constant-time-verified on every message.
- PIN bootstrap with 60s TTL gates token issuance.
