import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/core/tv_key.dart';
import 'package:tv_remote/drivers/samsung/samsung_protocol.dart';

void main() {
  group('samsungUrl', () {
    test('secure_url_has_port_8002_name_and_token', () {
      final u = samsungUrl('10.0.0.9', secure: true, token: 'abc');
      expect(u.scheme, 'wss');
      expect(u.host, '10.0.0.9');
      expect(u.port, 8002);
      expect(u.path, '/api/v2/channels/samsung.remote.control');
      expect(u.queryParameters['name'], base64Encode(utf8.encode('TV Remote')));
      expect(u.queryParameters['token'], 'abc');
    });

    test('secure_url_without_token_omits_it', () {
      final u = samsungUrl('10.0.0.9', secure: true);
      expect(u.queryParameters.containsKey('token'), isFalse);
    });

    test('plain_url_uses_ws_8001_and_never_a_token', () {
      final u = samsungUrl('10.0.0.9', secure: false, token: 'abc');
      expect(u.scheme, 'ws');
      expect(u.port, 8001);
      expect(u.queryParameters.containsKey('token'), isFalse);
    });
  });

  group('keys', () {
    test('key_message_shape', () {
      final m = jsonDecode(samsungKeyMessage('KEY_VOLUP')) as Map;
      expect(m['method'], 'ms.remote.control');
      final p = m['params'] as Map;
      expect(p['Cmd'], 'Click');
      expect(p['DataOfCmd'], 'KEY_VOLUP');
      expect(p['Option'], 'false');
      expect(p['TypeOfRemote'], 'SendRemoteKey');
    });

    test('every_tv_key_is_mapped', () {
      for (final k in TvKey.values) {
        expect(SamsungKeyMap.key(k), isNotNull, reason: '$k unmapped');
      }
    });

    test('spot_checks', () {
      expect(SamsungKeyMap.key(TvKey.ok), 'KEY_ENTER');
      expect(SamsungKeyMap.key(TvKey.back), 'KEY_RETURN');
      expect(SamsungKeyMap.key(TvKey.power), 'KEY_POWER');
      expect(SamsungKeyMap.key(TvKey.fastForward), 'KEY_FF');
      expect(SamsungKeyMap.key(TvKey.channelUp), 'KEY_CHUP');
      expect(SamsungKeyMap.key(TvKey.mute), 'KEY_MUTE');
      expect(SamsungKeyMap.key(TvKey.volumeDown), 'KEY_VOLDOWN');
    });
  });

  group('parseSamsungInbound', () {
    test('connect_with_token', () {
      final r = parseSamsungInbound(
          '{"event":"ms.channel.connect","data":{"token":"12345678"}}');
      expect(r, isA<SamsungConnected>());
      expect((r as SamsungConnected).token, '12345678');
    });

    test('connect_with_numeric_token', () {
      final r = parseSamsungInbound(
          '{"event":"ms.channel.connect","data":{"token":12345678}}');
      expect((r as SamsungConnected).token, '12345678');
    });

    test('connect_without_token', () {
      final r = parseSamsungInbound('{"event":"ms.channel.connect","data":{}}');
      expect((r as SamsungConnected).token, isNull);
    });

    test('unauthorized_and_timeout', () {
      expect(parseSamsungInbound('{"event":"ms.channel.unauthorized"}'),
          isA<SamsungUnauthorized>());
      expect(parseSamsungInbound('{"event":"ms.channel.timeOut"}'),
          isA<SamsungTimeout>());
    });

    test('garbage_and_unknown_events_return_null', () {
      expect(parseSamsungInbound('nope'), isNull);
      expect(parseSamsungInbound('[1]'), isNull);
      expect(parseSamsungInbound('{"event":"ms.channel.clientConnect"}'), isNull);
      expect(parseSamsungInbound('{"event":42}'), isNull);
    });
  });

  group('macFromSamsungDeviceInfo', () {
    test('reads_and_normalizes_wifi_mac', () {
      expect(
          macFromSamsungDeviceInfo({
            'device': {'wifiMac': 'aa-bb-cc-dd-ee-ff'}
          }),
          'AA:BB:CC:DD:EE:FF');
    });

    test('returns_null_for_missing_or_invalid', () {
      expect(macFromSamsungDeviceInfo({}), isNull);
      expect(macFromSamsungDeviceInfo({'device': 'x'}), isNull);
      expect(macFromSamsungDeviceInfo({'device': {'wifiMac': 'nope'}}), isNull);
      expect(macFromSamsungDeviceInfo({'device': {'wifiMac': 5}}), isNull);
    });
  });
}
