# Foundation, Remote UI and LG Driver: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Flutter app for Android and iOS that discovers an LG webOS TV on Wi-Fi, pairs with it, and controls it from a Glass Aurora remote screen.

**Architecture:** A UI layer talks only to a `TvDriver` interface. `LgDriver` implements it over an injectable `Transport` (so protocol logic is unit-tested with a fake socket, no TV needed). Discovery, saved TVs and Wake-on-LAN are separate small units. Later brands (Roku, Samsung, Android/Google TV) are separate plans that add drivers behind the same interface.

**Tech Stack:** Flutter (stable) / Dart 3, `flutter_riverpod`, `web_socket_channel`, `flutter_secure_storage`, `shared_preferences`, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-11-13-tv-remote-design.md`

## Global Constraints

- Wi-Fi/local network control only; no IR, no cloud accounts, no internet control.
- Targets: Android and iOS. LG webOS 4+ (TVs 2018 or newer) only.
- Visual identity: "Glass Aurora": frosted-glass panels over a violet-to-magenta gradient; dark theme only.
- Press latency target: under about 150 ms tap to command; persistent connection kept warm; key-repeat on hold for volume and d-pad; automatic reconnect after sleep/background.
- Basic keys only in this plan: power, d-pad, OK, back, home, menu, volume up/down, mute, channel up/down. Text entry and app launch are out of scope.
- Power-on from off uses Wake-on-LAN; the TV's MAC address is stored at pairing time. Multiple saved TVs; manual IP entry is the fallback when discovery is blocked.
- Pairing tokens go in the platform secure store, never in plain preferences.
- iOS needs `NSLocalNetworkUsageDescription` and `NSBonjourServices`; Android needs `INTERNET` and `CHANGE_WIFI_MULTICAST_STATE`.
- Per-brand code never appears in UI code; UI uses only `TvDriver` and `TvCapabilities`.
- No Claude/AI attribution in commit messages.

## Review Focus

1. TV is off or unreachable at connect: connect times out in a few seconds with a clear `TvConnectionError`, never hangs; Power uses Wake-on-LAN when off.
2. User denies the pairing prompt on the TV: driver reports `PairingDenied`; no stored key is written; UI offers retry.
3. Stored client-key rejected (TV reset): driver clears the key and re-pairs instead of failing silently.
4. Socket drops while a key is held: repeat stops, driver reconnects, and the app does not crash or keep firing into a dead socket.
5. Malformed or unexpected JSON from the TV: ignored or surfaced as an error, never an unhandled exception.
6. TV changes IP (DHCP): saved TV is re-found by its device id via discovery before connecting fails permanently.

---

### Task 1: Scaffold project and repository

**Files:**
- Create: Flutter app in `/home/neenus/workspace/projects/tv-remote` (`flutter create --org com.tvremote --project-name tv_remote .`), `.gitignore` additions, `analysis_options.yaml`
- Modify: `pubspec.yaml`

**Interfaces:**
- Produces: a compiling app, `git` repo, dependencies installed.

- [ ] **Step 1: Check the toolchain.** Run `flutter --version`. If missing, install Flutter stable and record the version in `README.md`.
- [ ] **Step 2: Run `git init`, then `flutter create --org com.tvremote --project-name tv_remote .`** in the project root. Append `.superpowers/` to `.gitignore`.
- [ ] **Step 3: Add dependencies** `flutter_riverpod`, `web_socket_channel`, `flutter_secure_storage`, `shared_preferences`, and dev dependency `flutter_lints`. Run `flutter pub get`.
- [ ] **Step 4: Run `flutter analyze && flutter test`.** Expected: no issues; the default widget test passes (replace it with a trivial `App` smoke test).
- [ ] **Step 5: Commit** `chore: scaffold flutter app`.

### Task 2: Domain model and fake driver

**Files:**
- Create: `lib/core/tv_key.dart`, `lib/core/tv_device.dart`, `lib/core/tv_driver.dart`, `lib/core/fake_driver.dart`
- Test: `test/core/fake_driver_test.dart`

**Interfaces:**
- Produces:
  - `enum TvKey { power, up, down, left, right, ok, back, home, menu, volumeUp, volumeDown, mute, channelUp, channelDown }`
  - `enum TvBrand { lg }` (extended by later plans)
  - `class TvDevice { final String id; final String name; final TvBrand brand; final String host; final String? mac; TvDevice copyWith({String? host, String? mac}); Map<String,dynamic> toJson(); factory TvDevice.fromJson(Map<String,dynamic>); }`
  - `class TvCapabilities { final Set<TvKey> keys; bool supports(TvKey k); }`
  - `sealed class TvConnectionState` with `Disconnected`, `Connecting`, `AwaitingPairing`, `Connected`, `Failed(Object error)`
  - sealed `TvError`: `TvConnectionError`, `PairingDenied`, `InvalidClientKey`
  - `abstract class TvDriver { TvCapabilities get capabilities; Stream<TvConnectionState> get state; Future<void> connect(); Future<void> sendKey(TvKey key); Future<void> dispose(); }`
  - `class FakeDriver implements TvDriver` recording sent keys in `List<TvKey> sent`, with `emit(TvConnectionState)` for tests.

- [ ] **Step 1: Write failing test `fake_driver_records_keys`** asserting that after `await d.sendKey(TvKey.volumeUp)`, `d.sent == [TvKey.volumeUp]`, and `TvDevice.fromJson(device.toJson()) == device` equality fields match.
- [ ] **Step 2: Run `flutter test test/core/fake_driver_test.dart`.** Expected: FAIL (types undefined).
- [ ] **Step 3: Implement the types above** in the listed files.
- [ ] **Step 4: Run the test.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: core domain types and fake driver`.

