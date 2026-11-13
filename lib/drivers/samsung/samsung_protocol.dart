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

/// The TV's Wi-Fi MAC from its device-info reply, or null if missing/invalid.
String? macFromSamsungDeviceInfo(Map json) {
  final device = json['device'];
  if (device is! Map) return null;
  // wifiMac is the wrong interface for Wake-on-LAN when the TV is on Ethernet.
  if (device['networkType'] == 'wired') return null;
  final mac = device['wifiMac'];
  if (mac is! String) return null;
  try {
    magicPacket(mac); // validates the format
  } on FormatException {
    return null;
  }
  return mac.replaceAll('-', ':').toUpperCase();
}
