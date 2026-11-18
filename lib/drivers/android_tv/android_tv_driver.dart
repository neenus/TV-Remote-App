import 'dart:async';
import 'dart:typed_data';

import '../../core/key_store.dart';
import '../../core/tv_device.dart';
import '../../core/tv_driver.dart';
import '../../core/tv_key.dart';
import 'atv_crypto.dart';
import 'atv_protobuf.dart';
import 'atv_transport.dart';

const _pairingPort = 6467;
const _controlPort = 6466;

// What we tell the TV we can do: ping, keys, power, volume, app links (no typing, no voice).
const _ourFeatures = 1 | 2 | 32 | 64 | 512;

const _unreachable = 'Could not reach the TV. Check it is on and on the same Wi-Fi network.';
const _hungUp = 'The TV closed the connection. If this keeps happening, remove the TV and '
    'add it again to pair afresh.';
const _needsPairing = 'This TV needs to be paired. Go back, open it again and enter the code '
    'shown on the TV.';

/// Android key codes for each button.
class AtvKeyMap {
  static int code(TvKey k) => switch (k) {
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
        TvKey.mute => 164, // KEYCODE_VOLUME_MUTE
        TvKey.channelUp => 166,
        TvKey.channelDown => 167,
        TvKey.rewind => 89,
        TvKey.play => 126,
        TvKey.pause => 127,
        TvKey.fastForward => 90,
        TvKey.power => 26,
        TvKey.input => 178, // KEYCODE_TV_INPUT
      };
}

/// Android TV / Google TV (Sony, Philips, TCL, Hisense, Nvidia Shield, ...) over the
/// Android TV Remote protocol v2: pairing with a code on port 6467, control on 6466.
class AndroidTvDriver implements TvDriver {
  AndroidTvDriver(
    this.device,
    this._keys,
    this._makeChannel, {
    Future<AtvIdentity> Function()? makeIdentity,
    this.connectTimeout = const Duration(seconds: 5),
    this.stepTimeout = const Duration(seconds: 10),
    this.pairingTimeout = const Duration(minutes: 2),
    this.idleTimeout = const Duration(seconds: 16),
  }) : _makeIdentity = makeIdentity ?? generateAtvIdentity;

  static const _identityKeyId = 'atv-identity';
  static const _pairedMark = 'paired';

  // One identity per key store for the whole app run: making one takes seconds, and a
  // session being closed (or storage failing) must not make us start over.
  static final _identityMemo = Expando<Future<AtvIdentity>>('atv identity');

  final TvDevice device;
  final KeyStore _keys;
  final AtvChannel Function() _makeChannel;
  final Future<AtvIdentity> Function() _makeIdentity;
  final Duration connectTimeout;
  final Duration stepTimeout;
  final Duration pairingTimeout;

  /// The TV pings every few seconds; this much silence means the connection is dead.
  final Duration idleTimeout;

  final _states = StreamController<TvConnectionState>.broadcast();
  AtvChannel? _channel;
  StreamSubscription<List<int>>? _sub;
  AtvFrameParser _parser = AtvFrameParser();
  Future<void>? _connecting;
  bool _disposed = false;
  bool _online = false; // control handshake finished: keys may be sent
  bool _paired = false;
  bool _pairedLoaded = false;
  int _features = _ourFeatures;
  bool _controlPhase = false;

  Completer<PoloMessage>? _awaitingPolo;
  Completer<String>? _pinWaiter;
  Completer<void>? _ready;
  Timer? _timer;
  Timer? _idleTimer;

  @override
  TvCapabilities get capabilities =>
      TvCapabilities(TvKey.values.toSet(), typing: false, pinHex: true);

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

  // ---- storage (never allowed to break control) ---------------------------

  Future<AtvIdentity> _loadIdentity() {
    final existing = _identityMemo[_keys];
    if (existing != null) return existing;
    final future = _loadOrCreateIdentity();
    _identityMemo[_keys] = future;
    future.then<void>((_) {}, onError: (Object _) {
      if (identical(_identityMemo[_keys], future)) _identityMemo[_keys] = null;
    });
    return future;
  }

  Future<AtvIdentity> _loadOrCreateIdentity() async {
    AtvIdentity? identity;
    try {
      final raw = await _keys.read(_identityKeyId);
      identity = raw == null ? null : AtvIdentity.parse(raw);
    } catch (_) {}
    if (identity == null) {
      identity = await _makeIdentity(); // several seconds the first time
      try {
        await _keys.write(_identityKeyId, identity.serialize());
      } catch (_) {}
    }
    return identity;
  }

  Future<bool> _isPaired() async {
    if (_pairedLoaded) return _paired;
    try {
      _paired = await _keys.read(device.id) == _pairedMark;
    } catch (_) {
      _paired = false;
    }
    _pairedLoaded = true;
    return _paired;
  }

  Future<void> _rememberPaired() async {
    _paired = true;
    _pairedLoaded = true; // kept in memory even if storage fails
    try {
      await _keys.write(device.id, _pairedMark);
    } catch (_) {}
  }