### Task 3: LG protocol messages (pure functions)

**Files:**
- Create: `lib/drivers/lg/lg_protocol.dart`
- Test: `test/drivers/lg/lg_protocol_test.dart`

**Interfaces:**
- Produces:
  - `String registerMessage({String? clientKey})`: JSON `{"type":"register","id":"register_0","payload":{"forcePairing":false,"pairingType":"PROMPT","manifest":{...},"client-key":<key if given>}}`. The manifest lists permissions `CONTROL_POWER`, `CONTROL_AUDIO`, `CONTROL_INPUT_TV`, `CONTROL_INPUT_JOYSTICK`, `CONTROL_INPUT_MEDIA_PLAYBACK`, `READ_TV_CHANNEL_LIST`.
  - `String requestMessage(String id, String uri, [Map<String,dynamic>? payload])`: JSON `{"type":"request","id":id,"uri":uri,"payload":payload}`.
  - `String pointerButtonFrame(String name)` returns `"type:button\nname:$name\n\n"`.
  - `sealed class LgInbound` with `Registered(String clientKey)`, `PairingPrompt`, `Response(String id, Map payload)`, `LgErrorMsg(String id, String error)`; `LgInbound? parseInbound(String raw)` returning `null` for malformed JSON.
  - `class LgKeyMap`: `String? uri(TvKey)` (for `volumeUp` -> `ssap://audio/volumeUp`, `volumeDown` -> `ssap://audio/volumeDown`, `channelUp` -> `ssap://tv/channelUp`, `channelDown` -> `ssap://tv/channelDown`, `power` -> `ssap://system/turnOff`) and `String? pointerName(TvKey)` (`up`->`UP`, `down`->`DOWN`, `left`->`LEFT`, `right`->`RIGHT`, `ok`->`ENTER`, `back`->`BACK`, `home`->`HOME`, `menu`->`MENU`). `mute` is sent as `ssap://audio/setMute` with `{"mute":true}` by the driver in Task 4.

- [ ] **Step 1: Write failing tests** `register_includes_client_key_when_given`, `register_omits_client_key_when_null`, `pointer_frame_format` (equals `"type:button\nname:UP\n\n"`), `parse_registered_returns_client_key` (input `{"type":"registered","id":"register_0","payload":{"client-key":"abc"}}` gives `Registered("abc")`), `parse_response_with_pairing_prompt` (`{"type":"response","id":"register_0","payload":{"pairingType":"PROMPT","returnValue":true}}` gives `PairingPrompt`), `parse_garbage_returns_null` (`"not json"` and `"[1,2]"` both give `null`), `keymap_covers_every_key_except_mute` (every `TvKey` other than `mute` has a uri or a pointer name).
- [ ] **Step 2: Run `flutter test test/drivers/lg/lg_protocol_test.dart`.** Expected: FAIL.
- [ ] **Step 3: Implement** the functions and classes above with `dart:convert`.
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: LG webOS protocol messages`.

### Task 4: LG driver (connect, pair, send keys, reconnect)

**Files:**
- Create: `lib/drivers/lg/lg_driver.dart`, `lib/drivers/lg/transport.dart`, `lib/core/key_store.dart`
- Test: `test/drivers/lg/lg_driver_test.dart`

**Interfaces:**
- Consumes: Task 2 types, Task 3 functions.
- Produces:
  - `abstract class Transport { Future<void> open(Uri uri); Stream<String> get messages; void send(String data); Future<void> close(); bool get isOpen; }` with `WebSocketTransport` (uses `dart:io` `HttpClient.badCertificateCallback = (_, __, ___) => true` so the TV's self-signed cert is accepted, wrapped by `IOWebSocketChannel`) and `FakeTransport` for tests (in `test/` support file) that can push inbound messages and record sent ones.
  - `abstract class KeyStore { Future<String?> read(String deviceId); Future<void> write(String deviceId, String key); Future<void> delete(String deviceId); }` with `SecureKeyStore` (flutter_secure_storage) and `MemoryKeyStore`.
  - `class LgDriver implements TvDriver { LgDriver(TvDevice device, KeyStore keys, Transport Function() makeTransport, {Duration connectTimeout = const Duration(seconds: 5)}); }`. Main socket is `wss://<host>:3001`. After `registered`, the driver requests `ssap://com.webos.service.networkinput/getPointerInputSocket`, opens the returned `socketPath` as a second transport, and sends `pointerButtonFrame` for d-pad/OK/back/home/menu; volume/channel/power use `requestMessage`; mute uses `ssap://audio/setMute` with `{"mute":true}`.

