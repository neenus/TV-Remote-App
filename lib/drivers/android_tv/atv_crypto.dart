import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:pointycastle/export.dart' as pc;

// ---------------------------------------------------------------------------
// Pairing secret
// ---------------------------------------------------------------------------

Uint8List _minimalBytes(BigInt v) {
  if (v == BigInt.zero) return Uint8List(0);
  var hex = v.toRadixString(16);
  if (hex.length.isOdd) hex = '0$hex';
  return Uint8List.fromList(
      [for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)]);
}

/// The 6 hex digits the TV shows, normalised, or null if malformed.
String? normalizeAtvCode(String raw) {
  final s = raw.trim().toUpperCase();
  return RegExp(r'^[0-9A-F]{6}$').hasMatch(s) ? s : null;
}

/// The secret that proves we typed the code the TV is showing: SHA-256 over both
/// certificates' public keys and the last 4 digits of the code. The first two digits
/// are a checksum byte of that hash, so a wrong code is recognised without asking
/// the TV (null).
Uint8List? atvPairingSecret({
  required BigInt clientN,
  required BigInt clientE,
  required BigInt serverN,
  required BigInt serverE,
  required String code,
}) {
  final c = normalizeAtvCode(code);
  if (c == null) return null;
  final tail = [
    for (var i = 2; i < 6; i += 2) int.parse(c.substring(i, i + 2), radix: 16),
  ];
  final digest = sha256.convert([
    ..._minimalBytes(clientN),
    ..._minimalBytes(clientE),
    ..._minimalBytes(serverN),
    ..._minimalBytes(serverE),
    ...tail,
  ]).bytes;
  if (digest[0] != int.parse(c.substring(0, 2), radix: 16)) return null;
  return Uint8List.fromList(digest);
}

// ---------------------------------------------------------------------------
// DER (just enough to read and build certificates)
// ---------------------------------------------------------------------------

class DerNode {
  DerNode(this.tag, this.content, this.raw);
  final int tag;
  final Uint8List content;
  final Uint8List raw;

  List<DerNode> get children {
    final out = <DerNode>[];
    var offset = 0;
    while (offset < content.length) {
      final node = parseDerNode(content, offset);
      if (node == null) break;
      out.add(node);
      offset += node.raw.length;
    }
    return out;
  }
}

/// Reads one TLV at [offset]; null if it is malformed or doesn't fit.
DerNode? parseDerNode(List<int> bytes, [int offset = 0]) {
  if (offset + 2 > bytes.length) return null;
  final tag = bytes[offset];
  if (tag & 0x1f == 0x1f) return null; // multi-byte tags aren't used here
  var pos = offset + 1;
  var length = bytes[pos++];
  if (length & 0x80 != 0) {
    final n = length & 0x7f;
    if (n == 0 || n > 4 || pos + n > bytes.length) return null;
    length = 0;
    for (var i = 0; i < n; i++) {
      length = (length << 8) | bytes[pos++];
    }
  }
  if (pos + length > bytes.length) return null;
  return DerNode(
    tag,
    Uint8List.fromList(bytes.sublist(pos, pos + length)),
    Uint8List.fromList(bytes.sublist(offset, pos + length)),
  );
}

BigInt _derUnsigned(DerNode n) =>
    n.content.isEmpty ? BigInt.zero : BigInt.parse(_hex(n.content), radix: 16);

String _hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

/// The RSA public key (modulus, exponent) inside an X.509 certificate, or null.
({BigInt n, BigInt e})? rsaPublicKeyFromCertDer(List<int> der) {
  try {
    final root = parseDerNode(der);
    if (root == null || root.tag != 0x30) return null;
    final tbs = root.children.first.children;
    var i = tbs.first.tag == 0xA0 ? 1 : 0; // optional version
    final spki = tbs[i + 5]; // serial, signature, issuer, validity, subject, then the key
    final bits = spki.children[1].content;
    final key = parseDerNode(bits.sublist(1)); // skip the unused-bits byte
    final parts = key!.children;
    if (key.tag != 0x30 || parts.length != 2) return null;
    return (n: _derUnsigned(parts[0]), e: _derUnsigned(parts[1]));
  } catch (_) {
    return null;
  }
}

Uint8List? pemToDer(String pem) {
  final m = RegExp(r'-----BEGIN [A-Z ]+-----([\s\S]*?)-----END [A-Z ]+-----').firstMatch(pem);
  if (m == null) return null;
  try {
    return base64.decode(m.group(1)!.replaceAll(RegExp(r'\s'), ''));
  } catch (_) {
    return null;
  }
}

class RsaPrivateKey {
  RsaPrivateKey(this.n, this.e, this.d, this.p, this.q, this.dp, this.dq, this.qinv);
  final BigInt n, e, d, p, q, dp, dq, qinv;
}

/// A PKCS#1 RSAPrivateKey, or null if it isn't one.
RsaPrivateKey? parseRsaPrivateKeyDer(List<int> der) {
  try {
    final root = parseDerNode(der);
    final c = root?.children;
    if (root == null || root.tag != 0x30 || c == null || c.length < 9) return null;
    final v = [for (var i = 1; i < 9; i++) _derUnsigned(c[i])];
    return RsaPrivateKey(v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7]);
  } catch (_) {
    return null;
  }
}

Uint8List _len(int n) {
  if (n < 0x80) return Uint8List.fromList([n]);
  final bytes = <int>[];
  var v = n;
  while (v > 0) {
    bytes.insert(0, v & 0xff);
    v >>= 8;
  }
  return Uint8List.fromList([0x80 | bytes.length, ...bytes]);
}

Uint8List _tlv(int tag, List<int> content) =>
    Uint8List.fromList([tag, ..._len(content.length), ...content]);

