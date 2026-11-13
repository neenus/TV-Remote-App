import 'dart:io';

import 'package:tv_remote/drivers/samsung/samsung_encrypted_http.dart';

typedef RecordedRequest = ({String method, Uri uri, String? body});

/// A scripted Samsung H/J TV's pairing web server (port 8080).
class FakeSamsungHttp implements SamsungHttp {
  final requests = <RecordedRequest>[];
  String pinPageState = 'stopped';
  String clientHello = '';
  String clientAck = '';
  String sessionId = '1';
  bool failAll = false;
  bool emptyAuthData = false; // the PIN window expired
  bool noClientHello = false; // step 1 reply without a hello (wrong PIN on some TVs)

  Iterable<RecordedRequest> where(String method, String pathContains) =>
      requests.where((r) => r.method == method && r.uri.path.contains(pathContains));

  @override
  Future<HttpReply> send(String method, Uri uri, {String? body}) async {
    requests.add((method: method, uri: uri, body: body));
    if (failAll) throw const SocketException('unreachable');
    final path = uri.path;
    if (path == '/ws/apps/CloudPINPage' && method == 'GET') {
      return HttpReply(200,
          '<?xml version="1.0"?><service><name>CloudPINPage</name><state>$pinPageState</state></service>');
    }
    if (path == '/ws/apps/CloudPINPage' && method == 'POST') {
      pinPageState = 'running';
      return const HttpReply(201, '');
    }
    if (path == '/ws/apps/CloudPINPage/run' && method == 'DELETE') {
      pinPageState = 'stopped';
      return const HttpReply(200, '');
    }
    if (path == '/ws/pairing') {
      switch (uri.queryParameters['step']) {
        case '0':
          return const HttpReply(200, '');
        case '1':
          if (noClientHello) return const HttpReply(200, '{"auth_data":""}');
          return HttpReply(200,
              '{"auth_data":"{\\"auth_Data\\":{\\"auth_type\\":\\"SPC\\",\\"request_id\\":\\"0\\",\\"GeneratorClientHello\\":\\"$clientHello\\"}}"}');
        case '2':
          if (emptyAuthData) return const HttpReply(200, '{"auth_data":""}');
          return HttpReply(200,
              '{"auth_data":"{\\"auth_Data\\":{\\"auth_type\\":\\"SPC\\",\\"request_id\\":\\"0\\",\\"ClientAckMsg\\":\\"$clientAck\\",\\"session_id\\":\\"$sessionId\\"}}"}');
      }
    }
    return const HttpReply(404, '');
  }
}
