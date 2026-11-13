import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/core/key_store.dart';
import 'package:tv_remote/core/tv_device.dart';
import 'package:tv_remote/core/tv_driver.dart';
import 'package:tv_remote/core/tv_key.dart';
import 'package:tv_remote/drivers/samsung/samsung_encrypted_crypto.dart';
import 'package:tv_remote/drivers/samsung/samsung_encrypted_driver.dart';
import 'package:tv_remote/drivers/samsung/samsung_encrypted_protocol.dart';

import '../../support/fake_samsung_http.dart';
import '../../support/fake_sio.dart';
import '../../support/samsung_encrypted_goldens.dart';

const device = TvDevice(id: 'e-1', name: 'Old Samsung', brand: TvBrand.samsungEncrypted, host: '10.0.0.5');
final vector = exchangeVectors.first; // PIN 1234
final creds = '${vector.ctx}:1';

class ThrowingKeyStore implements KeyStore {
  @override
  Future<String?> read(String deviceId) async => throw Exception('keystore');
  @override
  Future<void> write(String deviceId, String key) async => throw Exception('keystore');
  @override
  Future<void> delete(String deviceId) async => throw Exception('keystore');
}

String keyFrame(TvKey k, String wire) => SamsungEncryptedSession(vector.ctx, '1').encryptKeyCommand(wire);

