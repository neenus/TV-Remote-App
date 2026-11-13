import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/core/key_store.dart';
import 'package:tv_remote/core/tv_device.dart';
import 'package:tv_remote/core/tv_driver.dart';
import 'package:tv_remote/core/tv_key.dart';
import 'package:tv_remote/drivers/lg/lg_driver.dart';

import '../../support/fake_tv.dart';

const device =
    TvDevice(id: 'lg-1', name: 'LG', brand: TvBrand.lg, host: 'tv');

LgDriver build(FakeTv tv, MemoryKeyStore keys,
        {Duration timeout = const Duration(seconds: 2)}) =>
    LgDriver(device, keys, tv.make, connectTimeout: timeout);

void main() {
  late FakeTv tv;
  late MemoryKeyStore keys;
  setUp(() {
    tv = FakeTv();
    keys = MemoryKeyStore();
  });

  test('first_connect_sends_register_without_key_and_stores_key_on_registered',
      () async {
    tv.promptFirst = true;
    final d = build(tv, keys);
    final states = <TvConnectionState>[];
    d.state.listen(states.add);
    await d.connect();
    await Future<void>.delayed(Duration.zero);
    expect(
        (tv.registerMessages().first['payload'] as Map).containsKey('client-key'),
        isFalse);
    expect(await keys.read('lg-1'), 'abc');
    expect(states.map((s) => s.runtimeType),
        [Connecting, AwaitingPairing, Connected]);
  });

  test('reconnect_uses_stored_key', () async {
    await keys.write('lg-1', 'abc');
    await build(tv, keys).connect();
    expect((tv.registerMessages().first['payload'] as Map)['client-key'], 'abc');
  });

  test('pairing_denied_reports_error_and_stores_nothing', () async {
    tv.denyPairing = true;
    final d = build(tv, keys);
    await expectLater(d.connect(), throwsA(isA<PairingDenied>()));
    expect(await keys.read('lg-1'), isNull);
  });

  test('rejected_stored_key_is_deleted_and_repaired', () async {
    await keys.write('lg-1', 'old');
    tv.rejectStoredKeys = true;
    tv.clientKeyToIssue = 'new';
    await build(tv, keys).connect();
    final regs = tv.registerMessages().toList();
    expect((regs[0]['payload'] as Map)['client-key'], 'old');
    expect((regs[1]['payload'] as Map).containsKey('client-key'), isFalse);
    expect(await keys.read('lg-1'), 'new');
  });

  test('connect_times_out_to_TvConnectionError', () async {
    tv.silent = true;
    final d = build(tv, keys, timeout: const Duration(milliseconds: 50));
    final states = <TvConnectionState>[];
    d.state.listen(states.add);
    await expectLater(d.connect(), throwsA(isA<TvConnectionError>()));
    await Future<void>.delayed(Duration.zero);
    expect(states.last, isA<Failed>());
  });

  test('unreachable_tv_is_TvConnectionError', () async {
    tv.openFails = true;
    await expectLater(
        build(tv, keys).connect(), throwsA(isA<TvConnectionError>()));
  });

  test('send_key_dpad_uses_pointer_socket', () async {
    final d = build(tv, keys);
    await d.connect();
    await d.sendKey(TvKey.up);
    expect(tv.transports[1].sent.last, 'type:button\nname:UP\n\n');
  });

  test('send_key_volume_uses_request_uri', () async {
    final d = build(tv, keys);
    await d.connect();
    await d.sendKey(TvKey.volumeUp);
    final m = jsonDecode(tv.main.sent.last) as Map;
    expect(m['type'], 'request');
    expect(m['uri'], 'ssap://audio/volumeUp');
  });

  test('mute_uses_toggle_pointer_button', () async {
    final d = build(tv, keys);
    await d.connect();
    await d.sendKey(TvKey.mute);
    expect(tv.transports[1].sent.last, 'type:button\nname:MUTE\n\n');
  });

  test('malformed_inbound_is_ignored', () async {
    final d = build(tv, keys);
    final states = <TvConnectionState>[];
    d.state.listen(states.add);
    await d.connect();
    tv.main.push('%%%');
    await Future<void>.delayed(Duration.zero);
    expect(states.last, isA<Connected>());
  });

  test('socket_close_triggers_disconnected_then_reconnect_on_next_sendKey',
      () async {
    final d = build(tv, keys);
    final states = <TvConnectionState>[];
    d.state.listen(states.add);
    await d.connect();
    tv.main.closeFromRemote();
    await Future<void>.delayed(Duration.zero);
    expect(states.last, isA<Disconnected>());
    await d.sendKey(TvKey.volumeDown);
    expect(tv.transports.length, 4);
    final m = jsonDecode(tv.transports[2].sent.last) as Map;
    expect(m['uri'], 'ssap://audio/volumeDown');
  });

  test('connection_dropped_while_awaiting_pairing_fails_instead_of_hanging',
      () async {
    tv.promptOnly = true;
    final d = build(tv, keys);
    final pending = expectLater(d.connect(), throwsA(isA<TvConnectionError>()));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    tv.main.closeFromRemote();
    await pending.timeout(const Duration(seconds: 1));
    tv.promptOnly = false;
    await d.connect().timeout(const Duration(seconds: 1)); // driver recovers
  });

  test('duplicate_registered_message_is_ignored', () async {
    final d = build(tv, keys);
    final states = <TvConnectionState>[];
    d.state.listen(states.add);
    await d.connect();
    tv.main.push('{"type":"registered","id":"register_0","payload":{"client-key":"abc"}}');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(states.last, isA<Connected>());
  });

  test('key_store_failures_do_not_break_connect', () async {
    final d = LgDriver(device, ThrowingKeyStore(), tv.make,
        connectTimeout: const Duration(seconds: 2));
    await d.connect();
  });

  test('unexpected_exception_becomes_connection_error', () async {
    final d = LgDriver(device, keys, () => throw StateError('boom'));
    final states = <TvConnectionState>[];
    d.state.listen(states.add);
    await expectLater(d.connect(), throwsA(isA<TvConnectionError>()));
    await Future<void>.delayed(Duration.zero);
    expect(states.last, isA<Failed>());
  });

  test('stale_key_then_prompt_then_denied_is_PairingDenied_without_second_prompt',
      () async {
    await keys.write('lg-1', 'stale');
    tv.promptThenDeny = true;
    await expectLater(build(tv, keys).connect(), throwsA(isA<PairingDenied>()));
    expect(tv.registerMessages().length, 1);
    expect(await keys.read('lg-1'), isNull);
  });

  test('concurrent_presses_while_reconnecting_send_once', () async {
    final d = build(tv, keys);
    await d.connect();
    tv.main.closeFromRemote();
    await Future<void>.delayed(Duration.zero);
    await Future.wait(List.generate(10, (_) => d.sendKey(TvKey.volumeUp)));
    final volumeRequests = tv.transports[2].sent
        .where((s) => s.contains('ssap://audio/volumeUp'))
        .length;
    expect(volumeRequests, 1);
  });

  test('pointer_socket_error_fails_fast_with_tv_message', () async {
    tv.pointerError = true;
    await expectLater(
        build(tv, keys).connect().timeout(const Duration(milliseconds: 500)),
        throwsA(isA<TvConnectionError>()
            .having((e) => e.message, 'message', contains('401'))));
  });
}

class ThrowingKeyStore implements KeyStore {
  @override
  Future<String?> read(String deviceId) async => throw Exception('keystore');
  @override
  Future<void> write(String deviceId, String key) async => throw Exception('keystore');
  @override
  Future<void> delete(String deviceId) async => throw Exception('keystore');
}
