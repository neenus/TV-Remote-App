@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/drivers/android_tv/atv_crypto.dart';

import '../../support/atv_goldens.dart';

Uint8List unhex(String s) => Uint8List.fromList(
    [for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)]);
String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('pairing secret (matches the reference library)', () {
    final clientN = BigInt.parse(atvPair_client_n, radix: 16);
    final serverN = BigInt.parse(atvPair_server_n, radix: 16);

    test('the_right_code_gives_the_reference_secret', () {
      final secret = atvPairingSecret(
          clientN: clientN,
          clientE: BigInt.from(atvPair_client_e),
          serverN: serverN,
          serverE: BigInt.from(atvPair_server_e),
          code: atvPair_code);
      expect(secret == null ? null : hex(secret), atvPair_secret);
    });

    test('lowercase_and_spaces_are_accepted', () {
      final secret = atvPairingSecret(
          clientN: clientN,
          clientE: BigInt.from(atvPair_client_e),
          serverN: serverN,
          serverE: BigInt.from(atvPair_server_e),
          code: ' ${atvPair_code.toLowerCase()} ');
      expect(secret == null ? null : hex(secret), atvPair_secret);
    });

    test('a_wrong_code_is_caught_locally_by_its_checksum_byte', () {
      expect(
          atvPairingSecret(
              clientN: clientN,
              clientE: BigInt.from(atvPair_client_e),
              serverN: serverN,
              serverE: BigInt.from(atvPair_server_e),
              code: atvPair_bad_code),
          isNull);
    });

    test('malformed_codes_are_rejected', () {
      for (final bad in ['', '12345', '1234567', 'ZZZZZZ', '4B2B3', '4B 2B3C']) {
        expect(
            atvPairingSecret(
                clientN: clientN,
                clientE: BigInt.from(atvPair_client_e),
                serverN: serverN,
                serverE: BigInt.from(atvPair_server_e),
                code: bad),
            isNull,
            reason: bad);
      }
    });
  });

  group('certificates', () {
    test('the_public_key_is_read_from_a_real_certificate', () {
      final key = rsaPublicKeyFromCertDer(unhex(atvPair_server_cert_der));
      expect(key?.n.toRadixString(16), atvPair_server_n);
      expect(key?.e, BigInt.from(atvPair_server_e));
    });

    test('and_from_a_pem_certificate', () {
      final der = pemToDer(atvPair_client_cert_pem);
      final key = rsaPublicKeyFromCertDer(der!);
      expect(key?.n.toRadixString(16), atvPair_client_n);
    });

    test('garbage_is_not_a_certificate', () {
      expect(rsaPublicKeyFromCertDer(Uint8List(0)), isNull);
      expect(rsaPublicKeyFromCertDer(Uint8List.fromList([1, 2, 3, 4, 5])), isNull);
      expect(rsaPublicKeyFromCertDer(unhex(atvPair_server_cert_der).sublist(0, 200)), isNull);
      expect(pemToDer('not pem'), isNull);
    });
  });

  group('our own identity', () {
    late AtvIdentity id;
    setUpAll(() => id = generateAtvIdentitySync());

    test('is_pem_with_the_usual_labels', () {
      expect(id.certPem, startsWith('-----BEGIN CERTIFICATE-----'));
      expect(id.certPem.trim(), endsWith('-----END CERTIFICATE-----'));
      expect(id.keyPem, startsWith('-----BEGIN RSA PRIVATE KEY-----'));
      for (final line in id.certPem.split('\n')) {
        expect(line.length, lessThanOrEqualTo(64));
      }
    });

    test('certificate_and_private_key_belong_together', () {
      final cert = rsaPublicKeyFromCertDer(pemToDer(id.certPem)!)!;
      expect(cert.n.bitLength, 2048);
      expect(cert.e, BigInt.from(65537));
      final priv = parseRsaPrivateKeyDer(pemToDer(id.keyPem)!)!;
      expect(priv.n, cert.n);
      expect(priv.p * priv.q, priv.n);
      expect(priv.dp, priv.d % (priv.p - BigInt.one));
      expect(priv.dq, priv.d % (priv.q - BigInt.one));
      expect((priv.qinv * priv.q) % priv.p, BigInt.one);
      final m = BigInt.from(123456789);
      expect(m.modPow(priv.e, priv.n).modPow(priv.d, priv.n), m);
    });

    test('the_certificate_signature_verifies', () {
      final der = pemToDer(id.certPem)!;
      final root = parseDerNode(der)!;
      final tbs = root.children[0];
      final sig = root.children[2].content.sublist(1); // BIT STRING: skip the unused-bits byte
      final pub = rsaPublicKeyFromCertDer(der)!;
      final em = BigInt.parse(hex(sig), radix: 16).modPow(pub.e, pub.n).toRadixString(16).padLeft(512, '0');
      final digest = sha256.convert(tbs.raw).bytes;
      const prefix = '3031300d060960864801650304020105000420';
      expect(em.endsWith('$prefix${hex(digest)}'), isTrue);
      expect(em.startsWith('0001ffff'), isTrue);
    });

    test('is_self_signed_for_a_long_time', () {
      final text = latin1.decode(pemToDer(id.certPem)!, allowInvalid: true);
      expect(text.contains('atvremote'), isTrue);
    });
  });

  test('identity_serializes_and_parses', () {
    final id = generateAtvIdentitySync();
    final back = AtvIdentity.parse(id.serialize());
    expect(back?.certPem, id.certPem);
    expect(back?.keyPem, id.keyPem);
    expect(AtvIdentity.parse('garbage'), isNull);
    expect(AtvIdentity.parse(''), isNull);
  });
}
