import 'dart:async';

import '../../core/tv_device.dart';
import '../../core/tv_driver.dart';
import '../../core/tv_key.dart';
import '../samsung/samsung_encrypted_http.dart';
import 'roku_protocol.dart';

const _unreachable = 'Could not reach the Roku. Check it is on and on the same Wi-Fi.';
const _blocked = 'The Roku refused the remote. On the Roku open Settings > System > '
    'Advanced system settings > Control by mobile apps and choose Default or Permissive.';

/// Roku TVs and players over ECP (HTTP on port 8060). There is no pairing.
class RokuDriver implements TvDriver {
  RokuDriver(this.device, this._http, {this.connectTimeout = const Duration(seconds: 5)});

  final TvDevice device;
  final SamsungHttp _http;
  final Duration connectTimeout;

  final _states = StreamController<TvConnectionState>.broadcast();
  bool _disposed = false;
  bool _connected = false;
  String? _mac;
  Future<void> _tail = Future.value(); // typing runs strictly in order

  @override
  TvCapabilities get capabilities => TvCapabilities(
        TvKey.values.where((k) => RokuKeyMap.key(k) != null).toSet(),
        typing: true,
      );

  @override
  Stream<TvConnectionState> get state => _states.stream;

  // Roku doesn't say when a text field is focused; the keyboard is opened by hand.
  @override
  Stream<bool> get keyboardFocus => const Stream<bool>.empty();

  void _emit(TvConnectionState s) {
    if (!_states.isClosed) _states.add(s);
  }

  void _checkDisposed() {
    if (_disposed) throw const TvConnectionError('Driver disposed');
  }

  @override
  Future<void> connect({bool pinPairing = false}) async {
    // No pairing on a Roku: [pinPairing] is ignored.
    _emit(const Connecting());
    try {
      _checkDisposed();
      final HttpReply reply;
      try {
        reply = await _http.send('GET', rokuInfoUri(device.host)).timeout(connectTimeout);
      } catch (_) {
        throw const TvConnectionError(_unreachable);
      }
      _checkDisposed();
      if (reply.status == 403) throw const TvConnectionError(_blocked);
      final info = reply.status == 200 ? parseRokuDeviceInfo(reply.body) : null;
      if (info == null) {
        throw const TvConnectionError('That device did not answer like a Roku.');
      }
      _mac = info.mac;
      _connected = true;
      _emit(const Connected());
    } catch (e) {
      _connected = false;
      final error = e is TvError ? e : const TvConnectionError(_unreachable);
      _emit(Failed(error));
      throw error;
    }
  }

  Future<void> _post(String keyName) async {
    _checkDisposed();
    final HttpReply reply;
    try {
      reply = await _http.send('POST', rokuKeypressUri(device.host, keyName)).timeout(connectTimeout);
    } catch (_) {
      if (_connected) {
        _connected = false;
        _emit(const Disconnected());
      }
      throw const TvConnectionError(_unreachable);
    }
    if (reply.status == 403) throw const TvConnectionError(_blocked);
    if (reply.status < 200 || reply.status >= 300) {
      throw const TvConnectionError('The Roku did not accept that button.');
    }
    if (!_connected) {
      _connected = true;
      _emit(const Connected());
    }
  }

  @override
  Future<void> sendKey(TvKey key) {
    final name = RokuKeyMap.key(key);
    if (name == null) {
      return Future.error(const TvConnectionError('That button is not available on a Roku'));
    }
    return _post(name);
  }

  Future<void> _serial(Future<void> Function() job) {
    final result = _tail.then((_) => job());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  @override
  Future<void> sendText(String text) => _serial(() async {
        for (final rune in text.runes) {
          await _post(rokuLiteralKey(String.fromCharCode(rune)));
        }
      });

  @override
  Future<void> deleteText(int count) => _serial(() async {
        for (var i = 0; i < count; i++) {
          await _post('Backspace');
        }
      });

  @override
  Future<void> sendEnter() => _serial(() => _post('Enter'));

  @override
  Future<void> submitPairingPin(String pin) async {}

  @override
  Future<String?> fetchMacAddress() async {
    if (_mac != null) return _mac;
    try {
      final reply = await _http.send('GET', rokuInfoUri(device.host)).timeout(connectTimeout);
      return reply.status == 200 ? parseRokuDeviceInfo(reply.body)?.mac : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    unawaited(_states.close());
  }
}
