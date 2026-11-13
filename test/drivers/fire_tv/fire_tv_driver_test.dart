import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/core/key_store.dart';
import 'package:tv_remote/core/tv_device.dart';
import 'package:tv_remote/core/tv_driver.dart';
import 'package:tv_remote/core/tv_key.dart';
import 'package:tv_remote/drivers/fire_tv/adb_auth.dart';
import 'package:tv_remote/drivers/fire_tv/adb_protocol.dart';
import 'package:tv_remote/drivers/fire_tv/fire_tv_driver.dart';

import '../../support/adb_goldens.dart';
import '../../support/fake_adb_device.dart';

const device = TvDevice(id: 'f-1', name: 'Fire TV', brand: TvBrand.fireTv, host: '10.0.0.8');
final testKey = AdbKey(BigInt.parse(adbKeyN, radix: 16), BigInt.parse(adbKeyD, radix: 16));

class ThrowingKeyStore implements KeyStore {
  @override
  Future<String?> read(String deviceId) async => throw Exception('keystore');
  @override
  Future<void> write(String deviceId, String key) async => throw Exception('keystore');
  @override
  Future<void> delete(String deviceId) async => throw Exception('keystore');
}

void main() {
  late FakeAdbDevice tv;
  late MemoryKeyStore keys;
  var keysMade = 0;

  FireTvDriver build({
    KeyStore? store,
    Duration timeout = const Duration(seconds: 2),
    Duration pairing = const Duration(seconds: 2),
    Duration ack = const Duration(milliseconds: 200),
    Duration gate = const Duration(milliseconds: 40),
    Future<AdbKey> Function()? makeKey,
  }) =>
      FireTvDriver(device, store ?? keys, tv.make,
          makeKey: makeKey ??
              () async {
                keysMade++;
                return testKey;
              },
          connectTimeout: timeout,
          pairingTimeout: pairing,
          ackTimeout: ack,
          keyGate: gate);

  setUp(() async {
    tv = FakeAdbDevice();
    keys = MemoryKeyStore();
    await keys.write('adb-key', testKey.serialize()); // most tests start with a key
    keysMade = 0;
  });

  group('handshake', () {
    test('trusted_device_connects_without_a_prompt', () async {
      final d = build();
      final states = <TvConnectionState>[];
      d.state.listen(states.add);
      await d.connect();
      await Future<void>.delayed(Duration.zero);
      expect(states.map((s) => s.runtimeType), [Connecting, Connected]);
      final first = tv.transports.first.sent.first;
      expect(first.command, AdbCommand.cnxn);
      expect(first.arg0, adbVersion);
      expect(tv.transports.first.host, '10.0.0.8');
      expect(tv.transports.first.port, 5555);
    });

    test('known_key_answers_the_challenge_with_a_signature', () async {
      tv
        ..mode = AdbMode.knownKey
        ..trustedKey = testKey;
      final d = build();
      final states = <TvConnectionState>[];
      d.state.listen(states.add);
      await d.connect();
      expect(states.any((s) => s is AwaitingPairing), isFalse);
      expect(tv.publicKeysSeen, isEmpty);
    });

    test('unknown_key_sends_the_public_key_then_waits_for_allow', () async {
      tv
        ..mode = AdbMode.unknownKey
        ..holdAllow = true;
      final d = build();
      final states = <TvConnectionState>[];
      d.state.listen(states.add);
      final connecting = d.connect();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(states.map((s) => s.runtimeType), [Connecting, AwaitingPairing]);
      expect(tv.publicKeysSeen.single, adbPublicKeyPayload(testKey));
      tv.accept();
      await connecting;
      await Future<void>.delayed(Duration.zero);
      expect(states.last, isA<Connected>());
    });

    test('declining_the_prompt_is_PairingDenied', () async {
      tv
        ..mode = AdbMode.unknownKey
        ..denyPrompt = true;
      await expectLater(build().connect(), throwsA(isA<PairingDenied>()));
    });

    test('a_device_that_rejects_the_key_again_is_PairingDenied', () async {
      tv
        ..mode = AdbMode.unknownKey
        ..rejectAfterPubkey = true;
      await expectLater(build().connect(), throwsA(isA<PairingDenied>()));
    });

    test('an_unanswered_prompt_times_out_as_PairingDenied', () async {
      tv
        ..mode = AdbMode.unknownKey
        ..holdAllow = true;
      await expectLater(build(pairing: const Duration(milliseconds: 100)).connect(),
          throwsA(isA<PairingDenied>()));
    });

    test('adb_switched_off_explains_how_to_turn_it_on', () async {
      tv.openFails = true;
      await expectLater(
          build().connect(),
          throwsA(isA<TvConnectionError>()
              .having((e) => e.message, 'message', contains('ADB debugging'))));
    });

    test('a_device_that_never_answers_is_a_connection_error_in_time', () async {
      tv.mode = AdbMode.silent;
      await expectLater(
          build(timeout: const Duration(milliseconds: 100)).connect().timeout(const Duration(seconds: 1)),
          throwsA(isA<TvConnectionError>()));
    });

    test('socket_close_mid_handshake_fails_connect_and_the_driver_recovers', () async {
      tv.mode = AdbMode.silent;
      final d = build();
      final pending = expectLater(d.connect(), throwsA(isA<TvConnectionError>()));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      tv.transports.first.closeFromRemote();
      await pending.timeout(const Duration(seconds: 1));
      tv.mode = AdbMode.trusted;
      await d.connect().timeout(const Duration(seconds: 1));
    });

    test('corrupt_frames_during_the_handshake_are_a_connection_error', () async {
      tv.mode = AdbMode.silent;
      final d = build();
      final pending = expectLater(d.connect(), throwsA(isA<TvConnectionError>()));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      tv.transports.first.push(Uint8List(24)..fillRange(0, 24, 7));
      await pending.timeout(const Duration(seconds: 1));
    });

    test('disposing_during_the_prompt_ends_connect', () async {
      tv
        ..mode = AdbMode.unknownKey
        ..holdAllow = true;
      final d = build();
      final pending = expectLater(d.connect(), throwsA(isA<TvConnectionError>()));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await d.dispose();
      await pending.timeout(const Duration(seconds: 1));
    });

    test('disposing_while_the_socket_is_opening_closes_it_and_ends_connect', () async {
      tv.openDelay = const Duration(milliseconds: 100);
      final d = build();
      final pending = expectLater(d.connect(), throwsA(isA<TvConnectionError>()));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await d.dispose();
      await pending.timeout(const Duration(seconds: 1));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(tv.transports.every((t) => !t.isOpen), isTrue);
    });

    test('disposing_while_the_key_is_being_made_opens_no_socket', () async {
      await keys.delete('adb-key');
      final gate = Future<AdbKey>.delayed(const Duration(milliseconds: 150), () => testKey);
      final d = build(makeKey: () => gate);
      final pending = expectLater(d.connect(), throwsA(isA<TvConnectionError>()));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await d.dispose();
      await pending.timeout(const Duration(seconds: 1));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(tv.transports, isEmpty);
    });

    test('unexpected_exception_becomes_connection_error', () async {
      final d = FireTvDriver(device, keys, () => throw StateError('boom'), makeKey: () async => testKey);
      final states = <TvConnectionState>[];
      d.state.listen(states.add);
      await expectLater(d.connect(), throwsA(isA<TvConnectionError>()));
      await Future<void>.delayed(Duration.zero);
      expect(states.last, isA<Failed>());
    });
  });

  group('the app key', () {
    test('is_made_once_stored_and_reused', () async {
      await keys.delete('adb-key');
      final d = build();
      await d.connect();
      expect(keysMade, 1);
      expect(AdbKey.parse((await keys.read('adb-key'))!)?.n, testKey.n);
      await build().connect();
      expect(keysMade, 1, reason: 'the stored key is reused');
    });

    test('storage_failures_are_tolerated_and_the_key_is_kept_in_memory', () async {
      final d = build(store: ThrowingKeyStore());
      await d.connect();
      tv.transports.first.closeFromRemote();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await d.sendKey(TvKey.volumeUp);
      expect(keysMade, 1);
      expect(tv.transports.length, 2);
    });

    test('a_corrupt_stored_key_is_replaced', () async {
      await keys.write('adb-key', 'garbage');
      await build().connect();
      expect(keysMade, 1);
    });
  });

  group('keys', () {
    test('send_the_android_keycodes', () async {
      final d = build();
      await d.connect();
      await d.sendKey(TvKey.volumeUp);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await d.sendKey(TvKey.ok);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await d.sendKey(TvKey.power);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(tv.commands, ['input keyevent 24', 'input keyevent 23', 'input keyevent 26']);
    });

    test('unsupported_keys_are_reported_not_sent', () async {
      final d = build();
      await d.connect();
      expect(d.capabilities.supports(TvKey.input), isFalse);
      expect(d.capabilities.supports(TvKey.channelUp), isFalse);
      expect(d.capabilities.supports(TvKey.play), isTrue);
      await expectLater(d.sendKey(TvKey.input), throwsA(isA<TvConnectionError>()));
      expect(tv.commands, isEmpty);
    });

    test('only_one_key_command_is_in_flight_so_held_keys_cannot_pile_up', () async {
      tv.neverClose = true;
      final d = build(gate: const Duration(milliseconds: 500));
      await d.connect();
      await d.sendKey(TvKey.volumeUp);
      await d.sendKey(TvKey.volumeUp);
      await d.sendKey(TvKey.volumeUp);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(tv.commands, ['input keyevent 24']);
    });

    test('the_next_key_goes_through_once_the_previous_command_finished', () async {
      final d = build();
      await d.connect();
      await d.sendKey(TvKey.volumeUp);
      await Future<void>.delayed(const Duration(milliseconds: 50)); // device closes the stream
      await d.sendKey(TvKey.volumeUp);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(tv.commands, hasLength(2));
    });

    test('stream_output_and_closing_are_answered', () async {
      tv.output = true;
      final d = build();
      await d.connect();
      await d.sendKey(TvKey.up);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(tv.okaysFromClient, 1, reason: 'WRTE must be acknowledged');
      expect(tv.closesFromClient, 1, reason: 'CLSE must be answered with CLSE');
    });

    test('a_missing_ack_means_a_dead_connection_and_the_next_press_reconnects', () async {
      final d = build(ack: const Duration(milliseconds: 100));
      final states = <TvConnectionState>[];
      d.state.listen(states.add);
      await d.connect();
      tv
        ..neverAckOpen = true
        ..neverClose = true; // a completely silent device
      await d.sendKey(TvKey.volumeUp);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(states.last, isA<Disconnected>());
      tv
        ..neverAckOpen = false
        ..neverClose = false;
      await d.sendKey(TvKey.volumeUp);
      expect(tv.transports.length, 2);
    });

    test('closed_socket_reports_disconnected_and_the_next_press_reconnects', () async {
      final d = build();
      final states = <TvConnectionState>[];
      d.state.listen(states.add);
      await d.connect();
      tv.transports.first.closeFromRemote();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(states.last, isA<Disconnected>());
      await d.sendKey(TvKey.volumeDown);
      expect(tv.transports.length, 2);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(tv.commands, ['input keyevent 25']);
    });

    test('concurrent_presses_while_reconnecting_send_once', () async {
      final d = build();
      await d.connect();
      tv.transports.first.closeFromRemote();
      await Future<void>.delayed(Duration.zero);
      await Future.wait(List.generate(10, (_) => d.sendKey(TvKey.volumeUp)));
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(tv.commands.where((c) => c == 'input keyevent 24'), hasLength(1));
    });

    test('corrupt_frames_after_connecting_drop_the_connection', () async {
      final d = build();
      final states = <TvConnectionState>[];
      d.state.listen(states.add);
      await d.connect();
      tv.transports.first.push(Uint8List(24)..fillRange(0, 24, 9));
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(states.last, isA<Disconnected>());
    });
  });

  group('typing', () {
    test('text_is_sent_with_input_text', () async {
      final d = build();
      await d.connect();
      await d.sendText('hello world');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(tv.commands, ["input text 'hello%sworld'"]);
    });

    test('long_text_is_sent_in_pieces', () async {
      final d = build();
      await d.connect();
      await d.sendText('a' * 250);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(tv.commands.length, 3);
      expect(tv.commands.join().replaceAll(RegExp('[^a]'), '').length, 250);
    });

    test('untypeable_text_sends_nothing', () async {
      final d = build();
      await d.connect();
      await d.sendText('é€');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(tv.commands, isEmpty);
    });

    test('backspace_and_enter_use_keycodes', () async {
      final d = build();
      await d.connect();
      await d.deleteText(3);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await d.sendEnter();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(tv.commands, ['input keyevent 67 67 67', 'input keyevent 66']);
    });

    test('capabilities_allow_typing_but_the_tv_does_not_announce_text_fields', () {
      final d = build();
      expect(d.capabilities.typing, isTrue);
      expect(d.capabilities.announcesKeyboard, isFalse);
      expect(d.capabilities.pairingChoice, isFalse);
    });

    test('keyboard_focus_never_fires', () async {
      final events = <bool>[];
      build().keyboardFocus.listen(events.add);
      expect(events, isEmpty);
    });
  });

  test('submitting_a_pin_is_ignored_and_the_mac_is_unknown', () async {
    final d = build();
    await d.submitPairingPin('1234');
    expect(await d.fetchMacAddress(), isNull);
  });
}
