import 'dart:async';
import 'dart:convert';

import 'package:tv_remote/drivers/samsung/tcp_transport.dart';

List<int> legacyFrame(List<int> resp, {String name = 'TV'}) {
  final n = utf8.encode(name);
  return [0x00, n.length & 0xff, n.length >> 8, ...n, resp.length & 0xff, resp.length >> 8, ...resp];
}

enum LegacyMode { grant, waitThenGrant, deny, cancel, silent, waitThenSilence, garbage }

/// A scripted pre-2016 Samsung TV.
class FakeLegacyTv {
  LegacyMode mode = LegacyMode.grant;
  bool openFails = false;
  bool chunked = false; // deliver replies one byte at a time
  Duration openDelay = Duration.zero;
  final List<FakeByteTransport> transports = [];

  ByteTransport make() {
    final t = FakeByteTransport(this);
    transports.add(t);
    return t;
  }

  /// The user presses Allow on the TV.
  void accept() {
    for (final t in transports) {
      if (t.isOpen) t.push(legacyFrame([0x64, 0, 1, 0]));
    }
  }
}

class FakeByteTransport implements ByteTransport {
  FakeByteTransport(this.tv);
  final FakeLegacyTv tv;
  final sent = <List<int>>[];
  final _controller = StreamController<List<int>>.broadcast();
  bool _open = false;
  String? host;
  int? port;

  @override
  bool get isOpen => _open;

  @override
  Stream<List<int>> get bytes => _controller.stream;

  @override
  Future<void> open(String host, int port) async {
    if (tv.openDelay > Duration.zero) await Future<void>.delayed(tv.openDelay);
    if (tv.openFails) throw Exception('connection refused');
    this.host = host;
    this.port = port;
    _open = true;
  }

  void push(List<int> data) => Timer(const Duration(milliseconds: 5), () {
        if (_controller.isClosed) return;
        if (tv.chunked) {
          for (final b in data) {
            _controller.add([b]);
          }
        } else {
          _controller.add(data);
        }
      });

  void closeFromRemote() {
    _open = false;
    _controller.close();
  }

  @override
  void send(List<int> data) {
    sent.add(data);
    if (sent.length > 1) {
      push(legacyFrame([0, 0, 0, 0])); // key accepted
      return;
    }
    switch (tv.mode) {
      case LegacyMode.grant:
        push(legacyFrame([0x64, 0, 1, 0]));
      case LegacyMode.waitThenGrant:
      case LegacyMode.waitThenSilence:
        push(legacyFrame([0x0a, 0]));
      case LegacyMode.deny:
        push(legacyFrame([0x64, 0, 0, 0]));
      case LegacyMode.cancel:
        push(legacyFrame([0x65, 0]));
      case LegacyMode.garbage:
        push(legacyFrame([1, 2, 3, 4]));
      case LegacyMode.silent:
        break;
    }
  }

  @override
  Future<void> close() async {
    _open = false;
    if (!_controller.isClosed) await _controller.close();
  }
}
