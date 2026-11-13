import 'dart:convert';
import 'dart:typed_data';

/// The Android Debug Bridge wire format (as used over TCP, port 5555).
class AdbCommand {
  static const sync = 0x434e5953;
  static const cnxn = 0x4e584e43;
  static const auth = 0x48545541;
  static const open = 0x4e45504f;
  static const okay = 0x59414b4f;
  static const clse = 0x45534c43;
  static const wrte = 0x45545257;
  static const stls = 0x534c5453; // TLS upgrade (wireless-debugging pairing)
}

const adbVersion = 0x01000000;
const adbMaxData = 256 * 1024;

/// Larger payloads than this are treated as corruption rather than buffered.
const _maxPayload = 1024 * 1024;
const _headerSize = 24;

class AdbMessage {
  const AdbMessage(this.command, this.arg0, this.arg1, this.data);
  final int command;
  final int arg0;
  final int arg1;
  final Uint8List data;
}

Uint8List encodeAdbMessage(int command, int arg0, int arg1, List<int> data) {
  final out = Uint8List(_headerSize + data.length);
  final bd = out.buffer.asByteData();
  var checksum = 0;
  for (final b in data) {
    checksum = (checksum + b) & 0xffffffff;
  }
  bd.setUint32(0, command, Endian.little);
  bd.setUint32(4, arg0, Endian.little);
  bd.setUint32(8, arg1, Endian.little);
  bd.setUint32(12, data.length, Endian.little);
  bd.setUint32(16, checksum, Endian.little);
  bd.setUint32(20, (command ^ 0xffffffff) & 0xffffffff, Endian.little);
  out.setRange(_headerSize, out.length, data);
  return out;
}

/// Reassembles ADB messages from arbitrary TCP chunks. Throws [FormatException]
/// on a corrupt stream (the caller should drop the connection).
class AdbFrameParser {
  final _buf = <int>[];

  List<AdbMessage> add(List<int> chunk) {
    _buf.addAll(chunk);
    final out = <AdbMessage>[];
    while (_buf.length >= _headerSize) {
      final header = Uint8List.fromList(_buf.sublist(0, _headerSize));
      final bd = header.buffer.asByteData();
      final command = bd.getUint32(0, Endian.little);
      final length = bd.getUint32(12, Endian.little);
      final magic = bd.getUint32(20, Endian.little);
      if (((command ^ 0xffffffff) & 0xffffffff) != magic) {
        _buf.clear();
        throw const FormatException('Corrupt ADB message (bad magic)');
      }
      if (length > _maxPayload) {
        _buf.clear();
        throw const FormatException('Corrupt ADB message (payload too large)');
      }
      if (_buf.length < _headerSize + length) break;
      final data = Uint8List.fromList(_buf.sublist(_headerSize, _headerSize + length));
      _buf.removeRange(0, _headerSize + length);
      out.add(AdbMessage(command, bd.getUint32(4, Endian.little),
          bd.getUint32(8, Endian.little), data));
    }
    return out;
  }
}

/// Data for an OPEN message that runs a shell command.
Uint8List shellOpenData(String command) =>
    Uint8List.fromList([...utf8.encode('shell:$command'), 0]);

/// Cuts [text] between every '%' and a following 's', because Android's
/// `input text` turns the two-character sequence "%s" into a space and there is
/// no way to escape it. Each piece goes in a separate command.
List<String> splitForInput(String text) {
  final parts = <String>[];
  var start = 0;
  for (var i = 0; i < text.length - 1; i++) {
    if (text[i] == '%' && text[i + 1] == 's') {
      parts.add(text.substring(start, i + 1));
      start = i + 1;
    }
  }
  if (start < text.length) parts.add(text.substring(start));
  return parts;
}

String inputKeyeventCommand(List<int> keycodes) => 'input keyevent ${keycodes.join(' ')}';

/// `input text` for [text], or null if nothing in it can be typed. Only printable
/// ASCII is supported by Android's `input text`; everything else is dropped. The
/// text is single-quoted so the shell can't interpret any of it.
String? inputTextCommand(String text) {
  final typeable = StringBuffer();
  for (final r in text.runes) {
    if (r < 0x20 || r > 0x7e) continue;
    typeable.write(r == 0x20 ? '%s' : String.fromCharCode(r)); // %s is how `input` writes a space
  }
  if (typeable.isEmpty) return null;
  return "input text '${typeable.toString().replaceAll("'", "'\\''")}'";
}
