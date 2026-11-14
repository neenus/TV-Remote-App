import 'dart:async';

import '../../core/key_store.dart';
import '../../core/tv_device.dart';
import '../../core/tv_driver.dart';
import '../../core/tv_key.dart';
import '../lg/transport.dart';
import 'samsung_driver.dart' show JsonFetcher, defaultFetchJson;
import 'samsung_encrypted_auth.dart';
import 'samsung_encrypted_crypto.dart';
import 'samsung_encrypted_http.dart';
import 'samsung_encrypted_protocol.dart';
import 'samsung_legacy_protocol.dart' show LegacyKeyMap;
import 'samsung_protocol.dart' show macFromSamsungDeviceInfo;

/// Samsung H/J-series TVs (2014-2015): PIN pairing over HTTP (port 8080), then an
/// encrypted socket.io control channel (port 8000).
class SamsungEncryptedDriver implements TvDriver {
  SamsungEncryptedDriver(
    this.device,
    this._keys,
    this._makeTransport,
    this._http, {
    JsonFetcher? fetchJson,
    this.connectTimeout = const Duration(seconds: 5),
    this.pairingTimeout = const Duration(seconds: 90),
    Duration? idleTimeout,
  })  : _fetchJson = fetchJson ?? defaultFetchJson,
        _idleOverride = idleTimeout;

  final TvDevice device;
  final KeyStore _keys;
  final Transport Function() _makeTransport;
  final SamsungHttp _http;
  final JsonFetcher _fetchJson;
  final Duration connectTimeout;
  final Duration pairingTimeout;
  final Duration? _idleOverride;

  final _states = StreamController<TvConnectionState>.broadcast();
  Transport? _transport;
  StreamSubscription<String>? _sub;
  Future<void>? _connecting;
  Completer<String>? _pinWaiter;
  Timer? _pinTimer;
  Timer? _idleTimer;
  Duration _idle = const Duration(seconds: 90);
  bool _watchdogArmed = false;
  EncryptedCredentials? _creds; // kept in memory so storage trouble can't force a re-pair
  SamsungEncryptedSession? _session;
  bool _disposed = false;

  @override
  TvCapabilities get capabilities => TvCapabilities(TvKey.values.toSet(), typing: false);

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

