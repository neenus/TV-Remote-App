import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/drivers/fire_tv/adb_auth.dart';

import '../../support/adb_goldens.dart';

Uint8List unhex(String s) => Uint8List.fromList(
    [for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)]);
String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

final key = AdbKey(BigInt.parse(adbKeyN, radix: 16), BigInt.parse(adbKeyD, radix: 16));

void main() {
  test('signs_tokens_exactly_like_the_reference', () {
    for (final (token, sig) in adbSignatureVectors) {
      expect(hex(adbSignToken(key, unhex(token))), sig);
    }
  });

  test('public_key_struct_matches_the_reference', () {
    expect(hex(adbPublicKeyStruct(key)), adbPubkeyStructHex);
    expect(adbPublicKeyStruct(key), hasLength(524));
  });

  test('public_key_payload_matches_the_reference', () {
    final payload = adbPublicKeyPayload(key, userInfo: ' tester@host');
    expect(hex(payload), adbPubkeyPayloadHex);
    expect(payload.last, 0);
    expect(base64.decode(utf8.decode(payload.sublist(0, payload.length - 1 - ' tester@host'.length))),
        hasLength(524));
  });

  test('signing_rejects_tokens_of_the_wrong_size', () {
    expect(() => adbSignToken(key, [1, 2, 3]), throwsArgumentError);
  });

  group('storing a key', () {
    test('round_trips', () {
      final back = AdbKey.parse(key.serialize());
      expect(back?.n, key.n);
      expect(back?.d, key.d);
    });

    test('rejects_keys_that_cannot_work', () {
      expect(AdbKey.parse(key.serialize()), isNotNull);
      expect(AdbKey.parse(AdbKey(key.n - BigInt.one, key.d).serialize()), isNull,
          reason: 'even modulus');
      expect(AdbKey.parse(AdbKey(key.n, key.d + BigInt.two).serialize()), isNull,
          reason: 'private exponent does not match');
    });

    test('rejects_garbage', () {
      for (final s in ['', 'x', 'zz:11', 'ab', 'ab:', ':ab', 'ab:cd:ef']) {
        expect(AdbKey.parse(s), isNull, reason: s);
      }
    });
  });

  test('a_generated_key_is_a_valid_2048_bit_key_that_signs_correctly', () {
    final k = generateAdbKeySync();
    expect(k.n.bitLength, 2048);
    expect(k.e, BigInt.from(65537));
    // sig^e mod n must give back the padded digest block
    final token = Uint8List.fromList(List.generate(20, (i) => i * 3));
    final sig = BigInt.parse(hex(adbSignToken(k, token)), radix: 16);
    final em = sig.modPow(k.e, k.n).toRadixString(16).padLeft(512, '0');
    expect(em.startsWith('0001ffff'), isTrue);
    expect(em.endsWith(hex(token)), isTrue);
    expect(adbPublicKeyStruct(k), hasLength(524));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
