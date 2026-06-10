# Rimote — Mac Agent

Turn your iPhone into a dead-simple, LAN-only remote for your Mac. **Rimote** is
the macOS menu-bar companion that listens for commands from the
[Rimote iPhone app](https://rimote.app) over your local network and runs them —
sleep, lock, volume, mute, media transport, brightness, and a directional pad
(arrow keys + Enter) — with sub-second latency and
**nothing ever leaving your Wi-Fi**.

> No cloud. No account. No relay server. No data collection. The phone talks to
> the Mac directly over the local network, and that's the whole story.

<!--
  SCREENSHOTS / DEMO GIF
  ----------------------
  Drop a menu-bar popover screenshot and a short pairing → control demo GIF here
  before publishing. Suggested: docs/menubar.png and docs/demo.gif.
-->

---

## Features

- **Menu-bar app** with a three-state icon — connected, idle, and error — and a
  popover showing connection status and the pairing PIN.
- **Zero-config discovery** over Bonjour (`_rimote._tcp`). The iPhone finds your
  Mac by name; no IP addresses to type.
- **Secure pairing** — a one-time 4-digit PIN (60-second expiry) bootstraps a
  256-bit token that authenticates every subsequent command.
- **WebSocket control server** on port `8765`, built on Apple's
  `Network.framework`, with a 10-second ping/pong heartbeat.
- **Live state sync** — the Mac pushes volume, mute, and battery back to the
  phone on connect and after every audio change, so the remote always reflects
  reality.
- **A locked-down command whitelist** — the agent executes only a fixed Swift
  enum of actions. No request string ever reaches a shell.
- **Launch at Login**, on by default and toggleable from the menu bar.

### Supported commands

| Command | Effect |
|---|---|
| Sleep | Sleeps the Mac (`pmset sleepnow`) |
| Lock | Locks the screen instantly (no permission needed) |
| Mute | Toggles output mute; reports the new state |
| Volume Up / Down | Adjusts output volume by ±10 |
| Play / Pause | System media key — works across apps |
| Next / Previous Track | System media keys |
| Brightness Up / Down | Display brightness via HID keys (a blind ± — level isn't read) |
| Arrows / Select | Up / Down / Left / Right + Return keys (directional pad) |
| Restart / Shut Down | AppleScript power control (confirmed in the iPhone UI) |
| Status | Reads volume / mute / battery (a read, not a command) |

---

## Requirements

- macOS 13 (Ventura) or later
- Xcode 15 or later (to build from source)
- An iPhone running the Rimote app, on the **same Wi-Fi network**

---

## Install (via the `.dmg`)

> A signed + notarized `.dmg` will be attached to each
> [GitHub release](../../releases). Until then, build one yourself with
> `Scripts/build-dmg.sh` (produces `dist/Rimote.dmg`, ad-hoc signed — on first
> launch, **right-click → Open** to get past Gatekeeper), or build from source below.

1. Download `Rimote.dmg` from the latest release.
2. Open it and drag **Rimote** to your Applications folder.
3. Launch Rimote. It lives in the menu bar — look for the circle icon, not the
   Dock.
4. On first launch, Rimote asks for **Accessibility**
   (**System Settings → Privacy & Security → Accessibility**). Grant it so the
   **media (Play/Pause, track), brightness, and navigation (arrows / Select)**
   controls work. Sleep, lock, mute, and volume work without it. The menu-bar popover shows a reminder until it's
   granted. (Restart / Shut Down also prompt for Automation the first time.)
5. Open the Rimote app on your iPhone, pick your Mac, and enter the PIN shown in
   the menu-bar popover.

---

## Build from source

```bash
git clone https://github.com/farhajshahid/rimote-mac.git
cd rimote-mac
xcodebuild -project Rimote.xcodeproj -scheme Rimote -configuration Release build
```

Or open `Rimote.xcodeproj` in Xcode, select the **Rimote** scheme, and run. The
agent appears in the menu bar (no Dock icon). On first launch, grant
Accessibility (**System Settings → Privacy & Security → Accessibility**) so media
keys work.

Verify the agent is advertising on the network from another terminal:

```bash
dns-sd -B _rimote._tcp
```

---

## Tests

An end-to-end pairing test drives the **real agent binary** through the full
[`PROTOCOL.md`](PROTOCOL.md) handshake over an actual WebSocket — pairing, token
auth, live status push, a self-restoring command, and rejection of a bad token:

```bash
Tests/run-e2e.sh
```

It builds the app, launches it with an isolated, throwaway environment (so your
real pairing state is never touched), and asserts the whole contract. See
[`Tests/README.md`](Tests/README.md) for details.

---

## How it works

```
iPhone (SwiftUI)  ──WebSocket :8765──▶  Rimote Mac agent  ──▶  macOS
  URLSessionWS         ws://mac.local        NWListener          osascript /
  Bonjour browse       JSON frames           command whitelist   pmset / CGEvent keys
```

The wire contract is frozen in [`PROTOCOL.md`](PROTOCOL.md): WebSocket transport,
PIN pairing, token auth on every message, and heartbeat. The agent is organized
into small, single-responsibility pieces:

- `Networking/` — the `NWListener` WebSocket server and per-connection protocol.
- `Protocol/` — the action whitelist enum and JSON message encoders/decoders.
- `Pairing/` — PIN lifecycle and the persisted 256-bit token (constant-time
  verified, stored `0600` in Application Support).
- `Commands/` — the fixed command implementations and the system-state reader.
- `MenuBar/` — the SwiftUI menu-bar icon and popover.

---

## Releasing (signing & notarization)

`Scripts/build-dmg.sh` produces an **ad-hoc-signed** `dist/Rimote.dmg` — great for
local use, but a downloaded copy needs a one-time **right-click → Open** to get
past Gatekeeper. For a frictionless public release, sign with a **Developer ID
Application** certificate and notarize (requires an Apple Developer account):

1. **Sign** with hardened runtime — replace the ad-hoc `codesign --sign -` in the
   script with your identity:
   ```bash
   codesign --force --deep --options runtime \
     --sign "Developer ID Application: Your Name (TEAMID)" Rimote.app
   ```
2. **Notarize** the disk image and staple the ticket:
   ```bash
   xcrun notarytool submit dist/Rimote.dmg --keychain-profile "AC_NOTARY" --wait
   xcrun stapler staple dist/Rimote.dmg
   ```
3. Attach the stapled `.dmg` to a [GitHub release](../../releases).

Once notarized, the app opens with a normal double-click — no right-click needed.

---

## Privacy

Rimote is **local-only by design**. It opens no internet connections, contacts
no servers, includes no analytics or telemetry, and stores nothing about you
beyond a single pairing token on your own Mac (file permissions `0600`). Every
byte stays on your local network. Removing a paired device ("Forget Paired
Device") deletes that token immediately.

---

## Known limitations (stated honestly)

- **LAN-only.** Rimote works only when your iPhone and Mac are on the same
  network. There is no remote/cellular access, by design.
- **No wake-from-sleep.** A sleeping Mac can't be woken over the network, so
  Rimote can't either. It is never promised.
- **Enterprise / university Wi-Fi** often blocks Bonjour (mDNS); discovery may
  fail on those networks (~10% of setups).
- **Brightness is a blind ±.** macOS doesn't report the current brightness back
  reliably, so the brightness buttons nudge up/down like a TV remote — there's no
  on-screen level.

---

## License

[MIT](LICENSE) © 2026 Farhaj Shahid