  // Storage must never be able to break control of the TV.
  Future<EncryptedCredentials?> _readCreds() async {
    try {
      final raw = await _keys.read(device.id);
      final c = raw == null ? null : EncryptedCredentials.parse(raw);
      if (c != null) _creds = c;
      return c;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCreds(EncryptedCredentials c) async {
    try {
      await _keys.write(device.id, c.serialize());
    } catch (_) {}
  }

  @override
  Future<void> connect({bool pinPairing = false}) {
    // These TVs only offer PIN pairing; [pinPairing] is ignored.
    if (_disposed) return Future.error(const TvConnectionError('Driver disposed'));
    return _connecting ??= _connect().whenComplete(() => _connecting = null);
  }

  Future<void> _connect() async {
    _emit(const Connecting());
    try {
      await _teardown();
      var creds = _creds ?? await _readCreds();
      if (creds == null) {
        creds = await _pair();
        _creds = creds;
        await _writeCreds(creds);
      }
      _checkDisposed();
      await _openChannel(creds);
      _checkDisposed();
      _emit(const Connected());
    } catch (e) {
      final error = e is TvError ? e : const TvConnectionError();
      await _teardown();
      _emit(Failed(error));
      throw error;
    }
  }

  /// Shows a PIN on the TV, waits for the user to type it, and pairs.
  Future<EncryptedCredentials> _pair() async {
    final auth = SamsungEncryptedAuth(device.host, _http);
    try {
      await auth.startPairing();
      _checkDisposed();
      _emit(const AwaitingPin());
      final pin = await _waitForPin();
      _checkDisposed();
      _emit(const Connecting()); // the code is taken; the next steps take a moment
      if (!await auth.tryPin(pin)) throw const PairingDenied('That code was not accepted');
      // Once paired, keep the result even if we were disposed meanwhile.
      return await auth.finish();
    } catch (_) {
      // Whatever went wrong, don't leave a PIN screen up on the TV (best effort,
      // harmless if none is showing).
      await auth.closePinPage();
      rethrow;
    }
  }

  Future<String> _waitForPin() {
    final waiter = Completer<String>();
    _pinWaiter = waiter;
    _pinTimer?.cancel();
    _pinTimer = Timer(pairingTimeout, () {
      if (!waiter.isCompleted) waiter.completeError(const PairingDenied('Pairing timed out'));
    });
    return waiter.future.whenComplete(() {
      _pinTimer?.cancel();
      if (identical(_pinWaiter, waiter)) _pinWaiter = null;
    });
  }

  @override
  Future<void> submitPairingPin(String pin) async {
    final waiter = _pinWaiter;
    if (waiter != null && !waiter.isCompleted) waiter.complete(pin.trim());
  }

  Future<void> _closeQuietly(Transport t) async {
    try {
      await t.close();
    } catch (_) {}
    if (identical(_transport, t)) _transport = null;
  }

  Future<void> _openChannel(EncryptedCredentials creds) async {
    String body;
    try {
      final reply = await _http
          .send('GET', socketIoHandshakeUri(device.host, DateTime.now().millisecondsSinceEpoch))
          .timeout(connectTimeout);
      body = reply.body;
    } catch (_) {
      throw const TvConnectionError('Could not reach the TV control port. Is it switched on?');
    }
    final sid = socketIoSessionId(body);
    if (sid == null) throw const TvConnectionError('Unexpected reply from the TV');
    final advertised = socketIoIdleTimeout(body);
    _idle = _idleOverride ?? advertised ?? const Duration(seconds: 90);
    // Only trust silence as a sign of death if the TV said it sends heartbeats.
    _watchdogArmed = advertised != null;
    _checkDisposed();

    final transport = _makeTransport();
    _transport = transport; // visible to _teardown/dispose while still opening
    try {
      await transport.open(socketIoWebSocketUri(device.host, sid)).timeout(connectTimeout);
    } catch (_) {
      await _closeQuietly(transport);
      _checkDisposed();
      throw const TvConnectionError('Could not open the TV control channel');
    }
    if (_disposed) {
      await _closeQuietly(transport);
      _checkDisposed();
    }
    _session = SamsungEncryptedSession(creds.tokenHex, creds.sessionId);
    _sub = transport.messages.listen(
      (m) => _onMessage(transport, m),
      onDone: () => _onClosed(transport),
    );
    transport.send(socketIoConnectFrame);
    _resetIdle();
  }

  void _resetIdle() {
    _idleTimer?.cancel();
    if (!_watchdogArmed) return;
    _idleTimer = Timer(_idle, _onIdle);
  }

  /// The TV heartbeats regularly; long silence means the connection is dead
  /// (e.g. the TV lost power). Drop it so the next press reconnects.
  void _onIdle() {
    if (_disposed) return;
    _emit(const Disconnected());
    unawaited(_teardown());
  }

  void _onMessage(Transport from, String raw) {
    if (!identical(from, _transport)) return; // a socket we already let go of
    _resetIdle();
    switch (parseSocketIoFrame(raw)) {
      case SioHeartbeat():
        if (!_watchdogArmed) {
          _watchdogArmed = true; // this TV does heartbeat: silence now means trouble
          _resetIdle();
        }
        try {
          from.send(socketIoHeartbeat);
        } catch (_) {}
      case SioDisconnect():
        _onClosed(from);
      case SioConnected() || SioOther():
        break;
    }
  }

  void _onClosed(Transport from) {
    if (_disposed || !identical(from, _transport)) return;
    _emit(const Disconnected());
    unawaited(_teardown());
  }

  Future<void> _teardown() async {
    _pinTimer?.cancel();
    _idleTimer?.cancel();
    _idleTimer = null;
    final transport = _transport, sub = _sub;
    _transport = null;
    _sub = null;
    _session = null;
    await sub?.cancel();
    try {
      await transport?.close();
    } catch (_) {}
  }

  bool get _alive => _transport?.isOpen ?? false;

  @override
  Future<void> sendKey(TvKey key) async {
    if (!_alive) {
      // A key press must never start pairing: there'd be no screen to enter a PIN on.
      if (_creds == null && await _readCreds() == null) {
        throw const TvConnectionError('This TV is not paired. Remove it and add it again.');
      }
      final joining = _connecting != null;
      await connect();
      // A reconnect was already underway for an earlier press: drop this one
      // rather than letting queued presses all fire at once on reconnect.
      if (joining) return;
    }
    final transport = _transport, session = _session;
    if (transport == null || session == null) throw const TvConnectionError();
    try {
      transport.send(session.encryptKeyCommand(LegacyKeyMap.key(key)!));
    } catch (_) {
      throw const TvConnectionError();
    }
  }

  static const _noTyping = TvConnectionError('Typing is not supported on this Samsung TV yet');

  @override
  Future<void> sendText(String text) async => throw _noTyping;

  @override
  Future<void> deleteText(int count) async => throw _noTyping;

  @override
  Future<void> sendEnter() async => throw _noTyping;

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
    final waiter = _pinWaiter;
    if (waiter != null && !waiter.isCompleted) {
      waiter.completeError(const TvConnectionError('Driver disposed'));
    }
    await _teardown();
    // Not awaited: nothing depends on it finishing.
    unawaited(_states.close());
  }
}
