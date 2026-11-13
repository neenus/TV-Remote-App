import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha1;

// Port of the pairing and encryption steps used by Samsung H/J-series (2014-2015)
// TVs, following the samsungtvws library (`samsungtvws.encrypted`). The constants
// are fixed values those TVs expect; they are not secrets.
const _publicKey =
    '2cb12bb2cbf7cec713c0fff7b59ae68a96784ae517f41d259a45d20556177c0ffe951ca60ec03a990c9412619d1bee30adc7773088c5721664cffcedacf6d251cb4b76e2fd7aef09b3ae9f9496ac8d94ed2b262eee37291c8b237e880cc7c021fb1be0881f3d0bffa4234d3b8e6a61530c00473ce169c025f47fcc001d9b8051';
const _privateKey =
    '2fd6334713816fae018cdee4656c5033a8d6b00e8eaea07b3624999242e96247112dcd019c4191f4643c3ce1605002b2e506e7f1d1ef8d9b8044e46d37c0d5263216a87cd783aa185490436c4a0cb2c524e15bc1bfeae703bcbc4b74a0540202e8d79cadaae85c6f9c218bc1107d1f5b4b9bd87160e782f4e436eeb17485ab4d';
const _wbKey = 'abbb120c09e7114243d1fa0102163b27';
const _transKey = '6c9474469ddf7578f3e5ad8a4c703d99';
const _prime =
    'b361eb0ab01c3439f2c16ffda7b05e3e320701ebee3e249123c3586765fd5bf6c1dfa88bb6bb5da3fde74737cd88b6a26c5ca31d81d18e3515533d08df619317063224cf0943a2f29a5fe60c1c31ddf28334ed76a6478a1122fb24c4a94c8711617ddfe90cf02e643cd82d4748d6d4a7ca2f47d88563aa2baf6482e124acd7dd';

const _blockSize = 16;
const _shaLen = 20;

Uint8List _unhex(String s) {
  if (s.length.isOdd) throw const FormatException('odd-length hex');
  return Uint8List.fromList(
      [for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)]);
}

String _hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Uint8List _sha1(List<int> data) => Uint8List.fromList(sha1.convert(data).bytes);

Uint8List _be32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v);

// ---------------------------------------------------------------------------
// AES (any number of rounds, because the TV uses a 3-round variant)
// ---------------------------------------------------------------------------

final List<int> _sbox = () {
  final s = List<int>.filled(256, 0);
  var p = 1, q = 1;
  int rotl8(int x, int n) => ((x << n) | (x >> (8 - n))) & 0xff;
  do {
    p = (p ^ (p << 1) ^ ((p & 0x80) != 0 ? 0x11b : 0)) & 0xff; // multiply by 3
    q = (q ^ (q << 1)) & 0xff; // divide by 3
    q = (q ^ (q << 2)) & 0xff;
    q = (q ^ (q << 4)) & 0xff;
    if ((q & 0x80) != 0) q ^= 0x09;
    s[p] = (q ^ rotl8(q, 1) ^ rotl8(q, 2) ^ rotl8(q, 3) ^ rotl8(q, 4) ^ 0x63) & 0xff;
  } while (p != 1);
  s[0] = 0x63;
  return s;
}();

final List<int> _invSbox = () {
  final inv = List<int>.filled(256, 0);
  for (var i = 0; i < 256; i++) {
    inv[_sbox[i]] = i;
  }
  return inv;
}();

int _xtime(int x) => ((x << 1) ^ ((x & 0x80) != 0 ? 0x1b : 0)) & 0xff;

int _gmul(int a, int b) {
  var r = 0;
  while (b != 0) {
    if ((b & 1) != 0) r ^= a;
    a = _xtime(a);
    b >>= 1;
  }
  return r;
}

/// AES with a 128-bit key. [encryptBlock] can run fewer than the standard 10
/// rounds (the pairing handshake uses 3).
class Aes128 {
  Aes128(List<int> key) {
    if (key.length != 16) throw ArgumentError('AES-128 needs a 16-byte key');
    final w = List<int>.filled(176, 0);
    for (var i = 0; i < 16; i++) {
      w[i] = key[i];
    }
    var rcon = 1;
    for (var i = 16; i < 176; i += 4) {
      var t0 = w[i - 4], t1 = w[i - 3], t2 = w[i - 2], t3 = w[i - 1];
      if (i % 16 == 0) {
        final u = t0;
        t0 = _sbox[t1] ^ rcon;
        t1 = _sbox[t2];
        t2 = _sbox[t3];
        t3 = _sbox[u];
        rcon = _xtime(rcon);
      }
      w[i] = w[i - 16] ^ t0;
      w[i + 1] = w[i - 15] ^ t1;
      w[i + 2] = w[i - 14] ^ t2;
      w[i + 3] = w[i - 13] ^ t3;
    }
    _roundKeys = w;
  }

  late final List<int> _roundKeys;

  void _addRoundKey(List<int> s, int round) {
    for (var i = 0; i < 16; i++) {
      s[i] ^= _roundKeys[round * 16 + i];
    }
  }

