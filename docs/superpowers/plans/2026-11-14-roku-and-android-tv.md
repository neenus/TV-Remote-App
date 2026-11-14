# Roku and Android TV (Sony, Philips 2018+, TCL, Hisense, Shield...) Plan

> Executed inline, same process and review lessons as the earlier driver plans.

**Goal:** Support Roku TVs/players and Android TV / Google TV devices (which covers Sony and Philips from 2018) from the same remote UI.

## Decision: one Android TV driver instead of Sony + Philips drivers
Sony (IRCC-IP, needs IP control + PSK/PIN switched on in TV settings) and Philips (JointSpace v6, digest-auth PIN pairing) each have their own API. Both brands' 2018+ TVs run Android TV and support the **Android TV Remote protocol v2** that Google's remote app uses: TLS on ports 6466 (control) and 6467 (pairing), a PIN shown on the TV, no TV settings to change. One driver covers them plus TCL, Hisense, Nvidia Shield, Chromecast with Google TV, etc. Trade-off: no Sony/Philips-specific extras (their network power-on when in standby, etc.).

## Part A: Roku (ECP, External Control Protocol)
- HTTP on port 8060, no pairing. `GET /query/device-info` (XML: `friendly-device-name`, `model-name`, `serial-number`, `wifi-mac`, `ethernet-mac`, `network-type`, `power-mode`). `POST /keypress/<Key>` (empty body); typing is `POST /keypress/Lit_<url-encoded char>`.
- Keys: Up/Down/Left/Right, Select, Back, Home, Info (the * options key, used for Menu), VolumeUp/VolumeDown/VolumeMute, ChannelUp/ChannelDown, Rev/Play/Fwd, Power. Play is a toggle, so Pause also sends Play. Input is not available.
- Discovery by SSDP search target `roku:ecp` (USN `uuid:roku:ecp:<serial>`: the id must be the serial, not the literal word "roku").
- MAC read automatically from device-info (`network-type` picks wifi vs ethernet), which also enables Wake-on-LAN.
- The phone setting on the Roku "Control by mobile apps" can be Limited/Disabled: a 403 gets a clear message.

## Part B: Android TV Remote v2
Verified against the Python library `androidtvremote2` (scratch virtualenv): protobuf message encoding, the pairing secret hash, key injection. Pairing: client certificate (self-signed RSA, generated once, stored securely), TLS to 6467, pairing request/option/configuration messages, the 6-hex-digit code from the TV is combined with both certificates' public keys into a SHA-256 secret. Control: TLS to 6466 with the same certificate, configure/set-active handshake, ping/pong, `RemoteKeyInject` key events.
Key codes are Android's (DPAD 19-22/23, BACK 4, HOME 3, MENU 82, VOLUME 24/25, MUTE 164, CHANNEL 166/167, MEDIA 126/127/89/90, TV_INPUT 178, POWER 26). Typing is out of scope for this version.

## Tasks
1. Roku: protocol helpers + driver + discovery + wiring (tests first, fake HTTP device).
2. Android TV: protobuf codec, certificate/secret, pairing flow, control channel, driver, wiring.
3. Checklist, builds, fresh reviews, fix passes, serve.

## Review Focus
1. Roku: 403/Limited mode, unreachable TV, XML parsing robustness, typing order, MAC selection, SSDP id.
2. Android TV: pairing code wrong/expired, certificate handling and storage, TLS verification choices, framing of length-delimited protobuf, ping/pong keepalive, reconnect, lifecycle (dispose mid-pairing/handshake), malformed frames.
