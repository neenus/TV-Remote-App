import 'dart:convert';

import '../../core/tv_key.dart';

/// Samsung TVs from about 2008 to 2015 listen for a simple binary protocol on
/// this TCP port. Packet formats follow samsungctl's `remote_legacy.py`.
const legacyPort = 55000;

// What the TV shows on its "Allow" prompt and remembers us by.
const _description = 'TV Remote';
const _id = 'tv-remote-app';
const _name = 'TV Remote';

/// 1-byte length, 0x00, then the bytes (base64 first unless [raw]).
List<int> _serialize(List<int> data, {bool raw = false}) {
  final bytes = raw ? data : utf8.encode(base64Encode(data));
  if (bytes.length > 255) {
    // Length-prefixed with one byte: never send a truncated, corrupt packet.
    throw ArgumentError('legacy strings must fit in 255 bytes (got ${bytes.length})');
  }
  return [bytes.length & 0xff, 0x00, ...bytes];
}

List<int> legacyHandshake() {
  final payload = [
    0x64,
    0x00,
    ..._serialize(utf8.encode(_description)),
    ..._serialize(utf8.encode(_id)),
    ..._serialize(utf8.encode(_name)),
  ];
  return [0x00, 0x00, 0x00, ..._serialize(payload, raw: true)];
}

List<int> legacyKeyPacket(String key) {
  final payload = [0x00, 0x00, 0x00, ..._serialize(utf8.encode(key))];
  return [0x00, 0x00, 0x00, ..._serialize(payload, raw: true)];
}

class LegacyKeyMap {
  static String? key(TvKey k) => switch (k) {
        TvKey.power => 'KEY_POWEROFF', // KEY_POWER is for 2016+ TVs
        TvKey.up => 'KEY_UP',
        TvKey.down => 'KEY_DOWN',
        TvKey.left => 'KEY_LEFT',
        TvKey.right => 'KEY_RIGHT',
        TvKey.ok => 'KEY_ENTER',
        TvKey.back => 'KEY_RETURN',
        TvKey.home => 'KEY_CONTENTS', // SmartHub
        TvKey.menu => 'KEY_MENU',
        TvKey.volumeUp => 'KEY_VOLUP',
        TvKey.volumeDown => 'KEY_VOLDOWN',
        TvKey.mute => 'KEY_MUTE',
        TvKey.channelUp => 'KEY_CHUP',
        TvKey.channelDown => 'KEY_CHDOWN',
        TvKey.rewind => 'KEY_REWIND',
        TvKey.play => 'KEY_PLAY',
        TvKey.pause => 'KEY_PAUSE',
        TvKey.fastForward => 'KEY_FF',
        TvKey.input => 'KEY_SOURCE',
      };
}

sealed class LegacyReply {
  const LegacyReply();
}

class LegacyGranted extends LegacyReply {
  const LegacyGranted();
}

class LegacyDenied extends LegacyReply {
  const LegacyDenied();
}

/// The TV is showing its "Allow" prompt and waiting for the user.
class LegacyWaiting extends LegacyReply {
  const LegacyWaiting();
}

class LegacyCancelled extends LegacyReply {
  const LegacyCancelled();
}

/// A key press was accepted.
class LegacyAck extends LegacyReply {
  const LegacyAck();
}

class LegacyUnknown extends LegacyReply {
  const LegacyUnknown(this.raw);
  final List<int> raw;
}

/// Reassembles TV replies (`00 <nameLen LE16> name <respLen LE16> resp`) from
/// arbitrary TCP chunks.
class LegacyFrameParser {
  static const _maxField = 1024;
  final _buf = <int>[];

  List<LegacyReply> add(List<int> chunk) {
    _buf.addAll(chunk);
    final out = <LegacyReply>[];
    while (_buf.length >= 3) {
      final nameLen = _buf[1] | (_buf[2] << 8);
      if (nameLen > _maxField) return _garbage(out);
      final respLenAt = 3 + nameLen;
      if (_buf.length < respLenAt + 2) break;
      final respLen = _buf[respLenAt] | (_buf[respLenAt + 1] << 8);
      if (respLen > _maxField) return _garbage(out);
      final end = respLenAt + 2 + respLen;
      if (_buf.length < end) break;
      final resp = _buf.sublist(respLenAt + 2, end);
      _buf.removeRange(0, end);
      out.add(_classify(resp));
    }
    return out;
  }

  List<LegacyReply> _garbage(List<LegacyReply> out) {
    out.add(LegacyUnknown(List.of(_buf)));
    _buf.clear();
    return out;
  }

  static LegacyReply _classify(List<int> r) {
    if (r.length == 4 && r[0] == 0x64 && r[1] == 0 && r[2] == 1 && r[3] == 0) {
      return const LegacyGranted();
    }
    if (r.length == 4 && r[0] == 0x64 && r[1] == 0 && r[2] == 0 && r[3] == 0) {
      return const LegacyDenied();
    }
    if (r.isNotEmpty && r[0] == 0x0a) return const LegacyWaiting();
    if (r.isNotEmpty && r[0] == 0x65) return const LegacyCancelled();
    if (r.length == 4 && r.every((b) => b == 0)) return const LegacyAck();
    return LegacyUnknown(r);
  }
}
