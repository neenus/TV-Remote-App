import 'dart:io';
import 'dart:typed_data';

Uint8List magicPacket(String mac) {
  final parts = mac.split(RegExp(r'[:-]'));
  if (parts.length != 6) throw FormatException('Invalid MAC address', mac);
  final bytes = <int>[];
  for (final p in parts) {
    final v = p.length == 2 ? int.tryParse(p, radix: 16) : null;
    if (v == null) throw FormatException('Invalid MAC address', mac);
    bytes.add(v);
  }
  return Uint8List.fromList([
    ...List.filled(6, 0xFF),
    for (var i = 0; i < 16; i++) ...bytes,
  ]);
}

Future<void> sendWakeOnLan(String mac,
    {String broadcast = '255.255.255.255'}) async {
  final packet = magicPacket(mac);
  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  try {
    socket.broadcastEnabled = true;
    socket.send(packet, InternetAddress(broadcast), 9);
  } finally {
    socket.close();
  }
}
