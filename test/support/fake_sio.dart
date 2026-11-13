import 'dart:async';

import 'package:tv_remote/drivers/lg/transport.dart';

/// Hands out socket.io-style transports for the Samsung H/J control channel.
class FakeSioTv {
  final List<FakeSioTransport> transports = [];
  bool openFails = false;
  Duration openDelay = Duration.zero;

  Transport make() {
    final t = FakeSioTransport(this);
    transports.add(t);
    return t;
  }
}

class FakeSioTransport implements Transport {
  FakeSioTransport(this.tv);
  final FakeSioTv tv;
  final sent = <String>[];
  final _controller = StreamController<String>.broadcast();
  bool _open = false;
  Uri? uri;

  @override
  bool get isOpen => _open;

  @override
  Stream<String> get messages => _controller.stream;

  @override
  Future<void> open(Uri uri) async {
    if (tv.openDelay > Duration.zero) await Future<void>.delayed(tv.openDelay);
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
  void send(String data) => sent.add(data);

  @override
  Future<void> close() async {
    _open = false;
    if (!_controller.isClosed) await _controller.close();
  }
}
