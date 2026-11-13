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

  group('macFromConnectionInfo', () {
    test('prefers_the_interface_whose_ip_matches_the_tv_host', () {
      final mac = macFromConnectionInfo({
        'wiredInfo': {'macAddress': '11:11:11:11:11:11', 'ipAddress': '10.0.0.9'},
        'wifiInfo': {'macAddress': '22:22:22:22:22:22', 'ipAddress': '10.0.0.5'},
      }, '10.0.0.5');
      expect(mac, '22:22:22:22:22:22');
    });

    test('falls_back_to_connected_interface', () {
      final mac = macFromConnectionInfo({
        'wiredInfo': {'macAddress': '11:11:11:11:11:11', 'state': 'disconnected'},
        'wifiInfo': {'macAddress': '22:22:22:22:22:22', 'state': 'connected'},
      }, 'unknown-host');
      expect(mac, '22:22:22:22:22:22');
    });

    test('normalizes_case_and_dashes', () {
      expect(
          macFromConnectionInfo({
            'wifiInfo': {'macAddress': 'aa-bb-cc-dd-ee-ff'}
          }, 'h'),
          'AA:BB:CC:DD:EE:FF');
    });

    test('returns_null_for_missing_or_invalid_data', () {
      expect(macFromConnectionInfo({}, 'h'), isNull);
      expect(macFromConnectionInfo({'wifiInfo': 'oops'}, 'h'), isNull);
      expect(macFromConnectionInfo({'wifiInfo': {'macAddress': 'nope'}}, 'h'), isNull);
      expect(macFromConnectionInfo({'wifiInfo': {'macAddress': 42}}, 'h'), isNull);
    });
  });

  group('pin pairing', () {
    test('register_with_pin_asks_for_PIN_pairing', () {
      final m = jsonDecode(registerMessage(pin: true)) as Map;
      expect((m['payload'] as Map)['pairingType'], 'PIN');
    });

    test('register_default_is_PROMPT', () {
      final m = jsonDecode(registerMessage()) as Map;
      expect((m['payload'] as Map)['pairingType'], 'PROMPT');
    });

    test('set_pin_message_shape', () {
      final m = jsonDecode(setPinMessage('12345678')) as Map;
      expect(m['type'], 'request');
      expect(m['uri'], 'ssap://pairing/setPin');
      expect((m['payload'] as Map)['pin'], '12345678');
    });

    test('parse_pin_pairing_response', () {
      final r = parseInbound(
          '{"type":"response","id":"register_0","payload":{"pairingType":"PIN","returnValue":true}}');
      expect(r, isA<PinPrompt>());
    });
  });

  test('input_opens_the_tvs_input_picker', () {
    expect(LgKeyMap.uri(TvKey.input), 'ssap://system.launcher/launch');
    expect(LgKeyMap.payload(TvKey.input), {'id': 'com.webos.app.inputpicker'});
    expect(LgKeyMap.payload(TvKey.volumeUp), isNull);
  });

  test('register_requests_the_launch_permission', () {
    final m = jsonDecode(registerMessage()) as Map;
    final perms = ((m['payload'] as Map)['manifest'] as Map)['permissions'] as List;
    expect(perms, contains('LAUNCH'));
  });

  test('media_keys_map_to_media_controls_uris', () {
    expect(LgKeyMap.uri(TvKey.play), 'ssap://media.controls/play');
    expect(LgKeyMap.uri(TvKey.pause), 'ssap://media.controls/pause');
    expect(LgKeyMap.uri(TvKey.rewind), 'ssap://media.controls/rewind');
    expect(LgKeyMap.uri(TvKey.fastForward), 'ssap://media.controls/fastForward');
  });

  group('remote keyboard', () {
    test('subscribe_message_shape', () {
      final m = jsonDecode(subscribeMessage('kb', keyboardUri)) as Map;
      expect(m['type'], 'subscribe');
      expect(m['id'], 'kb');
      expect(m['uri'], 'ssap://com.webos.service.ime/registerRemoteKeyboard');
    });

    test('text_messages_use_the_ime_service', () {
      final ins = jsonDecode(insertTextMessage('t1', 'hi')) as Map;
      expect(ins['uri'], 'ssap://com.webos.service.ime/insertText');
      expect((ins['payload'] as Map)['text'], 'hi');
      expect((ins['payload'] as Map)['replace'], 0);
      final del = jsonDecode(deleteCharactersMessage('t2', 3)) as Map;
      expect(del['uri'], 'ssap://com.webos.service.ime/deleteCharacters');
      expect((del['payload'] as Map)['count'], 3);
      final enter = jsonDecode(enterKeyMessage('t3')) as Map;
      expect(enter['uri'], 'ssap://com.webos.service.ime/sendEnterKey');
    });

    test('parse_keyboard_focus_true_and_false', () {
      final on = parseInbound(
          '{"type":"response","id":"kb","payload":{"currentWidget":{"focus":true},"returnValue":true}}');
      expect(on, isA<KeyboardState>());
      expect((on as KeyboardState).focused, isTrue);
      final off = parseInbound(
          '{"type":"response","id":"kb","payload":{"currentWidget":{"focus":false}}}');
      expect((off as KeyboardState).focused, isFalse);
    });

    test('keyboard_reply_without_widget_is_not_a_focus_event', () {
      final r = parseInbound('{"type":"response","id":"kb","payload":{"returnValue":true}}');
      expect(r, isNot(isA<KeyboardState>()));
    });

    test('register_requests_text_input_permission', () {
      final m = jsonDecode(registerMessage()) as Map;
      final perms = ((m['payload'] as Map)['manifest'] as Map)['permissions'] as List;
      expect(perms, contains('CONTROL_INPUT_TEXT'));
    });
  });
}