- [ ] **Step 1: Write failing tests** using `FakeTransport` and `MemoryKeyStore`:
  - `first_connect_sends_register_without_key_and_stores_key_on_registered` (state goes `Connecting` -> `AwaitingPairing` -> `Connected`; key `abc` written).
  - `reconnect_uses_stored_key` (register message contains `"client-key":"abc"`).
  - `pairing_denied_reports_error_and_stores_nothing` (inbound error response to `register_0` gives `Failed(PairingDenied)`; store empty).
  - `rejected_stored_key_is_deleted_and_repaired` (inbound error with stored key deletes it and sends a new register without a key).
  - `connect_times_out_to_TvConnectionError` (no inbound messages; with `connectTimeout: 50ms`, state becomes `Failed(TvConnectionError)`).
  - `send_key_dpad_uses_pointer_socket` (after pointer socket is open, `sendKey(TvKey.up)` sends `"type:button\nname:UP\n\n"` on it).
  - `send_key_volume_uses_request_uri` (sends a request with `uri` `ssap://audio/volumeUp`).
  - `malformed_inbound_is_ignored` (push `"%%%"`; state unchanged, no exception).
  - `socket_close_triggers_disconnected_then_reconnect_on_next_sendKey`.
- [ ] **Step 2: Run `flutter test test/drivers/lg/lg_driver_test.dart`.** Expected: FAIL.
- [ ] **Step 3: Implement** the interfaces above. Keep the main socket open between presses; reconnect lazily on the next `sendKey` or on app resume.
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: LG driver with pairing and reconnect`.

### Task 5: Wake-on-LAN

**Files:**
- Create: `lib/core/wake_on_lan.dart`
- Test: `test/core/wake_on_lan_test.dart`

**Interfaces:**
- Produces: `Uint8List magicPacket(String mac)` (6 bytes of `0xFF` followed by the MAC 16 times, 102 bytes; accepts `:` or `-` separators, throws `FormatException` otherwise) and `Future<void> sendWakeOnLan(String mac, {String broadcast = '255.255.255.255'})` over `RawDatagramSocket`, UDP port 9.
- Consumes: used by the UI power handler (Task 9) when the driver is not connected.

- [ ] **Step 1: Write failing tests** `packet_is_102_bytes_with_header_and_16_repeats` (for `"AA:BB:CC:DD:EE:FF"`), `accepts_dash_separators`, `rejects_invalid_mac` (`"zz"` and a 5-octet MAC throw `FormatException`).
- [ ] **Step 2: Run `flutter test test/core/wake_on_lan_test.dart`.** Expected: FAIL.
- [ ] **Step 3: Implement** both functions.
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: wake-on-lan`.

### Task 6: Discovery and saved TVs

**Files:**
- Create: `lib/discovery/lg_discovery.dart`, `lib/storage/tv_repository.dart`
- Modify: `ios/Runner/Info.plist` (add `NSLocalNetworkUsageDescription` and `NSBonjourServices` containing `_lg-smart-device._tcp`), `android/app/src/main/AndroidManifest.xml` (add `INTERNET`, `CHANGE_WIFI_MULTICAST_STATE`)
- Test: `test/discovery/lg_discovery_test.dart`, `test/storage/tv_repository_test.dart`

