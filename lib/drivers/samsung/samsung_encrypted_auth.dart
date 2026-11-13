import 'dart:convert';

import '../../core/tv_driver.dart';
import 'samsung_encrypted_crypto.dart';
import 'samsung_encrypted_http.dart';

/// What pairing produces and later connections reuse.
class EncryptedCredentials {
  const EncryptedCredentials(this.tokenHex, this.sessionId);
  final String tokenHex;
  final String sessionId;

  String serialize() => '$tokenHex:$sessionId';

  static EncryptedCredentials? parse(String s) {
    final i = s.indexOf(':');
    if (i <= 0 || i == s.length - 1) return null;
    final token = s.substring(0, i);
    final id = s.substring(i + 1);
    if (!RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(token)) return null;
    if (!RegExp(r'^\d+$').hasMatch(id)) return null;
    return EncryptedCredentials(token, id);
  }
}

String _hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

/// PIN pairing with a Samsung H/J-series TV over its web server on port 8080.
class SamsungEncryptedAuth {
  SamsungEncryptedAuth(this.host, this._http, {this.port = 8080});

  static const userId = '654321';
  static const _appId = '12345';
  static const _deviceId = '7e509404-9d7c-46b4-8f6a-e2a9668ad184';

  final String host;
  final int port;
  final SamsungHttp _http;
  PairingKeys? _keys;

  Uri _url(String path, [Map<String, String>? query]) =>
      Uri(scheme: 'http', host: host, port: port, path: path, queryParameters: query);

  Uri _pairingUrl(int step, [Map<String, String> extra = const {}]) => _url('/ws/pairing',
      {'step': '$step', 'app_id': _appId, 'device_id': _deviceId, ...extra});

  Future<HttpReply> _send(String method, Uri uri, {String? body}) async {
    try {
      return await _http.send(method, uri, body: body);
    } catch (_) {
      throw const TvConnectionError('Could not reach the TV. Check it is on and on the same Wi-Fi.');
    }
  }

  /// Makes the TV show its PIN screen (if it isn't already).
  Future<void> startPairing() async {
    final page = await _send('GET', _url('/ws/apps/CloudPINPage'));
    final state = RegExp(r'state>([^<>]*)</state>', caseSensitive: false)
        .firstMatch(page.body)
        ?.group(1);
    if (page.status != 200 || state == null) {
      throw const TvConnectionError(
          'The TV has no PIN pairing service here. If this TV is a Samsung from 2014-2015, '
          'remove it and try another Samsung option when adding it.');
    }
    if (state == 'stopped') {
      final shown = await _send('POST', _url('/ws/apps/CloudPINPage'), body: 'pin4');
      if (shown.status < 200 || shown.status >= 300) {
        throw const TvConnectionError('The TV would not show its PIN screen.');
      }
    }
  }

  /// Tries the PIN shown on the TV. Returns false if it is wrong.
  Future<bool> tryPin(String pin) async {
    await _send('GET', _pairingUrl(0, {'type': '1'}));
    final hello = generateServerHello(userId, pin);
    final content = '{"auth_Data":{"auth_type":"SPC","GeneratorServerHello":"'
        '${_hex(hello.hello).toUpperCase()}"}}';
    final reply = await _send('POST', _pairingUrl(1), body: content);
    if (reply.status < 200 || reply.status >= 300) {
      throw const TvConnectionError('The TV rejected the pairing request. Try again.');
    }
    final match = RegExp(
      r'request_id.*?(\d).*?GeneratorClientHello.*?:.*?(\d[0-9a-zA-Z]*)',
      caseSensitive: false,
    ).firstMatch(reply.body);
    final clientHello = match?.group(2);
    if (clientHello == null) return false;
    final keys = parseClientHello(clientHello, hello.hash, hello.aesKey, userId);
    if (keys == null) return false;
    _keys = keys;
    return true;
  }

  /// After an accepted PIN: confirms the exchange and returns the credentials.
  Future<EncryptedCredentials> finish() async {
    final keys = _keys;
    if (keys == null) throw const PairingDenied('Enter the code shown on the TV first');
    final content = '{"auth_Data":{"auth_type":"SPC","request_id":"0","ServerAckMsg":"'
        '${generateServerAcknowledge(keys.skPrime)}"}}';
    final reply = await _send('POST', _pairingUrl(2), body: content);
    final authData = _authData(reply.body);
    if (authData.isEmpty) {
      throw const PairingDenied('The code expired. Try again and enter the new code.');
    }
    if (authData.contains('secure-mode')) {
      throw const TvConnectionError(
          'This TV asks for a security mode the app does not support yet.');
    }
    final match = RegExp(
      r'ClientAckMsg.*?:.*?(\d[0-9a-zA-Z]*).*?session_id.*?(\d+)',
      caseSensitive: false,
    ).firstMatch(authData);
    if (match == null || !parseClientAcknowledge(match.group(1)!, keys.skPrime)) {
      throw const TvConnectionError('Unexpected reply from the TV while pairing');
    }
    await closePinPage();
    return EncryptedCredentials(_hex(keys.ctx), match.group(2)!);
  }

  /// Removes the PIN screen from the TV. Best effort.
  Future<void> closePinPage() async {
    try {
      await _http.send('DELETE', _url('/ws/apps/CloudPINPage/run'));
    } catch (_) {}
  }

  static String _authData(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) return (decoded['auth_data'] as String?) ?? '';
    } catch (_) {}
    return body;
  }
}