Uint8List _seq(List<List<int>> parts) => _tlv(0x30, [for (final p in parts) ...p]);

Uint8List _int(BigInt v) {
  var bytes = _minimalBytes(v);
  if (bytes.isEmpty) bytes = Uint8List.fromList([0]);
  if (bytes[0] & 0x80 != 0) bytes = Uint8List.fromList([0, ...bytes]);
  return _tlv(0x02, bytes);
}

Uint8List _oid(String dotted) {
  final parts = dotted.split('.').map(int.parse).toList();
  final out = <int>[parts[0] * 40 + parts[1]];
  for (final part in parts.skip(2)) {
    final chunk = <int>[part & 0x7f];
    var v = part >> 7;
    while (v > 0) {
      chunk.insert(0, (v & 0x7f) | 0x80);
      v >>= 7;
    }
    out.addAll(chunk);
  }
  return _tlv(0x06, out);
}

final _null = Uint8List.fromList([0x05, 0x00]);

String _utcTime(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  final u = t.toUtc();
  return '${two(u.year % 100)}${two(u.month)}${two(u.day)}${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
}

String _pem(String label, List<int> der) {
  final b64 = base64.encode(der);
  final lines = [for (var i = 0; i < b64.length; i += 64) b64.substring(i, min(i + 64, b64.length))];
  return '-----BEGIN $label-----\n${lines.join('\n')}\n-----END $label-----\n';
}

// ---------------------------------------------------------------------------
// Our own identity: a self-signed certificate and its private key
// ---------------------------------------------------------------------------

class AtvIdentity {
  const AtvIdentity(this.certPem, this.keyPem);
  final String certPem;
  final String keyPem;

  String serialize() => jsonEncode({'c': certPem, 'k': keyPem});

  static AtvIdentity? parse(String s) {
    try {
      final j = jsonDecode(s);
      if (j is! Map) return null;
      final c = j['c'], k = j['k'];
      if (c is! String || k is! String) return null;
      if (pemToDer(c) == null || pemToDer(k) == null) return null;
      return AtvIdentity(c, k);
    } catch (_) {
      return null;
    }
  }
}

final _sha256Prefix = Uint8List.fromList(
    [0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20]);

/// A new RSA-2048 key and a self-signed certificate for it (CN and DNS name
/// [commonName], valid for ten years) in PEM. Takes seconds: use [generateAtvIdentity].
AtvIdentity generateAtvIdentitySync({String commonName = 'atvremote'}) {
  final random = pc.FortunaRandom();
  final seeder = Random.secure();
  random.seed(pc.KeyParameter(Uint8List.fromList(List.generate(32, (_) => seeder.nextInt(256)))));
  final e = BigInt.from(65537);
  final gen = pc.RSAKeyGenerator()
    ..init(pc.ParametersWithRandom(pc.RSAKeyGeneratorParameters(e, 2048, 64), random));
  final pair = gen.generateKeyPair();
  final pub = pair.publicKey;
  final priv = pair.privateKey;
  final n = pub.modulus!, d = priv.privateExponent!, p = priv.p!, q = priv.q!;

  final signatureAlgorithm = _seq([_oid('1.2.840.113549.1.1.11'), _null]); // sha256WithRSAEncryption
  final name = _seq([
    _tlv(0x31, _seq([_oid('2.5.4.3'), _tlv(0x0c, utf8.encode(commonName))])),
  ]);
  final now = DateTime.now().toUtc();
  final validity = _seq([
    _tlv(0x17, ascii.encode(_utcTime(now.subtract(const Duration(days: 1))))),
    _tlv(0x17, ascii.encode(_utcTime(now.add(const Duration(days: 3650))))),
  ]);
  final spki = _seq([
    _seq([_oid('1.2.840.113549.1.1.1'), _null]), // rsaEncryption
    _tlv(0x03, [0, ..._seq([_int(n), _int(e)])]),
  ]);
  final extensions = _tlv(0xA3, _seq([
    _seq([_oid('2.5.29.19'), _tlv(0x04, _seq([_tlv(0x01, [0xff]), _int(BigInt.zero)]))]), // CA, pathlen 0
    _seq([_oid('2.5.29.17'), _tlv(0x04, _seq([_tlv(0x82, ascii.encode(commonName))]))]), // DNS name
  ]));
  final tbs = _seq([
    _tlv(0xA0, _int(BigInt.two)), // version 3
    _int(BigInt.from(1000)),
    signatureAlgorithm,
    name,
    validity,
    name,
    spki,
    extensions,
  ]);

  final digestInfo = [..._sha256Prefix, ...sha256.convert(tbs).bytes];
  final em = Uint8List.fromList([0x00, 0x01, ...List.filled(256 - 3 - digestInfo.length, 0xff), 0x00, ...digestInfo]);
  final signature = _minimalBytesPadded(BigInt.parse(_hex(em), radix: 16).modPow(d, n), 256);
  final cert = _seq([tbs, signatureAlgorithm, _tlv(0x03, [0, ...signature])]);

  final key = _seq([
    _int(BigInt.zero),
    _int(n),
    _int(e),
    _int(d),
    _int(p),
    _int(q),
    _int(d % (p - BigInt.one)),
    _int(d % (q - BigInt.one)),
    _int(q.modInverse(p)),
  ]);
  return AtvIdentity(_pem('CERTIFICATE', cert), _pem('RSA PRIVATE KEY', key));
}

Uint8List _minimalBytesPadded(BigInt v, int length) {
  final bytes = _minimalBytes(v);
  return Uint8List.fromList([...List.filled(length - bytes.length, 0), ...bytes]);
}

/// Generates an identity off the UI thread (takes several seconds).
Future<AtvIdentity> generateAtvIdentity() => Isolate.run(generateAtvIdentitySync);
