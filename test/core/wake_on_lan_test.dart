import 'dart:io';

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

  group('where the wake signal is sent', () {
    test('always_includes_the_general_broadcast', () {
      expect(wakeTargets(null), ['255.255.255.255']);
      expect(wakeTargets('not-an-ip'), ['255.255.255.255']);
    });

    test('also_targets_the_tvs_own_network_and_the_tv_itself', () {
      expect(wakeTargets('172.20.0.187'), ['255.255.255.255', '172.20.0.255', '172.20.0.187']);
    });
  });

  group('sending', () {
    test('sends_the_packet_several_times_to_each_target_and_port', () async {
      final listener = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      final received = <List<int>>[];
      listener.listen((e) {
        if (e == RawSocketEvent.read) {
          final d = listener.receive();
          if (d != null) received.add(d.data);
        }
      });
      await sendWakeOnLan('AA:BB:CC:DD:EE:FF',
          targets: ['127.0.0.1'],
          ports: [listener.port],
          repeats: 3,
          gap: const Duration(milliseconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      listener.close();
      expect(received, hasLength(3));
      for (final p in received) {
        expect(p, magicPacket('AA:BB:CC:DD:EE:FF'));
      }
    });

    test('an_unreachable_target_does_not_stop_the_others', () async {
      final listener = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      var count = 0;
      listener.listen((e) {
        if (e == RawSocketEvent.read && listener.receive() != null) count++;
      });
      await sendWakeOnLan('AA:BB:CC:DD:EE:FF',
          targets: ['203.0.113.255', '127.0.0.1'],
          ports: [listener.port],
          repeats: 1,
          gap: Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      listener.close();
      expect(count, greaterThanOrEqualTo(1));
    });

    test('a_bad_mac_is_still_rejected', () async {
      await expectLater(sendWakeOnLan('nope', targets: ['127.0.0.1']), throwsFormatException);
    });
  });
}
