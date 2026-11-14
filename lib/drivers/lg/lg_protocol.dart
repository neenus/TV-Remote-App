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
  'CONTROL_INPUT_TEXT',
  'LAUNCH',
  'READ_NETWORK_STATE', // needed to ask the TV for its MAC address
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

const keyboardUri = 'ssap://com.webos.service.ime/registerRemoteKeyboard';
const _imeBase = 'ssap://com.webos.service.ime';

String subscribeMessage(String id, String uri) =>
    jsonEncode({'type': 'subscribe', 'id': id, 'uri': uri});

String insertTextMessage(String id, String text) =>
    requestMessage(id, '$_imeBase/insertText', {'text': text, 'replace': 0});

String deleteCharactersMessage(String id, int count) =>
    requestMessage(id, '$_imeBase/deleteCharacters', {'count': count});

String enterKeyMessage(String id) => requestMessage(id, '$_imeBase/sendEnterKey');

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

/// The TV focused or unfocused a text field (reply to the keyboard subscription).
class KeyboardState extends LgInbound {
  const KeyboardState(this.focused);
  final bool focused;
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
      if (id == 'kb') {
        final widget = payload['currentWidget'];
        return widget is Map ? KeyboardState(widget['focus'] == true) : null;
      }
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
        TvKey.input => 'ssap://system.launcher/launch',
        _ => null,
      };

  /// Extra request data some keys need (the input key opens the TV's input picker).
  static Map<String, dynamic>? payload(TvKey k) =>
      k == TvKey.input ? const {'id': 'com.webos.app.inputpicker'} : null;

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
/// unverified on real hardware, so this looks anywhere in the reply for a field
/// named like a MAC address (`macAddress`, `wifiMac`, `mac_address`, ...) holding a
/// valid MAC, and prefers the network interface that has the address we are
/// talking to, then one that is connected. It returns null rather than guessing.
String? macFromConnectionInfo(Map payload, String host) {
  final macKey = RegExp(r'mac(_?address)?$', caseSensitive: false);
  final found = <({String mac, String? ip, String? state})>[];

  void walk(Object? node) {
    if (node is Map) {
      for (final entry in node.entries) {
        final key = entry.key;
        final mac = key is String && macKey.hasMatch(key) ? _normalizeMac(entry.value) : null;
        if (mac != null) {
          found.add((
            mac: mac,
            ip: node['ipAddress']?.toString(),
            state: node['state']?.toString(),
          ));
        } else {
          walk(entry.value);
        }
      }
    } else if (node is List) {
      node.forEach(walk);
    }
  }

  walk(payload);
  if (found.isEmpty) return null;
  return found
      .firstWhere((f) => f.ip == host,
          orElse: () => found.firstWhere((f) => f.state == 'connected', orElse: () => found.first))
      .mac;
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
