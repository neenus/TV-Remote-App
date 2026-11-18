import 'dart:convert';
import 'dart:typed_data';

// The few protobuf messages of the Android TV Remote protocol v2 (polo pairing and
// remote control), hand-encoded. Field numbers follow the open-source
// androidtvremote2 library's .proto files and are checked against it in the tests.

const _maxMessage = 1024 * 1024;

Uint8List encodeVarint(int value) {
  assert(value >= 0);
  final out = <int>[];
  var v = value;
  while (v > 0x7f) {
    out.add((v & 0x7f) | 0x80);
    v >>= 7;
  }
  out.add(v);
  return Uint8List.fromList(out);
}

/// A message prefixed with its length as a varint (how the TV expects them on the wire).
Uint8List frameMessage(List<int> message) =>
    Uint8List.fromList([...encodeVarint(message.length), ...message]);

/// Reassembles length-delimited messages from arbitrary TCP chunks. Throws
/// [FormatException] if the stream is corrupt (the connection should be dropped).
class AtvFrameParser {
  final _buf = <int>[];

  List<Uint8List> add(List<int> chunk) {
    _buf.addAll(chunk);
    final out = <Uint8List>[];
    while (_buf.isNotEmpty) {
      var length = 0;
      var shift = 0;
      var pos = 0;
      var complete = false;
      while (pos < _buf.length && pos < 5) {
        final b = _buf[pos++];
        length |= (b & 0x7f) << shift;
        shift += 7;
        if (b & 0x80 == 0) {
          complete = true;
          break;
        }
      }
      if (!complete) {
        if (pos >= 5) {
          _buf.clear();
          throw const FormatException('Corrupt message length');
        }
        break; // the length itself isn't fully here yet
      }
      if (length > _maxMessage) {
        _buf.clear();
        throw const FormatException('Message too large');
      }
      if (_buf.length < pos + length) break;
      out.add(Uint8List.fromList(_buf.sublist(pos, pos + length)));
      _buf.removeRange(0, pos + length);
    }
    return out;
  }
}

// ---------------------------------------------------------------------------
// writing
// ---------------------------------------------------------------------------

List<int> _varintField(int field, int value) =>
    [...encodeVarint((field << 3) | 0), ...encodeVarint(value)];

List<int> _bytesField(int field, List<int> data) =>
    [...encodeVarint((field << 3) | 2), ...encodeVarint(data.length), ...data];

List<int> _stringField(int field, String s) => _bytesField(field, utf8.encode(s));

// polo OuterMessage: protocol_version = 2, status = STATUS_OK (200), then the payload.
Uint8List _outer(List<int> payload) =>
    Uint8List.fromList([..._varintField(1, 2), ..._varintField(2, 200), ...payload]);

List<int> _hexEncoding() => [..._varintField(1, 3), ..._varintField(2, 6)]; // HEX, 6 symbols

const _roleInput = 1;

Uint8List poloPairingRequest(String clientName) => _outer(_bytesField(10, [
      ..._stringField(1, 'atvremote'),
      ..._stringField(2, clientName),
    ]));

Uint8List poloOptions() => _outer(_bytesField(20, [
      ..._bytesField(1, _hexEncoding()),
      ..._varintField(3, _roleInput),
    ]));

Uint8List poloConfiguration() => _outer(_bytesField(30, [
      ..._bytesField(1, _hexEncoding()),
      ..._varintField(2, _roleInput),
    ]));

Uint8List poloSecret(List<int> secret) => _outer(_bytesField(40, _bytesField(1, secret)));

Uint8List remoteConfigure(int features) => Uint8List.fromList(_bytesField(1, [
      ..._varintField(1, features),
      ..._bytesField(2, [
        ..._varintField(3, 1),
        ..._stringField(4, '1'),
        ..._stringField(5, 'atvremote'),
        ..._stringField(6, '1.0.0'),
      ]),
    ]));

Uint8List remoteSetActive(int features) =>
    Uint8List.fromList(_bytesField(2, _varintField(1, features)));

Uint8List remotePingResponse(int value) =>
    Uint8List.fromList(_bytesField(9, _varintField(1, value)));

/// [direction] 3 is a short press.
Uint8List remoteKeyInject(int keyCode, {int direction = 3}) => Uint8List.fromList(
    _bytesField(10, [..._varintField(1, keyCode), ..._varintField(2, direction)]));

// ---------------------------------------------------------------------------
// reading
// ---------------------------------------------------------------------------

