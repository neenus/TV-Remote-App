# Samsung (Tizen) Driver Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (chosen by the owner earlier for this project) to implement this plan task-by-task.

**Goal:** Control 2016-or-newer Samsung Tizen smart TVs from the same remote UI, alongside LG.

**Architecture:** `SamsungDriver` implements the existing `TvDriver` over the existing `Transport` seam. Discovery, the Add-by-IP dialog and the driver factory become brand-aware. No UI changes to the remote screen itself.

**Tech Stack:** Flutter/Dart, existing `Transport`/`WebSocketTransport`, `KeyStore`, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-11-13-tv-remote-design.md` (Samsung is a listed first-class brand). Protocol facts below are from community documentation and are **unverified on real hardware**.

## Global Constraints
- Same constraints as `2026-11-13-foundation-and-lg.md` (Wi-Fi only, no ads/trackers, secure storage for tokens, no AI attribution in commits).
- Samsung Tizen 2016+ only. Older (pre-2016) protocols are out of scope.
- Lessons from the LG review apply from the start: pending handshake futures must fail when the socket closes or the driver is disposed; stream controllers are closed with `unawaited`; key-store failures never break control; presses arriving while a reconnect is underway are dropped, not queued; malformed JSON is ignored.

## Protocol facts used
- Remote control socket: `wss://<ip>:8002/api/v2/channels/samsung.remote.control?name=<base64 app name>[&token=<token>]`; fall back to `ws://<ip>:8001/...` (no token) for TVs without the secure port. Self-signed cert accepted (existing `WebSocketTransport`).
- First connection without a token makes the TV show an "Allow" prompt (no PIN alternative). After allowing, the TV sends `{"event":"ms.channel.connect","data":{"token":"..."}}`; the token is stored and sent on later connections. `ms.channel.unauthorized` means denied; `ms.channel.timeOut` means nobody answered.
- Key press: `{"method":"ms.remote.control","params":{"Cmd":"Click","DataOfCmd":"KEY_VOLUP","Option":"false","TypeOfRemote":"SendRemoteKey"}}`.
- Device info and MAC: `GET http://<ip>:8001/api/v2/` returns JSON with `device.wifiMac`.
- Discovery: SSDP search target `urn:samsung.com:device:RemoteControlReceiver:1`.

## Review Focus
1. Denied or unanswered Allow prompt: `PairingDenied`, no token stored, UI offers retry.
2. Stored token rejected or ignored (TV reset): token deleted, one retry without a token.
3. Socket closes mid-handshake: `connect()` fails instead of hanging.
4. TV only offers the plain port: falls back to `ws://:8001`.
5. Typing is not supported: no crash when the keyboard UI calls the driver.

---

### Task 1: Samsung protocol helpers (pure functions)
**Files:** Create `lib/drivers/samsung/samsung_protocol.dart`; Test `test/drivers/samsung/samsung_protocol_test.dart`
**Interfaces (produces):**
- `Uri samsungUrl(String host, {required bool secure, String? token})`
- `String samsungKeyMessage(String key)`; `class SamsungKeyMap { static String? key(TvKey k) }` (every `TvKey` mapped)
- `sealed class SamsungInbound`: `SamsungConnected(String? token)`, `SamsungUnauthorized`, `SamsungTimeout`; `SamsungInbound? parseSamsungInbound(String raw)`
- `String? macFromSamsungDeviceInfo(Map json)`
- [ ] Write failing tests (URL shape, message shape, full key map, parse connect/unauthorized/timeout/garbage, numeric token, MAC parse/invalid). [ ] Run: FAIL. [ ] Implement. [ ] Run: PASS. [ ] Commit.

### Task 2: Samsung driver
**Files:** Create `lib/drivers/samsung/samsung_driver.dart`; Test `test/drivers/samsung/samsung_driver_test.dart`, `test/support/fake_samsung_tv.dart`
**Interfaces:** `SamsungDriver(TvDevice device, KeyStore keys, Transport Function() makeTransport, {Future<Map<String,dynamic>?> Function(Uri)? fetchJson, Duration connectTimeout, Duration pairingTimeout})` implementing `TvDriver` (`connect({pinPairing})` ignores the flag; `submitPairingPin` ignored; `keyboardFocus` is empty; `sendText/deleteText/sendEnter` throw `TvConnectionError('Typing is not supported on Samsung TVs yet')`; `fetchMacAddress` uses `fetchJson` on `http://<ip>:8001/api/v2/`).
- [ ] Tests: first connect shows `AwaitingPairing` then `Connected` and stores the token; reconnect sends the stored token; denied -> `PairingDenied` and nothing stored; stored token rejected -> deleted and retried once without; unanswered prompt times out; unreachable -> `TvConnectionError`; falls back from `wss:8002` to `ws:8001`; socket close mid-handshake fails connect; unexpected exception -> `TvConnectionError`; key store failures tolerated; duplicate/malformed events ignored; every key sends the mapped message; concurrent presses during reconnect send once; MAC via fetcher, null on failure; typing methods throw. [ ] FAIL. [ ] Implement. [ ] PASS. [ ] Commit.

### Task 3: Brand-aware discovery, factory and Add-by-IP
**Files:** Modify `lib/core/tv_device.dart` (`TvBrand.samsung`), `lib/discovery/lg_discovery.dart` (parse Samsung replies; `discoverTvs` sends both searches; `manualDevice(host, {brand})`), `lib/providers.dart` (factory by brand; use `discoverTvs`), `lib/ui/add_tv_dialog.dart` (brand choice); Tests: `test/discovery/lg_discovery_test.dart`, `test/ui/tv_picker_screen_test.dart`
- [ ] Tests: Samsung SSDP reply parses to a Samsung device; LG still parses; non-matching ignored; `manualDevice` brand/name; dialog returns the chosen brand; factory returns the right driver type. [ ] FAIL. [ ] Implement. [ ] PASS (full suite + analyze). [ ] Commit.

### Task 4: Checklist, build, review
- [ ] Add a Samsung section to `docs/lg-hardware-checklist.md` (rename content generically). [ ] Push; CI builds the APK. [ ] Whole-branch review by a fresh reviewer; fix pass for Critical/Important findings with tests. [ ] Serve the build.
