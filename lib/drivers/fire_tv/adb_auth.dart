import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' as pc;

const _modulusBytes = 256; // ADB keys are always RSA-2048
final _publicExponent = BigInt.from(65537);

// DER prefix of a SHA-1 DigestInfo (ADB signs the 20-byte token as if it were already a hash).
const _sha1DigestInfoPrefix = [
  0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2b, 0x0e, 0x03, 0x02, 0x1a, 0x05, 0x00, 0x04, 0x14,
];

class AdbKey {
  AdbKey(this.n, this.d, [BigInt? e]) : e = e ?? _publicExponent;
  final BigInt n;
  final BigInt d;
  final BigInt e;

  String serialize() => '${n.toRadixString(16)}:${d.toRadixString(16)}';

  static AdbKey? parse(String s) {
    final parts = s.split(':');
    if (parts.length != 2) return null;
    final n = BigInt.tryParse(parts[0], radix: 16);
    final d = BigInt.tryParse(parts[1], radix: 16);
    if (n == null || d == null || parts[0].isEmpty || parts[1].isEmpty) return null;
    if (n.bitLength != _modulusBytes * 8 || d <= BigInt.zero || d >= n) return null;
    return AdbKey(n, d);
  }
}

Uint8List _bigEndian(BigInt v, int length) {
  final out = Uint8List(length);
  var x = v;
  for (var i = length - 1; i >= 0; i--) {
    out[i] = (x & BigInt.from(0xff)).toInt();
    x >>= 8;
  }
  if (x != BigInt.zero) throw ArgumentError('value does not fit in $length bytes');
  return out;
}

Uint8List _littleEndian(BigInt v, int length) =>
    Uint8List.fromList(_bigEndian(v, length).reversed.toList());

BigInt _bigFromBytes(List<int> b) {
  var v = BigInt.zero;
  for (final byte in b) {
    v = (v << 8) | BigInt.from(byte);
  }
  return v;
}

/// Signs the 20-byte token from the device (PKCS#1 v1.5, SHA-1 DigestInfo built
/// directly from the token, which is what ADB expects).
Uint8List adbSignToken(AdbKey key, List<int> token) {
  if (token.length != 20) throw ArgumentError('ADB tokens are 20 bytes');
  final digestInfo = [..._sha1DigestInfoPrefix, ...token];
  final padding = _modulusBytes - 3 - digestInfo.length;
  final em = Uint8List.fromList([0x00, 0x01, ...List.filled(padding, 0xff), 0x00, ...digestInfo]);
  final signature = _bigFromBytes(em).modPow(key.d, key.n);
  return _bigEndian(signature, _modulusBytes);
}

/// ADB's own RSAPublicKey struct (little-endian words), 524 bytes for RSA-2048.
Uint8List adbPublicKeyStruct(AdbKey key) {
  final r32 = BigInt.one << 32;
  final n0inv = r32 - (key.n % r32).modInverse(r32); // -1 / n[0] mod 2^32
  final rr = (BigInt.one << (_modulusBytes * 8 * 2)) % key.n; // (2^2048)^2 mod n
  final out = BytesBuilder()
    ..add(_littleEndian(BigInt.from(_modulusBytes ~/ 4), 4))
    ..add(_littleEndian(n0inv, 4))
    ..add(_littleEndian(key.n, _modulusBytes))
    ..add(_littleEndian(rr, _modulusBytes))
    ..add(_littleEndian(key.e, 4));
  return out.toBytes();
}

/// What goes in the AUTH "public key" message: base64 of the struct, a user label
/// (shown on the device's Allow box), and a NUL.
Uint8List adbPublicKeyPayload(AdbKey key, {String userInfo = ' tv-remote@phone'}) =>
    Uint8List.fromList([
      ...utf8.encode(base64.encode(adbPublicKeyStruct(key))),
      ...utf8.encode(userInfo),
      0,
    ]);

AdbKey generateAdbKeySync({int bits = 2048}) {
  final random = pc.FortunaRandom();
  final seeder = Random.secure();
  random.seed(pc.KeyParameter(Uint8List.fromList(List.generate(32, (_) => seeder.nextInt(256)))));
  final generator = pc.RSAKeyGenerator()
    ..init(pc.ParametersWithRandom(
        pc.RSAKeyGeneratorParameters(_publicExponent, bits, 64), random));
  final pair = generator.generateKeyPair();
  final pub = pair.publicKey;
  final priv = pair.privateKey;
  return AdbKey(pub.modulus!, priv.privateExponent!, pub.publicExponent);
}

/// Generates a key off the UI thread (takes several seconds).
Future<AdbKey> generateAdbKey() => Isolate.run(generateAdbKeySync);