  // ---- connecting ------------------------------------------------------------

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
      final paired = await _isPaired();
      if (!paired && !allowPairing) throw const PairingDenied(_needsPairing);
      final identity = await _loadIdentity();
      _checkDisposed();
      if (!paired) {
        await _pair(identity);
        await _rememberPaired();
      }
      _checkDisposed();
      await _openControl(identity);
      _checkDisposed();
      _emit(const Connected());
    } catch (e) {
      final error = e is TvError ? e : const TvConnectionError(_unreachable);
      await _teardown();
      _emit(Failed(error));
      throw error;
    }
  }

  Future<AtvChannel> _open(int port, AtvIdentity identity) async {
    final channel = _makeChannel();
    _channel = channel; // visible to _teardown/dispose while still opening
    try {
      await channel.openSecure(device.host, port, identity).timeout(connectTimeout);
    } catch (_) {
      await _closeQuietly(channel);
      _checkDisposed();
      throw const TvConnectionError(_unreachable);
    }
    if (_disposed) {
      await _closeQuietly(channel);
      _checkDisposed();
    }
    _parser = AtvFrameParser();
    _sub = channel.bytes.listen((c) => _onBytes(channel, c), onDone: () => _onClosed(channel));
    return channel;
  }

  Future<void> _closeQuietly(AtvChannel c) async {
    try {
      await c.close();
    } catch (_) {}
    if (identical(_channel, c)) _channel = null;
  }

  // ---- pairing ---------------------------------------------------------------

  Future<PoloMessage> _expectPolo() {
    final waiter = Completer<PoloMessage>();
    _awaitingPolo = waiter;
    _timer?.cancel();
    _timer = Timer(stepTimeout, () {
      if (!waiter.isCompleted) {
        waiter.completeError(const TvConnectionError('The TV did not answer while pairing'));
      }
    });
    return waiter.future.whenComplete(() {
      _timer?.cancel();
      if (identical(_awaitingPolo, waiter)) _awaitingPolo = null;
    });
  }

  TvError _pairingFailure(PoloMessage m) => m is PoloError && m.status == 402
      ? const PairingDenied('That code was not accepted')
      : const TvConnectionError('The TV refused the pairing request. Try again.');

  Future<void> _step(AtvChannel channel, List<int> message, bool Function(PoloMessage) ok) async {
    final next = _expectPolo();
    channel.send(frameMessage(message));
    final reply = await next;
    if (!ok(reply)) throw _pairingFailure(reply);
  }

  Future<void> _pair(AtvIdentity identity) async {
    _controlPhase = false;
    try {
      final channel = await _open(_pairingPort, identity);
      await _step(channel, poloPairingRequest('TV Remote'), (m) => m is PoloPairingRequestAck);
      await _step(channel, poloOptions(), (m) => m is PoloOptions);
      await _step(channel, poloConfiguration(), (m) => m is PoloConfigurationAck);

      _emit(const AwaitingPin()); // the TV is now showing its code
      final code = await _waitForPin();
      _checkDisposed();
      _emit(const Connecting()); // the code is taken; the last step takes a moment

      final client = rsaPublicKeyFromCertDer(pemToDer(identity.certPem) ?? const []);
      final serverDer = channel.peerCertificateDer;
      final server = serverDer == null ? null : rsaPublicKeyFromCertDer(serverDer);
      if (client == null || server == null) {
        throw const TvConnectionError('Unexpected certificate from the TV');
      }
      final secret = atvPairingSecret(
          clientN: client.n,
          clientE: client.e,
          serverN: server.n,
          serverE: server.e,
          code: code);
      if (secret == null) throw const PairingDenied('That code was not accepted');
      await _step(channel, poloSecret(secret), (m) => m is PoloSecretAck);
    } finally {
      await _closeCurrent(); // the pairing connection isn't needed any more
    }
  }

  Future<String> _waitForPin() {
    final waiter = Completer<String>();
    _pinWaiter = waiter;
    _timer?.cancel();
    _timer = Timer(pairingTimeout, () {
      if (!waiter.isCompleted) waiter.completeError(const PairingDenied('Pairing timed out'));
    });
    return waiter.future.whenComplete(() {
      _timer?.cancel();
      if (identical(_pinWaiter, waiter)) _pinWaiter = null;
    });
  }

  @override
  Future<void> submitPairingPin(String pin) async {
    final waiter = _pinWaiter;
    if (waiter != null && !waiter.isCompleted) waiter.complete(pin);
  }

  // ---- control ---------------------------------------------------------------

  Future<void> _openControl(AtvIdentity identity) async {
    _controlPhase = true;
    final channel = await _open(_controlPort, identity);
    final ready = Completer<void>();
    _ready = ready;
    _timer?.cancel();
    _timer = Timer(stepTimeout, () {
      if (!ready.isCompleted) {
        ready.completeError(const TvConnectionError('The TV did not finish connecting'));
      }
    });
    try {
      await ready.future;
      _online = true;
      _resetIdle();
    } finally {
      _timer?.cancel();
      if (identical(_ready, ready)) _ready = null;
    }
    if (!identical(_channel, channel)) throw const TvConnectionError('Connection to the TV was lost');
  }

  void _onBytes(AtvChannel from, List<int> chunk) {
    if (!identical(from, _channel)) return; // a connection we already let go of
    final List<Uint8List> frames;
    try {
      frames = _parser.add(chunk);
    } on FormatException {
      _protocolError(from);
      return;
    }
    for (final frame in frames) {
      if (!identical(from, _channel)) return;
      try {
        _controlPhase ? _onControl(from, parseRemote(frame)) : _onPairing(parsePolo(frame));
      } on FormatException {
        _protocolError(from);
        return;
      }
    }
  }

  void _protocolError(AtvChannel from) {
    const error = TvConnectionError('Unexpected data from the TV');
    _failPending(error);
    if (_online) {
      _emit(const Disconnected());
      unawaited(_teardown());
    }
  }

  void _onPairing(PoloMessage m) {
    final waiter = _awaitingPolo;
    if (waiter != null && !waiter.isCompleted) waiter.complete(m);
  }

  void _onControl(AtvChannel from, RemoteIn m) {
    if (_online) _resetIdle();
    switch (m) {
      case RemoteConfigureIn(:final features):
        _features = _ourFeatures & features;
        _send(from, remoteConfigure(_features));
      case RemoteSetActiveIn():
        _send(from, remoteSetActive(_features));
      case RemotePingIn(:final value):
        _send(from, remotePingResponse(value));
      case RemoteStartIn():
        final ready = _ready;
        if (ready != null && !ready.isCompleted) ready.complete();
      case RemoteErrorIn():
        final ready = _ready;
        if (ready != null && !ready.isCompleted) {
          ready.completeError(const TvConnectionError('The TV reported an error. Try again.'));
        }
      case RemoteOther():
        break;
    }
  }

  void _send(AtvChannel c, List<int> message) {
    try {
      c.send(frameMessage(message));
    } catch (_) {}
  }

  void _failPending(TvError error) {
    final polo = _awaitingPolo;
    if (polo != null && !polo.isCompleted) polo.completeError(error);
    final pin = _pinWaiter;
    if (pin != null && !pin.isCompleted) pin.completeError(error);
    final ready = _ready;
    if (ready != null && !ready.isCompleted) ready.completeError(error);
  }

  void _onClosed(AtvChannel from) {
    if (_disposed || !identical(from, _channel)) return;
    _failPending(_controlPhase
        ? const TvConnectionError(_hungUp)
        : const TvConnectionError('The TV closed the connection while pairing'));
    if (_online) {
      _emit(const Disconnected());
      unawaited(_teardown());
    }
  }

  void _resetIdle() {
    _idleTimer?.cancel();
    _idleTimer = Timer(idleTimeout, _onIdle);
  }

  // The TV pings every few seconds; long silence means the connection is dead (the TV
  // lost power or the network dropped). Drop it so the next press reconnects.
  void _onIdle() {
    if (_disposed) return;
    _emit(const Disconnected());
    unawaited(_teardown());
  }

  Future<void> _closeCurrent() async {
    final channel = _channel, sub = _sub;
    _channel = null;
    _sub = null;
    await sub?.cancel();
    try {
      await channel?.close();
    } catch (_) {}
  }

  Future<void> _teardown() async {
    _online = false;
    _timer?.cancel();
    _idleTimer?.cancel();
    _idleTimer = null;
    await _closeCurrent();
  }

  bool get _alive => _online && (_channel?.isOpen ?? false);

  // ---- keys ------------------------------------------------------------------

  @override
  Future<void> sendKey(TvKey key) async {
    if (!_alive) {
      // A key press must never start pairing: there'd be no screen to enter the code on.
      final joining = _connecting != null;
      await _start(allowPairing: false);
      // A reconnect was already underway for an earlier press: drop this one rather
      // than letting queued presses all fire at once on reconnect.
      if (joining) return;
    }
    final channel = _channel;
    if (channel == null || !_online) throw const TvConnectionError();
    try {
      channel.send(frameMessage(remoteKeyInject(AtvKeyMap.code(key))));
    } catch (_) {
      throw const TvConnectionError();
    }
  }

  static const _noTyping = TvConnectionError('Typing is not supported on this TV yet');

  @override
  Future<void> sendText(String text) async => throw _noTyping;

  @override
  Future<void> deleteText(int count) async => throw _noTyping;

  @override
  Future<void> sendEnter() async => throw _noTyping;

  @override
  Future<String?> fetchMacAddress() async => null;

  @override
  Future<void> dispose() async {
    _disposed = true;
    _failPending(const TvConnectionError('Driver disposed'));
    await _teardown();
    // Not awaited: nothing depends on it finishing.
    unawaited(_states.close());
  }
}
