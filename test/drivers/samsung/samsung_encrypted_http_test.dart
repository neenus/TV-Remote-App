import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/drivers/samsung/samsung_encrypted_http.dart';

void main() {
  late HttpServer server;
  late Uri base;
  final seen = <({String method, String? transferEncoding, int contentLength, String body})>[];
  late FutureOr<void> Function(HttpRequest) handler;

  setUp(() async {
    seen.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri.parse('http://127.0.0.1:${server.port}/x');
    handler = (r) async {
      r.response.write('ok');
      await r.response.close();
    };
    server.listen((r) async {
      final body = await utf8.decoder.bind(r).join();
      seen.add((
        method: r.method,
        transferEncoding: r.headers.value('transfer-encoding'),
        contentLength: r.contentLength,
        body: body,
      ));
      await handler(r);
    });
  });
  tearDown(() => server.close(force: true));

  test('post_bodies_have_a_content_length_and_are_not_chunked', () async {
    final reply = await IoSamsungHttp().send('POST', base, body: 'pin4');
    expect(reply.status, 200);
    expect(seen.single.body, 'pin4');
    expect(seen.single.contentLength, 4);
    expect(seen.single.transferEncoding, isNull);
  });

  test('non_ascii_bodies_are_measured_in_bytes', () async {
    await IoSamsungHttp().send('POST', base, body: 'é');
    expect(seen.single.contentLength, 2);
  });

  test('requests_without_a_body_send_no_body', () async {
    await IoSamsungHttp().send('GET', base);
    expect(seen.single.method, 'GET');
    expect(seen.single.body, isEmpty);
  });

  test('error_statuses_are_returned_not_thrown', () async {
    handler = (r) async {
      r.response.statusCode = 404;
      await r.response.close();
    };
    expect((await IoSamsungHttp().send('GET', base)).status, 404);
  });

  test('a_malformed_utf8_reply_does_not_throw', () async {
    handler = (r) async {
      r.response.add([0x68, 0x69, 0xff, 0xfe]);
      await r.response.close();
    };
    final reply = await IoSamsungHttp().send('GET', base);
    expect(reply.body, startsWith('hi'));
  });
}
