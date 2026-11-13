import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../../core/key_store.dart';
import '../../core/tv_device.dart';
import '../../core/tv_driver.dart';
import '../../core/tv_key.dart';
import '../samsung/tcp_transport.dart';
import 'adb_auth.dart';
import 'adb_protocol.dart';

const adbPort = 5555;

const _adbOffMessage = 'Could not reach the Fire TV on port 5555. Turn on ADB debugging on it: '
    'Settings > My Fire TV > Developer options > ADB debugging. (If Developer options is '
    'missing, open About and click the Fire TV name seven times.) Also make sure the phone '
    'is on the same Wi-Fi network.';

const _deniedMessage = 'The Fire TV did not allow the connection. Retry, and choose OK on the '
    'Fire TV when it asks to allow debugging (tick "Always allow").';

/// Android key codes for the buttons a Fire TV can act on.
class FireTvKeyMap {
  static int? code(TvKey k) => switch (k) {
        TvKey.up => 19,
        TvKey.down => 20,
        TvKey.left => 21,
        TvKey.right => 22,
        TvKey.ok => 23,
        TvKey.back => 4,
        TvKey.home => 3,
        TvKey.menu => 82,
        TvKey.volumeUp => 24,
        TvKey.volumeDown => 25,
        TvKey.mute => 164,
        TvKey.rewind => 89,
        TvKey.play => 126,
        TvKey.pause => 127,
        TvKey.fastForward => 90,
        TvKey.power => 26,
        TvKey.channelUp || TvKey.channelDown || TvKey.input => null,
      };
}

class _Stream {
  _Stream(this.local, {required this.isKey});
  final int local;
  final bool isKey;
  int? remote;
}

/// Amazon Fire TV over ADB (Android Debug Bridge) on port 5555.
class FireTvDriver implements TvDriver {
  FireTvDriver(
    this.device,
    this._keys,
    this._makeTransport, {
    Future<AdbKey> Function()? makeKey,
    this.connectTimeout = const Duration(seconds: 5),
    this.pairingTimeout = const Duration(seconds: 60),
    this.ackTimeout = const Duration(seconds: 3),
    this.keyGate = const Duration(seconds: 1),
  }) : _makeKey = makeKey ?? generateAdbKey;

  static const _keyId = 'adb-key';

  final TvDevice device;
  final KeyStore _keys;
  final ByteTransport Function() _makeTransport;
  final Future<AdbKey> Function() _makeKey;
  final Duration connectTimeout;
  final Duration pairingTimeout;

  /// How long a silent device may take to acknowledge a command before the
  /// connection is considered dead.
  final Duration ackTimeout;

  /// A key command still running blocks further key presses for at most this long.
  final Duration keyGate;

  final _states = StreamController<TvConnectionState>.broadcast();
  ByteTransport? _transport;
  StreamSubscription<List<int>>? _sub;
  Future<void>? _connecting;
  Completer<void>? _ready;
  Timer? _timer;
  Timer? _ackTimer;
  int _pendingAcks = 0;
  bool _signed = false;
  bool _sentKey = false;
  bool _allowPairing = true;
  bool _disposed = false;
  AdbKey? _key; // kept in memory so storage trouble can't force a new key
  final _streams = <int, _Stream>{};
  int _nextLocal = 1;
  int? _keyStream;
  DateTime? _keyStreamStart;

  @override
  TvCapabilities get capabilities => TvCapabilities(
        TvKey.values.where((k) => FireTvKeyMap.code(k) != null).toSet(),
        typing: true,
      );

  @override
  Stream<TvConnectionState> get state => _states.stream;

  // Fire TV doesn't say when a text field is focused; the keyboard is opened by hand.
  @override
  Stream<bool> get keyboardFocus => const Stream<bool>.empty();

  void _emit(TvConnectionState s) {
    if (!_states.isClosed) _states.add(s);
  }

  void _checkDisposed() {
    if (_disposed) throw const TvConnectionError('Driver disposed');
  }

  @override
  Future<void> connect({bool pinPairing = false}) => _start(allowPairing: true);

  Future<void> _start({required bool allowPairing}) {
    if (_disposed) return Future.error(const TvConnectionError('Driver disposed'));
    return _connecting ??= _connect(allowPairing).whenComplete(() => _connecting = null);
  }

  Future<void> _connect(bool allowPairing) async {
    _emit(const Connecting());
    try {
      await _teardown();
      _allowPairing = allowPairing;
      final key = await _loadKey();
      _checkDisposed();
      await _handshake(key);
      _checkDisposed();
      _emit(const Connected());
    } catch (e) {
      final error = e is TvError ? e : const TvConnectionError();
      await _teardown();
      _emit(Failed(error));
      throw error;
    }
  }

