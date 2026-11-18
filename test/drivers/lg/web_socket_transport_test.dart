import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/drivers/lg/transport.dart';

void main() {
  test('close_before_open_completes_does_not_leak_the_socket', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serverSideClosed = Completer<void>();
    server.listen((req) async {
      final ws = await WebSocketTransformer.upgrade(req);
      ws.listen((_) {}, onDone: serverSideClosed.complete);
    });
    final t = WebSocketTransport();
    final opening = t.open(Uri.parse('ws://127.0.0.1:${server.port}/'));
    await t.close(); // e.g. connect timed out and the driver tore down
    await opening.catchError((_) {});
    await serverSideClosed.future.timeout(const Duration(seconds: 2));
    expect(t.isOpen, isFalse);
    await server.close(force: true);
  });
}