  static void _shiftRows(List<int> s, {required bool inverse}) {
    final t = List<int>.of(s);
    for (var r = 1; r < 4; r++) {
      for (var c = 0; c < 4; c++) {
        final from = inverse ? (c - r) % 4 : (c + r) % 4;
        s[r + 4 * c] = t[r + 4 * from];
      }
    }
  }

  static void _mixColumns(List<int> s, {required bool inverse}) {
    final m = inverse ? const [14, 11, 13, 9] : const [2, 3, 1, 1];
    for (var c = 0; c < 4; c++) {
      final a = s.sublist(4 * c, 4 * c + 4);
      for (var r = 0; r < 4; r++) {
        s[4 * c + r] = _gmul(a[0], m[(0 - r) % 4]) ^
            _gmul(a[1], m[(1 - r) % 4]) ^
            _gmul(a[2], m[(2 - r) % 4]) ^
            _gmul(a[3], m[(3 - r) % 4]);
      }
    }
  }

  Uint8List encryptBlock(List<int> block, {int rounds = 10}) {
    if (block.length != 16) throw ArgumentError('AES blocks are 16 bytes');
    final s = List<int>.of(block);
    _addRoundKey(s, 0);
    for (var round = 1; round <= rounds; round++) {
      for (var i = 0; i < 16; i++) {
        s[i] = _sbox[s[i]];
      }
      _shiftRows(s, inverse: false);
      if (round != rounds) _mixColumns(s, inverse: false);
      _addRoundKey(s, round);
    }
    return Uint8List.fromList(s);
  }

  Uint8List decryptBlock(List<int> block) {
    if (block.length != 16) throw ArgumentError('AES blocks are 16 bytes');
    final s = List<int>.of(block);
    _addRoundKey(s, 10);
    for (var round = 9; round >= 0; round--) {
      _shiftRows(s, inverse: true);
      for (var i = 0; i < 16; i++) {
        s[i] = _invSbox[s[i]];
      }
      _addRoundKey(s, round);
      if (round != 0) _mixColumns(s, inverse: true);
    }
    return Uint8List.fromList(s);
  }
}

Uint8List aesEcbEncrypt(List<int> key, List<int> data) {
  if (data.length % 16 != 0) throw ArgumentError('data must be whole 16-byte blocks');
  final aes = Aes128(key);
  final out = BytesBuilder();
  for (var i = 0; i < data.length; i += 16) {
    out.add(aes.encryptBlock(data.sublist(i, i + 16)));
  }
  return out.toBytes();
}

/// CBC with an all-zero IV and no padding, as the TV does.
Uint8List aesCbcEncrypt(List<int> key, List<int> data) {
  if (data.length % 16 != 0) throw ArgumentError('data must be whole 16-byte blocks');
  final aes = Aes128(key);
  final out = BytesBuilder();
  var prev = List<int>.filled(16, 0);
  for (var i = 0; i < data.length; i += 16) {
    final x = [for (var j = 0; j < 16; j++) data[i + j] ^ prev[j]];
    prev = aes.encryptBlock(x);
    out.add(prev);
  }
  return out.toBytes();
}

Uint8List aesCbcDecrypt(List<int> key, List<int> data) {
  if (data.length % 16 != 0) throw ArgumentError('data must be whole 16-byte blocks');
  final aes = Aes128(key);
  final out = BytesBuilder();
  var prev = List<int>.filled(16, 0);
  for (var i = 0; i < data.length; i += 16) {
    final block = data.sublist(i, i + 16);
    final d = aes.decryptBlock(block);
    out.add([for (var j = 0; j < 16; j++) d[j] ^ prev[j]]);
    prev = block;
  }
  return out.toBytes();
}

/// The TV's fixed-key per-block cipher over the first 128 bytes
/// (`_encrypt_parameter_data_with_aes` in the reference).
Uint8List fixedKeyEncrypt(List<int> data) {
  if (data.length < 128) throw ArgumentError('need 128 bytes');
  final aes = Aes128(_unhex(_wbKey));
  final out = BytesBuilder();
  for (var i = 0; i < 128; i += 16) {
    out.add(aes.encryptBlock(data.sublist(i, i + 16)));
  }
  return out.toBytes();
}

Uint8List fixedKeyDecrypt(List<int> data) {
  if (data.length < 128) throw ArgumentError('need 128 bytes');
  final aes = Aes128(_unhex(_wbKey));
  final out = BytesBuilder();
  for (var i = 0; i < 128; i += 16) {
    out.add(aes.decryptBlock(data.sublist(i, i + 16)));
  }
  return out.toBytes();
}

/// One 16-byte block through a **3-round** AES with the TV's fixed key.
Uint8List samyGoKeyTransform(List<int> data) =>
    Aes128(_unhex(_transKey)).encryptBlock(data, rounds: 3);

// ---------------------------------------------------------------------------
// Pairing handshake
// ---------------------------------------------------------------------------

