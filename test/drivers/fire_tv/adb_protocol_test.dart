import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/drivers/fire_tv/adb_protocol.dart';

import '../../support/adb_goldens.dart';

Uint8List unhex(String s) => Uint8List.fromList(
    [for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)]);
String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  test('command_codes_match_the_reference', () {
    expect(AdbCommand.cnxn, adbConstants.cnxn);
    expect(AdbCommand.auth, adbConstants.auth);
    expect(AdbCommand.open, adbConstants.open);
    expect(AdbCommand.okay, adbConstants.okay);
    expect(AdbCommand.clse, adbConstants.clse);
    expect(AdbCommand.wrte, adbConstants.wrte);
  });

  group('encoding', () {
    test('packed_messages_match_the_reference', () {
      for (final v in adbMessageVectors) {
        expect(hex(encodeAdbMessage(v.command, v.arg0, v.arg1, unhex(v.data))), v.packed,
            reason: v.name);
      }
    });

    test('shell_open_data_is_nul_terminated', () {
      expect(hex(shellOpenData('input keyevent 24')),
          hex([...'shell:input keyevent 24'.codeUnits, 0]));
    });
  });

  group('parser', () {
    List<AdbMessage> parseAll(AdbFrameParser p, List<int> bytes) => p.add(bytes);

    test('decodes_every_reference_message', () {
      for (final v in adbMessageVectors) {
        final out = parseAll(AdbFrameParser(), unhex(v.packed));
        expect(out, hasLength(1), reason: v.name);
        expect(out.single.command, v.command);
        expect(out.single.arg0, v.arg0);
        expect(out.single.arg1, v.arg1);
        expect(hex(out.single.data), v.data);
      }
    });

    test('handles_single_byte_chunks_and_joined_messages', () {
      final a = unhex(adbMessageVectors[0].packed);
      final b = unhex(adbMessageVectors[2].packed);
      final p = AdbFrameParser();
      final out = <AdbMessage>[];
      for (final byte in [...a, ...b]) {
        out.addAll(p.add([byte]));
      }
      expect(out.map((m) => m.command), [adbMessageVectors[0].command, adbMessageVectors[2].command]);
      final joined = AdbFrameParser().add([...a, ...b]);
      expect(joined, hasLength(2));
    });

    test('bad_magic_is_rejected', () {
      final bad = unhex(adbMessageVectors[3].packed);
      bad[20] ^= 0xff;
      expect(() => AdbFrameParser().add(bad), throwsFormatException);
    });

    test('oversize_payload_is_rejected_without_waiting_for_it', () {
      final header = encodeAdbMessage(AdbCommand.wrte, 1, 1, const []);
      final bd = header.buffer.asByteData();
      bd.setUint32(12, 50 * 1024 * 1024, Endian.little); // claims 50 MB
      expect(() => AdbFrameParser().add(header), throwsFormatException);
    });
  });

  test('the_stls_command_code_is_known', () {
    expect(AdbCommand.stls, 0x534c5453);
  });

  group('shell commands', () {
    test('text_is_split_so_a_percent_never_meets_an_s', () {
      expect(splitForInput('100%sure'), ['100%', 'sure']);
      expect(splitForInput('a%b'), ['a%b']);
      expect(splitForInput('%s%s'), ['%', 's%', 's']);
      expect(splitForInput(''), isEmpty);
    });

    test('keyevent', () => expect(inputKeyeventCommand([24]), 'input keyevent 24'));
    test('several_keyevents', () => expect(inputKeyeventCommand([67, 67]), 'input keyevent 67 67'));

    test('text_is_single_quoted_with_spaces_as_percent_s', () {
      expect(inputTextCommand('hello world'), "input text 'hello%sworld'");
    });

    test('quotes_cannot_break_out_of_the_shell_string', () {
      expect(inputTextCommand("it's"), "input text 'it'\\''s'");
      expect(inputTextCommand("'; reboot; '"), "input text ''\\'';%sreboot;%s'\\'''");
      expect(inputTextCommand(r'$(id) `id` & | > <'), r"input text '$(id)%s`id`%s&%s|%s>%s<'");
    });

    test('control_characters_and_non_ascii_are_dropped', () {
      expect(inputTextCommand('a\nb\tc\u0000d\u007fé€😀'), "input text 'abcd'");
    });

    test('nothing_typeable_gives_no_command', () {
      expect(inputTextCommand(''), isNull);
      expect(inputTextCommand('é€'), isNull);
    });
  });
}
