import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/drivers/samsung/tcp_transport.dart';

void main() {
  test('close_before_open_completes_does_not_leak_the_socket', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final serverSideClosed = Completer<void>();
    server.listen((s) => s.listen((_) {}, onDone: serverSideClosed.complete));
    final t = TcpTransport();
    final opening = t.open('127.0.0.1', server.port);
    await t.close(); // e.g. the connect timed out and the driver tore down
    await opening.catchError((_) {});
    await serverSideClosed.future.timeout(const Duration(seconds: 2));
    expect(t.isOpen, isFalse);
    await server.close();
  });

  test('bytes_round_trip', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((s) => s.listen(s.add));
    final t = TcpTransport();
    await t.open('127.0.0.1', server.port);
    final received = Completer<List<int>>();
    t.bytes.listen(received.complete);
    t.send([1, 2, 3]);
    expect(await received.future.timeout(const Duration(seconds: 2)), [1, 2, 3]);
    await t.close();
    await server.close();
  });

  test('sending_on_a_closed_transport_does_not_throw', () async {
    final t = TcpTransport();
    t.send([1]);
  });
}
