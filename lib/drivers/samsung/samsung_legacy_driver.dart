import 'dart:async';

import '../../core/tv_device.dart';
import '../../core/tv_driver.dart';
import '../../core/tv_key.dart';
import 'samsung_driver.dart' show JsonFetcher, defaultFetchJson;
import 'samsung_legacy_protocol.dart';
import 'samsung_protocol.dart' show macFromSamsungDeviceInfo;
import 'tcp_transport.dart';

const _deniedMessage = 'The TV did not allow the request. If no prompt appears when you retry, '
    'allow "TV Remote" in the TV\'s network or external device settings '
    '(the menu name varies by model).';

const _unsupportedNote =
    'Some 2014-2015 Samsung models use a protocol this app does not support yet.';

/// Samsung TVs from about 2008 to 2015, over the binary TCP protocol on port 55000.
class SamsungLegacyDriver implements TvDriver {
  SamsungLegacyDriver(
    this.device,
    this._makeTransport, {
    JsonFetcher? fetchJson,
    this.connectTimeout = const Duration(seconds: 5),
    this.pairingTimeout = const Duration(seconds: 60),
    this.ackTimeout = const Duration(seconds: 3),
  }) : _fetchJson = fetchJson ?? defaultFetchJson;

  final TvDevice device;
  final ByteTransport Function() _makeTransport;
  final JsonFetcher _fetchJson;
  final Duration connectTimeout;
  final Duration pairingTimeout;

  /// How long a key press may go unacknowledged before the socket is considered dead.
  final Duration ackTimeout;

  final _states = StreamController<TvConnectionState>.broadcast();
  ByteTransport? _transport;
  StreamSubscription<List<int>>? _sub;
  Future<void>? _connecting;
  Completer<void>? _ready;
  Timer? _timer;
  Timer? _ackTimer;
  int _pendingAcks = 0;
  bool _prompted = false;
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

  @override
  Future<void> connect({bool pinPairing = false}) {
    // Only the on-TV "Allow" prompt exists on these TVs; [pinPairing] is ignored.
    if (_disposed) return Future.error(const TvConnectionError('Driver disposed'));
    return _connecting ??= _connect().whenComplete(() => _connecting = null);
  }

  Future<void> _connect() async {
    _emit(const Connecting());
    try {
      await _teardown();
      await _handshake();
      _checkDisposed();
      _emit(const Connected());
    } catch (e) {
      final error = e is TvError ? e : const TvConnectionError();
      await _teardown();
      _emit(Failed(error));
      throw error;
    }
  }

  Future<void> _closeQuietly(ByteTransport t) async {
    try {
      await t.close();
    } catch (_) {}
    if (identical(_transport, t)) _transport = null;
  }

  Future<void> _handshake() async {
    _checkDisposed();
    final transport = _makeTransport();
    _transport = transport; // visible to _teardown/dispose while still opening
    try {
      await transport.open(device.host, legacyPort).timeout(connectTimeout);
    } catch (_) {
      await _closeQuietly(transport);
      _checkDisposed();
      throw TvConnectionError(
          'Could not reach the TV on port $legacyPort. Check it is on and on the same Wi-Fi. '
          '$_unsupportedNote');
    }
    if (_disposed) {
      await _closeQuietly(transport);
      _checkDisposed();
    }
    final ready = Completer<void>();
    _ready = ready;
    _prompted = false;
    final parser = LegacyFrameParser();
    _sub = transport.bytes.listen(
      (chunk) => _onBytes(transport, parser, ready, chunk),
      onDone: () => _onClosed(transport),
    );
    _startTimer(connectTimeout, ready,
        const TvConnectionError('The TV did not answer. $_unsupportedNote'));
    try {
      transport.send(legacyHandshake());
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

  void _failPending(TvError error) {
    final c = _ready;
    if (c != null && !c.isCompleted) c.completeError(error);
  }

  void _onBytes(ByteTransport from, LegacyFrameParser parser, Completer<void> ready,
      List<int> chunk) {
    if (!identical(from, _transport)) return; // a socket we already let go of
    for (final reply in parser.add(chunk)) {
      switch (reply) {
        case LegacyGranted():
          if (!ready.isCompleted) ready.complete();
        case LegacyWaiting():
          // Only the first "waiting" counts: repeats must not extend the timeout.
          if (!ready.isCompleted && !_prompted) {
            _prompted = true;
            _emit(const AwaitingPairing());
            _startTimer(pairingTimeout, ready, const PairingDenied('Pairing timed out'));
          }
        case LegacyDenied() || LegacyCancelled():
          if (!ready.isCompleted) {
            ready.completeError(const PairingDenied(_deniedMessage));
          } else {
            // The TV revoked access while connected: report it; the next press retries.
            _emit(const Failed(PairingDenied(_deniedMessage)));
            unawaited(_teardown());
          }
        case LegacyUnknown():
          if (!ready.isCompleted) {
            ready.completeError(const TvConnectionError('Unexpected reply from the TV'));
          }
        case LegacyAck():
          _onAck();
      }
    }
  }

  void _onClosed(ByteTransport from) {
    if (_disposed || !identical(from, _transport)) return;
    _failPending(const TvConnectionError('Connection to the TV was lost'));
    _emit(const Disconnected());
    unawaited(_teardown());
  }

  void _expectAck() {
    _pendingAcks++;
    _ackTimer ??= Timer(ackTimeout, _onAckTimeout);
  }

  void _onAck() {
    if (_pendingAcks > 0) _pendingAcks--;
    _ackTimer?.cancel();
    _ackTimer = _pendingAcks > 0 ? Timer(ackTimeout, _onAckTimeout) : null;
  }

  /// The TV acknowledges every key. Silence means the socket is dead (e.g. the TV
  /// was switched off at the wall): drop it so the next press reconnects or fails.
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
    transport.send(legacyKeyPacket(LegacyKeyMap.key(key)!));
    _expectAck();
  }

  static const _noTyping = TvConnectionError('Typing is not supported on this Samsung TV yet');

  @override
  Future<void> sendText(String text) async => throw _noTyping;

  @override
  Future<void> deleteText(int count) async => throw _noTyping;

  @override
  Future<void> sendEnter() async => throw _noTyping;

  @override
  Future<void> submitPairingPin(String pin) async {}

  /// Best effort: some 2015 Tizen TVs answer the newer device-info request.
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
