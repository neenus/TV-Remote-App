import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/core/wake_on_lan.dart';

void main() {
  test('packet_is_102_bytes_with_header_and_16_repeats', () {
    final p = magicPacket('AA:BB:CC:DD:EE:FF');
    expect(p.length, 102);
    expect(p.sublist(0, 6), List.filled(6, 0xFF));
    for (var i = 0; i < 16; i++) {
      expect(p.sublist(6 + i * 6, 12 + i * 6),
          [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]);
    }
  });

  test('accepts_dash_separators', () {
    expect(magicPacket('aa-bb-cc-dd-ee-ff'), magicPacket('AA:BB:CC:DD:EE:FF'));
  });

  test('rejects_invalid_mac', () {
    expect(() => magicPacket('zz'), throwsFormatException);
    expect(() => magicPacket('AA:BB:CC:DD:EE'), throwsFormatException);
    expect(() => magicPacket('AA:BB:CC:DD:EE:GG'), throwsFormatException);
  });
}
