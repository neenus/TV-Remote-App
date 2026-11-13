import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/core/tv_key.dart';
import 'package:tv_remote/drivers/samsung/samsung_legacy_protocol.dart';

String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

/// A TV reply frame, as samsungctl's _read_response expects it.
List<int> frame(List<int> resp, {String name = 'TV'}) {
  final n = utf8.encode(name);
  return [0x00, n.length & 0xff, n.length >> 8, ...n, resp.length & 0xff, resp.length >> 8, ...resp];
}

void main() {
  group('packets (golden bytes computed with samsungctl\'s serializer)', () {
    test('handshake', () {
      expect(hex(legacyHandshake()),
          '000000340064000c0056465967556d56746233526c140064485974636d56746233526c4c57467763413d3d0c0056465967556d56746233526c');
    });

    test('key_packets', () {
      expect(hex(legacyKeyPacket('KEY_VOLUP')), '00000011000000000c005330565a58315a5054465651');
      expect(hex(legacyKeyPacket('KEY_POWEROFF')),
          '000000150000000010005330565a583142505630565354305a47');
      expect(hex(legacyKeyPacket('KEY_CONTENTS')),
          '000000150000000010005330565a58304e50546c5246546c5254');
    });
  });

  test('oversize_key_names_are_rejected_not_silently_truncated', () {
    expect(() => legacyKeyPacket('K' * 300), throwsArgumentError);
  });

  group('LegacyKeyMap', () {
    test('every_tv_key_is_mapped', () {
      for (final k in TvKey.values) {
        expect(LegacyKeyMap.key(k), isNotNull, reason: '$k unmapped');
      }
    });

    test('older_tvs_use_poweroff_and_smarthub', () {
      expect(LegacyKeyMap.key(TvKey.power), 'KEY_POWEROFF');
      expect(LegacyKeyMap.key(TvKey.home), 'KEY_CONTENTS');
      expect(LegacyKeyMap.key(TvKey.ok), 'KEY_ENTER');
      expect(LegacyKeyMap.key(TvKey.back), 'KEY_RETURN');
      expect(LegacyKeyMap.key(TvKey.volumeUp), 'KEY_VOLUP');
      expect(LegacyKeyMap.key(TvKey.fastForward), 'KEY_FF');
    });
  });

  group('LegacyFrameParser', () {
    List<Type> types(List<LegacyReply> r) => r.map((e) => e.runtimeType).toList();

    test('decodes_each_reply_kind', () {
      final p = LegacyFrameParser();
      expect(types(p.add(frame([0x64, 0, 1, 0]))), [LegacyGranted]);
      expect(types(p.add(frame([0x64, 0, 0, 0]))), [LegacyDenied]);
      expect(types(p.add(frame([0x0a, 0]))), [LegacyWaiting]);
      expect(types(p.add(frame([0x65, 0]))), [LegacyCancelled]);
      expect(types(p.add(frame([0, 0, 0, 0]))), [LegacyAck]);
    });

    test('handles_a_reply_split_into_single_bytes', () {
      final p = LegacyFrameParser();
      final out = <LegacyReply>[];
      for (final b in frame([0x64, 0, 1, 0], name: 'Samsung TV')) {
        out.addAll(p.add([b]));
      }
      expect(types(out), [LegacyGranted]);
    });

    test('handles_two_replies_in_one_chunk_in_order', () {
      final p = LegacyFrameParser();
      final out = p.add([...frame([0x0a, 0]), ...frame([0x64, 0, 1, 0])]);
      expect(types(out), [LegacyWaiting, LegacyGranted]);
    });

    test('unknown_and_empty_replies_are_reported_as_unknown', () {
      final p = LegacyFrameParser();
      final out = p.add(frame([1, 2, 3, 4]));
      expect(types(out), [LegacyUnknown]);
      expect((out.single as LegacyUnknown).raw, [1, 2, 3, 4]);
      expect(types(p.add(frame([]))), [LegacyUnknown]);
    });

    test('oversize_garbage_is_reported_and_the_parser_recovers', () {
      final p = LegacyFrameParser();
      expect(types(p.add([0x00, 0x60, 0xea, 1, 2, 3])), [LegacyUnknown]); // claims 60000-byte name
      expect(types(p.add(frame([0x64, 0, 1, 0]))), [LegacyGranted]);
    });
  });
}