class ServerHello {
  const ServerHello(this.hello, this.hash, this.aesKey);
  final Uint8List hello;
  final Uint8List hash;
  final Uint8List aesKey;
}

ServerHello generateServerHello(String userId, String pin) {
  final aesKey = _sha1(utf8.encode(pin)).sublist(0, 16);
  final encrypted = aesCbcEncrypt(aesKey, _unhex(_publicKey));
  final swapped = fixedKeyEncrypt(encrypted);
  final uid = utf8.encode(userId);
  final data = Uint8List.fromList([..._be32(uid.length), ...uid, ...swapped]);
  final hello = Uint8List.fromList(
      [1, 2, ...List.filled(5, 0), ..._be32(uid.length + 132), ...data, ...List.filled(5, 0)]);
  return ServerHello(hello, _sha1(data), aesKey);
}

class PairingKeys {
  const PairingKeys(this.ctx, this.skPrime);

  /// The AES key used to encrypt commands (16 bytes).
  final Uint8List ctx;
  final Uint8List skPrime;
}

BigInt _bigFromBytes(List<int> b) => b.isEmpty ? BigInt.zero : BigInt.parse(_hex(b), radix: 16);

/// Checks the TV's reply against the PIN. Returns null if the PIN is wrong or
/// the message is malformed (never throws).
PairingKeys? parseClientHello(
    String clientHelloHex, List<int> dataHash, List<int> aesKey, String userId) {
  try {
    const userIdPos = 15;
    const gxSize = 0x80;
    final data = _unhex(clientHelloHex);
    final bd = data.buffer.asByteData();
    final userIdLen = bd.getUint32(11);
    final userIdBytes = data.sublist(userIdPos, userIdPos + userIdLen);
    final pEncWBGx = data.sublist(userIdPos + userIdLen, userIdPos + userIdLen + gxSize);
    final pEncGx = fixedKeyDecrypt(pEncWBGx);
    final pGx = aesCbcDecrypt(aesKey, pEncGx);

    var secretHex = _bigFromBytes(pGx)
        .modPow(BigInt.parse(_privateKey, radix: 16), BigInt.parse(_prime, radix: 16))
        .toRadixString(16);
    // The reference would fail on an odd digit count; a leading zero is the natural reading.
    if (secretHex.length.isOdd) secretHex = '0$secretHex';
    final secret = _unhex(secretHex);

    final hashPos = userIdPos + userIdLen + gxSize;
    final dataHash2 = data.sublist(hashPos, hashPos + _shaLen);
    final dataHash3 = _sha1([...userIdBytes, ...secret]);
    var same = dataHash2.length == dataHash3.length;
    for (var i = 0; same && i < dataHash2.length; i++) {
      same = dataHash2[i] == dataHash3[i];
    }
    if (!same) return null;

    final flagPos = hashPos + _shaLen;
    if (data[flagPos] != 0) return null;
    if (bd.getUint32(flagPos + 1) != 0) return null;

    final finalBuffer = [
      ...userIdBytes,
      ...utf8.encode(userId),
      ...pGx,
      ..._unhex(_publicKey),
      ...secret,
    ];
    final skPrime = _sha1(finalBuffer);
    final skPrimeHash = _sha1([...skPrime, 0]);
    return PairingKeys(samyGoKeyTransform(skPrimeHash.sublist(0, 16)), skPrime);
  } catch (_) {
    return null;
  }
}

String generateServerAcknowledge(List<int> skPrime) =>
    '0103000000000000000014${_hex(_sha1([...skPrime, 1])).toUpperCase()}0000000000';

bool parseClientAcknowledge(String clientAck, List<int> skPrime) =>
    clientAck == '0104000000000000000014${_hex(_sha1([...skPrime, 2])).toUpperCase()}0000000000';

// ---------------------------------------------------------------------------
// Encrypted commands
// ---------------------------------------------------------------------------

class SamsungEncryptedSession {
  /// [tokenHex] is the 32-hex-digit key from pairing; [sessionId] comes from pairing too.
  SamsungEncryptedSession(String tokenHex, this.sessionId) : _key = _unhex(tokenHex) {
    if (_key.length != 16) throw ArgumentError('token must be 16 bytes');
  }

  final String sessionId;
  final Uint8List _key;

  /// The socket.io frame carrying an encrypted remote-key click.
  String encryptKeyCommand(String key) {
    // Spacing matches Python's json.dumps so output can be compared with the reference.
    final payload = '{"method": "POST", "body": {"plugin": "RemoteControl", '
        '"param1": "uuid:12345", "param2": "Click", "param3": ${jsonEncode(key)}, '
        '"param4": false, "api": "SendRemoteKey", "version": "1.000"}}';
    final raw = utf8.encode(payload);
    final pad = 16 - raw.length % 16;
    final bytes = aesEcbEncrypt(_key, [...raw, ...List.filled(pad, pad)]);
    return '5::/com.samsung.companion:{"name":"callCommon","args":[{"Session_Id":$sessionId,'
        '"body":"[${bytes.join(',')}]"}]}';
  }
}
