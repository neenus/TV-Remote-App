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

  test('send_key_mute_sets_mute', () async {
    final d = build(tv, keys);
    await d.connect();
    await d.sendKey(TvKey.mute);
    final m = jsonDecode(tv.main.sent.last) as Map;
    expect(m['uri'], 'ssap://audio/setMute');
    expect((m['payload'] as Map)['mute'], true);
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
}
