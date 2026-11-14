import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'atv_crypto.dart';

/// A TLS connection to an Android TV that presents our certificate.
abstract class AtvChannel {
  /// Opens the connection. The TV's certificate is not checked against any
  /// authority (it is self-signed): the pairing code is what establishes trust.
  Future<void> openSecure(String host, int port, AtvIdentity identity);
  Stream<List<int>> get bytes;
  void send(List<int> data);
  Future<void> close();
  bool get isOpen;

  /// The TV's certificate (DER), needed to compute the pairing secret.
  Uint8List? get peerCertificateDer;
}

class TlsChannel implements AtvChannel {
  TlsChannel({this.timeout = const Duration(seconds: 5)});
  final Duration timeout;

  SecureSocket? _socket;
  bool _closed = false;
  bool _open = false;
  Uint8List? _peer;
  final _controller = StreamController<List<int>>.broadcast();

  @override
  bool get isOpen => _open;

  @override
  Stream<List<int>> get bytes => _controller.stream;

  @override
  Uint8List? get peerCertificateDer => _peer;

  @override
  Future<void> openSecure(String host, int port, AtvIdentity identity) async {
    final context = SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(utf8.encode(identity.certPem))
      ..usePrivateKeyBytes(utf8.encode(identity.keyPem));
    final socket = await SecureSocket.connect(host, port,
        context: context, onBadCertificate: (_) => true, timeout: timeout);
    if (_closed) {
      // close() ran while we were still connecting: don't leave a live socket behind.
      socket.destroy();
      throw StateError('Channel closed while opening');
    }
    _socket = socket; // stored first so close() can always reach it
    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {}
    final peer = socket.peerCertificate;
    _peer = peer == null ? null : Uint8List.fromList(peer.der);
    _open = true;
    void finish() {
      _open = false;
      if (!_controller.isClosed) _controller.close();
    }

    // Write failures surface on `done`; handle them so they never become uncaught.
    unawaited(socket.done.then<void>((_) {}, onError: (Object _) {}));
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
