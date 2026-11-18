import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/drivers/android_tv/atv_protobuf.dart';

import '../../support/atv_goldens.dart';

Uint8List unhex(String s) => Uint8List.fromList(
    [for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)]);
String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('encoding matches the reference library', () {
    test('pairing_messages', () {
      expect(hex(poloPairingRequest('TV Remote')), atvSend_pairing_request);
      expect(hex(poloOptions()), atvSend_options);
      expect(hex(poloConfiguration()), atvSend_configuration);
      expect(hex(poloSecret(unhex(atvSecretBytes))), atvSecretMessage);
    });

    test('control_handshake_messages', () {
      expect(hex(remoteConfigure(611)), atvSend_remote_configure_611);
      expect(hex(remoteSetActive(611)), atvSend_remote_set_active_611);
      expect(hex(remotePingResponse(7)), atvSend_ping_response_7);
    });

    test('key_presses_including_codes_over_127', () {
      for (final v in atvKeyInjectVectors) {
        expect(hex(remoteKeyInject(v.code)), v.message, reason: '${v.code}');
        expect(hex(frameMessage(remoteKeyInject(v.code))), v.framed, reason: '${v.code}');
      }
    });
  });

  group('parsing what the TV sends', () {
    test('pairing_messages', () {
      expect(parsePolo(unhex(atvRecv_pairing_request_ack)), isA<PoloPairingRequestAck>());
      expect(parsePolo(unhex(atvRecv_options)), isA<PoloOptions>());
      expect(parsePolo(unhex(atvRecv_configuration_ack)), isA<PoloConfigurationAck>());
      expect(parsePolo(unhex(atvRecv_secret_ack)), isA<PoloSecretAck>());
    });

    test('error_statuses', () {
      final e = parsePolo(unhex(atvRecv_error));
      expect(e, isA<PoloError>());
      expect((e as PoloError).status, 400);
      expect((parsePolo(unhex(atvRecv_bad_secret)) as PoloError).status, 402);
    });

    test('control_messages', () {
      final cfg = parseRemote(unhex(atvRecv_remote_configure));
      expect(cfg, isA<RemoteConfigureIn>());
      expect((cfg as RemoteConfigureIn).features, 0x2FF);
      expect(cfg.vendor, 'Sony');
      expect(cfg.model, 'BRAVIA 4K');
      expect((parseRemote(unhex(atvRecv_remote_set_active)) as RemoteSetActiveIn).features, 0x2FF);
      expect((parseRemote(unhex(atvRecv_ping_request)) as RemotePingIn).value, 1234);
      expect((parseRemote(unhex(atvRecv_remote_start)) as RemoteStartIn).started, isTrue);
      expect(parseRemote(unhex(atvRecv_remote_error)), isA<RemoteErrorIn>());
    });

    test('messages_we_do_not_use_are_other_not_errors', () {
      expect(parseRemote(unhex(atvRecv_unhandled_ime)), isA<RemoteOther>());
      expect(parseRemote(Uint8List(0)), isA<RemoteOther>());
    });

    test('a_truncated_message_is_a_format_error', () {
      final raw = unhex(atvRecv_remote_configure);
      expect(() => parseRemote(raw.sublist(0, raw.length - 3)), throwsFormatException);
      expect(() => parsePolo(unhex('0a')), throwsFormatException);
    });
  });

  group('framing', () {
    List<Uint8List> feed(AtvFrameParser p, List<int> bytes) => p.add(bytes);

    test('splits_and_joins_messages', () {
      final a = frameMessage(unhex(atvRecv_remote_start));
      final b = frameMessage(unhex(atvRecv_ping_request));
      final out = feed(AtvFrameParser(), [...a, ...b]);
      expect(out.map(hex), [atvRecv_remote_start, atvRecv_ping_request]);
      final p = AtvFrameParser();
      final single = <Uint8List>[];
      for (final byte in [...a, ...b]) {
        single.addAll(p.add([byte]));
      }
      expect(single.map(hex), [atvRecv_remote_start, atvRecv_ping_request]);
    });

    test('a_long_message_with_a_multi_byte_length', () {
      final big = Uint8List.fromList(List.filled(300, 7));
      final framed = frameMessage(big);
      expect(framed.sublist(0, 2), [0xac, 0x02]); // 300 as a varint
      expect(AtvFrameParser().add(framed).single, big);
    });

    test('a_length_that_never_ends_or_is_huge_is_corrupt', () {
      expect(() => AtvFrameParser().add([0xff, 0xff, 0xff, 0xff, 0xff, 0xff]), throwsFormatException);
      expect(() => AtvFrameParser().add([0x80, 0x80, 0x80, 0x08]), throwsFormatException); // 128 MB
    });

    test('varints_round_trip', () {
      for (final v in [0, 1, 127, 128, 300, 16384]) {
        final bytes = encodeVarint(v);
        expect(AtvFrameParser().add([...bytes, ...List.filled(v, 1)]).single, hasLength(v), reason: '$v');
      }
    });
  });
}