void main() {
  late FakeSamsungHttp http;
  late FakeSioTv sio;
  late MemoryKeyStore keys;

  SamsungEncryptedDriver build(
          {KeyStore? store,
          Duration timeout = const Duration(seconds: 2),
          Duration pairing = const Duration(seconds: 2),
          Duration? idle,
          Future<Map<String, dynamic>?> Function(Uri)? fetch}) =>
      SamsungEncryptedDriver(device, store ?? keys, sio.make, http,
          fetchJson: fetch, connectTimeout: timeout, pairingTimeout: pairing, idleTimeout: idle);

  setUp(() {
    http = FakeSamsungHttp()
      ..clientHello = vector.clientHello
      ..clientAck = vector.clientAck;
    sio = FakeSioTv();
    keys = MemoryKeyStore();
  });

  group('first pairing', () {
    test('shows_a_pin_prompt_then_connects_and_stores_the_credentials', () async {
      final d = build();
      final states = <TvConnectionState>[];
      d.state.listen(states.add);
      final connecting = d.connect();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(states.map((s) => s.runtimeType), [Connecting, AwaitingPin]);
      expect(http.where('POST', '/ws/apps/CloudPINPage'), hasLength(1));
      await d.submitPairingPin('1234');
      await connecting;
      await Future<void>.delayed(Duration.zero);
      expect(states.last, isA<Connected>());
      expect(await keys.read('e-1'), creds);
      expect(sio.transports.first.uri.toString(), 'ws://10.0.0.5:8000/socket.io/1/websocket/SID123');
      expect(sio.transports.first.sent.first, socketIoConnectFrame);
      expect(http.where('DELETE', '/ws/apps/CloudPINPage/run'), hasLength(1));
    });

    test('wrong_pin_is_PairingDenied_stores_nothing_and_closes_the_pin_screen', () async {
      final d = build();
      final pending = expectLater(d.connect(),
          throwsA(isA<PairingDenied>().having((e) => e.message, 'message', contains('not accepted'))));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await d.submitPairingPin('4321');
      await pending;
      expect(await keys.read('e-1'), isNull);
      expect(http.where('DELETE', '/ws/apps/CloudPINPage/run'), isNotEmpty);
    });

    test('expired_pin_window_is_PairingDenied_and_stores_nothing', () async {
      http.emptyAuthData = true;
      final d = build();
      final pending = expectLater(d.connect(), throwsA(isA<PairingDenied>()));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await d.submitPairingPin('1234');
      await pending;
      expect(await keys.read('e-1'), isNull);
    });

    test('unanswered_prompt_times_out_and_closes_the_pin_screen', () async {
      final d = build(pairing: const Duration(milliseconds: 80));
      await expectLater(d.connect(), throwsA(isA<PairingDenied>()));
      expect(http.where('DELETE', '/ws/apps/CloudPINPage/run'), isNotEmpty);
    });

    test('disposing_during_the_prompt_ends_connect_and_closes_the_pin_screen', () async {
      final d = build();
      final pending = expectLater(d.connect(), throwsA(isA<TvConnectionError>()));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await d.dispose();
      await pending.timeout(const Duration(seconds: 1));
      expect(http.where('DELETE', '/ws/apps/CloudPINPage/run'), isNotEmpty);
    });

    test('unreachable_tv_is_a_connection_error', () async {
      http.failAll = true;
      await expectLater(build().connect(), throwsA(isA<TvConnectionError>()));
    });

    test('submitting_a_pin_when_not_asked_is_ignored', () async {
      final d = build();
      await d.submitPairingPin('1234');
      await keys.write('e-1', creds);
      await d.connect();
      await d.submitPairingPin('1234');
    });

    test('the_pairing_mode_flag_is_ignored', () async {
      await keys.write('e-1', creds);
      await build().connect(pinPairing: false);
    });
  });

  group('connecting with saved credentials', () {
    setUp(() async => keys.write('e-1', creds));

    test('skips_pairing_entirely', () async {
      final d = build();
      final states = <TvConnectionState>[];
      d.state.listen(states.add);
      await d.connect();
      expect(http.requests.where((r) => r.uri.port == 8080), isEmpty);
      expect(states.any((s) => s is AwaitingPin), isFalse);
    });

    test('control_port_unreachable_keeps_the_credentials', () async {
      http.sioFails = true;
      await expectLater(build().connect(), throwsA(isA<TvConnectionError>()));
      expect(await keys.read('e-1'), creds);
    });

    test('websocket_failure_is_a_connection_error', () async {
      sio.openFails = true;
      await expectLater(build().connect(), throwsA(isA<TvConnectionError>()));
    });

    test('unreadable_handshake_is_a_connection_error', () async {
      http.sioBody = '<html>nope</html>';
      await expectLater(build().connect(), throwsA(isA<TvConnectionError>()));
    });

    test('garbled_saved_credentials_fall_back_to_pairing', () async {
      await keys.write('e-1', 'garbage');
      final d = build();
      final states = <TvConnectionState>[];
      d.state.listen(states.add);
      final connecting = d.connect();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(states.last, isA<AwaitingPin>());
      await d.dispose();
      await connecting.catchError((_) {});
    });
  });

  group('keys', () {
    setUp(() async => keys.write('e-1', creds));

    test('send_key_sends_the_encrypted_frame', () async {
      final d = build();
      await d.connect();
      await d.sendKey(TvKey.volumeUp);
      expect(sio.transports.first.sent.last, keyFrame(TvKey.volumeUp, 'KEY_VOLUP'));
    });

    test('power_uses_the_older_power_off_key_and_home_the_smarthub_key', () async {
      final d = build();
      await d.connect();
      await d.sendKey(TvKey.power);
      await d.sendKey(TvKey.home);
      final sent = sio.transports.first.sent;
      expect(sent[sent.length - 2], keyFrame(TvKey.power, 'KEY_POWEROFF'));
      expect(sent.last, keyFrame(TvKey.home, 'KEY_CONTENTS'));
    });

    test('heartbeats_are_answered', () async {
      final d = build();
      await d.connect();
      sio.transports.first.push('2::');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(sio.transports.first.sent.last, socketIoHeartbeat);
    });

    test('malformed_and_unknown_frames_are_ignored', () async {
      final d = build();
      final states = <TvConnectionState>[];
      d.state.listen(states.add);
      await d.connect();
      sio.transports.first.push('%%%');
      sio.transports.first.push('5::/com.samsung.companion:{"name":"x"}');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(states.last, isA<Connected>());
    });

    test('closed_socket_reports_disconnected_and_the_next_press_reconnects', () async {
      final d = build();
      final states = <TvConnectionState>[];
      d.state.listen(states.add);
      await d.connect();
      sio.transports.first.closeFromRemote();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(states.last, isA<Disconnected>());
      await d.sendKey(TvKey.volumeDown);
      expect(sio.transports.length, 2);
      expect(sio.transports.last.sent.last, keyFrame(TvKey.volumeDown, 'KEY_VOLDOWN'));
    });

    test('concurrent_presses_while_reconnecting_send_once', () async {
      final d = build();
      await d.connect();
      sio.transports.first.closeFromRemote();
      await Future<void>.delayed(Duration.zero);
      await Future.wait(List.generate(10, (_) => d.sendKey(TvKey.volumeUp)));
      final frame = keyFrame(TvKey.volumeUp, 'KEY_VOLUP');
      expect(sio.transports.last.sent.where((s) => s == frame), hasLength(1));
    });

    test('a_silent_channel_is_dropped_and_the_next_press_reconnects', () async {
      final d = build(idle: const Duration(milliseconds: 100));
      final states = <TvConnectionState>[];
      d.state.listen(states.add);
      await d.connect();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(states.last, isA<Disconnected>());
      await d.sendKey(TvKey.volumeUp);
      expect(sio.transports.length, 2);
      expect(sio.transports.last.sent.last, keyFrame(TvKey.volumeUp, 'KEY_VOLUP'));
    });

    test('heartbeats_keep_the_channel_alive', () async {
      final d = build(idle: const Duration(milliseconds: 100));
      final states = <TvConnectionState>[];
      d.state.listen(states.add);
      await d.connect();
      for (var i = 0; i < 8; i++) {
        sio.transports.first.push('2::');
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      expect(states.last, isA<Connected>());
      expect(sio.transports.length, 1);
    });
  });

  group('robustness', () {
    test('unexpected_exception_becomes_connection_error', () async {
      final d = SamsungEncryptedDriver(device, keys, () => throw StateError('boom'), http);
      await keys.write('e-1', creds);
      final states = <TvConnectionState>[];
      d.state.listen(states.add);
      await expectLater(d.connect(), throwsA(isA<TvConnectionError>()));
      await Future<void>.delayed(Duration.zero);
      expect(states.last, isA<Failed>());
    });

    test('key_store_failures_do_not_break_pairing', () async {
      final d = build(store: ThrowingKeyStore());
      final connecting = d.connect();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await d.submitPairingPin('1234');
      await connecting;
    });

    test('typing_is_not_supported_but_does_not_crash', () async {
      final d = build();
      final events = <bool>[];
      d.keyboardFocus.listen(events.add);
      expect(d.capabilities.typing, isFalse);
      await expectLater(d.sendText('a'), throwsA(isA<TvConnectionError>()));
      await expectLater(d.deleteText(1), throwsA(isA<TvConnectionError>()));
      await expectLater(d.sendEnter(), throwsA(isA<TvConnectionError>()));
      expect(events, isEmpty);
    });

    test('mac_is_best_effort', () async {
      expect(await build(fetch: (_) async => null).fetchMacAddress(), isNull);
      expect(
          await build(fetch: (_) async => {'device': {'wifiMac': 'aa:bb:cc:dd:ee:ff'}})
              .fetchMacAddress(),
          'AA:BB:CC:DD:EE:FF');
    });
  });
}
