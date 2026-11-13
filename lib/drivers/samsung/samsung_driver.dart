import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/key_store.dart';
import '../../core/tv_device.dart';
import '../../core/tv_driver.dart';
import '../../core/tv_key.dart';
import '../lg/transport.dart';
import 'samsung_protocol.dart';

/// The TV refused the token we sent (explicit `ms.channel.unauthorized`).
class _TokenRejected implements Exception {}

typedef JsonFetcher = Future<Map<String, dynamic>?> Function(Uri uri);

/// Plain HTTP GET returning a JSON object, or null on any failure.
Future<Map<String, dynamic>?> defaultFetchJson(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  try {
    final request = await client.getUrl(uri);
    final response = await request.close().timeout(const Duration(seconds: 3));
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 3));
    final json = jsonDecode(body);
    return json is Map<String, dynamic> ? json : null;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

const _deniedMessage = 'The TV denied the request. If no prompt appears when you retry, '
    'on the TV open Settings > General > External Device Manager > '
    'Device Connection Manager > Device List and allow or remove "TV Remote".';

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
  bool _preferPlain = false; // this TV only answered on the plain port last time
  bool _disposed = false;

  // Typing is not available through this driver yet.
  @override
  TvCapabilities get capabilities =>
      TvCapabilities(TvKey.values.toSet(), typing: false);

  @override
  Stream<TvConnectionState> get state => _states.stream;

  @override
  Stream<bool> get keyboardFocus => const Stream<bool>.empty();

  void _emit(TvConnectionState s) {
    if (!_states.isClosed) _states.add(s);
  }

  void _checkDisposed() {
    if (_disposed) throw const TvConnectionError('Driver disposed');
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
          // Close the refused socket before starting over, so it can't interfere.
          await _teardown();
          await _deleteToken();
          token = null;
        }
      }
      _checkDisposed();
      if (issued != null) await _writeToken(issued);
      _emit(const Connected());
    } catch (e) {
      final error = e is TvError ? e : const TvConnectionError();
      await _teardown();
      _emit(Failed(error));
      throw error;
    }
  }

  /// Opens the remote-control socket. With a stored token only the secure port
  /// is tried (that TV has already proven it speaks it); otherwise the plain
  /// port is the fallback for older TVs. Returns whether the secure port is used.
  Future<bool> _open(String? token) async {
    final order = token != null
        ? const [true]
        : (_preferPlain ? const [false, true] : const [true, false]);
    for (final secure in order) {
      _checkDisposed();
      final transport = _makeTransport();
      _transport = transport; // visible to _teardown/dispose while still opening
      try {
        await transport
            .open(samsungUrl(device.host, secure: secure, token: token))
            .timeout(connectTimeout);
        _checkDisposed();
        _preferPlain = !secure;
        return secure;
      } catch (e) {
        try {
          await transport.close();
        } catch (_) {}
        if (identical(_transport, transport)) _transport = null;
        if (e is TvError) rethrow;
      }
    }
    throw const TvConnectionError(
        'Could not reach the TV. If it is an older Samsung (before 2016), add it by IP '
        'and choose "Samsung (older, pre-2016)".');
  }

  Future<String?> _handshake(String? token) async {
    final secure = await _open(token);
    final transport = _transport;
    if (transport == null) throw const TvConnectionError();
    final ready = Completer<String?>();
    _ready = ready;
    final useToken = secure && token != null;
    _usedToken = useToken;
    _sub = transport.messages.listen(
      (m) => _onMessage(transport, m),
      onDone: () => _onClosed(transport),
    );
    if (!useToken) {
      // No token yet: the TV is showing its "Allow" prompt.
      _emit(const AwaitingPairing());
      _startTimer(pairingTimeout, ready, const PairingDenied('Pairing timed out'));
    } else {
      // A slow TV, or one that wants us to confirm again: keep the same socket
      // and keep the token, but tell the user a prompt may be waiting.
      _timer?.cancel();
      _timer = Timer(connectTimeout, () {
        if (ready.isCompleted) return;
        _emit(const AwaitingPairing());
        _startTimer(pairingTimeout, ready, const PairingDenied('Pairing timed out'));
      });
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

  void _onMessage(Transport from, String raw) {
    if (!identical(from, _transport)) return; // a socket we already let go of
    final msg = parseSamsungInbound(raw);
    if (msg == null) return;
    final c = _ready;
    if (c == null || c.isCompleted) return;
    switch (msg) {
      case SamsungConnected(:final token):
        c.complete(token);
      case SamsungUnauthorized():
        c.completeError(_usedToken ? _TokenRejected() : const PairingDenied(_deniedMessage));
      case SamsungTimeout():
        c.completeError(const PairingDenied('The prompt on the TV timed out'));
    }
  }

  void _onClosed(Transport from) {
    if (_disposed || !identical(from, _transport)) return;
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
