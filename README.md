<a name="top"></a>
<div align="center">

<img src="Rimote/Resources/Assets.xcassets/AppIcon.appiconset/icon_128.png" alt="Rimote app icon" width="88" height="88" />

# Rimote

**Use your iPhone as a remote for your Mac.**<br/>
**Nothing ever leaves your Wi-Fi.**

<a href="https://github.com/sfs016/rimote-mac/releases/latest"><img src="https://img.shields.io/github/v/release/sfs016/rimote-mac?label=release&labelColor=000000&color=white" alt="Latest release" /></a>
<a href="https://github.com/sfs016/rimote-mac/releases"><img src="https://img.shields.io/github/downloads/sfs016/rimote-mac/total?labelColor=000000&color=white" alt="Downloads" /></a>
<img src="https://img.shields.io/badge/macOS-13%2B-white?labelColor=000000" alt="macOS 13+" />
<img src="https://img.shields.io/badge/iOS-16%2B-white?labelColor=000000" alt="iOS 16+" />
<a href="LICENSE"><img src="https://img.shields.io/github/license/sfs016/rimote-mac?labelColor=000000&color=white" alt="MIT license" /></a>

<br/>

<a href="https://github.com/sfs016/rimote-mac/releases/latest/download/Rimote.dmg"><img src="https://img.shields.io/badge/%E2%AC%87%EF%B8%8E%20%20Download%20for%20Mac-000000?style=for-the-badge&logo=apple&logoColor=white" alt="Download Rimote for Mac" height="36" /></a>
&nbsp;
<a href="https://apps.apple.com/app/id6779406773"><img src="https://img.shields.io/badge/Get%20the%20iPhone%20app-000000?style=for-the-badge&logo=appstore&logoColor=white" alt="Get the Rimote iPhone app on the App Store" height="36" /></a>

<sub>Signed &amp; notarized by Apple &nbsp;·&nbsp; free &nbsp;·&nbsp; <a href="https://rimote.app">rimote.app</a></sub>

<br/><br/>

<a href="https://rimote.app"><img src="docs/hero.png" alt="The Rimote iPhone remote next to the tagline 'Your Mac. In your hand.'" /></a>

</div>

## About

Rimote turns your iPhone into a beautifully simple remote for your Mac — a
SwiftUI app talking to a tiny AppKit menu-bar agent over a direct WebSocket on
your own network. It exists because pausing a movie, muting a call blast, or
clicking through Keynote shouldn't require standing up — and shouldn't require
a cloud account either. No servers, no analytics, no internet: pair once with
a PIN and every command stays on your Wi-Fi.

|                   | Control                                                        |
| ----------------- | -------------------------------------------------------------- |
| 🌙 **Power**      | Sleep, lock, restart, shut down — one tap                      |
| 🔊 **Audio**      | Volume up/down and mute, with live state pushed back           |
| ⏯ **Media**      | Play/pause, next, previous — YouTube, Spotify, Music, anything |
| ☀️ **Display**    | Screen brightness up/down                                      |
| 🎯 **Clickpad**   | Arrows + Select — drive Keynote or accept your AI agent's plan |
| 📡 **Status**     | Mac name, battery, volume — live in the app header             |

## Install

1. **[Download Rimote.dmg](https://github.com/sfs016/rimote-mac/releases/latest/download/Rimote.dmg)** and drag **Rimote** to Applications. It lives in the menu bar, not the Dock.
2. Open the **[iPhone app](https://apps.apple.com/app/id6779406773)**, pick your Mac, and type the 4-digit PIN shown in the menu-bar popover. Done — paired forever.

> [!NOTE]
> Grant **Accessibility** when prompted (System Settings → Privacy &amp; Security) —
> it's needed for media, brightness, and arrow keys. Sleep, lock, and volume
> work without it.

## How it works

```
iPhone (SwiftUI)  ──WebSocket :8765──▶  Mac agent (NWListener)  ──▶  macOS
  Bonjour browse       JSON + token         command whitelist       pmset / osascript /
  URLSessionWS         10s heartbeat        constant-time auth      CGEvent media keys
```

- **Zero-config discovery.** The agent advertises `_rimote._tcp` over Bonjour; the phone finds it by name. No IP addresses.
- **Event-driven, zero polling.** State (volume, mute, battery) is pushed on connect and after each change — idle CPU is ~0%.
- **One frozen wire contract.** Both apps implement [PROTOCOL.md](PROTOCOL.md): pairing handshake, message shapes, and the action whitelist.

## Security model

- **Hardcoded command whitelist.** The agent executes only the fixed cases of one Swift enum ([RemoteAction.swift](Rimote/Protocol/RemoteAction.swift)). No request string ever reaches a shell — commands run as an absolute executable plus an argument array, never `sh -c`.
- **PIN → token auth.** A one-time 4-digit PIN (60-second expiry) bootstraps a 256-bit token, stored `0600` and verified in **constant time on every message** ([TokenStore.swift](Rimote/Pairing/TokenStore.swift)).
- **LAN-only by design.** The agent opens zero internet connections. "Forget Paired Device" deletes the token immediately.

## Build from source

```bash
git clone https://github.com/sfs016/rimote-mac.git && cd rimote-mac
xcodebuild -project Rimote.xcodeproj -scheme Rimote -configuration Release build
```

Or open `Rimote.xcodeproj` in Xcode (15+) and run. Verify it's advertising:
`dns-sd -B _rimote._tcp`

To produce an installable image, `Scripts/build-dmg.sh` builds `dist/Rimote.dmg`
— ad-hoc signed by default, Developer ID-signed and notarized automatically when
signing credentials are present in the environment.

## Testing

```bash
Tests/run-e2e.sh
```

A 16-check end-to-end suite that builds and launches the **real agent binary**
in an isolated throwaway environment, then drives the full protocol over an
actual WebSocket: pairing, token issuance, live status push, a self-restoring
command, and rejection of a bad token. See [Tests/README.md](Tests/README.md).

## Limitations

- Same Wi-Fi network only; no remote access, by design. A sleeping Mac can't be woken over the network.
- Networks that block Bonjour/mDNS (some enterprise Wi-Fi) break discovery.
- Brightness is a blind ± (macOS doesn't reliably report the level back).

## License

[MIT](LICENSE) © 2026 Farhaj Shahid

<div align="right"><a href="#top">back to top ↑</a></div>
