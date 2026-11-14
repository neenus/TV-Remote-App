import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/core/tv_device.dart';
import 'package:tv_remote/core/tv_driver.dart';
import 'package:tv_remote/core/tv_key.dart';
import 'package:tv_remote/drivers/samsung/samsung_legacy_driver.dart';
import 'package:tv_remote/drivers/samsung/samsung_legacy_protocol.dart';

import '../../support/fake_legacy_tv.dart';

const device = TvDevice(id: 'l-1', name: 'Old Samsung', brand: TvBrand.samsungLegacy, host: '10.0.0.7');

SamsungLegacyDriver build(FakeLegacyTv tv,
        {Duration timeout = const Duration(seconds: 2),
        Duration pairing = const Duration(seconds: 2),
        Duration ack = const Duration(milliseconds: 150),
        Future<Map<String, dynamic>?> Function(Uri)? fetch}) =>
    SamsungLegacyDriver(device, tv.make,
        fetchJson: fetch,
        connectTimeout: timeout,
        pairingTimeout: pairing,
        ackTimeout: ack);

void main() {
  late FakeLegacyTv tv;
  setUp(() => tv = FakeLegacyTv());

  test('connects_to_port_55000_and_sends_the_handshake', () async {
    await build(tv).connect();
    expect(tv.transports.first.host, '10.0.0.7');
    expect(tv.transports.first.port, 55000);
    expect(tv.transports.first.sent.first, legacyHandshake());
  });

  test('already_allowed_tv_connects_without_a_prompt_state', () async {
    final d = build(tv);
    final states = <TvConnectionState>[];
    d.state.listen(states.add);
    await d.connect();
    await Future<void>.delayed(Duration.zero);
    expect(states.map((s) => s.runtimeType), [Connecting, Connected]);
  });

  test('prompt_then_allow_shows_awaiting_pairing_then_connected', () async {
    tv.mode = LegacyMode.waitThenGrant;
    final d = build(tv);
    final states = <TvConnectionState>[];
    d.state.listen(states.add);
    final connecting = d.connect();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(states.map((s) => s.runtimeType), [Connecting, AwaitingPairing]);
    tv.accept();
    await connecting;
    await Future<void>.delayed(Duration.zero);
    expect(states.last, isA<Connected>());
  });

  test('denied_fails_with_PairingDenied', () async {
    tv.mode = LegacyMode.deny;
    await expectLater(build(tv).connect(), throwsA(isA<PairingDenied>()));
  });

  test('cancelled_prompt_fails_with_PairingDenied', () async {
    tv.mode = LegacyMode.cancel;
    await expectLater(build(tv).connect(), throwsA(isA<PairingDenied>()));
  });

  test('unanswered_prompt_times_out_as_PairingDenied', () async {
    tv.mode = LegacyMode.waitThenSilence;
    final d = build(tv, pairing: const Duration(milliseconds: 100));
    await expectLater(d.connect(), throwsA(isA<PairingDenied>()));
  });

  test('no_reply_at_all_is_a_connection_error_within_the_timeout', () async {
    tv.mode = LegacyMode.silent;
    final d = build(tv, timeout: const Duration(milliseconds: 100));
    await expectLater(d.connect().timeout(const Duration(seconds: 1)),
        throwsA(isA<TvConnectionError>()));
  });

  test('unreachable_tv_is_a_connection_error', () async {
    tv.openFails = true;
    await expectLater(build(tv).connect(), throwsA(isA<TvConnectionError>()));
  });

  test('garbage_reply_is_a_connection_error', () async {
    tv.mode = LegacyMode.garbage;
    await expectLater(build(tv).connect(), throwsA(isA<TvConnectionError>()));
  });

  test('replies_split_into_single_bytes_still_work', () async {
    tv.chunked = true;
    await build(tv).connect();
  });

  test('socket_close_mid_handshake_fails_connect_instead_of_hanging', () async {
    tv.mode = LegacyMode.waitThenSilence;
    final d = build(tv);
    final pending = expectLater(d.connect(), throwsA(isA<TvConnectionError>()));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    tv.transports.first.closeFromRemote();
    await pending.timeout(const Duration(seconds: 1));
    tv.mode = LegacyMode.grant;
    await d.connect().timeout(const Duration(seconds: 1)); // driver recovers
  });

  test('disposing_during_the_prompt_fails_connect_instead_of_hanging', () async {
    tv.mode = LegacyMode.waitThenSilence;
    final d = build(tv);
    final pending = expectLater(d.connect(), throwsA(isA<TvConnectionError>()));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await d.dispose();
    await pending.timeout(const Duration(seconds: 1));
  });

  test('disposing_while_the_socket_is_opening_closes_it_and_ends_connect', () async {
    tv.openDelay = const Duration(milliseconds: 100);
    final d = build(tv);
    final pending = expectLater(d.connect(), throwsA(isA<TvConnectionError>()));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await d.dispose();
    await pending.timeout(const Duration(seconds: 1));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(tv.transports.every((t) => !t.isOpen), isTrue);
  });

  test('unexpected_exception_becomes_connection_error', () async {
    final d = SamsungLegacyDriver(device, () => throw StateError('boom'));
    final states = <TvConnectionState>[];
    d.state.listen(states.add);
    await expectLater(d.connect(), throwsA(isA<TvConnectionError>()));
    await Future<void>.delayed(Duration.zero);
    expect(states.last, isA<Failed>());
  });

  test('send_key_sends_the_packet_for_the_mapped_key', () async {
    final d = build(tv);
    await d.connect();
    await d.sendKey(TvKey.volumeUp);
    await d.sendKey(TvKey.power);
    await d.sendKey(TvKey.home);
    final sent = tv.transports.first.sent;
    expect(sent[1], legacyKeyPacket('KEY_VOLUP'));
    expect(sent[2], legacyKeyPacket('KEY_POWEROFF'));
    expect(sent[3], legacyKeyPacket('KEY_CONTENTS'));
  });

  test('key_acknowledgements_and_duplicate_grants_are_ignored', () async {
    final d = build(tv);
    final states = <TvConnectionState>[];
    d.state.listen(states.add);
    await d.connect();
    await d.sendKey(TvKey.up);
    tv.transports.first.push(legacyFrame([0x64, 0, 1, 0]));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(states.last, isA<Connected>());
  });

  test('closed_socket_reports_disconnected_and_next_key_reconnects', () async {
    final d = build(tv);
    final states = <TvConnectionState>[];
    d.state.listen(states.add);
    await d.connect();
    tv.transports.first.closeFromRemote();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(states.last, isA<Disconnected>());
    await d.sendKey(TvKey.volumeDown);
    expect(tv.transports.length, 2);
    expect(tv.transports.last.sent.last, legacyKeyPacket('KEY_VOLDOWN'));
  });

  test('concurrent_presses_while_reconnecting_send_once', () async {
    final d = build(tv);
    await d.connect();
    tv.transports.first.closeFromRemote();
    await Future<void>.delayed(Duration.zero);
    await Future.wait(List.generate(10, (_) => d.sendKey(TvKey.volumeUp)));
    final sends = tv.transports.last.sent.where((p) => p.length == legacyKeyPacket('KEY_VOLUP').length &&
        p.toString() == legacyKeyPacket('KEY_VOLUP').toString()).length;
    expect(sends, 1);
  });

  test('typing_is_not_supported_but_does_not_crash', () async {
    final d = build(tv);
    final events = <bool>[];
    d.keyboardFocus.listen(events.add);
    expect(d.capabilities.typing, isFalse);
    await expectLater(d.sendText('a'), throwsA(isA<TvConnectionError>()));
    await expectLater(d.deleteText(1), throwsA(isA<TvConnectionError>()));
    await expectLater(d.sendEnter(), throwsA(isA<TvConnectionError>()));
    await d.submitPairingPin('1'); // ignored
    expect(events, isEmpty);
  });

  test('mac_is_best_effort_and_null_when_unavailable', () async {
    expect(await build(tv, fetch: (_) async => null).fetchMacAddress(), isNull);
    expect(
        await build(tv, fetch: (_) async => {'device': {'wifiMac': 'aa:bb:cc:dd:ee:ff'}})
            .fetchMacAddress(),
        'AA:BB:CC:DD:EE:FF');
  });

  test('repeated_waiting_frames_do_not_extend_the_pairing_timeout', () async {
    tv.mode = LegacyMode.repeatWaiting;
    final d = build(tv, pairing: const Duration(milliseconds: 300));
    await expectLater(d.connect().timeout(const Duration(seconds: 2)),
        throwsA(isA<PairingDenied>()));
  });

  test('missing_key_ack_is_detected_and_the_next_press_reconnects', () async {
    final d = build(tv);
    final states = <TvConnectionState>[];
    d.state.listen(states.add);
    await d.connect();
    tv.ackKeys = false;
    await d.sendKey(TvKey.volumeUp);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(states.last, isA<Disconnected>());
    tv.ackKeys = true;
    await d.sendKey(TvKey.volumeUp);
    expect(tv.transports.length, 2);
  });

  test('acknowledged_keys_keep_the_connection_alive', () async {
    final d = build(tv);
    final states = <TvConnectionState>[];
    d.state.listen(states.add);
    await d.connect();
    await d.sendKey(TvKey.volumeUp);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(states.last, isA<Connected>());
    expect(tv.transports.length, 1);
  });

  test('denied_after_connect_is_reported_and_the_next_press_retries', () async {
    final d = build(tv);
    final states = <TvConnectionState>[];
    d.state.listen(states.add);
    await d.connect();
    tv.transports.first.push(legacyFrame([0x64, 0, 0, 0]));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(states.last, isA<Failed>());
    expect((states.last as Failed).error, isA<PairingDenied>());
    await d.sendKey(TvKey.volumeUp);
    expect(tv.transports.length, 2);
  });

  test('denied_message_says_what_to_do_when_no_prompt_appears', () async {
    tv.mode = LegacyMode.deny;
    await expectLater(
        build(tv).connect(),
        throwsA(isA<PairingDenied>()
            .having((e) => e.message, 'message', contains('If no prompt appears'))));
  });

  test('unreachable_message_admits_some_2014_2015_models_are_unsupported', () async {
    tv.openFails = true;
    await expectLater(
        build(tv).connect(),
        throwsA(isA<TvConnectionError>()
            .having((e) => e.message, 'message', contains('2014'))));
  });
}
