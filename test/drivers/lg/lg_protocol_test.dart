import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/core/tv_key.dart';
import 'package:tv_remote/drivers/lg/lg_protocol.dart';

void main() {
  test('register_includes_client_key_when_given', () {
    final m = jsonDecode(registerMessage(clientKey: 'abc')) as Map;
    expect(m['type'], 'register');
    expect(m['id'], 'register_0');
    expect((m['payload'] as Map)['client-key'], 'abc');
    expect((m['payload'] as Map)['pairingType'], 'PROMPT');
  });

  test('register_omits_client_key_when_null', () {
    final m = jsonDecode(registerMessage()) as Map;
    expect((m['payload'] as Map).containsKey('client-key'), isFalse);
  });

  test('pointer_frame_format', () {
    expect(pointerButtonFrame('UP'), 'type:button\nname:UP\n\n');
  });

  test('request_message_shape', () {
    final m = jsonDecode(requestMessage('r1', 'ssap://audio/volumeUp')) as Map;
    expect(m['type'], 'request');
    expect(m['id'], 'r1');
    expect(m['uri'], 'ssap://audio/volumeUp');
  });

  test('parse_registered_returns_client_key', () {
    final r = parseInbound(
        '{"type":"registered","id":"register_0","payload":{"client-key":"abc"}}');
    expect(r, isA<Registered>());
    expect((r as Registered).clientKey, 'abc');
  });

  test('parse_response_with_pairing_prompt', () {
    final r = parseInbound(
        '{"type":"response","id":"register_0","payload":{"pairingType":"PROMPT","returnValue":true}}');
    expect(r, isA<PairingPrompt>());
  });

  test('parse_error_message', () {
    final r = parseInbound(
        '{"type":"error","id":"register_0","error":"403 User denied access"}');
    expect(r, isA<LgErrorMsg>());
    expect((r as LgErrorMsg).error, contains('denied'));
  });

  test('parse_garbage_returns_null', () {
    expect(parseInbound('not json'), isNull);
    expect(parseInbound('[1,2]'), isNull);
  });

  test('register_requests_pointer_socket_permission', () {
    final m = jsonDecode(registerMessage()) as Map;
    final perms = ((m['payload'] as Map)['manifest'] as Map)['permissions'] as List;
    expect(perms, contains('CONTROL_MOUSE_AND_KEYBOARD'));
  });

  test('keymap_covers_every_key', () {
    for (final k in TvKey.values) {
      expect(LgKeyMap.uri(k) != null || LgKeyMap.pointerName(k) != null, isTrue,
          reason: '$k unmapped');
    }
    expect(LgKeyMap.pointerName(TvKey.ok), 'ENTER');
    expect(LgKeyMap.pointerName(TvKey.mute), 'MUTE');
    expect(LgKeyMap.uri(TvKey.volumeUp), 'ssap://audio/volumeUp');
  });
}
