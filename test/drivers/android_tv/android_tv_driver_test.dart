@Timeout(Duration(minutes: 3))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/core/key_store.dart';
import 'package:tv_remote/core/tv_device.dart';
import 'package:tv_remote/core/tv_driver.dart';
import 'package:tv_remote/core/tv_key.dart';
import 'package:tv_remote/drivers/android_tv/android_tv_driver.dart';
import 'package:tv_remote/drivers/android_tv/atv_crypto.dart';
import 'package:tv_remote/drivers/android_tv/atv_protobuf.dart';

import '../../support/atv_goldens.dart';
import '../../support/fake_atv_tv.dart';

const device = TvDevice(id: 'a-1', name: 'Android TV', brand: TvBrand.androidTv, host: '10.0.0.9');

class ThrowingKeyStore implements KeyStore {
  @override
  Future<String?> read(String deviceId) async => throw Exception('keystore');
  @override
  Future<void> write(String deviceId, String key) async => throw Exception('keystore');
  @override
  Future<void> delete(String deviceId) async => throw Exception('keystore');
}

void main() {
  late AtvIdentity identity;
  late FakeAtvTv tv;
  late MemoryKeyStore keys;
  var identitiesMade = 0;

  setUpAll(() => identity = generateAtvIdentitySync());

  AndroidTvDriver build({
    KeyStore? store,
    Duration timeout = const Duration(seconds: 2),
    Duration pairing = const Duration(seconds: 2),
    Duration idle = const Duration(seconds: 2),
    Future<AtvIdentity> Function()? makeIdentity,
  }) =>
      AndroidTvDriver(device, store ?? keys, tv.make,
          makeIdentity: makeIdentity ??
              () async {
                identitiesMade++;
                return identity;
              },
          connectTimeout: timeout,
          stepTimeout: timeout,
          pairingTimeout: pairing,
          idleTimeout: idle);

  Future<void> markPaired() async {
    await keys.write('atv-identity', identity.serialize());
    await keys.write('a-1', 'paired');
  }

  setUp(() {
    tv = FakeAtvTv();
    keys = MemoryKeyStore();
    identitiesMade = 0;
  });

  group('pairing', () {
    test('shows_a_code_prompt_then_connects_and_remembers_the_pairing', () async {
      final d = build();
      final states = <TvConnectionState>[];
      d.state.listen(states.add);
      final connecting = d.connect();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(states.map((s) => s.runtimeType), [Connecting, AwaitingPin]);
      await d.submitPairingPin(tv.codeFor(identity));
      await connecting;
      await Future<void>.delayed(Duration.zero);
      expect(states.map((s) => s.runtimeType), [Connecting, AwaitingPin, Connecting, Connected]);
      expect(await keys.read('a-1'), 'paired');
      expect(AtvIdentity.parse((await keys.read('atv-identity'))!), isNotNull);
      expect(tv.pairingChannels, hasLength(1));
      expect(tv.pairingChannels.single.isOpen, isFalse, reason: 'the pairing connection is closed afterwards');
      expect(tv.controlChannels, hasLength(1));
    });

    test('a_lowercase_code_with_spaces_works', () async {
      final d = build();
      final connecting = d.connect();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await d.submitPairingPin(' ${tv.codeFor(identity).toLowerCase()} ');
      await connecting;
    });

    test('a_wrong_code_is_rejected_by_its_checksum_without_sending_a_secret', () async {
      final d = build();
      final pending = expectLater(d.connect(),
          throwsA(isA<PairingDenied>().having((e) => e.message, 'message', contains('not accepted'))));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final good = tv.codeFor(identity);
      final bad = '${((int.parse(good.substring(0, 2), radix: 16) + 1) % 256).toRadixString(16).padLeft(2, '0')}${good.substring(2)}';
      await d.submitPairingPin(bad);
      await pending;
      expect(tv.pairingChannels.single.received.any((m) => m.length > 6 && m[5] == 0xC2), isFalse);
      expect(tv.pairingChannels.single.isOpen, isFalse);
      expect(await keys.read('a-1'), isNull);
    });

    test('a_malformed_code_is_rejected', () async {
      final d = build();
      final pending = expectLater(d.connect(), throwsA(isA<PairingDenied>()));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await d.submitPairingPin('12');
      await pending;
    });

    test('a_secret_the_tv_refuses_is_PairingDenied', () async {
      tv.rejectSecret = true;
      final d = build();
      final pending = expectLater(d.connect(), throwsA(isA<PairingDenied>()));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await d.submitPairingPin(tv.codeFor(identity));
      await pending;
      expect(await keys.read('a-1'), isNull);
    });

    test('a_secret_the_tv_never_acknowledges_times_out', () async {
      tv.ignoreSecret = true;
      final d = build(timeout: const Duration(milliseconds: 150));
      final pending = expectLater(d.connect(), throwsA(isA<TvConnectionError>()));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await d.submitPairingPin(tv.codeFor(identity));
      await pending;
    });

    test('an_unanswered_prompt_times_out_as_PairingDenied_and_closes_the_connection', () async {
      final d = build(pairing: const Duration(milliseconds: 150));
      await expectLater(d.connect(), throwsA(isA<PairingDenied>()));
      expect(tv.pairingChannels.single.isOpen, isFalse);
    });

    test('a_tv_that_does_not_answer_the_pairing_request_is_a_connection_error', () async {
      tv.silentPairing = true;
      await expectLater(build(timeout: const Duration(milliseconds: 100)).connect(),
          throwsA(isA<TvConnectionError>()));
    });

    test('corrupt_frames_during_pairing_are_a_connection_error', () async {
      tv.garbagePairing = true;
      await expectLater(build().connect(), throwsA(isA<TvConnectionError>()));
    });

    test('an_unreachable_pairing_port_is_a_connection_error', () async {
      tv.pairOpenFails = true;
      await expectLater(build().connect(), throwsA(isA<TvConnectionError>()));
    });

    test('disposing_during_the_prompt_ends_connect_and_closes_the_connection', () async {
      final d = build();
      final pending = expectLater(d.connect(), throwsA(isA<TvConnectionError>()));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await d.dispose();
      await pending.timeout(const Duration(seconds: 1));
      expect(tv.pairingChannels.single.isOpen, isFalse);
    });

    test('disposing_while_the_socket_is_opening_closes_it', () async {
      tv.openDelay = const Duration(milliseconds: 100);
      final d = build();
      final pending = expectLater(d.connect(), throwsA(isA<TvConnectionError>()));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await d.dispose();
      await pending.timeout(const Duration(seconds: 1));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(tv.channels.every((c) => !c.isOpen), isTrue);
    });

    test('submitting_a_code_when_not_asked_is_ignored', () async {
      final d = build();
      await d.submitPairingPin('ABCDEF');
    });
  });

  group('the app identity (certificate and key)', () {
    test('is_made_once_stored_and_reused', () async {
      final d = build();
      final connecting = d.connect();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await d.submitPairingPin(tv.codeFor(identity));
      await connecting;
      expect(identitiesMade, 1);
      await build().connect(); // paired now, same store
      expect(identitiesMade, 1);
    });

    test('survives_a_disposed_session_and_is_shared_between_drivers', () async {
      Future<AtvIdentity> slow() async {
        identitiesMade++;
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return identity;
      }

      final first = build(makeIdentity: slow);
      final aborted = first.connect().then<void>((_) {}, onError: (Object _) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await first.dispose();
      await aborted;
      final second = build(makeIdentity: slow);
      final connecting = second.connect();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await second.dispose();
      await connecting.then<void>((_) {}, onError: (Object _) {});
      expect(identitiesMade, 1);
      expect(await keys.read('atv-identity'), isNotNull);
    });

    test('with_broken_storage_drivers_still_share_one_identity', () async {
      final store = ThrowingKeyStore();
      for (var i = 0; i < 2; i++) {
        final d = build(store: store);
        final c = d.connect().then<void>((_) {}, onError: (Object _) {});
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await d.dispose();
        await c;
      }
      expect(identitiesMade, 1);
    });

    test('a_corrupt_stored_identity_is_replaced', () async {
      await keys.write('atv-identity', 'garbage');
      final d = build();
      final c = d.connect().then<void>((_) {}, onError: (Object _) {});
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await d.dispose();
      await c;
      expect(identitiesMade, 1);
    });
  });

  group('connecting to a paired TV', () {
    setUp(() async => markPaired());

    test('does_the_control_handshake_and_skips_pairing', () async {
      final d = build();
      final states = <TvConnectionState>[];
      d.state.listen(states.add);
      await d.connect();
      await Future<void>.delayed(Duration.zero);
      expect(states.map((s) => s.runtimeType), [Connecting, Connected]);
      expect(tv.pairingChannels, isEmpty);
      final received = tv.controlChannels.single.received;
      expect(received.any((m) => sameBytes(m, remoteConfigure(611))), isTrue);
      expect(received.any((m) => sameBytes(m, remoteSetActive(611))), isTrue);
    });

    test('an_unreachable_control_port_is_a_connection_error', () async {
      tv.controlOpenFails = true;
      await expectLater(build().connect(), throwsA(isA<TvConnectionError>()));
    });

    test('a_tv_that_hangs_up_during_the_handshake_suggests_pairing_again', () async {
      tv.closeControlBeforeStart = true;
      await expectLater(
          build().connect(),
          throwsA(isA<TvConnectionError>()
              .having((e) => e.message, 'message', contains('add it again'))));
    });

    test('an_error_message_during_the_handshake_fails_the_connection', () async {
      tv.errorInControl = true;
      await expectLater(build().connect(), throwsA(isA<TvConnectionError>()));
    });

    test('a_tv_that_never_starts_is_a_connection_error_in_time', () async {
      tv.noStart = true;
      await expectLater(build(timeout: const Duration(milliseconds: 150)).connect(),
          throwsA(isA<TvConnectionError>()));
    });

    test('unexpected_exceptions_become_connection_errors', () async {
      final d = AndroidTvDriver(device, keys, () => throw StateError('boom'),
          makeIdentity: () async => identity);
      final states = <TvConnectionState>[];
      d.state.listen(states.add);
      await expectLater(d.connect(), throwsA(isA<TvConnectionError>()));
      await Future<void>.delayed(Duration.zero);
      expect(states.last, isA<Failed>());
    });

    test('a_failing_pairing_flag_write_does_not_force_a_new_pairing', () async {
      final store = ThrowingKeyStore();
      // pair once with a store that can't write...
      final d = build(store: store);
      final c = d.connect();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await d.submitPairingPin(tv.codeFor(identity));
      await c;
      tv.controlChannels.first.closeFromRemote();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await d.sendKey(TvKey.volumeUp); // ...it must reconnect without pairing again
      expect(tv.pairingChannels, hasLength(1));
      expect(tv.controlChannels, hasLength(2));
    });
  });

  group('control', () {
    setUp(() async => markPaired());

    test('keys_are_sent_framed_with_android_key_codes', () async {
      final d = build();
      await d.connect();
      await d.sendKey(TvKey.volumeUp);
      await d.sendKey(TvKey.home);
      await d.sendKey(TvKey.input);
      await d.sendKey(TvKey.mute);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(tv.keyMessages.map((m) => m.toList()), [
        remoteKeyInject(24).toList(),
        remoteKeyInject(3).toList(),
        remoteKeyInject(178).toList(),
        remoteKeyInject(164).toList(),
      ]);
    });

    test('every_button_is_available', () {
      final c = build().capabilities;
      for (final k in TvKey.values) {
        expect(c.supports(k), isTrue, reason: '$k');
      }
    });

    test('pings_are_answered_with_the_same_value', () async {
      final d = build();
      await d.connect();
      final channel = tv.controlChannels.single;
      channel.push(unhex(atvRecv_ping_request));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(channel.received.last.toList(), remotePingResponse(1234).toList());
    });

    test('closed_socket_reports_disconnected_and_the_next_press_reconnects', () async {
      final d = build();
      final states = <TvConnectionState>[];
      d.state.listen(states.add);
      await d.connect();
      tv.controlChannels.first.closeFromRemote();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(states.last, isA<Disconnected>());
      await d.sendKey(TvKey.volumeDown);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(tv.controlChannels, hasLength(2));
      expect(tv.keyMessages.last.toList(), remoteKeyInject(25).toList());
    });

    test('presses_during_the_handshake_are_not_sent_early_and_extra_ones_are_dropped', () async {
      final d = build();
      final states = <TvConnectionState>[];
      d.state.listen(states.add);
      await d.connect();
      tv.controlChannels.first.closeFromRemote();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final a = d.sendKey(TvKey.up);
      await Future<void>.delayed(const Duration(milliseconds: 3));
      final b = d.sendKey(TvKey.down);
      await Future.wait([a, b]);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final second = tv.controlChannels.last.received;
      final firstKey = second.indexWhere((m) => m.isNotEmpty && m[0] == 0x52);
      final start = second.indexWhere((m) => sameBytes(m, remoteSetActive(611)));
      expect(firstKey, greaterThan(start), reason: 'no key before the handshake finished');
      expect(tv.keyMessages.where((m) => sameBytes(m, remoteKeyInject(19))), hasLength(1));
      expect(tv.keyMessages.where((m) => sameBytes(m, remoteKeyInject(20))), isEmpty);
      expect(states.last, isA<Connected>());
    });

    test('ten_concurrent_presses_while_reconnecting_send_once', () async {
      final d = build();
      await d.connect();
      tv.controlChannels.first.closeFromRemote();
      await Future<void>.delayed(Duration.zero);
      await Future.wait(List.generate(10, (_) => d.sendKey(TvKey.volumeUp)));
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(tv.keyMessages.where((m) => sameBytes(m, remoteKeyInject(24))), hasLength(1));
    });

    test('a_silent_connection_is_dropped_and_the_next_press_reconnects', () async {
      final d = build(idle: const Duration(milliseconds: 100));
      final states = <TvConnectionState>[];
      d.state.listen(states.add);
      await d.connect();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(states.last, isA<Disconnected>());
      await d.sendKey(TvKey.volumeUp);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(tv.controlChannels, hasLength(2));
    });

    test('pings_keep_the_connection_alive', () async {
      final d = build(idle: const Duration(milliseconds: 100));
      final states = <TvConnectionState>[];
      d.state.listen(states.add);
      await d.connect();
      for (var i = 0; i < 8; i++) {
        tv.controlChannels.single.push(unhex(atvRecv_ping_request));
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      expect(states.last, isA<Connected>());
      expect(tv.controlChannels, hasLength(1));
    });

    test('corrupt_frames_after_connecting_drop_the_connection', () async {
      final d = build();
      final states = <TvConnectionState>[];
      d.state.listen(states.add);
      await d.connect();
      tv.controlChannels.single.pushRaw([0xff, 0xff, 0xff, 0xff, 0xff, 0xff]);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(states.last, isA<Disconnected>());
    });

    test('unknown_messages_are_ignored', () async {
      final d = build();
      final states = <TvConnectionState>[];
      d.state.listen(states.add);
      await d.connect();
      tv.controlChannels.single.push(unhex(atvRecv_unhandled_ime));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(states.last, isA<Connected>());
    });

    test('typing_is_not_supported_but_does_not_crash', () async {
      final d = build();
      expect(d.capabilities.typing, isFalse);
      await expectLater(d.sendText('a'), throwsA(isA<TvConnectionError>()));
      await expectLater(d.deleteText(1), throwsA(isA<TvConnectionError>()));
      await expectLater(d.sendEnter(), throwsA(isA<TvConnectionError>()));
      final events = <bool>[];
      d.keyboardFocus.listen(events.add);
      expect(events, isEmpty);
    });

    test('the_code_is_six_hex_characters_and_the_mac_is_unknown', () async {
      final d = build();
      expect(d.capabilities.pinHex, isTrue);
      expect(d.capabilities.pairingChoice, isFalse);
      expect(await d.fetchMacAddress(), isNull);
    });
  });

  test('a_key_press_never_starts_pairing', () async {
    final d = build(); // never paired
    await expectLater(
        d.sendKey(TvKey.up),
        throwsA(isA<PairingDenied>().having((e) => e.message, 'message', contains('pair'))));
    expect(tv.channels, isEmpty);
  });

  test('forgetting_the_tv_removes_the_pairing_flag_so_it_pairs_again', () async {
    await markPaired();
    await keys.delete('a-1'); // what removing the TV in the list does
    final d = build();
    final connecting = d.connect();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(tv.pairingChannels, hasLength(1));
    await d.dispose();
    await connecting.then<void>((_) {}, onError: (Object _) {});
  });
}
