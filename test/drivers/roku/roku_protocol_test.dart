import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/core/tv_key.dart';
import 'package:tv_remote/drivers/roku/roku_protocol.dart';

import '../../support/fake_roku_http.dart';

void main() {
  group('keys', () {
    test('every_key_except_input_is_mapped', () {
      for (final k in TvKey.values.where((k) => k != TvKey.input)) {
        expect(RokuKeyMap.key(k), isNotNull, reason: '$k');
      }
      expect(RokuKeyMap.key(TvKey.input), isNull);
    });

    test('spot_checks', () {
      expect(RokuKeyMap.key(TvKey.ok), 'Select');
      expect(RokuKeyMap.key(TvKey.menu), 'Info');
      expect(RokuKeyMap.key(TvKey.mute), 'VolumeMute');
      expect(RokuKeyMap.key(TvKey.rewind), 'Rev');
      expect(RokuKeyMap.key(TvKey.fastForward), 'Fwd');
      expect(RokuKeyMap.key(TvKey.power), 'Power');
    });

    test('pause_sends_play_because_roku_has_one_toggle', () {
      expect(RokuKeyMap.key(TvKey.pause), 'Play');
      expect(RokuKeyMap.key(TvKey.play), 'Play');
    });
  });

  group('urls', () {
    test('keypress_url', () {
      expect(rokuKeypressUri('10.0.0.1', 'Home').toString(), 'http://10.0.0.1:8060/keypress/Home');
    });

    test('typed_characters_are_url_encoded', () {
      expect(rokuLiteralKey('a'), 'Lit_a');
      expect(rokuLiteralKey(' '), 'Lit_%20');
      expect(rokuLiteralKey('/'), 'Lit_%2F');
      expect(rokuLiteralKey('é'), 'Lit_%C3%A9');
      expect(rokuLiteralKey('%'), 'Lit_%25');
      expect(rokuLiteralKey('😀'), 'Lit_%F0%9F%98%80');
    });

    test('the_device_info_url', () {
      expect(rokuInfoUri('10.0.0.1').toString(), 'http://10.0.0.1:8060/query/device-info');
    });
  });

  group('device info', () {
    test('reads_name_model_and_the_mac_of_the_interface_in_use', () {
      final info = parseRokuDeviceInfo(rokuInfoXml);
      expect(info?.name, 'Living Room & Den');
      expect(info?.model, 'Roku Ultra');
      expect(info?.mac, 'B0:A7:37:12:34:56');
    });

    test('ethernet_tvs_use_the_ethernet_mac', () {
      final xml = rokuInfoXml.replaceFirst('<network-type>wifi', '<network-type>ethernet');
      expect(parseRokuDeviceInfo(xml)?.mac, 'B0:A7:37:12:34:57');
    });

    test('a_missing_network_type_still_finds_a_mac', () {
      final xml = rokuInfoXml.replaceFirst(RegExp('<network-type>.*</network-type>'), '');
      expect(parseRokuDeviceInfo(xml)?.mac, isNotNull);
    });

    test('invalid_macs_are_ignored', () {
      final xml = rokuInfoXml
          .replaceFirst('b0:a7:37:12:34:56', 'nope')
          .replaceFirst('b0:a7:37:12:34:57', '');
      expect(parseRokuDeviceInfo(xml)?.mac, isNull);
    });

    test('garbage_is_not_device_info', () {
      expect(parseRokuDeviceInfo(''), isNull);
      expect(parseRokuDeviceInfo('<html>nope</html>'), isNull);
    });
  });
}
