import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/core/key_store.dart';
import 'package:tv_remote/core/tv_device.dart';
import 'package:tv_remote/core/tv_driver.dart';
import 'package:tv_remote/core/tv_key.dart';
import 'package:tv_remote/drivers/samsung/samsung_driver.dart';
import 'package:tv_remote/drivers/samsung/samsung_protocol.dart';

import '../../support/fake_samsung_tv.dart';

const device = TvDevice(id: 's-1', name: 'Samsung', brand: TvBrand.samsung, host: '10.0.0.9');

class ThrowingKeyStore implements KeyStore {
  @override
  Future<String?> read(String deviceId) async => throw Exception('keystore');
  @override
  Future<void> write(String deviceId, String key) async => throw Exception('keystore');
  @override
  Future<void> delete(String deviceId) async => throw Exception('keystore');
}

SamsungDriver build(FakeSamsungTv tv, KeyStore keys,
        {Duration timeout = const Duration(seconds: 2),
        Duration pairing = const Duration(seconds: 2),
        Future<Map<String, dynamic>?> Function(Uri)? fetch}) =>
    SamsungDriver(device, keys, tv.make,
        fetchJson: fetch, connectTimeout: timeout, pairingTimeout: pairing);

void main() {
  late FakeSamsungTv tv;
  late MemoryKeyStore keys;
  setUp(() {
    tv = FakeSamsungTv();
    keys = MemoryKeyStore();
  });

  test('first_connect_shows_awaiting_pairing_then_connected_and_stores_token', () async {
    tv.holdAllow = true;
    final d = build(tv, keys);
    final states = <TvConnectionState>[];
    d.state.listen(states.add);
    final connecting = d.connect();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(states.map((s) => s.runtimeType), [Connecting, AwaitingPairing]);
    tv.accept();
    await connecting;
    await Future<void>.delayed(Duration.zero);
    expect(states.last, isA<Connected>());
    expect(await keys.read('s-1'), '12345678');
  });

  test('reconnect_sends_stored_token_without_a_prompt_state', () async {
    await keys.write('s-1', 'abc');
    final d = build(tv, keys);
    final states = <TvConnectionState>[];
    d.state.listen(states.add);
    await d.connect();
    expect(tv.openedUris.first.queryParameters['token'], 'abc');
    expect(states.any((s) => s is AwaitingPairing), isFalse);
  });

  test('denied_prompt_fails_with_PairingDenied_and_stores_nothing', () async {
    tv.deny = true;
    await expectLater(build(tv, keys).connect(), throwsA(isA<PairingDenied>()));
    expect(await keys.read('s-1'), isNull);
  });

  test('rejected_stored_token_is_deleted_and_retried_without_a_token', () async {
    await keys.write('s-1', 'old');
    tv.rejectStoredToken = true;
    await build(tv, keys).connect();
    expect(tv.openedUris[0].queryParameters['token'], 'old');
    expect(tv.openedUris[1].queryParameters.containsKey('token'), isFalse);
    expect(await keys.read('s-1'), '12345678');
  });

  test('rejected_socket_is_closed_and_cannot_disturb_the_new_connection', () async {
    await keys.write('s-1', 'old');
    tv.rejectStoredToken = true;
    final d = build(tv, keys);
    final states = <TvConnectionState>[];
    d.state.listen(states.add);
    await d.connect();
    expect(tv.transports[0].isOpen, isFalse);
    tv.transports[0].closeFromRemote();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(states.last, isA<Connected>());
    await d.sendKey(TvKey.volumeUp);
    expect(tv.transports[1].sent.last, samsungKeyMessage('KEY_VOLUP'));
  });

  test('tv_dropping_the_rejected_socket_does_not_abort_the_new_prompt', () async {
    await keys.write('s-1', 'old');
    tv.rejectStoredToken = true;
    tv.closeAfterUnauthorized = true;
    tv.holdAllow = true;
    final connecting = build(tv, keys).connect();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    tv.accept();
    await connecting.timeout(const Duration(seconds: 1));
    expect(await keys.read('s-1'), '12345678');
  });

  test('slow_tv_with_a_stored_token_keeps_its_socket_and_token_while_waiting', () async {
    await keys.write('s-1', 'old');
    tv.ignoreStoredToken = true;
    final d = build(tv, keys, timeout: const Duration(milliseconds: 80));
    final states = <TvConnectionState>[];
    d.state.listen(states.add);
    final connecting = d.connect();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(states.any((s) => s is AwaitingPairing), isTrue);
    expect(tv.transports.length, 1);
    expect(await keys.read('s-1'), 'old');
    tv.accept();
    await connecting.timeout(const Duration(seconds: 1));
    expect(await keys.read('s-1'), '12345678');
    expect(tv.transports.length, 1);
  });

  test('stored_token_is_not_deleted_when_the_secure_port_is_unreachable', () async {
    await keys.write('s-1', 'good');
    tv.secureFails = true;
    await expectLater(build(tv, keys).connect(), throwsA(isA<TvConnectionError>()));
    expect(await keys.read('s-1'), 'good');
    expect(tv.openedUris.every((u) => u.scheme == 'wss'), isTrue);
  });

  test('remembers_that_only_the_plain_port_works', () async {
    tv.secureFails = true;
    final d = build(tv, keys);
    await d.connect();
    tv.transports.last.closeFromRemote();
    await Future<void>.delayed(Duration.zero);
    tv.openedUris.clear();
    await d.sendKey(TvKey.volumeUp);
    expect(tv.openedUris.first.scheme, 'ws');
  });

  test('disposing_while_the_socket_is_opening_ends_connect_and_closes_the_socket', () async {
    tv.openDelay = const Duration(milliseconds: 100);
    final d = build(tv, keys);
    final pending = expectLater(d.connect(), throwsA(isA<TvConnectionError>()));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await d.dispose();
    await pending.timeout(const Duration(seconds: 1));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(tv.transports.every((t) => !t.isOpen), isTrue);
  });

  test('prompt_timeout_event_is_PairingDenied_and_stores_nothing', () async {
    tv.sendTimeOut = true;
    await expectLater(build(tv, keys).connect(), throwsA(isA<PairingDenied>()));
    expect(await keys.read('s-1'), isNull);
  });

  test('denied_message_says_where_to_allow_the_device_on_the_tv', () async {
    tv.deny = true;
    await expectLater(
        build(tv, keys).connect(),
        throwsA(isA<PairingDenied>()
            .having((e) => e.message, 'message', contains('Device Connection Manager'))));
  });

  test('samsung_reports_typing_as_unsupported', () {
    expect(build(tv, keys).capabilities.typing, isFalse);
  });

  test('unanswered_prompt_times_out_as_PairingDenied', () async {
    tv.holdAllow = true;
    final d = build(tv, keys, pairing: const Duration(milliseconds: 80));
    await expectLater(d.connect(), throwsA(isA<PairingDenied>()));
    expect(await keys.read('s-1'), isNull);
  });

  test('unreachable_tv_is_TvConnectionError_that_points_to_the_older_option', () async {
    tv.openAlwaysFails = true;
    await expectLater(
        build(tv, keys).connect(),
        throwsA(isA<TvConnectionError>()
            .having((e) => e.message, 'message', contains('pre-2016'))));
  });

  test('falls_back_to_the_plain_port_when_secure_is_unavailable', () async {
    tv.secureFails = true;
    await build(tv, keys).connect();
    expect(tv.openedUris.last.scheme, 'ws');
    expect(tv.openedUris.last.port, 8001);
  });

  test('socket_close_mid_handshake_fails_connect_instead_of_hanging', () async {
    tv.holdAllow = true;
    final d = build(tv, keys);
    final pending = expectLater(d.connect(), throwsA(isA<TvConnectionError>()));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    tv.transports.first.closeFromRemote();
    await pending.timeout(const Duration(seconds: 1));
    tv.holdAllow = false;
    await d.connect().timeout(const Duration(seconds: 1)); // driver recovers
  });

  test('disposing_during_pairing_fails_connect_instead_of_hanging', () async {
    tv.holdAllow = true;
    final d = build(tv, keys);
    final pending = expectLater(d.connect(), throwsA(isA<TvConnectionError>()));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await d.dispose();
    await pending.timeout(const Duration(seconds: 1));
  });

  test('unexpected_exception_becomes_connection_error', () async {
    final d = SamsungDriver(device, keys, () => throw StateError('boom'));
    final states = <TvConnectionState>[];
    d.state.listen(states.add);
    await expectLater(d.connect(), throwsA(isA<TvConnectionError>()));
    await Future<void>.delayed(Duration.zero);
    expect(states.last, isA<Failed>());
  });

  test('key_store_failures_do_not_break_connect', () async {
    await build(tv, ThrowingKeyStore()).connect();
  });

  test('duplicate_and_malformed_events_are_ignored', () async {
    final d = build(tv, keys);
    final states = <TvConnectionState>[];
    d.state.listen(states.add);
    await d.connect();
    tv.transports.first.push('{"event":"ms.channel.connect","data":{"token":"x"}}');
    tv.transports.first.push('%%%');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(states.last, isA<Connected>());
  });

  test('send_key_sends_the_mapped_message', () async {
    final d = build(tv, keys);
    await d.connect();
    await d.sendKey(TvKey.volumeUp);
    expect(tv.transports.first.sent.last, samsungKeyMessage('KEY_VOLUP'));
  });

  test('concurrent_presses_while_reconnecting_send_once', () async {
    final d = build(tv, keys);
    await d.connect();
    tv.transports.first.closeFromRemote();
    await Future<void>.delayed(Duration.zero);
    await Future.wait(List.generate(10, (_) => d.sendKey(TvKey.volumeUp)));
    final sends = tv.transports.last.sent.where((s) => s.contains('KEY_VOLUP')).length;
    expect(sends, 1);
  });

  test('mac_is_read_from_the_device_info_endpoint', () async {
    Uri? asked;
    final d = build(tv, keys, fetch: (uri) async {
      asked = uri;
      return {'device': {'wifiMac': 'aa:bb:cc:dd:ee:ff'}};
    });
    expect(await d.fetchMacAddress(), 'AA:BB:CC:DD:EE:FF');
    expect(asked, Uri.parse('http://10.0.0.9:8001/api/v2/'));
  });

  test('mac_is_null_when_the_endpoint_fails_or_is_unreadable', () async {
    expect(await build(tv, keys, fetch: (_) async => null).fetchMacAddress(), isNull);
    expect(await build(tv, keys, fetch: (_) async => throw Exception('x')).fetchMacAddress(),
        isNull);
  });

  test('typing_is_not_supported_but_does_not_crash', () async {
    final d = build(tv, keys);
    final events = <bool>[];
    d.keyboardFocus.listen(events.add);
    await expectLater(d.sendText('a'), throwsA(isA<TvConnectionError>()));
    await expectLater(d.deleteText(1), throwsA(isA<TvConnectionError>()));
    await expectLater(d.sendEnter(), throwsA(isA<TvConnectionError>()));
    expect(events, isEmpty);
    await d.submitPairingPin('1234'); // ignored
  });
}
