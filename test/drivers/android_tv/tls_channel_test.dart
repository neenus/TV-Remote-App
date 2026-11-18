@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/drivers/android_tv/atv_crypto.dart';
import 'package:tv_remote/drivers/android_tv/atv_transport.dart';

void main() {
  late AtvIdentity serverId;
  late AtvIdentity clientId;
  setUpAll(() {
    serverId = generateAtvIdentitySync(commonName: 'fake-tv');
    clientId = generateAtvIdentitySync(commonName: 'phone');
  });

  Future<SecureServerSocket> startServer() {
    final context = SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(utf8.encode(serverId.certPem))
      ..usePrivateKeyBytes(utf8.encode(serverId.keyPem))
      ..setTrustedCertificatesBytes(utf8.encode(clientId.certPem));
    return SecureServerSocket.bind(InternetAddress.loopbackIPv4, 0, context,
        requestClientCertificate: true);
  }

  test('connects_presenting_our_certificate_and_exposes_the_tvs', () async {
    final server = await startServer();
    final seenClientCert = Completer<List<int>?>();
    server.listen((s) {
      seenClientCert.complete(s.peerCertificate?.der);
      s.listen((d) => s.add(d)); // echo
    });
    final channel = TlsChannel();
    await channel.openSecure('127.0.0.1', server.port, clientId);
    expect(channel.isOpen, isTrue);
    expect(channel.peerCertificateDer, pemToDer(serverId.certPem));
    expect(await seenClientCert.future, pemToDer(clientId.certPem));
    final echoed = Completer<List<int>>();
    channel.bytes.listen(echoed.complete);
    channel.send([1, 2, 3]);
    expect(await echoed.future.timeout(const Duration(seconds: 3)), [1, 2, 3]);
    await channel.close();
    expect(channel.isOpen, isFalse);
    await server.close();
  });

  test('close_before_open_completes_does_not_leak_the_socket', () async {
    final server = await startServer();
    final serverSideClosed = Completer<void>();
    server.listen((s) => s.listen((_) {}, onDone: serverSideClosed.complete, onError: (_) => serverSideClosed.complete()));
    final channel = TlsChannel();
    final opening = channel.openSecure('127.0.0.1', server.port, clientId);
    await channel.close();
    await opening.then<void>((_) {}, onError: (Object _) {});
    await serverSideClosed.future.timeout(const Duration(seconds: 3));
    expect(channel.isOpen, isFalse);
    await server.close();
  });

  test('an_unreachable_port_is_an_error_not_a_hang', () async {
    final server = await startServer();
    final port = server.port;
    await server.close();
    await expectLater(
        TlsChannel(timeout: const Duration(seconds: 2)).openSecure('127.0.0.1', port, clientId),
        throwsA(anything));
  });

  test('a_server_that_drops_the_connection_ends_the_stream', () async {
    final server = await startServer();
    server.listen((s) => s.destroy());
    final channel = TlsChannel();
    await channel.openSecure('127.0.0.1', server.port, clientId);
    await channel.bytes.isEmpty.timeout(const Duration(seconds: 3));
    expect(channel.isOpen, isFalse);
    channel.send([1]); // must not throw
    await server.close();
  });
}
