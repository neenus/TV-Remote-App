import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/core/tv_device.dart';
import 'package:tv_remote/core/tv_driver.dart';
import 'package:tv_remote/core/tv_key.dart';
import 'package:tv_remote/drivers/roku/roku_driver.dart';

import '../../support/fake_roku_http.dart';

const device = TvDevice(id: 'r-1', name: 'Roku', brand: TvBrand.roku, host: '10.0.0.6');

void main() {
  late FakeRokuHttp http;
  setUp(() => http = FakeRokuHttp());

  RokuDriver build() => RokuDriver(device, http, connectTimeout: const Duration(seconds: 2));

  group('connecting', () {
    test('reads_device_info_on_port_8060_and_is_connected', () async {
      final d = build();
      final states = <TvConnectionState>[];
      d.state.listen(states.add);
      await d.connect();
      await Future<void>.delayed(Duration.zero);
      expect(states.map((s) => s.runtimeType), [Connecting, Connected]);
      expect(http.requests.single.uri.toString(), 'http://10.0.0.6:8060/query/device-info');
    });

    test('the_mac_comes_from_the_device_info', () async {
      final d = build();
      await d.connect();
      expect(await d.fetchMacAddress(), 'B0:A7:37:12:34:56');
    });

    test('unreachable_roku_is_a_connection_error', () async {
      http.failAll = true;
      final d = build();
      final states = <TvConnectionState>[];
      d.state.listen(states.add);
      await expectLater(d.connect(), throwsA(isA<TvConnectionError>()));
      await Future<void>.delayed(Duration.zero);
      expect(states.last, isA<Failed>());
    });

    test('control_by_mobile_apps_blocked_explains_the_setting', () async {
      http.infoStatus = 403;
      await expectLater(
          build().connect(),
          throwsA(isA<TvConnectionError>()
              .having((e) => e.message, 'message', contains('Control by mobile apps'))));
    });

    test('a_reply_that_is_not_device_info_is_an_error', () async {
      http.infoBody = '<html>router login</html>';
      await expectLater(build().connect(), throwsA(isA<TvConnectionError>()));
    });

    test('unexpected_exceptions_become_connection_errors', () async {
      http.throwOther = true;
      await expectLater(build().connect(), throwsA(isA<TvConnectionError>()));
    });

    test('disposing_during_connect_ends_it', () async {
      http.infoDelay = const Duration(milliseconds: 100);
      final d = build();
      final pending = expectLater(d.connect(), throwsA(isA<TvConnectionError>()));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await d.dispose();
      await pending.timeout(const Duration(seconds: 1));
    });

    test('there_is_no_pairing_and_the_pin_is_ignored', () async {
      final d = build();
      await d.submitPairingPin('1234');
      await d.connect(pinPairing: true);
      expect(d.capabilities.pairingChoice, isFalse);
    });
  });

  group('keys', () {
    test('send_the_ecp_key_names', () async {
      final d = build();
      await d.connect();
      await d.sendKey(TvKey.volumeUp);
      await d.sendKey(TvKey.ok);
      await d.sendKey(TvKey.pause);
      expect(http.keys, ['VolumeUp', 'Select', 'Play']);
      final post = http.requests.firstWhere((r) => r.method == 'POST');
      expect(post.uri.port, 8060);
      expect(post.body, anyOf(isNull, isEmpty));
    });

    test('input_is_not_available', () async {
      final d = build();
      expect(d.capabilities.supports(TvKey.input), isFalse);
      expect(d.capabilities.supports(TvKey.power), isTrue);
      await expectLater(d.sendKey(TvKey.input), throwsA(isA<TvConnectionError>()));
      expect(http.keys, isEmpty);
    });

    test('a_forbidden_key_press_explains_the_setting', () async {
      final d = build();
      await d.connect();
      http.keypressStatus = 403;
      await expectLater(
          d.sendKey(TvKey.up),
          throwsA(isA<TvConnectionError>()
              .having((e) => e.message, 'message', contains('Control by mobile apps'))));
    });

    test('a_network_failure_reports_disconnected_and_the_next_press_recovers', () async {
      final d = build();
      final states = <TvConnectionState>[];
      d.state.listen(states.add);
      await d.connect();
      http.failKeypress = true;
      await expectLater(d.sendKey(TvKey.up), throwsA(isA<TvConnectionError>()));
      await Future<void>.delayed(Duration.zero);
      expect(states.last, isA<Disconnected>());
      http.failKeypress = false;
      await d.sendKey(TvKey.up);
      await Future<void>.delayed(Duration.zero);
      expect(states.last, isA<Connected>());
    });

    test('pressing_a_key_before_connecting_just_works', () async {
      final d = build();
      await d.sendKey(TvKey.home);
      expect(http.keys, ['Home']);
    });

    test('after_dispose_keys_fail_cleanly', () async {
      final d = build();
      await d.dispose();
      await expectLater(d.sendKey(TvKey.home), throwsA(isA<TvConnectionError>()));
    });
  });

  group('typing', () {
    test('characters_are_sent_one_by_one_in_order', () async {
      http.firstKeypressDelay = const Duration(milliseconds: 40); // the first would finish last if not serialised
      final d = build();
      await d.sendText('hi!');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(http.keys, ['Lit_h', 'Lit_i', 'Lit_!']);
    });

    test('backspace_and_enter', () async {
      final d = build();
      await d.deleteText(2);
      await d.sendEnter();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(http.keys, ['Backspace', 'Backspace', 'Enter']);
    });

    test('text_and_deletes_keep_their_order', () async {
      http.firstKeypressDelay = const Duration(milliseconds: 40);
      final d = build();
      await d.sendText('ab');
      await d.deleteText(1);
      await d.sendText('c');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(http.keys, ['Lit_a', 'Lit_b', 'Backspace', 'Lit_c']);
    });

    test('a_failed_character_does_not_stop_later_typing', () async {
      final d = build();
      http.failKeypress = true;
      await expectLater(d.sendText('a'), throwsA(isA<TvConnectionError>()));
      http.failKeypress = false;
      await d.sendText('b');
      expect(http.keys, ['Lit_a', 'Lit_b'], reason: 'the failed one was attempted, then typing carried on');
    });

    test('capabilities_allow_typing_but_roku_does_not_announce_text_fields', () {
      final c = build().capabilities;
      expect(c.typing, isTrue);
      expect(c.announcesKeyboard, isFalse);
    });

    test('keyboard_focus_never_fires', () async {
      final events = <bool>[];
      build().keyboardFocus.listen(events.add);
      expect(events, isEmpty);
    });
  });
}
