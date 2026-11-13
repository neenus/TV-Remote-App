import 'dart:convert';

import '../../core/tv_key.dart';
import '../../core/wake_on_lan.dart';

const _permissions = [
  'CONTROL_POWER',
  'CONTROL_AUDIO',
  'CONTROL_INPUT_TV',
  'CONTROL_INPUT_JOYSTICK',
  'CONTROL_INPUT_MEDIA_PLAYBACK',
  'CONTROL_MOUSE_AND_KEYBOARD',
  'READ_TV_CHANNEL_LIST',
];

String registerMessage({String? clientKey, bool pin = false}) => jsonEncode({
      'type': 'register',
      'id': 'register_0',
      'payload': {
        'forcePairing': false,
        'pairingType': pin ? 'PIN' : 'PROMPT',
        'manifest': {
          'manifestVersion': 1,
          'permissions': _permissions,
        },
        'client-key': ?clientKey,
      },
    });

String requestMessage(String id, String uri, [Map<String, dynamic>? payload]) =>
    jsonEncode({
      'type': 'request',
      'id': id,
      'uri': uri,
      'payload': ?payload,
    });

String setPinMessage(String pin) =>
    requestMessage('pin', 'ssap://pairing/setPin', {'pin': pin});

String pointerButtonFrame(String name) => 'type:button\nname:$name\n\n';

sealed class LgInbound {
  const LgInbound();
}

class Registered extends LgInbound {
  const Registered(this.clientKey);
  final String clientKey;
}

class PairingPrompt extends LgInbound {
  const PairingPrompt();
}

/// The TV is displaying a PIN to be typed into the app.
class PinPrompt extends LgInbound {
  const PinPrompt();
}

class Response extends LgInbound {
  const Response(this.id, this.payload);
  final String id;
  final Map payload;
}

class LgErrorMsg extends LgInbound {
  const LgErrorMsg(this.id, this.error);
  final String id;
  final String error;
}

LgInbound? parseInbound(String raw) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return null;
  }
  if (decoded is! Map) return null;
  final type = decoded['type'];
  final id = decoded['id']?.toString() ?? '';
  final payload = decoded['payload'] is Map ? decoded['payload'] as Map : const {};
  switch (type) {
    case 'registered':
      final key = payload['client-key'];
      return key is String ? Registered(key) : null;
    case 'response':
      if (payload['pairingType'] == 'PROMPT') return const PairingPrompt();
      if (payload['pairingType'] == 'PIN') return const PinPrompt();
      return Response(id, payload);
    case 'error':
      return LgErrorMsg(id, decoded['error']?.toString() ?? 'unknown error');
    default:
      return null;
  }
}

class LgKeyMap {
  static String? uri(TvKey k) => switch (k) {
        TvKey.volumeUp => 'ssap://audio/volumeUp',
        TvKey.volumeDown => 'ssap://audio/volumeDown',
        TvKey.channelUp => 'ssap://tv/channelUp',
        TvKey.channelDown => 'ssap://tv/channelDown',
        TvKey.power => 'ssap://system/turnOff',
        TvKey.play => 'ssap://media.controls/play',
        TvKey.pause => 'ssap://media.controls/pause',
        TvKey.rewind => 'ssap://media.controls/rewind',
        TvKey.fastForward => 'ssap://media.controls/fastForward',
        _ => null,
      };

  static String? pointerName(TvKey k) => switch (k) {
        TvKey.up => 'UP',
        TvKey.down => 'DOWN',
        TvKey.left => 'LEFT',
        TvKey.right => 'RIGHT',
        TvKey.ok => 'ENTER',
        TvKey.back => 'BACK',
        TvKey.home => 'HOME',
        TvKey.menu => 'MENU',
        TvKey.mute => 'MUTE',
        _ => null,
      };
}

const connectionInfoUri = 'ssap://com.webos.service.connectionmanager/getinfo';

/// Picks the TV's MAC from a connection-info reply. The exact reply shape is
/// unverified on real hardware, so this is defensive: it returns null rather
/// than guessing when anything is missing or malformed.
String? macFromConnectionInfo(Map payload, String host) {
  final candidates = <Map>[];
  for (final key in const ['wiredInfo', 'wifiInfo']) {
    final info = payload[key];
    if (info is Map && _normalizeMac(info['macAddress']) != null) {
      candidates.add(info);
    }
  }
  if (candidates.isEmpty) return null;
  final chosen = candidates.firstWhere((i) => i['ipAddress'] == host,
      orElse: () => candidates.firstWhere((i) => i['state'] == 'connected',
          orElse: () => candidates.first));
  return _normalizeMac(chosen['macAddress']);
}

String? _normalizeMac(Object? raw) {
  if (raw is! String) return null;
  try {
    magicPacket(raw); // validates the format
  } on FormatException {
    return null;
  }
  return raw.replaceAll('-', ':').toUpperCase();
}
