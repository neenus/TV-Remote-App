import 'dart:convert';

import '../../core/tv_key.dart';

const _permissions = [
  'CONTROL_POWER',
  'CONTROL_AUDIO',
  'CONTROL_INPUT_TV',
  'CONTROL_INPUT_JOYSTICK',
  'CONTROL_INPUT_MEDIA_PLAYBACK',
  'READ_TV_CHANNEL_LIST',
];

String registerMessage({String? clientKey}) => jsonEncode({
      'type': 'register',
      'id': 'register_0',
      'payload': {
        'forcePairing': false,
        'pairingType': 'PROMPT',
        'manifest': {
          'manifestVersion': 1,
          'permissions': _permissions,
        },
        if (clientKey != null) 'client-key': clientKey,
      },
    });

String requestMessage(String id, String uri, [Map<String, dynamic>? payload]) =>
    jsonEncode({
      'type': 'request',
      'id': id,
      'uri': uri,
      if (payload != null) 'payload': payload,
    });

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
        _ => null,
      };
}
