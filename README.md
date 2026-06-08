# Rimote — Mac Agent

Turn your iPhone into a dead-simple, LAN-only remote for your Mac. **Rimote** is
the macOS menu-bar companion that listens for commands from the
[Rimote iPhone app](https://rimote.app) over your local network and runs them —
sleep, lock, volume, mute, and media transport — with sub-second latency and
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
| Lock | Locks the screen (⌃⌘Q) |
| Mute | Toggles output mute; reports the new state |
| Volume Up / Down | Adjusts output volume by ±10 |
| Play / Pause | System media key — works across apps |
| Next / Previous Track | System media keys |
| Skip Forward / Back 10s | Best-effort (native media key; see limitations) |
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
> [GitHub release](../../releases). Until then, build from source below.

1. Download `Rimote.dmg` from the latest release.
2. Open it and drag **Rimote** to your Applications folder.
3. Launch Rimote. It lives in the menu bar — look for the circle icon, not the
   Dock.
4. On first launch, macOS may ask permission to post media keys
   (**System Settings → Privacy & Security → Accessibility**). Grant it so
   Play/Pause and track controls work.
5. Open the Rimote app on your iPhone, pick your Mac, and enter the PIN shown in
   the menu-bar popover.

---

## Build from source

```bash
git clone https://github.com/farhajshahid/rimote-mac.git
cd rimote-mac
xcodebuild -project Rimote.xcodeproj -scheme Rimote -configuration Release build
```

Or open `Rimote.xcodeproj` in Xcode, select the **Rimote** scheme, and run.

Verify the agent is advertising on the network from another terminal:

```bash
dns-sd -B _rimote._tcp
```

---

## How it works

```
iPhone (SwiftUI)  ──WebSocket :8765──▶  Rimote Mac agent  ──▶  macOS
  URLSessionWS         ws://mac.local        NWListener          osascript /
  Bonjour browse       JSON frames           command whitelist   pmset / media keys
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
- **10-second skip in browsers is best-effort.** There is no universal macOS key
  for "skip 10s"; native players respond to the media key, but Chrome-based
  players (YouTube, Netflix) are handled best-effort and may not respond.

---

## License

[MIT](LICENSE) © 2026 Farhaj Shahid
