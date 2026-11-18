import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/drivers/samsung/samsung_encrypted_crypto.dart';

import '../../support/samsung_encrypted_goldens.dart';

Uint8List unhex(String s) => Uint8List.fromList(
    [for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)]);
String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('AES core', () {
    // FIPS-197 appendix C.1
    final key = unhex('000102030405060708090a0b0c0d0e0f');
    final plain = unhex('00112233445566778899aabbccddeeff');
    const cipher = '69c4e0d86a7b0430d8cdb78070b4c55a';

    test('encrypts_the_FIPS_197_vector', () {
      expect(hex(Aes128(key).encryptBlock(plain)), cipher);
    });

    test('decrypts_the_FIPS_197_vector', () {
      expect(hex(Aes128(key).decryptBlock(unhex(cipher))), hex(plain));
    });

    test('rejects_wrong_sizes', () {
      expect(() => Aes128([1, 2, 3]), throwsArgumentError);
      expect(() => Aes128(key).encryptBlock([1, 2, 3]), throwsArgumentError);
    });
  });

  group('matches the reference library', () {
    test('three_round_block_transform', () {
      for (final (input, expected) in samyVectors) {
        expect(hex(samyGoKeyTransform(unhex(input))), expected, reason: input);
      }
    });

    test('fixed_key_block_cipher_encrypt_and_decrypt', () {
      expect(hex(fixedKeyEncrypt(unhex(wbPlain))), wbEncrypted);
      expect(hex(fixedKeyDecrypt(unhex(wbPlain))), wbDecryptedOfPlain);
      expect(hex(fixedKeyDecrypt(unhex(wbEncrypted))), wbPlain);
    });

    test('server_hello', () {
      for (final v in helloVectors) {
        final h = generateServerHello(v.userId, v.pin);
        expect(hex(h.hello).toUpperCase(), v.hello, reason: v.pin);
        expect(hex(h.hash), v.hash, reason: v.pin);
        expect(hex(h.aesKey), v.aesKey, reason: v.pin);
      }
    });

    test('server_hello_is_what_the_exchange_vectors_used', () {
      for (final e in exchangeVectors) {
        expect(hex(generateServerHello(e.userId, e.pin).hello).toUpperCase(), e.serverHello);
      }
    });

    test('client_hello_yields_the_same_token_and_secret', () {
      for (final e in exchangeVectors) {
        final h = generateServerHello(e.userId, e.pin);
        final keys = parseClientHello(e.clientHello, h.hash, h.aesKey, e.userId);
        expect(keys, isNotNull, reason: e.pin);
        expect(hex(keys!.ctx), e.ctx);
        expect(hex(keys.skPrime), e.skprime);
      }
    });

    test('acknowledge_messages', () {
      for (final e in exchangeVectors) {
        expect(generateServerAcknowledge(unhex(e.skprime)), e.serverAck);
        expect(parseClientAcknowledge(e.clientAck, unhex(e.skprime)), isTrue);
        expect(parseClientAcknowledge(e.clientAck.replaceFirst('01', '02'), unhex(e.skprime)),
            isFalse);
      }
    });

    test('encrypted_key_command_frame', () {
      for (final e in exchangeVectors) {
        final s = SamsungEncryptedSession(e.ctx, '1');
        expect(s.encryptKeyCommand('KEY_VOLUP'), e.frameVolupSession1);
      }
    });
  });

  group('rejects bad input without throwing', () {
    test('wrong_pin_is_rejected', () {
      expect(
          parseClientHello(wrongPinClientHello, unhex(wrongPinHash), unhex(wrongPinAesKey), '654321'),
          isNull);
    });

    test('truncated_and_garbage_client_hellos_return_null', () {
      final h = generateServerHello('654321', '1234');
      final good = exchangeVectors.first.clientHello;
      for (final bad in [good.substring(0, 60), good.substring(0, good.length - 40), '', '00', 'zz']) {
        expect(parseClientHello(bad, h.hash, h.aesKey, '654321'), isNull, reason: bad);
      }
    });

    test('session_rejects_a_bad_token', () {
      expect(() => SamsungEncryptedSession('xyz', '1'), throwsA(anything));
    });
  });
}
