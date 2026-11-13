# Universal Wi-Fi TV Remote: Design

Date: 2026-11-13

## Intent and why
A cross-platform (Android and iOS) remote-control app for modern Wi-Fi smart TVs, with a distinctly modern, futuristic look. Built first for the owner's own use, with the door kept open to publishing later. The aim is one app that controls as many brands as practical, instead of one app per TV maker.

## Goals
- Discover TVs on the local Wi-Fi, pair, and control them from one UI.
- Control the full basics: power, d-pad/OK, back, home, menu, volume, mute, channel, playback, input and app launch where the platform supports it. Text entry for search where supported.
- First-class support, tested on real hardware, for: Roku/TCL Roku, Samsung (Tizen), LG (webOS), Android TV/Google TV.
- Visual identity: "Glass Aurora" (the owner picked direction B): frosted-glass panels over a soft violet/magenta gradient glow, premium and calm rather than harsh neon.
- Same look and behavior on Android and iOS.

## Non-goals
- Infrared control (no IR hardware on iPhones, and the owner confirmed Wi-Fi only).
- Legacy, non-networked TVs.
- Apple TV (limited, awkward protocol) in v1.
- Cloud accounts, remote control over the internet, and monetization in v1.

## Anti-goals (a failure even if it technically works)
- Laggy or unreliable button presses; a remote must feel instant.
- A pretty UI that is hard to use in the dark, one-handed, without looking.
- Per-brand code leaking into UI code, which makes new brands expensive to add.

## Constraints
- Control happens over the local network only; the phone and TV must be on the same Wi-Fi.
- iOS requires a Local Network permission prompt and Bonjour service declarations; Android needs multicast/network permissions.
- Brand protocols differ: Roku uses HTTP (ECP); Samsung and LG use WebSocket (LG with pairing prompt on TV; Samsung with an allow prompt and token); Android TV/Google TV uses a TLS remote protocol with certificate pairing via an on-screen code.
- Protocol layers will be built against public documentation and community-documented behavior; they must be verified on the owner's real TVs.

## Approaches considered
1. **Flutter, one codebase (chosen).** Custom animated UI renders identically on both platforms; raw TCP/UDP/WebSocket/TLS access. Trade-off: Dart, plus small platform-specific code for discovery and permissions.
2. React Native. Discovery and sockets rely on third-party native modules that break across versions; heavy custom visuals are harder.
3. Two native apps (Kotlin and Swift). Best platform integration, but double the build and maintenance cost.

The owner chose Flutter.

## Architecture (builder's calls where noted)
- **UI layer:** Flutter screens: TV picker/discovery, pairing, and the main remote. Talks only to a single `TvController` interface.
- **Driver layer:** one driver per brand implementing a common interface (connect, pair, sendKey, launchApp, text input, capabilities). Drivers: Roku, Samsung, LG, Android TV. Fire TV and Vizio are later.
- **Discovery:** mDNS/Bonjour and SSDP, run in parallel, plus manual IP entry as fallback. (My call.)
- **Storage:** saved TVs and pairing tokens/certificates kept on-device, tokens in the platform secure store. (My call.)
- **Capabilities:** each driver declares what it supports, and the UI hides or disables controls the TV can't do.

## Look and feel
- Main remote: large glass d-pad with glowing OK button, power button top-right, row for home/back/menu, volume and channel rockers.
- Soft violet-to-magenta gradient background with blur panels; subtle glow and haptic feedback on press.
- Dark theme only in v1. (My call.)
- Detailed visual tokens (colors, type, spacing) are left to the builder, anchored on the chosen mockup.

## Build order
1. Project scaffold, theme, and remote UI with a fake driver.
2. LG webOS driver first (owner's choice; it proves the driver interface, WebSocket plus on-TV pairing prompt).
3. Roku and Samsung drivers.
4. Android TV / Google TV driver (pairing is the hardest).
5. Discovery and saved-TV management, polish, then later brands.

## Decisions from the builder check
Owner's answers:
- TVs are all 2018 or newer (Samsung Tizen, LG webOS 4+, Android TV 9+/Google TV). Only modern protocol variants are built; older ones are added only if a real TV fails.
- Tested on both Android and iPhone. iOS on-device installs need an Apple developer account for builds that last beyond 7 days; the owner should plan for one.

Author's calls (not yet discussed with the owner, so open to change):
- Delivery is incremental: LG first (owner's request), then Roku, Samsung and Android/Google TV, each releasable once tested on the owner's TV.
- "Instant" target: under about 150 ms from tap to command, using persistent connections kept warm, key-repeat on hold for volume and d-pad, and automatic reconnect after the phone sleeps or the app backgrounds.
- Basic keys (power, d-pad, back, home, volume, mute, channel) ship first in each driver; text entry and app launch come in a second pass per brand.
- Power-on from off uses Wake-on-LAN where the TV supports it; the TV's MAC address is stored at pairing time. Several saved TVs are supported, with manual IP entry as the fallback when mDNS/SSDP are blocked.

## Left to the builder
- Exact Flutter packages and state-management approach.
- Visual token values, icon set, animation details.
- Testing approach (unit tests with recorded/fake TV servers; manual hardware checklist per brand).
- App naming, icon, and store assets.

## Open risks
- Brand firmware updates can change protocol behavior; a driver may need maintenance.
- I cannot test against physical TVs from this environment, so each driver needs a hands-on pass by the owner.