**Interfaces:**
- Consumes: `TvDevice`, `TvBrand`.
- Produces:
  - `TvDevice? parseSsdpResponse(String raw)`: parses an SSDP reply (headers `LOCATION`, `USN` containing a `uuid:`), returns an LG `TvDevice` (id = uuid, host from `LOCATION`, name defaulting to `"LG TV"`), or `null` if not an LG response.
  - `Stream<TvDevice> discoverLg({Duration timeout = const Duration(seconds: 4)})`: multicast `M-SEARCH` to `239.255.255.250:1900` with `ST: urn:lge-com:service:webos-second-screen:1`, emitting parsed devices de-duplicated by id.
  - `class TvRepository { TvRepository(SharedPreferences prefs); List<TvDevice> all(); Future<void> save(TvDevice d); Future<void> remove(String id); Future<TvDevice> refreshHost(TvDevice d, Stream<TvDevice> found); }`. `refreshHost` returns `d` with the host updated if a discovered device has the same id, otherwise `d` unchanged.
  - `TvDevice manualDevice(String host)` creating an LG device with `id = 'manual-$host'`.

- [ ] **Step 1: Write failing tests** `parse_lg_ssdp_response`, `parse_non_lg_response_returns_null`, `parse_garbage_returns_null`, `repository_saves_and_lists_devices`, `repository_removes_device`, `refresh_host_updates_changed_ip` (same id, new host, gives new host), `refresh_host_keeps_host_when_not_found`.
- [ ] **Step 2: Run `flutter test test/discovery test/storage`.** Expected: FAIL.
- [ ] **Step 3: Implement** the interfaces above; make the permission edits.
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: LG discovery and saved TVs`.

### Task 7: Glass Aurora theme

**Files:**
- Create: `lib/ui/theme.dart`, `lib/ui/glass_panel.dart`, `lib/ui/aurora_background.dart`
- Test: `test/ui/glass_panel_test.dart`

**Interfaces:**
- Produces: `class AuroraColors` (constants: `deepNavy #090A1A`, `violet #6B4CFF`, `deepViolet #1A1040`, `magenta #FF7AD9`, `lilac #8F7CFF`, `glassFill` white 8%, `glassBorder` white 17%, `textPrimary` white, `textSecondary #D8CCFF`); `ThemeData auroraTheme()` (dark only); `GlassPanel({required Widget child, double radius = 16, EdgeInsets padding})` using `BackdropFilter` blur 10 with `glassFill` and a 1 px `glassBorder`; `AuroraBackground({required Widget child})` painting `radial-gradient` from `violet` at the top-left through `deepViolet` to `deepNavy`.
- Values follow the chosen mockup (`.superpowers/brainstorm/*/content/visual-style.html`, option B).

