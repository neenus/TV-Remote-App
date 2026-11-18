# Samsung Legacy (pre-2016) Driver Plan

> Executed inline (the owner's earlier choice). Same global constraints and review lessons as `2026-11-13-samsung-driver.md`.

**Goal:** Control Samsung TVs from about 2008 to 2015 (e.g. "J" series) that do not have the WebSocket remote API.

**Why:** The owner's ~2015 Samsung was not found, and Add-by-IP failed, because the existing Samsung driver needs the 2016+ protocol.

**Protocol (verified against samsungctl's `remote_legacy.py`, public source):** raw TCP to port 55000. Handshake packet `00 00 00` + frame(`64 00` + b64(description) + b64(id) + b64(name)); key packet `00 00 00` + frame(`00 00 00` + b64(key)); a "frame" is a 1-byte length, `00`, then the bytes (strings are base64 first, except the outer payload). TV replies are `00 <nameLen LE16> name <respLen LE16> resp` where resp `64 00 01 00` = access granted, `64 00 00 00` = denied, starts `0a` = waiting for the user to answer the on-TV prompt, starts `65` = cancelled, `00 00 00 00` = key accepted. Power off is `KEY_POWEROFF`; SmartHub (home) is `KEY_CONTENTS`.
No pairing token: the TV remembers allowed devices itself. Pairing needs the on-TV "Allow" prompt (pressing Allow on the TV's own remote).

## Tasks
1. **Protocol** (`samsung_legacy_protocol.dart`): packet builders (golden bytes computed from the reference serializer), `LegacyKeyMap` (every `TvKey`), `LegacyFrameParser` (incremental, handles split and joined chunks, ignores oversize garbage), reply types.
2. **TCP transport** (`tcp_transport.dart`): `ByteTransport` interface and `TcpTransport` (closed-during-open safe).
3. **Driver** (`samsung_legacy_driver.dart`): connect/handshake/prompt states, keys, reconnect, dispose and socket-close mid-handshake fail the pending connect, concurrent presses send once, typing unsupported, MAC best effort.
4. **Wiring**: `TvBrand.samsungLegacy`, Add-by-IP chip "Samsung (2015 or older)", factory, and a hint in the 2016+ Samsung "could not reach the TV" message pointing to the older option.
5. Checklist, CI build, fresh review, fix pass, serve.

## Review Focus
1. Prompt denied/cancelled/unanswered: `PairingDenied`, clear message.
2. Socket closes or driver disposed mid-handshake: `connect()` fails, never hangs, no leaked socket.
3. Replies split across TCP chunks or several per chunk.
4. Unknown or garbage reply: connection error, no crash.
5. No reply at all (wrong kind of TV): `TvConnectionError` within the connect timeout.
