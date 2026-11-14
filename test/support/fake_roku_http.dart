import 'dart:async';
import 'dart:io';

import 'package:tv_remote/drivers/samsung/samsung_encrypted_http.dart';

const rokuInfoXml = '''<?xml version="1.0" encoding="UTF-8" ?>
<device-info>
  <udn>29ee4d6c-0000-1000-8000-b0a737123456</udn>
  <serial-number>X00A123456</serial-number>
  <friendly-device-name>Living Room &amp; Den</friendly-device-name>
  <model-name>Roku Ultra</model-name>
  <network-type>wifi</network-type>
  <wifi-mac>b0:a7:37:12:34:56</wifi-mac>
  <ethernet-mac>b0:a7:37:12:34:57</ethernet-mac>
  <power-mode>PowerOn</power-mode>
</device-info>''';

typedef RokuRequest = ({String method, Uri uri, String? body});

/// A scripted Roku answering ECP on port 8060.
class FakeRokuHttp implements SamsungHttp {
  final requests = <RokuRequest>[];
  String infoBody = rokuInfoXml;
  int infoStatus = 200;
  int keypressStatus = 200;
  bool failAll = false;
  bool failKeypress = false;
  bool throwOther = false; // an unexpected (non-network) exception
  Duration firstKeypressDelay = Duration.zero;
  Duration infoDelay = Duration.zero;
  int _keypresses = 0;

  List<String> get keys => [
        for (final r in requests)
          if (r.method == 'POST' && r.uri.path.startsWith('/keypress/'))
            Uri.decodeComponent(r.uri.path.substring('/keypress/'.length))
      ];

  @override
  Future<HttpReply> send(String method, Uri uri, {String? body}) async {
    requests.add((method: method, uri: uri, body: body));
    if (throwOther) throw StateError('boom');
    if (failAll) throw const SocketException('unreachable');
    if (uri.path == '/query/device-info' && method == 'GET') {
      if (infoDelay > Duration.zero) await Future<void>.delayed(infoDelay);
      return HttpReply(infoStatus, infoBody);
    }
    if (uri.path.startsWith('/keypress/') && method == 'POST') {
      if (failKeypress) throw const SocketException('connection reset');
      if (_keypresses++ == 0 && firstKeypressDelay > Duration.zero) {
        await Future<void>.delayed(firstKeypressDelay);
      }
      return HttpReply(keypressStatus, '');
    }
    return const HttpReply(404, '');
  }
}
