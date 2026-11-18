import 'dart:async';
import 'dart:io';

/// A raw TCP connection (the legacy Samsung protocol is not WebSocket).
abstract class ByteTransport {
  Future<void> open(String host, int port);
  Stream<List<int>> get bytes;
  void send(List<int> data);
  Future<void> close();
  bool get isOpen;
}

class TcpTransport implements ByteTransport {
  Socket? _socket;
  bool _closed = false;
  bool _open = false;
  final _controller = StreamController<List<int>>.broadcast();

  @override
  bool get isOpen => _open;

  @override
  Stream<List<int>> get bytes => _controller.stream;

  @override
  Future<void> open(String host, int port) async {
    final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
    if (_closed) {
      // close() ran while we were still connecting: don't leave a live socket behind.
      socket.destroy();
      throw StateError('Transport closed while opening');
    }
    _socket = socket; // stored first so close() can always reach it
    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {}
    _open = true;
    // Write failures (e.g. the TV reset the connection) surface on `done`; handle
    // them here so they never become uncaught errors.
    unawaited(socket.done.then<void>((_) {}, onError: (Object _) {}));
    void finish() {
      _open = false;
      if (!_controller.isClosed) _controller.close();
    }

    socket.listen(
      (d) {
        if (!_controller.isClosed) _controller.add(d);
      },
      onDone: finish,
      onError: (_) => finish(),
      cancelOnError: true,
    );
  }

  @override
  void send(List<int> data) {
    try {
      _socket?.add(data);
    } catch (_) {}
  }

  @override
  Future<void> close() async {
    _closed = true;
    _open = false;
    _socket?.destroy();
    if (!_controller.isClosed) await _controller.close();
  }
}
