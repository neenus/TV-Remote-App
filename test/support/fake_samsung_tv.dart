import 'dart:async';
import 'dart:convert';

import 'package:tv_remote/drivers/lg/transport.dart';

/// A scripted Samsung TV: hands out transports and answers like Tizen would.
class FakeSamsungTv {
  final List<FakeSamsungTransport> transports = [];
  final List<Uri> openedUris = [];
  String tokenToIssue = '12345678';
  bool holdAllow = false; // the user hasn't pressed Allow yet
  bool deny = false; // the user pressed Deny
  bool rejectStoredToken = false; // sends unauthorized when a token is presented
  bool ignoreStoredToken = false; // says nothing when a token is presented
  bool secureFails = false; // wss:8002 not available
  bool openAlwaysFails = false;

  Transport make() {
    final t = FakeSamsungTransport(this);
    transports.add(t);
    return t;
  }

  /// The user presses Allow on the TV.
  void accept() {
    for (final t in transports) {
      if (t.isOpen) t.push(_connectEvent(t.uri!));
    }
  }

  String _connectEvent(Uri uri) => jsonEncode({
        'event': 'ms.channel.connect',
        'data': uri.scheme == 'wss' ? {'token': tokenToIssue} : {},
      });
}

class FakeSamsungTransport implements Transport {
  FakeSamsungTransport(this.tv);
  final FakeSamsungTv tv;
  final sent = <String>[];
  final _controller = StreamController<String>.broadcast();
  bool _open = false;
  Uri? uri;

  @override
  bool get isOpen => _open;

  @override
  Stream<String> get messages => _controller.stream;

  @override
  Future<void> open(Uri uri) async {
    tv.openedUris.add(uri);
    if (tv.openAlwaysFails ||
        (uri.scheme == 'wss' && tv.secureFails)) {
      throw Exception('connection refused');
    }
    this.uri = uri;
    _open = true;
    final hasToken = uri.queryParameters.containsKey('token');
    Timer(const Duration(milliseconds: 10), () {
      if (tv.deny) {
        push('{"event":"ms.channel.unauthorized"}');
      } else if (hasToken && tv.rejectStoredToken) {
        push('{"event":"ms.channel.unauthorized"}');
      } else if (hasToken && tv.ignoreStoredToken) {
        // silence
      } else if (tv.holdAllow && !hasToken) {
        // waiting for tv.accept()
      } else {
        push(tv._connectEvent(uri));
      }
    });
  }

  void push(String raw) => scheduleMicrotask(() {
        if (!_controller.isClosed) _controller.add(raw);
      });

  void closeFromRemote() {
    _open = false;
    _controller.close();
  }

  @override
  void send(String data) => sent.add(data);

  @override
  Future<void> close() async {
    _open = false;
    if (!_controller.isClosed) await _controller.close();
  }
}
