import 'dart:convert';

import '../../core/tv_key.dart';
import '../../core/wake_on_lan.dart';

/// The name shown on the TV's "Allow" prompt.
const samsungAppName = 'TV Remote';

/// Remote-control socket. The secure port (8002) takes a pairing token; older
/// TVs only offer the plain port (8001), which never uses one.
Uri samsungUrl(String host, {required bool secure, String? token}) => Uri(
      scheme: secure ? 'wss' : 'ws',
      host: host,
      port: secure ? 8002 : 8001,
      path: '/api/v2/channels/samsung.remote.control',
      queryParameters: {
        'name': base64Encode(utf8.encode(samsungAppName)),
        if (secure && token != null) 'token': token,
      },
    );

String samsungKeyMessage(String key) => jsonEncode({
      'method': 'ms.remote.control',
      'params': {
        'Cmd': 'Click',
        'DataOfCmd': key,
        'Option': 'false',
        'TypeOfRemote': 'SendRemoteKey',
      },
    });

class SamsungKeyMap {
  static String? key(TvKey k) => switch (k) {
        TvKey.power => 'KEY_POWER',
        TvKey.up => 'KEY_UP',
        TvKey.down => 'KEY_DOWN',
        TvKey.left => 'KEY_LEFT',
        TvKey.right => 'KEY_RIGHT',
        TvKey.ok => 'KEY_ENTER',
        TvKey.back => 'KEY_RETURN',
        TvKey.home => 'KEY_HOME',
        TvKey.menu => 'KEY_MENU',
        TvKey.volumeUp => 'KEY_VOLUP',
        TvKey.volumeDown => 'KEY_VOLDOWN',
        TvKey.mute => 'KEY_MUTE',
        TvKey.channelUp => 'KEY_CHUP',
        TvKey.channelDown => 'KEY_CHDOWN',
        TvKey.rewind => 'KEY_REWIND',
        TvKey.play => 'KEY_PLAY',
        TvKey.pause => 'KEY_PAUSE',
        TvKey.fastForward => 'KEY_FF',
        TvKey.input => 'KEY_SOURCE',
      };
}

sealed class SamsungInbound {
  const SamsungInbound();
}

/// The TV accepted us. [token] is what to send on later connections.
class SamsungConnected extends SamsungInbound {
  const SamsungConnected(this.token);
  final String? token;
}

class SamsungUnauthorized extends SamsungInbound {
  const SamsungUnauthorized();
}

class SamsungTimeout extends SamsungInbound {
  const SamsungTimeout();
}

SamsungInbound? parseSamsungInbound(String raw) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return null;
  }
  if (decoded is! Map) return null;
  switch (decoded['event']) {
    case 'ms.channel.connect':
      final data = decoded['data'];
      final token = data is Map ? data['token'] : null;
      return SamsungConnected(token?.toString());
    case 'ms.channel.unauthorized':
      return const SamsungUnauthorized();
    case 'ms.channel.timeOut':
      return const SamsungTimeout();
    default:
      return null;
  }
}

/// The TV's MAC from its device-info reply, or null if it can't be found.
///
/// Prefers the reported Wi-Fi MAC (not when the TV is on Ethernet: it would be the
/// wrong interface). Many Samsungs don't report one, but their device id is a UUID
/// whose last 12 hex digits are the TV's MAC, so that is used as a best-effort
/// fallback (it may be the other interface on a TV that has both).
String? macFromSamsungDeviceInfo(Map json) {
  final device = json['device'];
  if (device is! Map) return null;
  if (device['networkType'] != 'wired') {
    final wifi = _validMac(device['wifiMac']);
    if (wifi != null) return wifi;
  }
  for (final id in [device['id'], device['duid'], json['id']]) {
    final fromId = _macFromUuid(id);
    if (fromId != null) return fromId;
  }
  return null;
}

String? _validMac(Object? raw) {
  if (raw is! String) return null;
  try {
    magicPacket(raw); // validates the format
  } on FormatException {
    return null;
  }
  return raw.replaceAll('-', ':').toUpperCase();
}

String? _macFromUuid(Object? id) {
  if (id is! String) return null;
  final m = RegExp(
          r'^(?:uuid:)?[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-([0-9a-f]{12})$',
          caseSensitive: false)
      .firstMatch(id.trim());
  final tail = m?.group(1)?.toLowerCase();
  if (tail == null || tail == '000000000000' || tail == 'ffffffffffff') return null;
  return [for (var i = 0; i < 12; i += 2) tail.substring(i, i + 2)].join(':').toUpperCase();
}