  // Storage must never be able to break control of the device.
  Future<AdbKey> _loadKey() async {
    final cached = _key;
    if (cached != null) return cached;
    AdbKey? key;
    try {
      final raw = await _keys.read(_keyId);
      key = raw == null ? null : AdbKey.parse(raw);
    } catch (_) {}
    if (key == null) {
      key = await _makeKey(); // several seconds the first time
      _checkDisposed();
      try {
        await _keys.write(_keyId, key.serialize());
      } catch (_) {}
    }
    return _key = key;
  }

  Future<void> _closeQuietly(ByteTransport t) async {
    try {
      await t.close();
    } catch (_) {}
    if (identical(_transport, t)) _transport = null;
  }

  Future<void> _handshake(AdbKey key) async {
    final transport = _makeTransport();
    _transport = transport; // visible to _teardown/dispose while still opening
    try {
      await transport.open(device.host, adbPort).timeout(connectTimeout);
    } catch (_) {
      await _closeQuietly(transport);
      _checkDisposed();
      throw const TvConnectionError(_adbOffMessage);
    }
    if (_disposed) {
      await _closeQuietly(transport);
      _checkDisposed();
    }
    final ready = Completer<void>();
    _ready = ready;
    _signed = false;
    _sentKey = false;
    final parser = AdbFrameParser();
    _sub = transport.bytes.listen(
      (chunk) => _onBytes(transport, parser, ready, key, chunk),
      onDone: () => _onClosed(transport),
    );
    _startTimer(connectTimeout, ready,
        const TvConnectionError('The Fire TV did not answer. Is ADB debugging switched on?'));
    try {
      transport.send(encodeAdbMessage(
          AdbCommand.cnxn, adbVersion, adbMaxData, utf8.encode('host::\x00')));
      await ready.future;
    } finally {
      _timer?.cancel();
      if (identical(_ready, ready)) _ready = null;
    }
  }

  void _startTimer(Duration d, Completer<void> c, Object error) {
    _timer?.cancel();
    _timer = Timer(d, () {
      if (!c.isCompleted) c.completeError(error);
    });
  }

  void _onBytes(ByteTransport from, AdbFrameParser parser, Completer<void> ready, AdbKey key,
      List<int> chunk) {
    if (!identical(from, _transport)) return; // a socket we already let go of
    final List<AdbMessage> messages;
    try {
      messages = parser.add(chunk);
    } on FormatException {
      _protocolError(ready);
      return;
    }
    for (final m in messages) {
      if (!identical(from, _transport)) return;
      if (!ready.isCompleted) {
        _onHandshakeMessage(from, ready, key, m);
      } else {
        _onStreamMessage(from, m);
      }
    }
  }

  void _protocolError(Completer<void> ready) {
    const error = TvConnectionError('Unexpected data from the Fire TV');
    if (!ready.isCompleted) {
      ready.completeError(error);
    } else {
      _emit(const Disconnected());
      unawaited(_teardown());
    }
  }

  void _onHandshakeMessage(ByteTransport t, Completer<void> ready, AdbKey key, AdbMessage m) {
    if (m.command == AdbCommand.cnxn) {
      ready.complete();
      return;
    }
    if (m.command != AdbCommand.auth || m.arg0 != 1) return;
    if (m.data.length != 20) {
      ready.completeError(const TvConnectionError('Unexpected data from the Fire TV'));
      return;
    }
    if (!_signed) {
      _signed = true; // try the key we may already be trusted with
      t.send(encodeAdbMessage(AdbCommand.auth, 2, 0, adbSignToken(key, m.data)));
    } else if (!_sentKey) {
      if (!_allowPairing) {
        ready.completeError(const PairingDenied(
            'This Fire TV no longer trusts the app. Remove it and add it again.'));
        return;
      }
      _sentKey = true; // unknown key: the device shows its Allow box
      _emit(const AwaitingPairing());
      t.send(encodeAdbMessage(AdbCommand.auth, 3, 0, adbPublicKeyPayload(key)));
      _startTimer(pairingTimeout, ready, const PairingDenied('Pairing timed out'));
    } else {
      ready.completeError(const PairingDenied(_deniedMessage));
    }
  }

  void _onStreamMessage(ByteTransport t, AdbMessage m) {
    switch (m.command) {
      case AdbCommand.okay:
        final s = _streams[m.arg1];
        if (s != null && s.remote == null) {
          s.remote = m.arg0;
          _onAck();
        }
      case AdbCommand.wrte:
        _send(t, AdbCommand.okay, m.arg1, m.arg0); // output we don't need, but must acknowledge
      case AdbCommand.clse:
        final s = _streams.remove(m.arg1);
        if (s == null) return;
        if (s.remote == null) _onAck(); // refused before it was acknowledged
        if (_keyStream == s.local) _keyStream = null;
        _send(t, AdbCommand.clse, s.local, m.arg0);
    }
  }

