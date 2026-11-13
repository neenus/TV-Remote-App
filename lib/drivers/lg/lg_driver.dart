import 'dart:async';

import '../../core/key_store.dart';
import '../../core/tv_device.dart';
import '../../core/tv_driver.dart';
import '../../core/tv_key.dart';
import 'lg_protocol.dart';
import 'transport.dart';

class _KeyRejected implements Exception {}

class LgDriver implements TvDriver {
  LgDriver(
    this.device,
    this._keys,
    this._makeTransport, {
    this.connectTimeout = const Duration(seconds: 5),
    this.pairingTimeout = const Duration(seconds: 60),
  });

  final TvDevice device;
  final KeyStore _keys;
  final Transport Function() _makeTransport;
  final Duration connectTimeout;
  final Duration pairingTimeout;

  final _states = StreamController<TvConnectionState>.broadcast();
  Transport? _main;
  Transport? _pointer;
  StreamSubscription<String>? _mainSub;
  Future<void>? _connecting;
  int _reqCounter = 0;
  bool _disposed = false;

  Completer<String>? _registration;
  Completer<String>? _pointerPath;
  Timer? _timer;
  bool _usedStoredKey = false;

  @override
  TvCapabilities get capabilities => TvCapabilities(TvKey.values.toSet());

  @override
  Stream<TvConnectionState> get state => _states.stream;

  void _emit(TvConnectionState s) {
    if (!_states.isClosed) _states.add(s);
  }

  @override
  Future<void> connect() =>
      _connecting ??= _connect().whenComplete(() => _connecting = null);

  Future<void> _connect() async {
    _emit(const Connecting());
    try {
      await _teardown();
      var key = await _keys.read(device.id);
      final main = _makeTransport();
      _main = main;
      try {
        await main
            .open(Uri.parse('wss://${device.host}:3001'))
            .timeout(connectTimeout);
      } catch (_) {
        throw const TvConnectionError();
      }
      _mainSub = main.messages.listen(_onMain, onDone: _onClosed);

      String clientKey;
      while (true) {
        try {
          clientKey = await _register(main, key);
          break;
        } on _KeyRejected {
          await _keys.delete(device.id);
          key = null;
        }
      }
      await _keys.write(device.id, clientKey);

      final path = await _requestPointerSocket(main);
      final pointer = _makeTransport();
      try {
        await pointer.open(Uri.parse(path)).timeout(connectTimeout);
      } catch (_) {
        throw const TvConnectionError('Could not open the TV input socket');
      }
      _pointer = pointer;
      _emit(const Connected());
    } on TvError catch (e) {
      await _teardown();
      _emit(Failed(e));
      rethrow;
    }
  }

  Future<String> _register(Transport main, String? key) {
    final c = Completer<String>();
    _registration = c;
    _usedStoredKey = key != null;
    _startTimer(connectTimeout, c, const TvConnectionError());
    main.send(registerMessage(clientKey: key));
    return c.future.whenComplete(() => _timer?.cancel());
  }

  Future<String> _requestPointerSocket(Transport main) {
    final c = Completer<String>();
    _pointerPath = c;
    _startTimer(connectTimeout, c,
        const TvConnectionError('TV did not provide an input socket'));
    main.send(requestMessage('pointer', LgUris.pointerSocket));
    return c.future.whenComplete(() => _timer?.cancel());
  }

  void _startTimer(Duration d, Completer<String> c, TvError error) {
    _timer?.cancel();
    _timer = Timer(d, () {
      if (!c.isCompleted) c.completeError(error);
    });
  }

  void _onMain(String raw) {
    final msg = parseInbound(raw);
    if (msg == null) return;
    switch (msg) {
      case Registered(:final clientKey):
        _registration?.complete(clientKey);
      case PairingPrompt():
        _emit(const AwaitingPairing());
        final c = _registration;
        if (c != null && !c.isCompleted) {
          _startTimer(pairingTimeout, c, const PairingDenied('Pairing timed out'));
        }
      case LgErrorMsg(:final id) when id == 'register_0':
        final c = _registration;
        if (c != null && !c.isCompleted) {
          c.completeError(_usedStoredKey ? _KeyRejected() : const PairingDenied());
        }
      case Response(:final id, :final payload) when id == 'pointer':
        final path = payload['socketPath'];
        final c = _pointerPath;
        if (c != null && !c.isCompleted) {
          path is String
              ? c.complete(path)
              : c.completeError(const TvConnectionError('Bad input socket reply'));
        }
      default:
    }
  }

  void _onClosed() {
    if (_disposed) return;
    _emit(const Disconnected());
    unawaited(_teardown());
  }

  Future<void> _teardown() async {
    _timer?.cancel();
    final main = _main, pointer = _pointer, sub = _mainSub;
    _main = null;
    _pointer = null;
    _mainSub = null;
    await sub?.cancel();
    try {
      await main?.close();
      await pointer?.close();
    } catch (_) {}
  }

  bool get _alive => (_main?.isOpen ?? false) && (_pointer?.isOpen ?? false);

  @override
  Future<void> sendKey(TvKey key) async {
    if (!_alive) await connect();
    final main = _main, pointer = _pointer;
    if (main == null || pointer == null) throw const TvConnectionError();
    final pointerName = LgKeyMap.pointerName(key);
    if (pointerName != null) {
      pointer.send(pointerButtonFrame(pointerName));
    } else if (key == TvKey.mute) {
      main.send(requestMessage('req_${_reqCounter++}', 'ssap://audio/setMute',
          {'mute': true}));
    } else {
      main.send(requestMessage('req_${_reqCounter++}', LgKeyMap.uri(key)!));
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _teardown();
    await _states.close();
  }
}

class LgUris {
  static const pointerSocket =
      'ssap://com.webos.service.networkinput/getPointerInputSocket';
}
