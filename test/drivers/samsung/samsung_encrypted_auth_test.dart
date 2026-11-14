import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/core/tv_driver.dart';
import 'package:tv_remote/drivers/samsung/samsung_encrypted_auth.dart';

import '../../support/fake_samsung_http.dart';
import '../../support/samsung_encrypted_goldens.dart';

final vector = exchangeVectors.first; // PIN 1234

FakeSamsungHttp tv() => FakeSamsungHttp()
  ..clientHello = vector.clientHello
  ..clientAck = vector.clientAck;

void main() {
  late FakeSamsungHttp http;
  late SamsungEncryptedAuth auth;
  setUp(() {
    http = tv();
    auth = SamsungEncryptedAuth('10.0.0.5', http);
  });

  group('start', () {
    test('shows_the_pin_page_when_it_is_not_running', () async {
      await auth.startPairing();
      final post = http.where('POST', '/ws/apps/CloudPINPage').single;
      expect(post.body, 'pin4');
      expect(post.uri.host, '10.0.0.5');
      expect(post.uri.port, 8080);
    });

    test('does_not_show_it_twice_when_it_is_already_up', () async {
      http.pinPageState = 'running';
      await auth.startPairing();
      expect(http.where('POST', '/ws/apps/CloudPINPage'), isEmpty);
    });

    test('unreachable_tv_is_a_connection_error', () async {
      http.failAll = true;
      await expectLater(auth.startPairing(), throwsA(isA<TvConnectionError>()));
    });

    test('a_missing_pin_page_points_to_the_other_samsung_options', () async {
      http.pageStatus = 404;
      await expectLater(
          auth.startPairing(),
          throwsA(isA<TvConnectionError>()
              .having((e) => e.message, 'message', contains('another Samsung option'))));
      expect(http.where('POST', '/ws/apps/CloudPINPage'), isEmpty);
    });

    test('a_pin_page_reply_without_a_state_is_not_trusted', () async {
      http.omitState = true;
      await expectLater(auth.startPairing(), throwsA(isA<TvConnectionError>()));
    });

    test('a_refused_pin_screen_request_is_an_error', () async {
      http.pagePostStatus = 500;
      await expectLater(auth.startPairing(), throwsA(isA<TvConnectionError>()));
    });
  });

  group('trying a PIN', () {
    test('right_pin_is_accepted_and_sends_the_expected_hello', () async {
      expect(await auth.tryPin('1234'), isTrue);
      final step0 = http.requests.firstWhere((r) => r.uri.queryParameters['step'] == '0');
      expect(step0.method, 'GET');
      expect(step0.uri.queryParameters['type'], '1');
      expect(step0.uri.queryParameters['app_id'], '12345');
      final step1 = http.requests.firstWhere((r) => r.uri.queryParameters['step'] == '1');
      expect(step1.method, 'POST');
      expect(jsonDecode(step1.body!), {
        'auth_Data': {'auth_type': 'SPC', 'GeneratorServerHello': vector.serverHello}
      });
    });

    test('wrong_pin_is_rejected', () async {
      expect(await auth.tryPin('4321'), isFalse);
    });

    test('a_reply_without_a_hello_means_not_accepted', () async {
      http.noClientHello = true;
      expect(await auth.tryPin('1234'), isFalse);
    });

    test('unreachable_tv_is_a_connection_error', () async {
      http.failAll = true;
      await expectLater(auth.tryPin('1234'), throwsA(isA<TvConnectionError>()));
    });

    test('an_http_error_on_the_pin_step_is_not_reported_as_a_wrong_code', () async {
      http.step1Status = 500;
      await expectLater(auth.tryPin('1234'), throwsA(isA<TvConnectionError>()));
    });
  });

  group('finishing', () {
    test('returns_credentials_and_closes_the_pin_page', () async {
      await auth.startPairing();
      await auth.tryPin('1234');
      final creds = await auth.finish();
      expect(creds.tokenHex, vector.ctx);
      expect(creds.sessionId, '1');
      expect(creds.serialize(), '${vector.ctx}:1');
      expect(http.where('DELETE', '/ws/apps/CloudPINPage/run'), hasLength(1));
      final step2 = http.requests.firstWhere((r) => r.uri.queryParameters['step'] == '2');
      expect(jsonDecode(step2.body!)['auth_Data']['ServerAckMsg'], vector.serverAck);
    });

    test('multi_digit_session_ids_are_kept_whole', () async {
      http.sessionId = '12';
      await auth.tryPin('1234');
      expect((await auth.finish()).sessionId, '12');
    });

    test('expired_pin_window_is_PairingDenied', () async {
      await auth.tryPin('1234');
      http.emptyAuthData = true;
      await expectLater(auth.finish(), throwsA(isA<PairingDenied>()));
    });

    test('a_bad_client_acknowledge_is_rejected', () async {
      await auth.tryPin('1234');
      http.clientAck = '0104${'0' * 40}';
      await expectLater(auth.finish(), throwsA(isA<TvConnectionError>()));
    });

    test('finishing_before_a_pin_was_accepted_is_a_pairing_error', () async {
      await expectLater(auth.finish(), throwsA(isA<PairingDenied>()));
    });
  });

  test('credentials_round_trip_and_reject_garbage', () {
    final c = EncryptedCredentials.parse('${vector.ctx}:7');
    expect((c?.tokenHex, c?.sessionId), (vector.ctx, '7'));
    expect(EncryptedCredentials.parse('nope'), isNull);
    expect(EncryptedCredentials.parse('zz:1'), isNull);
    expect(EncryptedCredentials.parse('${vector.ctx}:'), isNull);
  });

  test('closing_the_pin_page_is_best_effort', () async {
    http.failAll = true;
    await auth.closePinPage(); // must not throw
  });
}