  void _send(ByteTransport t, int command, int arg0, int arg1) {
    try {
      t.send(encodeAdbMessage(command, arg0, arg1, const []));
    } catch (_) {}
  }

  void _onClosed(ByteTransport from) {
    if (_disposed || !identical(from, _transport)) return;
    final ready = _ready;
    if (ready != null && !ready.isCompleted) {
      ready.completeError(_sentKey
          ? const PairingDenied(_deniedMessage)
          : const TvConnectionError('Connection to the Fire TV was lost'));
    }
    _emit(const Disconnected());
    unawaited(_teardown());
  }

  // Every command is acknowledged; silence means the connection is dead (the
  // device lost power or the network dropped) even though the socket looks open.
  void _expectAck() {
    _pendingAcks++;
    _ackTimer ??= Timer(ackTimeout, _onAckTimeout);
  }

  void _onAck() {
    if (_pendingAcks > 0) _pendingAcks--;
    _ackTimer?.cancel();
    _ackTimer = _pendingAcks > 0 ? Timer(ackTimeout, _onAckTimeout) : null;
  }

  void _onAckTimeout() {
    _ackTimer = null;
    _pendingAcks = 0;
    if (_disposed) return;
    _emit(const Disconnected());
    unawaited(_teardown());
  }

  Future<void> _teardown() async {
    _timer?.cancel();
    _ackTimer?.cancel();
    _ackTimer = null;
    _pendingAcks = 0;
    _streams.clear();
    _keyStream = null;
    final transport = _transport, sub = _sub;
    _transport = null;
    _sub = null;
    await sub?.cancel();
    try {
      await transport?.close();
    } catch (_) {}
  }

  bool get _alive => _transport?.isOpen ?? false;

  /// Reconnects (never pairing: there'd be no screen to confirm on). Returns true
  /// if another press was already reconnecting, in which case this press is dropped.
  Future<bool> _ensureAlive() async {
    if (_alive) return false;
    final joining = _connecting != null;
    await _start(allowPairing: false);
    return joining;
  }

  void _runShell(String command, {bool isKey = false}) {
    final transport = _transport;
    if (transport == null) throw const TvConnectionError();
    final local = _nextLocal++;
    _streams[local] = _Stream(local, isKey: isKey);
    if (isKey) {
      _keyStream = local;
      _keyStreamStart = DateTime.now();
    }
    try {
      transport.send(encodeAdbMessage(AdbCommand.open, local, 0, shellOpenData(command)));
    } catch (_) {
      throw const TvConnectionError();
    }
    _expectAck();
  }

  @override
  Future<void> sendKey(TvKey key) async {
    final code = FireTvKeyMap.code(key);
    if (code == null) throw const TvConnectionError('That button is not available on a Fire TV');
    // A reconnect was already underway for an earlier press: drop this one rather
    // than letting queued presses all fire at once on reconnect.
    if (await _ensureAlive()) return;
    // Each `input` call starts a process on the device, so held keys would pile up:
    // allow one key command at a time (a lost reply can block for at most [keyGate]).
    if (_keyStream != null &&
        DateTime.now().difference(_keyStreamStart ?? DateTime.now()) < keyGate) {
      return;
    }
    _runShell(inputKeyeventCommand([code]), isKey: true);
  }

  @override
  Future<void> sendText(String text) async {
    await _ensureAlive();
    final runes = text.runes.toList();
    for (var i = 0; i < runes.length; i += 100) {
      final cmd = inputTextCommand(String.fromCharCodes(runes.sublist(i, min(i + 100, runes.length))));
      if (cmd != null) _runShell(cmd);
    }
  }

  @override
  Future<void> deleteText(int count) async {
    await _ensureAlive();
    var left = count;
    while (left > 0) {
      final batch = min(left, 50);
      _runShell(inputKeyeventCommand(List.filled(batch, 67)));
      left -= batch;
    }
  }

  @override
  Future<void> sendEnter() async {
    await _ensureAlive();
    _runShell(inputKeyeventCommand([66]));
  }

  @override
  Future<void> submitPairingPin(String pin) async {}

  @override
  Future<String?> fetchMacAddress() async => null;

  @override
  Future<void> dispose() async {
    _disposed = true;
    final ready = _ready;
    if (ready != null && !ready.isCompleted) {
      ready.completeError(const TvConnectionError('Driver disposed'));
    }
    await _teardown();
    // Not awaited: nothing depends on it finishing.
    unawaited(_states.close());
  }
}
