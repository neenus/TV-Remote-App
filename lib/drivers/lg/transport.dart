import 'dart:async';
import 'dart:io';

abstract class Transport {
  Future<void> open(Uri uri);
  Stream<String> get messages;
  void send(String data);
  Future<void> close();
  bool get isOpen;
}

/// WebSocket transport for LG webOS. The TV serves a self-signed certificate on
/// its LAN-only wss port, so certificate errors are accepted for this socket.
class WebSocketTransport implements Transport {
  WebSocket? _ws;
  final _controller = StreamController<String>.broadcast();

  @override
  bool get isOpen => _ws?.readyState == WebSocket.open;

  @override
  Stream<String> get messages => _controller.stream;

  @override
  Future<void> open(Uri uri) async {
    final client = HttpClient()..badCertificateCallback = (_, _, _) => true;
    final ws = await WebSocket.connect(uri.toString(), customClient: client);
    _ws = ws;
    ws.listen(
      (e) {
        if (!_controller.isClosed) _controller.add(e.toString());
      },
      onDone: () {
        if (!_controller.isClosed) _controller.close();
      },
      onError: (_) {
        if (!_controller.isClosed) _controller.close();
      },
      cancelOnError: true,
    );
  }

  @override
  void send(String data) => _ws?.add(data);

  @override
  Future<void> close() async {
    await _ws?.close();
    if (!_controller.isClosed) await _controller.close();
  }
}
