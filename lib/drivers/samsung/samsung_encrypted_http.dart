import 'dart:async';
import 'dart:convert';
import 'dart:io';

class HttpReply {
  const HttpReply(this.status, this.body);
  final int status;
  final String body;
}

/// The little HTTP client the pairing steps need (injectable for tests).
abstract class SamsungHttp {
  Future<HttpReply> send(String method, Uri uri, {String? body});
}

class IoSamsungHttp implements SamsungHttp {
  IoSamsungHttp({this.timeout = const Duration(seconds: 5)});
  final Duration timeout;

  @override
  Future<HttpReply> send(String method, Uri uri, {String? body}) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.openUrl(method, uri).timeout(timeout);
      if (body != null) {
        request.headers.contentType = ContentType('text', 'plain', charset: 'utf-8');
        request.write(body);
      }
      final response = await request.close().timeout(timeout);
      final text = await response.transform(utf8.decoder).join().timeout(timeout);
      return HttpReply(response.statusCode, text);
    } finally {
      client.close(force: true);
    }
  }
}