class _Field {
  _Field(this.number, {this.value, this.bytes});
  final int number;
  final int? value;
  final Uint8List? bytes;
}

List<_Field> _readFields(Uint8List data) {
  final fields = <_Field>[];
  var i = 0;

  int varint() {
    var result = 0;
    var shift = 0;
    while (true) {
      if (i >= data.length || shift > 63) throw const FormatException('Bad varint');
      final b = data[i++];
      result |= (b & 0x7f) << shift;
      if (b & 0x80 == 0) return result;
      shift += 7;
    }
  }

  while (i < data.length) {
    final tag = varint();
    final number = tag >> 3;
    switch (tag & 7) {
      case 0:
        fields.add(_Field(number, value: varint()));
      case 2:
        final len = varint();
        if (len < 0 || i + len > data.length) throw const FormatException('Truncated field');
        fields.add(_Field(number, bytes: Uint8List.sublistView(data, i, i + len)));
        i += len;
      case 1:
        if (i + 8 > data.length) throw const FormatException('Truncated field');
        i += 8;
      case 5:
        if (i + 4 > data.length) throw const FormatException('Truncated field');
        i += 4;
      default:
        throw const FormatException('Unsupported wire type');
    }
  }
  return fields;
}

_Field? _first(List<_Field> fields, int number) {
  for (final f in fields) {
    if (f.number == number) return f;
  }
  return null;
}

sealed class PoloMessage {
  const PoloMessage();
}

class PoloPairingRequestAck extends PoloMessage {
  const PoloPairingRequestAck();
}

class PoloOptions extends PoloMessage {
  const PoloOptions();
}

class PoloConfigurationAck extends PoloMessage {
  const PoloConfigurationAck();
}

class PoloSecretAck extends PoloMessage {
  const PoloSecretAck();
}

class PoloError extends PoloMessage {
  const PoloError(this.status);
  final int status;
}

class PoloOther extends PoloMessage {
  const PoloOther();
}

PoloMessage parsePolo(Uint8List data) {
  final fields = _readFields(data);
  final status = _first(fields, 2)?.value ?? 200;
  if (status != 200) return PoloError(status);
  if (_first(fields, 11) != null) return const PoloPairingRequestAck();
  if (_first(fields, 20) != null) return const PoloOptions();
  if (_first(fields, 31) != null) return const PoloConfigurationAck();
  if (_first(fields, 41) != null) return const PoloSecretAck();
  return const PoloOther();
}

sealed class RemoteIn {
  const RemoteIn();
}

class RemoteConfigureIn extends RemoteIn {
  const RemoteConfigureIn(this.features, {this.model, this.vendor});
  final int features;
  final String? model;
  final String? vendor;
}

class RemoteSetActiveIn extends RemoteIn {
  const RemoteSetActiveIn(this.features);
  final int features;
}

class RemotePingIn extends RemoteIn {
  const RemotePingIn(this.value);
  final int value;
}

class RemoteStartIn extends RemoteIn {
  const RemoteStartIn(this.started);
  final bool started;
}

class RemoteErrorIn extends RemoteIn {
  const RemoteErrorIn();
}

class RemoteOther extends RemoteIn {
  const RemoteOther();
}

String? _string(_Field? f) => f?.bytes == null ? null : utf8.decode(f!.bytes!, allowMalformed: true);

RemoteIn parseRemote(Uint8List data) {
  final fields = _readFields(data);
  final configure = _first(fields, 1)?.bytes;
  if (configure != null) {
    final inner = _readFields(configure);
    final info = _first(inner, 2)?.bytes;
    final infoFields = info == null ? const <_Field>[] : _readFields(info);
    return RemoteConfigureIn(_first(inner, 1)?.value ?? 0,
        model: _string(_first(infoFields, 1)), vendor: _string(_first(infoFields, 2)));
  }
  final active = _first(fields, 2)?.bytes;
  if (active != null) return RemoteSetActiveIn(_first(_readFields(active), 1)?.value ?? 0);
  if (_first(fields, 3) != null) return const RemoteErrorIn();
  final ping = _first(fields, 8)?.bytes;
  if (ping != null) return RemotePingIn(_first(_readFields(ping), 1)?.value ?? 0);
  final start = _first(fields, 40)?.bytes;
  if (start != null) return RemoteStartIn((_first(_readFields(start), 1)?.value ?? 0) != 0);
  return const RemoteOther();
}