- [ ] **Step 1: Write failing test `glass_panel_renders_child_with_backdrop_filter`** (pumps a `GlassPanel(child: Text('x'))`, expects `find.text('x')` and `find.byType(BackdropFilter)`).
- [ ] **Step 2: Run `flutter test test/ui/glass_panel_test.dart`.** Expected: FAIL.
- [ ] **Step 3: Implement** the three files.
- [ ] **Step 4: Run the test.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: glass aurora theme`.

### Task 8: Remote screen

**Files:**
- Create: `lib/ui/remote_screen.dart`, `lib/ui/widgets/dpad.dart`, `lib/ui/widgets/key_button.dart`, `lib/ui/widgets/hold_repeat.dart`
- Test: `test/ui/remote_screen_test.dart`, `test/ui/hold_repeat_test.dart`

**Interfaces:**
- Consumes: `TvDriver`, `TvKey`, `TvCapabilities`, `FakeDriver`, theme widgets.
- Produces:
  - `RemoteScreen({required TvDriver driver, required String tvName, required Future<void> Function() onPower})`: top bar with TV name and power button (calls `onPower`); large glass `DPad` with glowing OK button; home/back/menu row; volume and channel rockers; mute. Buttons for keys the driver does not support (`!capabilities.supports(k)`) are disabled. Every press triggers `HapticFeedback.lightImpact()` and `driver.sendKey`.
  - `HoldRepeat({required VoidCallback onFire, Duration initialDelay = const Duration(milliseconds: 400), Duration interval = const Duration(milliseconds: 120), required Widget child})`: fires once on tap-down, then repeats after the delay until tap-up/cancel, and stops when the widget is disposed. Used for d-pad arrows and volume/channel.

- [ ] **Step 1: Write failing tests:**
  - `tapping_volume_up_sends_volumeUp` (`FakeDriver.sent == [TvKey.volumeUp]`).
  - `disabled_key_does_not_send` (capabilities lacking `TvKey.menu`; tapping menu sends nothing).
  - `hold_repeat_fires_repeatedly_then_stops_on_release` (with `fakeAsync`: press, advance 400 ms + 360 ms gives at least 3 fires; release; advance 1 s gives no further fires).
  - `hold_repeat_stops_on_dispose` (disposing mid-hold stops firing).
  - `no_exception_when_driver_sendKey_throws` (driver throws `TvConnectionError`; screen stays up and shows a snackbar, so Review Focus 4 holds).
- [ ] **Step 2: Run `flutter test test/ui`.** Expected: FAIL.
- [ ] **Step 3: Implement** the widgets, laid out per the chosen mockup.
- [ ] **Step 4: Run the tests.** Expected: PASS.
- [ ] **Step 5: Commit** `feat: remote screen`.

### Task 9: App wiring, picker and pairing flow

**Files:**
- Create: `lib/app.dart`, `lib/providers.dart`, `lib/ui/tv_picker_screen.dart`, `lib/ui/add_tv_dialog.dart`
- Modify: `lib/main.dart`
- Test: `test/ui/tv_picker_screen_test.dart`, `test/app_flow_test.dart`

**Interfaces:**
- Consumes: Tasks 2 to 8.
- Produces: Riverpod providers `tvRepositoryProvider`, `keyStoreProvider`, `discoveryProvider` (a `StreamProvider<TvDevice>`), `driverProvider(TvDevice)` (creates `LgDriver` with `WebSocketTransport` and `SecureKeyStore`; overridable in tests). `TvPickerScreen` lists saved and discovered TVs, supports manual IP entry via `AddTvDialog`, and shows an empty state ("No TVs found. Enter an IP address.") when nothing is found. Selecting a TV refreshes its host via `refreshHost`, connects, shows "Accept the prompt on your TV" while `AwaitingPairing`, shows retry on `PairingDenied`, then opens `RemoteScreen`. The power handler calls `driver.sendKey(TvKey.power)` when connected, otherwise `sendWakeOnLan(device.mac!)` (or a "No MAC saved; power on the TV once" message if `mac == null`). The MAC address is read from the TV's SSDP/info response when paired and saved with the device.

- [ ] **Step 1: Write failing tests:**
  - `picker_shows_empty_state_when_nothing_found`.
  - `picker_lists_saved_and_discovered_tvs`.
  - `selecting_tv_with_denied_pairing_shows_retry`.
  - `app_flow_pairs_and_opens_remote` (override `driverProvider` with a `FakeDriver` that emits `AwaitingPairing` then `Connected`; expects the remote screen).
  - `power_when_disconnected_without_mac_shows_message`.
- [ ] **Step 2: Run `flutter test test/ui/tv_picker_screen_test.dart test/app_flow_test.dart`.** Expected: FAIL.
- [ ] **Step 3: Implement** providers, screens and `main.dart` wiring.
- [ ] **Step 4: Run `flutter analyze && flutter test`.** Expected: no issues; all tests pass.
- [ ] **Step 5: Commit** `feat: app wiring and tv picker`.

### Task 10: Hardware checklist and run on devices

**Files:**
- Create: `docs/lg-hardware-checklist.md`

- [ ] **Step 1: Write the checklist** covering: Wi-Fi same network; first pairing prompt appears and Accept stores the key; relaunch reconnects without a prompt; every basic key works; hold-repeat on volume and arrows; power off then Wake-on-LAN power on (TV setting "Turn on via Wi-Fi" enabled); TV unplugged gives a clear error within about 5 s; deny prompt shows retry; change TV IP and confirm rediscovery; iOS Local Network permission prompt appears; measure tap-to-response against the 150 ms target.
- [ ] **Step 2: Build debug apps** with `flutter build apk --debug` and `flutter build ios --debug --no-codesign`. Expected: both succeed (iOS only on a macOS host; otherwise record as not run).
- [ ] **Step 3: Commit** `docs: LG hardware checklist`. The owner runs the checklist on their LG TV and reports failures.

---

## Self-review notes
- Spec coverage: discovery, pairing, token storage, capabilities, Glass Aurora UI, hold-repeat, reconnect, Wake-on-LAN, multi-TV and manual IP, LG-first order are all covered. Out of scope here by design: Roku, Samsung, Android/Google TV, Fire TV, Vizio, text entry, app launch (later plans).
- Types match across tasks: `TvDriver.sendKey(TvKey)`, `TvDevice.mac`, `KeyStore`, `Transport`, `LgKeyMap`.
- Cannot be verified here: real LG behavior (pointer socket, exact manifest permissions, MAC retrieval). Task 10 is the proof, and Task 4 and Task 9 should be adjusted after the first real-TV test.
