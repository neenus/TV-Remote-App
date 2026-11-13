import 'dart:async';
import 'dart:convert';

import 'package:tv_remote/drivers/lg/transport.dart';

/// A scripted LG TV: hands out FakeTransports and answers like webOS would.
class FakeTv {
  final List<FakeTransport> transports = [];
  String clientKeyToIssue = 'abc';
  bool denyPairing = false;
  bool rejectStoredKeys = false;
  bool silent = false;
  bool promptFirst = false;
  bool openFails = false;
  bool promptOnly = false; // shows the prompt, then never answers
  bool promptThenDeny = false;
  bool pointerError = false;
  bool macSilent = false;
  bool macError = false;
  Map<String, dynamic> macPayload = {
    'returnValue': true,
    'wiredInfo': {'macAddress': 'AA:BB:CC:DD:EE:FF', 'ipAddress': 'tv', 'state': 'connected'},
  };

  Transport make() {
    final t = FakeTransport(this);
    transports.add(t);
    return t;
  }

  FakeTransport get main => transports.first;
  Iterable<Map> registerMessages() => main.sent
      .map((s) => jsonDecode(s) as Map)
      .where((m) => m['type'] == 'register');
}

class FakeTransport implements Transport {
  FakeTransport(this.tv);
  final FakeTv tv;
  final sent = <String>[];
  final _controller = StreamController<String>.broadcast();
  bool _open = false;
  Uri? uri;

  bool get isMain => uri != null && !uri!.path.contains('netinput');

  @override
  bool get isOpen => _open;

  @override
  Stream<String> get messages => _controller.stream;

  @override
  Future<void> open(Uri uri) async {
    if (tv.openFails) throw Exception('connection refused');
    this.uri = uri;
    _open = true;
  }

  void push(String raw) => scheduleMicrotask(() {
        if (!_controller.isClosed) _controller.add(raw);
      });

  void closeFromRemote() {
    _open = false;
    _controller.close();
  }

  @override
  void send(String data) {
    sent.add(data);
    if (!isMain || tv.silent) return;
    final Object? m = jsonDecode(data);
    if (m is! Map) return;
    if (m['type'] == 'register') {
      final payload = m['payload'] as Map;
      if (tv.promptOnly) {
        push('{"type":"response","id":"register_0","payload":{"pairingType":"PROMPT","returnValue":true}}');
        return;
      }
      if (tv.promptThenDeny) {
        push('{"type":"response","id":"register_0","payload":{"pairingType":"PROMPT","returnValue":true}}');
        push('{"type":"error","id":"register_0","error":"403 User denied access"}');
        return;
      }
      if (tv.rejectStoredKeys && payload.containsKey('client-key')) {
        push('{"type":"error","id":"register_0","error":"403 forbidden"}');
      } else if (tv.denyPairing) {
        push('{"type":"error","id":"register_0","error":"403 User denied access"}');
      } else {
        if (tv.promptFirst) {
          push('{"type":"response","id":"register_0","payload":{"pairingType":"PROMPT","returnValue":true}}');
        }
        push('{"type":"registered","id":"register_0","payload":{"client-key":"${tv.clientKeyToIssue}"}}');
      }
    } else if (m['type'] == 'request' && m['id'] == 'mac') {
      if (tv.macSilent) return;
      push(tv.macError
          ? '{"type":"error","id":"mac","error":"404 no such service"}'
          : jsonEncode({'type': 'response', 'id': 'mac', 'payload': tv.macPayload}));
    } else if (m['type'] == 'request' && m['id'] == 'pointer') {
      if (tv.pointerError) {
        push('{"type":"error","id":"pointer","error":"401 insufficient permissions"}');
        return;
      }
      push('{"type":"response","id":"pointer","payload":{"returnValue":true,"socketPath":"wss://tv:3001/resources/x/netinput_pointer.sock"}}');
    }
  }

  @override
  Future<void> close() async {
    _open = false;
    if (!_controller.isClosed) await _controller.close();
  }
}
