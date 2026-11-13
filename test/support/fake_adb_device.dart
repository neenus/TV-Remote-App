import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:tv_remote/drivers/fire_tv/adb_auth.dart';
import 'package:tv_remote/drivers/fire_tv/adb_protocol.dart';
import 'package:tv_remote/drivers/samsung/tcp_transport.dart';

enum AdbMode { trusted, knownKey, unknownKey, silent }

/// A scripted Fire TV speaking ADB over TCP.
class FakeAdbDevice {
  AdbMode mode = AdbMode.trusted;
  AdbKey? trustedKey; // knownKey mode: the key it already trusts
  bool holdAllow = false; // unknownKey: wait for the user to press Allow
  bool denyPrompt = false; // close the socket after receiving the public key
  bool rejectAfterPubkey = false; // answer the public key with another token
  bool openFails = false;
  Duration openDelay = Duration.zero;
  bool neverAckOpen = false; // never answers OPEN with OKAY
  bool neverClose = false; // never ends a shell stream with CLSE
  bool output = false; // writes some output before closing
  final List<FakeAdbTransport> transports = [];
  final List<String> commands = []; // shell commands received
  final List<Uint8List> publicKeysSeen = [];
  int okaysFromClient = 0;
  int closesFromClient = 0;

  static final token = Uint8List.fromList(List.generate(20, (i) => i + 1));

  ByteTransport make() {
    final t = FakeAdbTransport(this);
    transports.add(t);
    return t;
  }

  /// The user presses Allow on the Fire TV.
  void accept() {
    for (final t in transports) {
      if (t.isOpen) t.sendCnxn();
    }
  }
}

class FakeAdbTransport implements ByteTransport {
  FakeAdbTransport(this.device);
  final FakeAdbDevice device;
  final _controller = StreamController<List<int>>.broadcast();
  final _parser = AdbFrameParser();
  bool _open = false;
  String? host;
  int? port;
  final sent = <AdbMessage>[];

  @override
  bool get isOpen => _open;

  @override
  Stream<List<int>> get bytes => _controller.stream;

  @override
  Future<void> open(String host, int port) async {
    if (device.openDelay > Duration.zero) await Future<void>.delayed(device.openDelay);
    if (device.openFails) throw Exception('connection refused');
    this.host = host;
    this.port = port;
    _open = true;
  }

  void push(List<int> data) => Timer(const Duration(milliseconds: 5), () {
        if (!_controller.isClosed) _controller.add(data);
      });

  void reply(int command, int arg0, int arg1, [List<int> data = const []]) =>
      push(encodeAdbMessage(command, arg0, arg1, data));

  void sendCnxn() => reply(AdbCommand.cnxn, adbVersion, adbMaxData, utf8.encode('device::\x00'));

  void closeFromRemote() {
    _open = false;
    _controller.close();
  }

  @override
  Future<void> close() async {
    _open = false;
    if (!_controller.isClosed) await _controller.close();
  }

  @override
  void send(List<int> data) {
    for (final m in _parser.add(data)) {
      sent.add(m);
      _handle(m);
    }
  }

  void _handle(AdbMessage m) {
    switch (m.command) {
      case AdbCommand.cnxn:
        switch (device.mode) {
          case AdbMode.trusted:
            sendCnxn();
          case AdbMode.knownKey || AdbMode.unknownKey:
            reply(AdbCommand.auth, 1, 0, FakeAdbDevice.token);
          case AdbMode.silent:
            break;
        }
      case AdbCommand.auth:
        if (m.arg0 == 2) {
          final key = device.trustedKey;
          final ok = device.mode == AdbMode.knownKey &&
              key != null &&
              _same(m.data, adbSignToken(key, FakeAdbDevice.token));
          ok ? sendCnxn() : reply(AdbCommand.auth, 1, 0, FakeAdbDevice.token);
        } else if (m.arg0 == 3) {
          device.publicKeysSeen.add(m.data);
          if (device.denyPrompt) {
            closeFromRemote();
          } else if (device.rejectAfterPubkey) {
            reply(AdbCommand.auth, 1, 0, FakeAdbDevice.token);
          } else if (!device.holdAllow) {
            sendCnxn();
          }
        }
      case AdbCommand.open:
        final local = m.arg0;
        var text = utf8.decode(m.data, allowMalformed: true);
        if (text.endsWith('\x00')) text = text.substring(0, text.length - 1);
        device.commands.add(text.startsWith('shell:') ? text.substring(6) : text);
        if (!device.neverAckOpen) reply(AdbCommand.okay, 100 + local, local);
        if (device.output) reply(AdbCommand.wrte, 100 + local, local, utf8.encode('out'));
        if (!device.neverClose) reply(AdbCommand.clse, 100 + local, local);
      case AdbCommand.okay:
        device.okaysFromClient++;
      case AdbCommand.clse:
        device.closesFromClient++;
    }
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
