import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/key_store.dart';
import '../../core/tv_device.dart';
import '../../core/tv_driver.dart';
import '../../core/tv_key.dart';
import '../lg/transport.dart';
import 'samsung_protocol.dart';

class _TokenRejected implements Exception {}

typedef JsonFetcher = Future<Map<String, dynamic>?> Function(Uri uri);

/// Plain HTTP GET returning a JSON object, or null on any failure.
Future<Map<String, dynamic>?> defaultFetchJson(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  try {
    final request = await client.getUrl(uri);
    final response = await request.close().timeout(const Duration(seconds: 3));
    final body = await response.transform(utf8.decoder).join();
    final json = jsonDecode(body);
    return json is Map<String, dynamic> ? json : null;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// Samsung Tizen (2016+) remote control over the WebSocket remote API.
class SamsungDriver implements TvDriver {
  SamsungDriver(
    this.device,
    this._keys,
    this._makeTransport, {
    JsonFetcher? fetchJson,
    this.connectTimeout = const Duration(seconds: 5),
    this.pairingTimeout = const Duration(seconds: 60),
  }) : _fetchJson = fetchJson ?? defaultFetchJson;

  final TvDevice device;
  final KeyStore _keys;
  final Transport Function() _makeTransport;
  final JsonFetcher _fetchJson;
  final Duration connectTimeout;
  final Duration pairingTimeout;

  final _states = StreamController<TvConnectionState>.broadcast();
  Transport? _transport;
  StreamSubscription<String>? _sub;
  Future<void>? _connecting;
  Completer<String?>? _ready;
  Timer? _timer;
  bool _usedToken = false;
  bool _disposed = false;

  @override
  TvCapabilities get capabilities => TvCapabilities(TvKey.values.toSet());

  @override
  Stream<TvConnectionState> get state => _states.stream;

  // Samsung's remote API has no typing channel in this driver yet.
  @override
  Stream<bool> get keyboardFocus => const Stream<bool>.empty();

  void _emit(TvConnectionState s) {
    if (!_states.isClosed) _states.add(s);
  }

  // Token storage must never be able to break control of the TV.
  Future<String?> _readToken() async {
    try {
      return await _keys.read(device.id);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeToken(String token) async {
    try {
      await _keys.write(device.id, token);
    } catch (_) {}
  }

  Future<void> _deleteToken() async {
    try {
      await _keys.delete(device.id);
    } catch (_) {}
  }

  @override
  Future<void> connect({bool pinPairing = false}) {
    // Samsung only offers the on-TV "Allow" prompt; [pinPairing] is ignored.
    if (_disposed) return Future.error(const TvConnectionError('Driver disposed'));
    return _connecting ??= _connect().whenComplete(() => _connecting = null);
  }

  Future<void> _connect() async {
    _emit(const Connecting());
    try {
      await _teardown();
      var token = await _readToken();
      String? issued;
      while (true) {
        try {
          issued = await _handshake(token);
          break;
        } on _TokenRejected {
          await _deleteToken();
          token = null;
        }
      }
      if (issued != null) await _writeToken(issued);
      _emit(const Connected());
    } catch (e) {
      final error = e is TvError ? e : const TvConnectionError();
      await _teardown();
      _emit(Failed(error));
      throw error;
    }
  }

  /// Tries the secure port first, then the plain one (older TVs).
  Future<Transport> _open(String? token) async {
    for (final secure in const [true, false]) {
      final transport = _makeTransport();
      try {
        await transport
            .open(samsungUrl(device.host, secure: secure, token: token))
            .timeout(connectTimeout);
        return transport;
      } catch (_) {
        try {
          await transport.close();
        } catch (_) {}
      }
    }
    throw const TvConnectionError();
  }

  Future<String?> _handshake(String? token) async {
    final transport = await _open(token);
    _transport = transport;
    final ready = Completer<String?>();
    _ready = ready;
    _usedToken = token != null;
    _sub = transport.messages.listen(_onMessage, onDone: _onClosed);
    if (token == null) {
      // No token yet: the TV is showing its "Allow" prompt.
      _emit(const AwaitingPairing());
      _startTimer(pairingTimeout, ready, const PairingDenied('Pairing timed out'));
    } else {
      _startTimer(connectTimeout, ready, _TokenRejected());
    }
    try {
      return await ready.future;
    } finally {
      _timer?.cancel();
      if (identical(_ready, ready)) _ready = null;
    }
  }

  void _startTimer(Duration d, Completer<String?> c, Object error) {
    _timer?.cancel();
    _timer = Timer(d, () {
      if (!c.isCompleted) c.completeError(error);
    });
  }

  void _failPending(TvError error) {
    final c = _ready;
    if (c != null && !c.isCompleted) c.completeError(error);
  }

  void _onMessage(String raw) {
    final msg = parseSamsungInbound(raw);
    if (msg == null) return;
    final c = _ready;
    if (c == null || c.isCompleted) return;
    switch (msg) {
      case SamsungConnected(:final token):
        c.complete(token);
      case SamsungUnauthorized():
        c.completeError(_usedToken ? _TokenRejected() : const PairingDenied());
      case SamsungTimeout():
        c.completeError(
            _usedToken ? _TokenRejected() : const PairingDenied('The TV prompt timed out'));
    }
  }

  void _onClosed() {
    if (_disposed) return;
    _failPending(const TvConnectionError('Connection to the TV was lost'));
    _emit(const Disconnected());
    unawaited(_teardown());
  }

  Future<void> _teardown() async {
    _timer?.cancel();
    final transport = _transport, sub = _sub;
    _transport = null;
    _sub = null;
    await sub?.cancel();
    try {
      await transport?.close();
    } catch (_) {}
  }

  bool get _alive => _transport?.isOpen ?? false;

  @override
  Future<void> sendKey(TvKey key) async {
    if (!_alive) {
      final joining = _connecting != null;
      await connect();
      // A reconnect was already underway for an earlier press: drop this one
      // rather than letting queued presses all fire at once on reconnect.
      if (joining) return;
    }
    final transport = _transport;
    if (transport == null) throw const TvConnectionError();
    transport.send(samsungKeyMessage(SamsungKeyMap.key(key)!));
  }

  static const _noTyping = TvConnectionError('Typing is not supported on Samsung TVs yet');

  @override
  Future<void> sendText(String text) async => throw _noTyping;

  @override
  Future<void> deleteText(int count) async => throw _noTyping;

  @override
  Future<void> sendEnter() async => throw _noTyping;

  @override
  Future<void> submitPairingPin(String pin) async {}

  @override
  Future<String?> fetchMacAddress() async {
    try {
      final json = await _fetchJson(Uri.http('${device.host}:8001', '/api/v2/'));
      return json == null ? null : macFromSamsungDeviceInfo(json);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _failPending(const TvConnectionError('Driver disposed'));
    await _teardown();
    // Not awaited: close() on a broadcast stream with no listeners never completes.
    unawaited(_states.close());
  }
}
